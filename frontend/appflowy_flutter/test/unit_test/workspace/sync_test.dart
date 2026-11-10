import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/workspace_file_path.dart';
import 'package:appflowy/workspace/application/app_password/app_password.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/sync/sync_files.dart';
import 'package:appflowy/workspace/application/sync/sync_pack.dart';
import 'package:appflowy/workspace/application/sync/sync_preferences.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:appflowy/workspace/application/sync/sync_settings.dart';
import 'package:appflowy/workspace/application/sync/sync_vault.dart';
import 'package:appflowy/workspace/application/sync/workspace_bundle_bridge.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

const _passphrase = 'correct horse battery staple';

void main() {
  group('names in a sync folder', () {
    test('every kind of file reads back as what it was written as', () {
      const epoch = '20261106T081500-abc123';
      const device = 'device000001';
      final base = SyncFileName.parse(SyncFileName.base(epoch))!;
      expect(base.kind, SyncFileKind.base);
      expect(base.epoch, epoch);

      final changes = SyncFileName.parse(
        SyncFileName.changes(epoch, device, 42),
      )!;
      expect(changes.kind, SyncFileKind.changes);
      expect(changes.device, device);
      expect(changes.seq, 42);

      expect(
        SyncFileName.parse(SyncFileName.checkpointInfo(epoch, device, 7))!.kind,
        SyncFileKind.checkpointInfo,
      );
      expect(
        SyncFileName.parse(SyncFileName.deviceInfo(epoch, device))!.kind,
        SyncFileKind.deviceInfo,
      );
      final vault = SyncFileName.parse(SyncFileName.vault(epoch))!;
      expect(vault.kind, SyncFileKind.vault);
      expect(vault.epoch, epoch);
      expect(SyncFileName.parse(SyncFileName.legacyVault), isNull);
      final hash = 'a' * 64;
      expect(SyncFileName.parse(SyncFileName.blob(hash))!.hash, hash);
    });

    test('anything else is ignored, never misread', () {
      for (final name in [
        'notes.txt',
        'appflowy-20261106-075718.afbackup',
        'afsync1_bad_base.pack',
        'afsync1_20261106T081500-abc123_chg_UPPER_00000001.pack',
        'afsync1_20261106T081500-abc123_chg_device000001_1.pack',
        'afsync1_20261106T081500-abc123_chg_device000001_00000000.pack',
        'afsync1_blob_nothex',
      ]) {
        expect(SyncFileName.parse(name), isNull, reason: name);
      }
    });

    test('epochs sort the way time does', () {
      final earlier = newSyncEpoch(DateTime.utc(2026, 1, 2, 3, 4, 5));
      final later = newSyncEpoch(DateTime.utc(2026, 1, 2, 3, 4, 6));
      expect(earlier.compareTo(later), lessThan(0));
      expect(SyncFileName.parse(SyncFileName.base(earlier)), isNotNull);
    });

    test('an epoch replacing another always sorts after it', () {
      final at = DateTime.utc(2026, 1, 2, 3, 4, 5);
      for (final previous in [
        newSyncEpoch(at),
        // Started on a computer whose clock is ahead.
        newSyncEpoch(at.add(const Duration(hours: 2))),
        '20261231T235959-zzzzzz',
      ]) {
        final next = nextSyncEpoch(previous, at);
        expect(next.compareTo(previous), greaterThan(0), reason: previous);
        expect(SyncFileName.parse(SyncFileName.base(next)), isNotNull);
      }
      expect(
        nextSyncEpoch('20260101T000000-aaaaaa', at).startsWith('20260102T'),
        isTrue,
      );
    });
  });

  group('reading a folder', () {
    RemoteSyncFile file(String name, [int minute = 0]) => RemoteSyncFile(
          name: name,
          id: name,
          modifiedAt: DateTime.utc(2026, 1, 1, 0, minute),
        );

    test('the current epoch is the newest one that was really started', () {
      const old = '20260101T000000-aaaaaa';
      const started = '20260102T000000-bbbbbb';
      const unfinished = '20260103T000000-cccccc';
      final listing = SyncListing.of([
        file(SyncFileName.base(old)),
        file(SyncFileName.baseInfo(old)),
        file(SyncFileName.base(started)),
        file(SyncFileName.baseInfo(started)),
        // A base whose record never arrived is an upload still going on.
        file(SyncFileName.base(unfinished)),
        file('Somebody else.docx'),
      ]);
      expect(listing.current!.id, started);
      expect(listing.others.single.name, 'Somebody else.docx');
    });

    test('changes are listed per computer, in order', () {
      const epoch = '20260101T000000-aaaaaa';
      final listing = SyncListing.of([
        file(SyncFileName.changes(epoch, 'deviceaaaaaa', 2)),
        file(SyncFileName.changes(epoch, 'deviceaaaaaa', 1)),
        file(SyncFileName.changes(epoch, 'devicebbbbbb', 1)),
      ]);
      final changes = listing.epochs[epoch]!.changes;
      expect(changes['deviceaaaaaa']!.keys, [1, 2]);
      expect(listing.epochs[epoch]!.lastSeqOf('deviceaaaaaa'), 2);
      expect(listing.epochs[epoch]!.lastSeqOf('nobody000000'), 0);
    });
  });

  group('what a computer pulls', () {
    const epoch = '20260101T000000-aaaaaa';
    const me = 'deviceme0000';
    const other = 'deviceother0';

    RemoteSyncFile file(String name) => RemoteSyncFile(name: name, id: name);

    test('everything not merged yet, in order, and nothing twice', () {
      final listing = SyncListing.of([
        for (final seq in [1, 2, 3])
          file(SyncFileName.changes(epoch, other, seq)),
        file(SyncFileName.changes(epoch, me, 1)),
      ]);
      final plan = planSyncPull(
        epoch: listing.epochs[epoch]!,
        applied: const {other: 1, me: 1},
        checkpointInfos: const {},
      );
      expect(plan.checkpoints, isEmpty);
      expect([for (final change in plan.changes) change.seq], [2, 3]);
    });

    test('its own changes come back when it joined without them', () {
      // Sent by this computer before it last joined, from a checkpoint that
      // holds only the first of them.
      final checkpoint = SyncFileName.checkpoint(epoch, other, 4);
      final listing = SyncListing.of([
        file(checkpoint),
        file(SyncFileName.checkpointInfo(epoch, other, 4)),
        for (final seq in [2, 3]) file(SyncFileName.changes(epoch, me, seq)),
      ]);
      final plan = planSyncPull(
        epoch: listing.epochs[epoch]!,
        applied: const {other: 4, me: 1},
        checkpointInfos: {
          checkpoint: SyncCheckpointInfo(
            covers: const {other: 4, me: 1},
            createdAt: DateTime.utc(2026),
            device: other,
          ),
        },
      );
      expect(plan.checkpoints, isEmpty);
      expect(
        [for (final change in plan.changes) '${change.device}:${change.seq}'],
        ['$me:2', '$me:3'],
      );
    });

    test('a gap is filled from the newest checkpoint first', () {
      final checkpoint = SyncFileName.checkpoint(epoch, other, 5);
      final listing = SyncListing.of([
        file(checkpoint),
        file(SyncFileName.checkpointInfo(epoch, other, 5)),
        for (final seq in [6, 7]) file(SyncFileName.changes(epoch, other, seq)),
      ]);
      final plan = planSyncPull(
        epoch: listing.epochs[epoch]!,
        applied: const {other: 2},
        checkpointInfos: {
          checkpoint: SyncCheckpointInfo(
            covers: const {other: 5},
            createdAt: DateTime.utc(2026),
            device: other,
          ),
        },
      );
      expect(plan.checkpoints.single.checkpoint.pack.name, checkpoint);
      expect([for (final change in plan.changes) change.seq], [6, 7]);
      expect(plan.unreachable, isEmpty);
    });

    test('changes tidied away entirely are still noticed', () {
      final checkpoint = SyncFileName.checkpoint(epoch, other, 9);
      final listing = SyncListing.of([
        file(checkpoint),
        file(SyncFileName.checkpointInfo(epoch, other, 9)),
      ]);
      final plan = planSyncPull(
        epoch: listing.epochs[epoch]!,
        applied: const {other: 4},
        checkpointInfos: {
          checkpoint: SyncCheckpointInfo(
            covers: const {other: 9},
            createdAt: DateTime.utc(2026),
            device: other,
          ),
        },
      );
      expect(plan.checkpoints, hasLength(1));
      expect(plan.changes, isEmpty);
    });

    test('checkpoints written at the same time are merged together', () {
      // Each computer tidied away what its own checkpoint holds, so neither
      // checkpoint alone fills both gaps.
      const third = 'devicethird0';
      final mine = SyncFileName.checkpoint(epoch, other, 10);
      final theirs = SyncFileName.checkpoint(epoch, third, 12);
      final listing = SyncListing.of([
        file(mine),
        file(SyncFileName.checkpointInfo(epoch, other, 10)),
        file(theirs),
        file(SyncFileName.checkpointInfo(epoch, third, 12)),
        for (final seq in [11, 12])
          file(SyncFileName.changes(epoch, other, seq)),
        file(SyncFileName.changes(epoch, third, 13)),
      ]);
      SyncCheckpointInfo covering(Map<String, int> covers, String device) =>
          SyncCheckpointInfo(
            covers: covers,
            createdAt: DateTime.utc(2026),
            device: device,
          );
      final plan = planSyncPull(
        epoch: listing.epochs[epoch]!,
        applied: const {other: 3, third: 3},
        checkpointInfos: {
          mine: covering(const {other: 10, third: 5}, other),
          theirs: covering(const {other: 8, third: 12}, third),
        },
      );
      expect(
        {for (final planned in plan.checkpoints) planned.checkpoint.pack.name},
        {mine, theirs},
      );
      expect(
        [for (final change in plan.changes) '${change.device}:${change.seq}'],
        ['$other:11', '$other:12', '$third:13'],
      );
      expect(plan.unreachable, isEmpty);
    });

    test('a checkpoint holding nothing new is not fetched', () {
      final newer = SyncFileName.checkpoint(epoch, other, 9);
      final older = SyncFileName.checkpoint(epoch, other, 4);
      final listing = SyncListing.of([
        file(older),
        file(SyncFileName.checkpointInfo(epoch, other, 4)),
        file(newer),
        file(SyncFileName.checkpointInfo(epoch, other, 9)),
      ]);
      final plan = planSyncPull(
        epoch: listing.epochs[epoch]!,
        applied: const {other: 1},
        checkpointInfos: {
          for (final (name, seq) in [(older, 4), (newer, 9)])
            name: SyncCheckpointInfo(
              covers: {other: seq},
              createdAt: DateTime.utc(2026),
              device: other,
            ),
        },
      );
      expect(plan.checkpoints.single.checkpoint.pack.name, newer);
    });

    test('changes nothing in the folder holds any more are reported', () {
      final listing = SyncListing.of([
        for (final seq in [5, 6]) file(SyncFileName.changes(epoch, other, seq)),
      ]);
      final plan = planSyncPull(
        epoch: listing.epochs[epoch]!,
        applied: const {other: 2},
        checkpointInfos: const {},
      );
      expect(plan.changes, isEmpty);
      expect(plan.unreachable, {other});
    });

    test('a computer that is up to date fetches nothing', () {
      final listing = SyncListing.of([
        file(SyncFileName.changes(epoch, other, 1)),
      ]);
      expect(
        planSyncPull(
          epoch: listing.epochs[epoch]!,
          applied: const {other: 1},
          checkpointInfos: const {},
        ).isEmpty,
        isTrue,
      );
    });
  });

  group('tidying', () {
    const epoch = '20260201T000000-bbbbbb';
    const older = '20260101T000000-aaaaaa';
    const device = 'deviceaaaaaa';

    RemoteSyncFile file(String name, DateTime at) =>
        RemoteSyncFile(name: name, id: name, modifiedAt: at);

    test('covered changes go, uncovered ones stay', () {
      final at = DateTime.utc(2026, 2);
      final listing = SyncListing.of([
        file(SyncFileName.base(epoch), at),
        file(SyncFileName.baseInfo(epoch), at),
        for (final seq in [1, 2, 3])
          file(SyncFileName.changes(epoch, device, seq), at),
      ]);
      final doomed = syncFilesToTidy(
        listing: listing,
        epoch: listing.epochs[epoch]!,
        newest: SyncCheckpointInfo(
          covers: const {device: 2},
          createdAt: at,
          device: device,
        ),
        checkpointInfos: const {},
        now: at,
      ).map((file) => file.name);
      expect(doomed, [
        SyncFileName.changes(epoch, device, 1),
        SyncFileName.changes(epoch, device, 2),
      ]);
    });

    test('a replaced epoch is only removed once nobody can still be on it', () {
      final started = DateTime.utc(2026, 2);
      final listing = SyncListing.of([
        file(SyncFileName.base(older), DateTime.utc(2026)),
        file(SyncFileName.baseInfo(older), DateTime.utc(2026)),
        file(SyncFileName.base(epoch), started),
        file(SyncFileName.baseInfo(epoch), started),
      ]);
      List<String> tidied(DateTime now) => syncFilesToTidy(
            listing: listing,
            epoch: listing.epochs[epoch]!,
            newest: SyncCheckpointInfo(
              covers: const {},
              createdAt: now,
              device: device,
            ),
            checkpointInfos: const {},
            now: now,
          ).map((file) => file.name).toList();
      expect(tidied(started.add(const Duration(days: 1))), isEmpty);
      expect(
        tidied(started.add(const Duration(days: 8))),
        containsAll([SyncFileName.base(older), SyncFileName.baseInfo(older)]),
      );
    });

    test('an old checkpoint stays while no newer one holds all it does', () {
      const second = 'devicebbbbbb';
      final at = DateTime.utc(2026, 2);
      // Oldest first: one a newer one holds, one nothing newer holds, one
      // whose record never arrived, and the newest two.
      final checkpoints = [
        (device, 1, {device: 3, second: 2}),
        (second, 2, {device: 2, second: 9}),
        (device, 3, null),
        (device, 4, {device: 8, second: 4}),
        (second, 5, {device: 8, second: 5}),
      ];
      final listing = SyncListing.of([
        file(SyncFileName.base(epoch), at),
        file(SyncFileName.baseInfo(epoch), at),
        for (final (index, (owner, seq, covers)) in checkpoints.indexed) ...[
          file(
            SyncFileName.checkpoint(epoch, owner, seq),
            at.add(Duration(minutes: index)),
          ),
          if (covers != null)
            file(
              SyncFileName.checkpointInfo(epoch, owner, seq),
              at.add(Duration(minutes: index)),
            ),
        ],
      ]);
      final infos = {
        for (final (owner, seq, covers) in checkpoints)
          if (covers != null)
            SyncFileName.checkpoint(epoch, owner, seq): SyncCheckpointInfo(
              covers: covers,
              createdAt: at,
              device: owner,
            ),
      };
      final doomed = syncFilesToTidy(
        listing: listing,
        epoch: listing.epochs[epoch]!,
        newest: infos[SyncFileName.checkpoint(epoch, second, 5)]!,
        checkpointInfos: infos,
        now: at,
      ).map((file) => file.name).toSet();
      expect(doomed, {
        SyncFileName.checkpoint(epoch, device, 1),
        SyncFileName.checkpointInfo(epoch, device, 1),
        SyncFileName.checkpoint(epoch, device, 3),
      });
    });
  });

  group('attached files', () {
    test('only plain paths inside synced folders may be written', () {
      expect(isSafeSyncPath('images/a.png'), isTrue);
      expect(isSafeSyncPath('page_versions/x/index.json'), isTrue);
      for (final path in [
        '',
        'a.png',
        '/etc/passwd',
        'images/../../etc/passwd',
        'images\\a.png',
        'cache_files/a',
        'shortcuts/shortcuts.json',
        'images/C:evil',
      ]) {
        expect(isSafeSyncPath(path), isFalse, reason: path);
      }
    });

    late Directory root;
    setUp(
      () async => root = await Directory.systemTemp.createTemp('sync_files'),
    );
    tearDown(() async => root.delete(recursive: true));

    test('a scan sees new, changed and removed files, and nothing else',
        () async {
      final image = File(p.join(root.path, 'images', 'a.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      File(p.join(root.path, 'image_cache', 'x.jpg'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([9]);
      File(p.join(root.path, 'images', '.a.png.part')).writeAsBytesSync([7]);

      final index = SyncFileIndex();
      var scan = await scanSyncedFiles(dataPath: root.path, index: index);
      expect(scan.changed.map((file) => file.path), ['images/a.png']);
      index.entries
        ..clear()
        ..addAll(scan.current);

      scan = await scanSyncedFiles(dataPath: root.path, index: index);
      expect(scan.isEmpty, isTrue);

      image.deleteSync();
      scan = await scanSyncedFiles(dataPath: root.path, index: index);
      expect(scan.deleted.map((file) => file.path), ['images/a.png']);
    });

    test('a newer file here is kept; an unchanged one is replaced', () async {
      final local = File(p.join(root.path, 'files', 'notes.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('mine');
      final blobs = <String, List<int>>{};
      Future<SyncFileRecord> remote(String text, DateTime at) async {
        final bytes = utf8.encode(text);
        final temp = File(p.join(root.path, 'blob'))..writeAsBytesSync(bytes);
        final hash = await hashFile(temp);
        blobs[hash] = bytes;
        return SyncFileRecord(
          path: 'files/notes.txt',
          hash: hash,
          bytes: bytes.length,
          modified: at.millisecondsSinceEpoch,
        );
      }

      Future<bool> fetch(String hash, File destination) async {
        final bytes = blobs[hash];
        if (bytes == null) {
          return false;
        }
        await destination.writeAsBytes(bytes);
        return true;
      }

      // Changed here, after the other computer's version: this one stays.
      final index = SyncFileIndex();
      final older = await remote(
        'theirs',
        DateTime.now().subtract(const Duration(days: 1)),
      );
      var result = await applyRemoteFiles(
        dataPath: root.path,
        index: index,
        files: [older],
        deleted: const [],
        fetch: fetch,
      );
      expect(result.kept, 1);
      expect(local.readAsStringSync(), 'mine');

      // Unchanged since it was last synced: the other computer's wins.
      final scan = await scanSyncedFiles(dataPath: root.path, index: index);
      index.entries.addAll(scan.current);
      final newer = await remote(
        'theirs, later',
        DateTime.now().add(const Duration(minutes: 1)),
      );
      result = await applyRemoteFiles(
        dataPath: root.path,
        index: index,
        files: [newer],
        deleted: const [],
        fetch: fetch,
      );
      expect(result.written, 1);
      expect(local.readAsStringSync(), 'theirs, later');

      // An older version arriving late changes nothing.
      result = await applyRemoteFiles(
        dataPath: root.path,
        index: index,
        files: [older],
        deleted: const [],
        fetch: fetch,
      );
      expect(result.written, 0);
      expect(local.readAsStringSync(), 'theirs, later');

      // A removal made before the version here leaves it alone.
      result = await applyRemoteFiles(
        dataPath: root.path,
        index: index,
        files: const [],
        deleted: [
          SyncFileRecord(
            path: 'files/notes.txt',
            modified: DateTime.now().millisecondsSinceEpoch,
          ),
        ],
        fetch: fetch,
      );
      expect(result.removed, 0);
      expect(local.existsSync(), isTrue);

      // A removal elsewhere after it removes it here too, as nothing changed
      // here since.
      final removedAt = DateTime.now().add(const Duration(minutes: 2));
      result = await applyRemoteFiles(
        dataPath: root.path,
        index: index,
        files: const [],
        deleted: [
          SyncFileRecord(
            path: 'files/notes.txt',
            modified: removedAt.millisecondsSinceEpoch,
          ),
        ],
        fetch: fetch,
      );
      expect(result.removed, 1);
      expect(local.existsSync(), isFalse);

      // A version from before the removal does not bring it back, even after
      // the record is read again; a later one does.
      final indexFile = File(p.join(root.path, 'index.json'));
      await index.save(indexFile);
      final reread = await SyncFileIndex.load(indexFile);
      result = await applyRemoteFiles(
        dataPath: root.path,
        index: reread,
        files: [newer],
        deleted: const [],
        fetch: fetch,
      );
      expect(result.written, 0);
      expect(local.existsSync(), isFalse);
      final revived = await remote(
        'theirs, revived',
        removedAt.add(const Duration(minutes: 1)),
      );
      result = await applyRemoteFiles(
        dataPath: root.path,
        index: reread,
        files: [revived],
        deleted: const [],
        fetch: fetch,
      );
      expect(result.written, 1);
      expect(local.readAsStringSync(), 'theirs, revived');
      expect(reread.removed, isEmpty);
    });

    test('every computer settles on the same version, in any order', () async {
      final blobs = <String, List<int>>{};
      Future<SyncFileRecord> version(String text, int minute) async {
        final bytes = utf8.encode(text);
        final temp = File(p.join(root.path, 'blob'))..writeAsBytesSync(bytes);
        final hash = await hashFile(temp);
        blobs[hash] = bytes;
        return SyncFileRecord(
          path: 'workflows/flow.json',
          hash: hash,
          bytes: bytes.length,
          modified: DateTime.utc(2026, 1, 1, 0, minute).millisecondsSinceEpoch,
        );
      }

      final first = await version('first', 1);
      final second = await version('second', 2);
      final removal = SyncFileRecord(
        path: 'workflows/flow.json',
        modified: DateTime.utc(2026, 1, 1, 0, 3).millisecondsSinceEpoch,
      );
      final last = await version('last', 4);
      final orders = [
        [first, second, removal, last],
        [last, removal, second, first],
        [second, last, first, removal],
        [removal, first, last, second],
      ];
      for (final (i, order) in orders.indexed) {
        final dataPath = p.join(root.path, 'computer$i');
        final index = SyncFileIndex();
        for (final record in order) {
          await applyRemoteFiles(
            dataPath: dataPath,
            index: index,
            files: [if (record.hash.isNotEmpty) record],
            deleted: [if (record.hash.isEmpty) record],
            fetch: (hash, destination) async {
              await destination.writeAsBytes(blobs[hash]!);
              return true;
            },
          );
        }
        expect(
          File(p.join(dataPath, 'workflows', 'flow.json')).readAsStringSync(),
          'last',
          reason: '$order',
        );
      }
    });

    test('a file grown too large to sync is not taken for removed', () async {
      final big = File(p.join(root.path, 'files', 'big.bin'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(List.filled(16, 1));
      final index = SyncFileIndex();
      var scan = await scanSyncedFiles(
        dataPath: root.path,
        index: index,
        maximumBytes: 32,
      );
      index.entries.addAll(scan.current);
      big.writeAsBytesSync(List.filled(64, 2));
      scan = await scanSyncedFiles(
        dataPath: root.path,
        index: index,
        maximumBytes: 32,
      );
      expect(scan.isEmpty, isTrue);
      expect(scan.skipped, 1);
    });

    test('contents not in the folder yet wait for a later round', () async {
      final index = SyncFileIndex();
      final result = await applyRemoteFiles(
        dataPath: root.path,
        index: index,
        files: [
          SyncFileRecord(path: 'images/b.png', hash: 'b' * 64, modified: 1),
        ],
        deleted: const [],
        fetch: (_, __) async => false,
      );
      expect(result.waiting, 1);
      expect(index.waiting.keys, ['images/b.png']);
    });
  });

  group('a file a page names, on another computer', () {
    late Directory root;
    setUp(
      () async => root = await Directory.systemTemp.createTemp('sync_paths'),
    );
    tearDown(() async => root.delete(recursive: true));

    test('is found at the same place inside this data folder', () {
      File(p.join(root.path, 'images', 'cat.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1]);
      final here = p.join(root.path, 'images', 'cat.png');

      for (final elsewhere in [
        '/home/someone/.local/share/io.appflowy.appflowy/data/images/cat.png',
        r'C:\Users\someone\AppData\Roaming\AppFlowy\data\images\cat.png',
        'file:///Users/someone/Library/AppFlowy/data/images/cat.png',
        // A synced folder's name higher up the old path does not mislead it.
        '/home/images/files/data/images/cat.png',
      ]) {
        expect(
          resolveWorkspaceFilePathUnder(elsewhere, root.path),
          here,
          reason: elsewhere,
        );
      }
    });

    test('is left alone when it is here already, remote, or nowhere', () {
      final local = File(p.join(root.path, 'files', 'a.pdf'))
        ..createSync(recursive: true);
      expect(resolveWorkspaceFilePathUnder(local.path, root.path), local.path);
      expect(
        resolveWorkspaceFilePathUnder(
          'https://example.com/images/a.png',
          root.path,
        ),
        'https://example.com/images/a.png',
      );
      expect(
        resolveWorkspaceFilePathUnder(
          '/elsewhere/images/missing.png',
          root.path,
        ),
        '/elsewhere/images/missing.png',
      );
    });
  });

  group('packs', () {
    late Directory root;
    setUp(
      () async => root = await Directory.systemTemp.createTemp('sync_pack'),
    );
    tearDown(() async => root.delete(recursive: true));

    test('a record and a bundle come back exactly', () async {
      final bundle = File(p.join(root.path, 'in.bundle'))
        ..writeAsBytesSync(List.generate(300000, (i) => i % 251));
      final pack = File(p.join(root.path, 'x.pack'));
      final record = SyncPackRecord(
        kind: SyncPackKind.changes,
        epoch: '20260101T000000-aaaaaa',
        device: 'deviceaaaaaa',
        deviceName: 'Desk',
        workspaceId: 'w',
        seq: 3,
        createdAt: DateTime.utc(2026),
        hasBundle: true,
        files: const [
          SyncFileRecord(
            path: 'images/a.png',
            hash: 'h',
            bytes: 4,
            modified: 5,
          ),
        ],
        deleted: const [SyncFileRecord(path: 'files/b.txt', modified: 6)],
      );
      await writeSyncPack(destination: pack, record: record, bundle: bundle);
      expect(pack.lengthSync(), lessThan(bundle.lengthSync()));

      final out = File(p.join(root.path, 'out.bundle'));
      final read = await readSyncPack(source: pack, bundle: out);
      expect(read.seq, 3);
      expect(read.deviceName, 'Desk');
      expect(read.files.single.path, 'images/a.png');
      expect(read.deleted.single.path, 'files/b.txt');
      expect(out.readAsBytesSync(), bundle.readAsBytesSync());
    });

    test('a pack with no bundle writes none', () async {
      final pack = File(p.join(root.path, 'x.pack'));
      await writeSyncPack(
        destination: pack,
        record: SyncPackRecord(
          kind: SyncPackKind.changes,
          epoch: 'e',
          device: 'd',
          workspaceId: 'w',
          createdAt: DateTime.utc(2026),
        ),
      );
      final out = File(p.join(root.path, 'out.bundle'));
      final read = await readSyncPack(source: pack, bundle: out);
      expect(read.hasBundle, isFalse);
      expect(out.existsSync(), isFalse);
    });

    test('something that is not a pack is refused', () async {
      final pack = File(p.join(root.path, 'x.pack'))
        ..writeAsBytesSync(gzip.encode(utf8.encode('hello, not a pack')));
      expect(
        () => readSyncPack(source: pack, bundle: File(p.join(root.path, 'o'))),
        throwsA(isA<SyncPackError>()),
      );
    });
  });

  group('two computers sharing a folder', () {
    late Directory root;
    late Directory folder;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('sync_engine');
      folder = Directory(p.join(root.path, 'shared'))..createSync();
    });
    tearDown(() async => root.delete(recursive: true));

    BackupDestination destination() => BackupDestination(
          kind: BackupDestinationKind.folder,
          localPath: folder.path,
        );

    test('join, merge both ways, keep files, checkpoint and restore', () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      a.bridge.add('page', 'hello from A');
      b.bridge.add('other', 'only on B');
      File(p.join(a.data.path, 'images', 'cat.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3, 4]);
      await a.attach();
      await b.attach();

      // A starts the folder.
      expect(
        (await a.engine.inspect(destination())).state,
        SyncFolderState.empty,
      );
      await a.engine.startNew(destination());
      expect(a.engine.isBoundHere, isTrue);

      // B sees somebody else's workspace there, and joins it.
      final seen = await b.engine.unlockFolder(
        destination(),
        await b.engine.inspect(destination()),
        _passphrase,
      );
      expect(seen.state, SyncFolderState.otherWorkspace);
      expect(seen.epoch!.workspaceId, 'workspace-a');
      await b.engine.join(destination(), seen);
      expect(b.restarted, 1);
      expect(b.safetyCopies, ['join']);
      expect(b.bridge.workspaceId, 'workspace-a');
      expect(b.bridge.objects['page'], {'hello from A'});
      expect(b.bridge.objects.containsKey('other'), isFalse);
      expect(
        File(p.join(b.data.path, 'images', 'cat.png')).readAsBytesSync(),
        [1, 2, 3, 4],
      );
      expect(b.engine.isBoundHere, isTrue);
      await b.engine.syncNow();
      expect(b.engine.phase, SyncPhase.idle);
      expect(b.bridge.exportsWritten, 0, reason: 'joining owes nothing back');

      // Edits on each side reach the other, once.
      a.bridge.add('page', 'second line from A');
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(b.bridge.objects['page'], {'hello from A', 'second line from A'});
      await b.engine.syncNow();
      expect(b.bridge.exportsWritten, 0, reason: 'nothing echoes back');

      a.bridge.add('page', 'A offline');
      b.bridge.add('page', 'B offline');
      File(p.join(b.data.path, 'files', 'notes.txt'))
        ..createSync(recursive: true)
        ..writeAsStringSync('from B');
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.bridge.objects['page'], b.bridge.objects['page']);
      expect(a.bridge.objects['page'], contains('B offline'));
      expect(
        File(p.join(a.data.path, 'files', 'notes.txt')).readAsStringSync(),
        'from B',
      );
      expect(
        a.engine.devices.map((device) => device.isThisComputer),
        containsAll([true, false]),
      );

      // A removed file goes everywhere.
      File(p.join(a.data.path, 'images', 'cat.png')).deleteSync();
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(
        File(p.join(b.data.path, 'images', 'cat.png')).existsSync(),
        isFalse,
      );

      // Enough changes make a checkpoint, and the changes it holds are tidied.
      for (var i = 0; i < 4; i++) {
        a.bridge.add('page', 'line $i');
        await a.engine.syncNow();
      }
      final names = folder.listSync().map((entity) => p.basename(entity.path));
      expect(names.where((name) => name.contains('_ckpt_')), isNotEmpty);

      // A third computer joining late starts from the checkpoint.
      final c = _Computer(
        root,
        'c',
        uid: 3,
        workspaceId: 'workspace-c',
        password: null,
      );
      await c.attach();
      final third = await c.engine.inspect(destination());
      expect(third.needsPassword, isTrue);
      final opened =
          await c.engine.unlockFolder(destination(), third, _passphrase);
      await c.engine.join(destination(), opened);
      expect(c.passwords.adopted, [_passphrase]);
      await c.engine.syncNow();
      expect(c.bridge.objects['page'], a.bridge.objects['page']);

      // A restores the workspace; B notices, and takes it up when asked.
      final snapshot = File(p.join(root.path, 'restore.bundle'));
      a.bridge.writeSnapshot(snapshot, {
        'page': {'restored'},
      });
      final epoch = a.engine.newRestoreEpoch()!;
      await a.bridge.scheduleRestore(
        path: snapshot.path,
        syncStatePath: await a.engine.collabStatePath(epoch),
      );
      await a.engine.publishRestore(
        epoch: epoch,
        snapshot: snapshot,
        filesRoot: a.data.path,
      );
      await a.restart();
      expect(a.bridge.objects['page'], {'restored'});

      b.bridge.add('page', 'typed on B before it heard');
      await b.engine.syncNow();
      expect(b.engine.phase, SyncPhase.restoredElsewhere);
      expect(b.engine.restoredElsewhere!.reason, SyncEpochReason.restored);
      await b.engine.loadRestoredWorkspace();
      expect(b.bridge.objects['page'], {'restored'});
      await b.engine.syncNow();
      expect(b.engine.phase, SyncPhase.idle);

      // And they carry on from there.
      b.bridge.add('page', 'after the restore');
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.bridge.objects['page'], {'restored', 'after the restore'});

      a.engine.detach();
      b.engine.detach();
      c.engine.detach();
    });

    test('settings follow the workspace, the later change winning', () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      a.prefs.values.addAll({'theme': 'dark', 'shortcuts.desktop': 'A keys'});
      b.prefs.values.addAll({
        'theme': 'light',
        'only on b': 'b',
        'shortcuts.desktop': 'B keys',
      });
      await a.attach();
      await b.attach();
      a.bridge.add('page', 'hello');
      await a.engine.startNew(destination());

      // Joining takes the folder's settings, and keeps what only B has.
      await b.joinSealed(destination());
      expect(b.prefs.values, {
        'theme': 'dark',
        'shortcuts.desktop': 'A keys',
        'only on b': 'b',
      });
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.prefs.values['only on b'], 'b');

      // A change, and a removal, on either side reach the other.
      b.prefs.values['theme'] = 'sepia';
      a.prefs.values.remove('only on b');
      await b.engine.syncNow();
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(a.prefs.values['theme'], 'sepia');
      expect(b.prefs.values.containsKey('only on b'), isFalse);

      // Both change one setting before hearing of the other: the change that
      // goes out last is the one everybody keeps.
      a.prefs.values['theme'] = 'from A';
      b.prefs.values['theme'] = 'from B';
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.prefs.values['theme'], 'from B');
      expect(b.prefs.values['theme'], 'from B');

      // With settings sync off, B neither sends its settings nor takes the
      // others'. Turned back on, it takes what the folder has.
      await b.engine.setSyncPreferences(false);
      b.prefs.values['theme'] = 'B alone';
      a.prefs.values['font'] = 'Inter';
      await a.engine.syncNow();
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.prefs.values['theme'], 'from B');
      expect(b.prefs.values.containsKey('font'), isFalse);
      await b.engine.setSyncPreferences(true);
      expect(b.prefs.values['theme'], 'from B');
      expect(b.prefs.values['font'], 'Inter');

      // A Mac's shortcuts are carried by the others, never applied by them,
      // and reach a Mac joining later from a checkpoint.
      final mac = _Computer(
        root,
        'mac',
        uid: 3,
        workspaceId: 'workspace-m',
        keyboard: 'macos',
      );
      mac.prefs.values['shortcuts.macos'] = 'Mac keys';
      await mac.attach();
      await mac.joinSealed(destination());
      expect(mac.prefs.values['shortcuts.desktop'], isNull);
      await mac.engine.syncNow();
      for (var i = 0; i < 4; i++) {
        a.bridge.add('page', 'line $i');
        await a.engine.syncNow();
      }
      expect(a.prefs.values.containsKey('shortcuts.macos'), isFalse);
      expect(
        folder.listSync().map((entity) => p.basename(entity.path)),
        contains(contains('_ckpt_')),
      );
      final laterMac = _Computer(
        root,
        'mac2',
        uid: 4,
        workspaceId: 'workspace-n',
        keyboard: 'macos',
      );
      await laterMac.attach();
      await laterMac.joinSealed(destination());
      expect(laterMac.prefs.values['shortcuts.macos'], 'Mac keys');
      expect(laterMac.prefs.values['theme'], 'from B');
      expect(laterMac.prefs.values.containsKey('shortcuts.desktop'), isFalse);

      for (final computer in [a, b, mac, laterMac]) {
        computer.engine.detach();
      }
    });

    // Every pack in the folder, opened with [key].
    Future<List<SyncPackRecord>> openPacks(SyncKey key) async {
      final records = <SyncPackRecord>[];
      for (final entity in folder.listSync()) {
        final name = p.basename(entity.path);
        if (entity is! File || !name.endsWith('.pack')) {
          continue;
        }
        final plain = File(p.join(root.path, 'opened.pack'));
        await key.openFile(entity, plain);
        records.add(
          await readSyncPack(
            source: plain,
            bundle: File(p.join(root.path, 'opened.bundle')),
          ),
        );
      }
      return records;
    }

    test('a sealed folder holds nothing anybody can read', () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      await a.attach();
      a.bridge.add('page', 'a secret line');
      a.prefs.values['cred:connection:google'] = 'refresh-token-value';
      final picture = List<int>.generate(4096, (i) => (i * 7) % 256);
      File(p.join(a.data.path, 'images', 'cat.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync(picture);
      await a.engine.startNew(destination());
      a.bridge.add('page', 'another secret line');
      await a.engine.syncNow();
      expect(a.engine.isSealed, isTrue);

      final hash =
          await hashFile(File(p.join(a.data.path, 'images', 'cat.png')));
      final everything = [
        ...folder.listSync(),
        ...Directory(p.join(folder.path, 'afsync1_files')).listSync(),
      ].whereType<File>();
      for (final file in everything) {
        final name = p.basename(file.path);
        final bytes = file.readAsBytesSync();
        final text = latin1.decode(bytes);
        for (final secret in [
          'secret line',
          'refresh-token-value',
          'workspace-a',
          'Computer a',
        ]) {
          expect(text, isNot(contains(secret)), reason: '$name: $secret');
        }
        expect(name, isNot(contains(hash)), reason: name);
        if (SyncFileName.parse(name)?.kind == SyncFileKind.vault) {
          expect(SyncVault.tryParse(text), isNotNull);
        } else if (name.endsWith('.json')) {
          expect(() => jsonDecode(text), throwsFormatException, reason: name);
        } else {
          expect(await isSealedSyncFile(file), isTrue, reason: name);
        }
      }
      a.engine.detach();
    });

    test('a computer without the password waits, then catches up', () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(
        root,
        'b',
        uid: 2,
        workspaceId: 'workspace-b',
        password: null,
      );
      await a.attach();
      await b.attach();
      a.bridge.add('page', 'hello');
      await a.engine.startNew(destination());

      final seen = await b.engine.inspect(destination());
      expect(seen.state, SyncFolderState.locked);
      expect(seen.epoch, isNull, reason: 'nothing is told before unlocking');
      await expectLater(
        b.engine.unlockFolder(destination(), seen, 'not the passphrase'),
        throwsA(isA<SyncError>()),
      );
      await b.joinSealed(destination());
      expect(b.bridge.objects['page'], {'hello'});

      // B forgets the key and the password, as a new computer would not have
      // them.
      b.keys.keys.clear();
      b.passwords.value = null;
      b.engine.forgetKeyInMemory();
      await b.restart();
      a.bridge.add('page', 'while B was locked');
      await a.engine.syncNow();
      b.bridge.add('page', 'typed on B while locked');
      await b.engine.syncNow();
      expect(b.engine.phase, SyncPhase.locked);
      expect(b.bridge.objects['page'], isNot(contains('while B was locked')));
      await expectLater(
        b.engine.unlock('not the passphrase'),
        throwsA(isA<SyncError>()),
      );
      await b.engine.unlock(_passphrase);
      expect(b.passwords.value, _passphrase, reason: 'it is the password');
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(b.engine.phase, SyncPhase.idle);
      expect(b.bridge.objects['page'], contains('while B was locked'));
      expect(a.bridge.objects['page'], contains('typed on B while locked'));

      a.engine.detach();
      b.engine.detach();
    });

    test('a folder written before sealing is sealed without losing anything',
        () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(
        root,
        'b',
        uid: 2,
        workspaceId: 'workspace-b',
        password: null,
      );
      await a.attach();
      await b.attach();
      a.bridge.add('page', 'from the old days');
      File(p.join(a.data.path, 'images', 'cat.png'))
        ..createSync(recursive: true)
        ..writeAsBytesSync([1, 2, 3]);
      a.prefs.values['theme'] = 'dark';
      await a.engine.startUnsealed(destination());
      final seen = await b.engine.inspect(destination());
      expect(seen.needsPassword, isFalse);
      await b.engine.join(destination(), seen);
      expect(b.bridge.objects['page'], {'from the old days'});
      expect(b.prefs.values, isEmpty, reason: 'settings travel sealed only');

      // B has something A has not seen when A seals the folder.
      b.bridge.add('page', 'B, just before the seal');
      await b.engine.syncNow();
      await a.engine.sealWithAppPassword();
      expect(a.engine.isSealed, isTrue);
      expect(a.bridge.objects['page'], contains('B, just before the seal'));
      final names = folder.listSync().map((entity) => p.basename(entity.path));
      final epochs = {
        for (final name in names)
          if (SyncFileName.parse(name)?.epoch case final epoch?
              when epoch.isNotEmpty)
            epoch,
      };
      expect(epochs, hasLength(1), reason: 'nothing unsealed stays behind');

      // B needs the passphrase, and loses nothing it typed meanwhile.
      b.bridge.add('page', 'B, after the seal');
      await b.engine.syncNow();
      expect(b.engine.phase, SyncPhase.locked);
      await b.engine.unlock(_passphrase);
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.bridge.objects['page'], b.bridge.objects['page']);
      expect(a.bridge.objects['page'], contains('B, after the seal'));
      expect(b.prefs.values['theme'], 'dark', reason: 'now they travel');
      expect(
        File(p.join(b.data.path, 'images', 'cat.png')).readAsBytesSync(),
        [1, 2, 3],
      );

      a.engine.detach();
      b.engine.detach();
    });

    test('accounts and keys travel, and can be taken out of the folder',
        () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      await a.attach();
      await b.attach();
      a.prefs.values.addAll({
        'cred:connection:google': 'token from A',
        'theme': 'dark',
      });
      await a.engine.startNew(destination());
      await b.joinSealed(destination());
      expect(b.prefs.values['cred:connection:google'], 'token from A');
      expect(b.engine.credentialsSynced, isTrue);

      // A refreshes its token; B gets the new one.
      a.prefs.values['cred:connection:google'] = 'token renewed on A';
      await a.engine.syncNow();
      await b.engine.syncNow();
      expect(b.prefs.values['cred:connection:google'], 'token renewed on A');

      // Taken out of the folder: every computer keeps its own.
      await a.engine.setSyncCredentials(false);
      expect(a.engine.credentialsSynced, isFalse);
      final key = a.keys.keys.values.single;
      for (final record in await openPacks(key)) {
        expect(
          record.preferences.where((r) => r.key.startsWith('cred:')),
          isEmpty,
          reason: '${record.kind} ${record.seq}',
        );
      }
      await b.engine.syncNow();
      expect(b.engine.credentialsSynced, isFalse);
      expect(b.prefs.values['cred:connection:google'], 'token renewed on A');
      b.prefs.values['cred:connection:box'] = 'only on B';
      b.prefs.values['theme'] = 'light';
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.prefs.values['theme'], 'light', reason: 'settings still travel');
      expect(a.prefs.values.containsKey('cred:connection:box'), isFalse);
      for (final record in await openPacks(key)) {
        expect(
          record.preferences.where((r) => r.key.startsWith('cred:')),
          isEmpty,
        );
      }

      // On again: what each has travels once more.
      await a.engine.setSyncCredentials(true);
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(b.engine.credentialsSynced, isTrue);
      expect(a.prefs.values['cred:connection:box'], 'only on B');

      a.engine.detach();
      b.engine.detach();
    });

    test('a pack copied over another is refused', () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      await a.attach();
      await b.attach();
      await a.engine.startNew(destination());
      await b.joinSealed(destination());
      a.bridge.add('page', 'first');
      await a.engine.syncNow();
      a.bridge.add('page', 'second');
      await a.engine.syncNow();
      final packs = [
        for (final entity in folder.listSync())
          if (p.basename(entity.path).contains('_chg_')) entity as File,
      ]..sort((x, y) => x.path.compareTo(y.path));
      expect(packs, hasLength(2));
      packs.first.copySync(packs.last.path);
      await b.engine.syncNow();
      expect(b.engine.phase, SyncPhase.failed);
      expect(b.engine.activity, contains('not what its name says'));

      a.engine.detach();
      b.engine.detach();
    });

    test('what was carried is taken once kept, never sent as removed',
        () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      a.prefs.values['home:workspace-a'] = 'A\'s Home';
      await a.attach();
      await b.attach();
      await a.engine.startNew(destination());

      // B joins before it keeps that workspace's Home, as a computer joining
      // from the first screen does.
      b.prefs.refused.add('home:workspace-a');
      await b.joinSealed(destination());
      expect(b.prefs.values.containsKey('home:workspace-a'), isFalse);
      await b.engine.syncNow();

      b.prefs.refused.clear();
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(b.prefs.values['home:workspace-a'], 'A\'s Home');
      expect(a.prefs.values['home:workspace-a'], 'A\'s Home');

      a.engine.detach();
      b.engine.detach();
    });

    test('only a computer that sent something writes a checkpoint', () async {
      // A never folds changes up, so B is the one that sees them pile up.
      final a = _Computer(
        root,
        'a',
        uid: 1,
        workspaceId: 'workspace-a',
        checkpointAfter: 1000,
      );
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      await a.attach();
      await b.attach();
      a.bridge.add('page', 'hello');
      await a.engine.startNew(destination());
      await b.joinSealed(destination());

      List<String> checkpointsOf(_Computer computer) => [
            for (final entity in folder.listSync())
              if (p
                  .basename(entity.path)
                  .contains('_ckpt_${computer.settings.deviceId}_'))
                p.basename(entity.path),
          ];

      // A checkpoint is named after its writer's last change; B has none.
      for (var i = 0; i < 4; i++) {
        a.bridge.add('page', 'line $i');
        await a.engine.syncNow();
        await b.engine.syncNow();
      }
      expect(checkpointsOf(b), isEmpty);
      expect(b.bridge.objects['page'], a.bridge.objects['page']);

      // Once it has sent something, it may.
      b.bridge.add('page', 'from B');
      await b.engine.syncNow();
      expect(checkpointsOf(b), hasLength(2)); // The pack and its record.
      await b.engine.syncNow();
      expect(checkpointsOf(b), hasLength(2));

      // What the checkpoint tidied away still reaches everybody.
      b.bridge.add('page', 'more from B');
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.bridge.objects['page'], b.bridge.objects['page']);
      final c = _Computer(root, 'c', uid: 3, workspaceId: 'workspace-c');
      await c.attach();
      await c.joinSealed(destination());
      await c.engine.syncNow();
      expect(c.bridge.objects['page'], b.bridge.objects['page']);

      a.engine.detach();
      b.engine.detach();
      c.engine.detach();
    });

    test('the AppFlowy password opens a folder sealed with it', () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      final c = _Computer(
        root,
        'c',
        uid: 3,
        workspaceId: 'workspace-c',
        password: 'another password',
      );
      await a.attach();
      await b.attach();
      await c.attach();
      a.bridge.add('page', 'hello');
      await a.engine.startNew(destination());

      // B has the same AppFlowy password: nothing to type.
      final seen = await b.engine.inspect(destination());
      expect(seen.needsPassword, isFalse);
      expect(seen.state, SyncFolderState.otherWorkspace);
      await b.engine.join(destination(), seen);
      expect(b.bridge.objects['page'], {'hello'});
      expect(b.passwords.adopted, isEmpty);

      // C's is another one: the folder stays shut to it.
      expect(
        (await c.engine.inspect(destination())).state,
        SyncFolderState.locked,
      );

      a.engine.detach();
      b.engine.detach();
      c.engine.detach();
    });

    test('a new AppFlowy password seals the folder again; the others ask once',
        () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      await a.attach();
      await b.attach();
      a.bridge.add('page', 'before');
      await a.engine.startNew(destination());
      await b.joinSealed(destination());
      await b.engine.syncNow();
      await a.engine.syncNow();
      final before = a.engine.binding!.vaultId;

      // A changes its password; B sends something before it hears.
      a.passwords.value = 'a brand new password';
      await a.engine.markResealPending();
      expect(a.engine.needsResealing, isTrue);
      b.bridge.add('page', 'B, before it heard');
      await b.engine.syncNow();
      await a.engine.sealWithAppPassword();
      expect(a.engine.needsResealing, isFalse);
      expect(a.engine.binding!.vaultId, isNot(before));
      expect(a.bridge.objects['page'], contains('B, before it heard'));

      // B is listed as catching up, and is asked for the new password.
      await a.engine.syncNow();
      SyncDeviceSummary other() =>
          a.engine.devices.singleWhere((device) => !device.isThisComputer);
      expect(other().waiting, isTrue);
      expect(other().name, 'Computer b');
      b.bridge.add('page', 'B, while locked');
      await b.engine.syncNow();
      expect(b.engine.phase, SyncPhase.locked);
      expect(b.engine.passwordChangedElsewhere, isTrue);
      await expectLater(
        b.engine.unlock(_passphrase),
        throwsA(isA<SyncError>()),
      );
      await b.engine.unlock('a brand new password');
      expect(b.passwords.value, 'a brand new password');
      await b.engine.syncNow();
      await a.engine.syncNow();
      expect(a.bridge.objects['page'], contains('B, while locked'));
      expect(b.bridge.objects['page'], a.bridge.objects['page']);
      expect(other().waiting, isFalse);

      // Only the epoch sealed with the new password is left.
      final vaults = folder
          .listSync()
          .map((entity) => p.basename(entity.path))
          .where((name) => SyncFileName.parse(name)?.kind == SyncFileKind.vault);
      expect(vaults, hasLength(1));

      a.engine.detach();
      b.engine.detach();
    });

    test('a record left by a seal that never finished seals nothing',
        () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      await a.attach();
      a.bridge.add('page', 'hello');
      await a.engine.startUnsealed(destination());

      // What a seal that failed half way left behind in an earlier version.
      final (stray, _) = await SyncVault.create(
        passphrase: 'whatever was typed then',
        now: DateTime.now(),
        iterations: 1000,
      );
      final strayFile = File(p.join(folder.path, SyncFileName.legacyVault))
        ..writeAsStringSync(stray.encode());
      a.bridge.add('page', 'still syncing');
      await a.engine.syncNow();
      expect(a.engine.phase, SyncPhase.idle, reason: a.engine.activity);
      expect(a.engine.isSealed, isFalse);

      await a.engine.sealWithAppPassword();
      expect(a.engine.isSealed, isTrue);
      expect(strayFile.existsSync(), isFalse);
      await a.engine.syncNow();
      expect(a.engine.phase, SyncPhase.idle, reason: a.engine.activity);

      a.engine.detach();
    });

    test('linked devices are listed, and known again before the first round',
        () async {
      final a = _Computer(root, 'a', uid: 1, workspaceId: 'workspace-a');
      final b = _Computer(root, 'b', uid: 2, workspaceId: 'workspace-b');
      await a.attach();
      await b.attach();
      await a.engine.startNew(destination());
      await b.joinSealed(destination());
      await b.engine.syncNow();
      await a.engine.syncNow();

      final devices = a.engine.devices;
      expect(devices.map((device) => device.name), ['Computer a', 'Computer b']);
      expect(devices.first.isThisComputer, isTrue);
      expect(devices.last.platform, Platform.operatingSystem);
      expect(devices.last.lastSeen, isNotNull);
      expect(devices.last.waiting, isFalse);

      // A restarted AppFlowy shows them before it has read the folder.
      a.engine.detach();
      final restarted = WorkspaceSyncEngine(
        bridge: a.bridge,
        settings: a.settings,
        dataPath: () async => a.data.path,
        scratch: () async => Directory(p.join(root.path, 'a', 'scratch')),
        deviceName: () => 'Computer a',
        preferences: a.prefs,
        keys: a.keys,
        passwords: a.passwords,
        vaultIterations: 1000,
      );
      await restarted.attach(
        workspaceId: a.bridge.workspaceId,
        uid: a.bridge.uid,
        workspaceName: 'Workspace of 1',
        isLocalWorkspace: true,
      );
      expect(
        restarted.devices.map((device) => device.name),
        ['Computer a', 'Computer b'],
      );

      restarted.detach();
      b.engine.detach();
    });
  });
}

/// One computer: a workspace held as sets of lines — a CRDT whose merge is a
/// union — a data folder, and an engine.
class _Computer {
  _Computer(
    Directory root,
    String name, {
    required int uid,
    required String workspaceId,
    int checkpointAfter = 3,
    String keyboard = 'desktop',
    String? password = _passphrase,
  })  : data = Directory(p.join(root.path, name, 'data'))
          ..createSync(recursive: true),
        bridge = _FakeBridge(uid: uid, workspaceId: workspaceId),
        prefs = _MemoryPreferences(keyboard),
        passwords = _FakePasswords(password) {
    final home = Directory(p.join(root.path, name, 'home'))
      ..createSync(recursive: true);
    settings = SyncSettings(storage: _MemoryStorage(), home: () async => home);
    engine = WorkspaceSyncEngine(
      bridge: bridge,
      settings: settings,
      dataPath: () async => data.path,
      scratch: () async => Directory(p.join(root.path, name, 'scratch')),
      restart: restart,
      safetyCopy: (reason) async => safetyCopies.add(reason),
      deviceName: () => 'Computer $name',
      checkpointAfter: checkpointAfter,
      checkpointQuietPeriod: Duration.zero,
      preferences: prefs,
      keys: keys,
      passwords: passwords,
      vaultIterations: 1000,
    );
  }

  final Directory data;
  final _FakeBridge bridge;
  final _MemoryPreferences prefs;
  final _FakePasswords passwords;
  final MemoryKeyKeeper keys = MemoryKeyKeeper();
  late final SyncSettings settings;
  late final WorkspaceSyncEngine engine;
  final List<String> safetyCopies = [];
  int restarted = 0;

  Future<void> attach() => engine.attach(
        workspaceId: bridge.workspaceId,
        uid: bridge.uid,
        workspaceName: 'Workspace of ${bridge.uid}',
        isLocalWorkspace: true,
      );

  /// Joins the workspace in a sealed folder, typing the passphrase.
  Future<void> joinSealed(BackupDestination destination) async {
    final seen = await engine.inspect(destination);
    await engine.join(
      destination,
      seen.needsPassword
          ? await engine.unlockFolder(destination, seen, _passphrase)
          : seen,
    );
  }

  Future<void> restart() async {
    restarted++;
    engine.detach();
    bridge.applyPendingRestore();
    await attach();
  }
}

/// A computer's AppFlowy password, as far as sync asks for it.
class _FakePasswords implements AppPasswordSource {
  _FakePasswords(this.value);

  String? value;
  final List<String> adopted = [];

  @override
  Future<String?> current() async => value;

  @override
  Future<void> adopt(String password) async {
    adopted.add(password);
    value = password;
  }
}

/// A computer's settings, with shortcuts for one kind of keyboard.
class _MemoryPreferences implements SyncedPreferencesSource {
  _MemoryPreferences(this.keyboard);

  @override
  Set<String> unreadable = {};

  final String keyboard;
  final Map<String, String> values = {};

  /// Settings this computer does not keep for now.
  final Set<String> refused = {};

  @override
  bool handles(String key) =>
      !refused.contains(key) &&
      (!key.startsWith('shortcuts.') || key == 'shortcuts.$keyboard');

  @override
  Future<Map<String, String>> read() async => Map.of(values);

  @override
  Future<void> apply(Map<String, String?> changes) async {
    changes.forEach((key, value) {
      if (value == null) {
        values.remove(key);
      } else {
        values[key] = value;
      }
    });
  }
}

class _FakeBridge implements WorkspaceBundleBridge {
  _FakeBridge({required this.uid, required this.workspaceId});

  int uid;
  String workspaceId;
  Map<String, Set<String>> objects = {};
  int exportsWritten = 0;
  (String, String)? _pending;
  WorkspaceRestoreOutcome? _outcome;

  void add(String object, String line) =>
      objects.putIfAbsent(object, () => {}).add(line);

  void writeSnapshot(File file, Map<String, Set<String>> contents) =>
      _write(file, 'snapshot', contents);

  void _write(File file, String kind, Map<String, Set<String>> contents) {
    final header = utf8.encode(
      jsonEncode({
        'kind': kind,
        'uid': uid,
        'workspace_id': workspaceId,
        'workspace_name': 'Workspace of $uid',
        'created_at': 1,
        'objects': {
          for (final entry in contents.entries) entry.key: entry.value.toList(),
        },
      }),
    );
    final length = ByteData(4)..setUint32(0, header.length, Endian.little);
    file
      ..createSync(recursive: true)
      ..writeAsBytesSync([
        ...ascii.encode(workspaceBundleMagic),
        ...length.buffer.asUint8List(),
        ...header,
      ]);
  }

  static Map<String, Object?> _read(String path) {
    final bytes = File(path).readAsBytesSync();
    final length =
        ByteData.sublistView(bytes, 8, 12).getUint32(0, Endian.little);
    return jsonDecode(utf8.decode(bytes.sublist(12, 12 + length)))
        as Map<String, Object?>;
  }

  static Map<String, Set<String>> _objects(Map<String, Object?> json) => {
        for (final entry in (json['objects']! as Map).entries)
          entry.key as String: {...(entry.value as List).cast<String>()},
      };

  static Map<String, Set<String>> _state(String path) {
    final file = File(path);
    if (!file.existsSync()) {
      return {};
    }
    return _objects(
      jsonDecode(file.readAsStringSync()) as Map<String, Object?>,
    );
  }

  static void _saveState(String path, Map<String, Set<String>> state) {
    File(path)
      ..createSync(recursive: true)
      ..writeAsStringSync(
        jsonEncode({
          'objects': {
            for (final entry in state.entries) entry.key: entry.value.toList(),
          },
        }),
      );
  }

  WorkspaceBundleExport _result(bool wrote, int count) => WorkspaceBundleExport(
        wrote: wrote,
        objectCount: count,
        uid: uid,
        workspaceId: workspaceId,
        workspaceName: 'Workspace of $uid',
        isLocalWorkspace: true,
      );

  @override
  Future<WorkspaceBundleExport> exportSnapshot({
    required String path,
    String syncStatePath = '',
  }) async {
    _write(File(path), 'snapshot', objects);
    if (syncStatePath.isNotEmpty) {
      _saveState(syncStatePath, {
        for (final entry in objects.entries) entry.key: {...entry.value},
      });
    }
    return _result(true, objects.length);
  }

  @override
  Future<WorkspaceBundleExport> exportChanges({
    required String path,
    required String syncStatePath,
  }) async {
    final state = _state(syncStatePath);
    final changed = <String, Set<String>>{};
    for (final entry in objects.entries) {
      if (!(state[entry.key] ?? {}).containsAll(entry.value)) {
        changed[entry.key] = {...entry.value};
        state[entry.key] = {...entry.value};
      }
    }
    if (changed.isEmpty) {
      return _result(false, 0);
    }
    exportsWritten++;
    _write(File(path), 'changes', changed);
    _saveState('$syncStatePath.next', state);
    return _result(true, changed.length);
  }

  @override
  Future<WorkspaceBundleImport> importChanges({
    required String path,
    String syncStatePath = '',
  }) async {
    final bundle = _read(path);
    if (bundle['workspace_id'] != workspaceId) {
      throw const WorkspaceBundleError('another workspace');
    }
    final state = syncStatePath.isEmpty ? null : _state(syncStatePath);
    for (final entry in _objects(bundle).entries) {
      final local = objects.putIfAbsent(entry.key, () => {});
      final clean =
          state != null && (state[entry.key] ?? {}).containsAll(local);
      local.addAll(entry.value);
      if (clean) {
        state[entry.key] = {...local};
      }
    }
    if (state != null) {
      _saveState(syncStatePath, state);
    }
    return const WorkspaceBundleImport();
  }

  @override
  Future<void> scheduleRestore({
    required String path,
    String syncStatePath = '',
  }) async {
    final kept = '$path.kept';
    File(path).copySync(kept);
    _pending = (kept, syncStatePath);
  }

  void applyPendingRestore() {
    final pending = _pending;
    if (pending == null) {
      return;
    }
    _pending = null;
    final bundle = _read(pending.$1);
    uid = bundle['uid']! as int;
    workspaceId = bundle['workspace_id']! as String;
    objects = _objects(bundle);
    if (pending.$2.isNotEmpty) {
      _saveState(pending.$2, {
        for (final entry in objects.entries) entry.key: {...entry.value},
      });
    }
    _outcome = WorkspaceRestoreOutcome(
      succeeded: true,
      workspaceId: workspaceId,
      workspaceName: 'Workspace of $uid',
      objectCount: objects.length,
    );
  }

  @override
  Future<WorkspaceRestoreOutcome?> takeRestoreOutcome() async {
    final outcome = _outcome;
    _outcome = null;
    return outcome;
  }
}

class _MemoryStorage implements KeyValueStorage {
  final Map<String, String> _values = {};

  @override
  Future<void> set(String key, String value) async => _values[key] = value;

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = _values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();
}
