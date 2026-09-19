import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/clipboard_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_copy_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/custom_paste_command.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/copy_and_paste/paste_from_attachments.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_media_player.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/shortcuts/command_shortcuts.dart'
    as page_shortcuts;
import 'package:appflowy/shared/clipboard_state.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/settings/application_data_storage.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:super_clipboard/super_clipboard.dart';

import 'test_asset_bundle.dart';

// These are page-workflow tests, not native clipboard/player integration tests.
// The real editor, production shortcut list, clipboard codecs, paste handlers,
// transactions and default local importers run. Only OS clipboard handles,
// application-data location, DocumentBloc/backend and media rendering are fake.
const _modes = ['light', 'dark', 'paper'];
const _deadline = Duration(seconds: 5);
const _paragraph = ParagraphBlockKeys.type;
const _image = CustomImageBlockKeys.type;
const _file = FileBlockKeys.type;
const _privateImageUrl =
    'https://clipboard.example.invalid/private.png?token=synthetic-private';
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8A'
  'AwMCAO+aL1YAAAAASUVORK5CYII=',
);
late Map<String, dynamic> _translations;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _translations = await const TestBundleAssetLoader()
        .load('assets/translations', const Locale('en', 'US'));
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  group('the registered page keyboard commands', () {
    for (final mode in _modes) {
      _test('$mode: Ctrl+V imports a photo once into an empty page',
          (tester, sandbox) async {
        final photo = await _source(
          tester,
          sandbox,
          'Original # 100% 文.PNG',
          bytes: _png,
        );
        final item = _fileItem(
          photo,
          plainText: photo.path,
          html: '<img src="$_privateImageUrl">',
          raster: _png,
        );
        sandbox.clipboard.items = [item];
        final page = await sandbox.mount(tester, mode: mode);

        final widget = tester.widget<AppFlowyEditor>(find.byKey(page.key));
        expect(widget.disableKeyboardService, isFalse);
        expect(widget.disableSelectionService, isFalse);
        expect(
          widget.commandShortcutEvents,
          contains(same(customPasteCommand)),
        );
        expect(
          widget.commandShortcutEvents,
          contains(same(customPastePlainTextCommand)),
        );
        expect(page.editor.document.root.context, isNotNull);
        if (mode == 'paper') {
          expect(
            PaperTheme.isEnabled(page.editor.document.root.context!),
            isTrue,
          );
        }

        await _pasteKey(tester, sandbox, page);

        _expectDocument(page, types: [_image, _paragraph], paragraphs: ['']);
        _expectTail(page, index: 1);
        expect(page.writes, 1);
        expect(
          item.fileReads,
          isEmpty,
          reason: 'A file URI and its advertised PNG are one attachment',
        );
        final copies = await _expectManagedCopies(
          tester,
          sandbox,
          page.attachments,
          [photo],
          images: [true],
        );
        expect(
          find.byKey(ValueKey('attachment-${page.nodes.first.id}')),
          findsOneWidget,
        );

        // A copied media export may disappear after the OS clipboard changes.
        // The document must not retain that export path as its source.
        await _removeExportsAndVerify(tester, sandbox, copies);
        _expectDocument(page, types: [_image, _paragraph], paragraphs: ['']);
      });

      _test('$mode: Ctrl+V splits formatted text around an actual file',
          (tester, sandbox) async {
        final file = await _source(tester, sandbox, 'Report # 100% 文.pdf');
        sandbox.clipboard.items = [_fileItem(file, plainText: file.path)];
        final page = await sandbox.mount(
          tester,
          mode: mode,
          nodes: [
            paragraphNode(
              delta: Delta()
                ..insert(
                  'before ',
                  attributes: {AppFlowyRichTextKeys.bold: true},
                )
                ..insert(
                  'after',
                  attributes: {AppFlowyRichTextKeys.italic: true},
                ),
            ),
          ],
          selection: Selection.collapsed(Position(path: [0], offset: 7)),
        );

        await _pasteKey(tester, sandbox, page);

        _expectDocument(
          page,
          types: [_paragraph, _file, _paragraph],
          paragraphs: ['before ', 'after'],
        );
        _expectStyle(page.nodes[0], 'before ', AppFlowyRichTextKeys.bold);
        _expectStyle(page.nodes[2], 'after', AppFlowyRichTextKeys.italic);
        _expectTail(page, index: 2, text: 'after');
        expect(page.writes, 1);
        final copies = await _expectManagedCopies(
          tester,
          sandbox,
          page.attachments,
          [file],
          images: [false],
        );
        await _removeExportsAndVerify(tester, sandbox, copies);
      });

      _test('$mode: Ctrl+V keeps mixed photo/file/video/audio item order',
          (tester, sandbox) async {
        final files = await _mixedSources(tester, sandbox);
        final items = files
            .map(
              (file) => _fileItem(
                file,
                plainText: file.path,
                html: '<p>do not paste a path or this HTML</p>',
                raster: _png,
              ),
            )
            .toList();
        sandbox.clipboard.items = items;
        final page = await sandbox.mount(
          tester,
          mode: mode,
          nodes: [paragraphNode(text: 'left REPLACE right')],
          selection: Selection.single(path: [0], startOffset: 5, endOffset: 12),
        );

        await _pasteKey(tester, sandbox, page);

        _expectDocument(
          page,
          types: [_paragraph, _image, _file, _file, _file, _image, _paragraph],
          paragraphs: ['left ', ' right'],
        );
        _expectTail(page, index: 6, text: ' right');
        expect(page.writes, 1);
        expect(items.every((item) => item.fileReads.isEmpty), isTrue);
        final copies = await _expectManagedCopies(
          tester,
          sandbox,
          page.attachments,
          files,
          images: [true, false, false, false, true],
        );
        expect(
          fileMediaKind(
            page.attachments[2].attributes[FileBlockKeys.name] as String,
            page.attachments[2].attributes[FileBlockKeys.url] as String,
          ),
          FileMediaKind.video,
        );
        expect(
          fileMediaKind(
            page.attachments[3].attributes[FileBlockKeys.name] as String,
            page.attachments[3].attributes[FileBlockKeys.url] as String,
          ),
          FileMediaKind.audio,
        );
        expect(sandbox.storage.reads, files.length);
        await _removeExportsAndVerify(tester, sandbox, copies);
      });
    }

    _test('Ctrl+B really formats the selected page text before Ctrl+V',
        (tester, sandbox) async {
      final photo = await _source(tester, sandbox, 'photo.png', bytes: _png);
      sandbox.clipboard.items = [_fileItem(photo)];
      final page = await sandbox.mount(
        tester,
        nodes: [paragraphNode(text: 'bold tail')],
        selection: Selection.single(path: [0], startOffset: 0, endOffset: 4),
      );

      expect(await _controlKey(tester, LogicalKeyboardKey.keyB), isTrue);
      await tester.pump();
      _expectStyle(page.nodes.single, 'bold', AppFlowyRichTextKeys.bold);
      await page.select(
        tester,
        Selection.collapsed(Position(path: [0], offset: 4)),
      );
      final writes = page.writes;
      await _pasteKey(tester, sandbox, page);

      _expectDocument(
        page,
        types: [_paragraph, _image, _paragraph],
        paragraphs: ['bold', ' tail'],
      );
      _expectStyle(page.nodes.first, 'bold', AppFlowyRichTextKeys.bold);
      expect(page.writes, writes + 1);
      _expectTail(page, index: 2, text: ' tail');
    });

    for (final kind in ['image', 'file', 'mixed']) {
      _test('Ctrl+C then Ctrl+V copies $kind blocks into nonempty text',
          (tester, sandbox) async {
        final photo = await _source(tester, sandbox, 'kept.png', bytes: _png);
        final file = await _source(tester, sandbox, 'kept.pdf');
        final copied = <Node>[
          if (kind != 'file')
            customImageNode(url: photo.path, width: 237, height: 119)
              ..updateAttributes({CustomImageBlockKeys.caption: 'A caption'}),
          if (kind != 'image') fileNode(url: file.path, name: 'kept.pdf'),
        ];
        final originalAttributes = copied
            .map((node) => Map<String, dynamic>.of(node.attributes))
            .toList();
        final originalIds = copied.map((node) => node.id).toSet();
        final page = await sandbox.mount(
          tester,
          nodes: [...copied, paragraphNode(text: 'left right')],
          selection: Selection(
            start: Position(path: [0]),
            end: Position(path: [copied.length - 1], offset: 1),
          ),
          selectionType: SelectionType.block,
        );
        expect(
          tester
              .widget<AppFlowyEditor>(find.byKey(page.key))
              .commandShortcutEvents,
          contains(same(customCopyCommand)),
        );
        final beforeCopy = page.json;
        await _copyKey(tester, sandbox);
        expect(page.json, beforeCopy);
        final encoded = sandbox.clipboard.lastWritten!.inAppJson!;
        final decoded = Document.fromJson(jsonDecode(encoded));
        expect(
          decoded.root.children.map((node) => node.type),
          copied.map((node) => node.type),
        );
        expect(
          decoded.root.children.map((node) => node.attributes),
          originalAttributes,
        );
        decoded.dispose();

        await page.select(
          tester,
          Selection.collapsed(Position(path: [copied.length], offset: 5)),
        );
        page.clipboardState.didCut();
        await _pasteKey(tester, sandbox, page);

        _expectDocument(
          page,
          types: [
            ...copied.map((node) => node.type),
            _paragraph,
            ...copied.map((node) => node.type),
            _paragraph,
          ],
          paragraphs: ['left ', 'right'],
        );
        final inserted = page.nodes.skip(copied.length + 1).take(copied.length);
        expect(inserted.map((node) => node.attributes), originalAttributes);
        expect(inserted.any((node) => originalIds.contains(node.id)), isFalse);
        expect(page.clipboardState.isCut, isFalse);
        expect(sandbox.clipboard.writes, 1);
        expect(
          sandbox.storage.reads,
          0,
          reason: 'An in-app block reference is not an OS attachment import',
        );
        expect(page.writes, 1);
        _expectTail(page, index: copied.length * 2 + 1, text: 'right');
      });
    }

    _test('valid in-app media JSON precedes native files, PNG and HTML',
        (tester, sandbox) async {
      final photo = await _source(tester, sandbox, 'copied.png', bytes: _png);
      final other = await _source(tester, sandbox, 'not-the-copied-file.pdf');
      final copied = customImageNode(url: photo.path, width: 211);
      sandbox.clipboard.items = [
        _fileItem(
          other,
          inAppJson: _inApp([copied]),
          plainText: other.path,
          html: '<img src="$_privateImageUrl">',
          raster: _png,
        ),
      ];
      final page = await sandbox.mount(
        tester,
        nodes: [paragraphNode(text: 'leftREMOVEright')],
        selection: Selection.single(path: [0], startOffset: 4, endOffset: 10),
      );

      await _pasteKey(tester, sandbox, page);

      _expectDocument(
        page,
        types: [_paragraph, _image, _paragraph],
        paragraphs: ['left', 'right'],
      );
      // Clipboard JSON intentionally omits absent/null attributes.
      expect(page.attachments.single.toJson(), copied.toJson());
      expect(sandbox.storage.reads, 0);
    });

    for (final (label, values) in <(String, Map<String, Object?>)>[
      ('ordinary text', {'NativeShell_CF_13': 'pasted words'}),
      (
        'HTML',
        {
          'text/html': '<p><strong>bold</strong> and <em>italic</em></p>',
          'NativeShell_CF_13': 'wrong plain alternative',
        },
      ),
      ('Markdown formatting', {'NativeShell_CF_13': '**bold** and *italic*'}),
    ]) {
      _test('Ctrl+V retains $label paste into a selected text range',
          (tester, sandbox) async {
        sandbox.clipboard.items = [_ClipboardItem(values)];
        final page = await sandbox.mount(
          tester,
          nodes: [paragraphNode(text: 'left REPLACE right')],
          selection: Selection.single(path: [0], startOffset: 5, endOffset: 12),
        );

        await _pasteKey(tester, sandbox, page);

        _expectDocument(
          page,
          types: [_paragraph],
          paragraphs: [
            label == 'ordinary text'
                ? 'left pasted words right'
                : 'left bold and italic right',
          ],
        );
        if (label != 'ordinary text') {
          _expectStyle(page.nodes.single, 'bold', AppFlowyRichTextKeys.bold);
          _expectStyle(
            page.nodes.single,
            'italic',
            AppFlowyRichTextKeys.italic,
          );
        }
        expect(page.attachments, isEmpty);
        expect(sandbox.storage.reads, 0);
      });
    }

    _test('Ctrl+C and Ctrl+V retain in-app rich-text attributes',
        (tester, sandbox) async {
      final page = await sandbox.mount(
        tester,
        nodes: [
          paragraphNode(
            delta: Delta()
              ..insert('bold', attributes: {AppFlowyRichTextKeys.bold: true})
              ..insert(' and ')
              ..insert(
                'italic',
                attributes: {AppFlowyRichTextKeys.italic: true},
              ),
          ),
          paragraphNode(text: 'left right'),
        ],
        selection: Selection.single(path: [0], startOffset: 0, endOffset: 15),
      );
      await _copyKey(tester, sandbox);
      expect(sandbox.clipboard.lastWritten!.plainText, 'bold and italic');
      await page.select(
        tester,
        Selection.collapsed(Position(path: [1], offset: 5)),
      );

      await _pasteKey(tester, sandbox, page);

      _expectDocument(
        page,
        types: [_paragraph, _paragraph],
        paragraphs: ['bold and italic', 'left bold and italicright'],
      );
      _expectStyle(page.nodes.last, 'bold', AppFlowyRichTextKeys.bold);
      _expectStyle(page.nodes.last, 'italic', AppFlowyRichTextKeys.italic);
      expect(sandbox.storage.reads, 0);
    });

    _test(
        'Ctrl+Shift+V keeps literal plain text instead of files or formatting',
        (tester, sandbox) async {
      final photo = await _source(tester, sandbox, 'photo.png', bytes: _png);
      const literal = '**literal** <b>not HTML</b>';
      sandbox.clipboard.items = [
        _fileItem(
          photo,
          plainText: literal,
          html: '<p><strong>formatted alternative</strong></p>',
          inAppJson: _inApp([customImageNode(url: photo.path)]),
          raster: _png,
        ),
      ];
      final page = await sandbox.mount(
        tester,
        nodes: [paragraphNode(text: 'left REPLACE right')],
        selection: Selection.single(path: [0], startOffset: 5, endOffset: 12),
      );

      await _pasteKey(tester, sandbox, page, plain: true);

      _expectDocument(
        page,
        types: [_paragraph],
        paragraphs: ['left $literal right'],
      );
      expect(
        page.nodes.single.delta!.whereType<TextInsert>().every(
              (run) => run.attributes?.isEmpty ?? true,
            ),
        isTrue,
      );
      expect(sandbox.storage.reads, 0);
    });
  });

  group('representations and durable imports', () {
    _test(
        'raw PNG beats a private HTML image URL and outlives scratch deletion',
        (tester, sandbox) async {
      final item = _ClipboardItem(
        {
          'text/html': '<img src="$_privateImageUrl">',
          'NativeShell_CF_13': _privateImageUrl,
        },
        files: {Formats.png: _png},
      );
      sandbox.clipboard.items = [item];
      final page = await sandbox.mount(
        tester,
        nodes: [paragraphNode(text: 'left right')],
        selection: Selection.collapsed(Position(path: [0], offset: 5)),
      );

      await _pasteDirect(
        tester,
        sandbox,
        page,
        attachments: AttachmentPasteService(
          temporaryDirectory: () async => sandbox.scratch,
        ),
      );

      _expectDocument(
        page,
        types: [_paragraph, _image, _paragraph],
        paragraphs: ['left ', 'right'],
      );
      expect(item.fileReads, [Formats.png]);
      expect(item.uriSynthesisRequests, [false]);
      final node = page.attachments.single;
      expect(
        node.attributes[CustomImageBlockKeys.imageType],
        CustomImageType.local.toIntValue(),
      );
      final saved = File(node.attributes[CustomImageBlockKeys.url] as String);
      expect(p.dirname(saved.path), p.join(sandbox.managed.path, 'images'));
      expect(p.extension(saved.path), '.png');
      expect(page.json, isNot(contains(_privateImageUrl)));
      expect(sandbox.storage.reads, 1);
      await tester.runAsync(() async {
        expectSync(await sandbox.scratch.list().toList(), isEmpty);
        expectSync(await _storedFiles(sandbox), hasLength(1));
        await sandbox.scratch.delete(recursive: true);
        expectSync(await saved.readAsBytes(), _png);
      });
      _expectTail(page, index: 2, text: 'right');
    });

    for (final (label, malformed) in [
      ('invalid JSON', '{not-json'),
      ('wrong top-level shape', '[]'),
      ('invalid document shape', '{"document":false}'),
      ('empty in-app document', '{"document":{"type":"page","children":[]}}'),
    ]) {
      _test('$label falls back to native files ahead of HTML and path text',
          (tester, sandbox) async {
        final file = await _source(tester, sandbox, 'real attachment.pdf');
        sandbox.clipboard.items = [
          _fileItem(
            file,
            inAppJson: malformed,
            html: '<img src="$_privateImageUrl"><p>wrong alternative</p>',
            plainText: file.path,
          ),
        ];
        final page = await sandbox.mount(
          tester,
          nodes: [paragraphNode(text: 'left right')],
          selection: Selection.collapsed(Position(path: [0], offset: 5)),
        );

        await _pasteKey(tester, sandbox, page);

        _expectDocument(
          page,
          types: [_paragraph, _file, _paragraph],
          paragraphs: ['left ', 'right'],
        );
        await _expectManagedCopies(
          tester,
          sandbox,
          page.attachments,
          [file],
          images: [false],
        );
        expect(page.writes, 1);
        expect(find.byType(DesktopToast), findsNothing);
      });
    }

    _test('malformed in-app JSON without attachments retains the HTML fallback',
        (tester, sandbox) async {
      sandbox.clipboard.items = [
        _ClipboardItem({
          'io.appflowy.InAppJsonType': utf8.encode('{broken'),
          'text/html': '<p><strong>HTML survives</strong></p>',
          'NativeShell_CF_13': 'wrong alternative',
        }),
      ];
      final page = await sandbox.mount(tester);

      await _pasteKey(tester, sandbox, page);

      _expectDocument(page, types: [_paragraph], paragraphs: ['HTML survives']);
      _expectStyle(
        page.nodes.single,
        'HTML survives',
        AppFlowyRichTextKeys.bold,
      );
      expect(sandbox.storage.reads, 0);
    });
  });

  group('real selection replacement transactions', () {
    for (final (name, lines, start, end, types, paragraphs, tailIndex) in <(
      String,
      List<String>,
      (int, int),
      (int, int),
      List<String>,
      List<String>,
      int
    )>[
      ('empty', [''], (0, 0), (0, 0), [_image, _paragraph], [''], 1),
      ('start', ['alpha'], (0, 0), (0, 0), [_image, _paragraph], ['alpha'], 1),
      (
        'middle',
        ['alphaomega'],
        (0, 5),
        (0, 5),
        [_paragraph, _image, _paragraph],
        ['alpha', 'omega'],
        2,
      ),
      (
        'end',
        ['alpha'],
        (0, 5),
        (0, 5),
        [_paragraph, _image, _paragraph],
        ['alpha', ''],
        2,
      ),
      (
        'forward selected text',
        ['leftREMOVEright'],
        (0, 4),
        (0, 10),
        [_paragraph, _image, _paragraph],
        ['left', 'right'],
        2,
      ),
      (
        'backward selected text',
        ['leftREMOVEright'],
        (0, 10),
        (0, 4),
        [_paragraph, _image, _paragraph],
        ['left', 'right'],
        2,
      ),
      (
        'forward multiline range',
        ['leftREMOVE', 'REMOVEright'],
        (0, 4),
        (1, 6),
        [_paragraph, _image, _paragraph],
        ['left', 'right'],
        2,
      ),
      (
        'backward multiline range',
        ['leftREMOVE', 'REMOVEright'],
        (1, 6),
        (0, 4),
        [_paragraph, _image, _paragraph],
        ['left', 'right'],
        2,
      ),
    ]) {
      _test('doPaste at $name never drops the image or surviving text',
          (tester, sandbox) async {
        final photo = await _source(tester, sandbox, 'photo.png', bytes: _png);
        sandbox.clipboard.items = [_fileItem(photo, plainText: photo.path)];
        final page = await sandbox.mount(
          tester,
          nodes: lines.map((text) => paragraphNode(text: text)).toList(),
          selection: Selection(
            start: Position(path: [start.$1], offset: start.$2),
            end: Position(path: [end.$1], offset: end.$2),
          ),
        );

        await _pasteDirect(tester, sandbox, page);

        _expectDocument(page, types: types, paragraphs: paragraphs);
        expect(page.attachments, hasLength(1));
        expect(
          page.writes,
          1,
          reason: 'Replacement and media insertion are one transaction',
        );
        _expectTail(page, index: tailIndex, text: paragraphs.last);
        await _expectManagedCopies(
          tester,
          sandbox,
          page.attachments,
          [photo],
          images: [true],
        );
      });
    }

    _test(
        'a backward block selection replaces the selected media, not neighbors',
        (tester, sandbox) async {
      final oldPhoto = customImageNode(url: 'synthetic-old-photo');
      final oldFile = fileNode(url: 'synthetic-old-file', name: 'old.pdf');
      final file = await _source(tester, sandbox, 'replacement.pdf');
      sandbox.clipboard.items = [_fileItem(file)];
      final page = await sandbox.mount(
        tester,
        nodes: [
          paragraphNode(text: 'before'),
          oldPhoto,
          oldFile,
          paragraphNode(text: 'after'),
        ],
        selection: Selection(
          start: Position(path: [2], offset: 1),
          end: Position(path: [1]),
        ),
        selectionType: SelectionType.block,
      );

      await _pasteDirect(tester, sandbox, page);

      _expectDocument(
        page,
        types: [_paragraph, _file, _paragraph, _paragraph],
        paragraphs: ['before', '', 'after'],
      );
      expect(
        page.attachments.single.attributes[FileBlockKeys.name],
        'replacement.pdf',
      );
      expect(
        page.nodes
            .any((node) => node.id == oldPhoto.id || node.id == oldFile.id),
        isFalse,
      );
      expect(page.writes, 1);
      _expectTail(page, index: 2);
    });

    _test(
        'an inline caret on an image inserts after it rather than ignoring paste',
        (tester, sandbox) async {
      final original = customImageNode(url: 'synthetic-existing-image');
      final attributes = Map<String, dynamic>.of(original.attributes);
      final file = await _source(tester, sandbox, 'next.pdf');
      sandbox.clipboard.items = [_fileItem(file)];
      final page = await sandbox.mount(
        tester,
        nodes: [original, paragraphNode(text: 'following text')],
      );

      await _pasteDirect(tester, sandbox, page);

      _expectDocument(
        page,
        types: [_image, _file, _paragraph, _paragraph],
        paragraphs: ['', 'following text'],
      );
      expect(page.nodes.first.attributes, attributes);
      _expectTail(page, index: 2);
    });
  });

  group('guards, pending work and serialization', () {
    for (final guard in ['null selection', 'read-only', 'disposed']) {
      _test('$guard prevents clipboard reads and storage work',
          (tester, sandbox) async {
        final photo = await _source(tester, sandbox, 'photo.png', bytes: _png);
        sandbox.clipboard.items = [_fileItem(photo)];
        final page = await sandbox.mount(tester);
        if (guard == 'null selection') {
          await page.select(tester, null);
        } else if (guard == 'read-only') {
          page.editor.editable = false;
        } else {
          await tester.pumpWidget(const SizedBox.shrink());
          page.editor.dispose();
        }
        final before = page.json;
        expect(customPasteCommand.handler(page.editor), KeyEventResult.ignored);

        await _pasteDirect(tester, sandbox, page);

        expect(page.json, before);
        expect(page.writes, 0);
        expect(sandbox.clipboard.reads, 0);
        expect(sandbox.storage.reads, 0);
      });
    }

    for (final provideBloc in [false, true]) {
      _test(
          '${provideBloc ? 'empty document id' : 'missing DocumentBloc'} fails safely',
          (tester, sandbox) async {
        final file = await _source(tester, sandbox, 'report.pdf');
        sandbox.clipboard.items = [_fileItem(file, plainText: file.path)];
        final page = await sandbox.mount(
          tester,
          documentId: '',
          provideBloc: provideBloc,
          nodes: [paragraphNode(text: 'keep selected words')],
          selection: Selection.single(path: [0], startOffset: 5, endOffset: 13),
        );
        final before = page.json;
        final selection = page.editor.selection;

        await _pasteDirect(tester, sandbox, page);

        expect(page.json, before);
        expect(page.editor.selection, selection);
        expect(page.writes, 0);
        expect(sandbox.storage.reads, 0);
        await _expectFailureToast(tester);
      });
    }

    for (final closed in [false, true]) {
      _test(
          'an already ${closed ? 'closed' : 'closing'} document is not written',
          (tester, sandbox) async {
        final file = await _source(tester, sandbox, 'report.pdf');
        sandbox.clipboard.items = [_fileItem(file)];
        final page = await sandbox.mount(tester);
        if (closed) {
          await tester.runAsync(page.bloc.close);
          expect(page.bloc.isClosed, isTrue);
        } else {
          page.bloc.isClosing = true;
        }
        final before = page.json;

        await _pasteDirect(tester, sandbox, page);

        // Intentionally strict: a still-mounted page can outlive bloc.close().
        expect(page.json, before);
        expect(page.writes, 0);
        expect(sandbox.storage.reads, 0);
      });
    }

    for (final change in [
      _PendingChange.moveSelection,
      _PendingChange.moveAwayAndBack,
      _PendingChange.clearSelection,
      _PendingChange.readOnly,
      _PendingChange.permissionAwayAndBack,
      _PendingChange.localText,
    ]) {
      _test('${change.name} during the clipboard read cancels before import',
          (tester, sandbox) async {
        final photo = await _source(tester, sandbox, 'photo.png', bytes: _png);
        sandbox.clipboard.items = [_fileItem(photo, plainText: photo.path)];
        final page = await sandbox.mount(
          tester,
          nodes: [paragraphNode(text: 'original text')],
          selection: Selection.collapsed(Position(path: [0], offset: 4)),
        );
        late _ClipboardGate gate;
        late Future<void> pending;
        await tester.runAsync(() async {
          gate = sandbox.clipboard.delayNextRead();
          pending = sandbox.beginPaste(page);
          await gate.entered.future.timeout(_deadline);
          // The lock must already cover the clipboard read, not just saving.
          await doPaste(page.editor);
        });
        expect(sandbox.clipboard.reads, 1);
        expect(page.writes, 0);
        await _changeWhilePending(tester, page, change);
        final expected = page.json;
        final selection = page.editor.selection;
        final writes = page.writes;

        await tester.runAsync(() async {
          gate.succeed();
          await pending.timeout(_deadline);
        });
        await tester.pump();

        expect(page.json, expected);
        expect(page.editor.selection, selection);
        expect(page.writes, writes);
        expect(sandbox.storage.reads, 0);
        expect(await tester.runAsync(() => _storedFiles(sandbox)), isEmpty);
      });
    }

    for (final change in _PendingChange.values) {
      _test(
          '${change.name} during a save rejects stale insertion and deletes its copy',
          (tester, sandbox) async {
        final photo = await _source(tester, sandbox, 'photo.png', bytes: _png);
        sandbox.clipboard.items = [_fileItem(photo, plainText: photo.path)];
        final page = await sandbox.mount(
          tester,
          nodes: [paragraphNode(text: 'original text')],
          selection: Selection.collapsed(Position(path: [0], offset: 4)),
        );
        final saver = sandbox.controlledSaver();
        late Future<void> pending;
        late _SaveCall call;
        late File copy;
        await tester.runAsync(() async {
          pending = sandbox.beginPaste(page, attachments: saver.service);
          call = await saver.callAt(0).timeout(_deadline);
          copy = await saver.materialize(call);
        });
        expect(page.writes, 0);
        expect(call.documentId, page.bloc.documentId);
        expect(call.isLocalMode, isTrue);
        expect(call.isImage, isTrue);
        expect(await tester.runAsync(copy.exists), isTrue);
        await _changeWhilePending(tester, page, change);
        final expected = page.json;
        final selection = page.editor.selection;
        final writes = page.writes;

        await tester.runAsync(() async {
          call.succeed(copy.path);
          await pending.timeout(_deadline);
        });
        await tester.pump();

        expect(
          page.json,
          expected,
          reason: 'Old media must not replace a newer draft',
        );
        expect(page.editor.selection, selection);
        expect(page.writes, writes);
        expect(await tester.runAsync(copy.exists), isFalse);
        expect(await tester.runAsync(photo.readAsBytes), _png);
        expect(await tester.runAsync(() => _storedFiles(sandbox)), isEmpty);
        expect(
          find.byType(DesktopToast),
          findsNothing,
          reason: 'Cancelling a stale operation is not an upload error',
        );
      });
    }

    _test(
        'file saves are serial, pending paste cannot reenter, and a later paste works',
        (tester, sandbox) async {
      final files = await _mixedSources(tester, sandbox);
      final next = await _source(tester, sandbox, 'later.pdf');
      sandbox.clipboard.items = files.map(_fileItem).toList();
      final page = await sandbox.mount(tester);
      final saver = sandbox.controlledSaver();
      late Future<void> pending;
      await tester.runAsync(() async {
        pending = sandbox.beginPaste(page, attachments: saver.service);
        await saver.callAt(0).timeout(_deadline);
      });
      expect(saver.calls, hasLength(1));
      expect(saver.active, 1);
      expect(page.writes, 0);
      // The pending operation owns the old clipboard snapshot; rejected
      // reentry must not read or queue the replacement clipboard content.
      sandbox.clipboard.items = [_fileItem(next)];
      await tester
          .runAsync(() => doPaste(page.editor, attachments: saver.service));
      expect(sandbox.clipboard.reads, 1);
      expect(saver.calls, hasLength(1));

      for (var index = 0; index < files.length; index++) {
        expect(saver.calls, hasLength(index + 1));
        expect(page.writes, 0);
        await tester.runAsync(() async {
          final call = saver.calls[index];
          final copy = await saver.materialize(call);
          call.succeed(copy.path);
          if (index + 1 < files.length) {
            await saver.callAt(index + 1).timeout(_deadline);
          } else {
            await pending.timeout(_deadline);
          }
        });
      }
      await tester.pump();
      await tester.pump();
      expect(saver.maximumActive, 1);
      expect(saver.active, 0);
      expect(
        saver.calls.map((call) => call.path),
        files.map((file) => file.path),
      );
      expect(
        saver.calls.map((call) => call.isImage),
        [true, false, false, false, true],
      );
      _expectDocument(
        page,
        types: [_image, _file, _file, _file, _image, _paragraph],
        paragraphs: [''],
      );
      expect(page.writes, 1);
      _expectTail(page, index: 5);

      // Awaited completion, not an arbitrary delay, releases the per-editor lock.
      await _pasteDirect(tester, sandbox, page);
      expect(sandbox.clipboard.reads, 2);
      expect(page.writes, 2);
      expect(page.attachments, hasLength(6));
      expect(page.attachments.last.attributes[FileBlockKeys.name], 'later.pdf');
      _expectTail(page, index: 6);
    });
  });

  group('failure, cleanup and retry', () {
    for (final directory in [false, true]) {
      _test(
          '${directory ? 'directory' : 'missing file'} aborts the entire native batch',
          (tester, sandbox) async {
        final photo = await _source(tester, sandbox, 'valid.png', bytes: _png);
        final unavailable = directory
            ? sandbox.exports.path
            : p.join(sandbox.exports.path, 'missing.pdf');
        sandbox.clipboard.items = [
          _fileItem(photo),
          _ClipboardItem({
            'NativeShell_CF_15': unavailable,
            'NativeShell_CF_13': unavailable,
            'text/html': '<p>must not replace the selection</p>',
          }),
        ];
        final page = await sandbox.mount(
          tester,
          nodes: [paragraphNode(text: 'keep this selection')],
          selection: Selection.single(path: [0], startOffset: 5, endOffset: 9),
        );
        final before = page.json;
        final selection = page.editor.selection;

        await _pasteKey(tester, sandbox, page);

        expect(page.json, before);
        expect(page.editor.selection, selection);
        expect(page.writes, 0);
        expect(
          sandbox.storage.reads,
          0,
          reason: 'The entire list must be preflighted before the first copy',
        );
        expect(await tester.runAsync(() => _storedFiles(sandbox)), isEmpty);
        expect(await tester.runAsync(photo.readAsBytes), _png);
        await _expectFailureToast(tester);
      });
    }

    for (final empty in <String?>[null, '']) {
      _test(
          'a saver returning ${empty == null ? 'null' : 'empty'} is not a successful paste',
          (tester, sandbox) async {
        final file = await _source(tester, sandbox, 'report.pdf');
        sandbox.clipboard.items = [_fileItem(file, plainText: file.path)];
        final page = await sandbox.mount(
          tester,
          nodes: [paragraphNode(text: 'keep me')],
          selection: Selection.single(path: [0], startOffset: 0, endOffset: 7),
        );
        final before = page.json;
        final selection = page.editor.selection;

        await _pasteDirect(
          tester,
          sandbox,
          page,
          attachments: AttachmentPasteService(
            saveFile: (
              path, {
              required documentId,
              required isLocalMode,
              required isImage,
            }) async =>
                empty,
          ),
        );

        expect(page.json, before);
        expect(page.editor.selection, selection);
        expect(page.writes, 0);
        await _expectFailureToast(tester);
      });
    }

    _test(
        'a delayed second-save failure cleans the first copy and permits retry',
        (tester, sandbox) async {
      final photo = await _source(tester, sandbox, 'photo.png', bytes: _png);
      final file = await _source(tester, sandbox, 'report.pdf');
      sandbox.clipboard.items = [
        _fileItem(photo, plainText: photo.path),
        _fileItem(file, html: '<p>wrong fallback</p>'),
      ];
      final page = await sandbox.mount(
        tester,
        mode: 'paper',
        nodes: [paragraphNode(text: 'leftREMOVEright')],
        selection: Selection.single(path: [0], startOffset: 4, endOffset: 10),
      );
      final before = page.json;
      final selection = page.editor.selection;
      final saver = sandbox.controlledSaver();
      final sensitive = _SensitiveError();
      late Future<void> pending;
      late File firstCopy;
      late _SaveCall failing;
      await tester.runAsync(() async {
        pending = sandbox.beginPaste(page, attachments: saver.service);
        final first = await saver.callAt(0).timeout(_deadline);
        firstCopy = await saver.materialize(first);
        first.succeed(firstCopy.path);
        failing = await saver.callAt(1).timeout(_deadline);
      });
      expect(page.json, before);
      expect(await tester.runAsync(firstCopy.exists), isTrue);

      await tester.runAsync(() async {
        failing.fail(sensitive);
        await pending.timeout(_deadline);
      });
      await tester.pump();
      await tester.pump();

      expect(page.json, before);
      expect(page.editor.selection, selection);
      expect(page.writes, 0);
      expect(await tester.runAsync(firstCopy.exists), isFalse);
      expect(await tester.runAsync(photo.readAsBytes), _png);
      expect(await tester.runAsync(file.exists), isTrue);
      expect(sensitive.stringified, isFalse);
      await _expectFailureToast(tester);
      expect(tester.takeException(), isNull);
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump();

      await _pasteDirect(tester, sandbox, page);

      _expectDocument(
        page,
        types: [_paragraph, _image, _file, _paragraph],
        paragraphs: ['left', 'right'],
      );
      expect(page.writes, 1);
      expect(sandbox.clipboard.reads, 2);
      await _expectManagedCopies(
        tester,
        sandbox,
        page.attachments,
        [photo, file],
        images: [true, false],
      );
    });

    _test(
        'raw screenshot failure deletes scratch without changing the document',
        (tester, sandbox) async {
      sandbox.clipboard.items = [
        _ClipboardItem({}, files: {Formats.png: _png}),
      ];
      final page = await sandbox.mount(tester);
      final before = page.json;
      final sensitive = _SensitiveError();
      String? scratchFile;

      await _pasteDirect(
        tester,
        sandbox,
        page,
        attachments: AttachmentPasteService(
          temporaryDirectory: () async => sandbox.scratch,
          saveFile: (
            path, {
            required documentId,
            required isLocalMode,
            required isImage,
          }) async {
            scratchFile = path;
            throw sensitive;
          },
        ),
      );

      expect(scratchFile, isNotNull);
      expect(p.isWithin(sandbox.scratch.path, scratchFile!), isTrue);
      expect(await tester.runAsync(() => File(scratchFile!).exists()), isFalse);
      expect(
        await tester.runAsync(() => sandbox.scratch.list().toList()),
        isEmpty,
      );
      expect(page.json, before);
      expect(page.writes, 0);
      expect(sensitive.stringified, isFalse);
      await _expectFailureToast(tester);
    });

    _test(
        'the actual Ctrl+V handler consumes an async storage failure and can retry',
        (tester, sandbox) async {
      final file = await _source(tester, sandbox, 'report.pdf');
      sandbox.clipboard.items = [_fileItem(file, plainText: file.path)];
      final page = await sandbox.mount(
        tester,
        mode: 'dark',
        nodes: [paragraphNode(text: 'keep these words')],
        selection: Selection.single(path: [0], startOffset: 5, endOffset: 10),
      );
      final before = page.json;
      final selection = page.editor.selection;
      late _StorageGate gate;
      late Future<void> finished;
      final sensitive = _SensitiveError();
      await tester.runAsync(() async {
        gate = sandbox.storage.delayNextRead();
        finished = page.clipboardState.nextPaste();
        final handled = await _controlKey(tester, LogicalKeyboardKey.keyV);
        expectSync(handled, isTrue);
        await gate.entered.future.timeout(_deadline);
      });
      expect(page.json, before);
      expect(page.clipboardState.pastes, 0);

      await tester.runAsync(() async {
        gate.result.completeError(sensitive, StackTrace.current);
        await finished.timeout(_deadline);
      });
      await tester.pump();
      await tester.pump();

      expect(page.json, before);
      expect(page.editor.selection, selection);
      expect(page.writes, 0);
      expect(sensitive.stringified, isFalse);
      expect(page.clipboardState.pastes, 1);
      await _expectFailureToast(tester);
      expect(tester.takeException(), isNull);
      toastification.dismissAll(delayForAnimation: false);
      await tester.pump();

      await _pasteKey(tester, sandbox, page);

      _expectDocument(
        page,
        types: [_paragraph, _file, _paragraph],
        paragraphs: ['keep ', ' words'],
      );
      expect(page.writes, 1);
      expect(page.clipboardState.pastes, 2);
      expect(await tester.runAsync(file.exists), isTrue);
    });

    _test(
        'a delayed unavailable clipboard does not escape the shortcut or poison retry',
        (tester, sandbox) async {
      final file = await _source(tester, sandbox, 'report.pdf');
      sandbox.clipboard.items = [_fileItem(file)];
      final page = await sandbox.mount(tester);
      final before = page.json;
      final sensitive = _SensitiveError();
      await tester.runAsync(() async {
        final gate = sandbox.clipboard.delayNextRead();
        final finished = page.clipboardState.nextPaste();
        expectSync(await _controlKey(tester, LogicalKeyboardKey.keyV), isTrue);
        await gate.entered.future.timeout(_deadline);
        gate.result.completeError(sensitive, StackTrace.current);
        await finished.timeout(_deadline);
      });
      await tester.pump();

      expect(page.json, before);
      expect(page.writes, 0);
      expect(sandbox.storage.reads, 0);
      expect(sensitive.stringified, isFalse);
      expect(tester.takeException(), isNull);

      await _pasteKey(tester, sandbox, page);

      _expectDocument(page, types: [_file, _paragraph], paragraphs: ['']);
      expect(page.writes, 1);
      expect(sandbox.clipboard.reads, 2);
    });
  });
}

enum _PendingChange {
  moveSelection,
  moveAwayAndBack,
  clearSelection,
  readOnly,
  permissionAwayAndBack,
  localText,
  remoteText,
  selectionType,
  unmount,
  disposeEditor,
  closingDocument,
  closedDocument,
}

Future<void> _changeWhilePending(
  WidgetTester tester,
  _Page page,
  _PendingChange change,
) async {
  final original = page.editor.selection;
  switch (change) {
    case _PendingChange.moveSelection:
    case _PendingChange.moveAwayAndBack:
      await page.select(
        tester,
        Selection.collapsed(Position(path: [0], offset: 1)),
      );
      if (change == _PendingChange.moveAwayAndBack) {
        await page.select(tester, original);
      }
    case _PendingChange.clearSelection:
      await page.select(tester, null);
    case _PendingChange.readOnly:
    case _PendingChange.permissionAwayAndBack:
      page.editor.editable = false;
      expect(page.editor.editable, isFalse);
      if (change == _PendingChange.permissionAwayAndBack) {
        page.editor.editable = true;
      }
    case _PendingChange.localText:
    case _PendingChange.remoteText:
      // Keep the same caret and node identity: a selection-only comparison is
      // insufficient. The remote case uses the actual editor's remote path.
      await page.editor.apply(
        page.editor.transaction..insertText(page.nodes.first, 0, 'new '),
        withUpdateSelection: false,
        isRemote: change == _PendingChange.remoteText,
      );
      expect(page.editor.selection, original);
      expect(page.nodes.first.delta!.toPlainText(), 'new original text');
      await tester.pump();
    case _PendingChange.selectionType:
      page.editor.selectionType = SelectionType.block;
    case _PendingChange.unmount:
    case _PendingChange.disposeEditor:
      await tester.pumpWidget(const SizedBox.shrink());
      if (change == _PendingChange.disposeEditor) {
        page.editor.dispose();
        expect(page.editor.isDisposed, isTrue);
      }
    case _PendingChange.closingDocument:
      page.bloc.isClosing = true;
    case _PendingChange.closedDocument:
      await tester.runAsync(page.bloc.close);
      expect(page.bloc.isClosed, isTrue);
  }
}

void _test(
  String name,
  Future<void> Function(WidgetTester, _Sandbox) body,
) {
  testWidgets(
    name,
    (tester) async {
      final sandbox = (await tester.runAsync(_Sandbox.create))!;
      getIt.pushNewScope();
      getIt.registerSingleton<ApplicationDataStorage>(sandbox.storage);
      getIt.registerSingleton<ClipboardService>(
        _RoundTripClipboardService(sandbox.clipboard),
      );
      ClipboardService.mockSetData(null);
      try {
        await body(tester, sandbox);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await sandbox.dispose(tester);
        } finally {
          ClipboardService.mockSetData(null);
          await tester.runAsync(getIt.popScope);
        }
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _Sandbox {
  _Sandbox(this.root)
      : exports = Directory(p.join(root.path, 'clipboard-exports')),
        scratch = Directory(p.join(root.path, 'clipboard-scratch')),
        managed = Directory(p.join(root.path, 'synthetic-application-data')) {
    storage = _Storage(managed.path);
  }

  static Future<_Sandbox> create() async {
    final sandbox = _Sandbox(
      await Directory.systemTemp.createTemp('attachment_paste_workflow_'),
    );
    await sandbox.exports.create();
    await sandbox.scratch.create();
    await sandbox.managed.create();
    return sandbox;
  }

  final Directory root;
  final Directory exports;
  final Directory scratch;
  final Directory managed;
  late final _Storage storage;
  final clipboard = _Clipboard();
  final pages = <_Page>[];
  final _savers = <_ControlledSaver>[];
  final _operations = <Future<void>>[];

  Future<_Page> mount(
    WidgetTester tester, {
    String mode = 'light',
    List<Node>? nodes,
    Selection? selection,
    SelectionType selectionType = SelectionType.inline,
    String documentId = 'synthetic-paste-document',
    bool provideBloc = true,
  }) async {
    final page = _Page(nodes ?? [paragraphNode()], documentId);
    pages.add(page);
    final theme = _theme(mode).copyWith(platform: TargetPlatform.windows);
    final defaults = AppFlowyDefaultTheme();
    final appTheme = PremiumTheme.appFlowyTheme(
      base: mode == 'dark' ? defaults.dark() : defaults.light(),
      palette: theme.extension<PremiumThemeExtension>()!,
      brightness: theme.brightness,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          if (provideBloc) BlocProvider<DocumentBloc>.value(value: page.bloc),
          Provider<ClipboardState>.value(value: page.clipboardState),
        ],
        child: EasyLocalization(
          supportedLocales: const [Locale('en', 'US')],
          path: 'assets/translations',
          fallbackLocale: const Locale('en', 'US'),
          saveLocale: false,
          assetLoader: _LoadedTranslations(_translations),
          child: Builder(
            builder: (context) => MaterialApp(
              locale: const Locale('en', 'US'),
              localizationsDelegates: context.localizationDelegates,
              theme: theme,
              themeAnimationDuration: Duration.zero,
              builder: (_, child) =>
                  AppFlowyTheme(data: appTheme, child: child!),
              home: Scaffold(
                body: Center(
                  child: SizedBox(
                    width: 720,
                    height: 560,
                    child: AppFlowyEditor(
                      key: page.key,
                      editorState: page.editor,
                      focusNode: page.focus,
                      disableAutoScroll: true,
                      editorStyle: const EditorStyle.desktop(
                        padding: EdgeInsets.all(24),
                      ),
                      // This is the application's registration, not a test
                      // shortcut whose callback happens to call doPaste.
                      commandShortcutEvents:
                          page_shortcuts.commandShortcutEvents,
                      blockComponentBuilders: {
                        ...standardBlockComponentBuilderMap,
                        _image: _AttachmentBuilder(),
                        _file: _AttachmentBuilder(),
                      },
                      contextMenuItems: const [],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
    expect(find.byKey(page.key), findsOneWidget);
    expect(page.editor.document.root.context?.mounted, isTrue);
    expect(page.editor.service.keyboardService, isNotNull);
    await page.select(
      tester,
      selection ?? Selection.collapsed(Position(path: [0])),
      type: selectionType,
    );
    return page;
  }

  Future<void> beginPaste(
    _Page page, {
    AttachmentPasteService attachments = const AttachmentPasteService(),
  }) {
    final future = doPaste(page.editor, attachments: attachments);
    _operations.add(future);
    return future;
  }

  _ControlledSaver controlledSaver() {
    final saver = _ControlledSaver(managed);
    _savers.add(saver);
    return saver;
  }

  Future<void> dispose(WidgetTester tester) async {
    // Release controlled work even if a preceding assertion fails. No pending
    // native I/O or test-created future is left for the next case to inherit.
    await tester.runAsync(() async {
      clipboard.releasePending();
      storage.releasePending();
      for (final saver in _savers) {
        saver.abort();
      }
      await Future.wait(_operations).timeout(_deadline);
    });
    // showCustom inserts on a real-clock 100ms timer (doPaste ran in runAsync).
    // Let it finish before dismissing; otherwise it leaks into the next case.
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 110)),
    );
    await tester.pump();
    toastification.dismissAll(delayForAnimation: false);
    // dismissAll(false) still schedules animation + overlay removal (650ms).
    await tester.pump(const Duration(milliseconds: 651));
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    for (final page in pages) {
      await tester.runAsync(page.subscription.cancel);
      if (!page.bloc.isClosed) await tester.runAsync(page.bloc.close);
      if (!page.editor.isDisposed) page.editor.dispose();
      page.editor.editableNotifier.dispose();
      page.focus.dispose();
      page.clipboardState.dispose();
    }
    await tester.pump();
    // This root was created above, never obtained from real preferences.
    await tester.runAsync(() => root.delete(recursive: true));
  }
}

class _Page {
  _Page(List<Node> nodes, String documentId)
      : editor =
            EditorState(document: Document(root: pageNode(children: nodes)))
              ..disableSealTimer = true {
    bloc = _DocumentBloc(editor, documentId);
    subscription = editor.transactionStream.listen(transactions.add);
  }

  final EditorState editor;
  final key = GlobalKey();
  final focus = FocusNode(debugLabel: 'attachment workflow page');
  final clipboardState = _ClipboardState();
  final transactions = <EditorTransactionValue>[];
  late final _DocumentBloc bloc;
  late final StreamSubscription<EditorTransactionValue> subscription;

  List<Node> get nodes => editor.document.root.children.toList();
  List<Node> get attachments =>
      nodes.where((node) => node.type == _image || node.type == _file).toList();
  String get json => jsonEncode(editor.document.toJson());
  int get writes => transactions
      .where(
        (event) =>
            event.$1 == TransactionTime.after && event.$2.operations.isNotEmpty,
      )
      .length;

  Future<void> select(
    WidgetTester tester,
    Selection? selection, {
    SelectionType type = SelectionType.inline,
  }) async {
    final selected = editor.updateSelectionWithReason(
      selection,
      reason: SelectionUpdateReason.uiEvent,
      customSelectionType: type,
    );
    if (selection != null) focus.requestFocus();
    await tester.pump();
    await selected;
    await tester.pump();
    expect(editor.selection, selection);
    expect(editor.selectionType, type);
    if (selection != null) expect(focus.hasFocus, isTrue);
  }
}

class _DocumentBloc extends Cubit<DocumentState> implements DocumentBloc {
  _DocumentBloc(EditorState editor, this.documentId)
      : super(
          DocumentState.initial()
              .copyWith(editorState: editor, isLoading: false),
        );

  @override
  final String documentId;

  @override
  bool get isLocalMode => true;

  @override
  bool isClosing = false;

  @override
  Future<void> close() {
    isClosing = true;
    return super.close();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ClipboardState extends ClipboardState {
  int pastes = 0;
  Completer<void>? _nextPaste;

  Future<void> nextPaste() {
    final completion = Completer<void>();
    _nextPaste = completion;
    return completion.future;
  }

  @override
  void didPaste() {
    super.didPaste();
    pastes++;
    final completion = _nextPaste;
    _nextPaste = null;
    completion?.complete();
  }
}

/// Rendering alone is substituted: all inserted objects are production Nodes.
/// No media_kit player, PDF backend, browser or authenticated image fetch runs.
class _AttachmentBuilder extends BlockComponentBuilder {
  @override
  BlockComponentWidget build(BlockComponentContext context) => _AttachmentBlock(
        key: context.node.key,
        node: context.node,
        configuration: configuration,
      );

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class _AttachmentBlock extends BlockComponentStatelessWidget {
  const _AttachmentBlock({
    super.key,
    required super.node,
    required super.configuration,
  });

  @override
  Widget build(BuildContext context) => SizedBox(
        key: ValueKey('attachment-${node.id}'),
        height: 40,
        child: Align(
          alignment: Alignment.centerLeft,
          child:
              Text(node.attributes[FileBlockKeys.name] as String? ?? node.type),
        ),
      );
}

class _LoadedTranslations extends AssetLoader {
  const _LoadedTranslations(this.translations);

  final Map<String, dynamic> translations;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      SynchronousFuture(translations);
}

class _Storage extends Fake implements ApplicationDataStorage {
  _Storage(this.path);

  final String path;
  int reads = 0;
  _StorageGate? _next;
  final _gates = <_StorageGate>[];

  _StorageGate delayNextRead() {
    final gate = _StorageGate();
    _gates.add(gate);
    _next = gate;
    return gate;
  }

  @override
  Future<String> getPath() {
    reads++;
    final gate = _next;
    _next = null;
    if (gate == null) return Future.value(path);
    gate.entered.complete();
    return gate.result.future;
  }

  void releasePending() {
    for (final gate in _gates) {
      if (!gate.result.isCompleted) gate.result.complete(path);
    }
  }
}

class _StorageGate {
  final entered = Completer<void>();
  final result = Completer<String>();
}

class _ControlledSaver {
  _ControlledSaver(this.directory);

  final Directory directory;
  final calls = <_SaveCall>[];
  final _arrivals = <int, Completer<_SaveCall>>{};
  bool _aborted = false;
  int active = 0;
  int maximumActive = 0;

  AttachmentPasteService get service => AttachmentPasteService(saveFile: save);

  Future<String?> save(
    String path, {
    required String documentId,
    required bool isLocalMode,
    required bool isImage,
  }) async {
    if (_aborted) return null;
    final call = _SaveCall(path, documentId, isLocalMode, isImage);
    calls.add(call);
    active++;
    if (active > maximumActive) maximumActive = active;
    _arrivals.remove(calls.length - 1)?.complete(call);
    try {
      return await call.result.future;
    } finally {
      active--;
    }
  }

  Future<_SaveCall> callAt(int index) {
    if (calls.length > index) return Future.value(calls[index]);
    return _arrivals.putIfAbsent(index, Completer<_SaveCall>.new).future;
  }

  Future<File> materialize(_SaveCall call) => File(call.path).copy(
        p.join(
          directory.path,
          'controlled-${calls.indexOf(call)}-${p.basename(call.path)}',
        ),
      );

  void abort() {
    _aborted = true;
    for (final call in calls) {
      if (!call.result.isCompleted) call.result.complete();
    }
  }
}

class _SaveCall {
  _SaveCall(this.path, this.documentId, this.isLocalMode, this.isImage);

  final String path;
  final String documentId;
  final bool isLocalMode;
  final bool isImage;
  final result = Completer<String?>();

  void succeed(String path) => result.complete(path);
  void fail(Object error) => result.completeError(error, StackTrace.current);
}

class _SensitiveError implements Exception {
  bool stringified = false;

  @override
  String toString() {
    stringified = true;
    return 'synthetic-private-path?token=must-not-be-rendered-or-logged';
  }
}

/// Read uses ClipboardService.getData unchanged, including all format codecs.
/// Only its native write endpoint is redirected for real Ctrl+C round trips.
class _RoundTripClipboardService extends ClipboardService {
  _RoundTripClipboardService(this.clipboard)
      : super(readClipboard: clipboard.read);

  final _Clipboard clipboard;

  @override
  Future<void> setData(ClipboardServiceData data) => clipboard.write(data);
}

class _Clipboard {
  List<ClipboardDataReader> items = [];
  ClipboardServiceData? lastWritten;
  int reads = 0;
  int writes = 0;
  Completer<void>? _nextWrite;
  _ClipboardGate? _nextRead;
  final _gates = <_ClipboardGate>[];

  Future<ClipboardReader?> read() {
    reads++;
    final reader = ClipboardReader(List<ClipboardDataReader>.of(items));
    final gate = _nextRead;
    _nextRead = null;
    if (gate == null) return Future.value(reader);
    gate.reader = reader;
    gate.entered.complete();
    return gate.result.future;
  }

  _ClipboardGate delayNextRead() {
    final gate = _ClipboardGate();
    _gates.add(gate);
    _nextRead = gate;
    return gate;
  }

  Future<void> nextWrite() {
    final completion = Completer<void>();
    _nextWrite = completion;
    return completion.future;
  }

  Future<void> write(ClipboardServiceData data) async {
    final values = <String, Object?>{};
    final representations = <FutureOr<EncodedData>>[
      if (data.plainText != null) Formats.plainText(data.plainText!),
      if (data.html != null) Formats.htmlText(data.html!),
      if (data.inAppJson != null) inAppJsonFormat(data.inAppJson!),
    ];
    for (final pending in representations) {
      final encoded = await pending;
      for (final representation in encoded.representations) {
        final serialized = representation.serialize() as Map;
        values[representation.format] = serialized['data'];
      }
    }
    items = [_ClipboardItem(values)];
    lastWritten = data;
    writes++;
    final completion = _nextWrite;
    _nextWrite = null;
    completion?.complete();
  }

  void releasePending() {
    for (final gate in _gates) {
      if (!gate.result.isCompleted) gate.succeed();
    }
  }
}

class _ClipboardGate {
  final entered = Completer<void>();
  final result = Completer<ClipboardReader?>();
  ClipboardReader? reader;

  void succeed() => result.complete(reader);
}

// Same platform-data seam as clipboard_service_test.dart, deliberately local
// to this file so concurrently authored clipboard/service suites are untouched.
class _ClipboardItem extends ClipboardDataReader
    implements PlatformDataProvider {
  _ClipboardItem(this.values, {this.files = const {}});

  final Map<String, Object?> values;
  final Map<FileFormat, Uint8List> files;
  final fileReads = <FileFormat?>[];
  final uriSynthesisRequests = <bool>[];

  @override
  List<DataFormat> getFormats(List<DataFormat> allFormats) => [
        for (final format in allFormats)
          if (files.containsKey(format) ||
              format is ValueFormat &&
                  format.codec.decodingFormats.any(values.containsKey))
            format,
      ];

  @override
  Future<T?> readValue<T extends Object>(ValueFormat<T> format) async {
    for (final platformFormat in format.codec.decodingFormats) {
      if (values.containsKey(platformFormat)) {
        return format.codec.decode(this, platformFormat);
      }
    }
    return null;
  }

  @override
  ReadProgress? getValue<T extends Object>(
    ValueFormat<T> format,
    AsyncValueChanged<T?> onValue, {
    ValueChanged<Object>? onError,
  }) =>
      throw UnimplementedError('The production service uses readValue');

  @override
  ReadProgress? getFile(
    FileFormat? format,
    AsyncValueChanged<DataReaderFile> onFile, {
    ValueChanged<Object>? onError,
    bool allowVirtualFiles = true,
    bool synthesizeFilesFromURIs = true,
  }) {
    fileReads.add(format);
    uriSynthesisRequests.add(synthesizeFilesFromURIs);
    final bytes = files[format];
    if (bytes == null) return null;
    unawaited(Future<void>.sync(() => onFile(_MemoryFile(bytes))));
    return _Progress();
  }

  @override
  Future<Object?> getData(String format) async => values[format];

  @override
  List<String> getAllFormats() => values.keys.toList();

  @override
  List<PlatformFormat> get platformFormats => getAllFormats();

  @override
  bool isSynthesized(DataFormat format) => false;

  @override
  bool isVirtual(DataFormat format) => false;

  @override
  Future<String?> getSuggestedName() async => null;

  @override
  Future<VirtualFileReceiver?> getVirtualFileReceiver({
    FileFormat? format,
  }) async =>
      null;
}

class _Progress extends Fake implements ReadProgress {}

class _MemoryFile extends Fake implements DataReaderFile {
  _MemoryFile(this.bytes);

  final Uint8List bytes;

  @override
  Future<Uint8List> readAll() async => bytes;
}

_ClipboardItem _fileItem(
  File file, {
  String? plainText,
  String? html,
  String? inAppJson,
  Uint8List? raster,
}) =>
    _ClipboardItem(
      {
        // CF_HDROP is decoded into one path per item by super_clipboard.
        'NativeShell_CF_15': file.path,
        if (plainText != null) 'NativeShell_CF_13': plainText,
        if (html != null) 'text/html': html,
        if (inAppJson != null)
          'io.appflowy.InAppJsonType': utf8.encode(inAppJson),
      },
      files: {if (raster != null) Formats.png: raster},
    );

Future<File> _source(
  WidgetTester tester,
  _Sandbox sandbox,
  String name, {
  List<int> bytes = const [1, 2, 3, 4],
}) async =>
    (await tester.runAsync(
      () => File(p.join(sandbox.exports.path, name))
          .writeAsBytes(bytes, flush: true),
    ))!;

Future<List<File>> _mixedSources(WidgetTester tester, _Sandbox sandbox) async =>
    [
      await _source(tester, sandbox, 'first # 100% 文.PNG', bytes: _png),
      await _source(tester, sandbox, 'document.pdf'),
      await _source(
        tester,
        sandbox,
        'movie.MP4',
        bytes: [0, 0, 0, 24, 102, 116, 121, 112],
      ),
      await _source(tester, sandbox, 'voice.MP3', bytes: [73, 68, 51, 4, 0, 0]),
      await _source(tester, sandbox, 'last.png', bytes: _png),
    ];

String _inApp(List<Node> nodes) =>
    jsonEncode(Document(root: pageNode(children: nodes)).toJson());

Future<void> _pasteDirect(
  WidgetTester tester,
  _Sandbox sandbox,
  _Page page, {
  AttachmentPasteService attachments = const AttachmentPasteService(),
}) async {
  final finished = await tester.runAsync(() async {
    await sandbox.beginPaste(page, attachments: attachments).timeout(_deadline);
    return true;
  });
  await tester.pump();
  await tester.pump();
  expect(
    finished,
    isTrue,
    reason: 'Await the real doPaste future, not a timer',
  );
  expect(tester.takeException(), isNull);
}

Future<bool> _controlKey(
  WidgetTester tester,
  LogicalKeyboardKey key, {
  bool shift = false,
}) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  try {
    if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    final handled = await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    return handled;
  } finally {
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }
}

Future<void> _pasteKey(
  WidgetTester tester,
  _Sandbox sandbox,
  _Page page, {
  bool plain = false,
}) async {
  expect(page.focus.hasFocus, isTrue);
  final reads = sandbox.clipboard.reads;
  final finished = await tester.runAsync(() async {
    // Create and await signals in the same real-I/O zone; a fake-clock
    // completer can otherwise strand an unawaited keyboard shortcut.
    final completed = page.clipboardState.nextPaste();
    final handled =
        await _controlKey(tester, LogicalKeyboardKey.keyV, shift: plain);
    if (!handled) return false;
    // didPaste is called by the real shortcut after doPaste's full future.
    await completed.timeout(_deadline);
    return true;
  });
  await tester.pump();
  await tester.pump();
  expect(finished, isTrue, reason: 'The registered page shortcut must finish');
  expect(sandbox.clipboard.reads, reads + 1);
  expect(tester.takeException(), isNull);
}

Future<void> _copyKey(WidgetTester tester, _Sandbox sandbox) async {
  final finished = await tester.runAsync(() async {
    final completed = sandbox.clipboard.nextWrite();
    if (!await _controlKey(tester, LogicalKeyboardKey.keyC)) return false;
    await completed.timeout(_deadline);
    return true;
  });
  await tester.pump();
  expect(finished, isTrue);
  expect(sandbox.clipboard.lastWritten?.inAppJson, isNotEmpty);
  expect(tester.takeException(), isNull);
}

void _expectDocument(
  _Page page, {
  required List<String> types,
  required List<String> paragraphs,
}) {
  expect(page.nodes.map((node) => node.type), types);
  expect(
    page.nodes
        .where((node) => node.delta != null)
        .map((node) => node.delta!.toPlainText()),
    paragraphs,
  );
  expect(
    page.nodes.map((node) => node.id).toSet(),
    hasLength(page.nodes.length),
  );
}

void _expectTail(_Page page, {required int index, String text = ''}) {
  final tail = page.nodes[index];
  expect(tail.type, _paragraph);
  expect(tail.delta!.toPlainText(), text);
  expect(
    tail.selectable,
    isNotNull,
    reason: 'The real paragraph renderer remains editable',
  );
  expect(page.editor.selection, Selection.collapsed(Position(path: [index])));
  expect(page.editor.selectionType, SelectionType.inline);
}

void _expectStyle(Node node, String text, String key) {
  final delta = node.delta!;
  final start = delta.toPlainText().indexOf(text);
  expect(start, isNonNegative);
  final slice = delta.slice(start, start + text.length);
  expect(slice.toPlainText(), text);
  expect(
    slice.whereType<TextInsert>().every((run) => run.attributes?[key] == true),
    isTrue,
  );
}

Future<void> _expectFailureToast(WidgetTester tester) async {
  await tester.pump();
  await tester.runAsync(
    () => Future<void>.delayed(const Duration(milliseconds: 110)),
  );
  // The notification's AnimatedList begins at zero extent. Advance both its
  // scheduled insertion and 600ms entrance before asserting visible content.
  await tester.pump(const Duration(milliseconds: 110));
  await tester.pump(const Duration(milliseconds: 601));
  // AnimatedList was started by the real-clock insertion callback. Drain its
  // completion in that zone before a retry dismisses the incoming item.
  await tester.runAsync(() async {});
  final finder = find.byType(DesktopToast);
  expect(finder, findsOneWidget);
  final toast = tester.widget<DesktopToast>(finder);
  expect(toast.type, ToastificationType.error);
  expect(toast.message, LocaleKeys.fileDropzone_uploadFailedDescription.tr());
  expect(toast.message, isNot(contains('synthetic-private')));
  expect(toast.message, isNot(contains('token=')));
}

Future<List<(File, Uint8List)>> _expectManagedCopies(
  WidgetTester tester,
  _Sandbox sandbox,
  List<Node> nodes,
  List<File> originals, {
  required List<bool> images,
}) async {
  expect(nodes, hasLength(originals.length));
  expect(images, hasLength(originals.length));
  final copies = <(File, Uint8List)>[];
  for (var index = 0; index < nodes.length; index++) {
    final node = nodes[index];
    final image = images[index];
    expect(node.type, image ? _image : _file);
    final path =
        node.attributes[image ? CustomImageBlockKeys.url : FileBlockKeys.url]
            as String;
    expect(
      p.dirname(path),
      p.join(sandbox.managed.path, image ? 'images' : 'files'),
    );
    expect(path, isNot(originals[index].path));
    expect(p.extension(path), p.extension(originals[index].path));
    if (image) {
      expect(
        node.attributes[CustomImageBlockKeys.imageType],
        CustomImageType.local.toIntValue(),
      );
      expect(node.attributes[CustomImageBlockKeys.align], 'center');
    } else {
      expect(
        node.attributes[FileBlockKeys.name],
        p.basename(originals[index].path),
      );
      expect(
        node.attributes[FileBlockKeys.urlType],
        FileUrlType.local.toIntValue(),
      );
      expect(node.attributes[FileBlockKeys.uploadedAt], isA<int>());
      expect(node.attributes[FileBlockKeys.uploadedAt] as int, greaterThan(0));
    }
    final original = (await tester.runAsync(originals[index].readAsBytes))!;
    final copy = File(path);
    expect(await tester.runAsync(copy.readAsBytes), original);
    copies.add((copy, original));
  }
  expect(
    copies.map((copy) => copy.$1.path).toSet(),
    hasLength(originals.length),
  );
  return copies;
}

Future<void> _removeExportsAndVerify(
  WidgetTester tester,
  _Sandbox sandbox,
  List<(File, Uint8List)> copies,
) async {
  sandbox.clipboard.items = [];
  await tester.runAsync(() async {
    await sandbox.exports.delete(recursive: true);
    for (final (file, bytes) in copies) {
      expectSync(await file.exists(), isTrue);
      expectSync(await file.readAsBytes(), bytes);
    }
  });
  await tester.pump();
}

Future<List<File>> _storedFiles(_Sandbox sandbox) async =>
    (await sandbox.managed.list(recursive: true).toList())
        .whereType<File>()
        .toList();

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );
