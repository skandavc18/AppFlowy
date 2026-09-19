import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_attachments.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// These tests never initialize AppFlowy, authentication, a backend, a native
// clipboard, or path_provider. Only the storage location/upload IO boundary is
// substituted; preparation, local copying, nodes, transactions and undo are real.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AttachmentPasteService', () {
    late Directory sandbox;
    late Directory originals;
    late Directory managed;
    late Directory temporary;
    late _TestDataStorage storage;
    late AttachmentPasteService service;
    late int temporaryRequests;

    setUp(() async {
      sandbox =
          await Directory.systemTemp.createTemp('paste_attachments_test_');
      originals = await Directory(p.join(sandbox.path, 'originals')).create();
      managed = await Directory(p.join(sandbox.path, 'managed')).create();
      temporary = await Directory(p.join(sandbox.path, 'temporary')).create();
      storage = _TestDataStorage(managed.path);
      getIt.pushNewScope();
      getIt.registerSingleton<ApplicationDataStorage>(storage);
      temporaryRequests = 0;
      service = AttachmentPasteService(
        temporaryDirectory: () async {
          temporaryRequests++;
          return temporary;
        },
      );
    });

    tearDown(() async {
      try {
        await getIt.popScope();
      } finally {
        if (await sandbox.exists()) {
          await sandbox.delete(recursive: true);
        }
      }
    });

    Future<List<File>> writeSamples(List<_Sample> samples) async {
      final files = <File>[];
      for (final sample in samples) {
        files.add(await _writeFile(originals, sample.name, sample.bytes));
      }
      return files;
    }

    Future<PreparedAttachments> prepareFiles(
      List<File> files, {
      AttachmentPasteService? using,
      String documentId = 'paste-test-document',
      bool isLocalMode = true,
    }) =>
        (using ?? service).prepare(
          ClipboardServiceData(files: files.map((file) => file.uri).toList()),
          documentId: documentId,
          isLocalMode: isLocalMode,
        );

    AttachmentPasteService withSaver(AttachmentFileSaver saver) =>
        AttachmentPasteService(
          saveFile: saver,
          temporaryDirectory: service.temporaryDirectory,
        );

    Future<void> expectNoStorageWrites() async {
      expect(storage.pathRequests, 0);
      expect(temporaryRequests, 0);
      expect(await managed.list().toList(), isEmpty);
      expect(await temporary.list().toList(), isEmpty);
    }

    test(
        'default local saver imports a mixed batch in order, not its fallbacks',
        () async {
      final samples = _mixedSamples();
      final files = await writeSamples(samples);
      final prepared = await service.prepare(
        ClipboardServiceData(
          files: files.map((file) => file.uri).toList(),
          image: ('png', _pngBytes),
          plainText: files.first.path,
          html: '<img src="clipboard-thumbnail.png">',
        ),
        // A local import must not require a logged-in document identity.
        documentId: '',
        isLocalMode: true,
      );

      expect(prepared.nodes, hasLength(samples.length));
      expect(temporaryRequests, 0);
      final copies = <File>[];
      for (var i = 0; i < samples.length; i++) {
        copies.add(
          await _expectLocalCopy(
            prepared.nodes[i],
            files[i],
            samples[i],
            managed,
          ),
        );
      }
      expect((await _filesUnder(managed)).length, samples.length);

      // Exercise the real preparation -> real editor insertion boundary too.
      final editor = _editor([paragraphNode()]);
      await _expectInsertion(
        editor,
        prepared.nodes,
        expected: [...prepared.nodes, paragraphNode()],
        after: _caret([samples.length]),
      );

      // Editing the source later cannot edit the imported attachment.
      await files.first.writeAsBytes(_binaryBytes, flush: true);
      expect(await copies.first.readAsBytes(), orderedEquals(_pngBytes));
      expect(await temporary.list().toList(), isEmpty);
    });

    test('recognizes uppercase/JFIF names and header MIME without an extension',
        () async {
      final samples = <_Sample>[
        (name: 'UPPER.JPG', bytes: _binaryBytes, isImage: true),
        (name: 'scan.JFIF', bytes: _binaryBytes, isImage: true),
        (name: 'camera export', bytes: _jpegBytes, isImage: true),
        (name: 'renamed.dat', bytes: _pngBytes, isImage: true),
        // A recognized non-image header wins over a misleading image suffix.
        (name: 'actually a PDF.JPG', bytes: _pdfBytes, isImage: false),
      ];
      final files = await writeSamples(samples);
      final prepared = await prepareFiles(files);

      expect(prepared.nodes, hasLength(samples.length));
      for (var i = 0; i < samples.length; i++) {
        await _expectLocalCopy(
          prepared.nodes[i],
          files[i],
          samples[i],
          managed,
        );
      }
    });

    test('same basenames and repeated pastes never overwrite existing copies',
        () async {
      final samples = <_Sample>[
        (name: 'left/photo.png', bytes: _pngBytes, isImage: true),
        (name: 'right/photo.png', bytes: [..._pngBytes, 7], isImage: true),
        (name: 'left/report.pdf', bytes: _pdfBytes, isImage: false),
        (
          name: 'right/report.pdf',
          bytes: utf8.encode('%PDF-1.7\nDifferent report\n%%EOF'),
          isImage: false,
        ),
      ];
      final existingImage =
          await _writeFile(managed, 'images/photo.png', [3, 4]);
      final existingFile =
          await _writeFile(managed, 'files/report.pdf', [5, 6]);
      final files = await writeSamples(samples);
      final first = await prepareFiles(files);
      final second = await prepareFiles(files);
      final imported = [...first.nodes, ...second.nodes];

      expect(imported.map(_attachmentUrl).toSet(), hasLength(8));
      for (final batch in [first, second]) {
        for (var i = 0; i < samples.length; i++) {
          await _expectLocalCopy(batch.nodes[i], files[i], samples[i], managed);
        }
      }
      expect(await existingImage.readAsBytes(), [3, 4]);
      expect(await existingFile.readAsBytes(), [5, 6]);
      expect(await _filesUnder(managed), hasLength(10));
    });

    test('discard is idempotent and deletes only this batch, never its parents',
        () async {
      final samples = _mixedSamples().take(2).toList();
      final files = await writeSamples(samples);
      final sentinel = await _writeFile(managed, 'files/keep.bin', [42]);
      final prepared = await prepareFiles(files);
      final paths = prepared.nodes.map(_attachmentUrl).toList();
      expect(
        () => prepared.nodes.add(paragraphNode()),
        throwsUnsupportedError,
      );

      await prepared.discard();
      await prepared.discard();

      for (final path in paths) {
        expect(await File(path).exists(), isFalse, reason: path);
      }
      for (var i = 0; i < files.length; i++) {
        expect(await files[i].readAsBytes(), orderedEquals(samples[i].bytes));
      }
      expect(await sentinel.readAsBytes(), [42]);
      expect(await Directory(p.join(managed.path, 'images')).exists(), isTrue);
      expect(await Directory(p.join(managed.path, 'files')).exists(), isTrue);
      expect(
        (await _filesUnder(managed)).map((file) => file.path),
        [sentinel.path],
      );
    });

    test('discard never owns an original returned unchanged by an IO saver',
        () async {
      final source = await _writeFile(originals, 'original.bin', _binaryBytes);
      final passthrough = withSaver(
        (
          path, {
          required documentId,
          required isLocalMode,
          required isImage,
        }) async =>
            path,
      );
      final prepared = await prepareFiles([source], using: passthrough);
      expect(_attachmentUrl(prepared.nodes.single), source.path);

      await prepared.discard();
      await prepared.discard();

      expect(await source.readAsBytes(), orderedEquals(_binaryBytes));
      await expectNoStorageWrites();
    });

    test('empty, text-only, empty bitmap and unsupported bitmap fail before IO',
        () async {
      final inputs = <ClipboardServiceData>[
        const ClipboardServiceData(),
        const ClipboardServiceData(plainText: 'C:\\not-an-attachment.txt'),
        const ClipboardServiceData(image: ('png', null)),
        ClipboardServiceData(image: ('png', Uint8List(0))),
        ClipboardServiceData(image: ('tiff', _pngBytes)),
      ];
      for (final data in inputs) {
        await expectLater(
          service.prepare(data, documentId: '', isLocalMode: true),
          throwsA(isA<FormatException>()),
        );
        await expectNoStorageWrites();
      }
    });

    test('a missing last file rejects the whole batch before local or cloud IO',
        () async {
      final valid = await _writeFile(originals, 'valid.png', _pngBytes);
      final missing = File(p.join(originals.path, 'missing.pdf'));
      final data = ClipboardServiceData(
        files: [valid.uri, missing.uri],
        // A failed explicit file must not silently fall back to this bitmap.
        image: ('png', _pngBytes),
      );
      await expectLater(
        service.prepare(data, documentId: '', isLocalMode: true),
        throwsA(isA<FileSystemException>()),
      );
      var uploads = 0;
      final cloud = withSaver(
        (
          path, {
          required documentId,
          required isLocalMode,
          required isImage,
        }) async {
          uploads++;
          return 'https://uploads.invalid/unexpected';
        },
      );
      await expectLater(
        cloud.prepare(data, documentId: 'cloud-doc', isLocalMode: false),
        throwsA(isA<FileSystemException>()),
      );

      expect(uploads, 0);
      expect(await valid.readAsBytes(), orderedEquals(_pngBytes));
      await expectNoStorageWrites();
    });

    test('a directory after a valid file fails preflight before any writes',
        () async {
      final valid = await _writeFile(originals, 'valid.bin', _binaryBytes);
      final directory =
          await Directory(p.join(originals.path, 'folder')).create();
      await expectLater(
        service.prepare(
          ClipboardServiceData(files: [valid.uri, directory.uri]),
          documentId: '',
          isLocalMode: true,
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(await directory.exists(), isTrue);
      expect(await valid.readAsBytes(), orderedEquals(_binaryBytes));
      await expectNoStorageWrites();
    });

    test('non-file and relative URIs reject a batch before any writes',
        () async {
      final valid = await _writeFile(originals, 'valid.bin', _binaryBytes);
      for (final invalid in [
        Uri.https('files.invalid', '/photo.png'),
        Uri(scheme: 'content', path: '/media/1'),
        Uri(path: 'relative.png'),
        Uri.parse('file:relative.pdf'),
      ]) {
        await expectLater(
          service.prepare(
            ClipboardServiceData(files: [valid.uri, invalid]),
            documentId: '',
            isLocalMode: true,
          ),
          throwsA(_unavailableInput),
          reason: invalid.toString(),
        );
        await expectNoStorageWrites();
      }
      expect(await valid.readAsBytes(), orderedEquals(_binaryBytes));
    });

    test('query, fragment and NUL-containing file paths fail before writes',
        () async {
      final valid = await _writeFile(originals, 'valid.bin', _binaryBytes);
      for (final invalid in [
        valid.uri.replace(query: 'download=1'),
        valid.uri.replace(fragment: 'page'),
        valid.uri.replace(path: '${valid.uri.path}\u0000bad'),
      ]) {
        await expectLater(
          service.prepare(
            ClipboardServiceData(files: [valid.uri, invalid]),
            documentId: '',
            isLocalMode: true,
          ),
          throwsA(_unavailableInput),
        );
        await expectNoStorageWrites();
      }
      expect(await valid.readAsBytes(), orderedEquals(_binaryBytes));
    });

    for (final sample in <(String, _Sample)>[
      ('images', (name: 'photo.png', bytes: _pngBytes, isImage: true)),
      ('files', (name: 'report.pdf', bytes: _pdfBytes, isImage: false)),
    ]) {
      test(
          'default ${sample.$1} saver reports failed storage, not fake success',
          () async {
        final source = await _writeFile(
          originals,
          sample.$2.name,
          sample.$2.bytes,
        );
        // A real file where the directory must be is a portable write failure.
        final blocker = await _writeFile(managed, sample.$1, [91, 92]);

        await expectLater(
          prepareFiles([source]),
          throwsA(isA<FileSystemException>()),
        );

        expect(await blocker.readAsBytes(), [91, 92]);
        expect(await source.readAsBytes(), orderedEquals(sample.$2.bytes));
        expect(
          (await _filesUnder(managed)).map((file) => file.path),
          [blocker.path],
        );
        expect(temporaryRequests, 0);
      });
    }

    test('a storage-location failure propagates without manufacturing a node',
        () async {
      final source = await _writeFile(originals, 'photo.png', _pngBytes);
      final failure = StateError('test storage is unavailable');
      storage.failure = failure;

      await expectLater(prepareFiles([source]), throwsA(same(failure)));

      expect(storage.pathRequests, 1);
      expect(await managed.list().toList(), isEmpty);
      expect(await source.readAsBytes(), orderedEquals(_pngBytes));
    });

    test('cloud IO receives the exact document, bytes, order and image flags',
        () async {
      final samples = _mixedSamples();
      final files = await writeSamples(samples);
      final requests = <_SaveCall>[];
      final urls = <String>[];
      final cloud = withSaver(
        (
          path, {
          required documentId,
          required isLocalMode,
          required isImage,
        }) async {
          requests.add(
            (
              path: path,
              documentId: documentId,
              isLocalMode: isLocalMode,
              isImage: isImage,
              bytes: await File(path).readAsBytes(),
            ),
          );
          final url = Uri(
            scheme: 'https',
            host: 'uploads.invalid',
            pathSegments: [documentId, p.basename(path)],
          ).toString();
          urls.add(url);
          return url;
        },
      );
      final prepared = await prepareFiles(
        files,
        using: cloud,
        documentId: 'cloud-page-42',
        isLocalMode: false,
      );

      expect(requests, hasLength(samples.length));
      expect(prepared.nodes, hasLength(samples.length));
      for (var i = 0; i < samples.length; i++) {
        final request = requests[i];
        final node = prepared.nodes[i];
        expect(request.path, files[i].path);
        expect(request.documentId, 'cloud-page-42');
        expect(request.isLocalMode, isFalse);
        expect(request.isImage, samples[i].isImage);
        expect(request.bytes, orderedEquals(samples[i].bytes));
        expect(_attachmentUrl(node), urls[i]);
        if (samples[i].isImage) {
          expect(node.type, CustomImageBlockKeys.type);
          expect(
            node.attributes[CustomImageBlockKeys.imageType],
            CustomImageType.internal.toIntValue(),
          );
        } else {
          expect(node.type, FileBlockKeys.type);
          expect(
            node.attributes[FileBlockKeys.name],
            p.basename(files[i].path),
          );
          expect(
            node.attributes[FileBlockKeys.urlType],
            FileUrlType.cloud.toIntValue(),
          );
        }
      }
      // Cloud rollback is not claimed by this API; it must not delete originals.
      await prepared.discard();
      for (var i = 0; i < files.length; i++) {
        expect(await files[i].readAsBytes(), orderedEquals(samples[i].bytes));
      }
      await expectNoStorageWrites();
    });

    test('default cloud saver requires a document before reaching the backend',
        () async {
      final files = await writeSamples([
        (name: 'photo.png', bytes: _pngBytes, isImage: true),
        (name: 'report.pdf', bytes: _pdfBytes, isImage: false),
      ]);
      for (final file in files) {
        await expectLater(
          prepareFiles([file], documentId: '', isLocalMode: false),
          throwsA(isA<StateError>()),
        );
        expect(await file.exists(), isTrue);
      }
      await expectNoStorageWrites();
    });

    for (final failureMode in ['null', 'empty', 'throw']) {
      test('partial local $failureMode failure removes only new real copies',
          () async {
        final samples = <_Sample>[
          (name: 'photo.png', bytes: _pngBytes, isImage: true),
          (name: 'report.pdf', bytes: _pdfBytes, isImage: false),
          (name: 'failing.bin', bytes: _binaryBytes, isImage: false),
          (name: 'not-attempted.txt', bytes: [65], isImage: false),
        ];
        final files = await writeSamples(samples);
        final earlierSource = await _writeFile(originals, 'earlier.txt', [66]);
        final earlier = await prepareFiles([earlierSource]);
        final earlierCopy = File(_attachmentUrl(earlier.nodes.single));
        final owned = <File>[];
        final attempted = <String>[];
        final failure = StateError('injected third-save failure');
        final AttachmentFileSaver defaultSaver = service.saveFile;
        final failing = withSaver(
          (
            path, {
            required documentId,
            required isLocalMode,
            required isImage,
          }) async {
            attempted.add(path);
            if (attempted.length == 3) {
              if (failureMode == 'throw') throw failure;
              return failureMode == 'empty' ? '' : null;
            }
            final saved = await defaultSaver(
              path,
              documentId: documentId,
              isLocalMode: isLocalMode,
              isImage: isImage,
            );
            if (saved != null) owned.add(File(saved));
            return saved;
          },
        );

        await expectLater(
          prepareFiles(files, using: failing),
          throwsA(
            failureMode == 'throw' ? same(failure) : isA<FileSystemException>(),
          ),
        );

        expect(attempted, files.take(3).map((file) => file.path).toList());
        expect(owned, hasLength(2));
        for (final copy in owned) {
          expect(await copy.exists(), isFalse);
        }
        for (var i = 0; i < files.length; i++) {
          expect(await files[i].readAsBytes(), orderedEquals(samples[i].bytes));
        }
        expect(await earlierSource.readAsBytes(), [66]);
        expect(await earlierCopy.readAsBytes(), [66]);
        expect(
          (await _filesUnder(managed)).map((file) => file.path),
          [earlierCopy.path],
        );
        expect(await temporary.list().toList(), isEmpty);
      });
    }

    for (final bitmap in <(String, Uint8List)>[
      ('png', _pngBytes),
      ('jpeg', _jpegBytes),
      ('gif', _gifBytes),
      ('webp', _webpBytes),
    ]) {
      test('${bitmap.$1} bitmap owns a managed copy after scratch is removed',
          () async {
        final sentinel = await _writeFile(temporary, 'keep.txt', [11]);
        final AttachmentFileSaver defaultSaver = service.saveFile;
        final requests = <_SaveCall>[];
        final recording = withSaver(
          (
            path, {
            required documentId,
            required isLocalMode,
            required isImage,
          }) async {
            requests.add(
              (
                path: path,
                documentId: documentId,
                isLocalMode: isLocalMode,
                isImage: isImage,
                bytes: await File(path).readAsBytes(),
              ),
            );
            return defaultSaver(
              path,
              documentId: documentId,
              isLocalMode: isLocalMode,
              isImage: isImage,
            );
          },
        );
        final prepared = await recording.prepare(
          ClipboardServiceData(image: bitmap),
          documentId: 'bitmap-document',
          isLocalMode: true,
        );

        expect(requests, hasLength(1));
        final request = requests.single;
        expect(p.basename(request.path), 'Pasted image.${bitmap.$1}');
        expect(p.isWithin(temporary.path, request.path), isTrue);
        expect(request.documentId, 'bitmap-document');
        expect(request.isImage, isTrue);
        expect(request.isLocalMode, isTrue);
        expect(request.bytes, orderedEquals(bitmap.$2));
        expect(temporaryRequests, 1);
        expect(await File(request.path).exists(), isFalse);
        expect(await Directory(p.dirname(request.path)).exists(), isFalse);
        expect(await sentinel.readAsBytes(), [11]);
        expect(
          (await temporary.list().toList()).map((entry) => entry.path),
          [sentinel.path],
        );

        final node = prepared.nodes.single;
        final saved = File(_attachmentUrl(node));
        expect(node.type, CustomImageBlockKeys.type);
        expect(
          node.attributes[CustomImageBlockKeys.imageType],
          CustomImageType.local.toIntValue(),
        );
        expect(p.dirname(saved.path), p.join(managed.path, 'images'));
        expect(p.extension(saved.path), '.${bitmap.$1}');
        expect(p.isWithin(temporary.path, saved.path), isFalse);
        expect(await saved.readAsBytes(), orderedEquals(bitmap.$2));
        await prepared.discard();
        expect(await saved.exists(), isFalse);
        expect(await sentinel.exists(), isTrue);
      });
    }

    test('a failed bitmap save removes scratch for null and thrown failures',
        () async {
      final sentinel = await _writeFile(temporary, 'keep.txt', [12]);
      for (final shouldThrow in [false, true]) {
        File? staged;
        List<int>? received;
        final failure = StateError('bitmap save failed');
        final failing = withSaver(
          (
            path, {
            required documentId,
            required isLocalMode,
            required isImage,
          }) async {
            staged = File(path);
            received = await staged!.readAsBytes();
            if (shouldThrow) throw failure;
            return null;
          },
        );
        await expectLater(
          failing.prepare(
            ClipboardServiceData(image: ('png', _pngBytes)),
            documentId: '',
            isLocalMode: true,
          ),
          throwsA(shouldThrow ? same(failure) : isA<FileSystemException>()),
        );

        expect(received, orderedEquals(_pngBytes));
        expect(staged, isNotNull);
        expect(await staged!.exists(), isFalse);
        expect(await staged!.parent.exists(), isFalse);
        expect(await sentinel.readAsBytes(), [12]);
        expect(
          (await temporary.list().toList()).map((entry) => entry.path),
          [sentinel.path],
        );
        expect(await managed.list().toList(), isEmpty);
      }
      expect(storage.pathRequests, 0);
    });

    test('temporary-directory failure propagates before the saver is called',
        () async {
      var saves = 0;
      final failure = StateError('temporary directory unavailable');
      final failing = AttachmentPasteService(
        temporaryDirectory: () async => throw failure,
        saveFile: (
          path, {
          required documentId,
          required isLocalMode,
          required isImage,
        }) async {
          saves++;
          return path;
        },
      );
      await expectLater(
        failing.prepare(
          ClipboardServiceData(image: ('png', _pngBytes)),
          documentId: '',
          isLocalMode: true,
        ),
        throwsA(same(failure)),
      );
      expect(saves, 0);
      await expectNoStorageWrites();
    });

    test('an actual pending import can be discarded after moving away and back',
        () async {
      final source = await _writeFile(originals, 'pending.png', _pngBytes);
      final editor = _editor([paragraphNode(text: 'original')]);
      final target = _target(editor);
      final before = _editorSnapshot(editor);
      final entered = Completer<void>();
      final release = Completer<void>();
      final AttachmentFileSaver defaultSaver = service.saveFile;
      final delayed = withSaver(
        (
          path, {
          required documentId,
          required isLocalMode,
          required isImage,
        }) async {
          entered.complete();
          await release.future;
          return defaultSaver(
            path,
            documentId: documentId,
            isLocalMode: isLocalMode,
            isImage: isImage,
          );
        },
      );
      final pending = prepareFiles([source], using: delayed);
      try {
        await entered.future;
        expect(target.isCurrent, isTrue);
        expect(_editorSnapshot(editor), before);
        final selection = editor.selection;
        editor.selection = _caret([0], 4);
        editor.selection = selection;
        release.complete();
        final prepared = await pending;
        final saved = File(_attachmentUrl(prepared.nodes.single));

        expect(await saved.readAsBytes(), orderedEquals(_pngBytes));
        expect(target.isCurrent, isFalse);
        await prepared.discard();
        expect(await saved.exists(), isFalse);
        expect(await source.readAsBytes(), orderedEquals(_pngBytes));
        expect(_editorSnapshot(editor), before);
        expect(editor.undoManager.undoStack.isEmpty, isTrue);
      } finally {
        if (!release.isCompleted) release.complete();
        await (await pending).discard();
      }
    });
  });

  group('insertPastedAttachments with a real EditorState', () {
    test(
        'replaces an empty paragraph and leaves one editable trailing paragraph',
        () async {
      final attachments = _attachments();
      await _expectInsertion(
        _editor([paragraphNode()]),
        attachments,
        expected: [...attachments, paragraphNode()],
        after: _caret([2]),
      );
    });

    test('splits rich deltas in the middle without losing unrelated attributes',
        () async {
      final delta = Delta()
        ..insert('ab', attributes: {'bold': true})
        ..insert(
          'cdef',
          attributes: {'italic': true, 'href': 'https://link.invalid'},
        )
        ..insert('gh', attributes: {'code': true});
      final attributes = <String, dynamic>{
        'align': 'right',
        'text_direction': 'rtl',
        'custom': {
          'nested': ['unchanged', 17],
        },
      };
      final attachments = _attachments();
      final editor = _editor(
        [paragraphNode(delta: delta, attributes: attributes)],
        selection: _caret([0], 4),
      );
      await _expectInsertion(
        editor,
        attachments,
        expected: [
          paragraphNode(
            delta: Delta()
              ..insert('ab', attributes: {'bold': true})
              ..insert(
                'cd',
                attributes: {'italic': true, 'href': 'https://link.invalid'},
              ),
            attributes: attributes,
          ),
          ...attachments,
          paragraphNode(
            delta: Delta()
              ..insert(
                'ef',
                attributes: {'italic': true, 'href': 'https://link.invalid'},
              )
              ..insert('gh', attributes: {'code': true}),
            attributes: attributes,
          ),
        ],
        after: _caret([3]),
      );
    });

    test('at text start inserts before the complete original text', () async {
      final original =
          paragraphNode(text: 'keep all', attributes: {'align': 'left'});
      final attachments = _attachments();
      await _expectInsertion(
        _editor([original]),
        attachments,
        expected: [...attachments, original.copyWith()],
        after: _caret([2]),
      );
    });

    test('at text end retains the prefix and provides a fresh empty paragraph',
        () async {
      final original =
          paragraphNode(text: 'keep all', attributes: {'custom': 7});
      final attachments = _attachments();
      await _expectInsertion(
        _editor([original], selection: _caret([0], 8)),
        attachments,
        expected: [original.copyWith(), ...attachments, paragraphNode()],
        after: _caret([3]),
      );
    });

    test('a backward inline range replaces only the selected text', () async {
      final attachments = _attachments();
      await _expectInsertion(
        _editor(
          [paragraphNode(text: 'abcdefgh')],
          selection: Selection.single(path: [0], startOffset: 6, endOffset: 2),
        ),
        attachments,
        expected: [
          paragraphNode(text: 'ab'),
          ...attachments,
          paragraphNode(text: 'gh'),
        ],
        after: _caret([3]),
      );
    });

    test('a full text range removes the old text but not the following sibling',
        () async {
      final following =
          paragraphNode(text: 'untouched', attributes: {'tag': 'next'});
      final attachments = _attachments();
      await _expectInsertion(
        _editor(
          [paragraphNode(text: 'replace me'), following],
          selection: Selection.single(path: [0], startOffset: 0, endOffset: 10),
        ),
        attachments,
        expected: [...attachments, paragraphNode(), following.copyWith()],
        after: _caret([2]),
      );
    });

    test('a backward multi-sibling range retains both rich ends and outsiders',
        () async {
      final before =
          paragraphNode(text: 'before', attributes: {'unrelated': 1});
      final after = paragraphNode(text: 'after', attributes: {'unrelated': 2});
      final attachments = _attachments();
      final editor = _editor(
        [
          before,
          paragraphNode(
            delta: Delta()..insert('left', attributes: {'bold': true}),
            attributes: {'align': 'center'},
          ),
          customImageNode(url: 'old-image.png'),
          paragraphNode(
            delta: Delta()..insert('right', attributes: {'italic': true}),
            attributes: {'custom': 'last'},
          ),
          after,
        ],
        selection: Selection(
          start: Position(path: [3], offset: 2),
          end: Position(path: [1], offset: 2),
        ),
      );
      await _expectInsertion(
        editor,
        attachments,
        expected: [
          before.copyWith(),
          paragraphNode(
            delta: Delta()..insert('le', attributes: {'bold': true}),
            attributes: {'align': 'center'},
          ),
          ...attachments,
          paragraphNode(
            delta: Delta()..insert('ght', attributes: {'italic': true}),
            attributes: {'custom': 'last'},
          ),
          after.copyWith(),
        ],
        after: _caret([4]),
      );
    });

    test('block selection replaces complete blocks rather than splitting text',
        () async {
      final following = paragraphNode(text: 'keep');
      final attachments = _attachments();
      final editor = _editor(
        [
          paragraphNode(text: 'whole block'),
          customImageNode(url: 'old.png'),
          following,
        ],
        selection: Selection(
          start: Position(path: [1], offset: 1),
          end: Position(path: [0], offset: 3),
        ),
      )..selectionType = SelectionType.block;

      await _expectInsertion(
        editor,
        attachments,
        expected: [...attachments, paragraphNode(), following.copyWith()],
        after: _caret([2]),
      );
    });

    test(
        'a caret on existing media inserts after it and keeps caption/metadata',
        () async {
      final originals = [
        customImageNode(url: 'existing.png', width: 444, height: 333)
          ..updateAttributes({
            CustomImageBlockKeys.caption: 'Keep this caption',
            CustomImageBlockKeys.workspaceFileId: 'workspace-photo',
            'custom': {'rating': 5},
          }),
        fileNode(url: 'existing.pdf', name: 'Existing report.pdf')
          ..updateAttributes({
            FileBlockKeys.previewMetadata: {'page': 4, 'zoom': 1.25},
            FileBlockKeys.workspaceFileId: 'workspace-file',
          }),
      ];
      for (final original in originals) {
        final following = paragraphNode(text: 'following');
        final attachments = _attachments();
        await _expectInsertion(
          _editor([original, following], selection: _caret([0], 1)),
          attachments,
          expected: [
            original.copyWith(),
            ...attachments,
            paragraphNode(),
            following.copyWith(),
          ],
          after: _caret([3]),
        );
      }
    });

    test(
        'nested list start/middle/end keep descendants exactly once, without premutation',
        () async {
      for (final offset in [0, 2, 4]) {
        final descendants = [
          paragraphNode(
            text: 'caption child',
            attributes: {'caption': 'retained'},
          ),
          bulletedListNode(
            text: 'child list',
            children: [paragraphNode(text: 'grandchild')],
          ),
        ];
        final attributes = <String, dynamic>{
          'custom': 'list-item',
          'align': 'right',
        };
        final previous = bulletedListNode(text: 'previous');
        final next = bulletedListNode(text: 'next');
        final parent = bulletedListNode(
          text: 'outer',
          attributes: {'custom': 'container'},
          children: [
            previous,
            bulletedListNode(
              text: 'abcd',
              attributes: attributes,
              children: descendants,
            ),
            next,
          ],
        );
        final outside = paragraphNode(text: 'outside');
        final attachments = _attachments();
        final expectedParent = parent.copyWith(
          children: [
            previous.copyWith(),
            if (offset > 0)
              bulletedListNode(
                text: 'abcd'.substring(0, offset),
                attributes: attributes,
              ),
            ...attachments.map((node) => node.copyWith()),
            if (offset < 4)
              bulletedListNode(
                text: 'abcd'.substring(offset),
                attributes: attributes,
                children: descendants.map((node) => node.copyWith()).toList(),
              )
            else
              paragraphNode(
                children: descendants.map((node) => node.copyWith()).toList(),
              ),
            next.copyWith(),
          ],
        );
        await _expectInsertion(
          _editor([parent, outside], selection: _caret([0, 1], offset)),
          attachments,
          expected: [expectedParent, outside.copyWith()],
          after: _caret([0, offset == 0 ? 3 : 4]),
        );
      }
    });

    test('sibling replacement retains child trees on both surviving endpoints',
        () async {
      final firstChildren = [
        bulletedListNode(
          text: 'first child',
          children: [paragraphNode(text: 'deep first')],
        ),
      ];
      final lastChildren = [paragraphNode(text: 'last caption child')];
      final preceding = paragraphNode(text: 'preceding');
      final following = paragraphNode(text: 'following');
      final attachments = _attachments();
      final editor = _editor(
        [
          preceding,
          bulletedListNode(
            text: 'erase',
            attributes: {'meta': 'first'},
            children: firstChildren,
          ),
          bulletedListNode(
            text: 'XXtail',
            attributes: {'meta': 'last'},
            children: lastChildren,
          ),
          following,
        ],
        selection: Selection(
          start: Position(path: [1]),
          end: Position(path: [2], offset: 2),
        ),
      );
      await _expectInsertion(
        editor,
        attachments,
        expected: [
          preceding.copyWith(),
          bulletedListNode(
            text: '',
            attributes: {'meta': 'first'},
            children: firstChildren.map((node) => node.copyWith()).toList(),
          ),
          ...attachments,
          bulletedListNode(
            text: 'tail',
            attributes: {'meta': 'last'},
            children: lastChildren.map((node) => node.copyWith()).toList(),
          ),
          following.copyWith(),
        ],
        after: _caret([4]),
      );
    });

    test('cross-container replacement is atomic and one undo restores the tree',
        () async {
      final attachments = _attachments();
      final following = paragraphNode(text: 'untouched');
      final editor = _editor(
        [
          bulletedListNode(
            text: 'parent',
            children: [bulletedListNode(text: 'left')],
          ),
          paragraphNode(text: 'right'),
          following,
        ],
        selection: Selection(
          start: Position(path: [0, 0], offset: 2),
          end: Position(path: [1], offset: 2),
        ),
      );
      // Do not weaken this to two transactions: every before observer must see
      // the original tree, never an already-deleted selection awaiting media.
      await _expectInsertion(
        editor,
        attachments,
        expected: [
          bulletedListNode(
            text: 'parent',
            children: [
              bulletedListNode(text: 'le'),
              ...attachments.map((node) => node.copyWith()),
              bulletedListNode(text: 'ght'),
            ],
          ),
          following.copyWith(),
        ],
        after: _caret([0, 3]),
      );
    });

    test(
        'readonly, disposed, null selection and empty attachments do not mutate',
        () async {
      for (final condition in ['readonly', 'disposed', 'null', 'empty']) {
        final editor = _editor([paragraphNode(text: 'unchanged')]);
        final attachments = condition == 'empty' ? <Node>[] : _attachments();
        switch (condition) {
          case 'readonly':
            editor.editable = false;
            break;
          case 'disposed':
            editor.dispose();
            break;
          case 'null':
            editor.selection = null;
            break;
        }
        await _expectRejected(editor, attachments, reason: condition);
      }
    });

    test(
        'bad paths and out-of-bounds text or media offsets reject without mutation',
        () async {
      final selections = [
        _caret([]),
        _caret([-1]),
        _caret([7]),
        _caret([0, 0]),
        _caret([0], -1),
        _caret([0], 5),
        Selection.single(path: [0], startOffset: 1, endOffset: 8),
        Selection(start: Position(path: [0]), end: Position(path: [9])),
        // Image/file selectable positions are 0..1, not arbitrary offsets.
        _caret([1], -1),
        _caret([1], 2),
      ];
      for (final selection in selections) {
        await _expectRejected(
          _editor(
            [paragraphNode(text: 'text'), customImageNode(url: 'existing.png')],
            selection: selection,
          ),
          _attachments(),
          reason: selection.toString(),
        );
      }
    });

    test('invalid cross-container offsets are validated before deletion',
        () async {
      for (final offsets in [(1, 99), (-1, 1), (99, 1)]) {
        await _expectRejected(
          _editor(
            [
              bulletedListNode(
                text: 'parent',
                children: [bulletedListNode(text: 'left')],
              ),
              paragraphNode(text: 'right'),
            ],
            selection: Selection(
              start: Position(path: [0, 0], offset: offsets.$1),
              end: Position(path: [1], offset: offsets.$2),
            ),
          ),
          _attachments(),
          reason: 'cross-container offsets $offsets',
        );
      }
    });
  });

  group('AttachmentPasteTarget with a real EditorState', () {
    test('an unchanged target and an equal selection value remain current', () {
      final editor =
          _editor([paragraphNode(text: 'abcdef')], selection: _caret([0], 2));
      final target = _target(editor);
      expect(target.selection, editor.selection);
      expect(target.selectionType, SelectionType.inline);
      expect(target.isCurrent, isTrue);

      editor.selection = _caret([0], 2);

      expect(target.isCurrent, isTrue);
      expect(editor.undoManager.undoStack.isEmpty, isTrue);
    });

    test('a missing selection or readonly editor is never a usable target', () {
      final withoutSelection = _editor([paragraphNode()])..selection = null;
      final readonly = _editor([paragraphNode()])..editable = false;

      expect(_target(withoutSelection).isCurrent, isFalse);
      expect(_target(readonly).isCurrent, isFalse);
    });

    test(
        'moving away or clearing selection stays stale even after restoring it',
        () {
      for (final clear in [false, true]) {
        final editor =
            _editor([paragraphNode(text: 'abcdef')], selection: _caret([0], 2));
        final target = _target(editor);
        final original = editor.selection;

        editor.selection = clear ? null : _caret([0], 4);
        expect(target.isCurrent, isFalse);
        editor.selection = original;

        expect(editor.selection, target.selection);
        expect(target.isCurrent, isFalse);
      }
    });

    test('changing selection mode away and back invalidates the pending target',
        () {
      final editor = _editor([paragraphNode(text: 'abcdef')]);
      final target = _target(editor);
      editor.selectionType = SelectionType.block;
      expect(target.isCurrent, isFalse);

      editor.selectionType = SelectionType.inline;

      expect(editor.selection, target.selection);
      expect(target.isCurrent, isFalse);
    });

    test('an attribute transaction invalidates the target even after undo',
        () async {
      final editor = _editor([paragraphNode(text: 'abcdef')]);
      final before = _treeSnapshot(editor.document.root);
      final target = _target(editor);
      final transaction = editor.transaction
        ..updateNode(
          editor.document.root.children.single,
          {'custom': 'changed'},
        )
        ..afterSelection = editor.selection
        ..customSelectionType = editor.selectionType;

      await editor.apply(transaction);

      expect(editor.selection, target.selection);
      expect(editor.selectionType, target.selectionType);
      expect(target.isCurrent, isFalse);
      editor.undoManager.undo();
      await Future<void>.value();
      expect(_treeSnapshot(editor.document.root), before);
      editor.selectionType = target.selectionType;
      expect(target.isCurrent, isFalse);
    });

    test('same-position text replacement invalidates a pending target',
        () async {
      final editor =
          _editor([paragraphNode(text: 'abcdef')], selection: _caret([0], 3));
      final node = editor.document.root.children.single;
      final target = _target(editor);
      final transaction = editor.transaction
        ..replaceText(node, 1, 2, 'XY')
        ..afterSelection = editor.selection
        ..customSelectionType = editor.selectionType;

      await editor.apply(transaction);

      expect(node.delta!.toPlainText(), 'aXYdef');
      expect(editor.getNodeAtPath([0]), same(node));
      expect(editor.selection, target.selection);
      expect(editor.selectionType, target.selectionType);
      expect(target.isCurrent, isFalse);
    });

    test('same-position remote text replacement also invalidates the target',
        () async {
      final editor =
          _editor([paragraphNode(text: 'abcdef')], selection: _caret([0], 3));
      final node = editor.document.root.children.single;
      final target = _target(editor);
      final transaction = editor.transaction..replaceText(node, 1, 2, 'XY');

      // Real EditorState.apply(remote) deliberately bypasses the local stream.
      // The target must nevertheless not overwrite somebody else's new text.
      await editor.apply(transaction, isRemote: true);

      expect(node.delta!.toPlainText(), 'aXYdef');
      expect(editor.getNodeAtPath([0]), same(node));
      expect(editor.selection, target.selection);
      expect(editor.selectionType, target.selectionType);
      expect(target.isCurrent, isFalse);
    });

    test('readonly then writable remains stale even with the same selection',
        () {
      final editor = _editor([paragraphNode(text: 'abcdef')]);
      final target = _target(editor);

      editor.editable = false;
      expect(target.isCurrent, isFalse);
      editor.editable = true;

      expect(editor.selection, target.selection);
      expect(target.isCurrent, isFalse);
    });

    test('editor disposal invalidates the target and target cleanup is safe',
        () {
      final editor = _editor([paragraphNode(text: 'abcdef')]);
      final target = _target(editor);

      editor.dispose();

      expect(target.isCurrent, isFalse);
      expect(target.dispose, returnsNormally);
    });

    testWidgets(
        'unmount rejects a pending target even if the root key is remounted',
        (tester) async {
      final editor = _editor([paragraphNode(text: 'abcdef')]);
      AttachmentPasteTarget? target;
      AttachmentPasteTarget? replacement;
      try {
        // Node.context is its real GlobalKey.currentContext. Mount that exact
        // key to exercise Flutter's actual Element lifecycle, without booting
        // document-page providers, rendering media, or starting backend services.
        await tester.pumpWidget(SizedBox(key: editor.document.root.key));
        final context = editor.document.root.context!;
        target = AttachmentPasteTarget(editor);
        expect(context.mounted, isTrue);
        expect(target.isCurrent, isTrue);

        await tester.pumpWidget(const SizedBox.shrink());

        expect(context.mounted, isFalse);
        expect(editor.isDisposed, isFalse);
        expect(editor.selection, target.selection);
        expect(target.isCurrent, isFalse);

        await tester.pumpWidget(SizedBox(key: editor.document.root.key));
        replacement = AttachmentPasteTarget(editor);
        expect(editor.document.root.context, isNot(same(context)));
        expect(replacement.isCurrent, isTrue);
        expect(target.isCurrent, isFalse);
        expect(tester.takeException(), isNull);
      } finally {
        replacement?.dispose();
        target?.dispose();
        await tester.pumpWidget(const SizedBox.shrink());
        editor.dispose();
      }
    });
  });
}

typedef _Sample = ({String name, List<int> bytes, bool isImage});

typedef _SaveCall = ({
  String path,
  String documentId,
  bool isLocalMode,
  bool isImage,
  List<int> bytes,
});

// Tiny deterministic payloads keep these tests about MIME sniffing and exact
// byte preservation, not codec availability. JPEG/WebP are signature fixtures;
// preparation must neither decode nor transcode an attachment to copy it.
final _pngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jVAAAAABJRU5ErkJggg==',
);
final _jpegBytes = Uint8List.fromList([
  0xff,
  0xd8,
  0xff,
  0xe0,
  0,
  16,
  0x4a,
  0x46,
  0x49,
  0x46,
  0,
  1,
  1,
  0,
  0,
  1,
  0,
  1,
  0,
  0,
  0xff,
  0xd9,
]);
final _gifBytes = base64Decode(
  'R0lGODlhAQABAIAAAAAAAP///yH5BAEAAAAALAAAAAABAAEAAAIBRAA7',
);
final _webpBytes = Uint8List.fromList([
  ...ascii.encode('RIFF'),
  12,
  0,
  0,
  0,
  ...ascii.encode('WEBPVP8 '),
  0,
  0,
  0,
  0,
]);
final _pdfBytes = utf8.encode('%PDF-1.7\nAttachment test\n%%EOF');
const _binaryBytes = [0, 1, 2, 3, 127, 128, 254, 255];

List<_Sample> _mixedSamples() => [
      (name: 'Photo 50% #café.PNG', bytes: _pngBytes, isImage: true),
      (
        name: 'Audio.WAV',
        bytes: [...ascii.encode('RIFF'), 4, 0, 0, 0, ...ascii.encode('WAVE')],
        isImage: false,
      ),
      (
        name: 'Video.MP4',
        bytes: [0, 0, 0, 24, ...ascii.encode('ftypmp42'), 0, 0, 0, 0],
        isImage: false,
      ),
      (name: 'Report.pdf', bytes: _pdfBytes, isImage: false),
      (
        name: 'Notes résumé #1 100%.txt',
        bytes: utf8.encode('Text stays an attachment.\r\nCafé ✓'),
        isImage: false,
      ),
      (name: 'Payload.bin', bytes: _binaryBytes, isImage: false),
      (name: 'Empty.bin', bytes: <int>[], isImage: false),
    ];

final _unavailableInput = anyOf(
  isA<FormatException>(),
  isA<FileSystemException>(),
  isA<ArgumentError>(),
);

class _TestDataStorage extends Fake implements ApplicationDataStorage {
  _TestDataStorage(this.path);

  final String path;
  int pathRequests = 0;
  Object? failure;

  @override
  Future<String> getPath() async {
    pathRequests++;
    final error = failure;
    if (error != null) throw error;
    return path;
  }
}

Future<File> _writeFile(Directory root, String name, List<int> bytes) async {
  final file = File(p.normalize(p.join(root.path, name)));
  await file.parent.create(recursive: true);
  return file.writeAsBytes(bytes, flush: true);
}

Future<List<File>> _filesUnder(Directory directory) async {
  final entries =
      await directory.list(recursive: true, followLinks: false).toList();
  return entries.whereType<File>().toList();
}

String _attachmentUrl(Node node) =>
    node.attributes[FileBlockKeys.url] as String;

Future<File> _expectLocalCopy(
  Node node,
  File source,
  _Sample sample,
  Directory managed,
) async {
  final saved = File(_attachmentUrl(node));
  expect(
    node.type,
    sample.isImage ? CustomImageBlockKeys.type : FileBlockKeys.type,
  );
  expect(node.children, isEmpty);
  expect(p.equals(saved.path, source.path), isFalse);
  expect(
    p.dirname(saved.path),
    p.join(managed.path, sample.isImage ? 'images' : 'files'),
  );
  expect(p.basename(saved.path), isNot(p.basename(source.path)));
  expect(p.extension(saved.path), p.extension(source.path));
  expect(await saved.readAsBytes(), orderedEquals(sample.bytes));
  expect(await source.readAsBytes(), orderedEquals(sample.bytes));
  if (sample.isImage) {
    expect(
      node.attributes[CustomImageBlockKeys.imageType],
      CustomImageType.local.toIntValue(),
    );
  } else {
    expect(node.attributes[FileBlockKeys.name], p.basename(source.path));
    expect(
      node.attributes[FileBlockKeys.urlType],
      FileUrlType.local.toIntValue(),
    );
    expect(node.attributes[FileBlockKeys.uploadedAt], isA<int>());
  }
  return saved;
}

Selection _caret(List<int> path, [int offset = 0]) =>
    Selection.collapsed(Position(path: path, offset: offset));

EditorState _editor(List<Node> nodes, {Selection? selection}) {
  final editor =
      EditorState(document: Document(root: pageNode(children: nodes)))
        ..disableSealTimer = true
        ..editorStyle = const EditorStyle.desktop()
        ..selectionType = SelectionType.inline
        ..selection = selection ?? _caret([0]);
  addTearDown(() {
    if (!editor.isDisposed) editor.dispose();
  });
  return editor;
}

AttachmentPasteTarget _target(EditorState editor) {
  final target = AttachmentPasteTarget(editor);
  // Registered after the state cleanup, so the guard is cleaned up first.
  addTearDown(target.dispose);
  return target;
}

List<Node> _attachments() => [
      customImageNode(url: 'managed-photo.png')
        ..updateAttributes({CustomImageBlockKeys.caption: 'Pasted caption'}),
      fileNode(url: 'managed-report.pdf', name: 'Report.pdf'),
    ];

Object _contentOf(Iterable<Node> nodes) =>
    jsonDecode(jsonEncode(nodes.map((node) => node.toJson()).toList()));

Map<String, Object?> _identityTree(Node node) => {
      'id': node.id,
      'type': node.type,
      'parent': node.parent?.id,
      'path': List<int>.of(node.path),
      'attributes': node.attributes,
      'children': node.children.map(_identityTree).toList(),
    };

// JSON serialization freezes nested attribute maps too. Node.toJson() omits
// IDs and parent links, so it alone would miss pre-transaction child reparenting.
Object _treeSnapshot(Node root) => jsonDecode(jsonEncode(_identityTree(root)));

Object _editorSnapshot(EditorState editor) => jsonDecode(
      jsonEncode({
        'tree': _identityTree(editor.document.root),
        'selection': editor.selection?.toJson(),
        'selectionType': editor.selectionType?.name,
        'editable': editor.editable,
      }),
    );

Iterable<Node> _walk(Iterable<Node> nodes) sync* {
  for (final node in nodes) {
    yield node;
    yield* _walk(node.children);
  }
}

void _expectTreeIntegrity(EditorState editor) {
  final nodes = _walk([editor.document.root]).toList();
  expect(nodes.map((node) => node.id), everyElement(isNotEmpty));
  expect(nodes.map((node) => node.id).toSet(), hasLength(nodes.length));
  expect(editor.document.root.parent, isNull);
  for (final parent in nodes) {
    for (var i = 0; i < parent.children.length; i++) {
      final child = parent.children[i];
      expect(child.parent, same(parent));
      expect(child.path, [...parent.path, i]);
      expect(editor.getNodeAtPath(child.path), same(child));
    }
  }
}

Future<void> _expectInsertion(
  EditorState editor,
  List<Node> attachments, {
  required List<Node> expected,
  required Selection after,
}) async {
  final before = _editorSnapshot(editor);
  final originalTree = _treeSnapshot(editor.document.root);
  final originalSelection = editor.selection;
  final expectedContent = _contentOf(expected);
  final attachmentSnapshots = attachments.map(_treeSnapshot).toList();
  final prototypeIds = _walk(attachments).map((node) => node.id).toSet();
  final phases = <TransactionTime>[];
  final beforeSnapshots = <Object>[];
  final subscription = editor.transactionStream.listen((event) {
    phases.add(event.$1);
    if (event.$1 == TransactionTime.before) {
      // Capture in the synchronous callback; assertions outside it cannot be
      // swallowed by a stream zone or affect the production transaction.
      beforeSnapshots.add(_editorSnapshot(editor));
    }
  });
  bool inserted;
  try {
    inserted = await insertPastedAttachments(editor, attachments);
  } finally {
    await subscription.cancel();
  }

  expect(inserted, isTrue);
  expect(beforeSnapshots, isNotEmpty);
  for (final snapshot in beforeSnapshots) {
    expect(
      snapshot,
      before,
      reason: 'every before observer must see the original document',
    );
  }
  expect(phases, [TransactionTime.before, TransactionTime.after]);
  expect(_contentOf(editor.document.root.children), expectedContent);
  expect(editor.selection, after);
  expect(editor.selectionType, SelectionType.inline);
  expect(editor.getNodeAtPath(after.end.path)!.delta, isNotNull);
  expect(attachments.map(_treeSnapshot).toList(), attachmentSnapshots);
  final liveIds = _walk([editor.document.root]).map((node) => node.id).toSet();
  expect(
    liveIds.intersection(prototypeIds),
    isEmpty,
    reason: 'inserted nodes need fresh IDs',
  );
  _expectTreeIntegrity(editor);

  expect(editor.undoManager.undoStack.isNonEmpty, isTrue);
  editor.undoManager.undoStack.last.seal();
  editor.undoManager.undo();
  await Future<void>.value();
  expect(
    _treeSnapshot(editor.document.root),
    originalTree,
    reason: 'one undo restores IDs, attributes and descendants',
  );
  expect(editor.selection, originalSelection);
  expect(editor.undoManager.undoStack.isEmpty, isTrue);
  expect(editor.undoManager.redoStack.isNonEmpty, isTrue);
  _expectTreeIntegrity(editor);
}

Future<void> _expectRejected(
  EditorState editor,
  List<Node> attachments, {
  required String reason,
}) async {
  final before = _editorSnapshot(editor);
  final prototypes = attachments.map(_treeSnapshot).toList();
  final events = <EditorTransactionValue>[];
  final subscription = editor.transactionStream.listen(events.add);
  bool? result;
  Object? error;
  try {
    result = await insertPastedAttachments(editor, attachments);
  } catch (caught) {
    error = caught;
  } finally {
    await subscription.cancel();
  }

  expect(_editorSnapshot(editor), before, reason: reason);
  expect(events, isEmpty, reason: '$reason must not start a transaction');
  expect(attachments.map(_treeSnapshot).toList(), prototypes, reason: reason);
  expect(editor.undoManager.undoStack.isEmpty, isTrue, reason: reason);
  expect(editor.undoManager.redoStack.isEmpty, isTrue, reason: reason);
  expect(error, isNull, reason: '$reason must return false rather than throw');
  expect(result, isFalse, reason: reason);
}
