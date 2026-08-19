import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/backup/backup_archive.dart';
import 'package:appflowy/workspace/application/backup/backup_crypto.dart';
import 'package:appflowy/workspace/application/backup/backup_manifest.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:archive/archive_io.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('what a destination needs before it can be used', () {
    test('nothing is ready until somewhere has been chosen', () {
      expect(const BackupDestination().isReady, isFalse);
      expect(const BackupDestination().isSet, isFalse);
    });

    test('a folder needs a path', () {
      const empty = BackupDestination(kind: BackupDestinationKind.folder);
      expect(empty.isReady, isFalse);
      expect(
        empty.copyWith(localPath: r'C:\copies').isReady,
        isTrue,
      );
    });

    test('a service needs an account and a folder in it', () {
      const service = BackupDestination(
        kind: BackupDestinationKind.googleDrive,
        connectionId: 'google|1',
      );
      expect(service.isReady, isFalse);
      expect(service.copyWith(folderId: 'abc').isReady, isTrue);
    });

    test('AppFlowy Cloud needs nothing chosen', () {
      const cloud = BackupDestination(
        kind: BackupDestinationKind.appflowyCloud,
      );
      expect(cloud.isReady, isTrue);
    });

    test('only a service can be asked what is already there', () {
      expect(BackupDestinationKind.googleDrive.canListRemotely, isTrue);
      expect(BackupDestinationKind.folder.canListRemotely, isTrue);
      // Storage behind a link has no listing, and the interface has to say so
      // rather than showing an empty list.
      expect(BackupDestinationKind.appflowyCloud.canListRemotely, isFalse);
    });

    test('each service names the provider that answers for it', () {
      expect(
        BackupDestinationKind.oneDrive.providerService?.name,
        'oneDrive',
      );
      expect(BackupDestinationKind.folder.providerService, isNull);
      expect(BackupDestinationKind.appflowyCloud.providerService, isNull);
    });
  });

  group('compression is answered separately for here and for away', () {
    const remote = BackupDestination(
      kind: BackupDestinationKind.box,
      connectionId: 'box|1',
      folderId: 'folder',
    );

    test('a copy sent away is squeezed by the remote setting', () {
      const policy = BackupPolicy(
        destination: remote,
        localCompression: BackupCompression.maximum,
        remoteCompression: BackupCompression.fast,
      );
      expect(policy.compressionForDestination, BackupCompression.fast);
    });

    test('a copy put in a folder is squeezed by the local setting', () {
      const policy = BackupPolicy(
        destination: BackupDestination(
          kind: BackupDestinationKind.folder,
          localPath: '/copies',
        ),
        localCompression: BackupCompression.maximum,
        remoteCompression: BackupCompression.fast,
      );
      expect(policy.compressionForDestination, BackupCompression.maximum);
    });

    test('two different answers really do mean two archives', () {
      const policy = BackupPolicy(
        destination: remote,
        localCompression: BackupCompression.maximum,
        remoteCompression: BackupCompression.fast,
      );
      expect(policy.needsTwoArchives, isTrue);
      expect(
        policy
            .copyWith(remoteCompression: BackupCompression.maximum)
            .needsTwoArchives,
        isFalse,
      );
      expect(
        policy.copyWith(keepLocalCopy: false).needsTwoArchives,
        isFalse,
      );
    });

    test('a folder destination never gathers twice', () {
      const policy = BackupPolicy(
        destination: BackupDestination(
          kind: BackupDestinationKind.folder,
          localPath: '/copies',
        ),
        localCompression: BackupCompression.none,
        remoteCompression: BackupCompression.fast,
      );
      expect(policy.needsTwoArchives, isFalse);
    });

    test('each level maps to a deflate level', () {
      expect(BackupCompression.none.deflateLevel, 0);
      expect(BackupCompression.none.compresses, isFalse);
      expect(BackupCompression.maximum.deflateLevel, 9);
    });
  });

  group('which parts a folder belongs to', () {
    test('attachments and versions are named, everything else is the workspace',
        () {
      expect(backupPartOfFolder('files'), BackupPart.attachments);
      expect(backupPartOfFolder('images'), BackupPart.attachments);
      expect(backupPartOfFolder('page_versions'), BackupPart.pageVersions);
      // A folder a later version of AppFlowy adds is carried by default rather
      // than silently left out of every copy.
      expect(backupPartOfFolder('something_new'), BackupPart.workspace);
    });

    test('caches are never copied', () {
      expect(backupExcludedFolders, contains('cache_files'));
      expect(backupExcludedFolders, contains('provider_cache'));
    });
  });

  group('how many copies survive', () {
    test('the newest is never swept', () {
      expect(expiredBackupCopies(['c', 'b', 'a'], 0), ['b', 'a']);
      expect(expiredBackupCopies(['a'], 0), isEmpty);
    });

    test('a count keeps that many, newest first', () {
      expect(expiredBackupCopies(['e', 'd', 'c', 'b', 'a'], 2), ['c', 'b', 'a']);
    });

    test('keeping every copy sweeps nothing', () {
      expect(
        expiredBackupCopies(['c', 'b', 'a'], BackupPolicy.keepEveryCopy),
        isEmpty,
      );
    });
  });

  group('when a copy falls due', () {
    final noon = DateTime(2026, 8, 19, 12);
    const ready = BackupPolicy(
      enabled: true,
      schedule: BackupSchedule.daily,
      destination: BackupDestination(
        kind: BackupDestinationKind.folder,
        localPath: '/copies',
      ),
    );

    test('a workspace that has never been copied is due at once', () {
      expect(backupIsDue(policy: ready, now: noon), isTrue);
    });

    test('one taken within the interval is not', () {
      expect(
        backupIsDue(
          policy: ready,
          now: noon,
          lastRunAt: noon.subtract(const Duration(hours: 3)),
        ),
        isFalse,
      );
    });

    test('one taken longer ago than the interval is', () {
      expect(
        backupIsDue(
          policy: ready,
          now: noon,
          lastRunAt: noon.subtract(const Duration(days: 2)),
        ),
        isTrue,
      );
    });

    test('a schedule with no clock never falls due', () {
      expect(
        backupIsDue(
          policy: ready.copyWith(schedule: BackupSchedule.onClose),
          now: noon,
        ),
        isFalse,
      );
      expect(
        backupIsDue(
          policy: ready.copyWith(schedule: BackupSchedule.manual),
          now: noon,
        ),
        isFalse,
      );
    });

    test('a policy that is off, or has nowhere to go, never falls due', () {
      expect(
        backupIsDue(policy: ready.copyWith(enabled: false), now: noon),
        isFalse,
      );
      expect(
        backupIsDue(
          policy: ready.copyWith(destination: const BackupDestination()),
          now: noon,
        ),
        isFalse,
      );
    });

    test('sealing with no passphrase set is not ready', () {
      expect(ready.copyWith(encrypt: true).isReady, isFalse);
      expect(
        ready
            .copyWith(encrypt: true, salt: 'c2FsdA==', verifier: 'af1.a.b')
            .isReady,
        isTrue,
      );
    });
  });

  group('what a policy remembers', () {
    test('it round trips', () {
      const policy = BackupPolicy(
        enabled: true,
        schedule: BackupSchedule.weekly,
        destination: BackupDestination(
          kind: BackupDestinationKind.oneDrive,
          connectionId: 'microsoft|1',
          accountLabel: 'someone@example.com',
          folderId: '01ABC',
          folderName: 'Backups',
        ),
        parts: {BackupPart.workspace, BackupPart.pageVersions},
        localCompression: BackupCompression.none,
        remoteCompression: BackupCompression.fast,
        localCopyPath: '/copies',
        localCopies: 3,
        remoteCopies: BackupPolicy.keepEveryCopy,
        encrypt: true,
        salt: 'c2FsdA==',
        verifier: 'af1.a.b',
        hint: 'the usual',
      );
      final read = BackupPolicy.fromJson(policy.toJson());
      expect(read, policy);
    });

    test('a policy written with no parts falls back rather than copying none',
        () {
      final read = BackupPolicy.fromJson({'parts': <String>[]});
      expect(read.parts, isNotEmpty);
    });

    test('turning sealing off forgets the salt as well as the flag', () {
      const sealed = BackupPolicy(
        encrypt: true,
        salt: 'c2FsdA==',
        verifier: 'af1.a.b',
        hint: 'the usual',
      );
      final open = sealed.withoutPassphrase();
      expect(open.encrypt, isFalse);
      expect(open.salt, isEmpty);
      expect(open.verifier, isEmpty);
      expect(open.hint, isEmpty);
    });
  });

  group('what is written beside a copy', () {
    BackupManifest sample() => BackupManifest(
          id: 'appflowy-20260819-120000',
          createdAt: DateTime.utc(2026, 8, 19, 12),
          parts: const {BackupPart.workspace, BackupPart.attachments},
          compression: BackupCompression.balanced,
          fileCount: 12,
          rawBytes: 4096,
          archiveBytes: 1024,
          omissions: const [
            BackupOmission(
              reason: BackupOmissionReason.tooLarge,
              count: 1,
              bytes: 900,
              names: ['files/holiday.mov'],
            ),
          ],
        );

    test('it round trips through its own text', () {
      final read = BackupManifest.tryParse(sample().encode());
      expect(read, isNotNull);
      expect(read!.id, sample().id);
      expect(read.parts, sample().parts);
      expect(read.createdAt, sample().createdAt);
      expect(read.omissions.single.names, ['files/holiday.mov']);
    });

    test('a sealed copy has nothing beside it that names a file', () {
      final redacted = sample().copyWith(encrypted: true).redacted();
      expect(redacted.omissions.single.count, 1);
      expect(redacted.omissions.single.names, isEmpty);
      expect(redacted.encode(), isNot(contains('holiday')));
    });

    test('anything that is not a manifest is refused, never thrown at', () {
      expect(BackupManifest.tryParse('not json at all'), isNull);
      expect(BackupManifest.tryParse('{"version": 99, "id": "x"}'), isNull);
      expect(BackupManifest.tryParse('[]'), isNull);
    });

    test('a name sorts by the moment it was taken', () {
      final earlier = newBackupId(DateTime.utc(2026, 8, 19, 9));
      final later = newBackupId(DateTime.utc(2026, 8, 19, 11));
      expect(earlier.compareTo(later), lessThan(0));
    });

    test('the archive and its record are named apart', () {
      final manifest = sample();
      expect(manifest.archiveFileName.endsWith(backupArchiveExtension), isTrue);
      expect(
        manifest.manifestFileName.endsWith(backupManifestExtension),
        isTrue,
      );
      expect(
        manifest.manifestFileName.endsWith(backupArchiveExtension),
        isFalse,
      );
    });
  });

  group('sealing a copy', () {
    late Directory workspace;

    setUp(() {
      workspace = Directory.systemTemp.createTempSync('af_backup_seal');
    });

    tearDown(() {
      if (workspace.existsSync()) {
        workspace.deleteSync(recursive: true);
      }
    });

    File write(String name, List<int> bytes) =>
        File(p.join(workspace.path, name))..writeAsBytesSync(bytes);

    test('a passphrase becomes a key that opens its own verifier', () {
      final chosen = newBackupPassphrase(
        passphrase: 'a long enough passphrase',
        verifierPhrase: BackupPolicy.verifierPhrase,
        iterations: 1000,
      );
      final key = unlockBackupKey(
        passphrase: 'a long enough passphrase',
        salt: chosen.salt,
        verifier: chosen.verifier,
        verifierPhrase: BackupPolicy.verifierPhrase,
        iterations: 1000,
      );
      expect(key, isNotNull);
      expect(key!.length, encryptionKeyLength);
    });

    test('a wrong passphrase is refused rather than throwing', () {
      final chosen = newBackupPassphrase(
        passphrase: 'the right one entirely',
        verifierPhrase: BackupPolicy.verifierPhrase,
        iterations: 1000,
      );
      expect(
        unlockBackupKey(
          passphrase: 'the wrong one entirely',
          salt: chosen.salt,
          verifier: chosen.verifier,
          verifierPhrase: BackupPolicy.verifierPhrase,
          iterations: 1000,
        ),
        isNull,
      );
    });

    test('what is sealed comes back exactly', () {
      final key = Uint8List.fromList(List.generate(32, (i) => i));
      // Deliberately more than one chunk, so the chunking itself is exercised.
      final content = Uint8List.fromList(
        List.generate(200 * 1024, (i) => (i * 31) & 0xFF),
      );
      final plain = write('plain.bin', content);
      final sealed = File(p.join(workspace.path, 'sealed.bin'));
      final opened = File(p.join(workspace.path, 'opened.bin'));

      sealBackupFileSync(
        sourcePath: plain.path,
        destinationPath: sealed.path,
        key: key,
        chunkBytes: 64 * 1024,
      );
      openBackupFileSync(
        sourcePath: sealed.path,
        destinationPath: opened.path,
        key: key,
      );

      expect(opened.readAsBytesSync(), content);
      expect(sealed.lengthSync(), greaterThan(content.length));
    });

    test('a sealed copy does not hold its contents in the clear', () {
      final key = Uint8List.fromList(List.filled(32, 7));
      final plain = write('plain.txt', utf8.encode('a memorable sentence'));
      final sealed = File(p.join(workspace.path, 'sealed.bin'));

      sealBackupFileSync(
        sourcePath: plain.path,
        destinationPath: sealed.path,
        key: key,
      );
      expect(
        utf8.decode(sealed.readAsBytesSync(), allowMalformed: true),
        isNot(contains('memorable')),
      );
    });

    test('the wrong key is refused', () {
      final key = Uint8List.fromList(List.filled(32, 1));
      final wrong = Uint8List.fromList(List.filled(32, 2));
      final plain = write('plain.txt', utf8.encode('something'));
      final sealed = File(p.join(workspace.path, 'sealed.bin'));
      sealBackupFileSync(
        sourcePath: plain.path,
        destinationPath: sealed.path,
        key: key,
      );

      expect(
        () => openBackupFileSync(
          sourcePath: sealed.path,
          destinationPath: p.join(workspace.path, 'out.bin'),
          key: wrong,
        ),
        throwsA(
          isA<BackupCipherError>().having(
            (e) => e.reason,
            'reason',
            BackupCipherFailure.wrongKeyOrAltered,
          ),
        ),
      );
    });

    test('a changed byte is refused', () {
      final key = Uint8List.fromList(List.filled(32, 3));
      final plain = write('plain.txt', utf8.encode('something worth keeping'));
      final sealed = File(p.join(workspace.path, 'sealed.bin'));
      sealBackupFileSync(
        sourcePath: plain.path,
        destinationPath: sealed.path,
        key: key,
      );

      final bytes = sealed.readAsBytesSync();
      bytes[bytes.length - 1] ^= 0xFF;
      sealed.writeAsBytesSync(bytes);

      expect(
        () => openBackupFileSync(
          sourcePath: sealed.path,
          destinationPath: p.join(workspace.path, 'out.bin'),
          key: key,
        ),
        throwsA(isA<BackupCipherError>()),
      );
    });

    test('a copy that stops early is refused rather than half restored', () {
      final key = Uint8List.fromList(List.filled(32, 4));
      final content = Uint8List.fromList(
        List.generate(150 * 1024, (i) => i & 0xFF),
      );
      final plain = write('plain.bin', content);
      final sealed = File(p.join(workspace.path, 'sealed.bin'));
      sealBackupFileSync(
        sourcePath: plain.path,
        destinationPath: sealed.path,
        key: key,
        chunkBytes: 64 * 1024,
      );

      final bytes = sealed.readAsBytesSync();
      sealed.writeAsBytesSync(bytes.sublist(0, bytes.length ~/ 2));

      expect(
        () => openBackupFileSync(
          sourcePath: sealed.path,
          destinationPath: p.join(workspace.path, 'out.bin'),
          key: key,
        ),
        throwsA(isA<BackupCipherError>()),
      );
    });

    test('something that was never a backup says so', () {
      final notABackup = write('plain.txt', utf8.encode('just a note'));
      expect(
        () => openBackupFileSync(
          sourcePath: notABackup.path,
          destinationPath: p.join(workspace.path, 'out.bin'),
          key: Uint8List(32),
        ),
        throwsA(
          isA<BackupCipherError>().having(
            (e) => e.reason,
            'reason',
            BackupCipherFailure.notABackup,
          ),
        ),
      );
    });

    test('a sealed copy can be recognised without opening it', () async {
      final key = Uint8List.fromList(List.filled(32, 5));
      final plain = write('plain.txt', utf8.encode('anything'));
      final sealed = File(p.join(workspace.path, 'sealed.bin'));
      sealBackupFileSync(
        sourcePath: plain.path,
        destinationPath: sealed.path,
        key: key,
      );

      expect(await looksLikeSealedBackup(sealed), isTrue);
      expect(await looksLikeSealedBackup(plain), isFalse);
    });

    test('sealing off the interface thread gives back the same bytes',
        () async {
      final key = Uint8List.fromList(List.filled(32, 9));
      final content = Uint8List.fromList(
        List.generate(80 * 1024, (i) => (i * 7) & 0xFF),
      );
      final plain = write('plain.bin', content);
      final sealed = File(p.join(workspace.path, 'sealed.bin'));
      final opened = File(p.join(workspace.path, 'opened.bin'));

      await sealBackupFile(
        source: plain,
        destination: sealed,
        key: key,
        chunkBytes: 32 * 1024,
      );
      await openBackupFile(source: sealed, destination: opened, key: key);

      expect(opened.readAsBytesSync(), content);
    });
  });

  group('gathering a workspace', () {
    late Directory root;
    late Directory data;
    late Directory out;

    setUp(() {
      root = Directory.systemTemp.createTempSync('af_backup_archive');
      data = Directory(p.join(root.path, 'workspace'))
        ..createSync(recursive: true);
      out = Directory(p.join(root.path, 'out'))..createSync(recursive: true);

      void write(String relative, List<int> bytes) {
        final file = File(p.join(data.path, relative));
        file.parent.createSync(recursive: true);
        file.writeAsBytesSync(bytes);
      }

      write(p.join('123', 'collab_db', 'db.dat'), List.filled(4096, 65));
      write('loose.txt', utf8.encode('a note at the root'));
      write(p.join('files', 'photo.bin'), List.filled(8192, 66));
      write(p.join('images', 'cover.bin'), List.filled(2048, 67));
      write(p.join('page_versions', 'v1.json'), utf8.encode('{"a":1}'));
      write(p.join('cache_files', 'junk.bin'), List.filled(65536, 68));
      write(p.join('provider_cache', 'junk.bin'), List.filled(65536, 69));
    });

    tearDown(() {
      if (root.existsSync()) {
        root.deleteSync(recursive: true);
      }
    });

    Future<List<String>> namesIn(File archive) async {
      final input = InputFileStream(archive.path);
      try {
        return [
          for (final file in ZipDecoder().decodeBuffer(input).files)
            if (file.isFile) file.name,
        ];
      } finally {
        input.closeSync();
      }
    }

    test('only the chosen parts are gathered, and never a cache', () async {
      final archive = File(p.join(out.path, 'a.zip'));
      final result = await writeBackupArchive(
        dataPath: data.path,
        destination: archive,
        parts: const {BackupPart.workspace},
        compression: BackupCompression.fast,
      );

      final names = await namesIn(archive);
      expect(names, contains('workspace/123/collab_db/db.dat'));
      expect(names, contains('workspace/loose.txt'));
      expect(names.where((name) => name.contains('files/')), isEmpty);
      expect(names.where((name) => name.contains('page_versions')), isEmpty);
      expect(names.where((name) => name.contains('cache')), isEmpty);
      expect(result.fileCount, names.length);
    });

    test('attachments cover pictures as well as files', () async {
      final archive = File(p.join(out.path, 'b.zip'));
      await writeBackupArchive(
        dataPath: data.path,
        destination: archive,
        parts: const {BackupPart.attachments},
        compression: BackupCompression.fast,
      );

      final names = await namesIn(archive);
      expect(names, contains('workspace/files/photo.bin'));
      expect(names, contains('workspace/images/cover.bin'));
      expect(names, hasLength(2));
    });

    test('a file over the ceiling is left out and named', () async {
      final archive = File(p.join(out.path, 'c.zip'));
      final result = await writeBackupArchive(
        dataPath: data.path,
        destination: archive,
        parts: const {BackupPart.attachments},
        compression: BackupCompression.fast,
        maximumFileBytes: 4096,
      );

      final names = await namesIn(archive);
      expect(names, isNot(contains('workspace/files/photo.bin')));
      expect(result.omissions, hasLength(1));
      expect(result.omissions.single.reason, BackupOmissionReason.tooLarge);
      expect(result.omissions.single.names, ['files/photo.bin']);
    });

    test('squeezing harder really does produce a smaller file', () async {
      final stored = File(p.join(out.path, 'stored.zip'));
      final squeezed = File(p.join(out.path, 'squeezed.zip'));

      final none = await writeBackupArchive(
        dataPath: data.path,
        destination: stored,
        parts: const {BackupPart.workspace, BackupPart.attachments},
        compression: BackupCompression.none,
      );
      final maximum = await writeBackupArchive(
        dataPath: data.path,
        destination: squeezed,
        parts: const {BackupPart.workspace, BackupPart.attachments},
        compression: BackupCompression.maximum,
      );

      expect(maximum.archiveBytes, lessThan(none.archiveBytes));
      expect(maximum.rawBytes, none.rawBytes);
    });

    test('what was gathered comes back the same', () async {
      final archive = File(p.join(out.path, 'd.zip'));
      await writeBackupArchive(
        dataPath: data.path,
        destination: archive,
        parts: const {BackupPart.workspace, BackupPart.attachments},
        compression: BackupCompression.balanced,
      );

      final restored = Directory(p.join(root.path, 'restored'));
      final files = await extractBackupArchive(
        source: archive,
        target: restored,
      );

      expect(files, greaterThan(0));
      expect(
        File(p.join(restored.path, 'workspace', 'loose.txt')).readAsStringSync(),
        'a note at the root',
      );
      expect(
        File(
          p.join(restored.path, 'workspace', 'files', 'photo.bin'),
        ).lengthSync(),
        8192,
      );
    });

    test('the listing says which parts an archive holds', () async {
      final archive = File(p.join(out.path, 'e.zip'));
      await writeBackupArchive(
        dataPath: data.path,
        destination: archive,
        parts: const {BackupPart.workspace, BackupPart.pageVersions},
        compression: BackupCompression.fast,
      );

      final parts = await readBackupArchiveParts(archive);
      expect(parts, contains(BackupPart.workspace));
      expect(parts, contains(BackupPart.pageVersions));
      expect(parts, isNot(contains(BackupPart.attachments)));
    });

    test('a name that tries to climb out of the folder is not written',
        () async {
      // An archive is somebody else's data, and a name inside one can say `..`.
      final escaping = Archive()
        ..addFile(
          ArchiveFile(
            '../escaped.txt',
            5,
            Uint8List.fromList(utf8.encode('oops!')),
          ),
        )
        ..addFile(
          ArchiveFile(
            'workspace/kept.txt',
            4,
            Uint8List.fromList(utf8.encode('fine')),
          ),
        );
      final archive = File(p.join(out.path, 'evil.zip'))
        ..writeAsBytesSync(ZipEncoder().encode(escaping)!);

      final restored = Directory(p.join(root.path, 'guarded'));
      await extractBackupArchive(source: archive, target: restored);

      expect(File(p.join(root.path, 'escaped.txt')).existsSync(), isFalse);
      expect(
        File(p.join(restored.path, 'workspace', 'kept.txt')).existsSync(),
        isTrue,
      );
    });
  });

  group('a folder full of copies', () {
    late Directory folder;

    setUp(() {
      folder = Directory.systemTemp.createTempSync('af_backup_folder');
    });

    tearDown(() {
      if (folder.existsSync()) {
        folder.deleteSync(recursive: true);
      }
    });

    test('a copy is put there, listed, fetched back and removed', () async {
      final target = LocalFolderBackupTarget(folder);
      final source = Directory.systemTemp.createTempSync('af_backup_src');
      addTearDown(() => source.deleteSync(recursive: true));

      final archive = File(p.join(source.path, 'a.zip'))
        ..writeAsBytesSync(List.filled(512, 42));
      final manifest = BackupManifest(
        id: newBackupId(DateTime.utc(2026, 8, 19, 12)),
        createdAt: DateTime.utc(2026, 8, 19, 12),
        parts: const {BackupPart.workspace},
        compression: BackupCompression.balanced,
        fileCount: 3,
        rawBytes: 900,
        archiveBytes: 512,
      );

      final stored = await target.put(archive: archive, manifest: manifest);
      expect(File(stored.locator).existsSync(), isTrue);
      expect(File(stored.manifestLocator).existsSync(), isTrue);

      final copies = await target.list();
      expect(copies, hasLength(1));
      expect(copies.single.id, manifest.id);
      expect(copies.single.manifest?.fileCount, 3);

      final fetched = File(p.join(source.path, 'back.zip'));
      await target.fetch(copies.single, fetched);
      expect(fetched.lengthSync(), 512);

      await target.remove(copies.single);
      expect(await target.list(), isEmpty);
    });

    test('a copy remembers itself in words that survive a restart', () {
      final copy = BackupCopy(
        id: 'appflowy-20260819-120000',
        locator: 'https://example.com/a',
        manifestLocator: 'https://example.com/b',
        bytes: 4096,
        storedAt: DateTime.fromMillisecondsSinceEpoch(1600000000000),
      );
      final read = BackupCopy.fromJson(copy.toJson());
      expect(read, isNotNull);
      expect(read!.id, copy.id);
      expect(read.locator, copy.locator);
      expect(read.bytes, copy.bytes);
      expect(read.storedAt, copy.storedAt);
    });

    test('anything that is not a remembered copy is refused', () {
      expect(BackupCopy.fromJson(null), isNull);
      expect(BackupCopy.fromJson(<String, Object?>{'id': ''}), isNull);
    });
  });

  group('the list kept beside the copies', () {
    BackupCopy copy(String id, DateTime at) => BackupCopy(
          id: id,
          locator: 'https://example.com/$id',
          bytes: 1024,
          storedAt: at,
        );

    test('the published list leads and what is only known here is added', () {
      final published = [
        copy('b', DateTime.utc(2026, 8, 18)),
        copy('a', DateTime.utc(2026, 8, 17)),
      ];
      final known = [
        copy('c', DateTime.utc(2026, 8, 19)),
        copy('a', DateTime.utc(2026, 8, 17)),
      ];

      final merged = mergeBackupCopies(published, known);
      expect(merged.map((c) => c.id), ['c', 'b', 'a']);
    });

    test('a copy named twice is only listed once', () {
      final one = copy('a', DateTime.utc(2026, 8, 17));
      expect(mergeBackupCopies([one], [one]), hasLength(1));
    });

    test('the published entry wins when the two disagree', () {
      final published = BackupCopy(
        id: 'a',
        locator: 'https://example.com/current',
        storedAt: DateTime.utc(2026, 8, 17),
      );
      final stale = BackupCopy(
        id: 'a',
        locator: 'https://example.com/stale',
        storedAt: DateTime.utc(2026, 8, 17),
      );
      expect(
        mergeBackupCopies([published], [stale]).single.locator,
        'https://example.com/current',
      );
    });

    test('an empty list on either side is harmless', () {
      final only = copy('a', DateTime.utc(2026, 8, 17));
      expect(mergeBackupCopies(const [], [only]).single.id, 'a');
      expect(mergeBackupCopies([only], const []).single.id, 'a');
      expect(mergeBackupCopies(const [], const []), isEmpty);
    });

    test('the index is named at a fixed address, not by its contents', () {
      // ⚠️ A content-addressed name would move every time the list changed,
      // and nothing on a fresh machine could find it.
      expect(AppFlowyCloudBackupTarget.indexObjectName, isNotEmpty);
      expect(
        AppFlowyCloudBackupTarget.indexObjectName,
        isNot(contains(AppFlowyCloudBackupTarget.parentDirectory)),
      );
    });
  });

  test('a size is written the way somebody reads one', () {
    expect(backupSizeLabel(512), '512 B');
    expect(backupSizeLabel(2048), '2 KB');
    expect(backupSizeLabel(5 * 1024 * 1024), '5.0 MB');
    expect(backupSizeLabel(3 * 1024 * 1024 * 1024), '3.0 GB');
  });
}
