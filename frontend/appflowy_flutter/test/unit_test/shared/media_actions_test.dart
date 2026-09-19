import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory temporary;
  late _RecordingClipboard clipboard;
  late _RecordingShare shares;
  late List<http.Request> requests;
  late http.Client rejectNetwork;

  setUp(() async {
    temporary = await Directory.systemTemp.createTemp('af_media_actions_test_');
    clipboard = _RecordingClipboard();
    shares = _RecordingShare();
    requests = [];
    rejectNetwork = MockClient((request) async {
      requests.add(request);
      throw StateError('Unexpected fake HTTP request.');
    });
    getIt.pushNewScope();
  });

  tearDown(() async {
    rejectNetwork.close();
    await getIt.popScope();
    await temporary.delete(recursive: true);
  });

  Future<Directory> tempDirectory() async => temporary;

  MediaActionService service({
    http.Client? client,
    ClipboardWriter? Function()? clipboardProvider,
    Future<Directory> Function()? directory,
  }) =>
      MediaActionService(
        clipboard: clipboardProvider ?? () => clipboard,
        shareFiles: shares.shareFiles,
        shareText: shares.shareText,
        httpClient: client ?? rejectNetwork,
        temporaryDirectory: directory ?? tempDirectory,
      );

  http.Client respond(List<int> bytes, {int status = 200}) {
    final client = MockClient((request) async {
      requests.add(request);
      return http.Response.bytes(bytes, status);
    });
    addTearDown(client.close);
    return client;
  }

  Future<File> sourceFile(String name, List<int> bytes) async {
    final file = File(p.join(temporary.path, 'sources', name));
    await file.parent.create(recursive: true);
    return file.writeAsBytes(bytes, flush: true);
  }

  List<FileSystemEntity> exports() {
    final directory = Directory(p.join(temporary.path, 'appflowy_media'));
    return directory.existsSync() ? directory.listSync() : [];
  }

  group('MediaActionSource', () {
    test('defaults and immutable header snapshot', () {
      final headers = {'Authorization': 'Bearer fake-first'};
      final target = MediaActionSource(
        source: 'https://media.invalid/fake-file',
        name: 'report.pdf',
        httpHeaders: headers,
      );
      headers['Authorization'] = 'Bearer fake-second';

      expect(target.source, 'https://media.invalid/fake-file');
      expect(target.name, 'report.pdf');
      expect(target.isImage, isFalse);
      expect(target.shareAsLink, isFalse);
      expect(target.requireAuthentication, isFalse);
      expect(target.httpHeaders, {'Authorization': 'Bearer fake-first'});
      expect(() => target.httpHeaders.clear(), throwsUnsupportedError);
    });

    test('value equality and hash include all fields and unordered headers',
        () {
      final target = MediaActionSource(
        source: 'fake-source',
        name: 'fake-name',
        httpHeaders: {'Authorization': 'Bearer fake', 'Accept': 'image/png'},
      );
      final equal = MediaActionSource(
        source: 'fake-source',
        name: 'fake-name',
        httpHeaders: {'Accept': 'image/png', 'Authorization': 'Bearer fake'},
      );
      expect(target, equal);
      expect(target.hashCode, equal.hashCode);
      expect({target, equal}, hasLength(1));

      for (final different in [
        MediaActionSource(
          source: 'changed-source',
          name: target.name,
          httpHeaders: target.httpHeaders,
        ),
        MediaActionSource(
          source: target.source,
          name: 'changed-name',
          httpHeaders: target.httpHeaders,
        ),
        MediaActionSource(
          source: target.source,
          name: target.name,
          isImage: true,
          httpHeaders: target.httpHeaders,
        ),
        MediaActionSource(
          source: target.source,
          name: target.name,
          shareAsLink: true,
          httpHeaders: target.httpHeaders,
        ),
        MediaActionSource(
          source: target.source,
          name: target.name,
          requireAuthentication: true,
          httpHeaders: target.httpHeaders,
        ),
        MediaActionSource(
          source: target.source,
          name: target.name,
          httpHeaders: {
            'Authorization': 'Bearer fake-changed',
            'Accept': 'image/png',
          },
        ),
        MediaActionSource(source: target.source, name: target.name),
      ]) {
        expect(target, isNot(different));
      }
    });

    for (final type in [CustomImageType.local, CustomImageType.external]) {
      test('image $type never receives profile credentials', () {
        final target = MediaActionSource.image(
          ImageBlockData(url: 'https://media.invalid/picture.png', type: type),
          userProfile: _profile(),
        );
        expect(target.isImage, isTrue);
        expect(target.name, 'picture.png');
        expect(target.httpHeaders, isEmpty);
        expect(target.requireAuthentication, isFalse);
      });
    }

    test('internal factory snapshots credentials and honours the original name',
        () {
      final profile = _profile('fake-first');
      final image = ImageBlockData(
        url: 'https://cloud.invalid/fake-blob',
        type: CustomImageType.internal,
      );
      final target = MediaActionSource.image(
        image,
        userProfile: profile,
        name: 'Original photo',
      );
      profile.token = jsonEncode({'access_token': 'fake-second'});

      expect(target.name, 'Original photo');
      expect(target.requireAuthentication, isTrue);
      expect(target.httpHeaders, {'Authorization': 'Bearer fake-first'});
      expect(
        target,
        isNot(
          MediaActionSource.image(
            image,
            userProfile: profile,
            name: target.name,
          ),
        ),
      );
    });

    final invalidTokens = <String?>[
      null,
      '',
      'fake-malformed-json',
      'null',
      '[]',
      '"fake-string"',
      '{}',
      '{"access_token":null}',
      '{"access_token":42}',
      '{"access_token":""}',
      '{"access_token":"   "}',
      '{"access_token":"fake\\r\\nheader"}',
    ];
    for (var index = 0; index < invalidTokens.length; index++) {
      test(
          'invalid cloud credential case $index fails on operation, not factory',
          () async {
        final token = invalidTokens[index];
        final target = MediaActionSource.image(
          ImageBlockData(
            url: 'https://cloud.invalid/fake-blob',
            type: CustomImageType.internal,
          ),
          userProfile: token == null ? null : (UserProfilePB()..token = token),
        );
        expect(target.requireAuthentication, isTrue);
        expect(target.httpHeaders, isEmpty);
        await expectLater(service().copy(target), throwsStateError);
        await expectLater(service().share(target), throwsStateError);
        expect(requests, isEmpty);
        expect(clipboard.writes, isEmpty);
        expect(shares.files, isEmpty);
        expect(shares.links, isEmpty);
        expect(exports(), isEmpty);
      });
    }

    for (final uploadType in <FileUploadTypePB?>[
      null,
      FileUploadTypePB.LocalFile,
      FileUploadTypePB.NetworkFile,
    ]) {
      test('file factory $uploadType does not attach a bearer', () {
        final target = MediaActionSource.file(
          source: 'fake-source',
          name: 'original.txt',
          uploadType: uploadType,
          userProfile: _profile(),
          shareAsLink: true,
        );
        expect(target.httpHeaders, isEmpty);
        expect(target.requireAuthentication, isFalse);
        expect(target.shareAsLink, isTrue);
        expect(target.isImage, isFalse);
      });
    }

    test('cloud file factory carries auth and the requested image flag', () {
      final target = MediaActionSource.file(
        source: 'https://cloud.invalid/fake-blob',
        name: 'original.png',
        uploadType: FileUploadTypePB.CloudFile,
        userProfile: _profile(),
        isImage: true,
      );
      expect(target.httpHeaders, {'Authorization': 'Bearer fake-token'});
      expect(target.requireAuthentication, isTrue);
      expect(target.isImage, isTrue);
      expect(target.shareAsLink, isFalse);
    });

    test('cloud file without a profile fails closed', () async {
      final target = MediaActionSource.file(
        source: 'https://cloud.invalid/fake-blob',
        name: 'original.txt',
        uploadType: FileUploadTypePB.CloudFile,
      );
      await expectLater(service().copy(target), throwsStateError);
      await expectLater(service().share(target), throwsStateError);
      expect(requests, isEmpty);
      expect(clipboard.writes, isEmpty);
      expect(shares.files, isEmpty);
    });

    test('default service is const and shared', () {
      expect(
        identical(MediaActionService.instance, const MediaActionService()),
        isTrue,
      );
    });
  });

  group('materializeMediaFile', () {
    for (final name in [
      'spaces in name.txt',
      'hash#tail.txt',
      '100%.txt',
      'literal%20name.txt',
      'résumé 文.txt',
      'mixed # 100% 文.txt',
    ]) {
      test('reads raw local path $name without interpreting URI characters',
          () async {
        final original = await sourceFile(name, [0, 255, 17, 42]);
        final file = await materializeMediaFile(
          source: original.path,
          name: 'a different display name.txt',
          httpClient: rejectNetwork,
          temporaryDirectory: tempDirectory,
        );
        expect(file.path, original.path);
        expect(await file.readAsBytes(), [0, 255, 17, 42]);
        expect(requests, isEmpty);
        expect(exports(), isEmpty);
      });
    }

    test('reads an encoded file URI with literal percent, hash and Unicode',
        () async {
      final original = await sourceFile('photo # 100% 文.png', [1, 2, 255]);
      final file = await materializeMediaFile(
        source: original.uri.toString(),
        name: 'photo.png',
        httpClient: rejectNetwork,
        temporaryDirectory: tempDirectory,
      );
      expect(file.path, original.path);
      expect(await file.readAsBytes(), [1, 2, 255]);
      expect(requests, isEmpty);
    });

    for (final folder in ['files', 'images']) {
      test('repairs relocated storage in $folder using the existing resolver',
          () async {
        final storage = Directory(p.join(temporary.path, 'relocated'));
        final file = File(p.join(storage.path, folder, 'saved # 100% 文.bin'));
        await file.parent.create(recursive: true);
        await file.writeAsBytes([7, 9, 11]);
        getIt.registerSingleton<ApplicationDataStorage>(
          _StorageRoot(storage.path),
        );

        final materialized = await materializeMediaFile(
          source: p.join(
            temporary.path,
            'old-storage',
            folder,
            p.basename(file.path),
          ),
          name: 'Original name.bin',
          httpClient: rejectNetwork,
          temporaryDirectory: tempDirectory,
        );
        expect(materialized.path, file.path);
        expect(await materialized.readAsBytes(), [7, 9, 11]);
        expect(requests, isEmpty);
      });
    }

    test('a missing local path or file URI never goes to HTTP', () async {
      final missing = File(p.join(temporary.path, 'missing # 100%.bin'));
      for (final source in [
        missing.path,
        missing.uri.toString(),
        '',
        'fake-missing.bin',
      ]) {
        await expectLater(
          materializeMediaFile(
            source: source,
            name: 'original.bin',
            httpClient: rejectNetwork,
            temporaryDirectory: tempDirectory,
          ),
          throwsA(isA<FileSystemException>()),
        );
      }
      expect(requests, isEmpty);
      expect(exports(), isEmpty);
    });

    for (final source in [
      'http:/fake-file',
      'https:///fake-file',
      'https://',
      'https://fake:fake@media.invalid/file',
    ]) {
      test('refuses invalid HTTP authority $source before any request',
          () async {
        await expectLater(
          materializeMediaFile(
            source: source,
            name: 'original.bin',
            httpClient: rejectNetwork,
            temporaryDirectory: tempDirectory,
          ),
          throwsA(isA<HttpException>()),
        );
        expect(requests, isEmpty);
        expect(exports(), isEmpty);
      });
    }

    for (final source in [
      'ftp://media.invalid/file',
      'data:image/png;base64,fake',
    ]) {
      test('never fetches unsupported scheme $source', () async {
        await expectLater(
          materializeMediaFile(
            source: source,
            name: 'original.bin',
            httpClient: rejectNetwork,
            temporaryDirectory: tempDirectory,
          ),
          throwsA(isA<FileSystemException>()),
        );
        expect(requests, isEmpty);
      });
    }

    for (final status in [200, 201, 206, 299]) {
      test('materializes HTTP $status bytes under the provided basename',
          () async {
        final file = await materializeMediaFile(
          source: 'https://media.invalid/fake-blob?fake=query',
          name: 'Original # 100% 文.bin',
          httpClient: respond([0, 255, 42], status: status),
          temporaryDirectory: tempDirectory,
        );
        expect(await file.readAsBytes(), [0, 255, 42]);
        expect(p.basename(file.path), 'Original # 100% 文.bin');
        expect(
          p.dirname(file.parent.path),
          p.join(temporary.path, 'appflowy_media'),
        );
        expect(requests.single.method, 'GET');
      });
    }

    test('snapshots mutable HTTP headers before the first await', () async {
      final headers = {'Authorization': 'Bearer fake-first'};
      final future = materializeMediaFile(
        source: 'https://cloud.invalid/fake-file',
        name: 'file.bin',
        httpHeaders: headers,
        httpClient: respond([1]),
        temporaryDirectory: tempDirectory,
      );
      headers['Authorization'] = 'Bearer fake-second';
      await future;
      expect(requests.single.headers['authorization'], 'Bearer fake-first');
    });

    for (final status in [302, 400, 401, 403, 404, 500]) {
      test('HTTP $status leaves no export and exposes only the status',
          () async {
        await expectLater(
          materializeMediaFile(
            source: 'https://cloud.invalid/fake-file',
            name: 'file.bin',
            httpHeaders: {'Authorization': 'Bearer fake-token'},
            httpClient:
                respond(utf8.encode('fake response body'), status: status),
            temporaryDirectory: tempDirectory,
          ),
          throwsA(
            isA<HttpException>().having(
              (error) => error.message,
              'message',
              'Unable to download media ($status).',
            ),
          ),
        );
        expect(exports(), isEmpty);
      });
    }

    test('concurrent same-name downloads never overwrite each other', () async {
      final firstEntered = Completer<void>();
      final secondEntered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      final client = MockClient((request) async {
        final first = request.url.path.endsWith('first');
        (first ? firstEntered : secondEntered).complete();
        await release.future;
        return http.Response.bytes(first ? [1, 2] : [3, 4], 200);
      });
      addTearDown(client.close);
      final pending = Future.wait([
        for (final suffix in ['first', 'second'])
          materializeMediaFile(
            source: 'https://media.invalid/$suffix',
            name: 'same.bin',
            httpClient: client,
            temporaryDirectory: tempDirectory,
          ),
      ]);
      await Future.wait([firstEntered.future, secondEntered.future]);
      release.complete();
      final files = await pending;

      expect(files[0].path, isNot(files[1].path));
      expect(
        files.map((file) => p.basename(file.path)),
        ['same.bin', 'same.bin'],
      );
      expect(await files[0].readAsBytes(), [1, 2]);
      expect(await files[1].readAsBytes(), [3, 4]);
      expect(exports(), hasLength(2));
    });

    final names = <String, String>{
      '': 'from-url.bin',
      '.': 'media',
      '..': 'media',
      '../../': 'media',
      r'..\..\NUL.txt': '_NUL.txt',
      '../../CON': '_CON',
      r'C:\fake\..\LPT1.pdf': '_LPT1.pdf',
      'folder/sub\\x?.txt... ': 'x_.txt',
      'control\x00\x01\x1f\x7f.txt': 'control____.txt',
      'part..part.bin': 'part_part.bin',
      'dir/ résumé # 100%.txt ': 'résumé # 100%.txt',
      'aux.photo.png': '_aux.photo.png',
      'COM¹.txt': '_COM¹.txt',
      'CONOUT\$.txt': '_CONOUT\$.txt',
      'file:stream.bin': 'file_stream.bin',
    };
    var caseNumber = 0;
    for (final entry in names.entries) {
      test('sanitizes cross-platform filename case ${caseNumber++}', () async {
        final file = await materializeMediaFile(
          source: 'https://media.invalid/from-url.bin?fake=query#fragment',
          name: entry.key,
          httpClient: respond([42]),
          temporaryDirectory: tempDirectory,
        );
        expect(p.basename(file.path), entry.value);
        expect(
          p.isWithin(p.join(temporary.path, 'appflowy_media'), file.path),
          isTrue,
        );
        expect(file.parent.listSync().single.path, file.path);
        expect(await file.readAsBytes(), [42]);
      });
    }

    test('an empty name and URL path still produce a nonempty safe filename',
        () async {
      final file = await materializeMediaFile(
        source: 'https://media.invalid/',
        name: '',
        httpClient: respond([42]),
        temporaryDirectory: tempDirectory,
      );
      expect(p.basename(file.path), 'media');
      expect(await file.readAsBytes(), [42]);
    });

    test(
        'write failure cleans only its own export, preserving successful siblings',
        () async {
      final successful = await materializeMediaFile(
        source: 'https://media.invalid/first',
        name: 'kept.bin',
        httpClient: respond([7]),
        temporaryDirectory: tempDirectory,
      );
      await expectLater(
        materializeMediaFile(
          source: 'https://media.invalid/second',
          name: '${'x' * 512}.bin',
          httpClient: respond([9]),
          temporaryDirectory: tempDirectory,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(exports().map((entry) => entry.path), [successful.parent.path]);
      expect(await successful.readAsBytes(), [7]);
    });
  });

  group('copy', () {
    for (final isImage in [false, true]) {
      test(
        'Windows ${isImage ? 'image' : 'file'} encodes CF_HDROP and Unicode text',
        () async {
          final previousPlatform = debugDefaultTargetPlatformOverride;
          debugDefaultTargetPlatformOverride = TargetPlatform.windows;
          try {
            final bytes = isImage ? await _png() : Uint8List.fromList([1, 255]);
            final original = await sourceFile('fake-uuid', bytes);
            final name = 'Original # 100% 文.${isImage ? 'png' : 'bin'}';
            await service().copy(
              MediaActionSource(
                source: original.path,
                name: name,
                isImage: isImage,
              ),
            );
            final data =
                await _ClipboardData.read(clipboard.writes.single.single);
            expect(data.values.keys, [
              if (isImage) 'PNG',
              'NativeShell_CF_15',
              'NativeShell_CF_13',
            ]);
            final path = data.values['NativeShell_CF_15'] as String;
            expect(data.values['NativeShell_CF_13'], path);
            expect(p.basename(path), name);
            expect(await data.decode(Formats.fileUri), File(path).uri);
            expect(await File(path).readAsBytes(), bytes);
            if (isImage) {
              expect(data.values['PNG'], bytes);
            }
          } finally {
            debugDefaultTargetPlatformOverride = previousPlatform;
          }
        },
        skip: !Platform.isWindows,
      );
    }

    test('generic files provide real file URI and path, not a web URL',
        () async {
      final target = MediaActionSource(
        source: 'https://media.invalid/fake-download',
        name: 'Original document.txt',
      );
      await service(client: respond([17, 33, 255])).copy(target);
      final item = clipboard.writes.single.single;
      final data = await _ClipboardData.read(item);
      final uri = await data.decode(Formats.fileUri);
      final path = await data.decode(Formats.plainText);

      expect(uri, isNotNull);
      expect(uri!.isScheme('file'), isTrue);
      expect(path, File.fromUri(uri).path);
      expect(await File.fromUri(uri).readAsBytes(), [17, 33, 255]);
      expect(item.suggestedName, 'Original document.txt');
      expect(item.data, hasLength(2));
      expect(data.values.values, isNot(contains(target.source)));
    });

    test('PNG image supplies original full-resolution pixels and a file URI',
        () async {
      final png = await _png();
      final original = await sourceFile('fake-uuid', png);
      await service().copy(
        MediaActionSource(
          source: original.path,
          name: 'Original photo',
          isImage: true,
        ),
      );
      final item = clipboard.writes.single.single;
      final data = await _ClipboardData.read(item);
      final bytes = data.values[Formats.png.providerFormat] as Uint8List;
      final file = File.fromUri((await data.decode(Formats.fileUri))!);

      expect(item.data, hasLength(3));
      expect(data.values.keys.first, Formats.png.providerFormat);
      expect(bytes, png);
      await _expectImage(
        bytes,
        width: 37,
        height: 23,
        firstPixel: [12, 34, 56, 255],
      );
      expect(file.path, isNot(original.path));
      expect(p.basename(file.path), 'Original photo.png');
      expect(await file.readAsBytes(), png);
      expect(await original.readAsBytes(), png);
    });

    test('JPEG clipboard and share preserve original bytes and filename',
        () async {
      final jpeg = await File(
        p.join('assets', 'test', 'images', 'sample.jpeg'),
      ).readAsBytes();
      final original = await sourceFile('fake-jpeg-uuid', jpeg);
      final target = MediaActionSource(
        source: original.path,
        name: 'Original photo.jpeg',
        isImage: true,
      );
      await service().copy(target);
      await service().share(target);
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      expect(data.values[Formats.jpeg.providerFormat], jpeg);
      expect(data.values.containsKey(Formats.png.providerFormat), isFalse);
      final copied = File.fromUri((await data.decode(Formats.fileUri))!);
      expect(p.basename(copied.path), target.name);
      expect(await copied.readAsBytes(), jpeg);
      final shared = shares.files.single.files.single;
      expect(shared.path, isNot(copied.path));
      expect(p.basename(shared.path), target.name);
      expect(shared.mimeType, 'image/jpeg');
      expect(await shared.readAsBytes(), jpeg);
    });

    test('GIF clipboard format and file preserve the original payload',
        () async {
      final gif = base64Decode(
        'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
      );
      final original = await sourceFile('fake-gif', gif);
      await service().copy(
        MediaActionSource(
          source: original.path,
          name: 'animation',
          isImage: true,
        ),
      );
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      expect(data.values[Formats.gif.providerFormat], gif);
      expect(data.values.containsKey(Formats.png.providerFormat), isFalse);
      final file = File.fromUri((await data.decode(Formats.fileUri))!);
      expect(p.basename(file.path), 'animation.gif');
      expect(await file.readAsBytes(), gif);
    });

    test('BMP is PNG on the clipboard but stays the original file format',
        () async {
      final bmp = _bmp();
      final original = await sourceFile('fake-bmp', bmp);
      await service().copy(
        MediaActionSource(
          source: original.path,
          name: 'Original bitmap',
          isImage: true,
        ),
      );
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      final png = data.values[Formats.png.providerFormat] as Uint8List;
      await _expectImage(
        png,
        width: 2,
        height: 1,
        firstPixel: [255, 0, 0, 255],
      );
      final file = File.fromUri((await data.decode(Formats.fileUri))!);
      expect(p.basename(file.path), 'Original bitmap.bmp');
      expect(await file.readAsBytes(), bmp);
    });

    test('unknown but decodable image format gets a PNG file as well',
        () async {
      // A real 8x2 WBMP; not recognized by the installed MIME sniffer.
      final original = await sourceFile('fake-wbmp', [0, 0, 8, 2, 0xaa, 0x55]);
      await service().copy(
        MediaActionSource(
          source: original.path,
          name: 'Unknown picture',
          isImage: true,
        ),
      );
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      final png = data.values[Formats.png.providerFormat] as Uint8List;
      await _expectImage(png, width: 8, height: 2);
      final file = File.fromUri((await data.decode(Formats.fileUri))!);
      expect(p.basename(file.path), 'Unknown picture.png');
      expect(await file.readAsBytes(), png);
      expect(await original.readAsBytes(), [0, 0, 8, 2, 0xaa, 0x55]);
      expect(file.parent.listSync(), hasLength(1));
    });

    for (final bytes in <List<int>>[
      [],
      [0x89, 0x50, 0x4e, 0x47],
      utf8.encode('<html>fake sign in</html>'),
    ]) {
      test(
          'invalid image of ${bytes.length} bytes never writes an empty clipboard',
          () async {
        final original = await sourceFile('bad-image', bytes);
        await expectLater(
          service().copy(
            MediaActionSource(
              source: original.path,
              name: 'image.png',
              isImage: true,
            ),
          ),
          throwsA(anything),
        );
        expect(clipboard.writes, isEmpty);
        expect(exports(), isEmpty);
        expect(await original.readAsBytes(), bytes);
      });
    }

    test('unavailable clipboard throws before reading or fetching anything',
        () async {
      await expectLater(
        service(clipboardProvider: () => null).copy(
          MediaActionSource(
            source: 'https://media.invalid/file',
            name: 'file.bin',
          ),
        ),
        throwsUnsupportedError,
      );
      expect(requests, isEmpty);
      expect(clipboard.writes, isEmpty);
      expect(exports(), isEmpty);
    });

    test('a local read failure propagates and removes the failed export',
        () async {
      final original = await sourceFile('read-failure.bin', [42]);
      final actions = service(
        directory: () async {
          await original.delete();
          return temporary;
        },
      );
      await expectLater(
        actions
            .copy(MediaActionSource(source: original.path, name: 'copy.bin')),
        throwsA(isA<FileSystemException>()),
      );
      expect(clipboard.writes, isEmpty);
      expect(exports(), isEmpty);
    });

    test(
        'awaits clipboard completion and retains a snapshot when source changes',
        () async {
      final first = await sourceFile('first.bin', [1, 2]);
      final second = await sourceFile('second.bin', [3, 4]);
      final entered = Completer<void>();
      final release = Completer<void>();
      addTearDown(() {
        if (!release.isCompleted) release.complete();
      });
      clipboard.onWrite = (_) async {
        entered.complete();
        await release.future;
      };
      var target = MediaActionSource(source: first.path, name: 'First.bin');
      var completed = false;
      final pending = service().copy(target).then((_) {
        completed = true;
      });
      target = MediaActionSource(source: second.path, name: 'Second.bin');
      await entered.future;
      expect(completed, isFalse);
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      final file = File.fromUri((await data.decode(Formats.fileUri))!);
      await first.writeAsBytes([9, 9]);
      release.complete();
      await pending;

      expect(completed, isTrue);
      expect(p.basename(file.path), 'First.bin');
      expect(await file.readAsBytes(), [1, 2]);
      expect(target.source, second.path);
      expect(await second.readAsBytes(), [3, 4]);
    });

    test('clipboard failure is not masked or converted to a link fallback',
        () async {
      final failure = StateError('fake clipboard failure');
      clipboard.onWrite = (_) async {
        throw failure;
      };
      final original = await sourceFile('uuid.bin', [42]);
      await expectLater(
        service().copy(
          MediaActionSource(source: original.path, name: 'original.bin'),
        ),
        throwsA(same(failure)),
      );
      expect(clipboard.writes, hasLength(1));
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      final file = File.fromUri((await data.decode(Formats.fileUri))!);
      // A native consumer may have accepted the item before reporting an error.
      expect(await file.readAsBytes(), [42]);
      expect(shares.links, isEmpty);
    });

    test('an explicitly requested public link is text only', () async {
      const source = 'https://media.invalid/public-link';
      await service().copy(
        MediaActionSource(
          source: source,
          name: 'Link',
          shareAsLink: true,
        ),
      );
      final item = clipboard.writes.single.single;
      final data = await _ClipboardData.read(item);
      expect(item.data, hasLength(1));
      expect(await data.decode(Formats.plainText), source);
      expect(requests, isEmpty);
      expect(exports(), isEmpty);
    });

    test('concurrent same-name copies keep both file snapshots alive',
        () async {
      final first = await sourceFile('first.bin', [1]);
      final second = await sourceFile('second.bin', [2]);
      await Future.wait([
        service().copy(MediaActionSource(source: first.path, name: 'same.bin')),
        service()
            .copy(MediaActionSource(source: second.path, name: 'same.bin')),
      ]);
      final paths = <String>[];
      final contents = <int>[];
      for (final write in clipboard.writes) {
        final data = await _ClipboardData.read(write.single);
        final file = File.fromUri((await data.decode(Formats.fileUri))!);
        paths.add(file.path);
        contents.add((await file.readAsBytes()).single);
      }
      expect(paths.toSet(), hasLength(2));
      expect(contents, unorderedEquals([1, 2]));
      expect(paths.map(p.basename), everyElement('same.bin'));
    });
  });

  group('share', () {
    test('shares a UUID local file under its physical original name and origin',
        () async {
      final original = await sourceFile('fake-uuid.bin', [0, 255, 42]);
      const origin = ui.Rect.fromLTWH(12, 24, 36, 48);
      await service().share(
        MediaActionSource(
          source: original.uri.toString(),
          name: 'My report # 100% 文.pdf',
        ),
        sharePositionOrigin: origin,
      );
      final call = shares.files.single;
      final file = call.files.single;
      expect(file.path, isNot(original.path));
      expect(p.basename(file.path), 'My report # 100% 文.pdf');
      expect(call.names, ['My report # 100% 文.pdf']);
      expect(call.origin, origin);
      expect(file.mimeType, 'application/pdf');
      expect(await file.readAsBytes(), [0, 255, 42]);
      expect(await original.readAsBytes(), [0, 255, 42]);
      expect(shares.links, isEmpty);
    });

    for (final name in [
      'Original image',
      'Original image.jpg',
      'Original image.PNG',
    ]) {
      test('sniffs extensionless PNG bytes when display name is $name',
          () async {
        final png = await _png();
        final original = await sourceFile('fake-uuid', png);
        await service().share(
          MediaActionSource.image(
            ImageBlockData(url: original.path, type: CustomImageType.local),
            name: name,
          ),
        );
        final file = shares.files.single.files.single;
        expect(
          p.basename(file.path),
          name.endsWith('.PNG') ? name : 'Original image.png',
        );
        expect(file.mimeType, 'image/png');
        expect(await file.readAsBytes(), png);
      });
    }

    test('preserves BMP bytes and detects the original file format', () async {
      final bmp = _bmp();
      final original = await sourceFile('fake-uuid', bmp);
      await service().share(
        MediaActionSource(
          source: original.path,
          name: 'Bitmap',
          isImage: true,
        ),
      );
      final file = shares.files.single.files.single;
      expect(p.basename(file.path), 'Bitmap.bmp');
      expect(file.mimeType, 'image/bmp');
      expect(await file.readAsBytes(), bmp);
    });

    test('encodes a decodable unknown format to a correctly named PNG',
        () async {
      final original = await sourceFile('fake-wbmp', [0, 0, 8, 2, 0xaa, 0x55]);
      await service().share(
        MediaActionSource(
          source: original.path,
          name: 'Picture',
          isImage: true,
        ),
      );
      final file = shares.files.single.files.single;
      expect(p.basename(file.path), 'Picture.png');
      expect(file.mimeType, 'image/png');
      await _expectImage(await file.readAsBytes(), width: 8, height: 2);
    });

    test('unavailable is a handoff result, not failure or a reason to delete',
        () async {
      final original = await sourceFile('fake-uuid', [7, 8, 9]);
      await service()
          .share(MediaActionSource(source: original.path, name: 'Shared.bin'));
      await original.delete();
      expect(await shares.files.single.files.single.readAsBytes(), [7, 8, 9]);
      expect(exports(), hasLength(1));
      expect(shares.links, isEmpty);
    });

    test('awaits the share handoff, with the file alive during and after it',
        () async {
      final entered = Completer<void>();
      final release = Completer<ShareResult>();
      addTearDown(() {
        if (!release.isCompleted) release.complete(ShareResult.unavailable);
      });
      shares.onFiles = (_) {
        entered.complete();
        return release.future;
      };
      final original = await sourceFile('fake-uuid', [13, 17]);
      var completed = false;
      final pending = service()
          .share(
        MediaActionSource(source: original.path, name: 'Shared.bin'),
      )
          .then((_) {
        completed = true;
      });
      await entered.future;
      expect(completed, isFalse);
      final file = shares.files.single.files.single;
      expect(await file.readAsBytes(), [13, 17]);
      release.complete(ShareResult.unavailable);
      await pending;
      expect(completed, isTrue);
      expect(await file.readAsBytes(), [13, 17]);
    });

    test('share failure propagates unchanged without text fallback', () async {
      final failure =
          PlatformException(code: 'fake-share-error', message: 'fake failure');
      shares.onFiles = (_) async {
        throw failure;
      };
      final original = await sourceFile('fake-uuid', [42]);
      await expectLater(
        service().share(
          MediaActionSource(source: original.path, name: 'Original.bin'),
        ),
        throwsA(same(failure)),
      );
      expect(shares.files, hasLength(1));
      expect(shares.links, isEmpty);
      expect(await shares.files.single.files.single.readAsBytes(), [42]);
    });

    test('default Share.shareXFiles receives only a real file and the origin',
        () async {
      const channel = MethodChannel('dev.fluttercommunity.plus/share');
      final calls = <MethodCall>[];
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return 'dev.fluttercommunity.plus/share/unavailable';
      });
      addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
      final png = await _png();
      final actions = MediaActionService(
        clipboard: () => clipboard,
        httpClient: respond(png),
        temporaryDirectory: tempDirectory,
      );
      const origin = ui.Rect.fromLTWH(10, 20, 30, 40);
      await actions.share(
        MediaActionSource.image(
          ImageBlockData(
            url: 'https://cloud.invalid/fake-blob',
            type: CustomImageType.internal,
          ),
          userProfile: _profile(),
          name: 'Original image',
        ),
        sharePositionOrigin: origin,
      );
      expect(calls.single.method, 'shareFiles');
      final args = calls.single.arguments as Map;
      expect(args.keys.toSet(), {
        'paths',
        'mimeTypes',
        'originX',
        'originY',
        'originWidth',
        'originHeight',
      });
      final file = File((args['paths'] as List).single as String);
      expect(p.basename(file.path), 'Original image.png');
      expect(await file.readAsBytes(), png);
      expect(args['mimeTypes'], ['image/png']);
      expect(args['originX'], 10);
      expect(args['originY'], 20);
      expect(args['originWidth'], 30);
      expect(args['originHeight'], 40);
      expect(requests.single.headers['authorization'], 'Bearer fake-token');
      expect(args.toString(), isNot(contains('fake-token')));
      expect(args.toString(), isNot(contains('cloud.invalid')));
    });

    test('explicit public link sharing carries position but never materializes',
        () async {
      const origin = ui.Rect.fromLTWH(1, 2, 3, 4);
      const source = 'https://media.invalid/public-link';
      await service().share(
        MediaActionSource(source: source, name: 'Link', shareAsLink: true),
        sharePositionOrigin: origin,
      );
      expect(shares.links.single, (source: source, origin: origin));
      expect(shares.files, isEmpty);
      expect(requests, isEmpty);
      expect(exports(), isEmpty);
    });
  });

  group('operation guards and authentication', () {
    test(
        'external image HTTP never receives a bearer despite a signed-in profile',
        () async {
      final png = await _png();
      final target = MediaActionSource.image(
        ImageBlockData(
          url: 'https://external.invalid/picture',
          type: CustomImageType.external,
        ),
        userProfile: _profile(),
      );
      final actions = service(client: respond(png));
      await actions.copy(target);
      await actions.share(target);
      expect(requests, hasLength(2));
      expect(
        requests.every(
          (request) => !request.headers.containsKey('authorization'),
        ),
        isTrue,
      );
    });

    test(
        'internal image uses snapshotted auth and never puts it in clipboard data',
        () async {
      final profile = _profile('fake-first');
      final target = MediaActionSource.image(
        ImageBlockData(
          url: 'https://cloud.invalid/fake-blob',
          type: CustomImageType.internal,
        ),
        userProfile: profile,
        name: 'Photo',
      );
      final png = await _png();
      final pending = service(client: respond(png)).copy(target);
      profile.token = jsonEncode({'access_token': 'fake-second'});
      await pending;
      expect(requests.single.headers['authorization'], 'Bearer fake-first');
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      final strings = data.values.values.whereType<String>().join(' ');
      expect(strings, isNot(contains('fake-first')));
      expect(strings, isNot(contains('cloud.invalid')));
    });

    test('HTTP 401 fails both actions without clipboard or link fallback',
        () async {
      final target = MediaActionSource.file(
        source: 'https://cloud.invalid/fake-file',
        name: 'Private.bin',
        uploadType: FileUploadTypePB.CloudFile,
        userProfile: _profile(),
      );
      final actions = service(client: respond([1], status: 401));
      await expectLater(actions.copy(target), throwsA(isA<HttpException>()));
      await expectLater(actions.share(target), throwsA(isA<HttpException>()));
      expect(requests, hasLength(2));
      expect(clipboard.writes, isEmpty);
      expect(shares.files, isEmpty);
      expect(shares.links, isEmpty);
      expect(exports(), isEmpty);
    });

    test('network exceptions are not masked and never produce an empty handoff',
        () async {
      final failure = http.ClientException('fake network failure');
      final client = MockClient((_) async {
        throw failure;
      });
      addTearDown(client.close);
      final actions = service(client: client);
      final target = MediaActionSource(
        source: 'https://media.invalid/file',
        name: 'File.bin',
      );
      await expectLater(actions.copy(target), throwsA(same(failure)));
      await expectLater(actions.share(target), throwsA(same(failure)));
      expect(clipboard.writes, isEmpty);
      expect(shares.files, isEmpty);
      expect(shares.links, isEmpty);
      expect(exports(), isEmpty);
    });

    test('missing local media fails both actions without handing out its path',
        () async {
      final target = MediaActionSource(
        source: p.join(temporary.path, 'fake-missing.bin'),
        name: 'File.bin',
      );
      await expectLater(
        service().copy(target),
        throwsA(isA<FileSystemException>()),
      );
      await expectLater(
        service().share(target),
        throwsA(isA<FileSystemException>()),
      );
      expect(requests, isEmpty);
      expect(clipboard.writes, isEmpty);
      expect(shares.files, isEmpty);
    });

    test('private media cannot be exported as an authenticated URL', () async {
      for (final target in [
        MediaActionSource.file(
          source: 'https://cloud.invalid/fake-file',
          name: 'Private.bin',
          uploadType: FileUploadTypePB.CloudFile,
          userProfile: _profile(),
          shareAsLink: true,
        ),
        MediaActionSource(
          source: 'https://cloud.invalid/fake-file',
          name: 'Private.bin',
          shareAsLink: true,
          httpHeaders: {'Authorization': 'Bearer fake-token'},
        ),
      ]) {
        await expectLater(service().copy(target), throwsStateError);
        await expectLater(service().share(target), throwsStateError);
      }
      expect(requests, isEmpty);
      expect(clipboard.writes, isEmpty);
      expect(shares.files, isEmpty);
      expect(shares.links, isEmpty);
    });

    test(
        'empty sources fail before native calls, including legacy entry points',
        () async {
      final target =
          MediaActionSource(source: '  ', name: 'Empty', shareAsLink: true);
      await expectLater(service().copy(target), throwsArgumentError);
      await expectLater(service().share(target), throwsArgumentError);
      await expectLater(
        copyMedia(source: '', name: 'Empty'),
        throwsArgumentError,
      );
      await expectLater(
        copyMedia(source: '', name: 'Empty', asImage: true),
        throwsArgumentError,
      );
      await expectLater(
        shareMedia(source: '', name: 'Empty'),
        throwsArgumentError,
      );
      await expectLater(
        downloadMedia(source: '', name: 'Empty'),
        throwsA(isA<FileSystemException>()),
      );
      expect(clipboard.writes, isEmpty);
      expect(shares.files, isEmpty);
      expect(shares.links, isEmpty);
    });

    test('image factory also benefits from relocated local storage', () async {
      final png = await _png();
      final storage = Directory(p.join(temporary.path, 'relocated'));
      final saved = File(p.join(storage.path, 'images', 'fake-image'));
      await saved.parent.create(recursive: true);
      await saved.writeAsBytes(png);
      getIt.registerSingleton<ApplicationDataStorage>(
        _StorageRoot(storage.path),
      );
      final target = MediaActionSource.image(
        ImageBlockData(
          url: p.join(temporary.path, 'old-storage', 'images', 'fake-image'),
          type: CustomImageType.local,
        ),
        userProfile: _profile(),
        name: 'Original image',
      );
      await service().copy(target);
      await service().share(target);
      final data = await _ClipboardData.read(clipboard.writes.single.single);
      expect(data.values[Formats.png.providerFormat], png);
      expect(await shares.files.single.files.single.readAsBytes(), png);
      expect(target.httpHeaders, isEmpty);
      expect(requests, isEmpty);
      expect(await saved.readAsBytes(), png);
    });
  });
}

UserProfilePB _profile([String token = 'fake-token']) =>
    UserProfilePB()..token = jsonEncode({'access_token': token});

class _StorageRoot extends ApplicationDataStorage {
  _StorageRoot(this.path);

  final String path;

  @override
  Future<String> getPath() async => path;
}

class _RecordingClipboard implements ClipboardWriter {
  final writes = <List<DataWriterItem>>[];
  Future<void> Function(List<DataWriterItem>)? onWrite;

  @override
  Future<void> write(Iterable<DataWriterItem> items) async {
    final snapshot = items.toList();
    writes.add(snapshot);
    await onWrite?.call(snapshot);
  }
}

typedef _FileHandoff = ({
  List<XFile> files,
  List<String>? names,
  ui.Rect? origin,
});

class _RecordingShare {
  final files = <_FileHandoff>[];
  final links = <({String source, ui.Rect? origin})>[];
  Future<ShareResult> Function(_FileHandoff)? onFiles;

  Future<ShareResult> shareFiles(
    List<XFile> values, {
    ui.Rect? sharePositionOrigin,
    List<String>? fileNameOverrides,
  }) async {
    final call = (
      files: List<XFile>.of(values),
      names:
          fileNameOverrides == null ? null : List<String>.of(fileNameOverrides),
      origin: sharePositionOrigin,
    );
    files.add(call);
    final callback = onFiles;
    if (callback != null) {
      return callback(call);
    }
    return ShareResult.unavailable;
  }

  Future<ShareResult> shareText(
    String text, {
    ui.Rect? sharePositionOrigin,
  }) async {
    links.add((source: text, origin: sharePositionOrigin));
    return ShareResult.unavailable;
  }
}

/// Inspect the actual eagerly encoded providers, without registering native
/// handles or touching the OS clipboard. Decode URIs with the package's codec.
class _ClipboardData implements PlatformDataProvider {
  _ClipboardData(this.values);

  static Future<_ClipboardData> read(DataWriterItem item) async {
    final values = <String, Object?>{};
    for (final pending in item.data) {
      final encoded = await pending;
      for (final representation in encoded.representations) {
        final serialized = representation.serialize() as Map;
        expect(serialized['type'], 'simple');
        values[representation.format] = serialized['data'];
      }
    }
    return _ClipboardData(values);
  }

  final Map<String, Object?> values;

  Future<T?> decode<T extends Object>(ValueFormat<T> format) =>
      format.codec.decode(
        this,
        format.codec.decodingFormats.firstWhere(values.containsKey),
      );

  @override
  List<String> getAllFormats() => values.keys.toList();

  @override
  Future<Object?> getData(String format) async => values[format];
}

Future<Uint8List> _png() async {
  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawRect(
    const ui.Rect.fromLTWH(0, 0, 37, 23),
    ui.Paint()..color = const ui.Color.fromARGB(255, 12, 34, 56),
  );
  final picture = recorder.endRecording();
  final image = await picture.toImage(37, 23);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
    picture.dispose();
  }
}

Uint8List _bmp() {
  // A real 2x1, 24-bit BMP containing a red and a blue pixel plus row padding.
  final bytes = Uint8List(62);
  final data = ByteData.sublistView(bytes);
  data
    ..setUint16(0, 0x4d42, Endian.little)
    ..setUint32(2, bytes.length, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, 2, Endian.little)
    ..setInt32(22, 1, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, 8, Endian.little);
  bytes.setAll(54, [0, 0, 255, 255, 0, 0]);
  return bytes;
}

Future<void> _expectImage(
  Uint8List bytes, {
  required int width,
  required int height,
  List<int>? firstPixel,
}) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final image = (await codec.getNextFrame()).image;
    try {
      expect(image.width, width);
      expect(image.height, height);
      if (firstPixel != null) {
        final data = await image.toByteData();
        expect(data!.buffer.asUint8List().take(4), firstPixel);
      }
    } finally {
      image.dispose();
    }
  } finally {
    codec.dispose();
  }
}
