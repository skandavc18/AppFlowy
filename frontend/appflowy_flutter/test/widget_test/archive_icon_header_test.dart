import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_icon_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/materialized_file_builder.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy_backend/protobuf/flowy-user/date_time.pbenum.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:archive/archive.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'file_controls_test_support.dart';

const _picker = ValueKey('file-icon-picker-button');
const _duplicate = ValueKey('file-preview-identity-icon');

void main() {
  fileControlTestSetup();
  late Directory directory;
  late File file;
  setUp(() async {
    directory =
        await Directory.systemTemp.createTemp('archive-header-fixture-');
    final archive = Archive()
      ..addFile(ArchiveFile('Folder/nested.bin', 3, [1, 2, 3]))
      ..addFile(ArchiveFile('Unknown.bin', 2, [4, 5]));
    file = await File('${directory.path}/fixture.zip')
        .writeAsBytes(ZipEncoder().encode(archive)!);
  });
  tearDown(() async => directory.delete(recursive: true));

  for (final appearance in fileControlAppearances) {
    for (final readonly in [false, true]) {
      testWidgets(
        '$appearance/readOnly=$readonly: normal archive icon is the guarded picker; no bottom duplicate',
        (tester) async {
          final editor = _editor(file.path, editable: !readonly);
          final node = editor.document.root.children.first;
          final originalBytes = await tester.runAsync(file.readAsBytes);
          final selection = Selection.collapsed(Position(path: [1], offset: 3));
          try {
            await mountFileControls(
              tester,
              _page(editor),
              mode: appearance,
              width: 900,
              height: 780,
              accessible: true,
              reduced: true,
            );
            await _wait(
              tester,
              () => find.byType(FileBrowserItems).evaluate().isNotEmpty,
            );
            editor.selection = selection;
            await tester.pump();
            final state = tester.state(find.byType(ArchiveExplorer));
            final materializer =
                tester.state(find.byType(MaterializedFileBuilder));
            final future = tester
                .widget<FutureBuilder<File>>(
                  find.descendant(
                    of: find.byType(MaterializedFileBuilder),
                    matching: find.byType(FutureBuilder<File>),
                  ),
                )
                .future;
            final browser =
                tester.widget<FileBrowserItems>(find.byType(FileBrowserItems));
            final selected = browser.entries.last.id;
            browser.selection.selectOnly(selected);
            await tester.pump();
            final before = Map<String, dynamic>.from(node.attributes);
            expect(find.byKey(_duplicate, skipOffstage: false), findsNothing);
            expect(find.byType(FileBlockIconButton), findsOneWidget);
            expect(
              find.descendant(
                of: find.byType(ArchiveGalleryHeader),
                matching: find.byKey(_picker),
              ),
              findsOneWidget,
            );
            final glyph = tester.widget<FileIdentityGlyph>(
              find.descendant(
                of: find.byKey(_picker),
                matching: find.byType(FileIdentityGlyph),
              ),
            );
            expect(glyph.icon.emoji, '📦');
            final button = tester.widget<IconButton>(find.byKey(_picker));
            expect(button.onPressed == null, readonly);
            await clickFileControl(tester, find.byKey(_picker));
            if (readonly) {
              expect(find.byType(FlowyIconEmojiPicker), findsNothing);
              final binding = tester
                  .widget<FileBlockIconButton>(find.byType(FileBlockIconButton))
                  .binding;
              expect(await binding.save(EmojiIconData.emoji('⭐')), isFalse);
              expect(node.attributes, before);
            } else {
              final picker = tester.widget<FlowyIconEmojiPicker>(
                find.byType(FlowyIconEmojiPicker),
              );
              expect(picker.effectiveTabs, [
                PickerTabType.emoji,
                PickerTabType.defaultIcons,
                PickerTabType.icon,
                PickerTabType.custom,
              ]);
              await clickFileControl(tester, find.text('Remove'));
              expect(node.attributes[FileBlockKeys.icon], isNull);
              expect(
                Map<String, dynamic>.from(node.attributes)
                  ..remove(FileBlockKeys.icon),
                Map<String, dynamic>.from(before)..remove(FileBlockKeys.icon),
              );
              expect(editor.selection, selection);
            }
            expect(tester.state(find.byType(ArchiveExplorer)), same(state));
            expect(
              tester.state(find.byType(MaterializedFileBuilder)),
              same(materializer),
            );
            expect(
              tester
                  .widget<FutureBuilder<File>>(
                    find.descendant(
                      of: find.byType(MaterializedFileBuilder),
                      matching: find.byType(FutureBuilder<File>),
                    ),
                  )
                  .future,
              same(future),
            );
            expect(
              tester
                  .widget<FileBrowserItems>(find.byType(FileBrowserItems))
                  .selection,
              same(browser.selection),
            );
            expect(browser.selection.ids, {selected});
            expect(await tester.runAsync(file.readAsBytes), originalBytes);
            expect(tester.takeException(), isNull);
          } finally {
            await unmountFileControls(tester);
            editor.dispose();
          }
        },
        variant: TargetPlatformVariant.only(TargetPlatform.windows),
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }

  testWidgets(
      'late archive icon selection cannot write after the editor becomes read-only',
      (tester) async {
    final editor = _editor(file.path);
    try {
      await mountFileControls(
        tester,
        _page(editor),
        accessible: true,
        reduced: true,
      );
      await _wait(
        tester,
        () => find.byType(FileBrowserItems).evaluate().isNotEmpty,
      );
      await clickFileControl(tester, find.byKey(_picker));
      final callback = tester
          .widget<FlowyIconEmojiPicker>(find.byType(FlowyIconEmojiPicker))
          .onSelectedEmoji!;
      editor.editable = false;
      final before = jsonEncode(editor.document.toJson());
      callback(EmojiIconData.emoji('⭐').toSelectedResult());
      await settleFileControls(tester);
      expect(jsonEncode(editor.document.toJson()), before);
      expect(find.byType(FlowyIconEmojiPicker), findsNothing);
      expect(tester.widget<IconButton>(find.byKey(_picker)).onPressed, isNull);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      editor.dispose();
    }
  });

  for (final readonly in [false, true]) {
    testWidgets(
      'archive modes/navigation retain file read future and never rewrite bytes; readOnly=$readonly',
      (tester) async {
        final tracked = _TrackedArchive(file);
        final saved = <Map<String, dynamic>>[];
        final metadata = <String, dynamic>{
          'unrelated': 'keep',
          FileBrowserViewSettings.key: 'list',
        };
        final before = await tester.runAsync(file.readAsBytes);
        try {
          Widget preview({
            required bool editable,
            Map<String, dynamic>? settings,
          }) =>
              FilePreview(
                file: tracked,
                name: 'fixture.zip',
                kind: FilePreviewKind.archive,
                metadata: settings ?? metadata,
                onMetadataChanged: saved.add,
                editable: editable,
                height: 560,
              );
          await mountFileControls(
            tester,
            preview(editable: !readonly),
            width: 320,
            mode: 'paper',
            textScale: 2,
            accessible: true,
            reduced: true,
          );
          await _wait(
            tester,
            () => find.byType(FileBrowserItems).evaluate().isNotEmpty,
          );
          final renderer = tester.state(find.byType(ArchiveExplorer));
          final future = tester
              .widget<FutureBuilder<Widget>>(find.byType(FutureBuilder<Widget>))
              .future;
          final reads = tracked.reads;
          for (final mode in FileBrowserViewMode.values) {
            await clickFileControl(
              tester,
              find.byKey(const ValueKey('file-browser-view-button')),
            );
            await clickFileControl(
              tester,
              find.widgetWithText(AppMenuRow, mode.label),
            );
            expect(tester.state(find.byType(ArchiveExplorer)), same(renderer));
            expect(tracked.reads, reads);
            expect(tester.takeException(), isNull);
          }
          expect(saved.isEmpty, readonly);
          expect(saved.every((value) => value['unrelated'] == 'keep'), isTrue);
          await clickFileControl(
            tester,
            find.byKey(const ValueKey('file-browser-view-button')),
          );
          await clickFileControl(
            tester,
            find.widgetWithText(AppMenuRow, FileBrowserViewMode.columns.label),
          );
          final rows =
              tester.widget<FileBrowserItems>(find.byType(FileBrowserItems));
          final folder =
              rows.entries.firstWhere((entry) => entry.item.isFolder);
          await tester.tap(
            find.byKey(ValueKey('file-browser-row-${folder.id}')),
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump(const Duration(milliseconds: 400));
          await _wait(
            tester,
            () => find.byType(FileBrowserItems).evaluate().length == 2,
          );
          expect(
            find.byKey(const ValueKey('file-browser-column-Folder')),
            findsOneWidget,
          );
          expect(tracked.reads, reads);
          await mountFileControls(
            tester,
            preview(
              editable: false,
              settings: FileBrowserViewSettings.withMode(
                metadata,
                FileBrowserViewMode.details,
              ),
            ),
            width: 320,
            mode: 'paper',
            textScale: 2,
            accessible: true,
            reduced: true,
          );
          expect(tester.state(find.byType(ArchiveExplorer)), same(renderer));
          expect(
            tester
                .widget<FutureBuilder<Widget>>(
                  find.byType(FutureBuilder<Widget>),
                )
                .future,
            same(future),
          );
          expect(tracked.reads, reads);
          expect(await tester.runAsync(file.readAsBytes), before);
          expect(tester.takeException(), isNull);
        } finally {
          await unmountFileControls(tester);
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets(
      'non-archive previews keep their existing bottom identity control',
      (tester) async {
    final text = await tester.runAsync(
      () => File('${directory.path}/notes.txt')
          .writeAsString('Unchanged text preview'),
    );
    final editor = _editor(text!.path, name: 'notes.txt');
    try {
      await mountFileControls(
        tester,
        _page(editor),
        accessible: true,
        reduced: true,
      );
      await _wait(
        tester,
        () => find.byType(SelectableText).evaluate().isNotEmpty,
      );
      expect(find.byKey(_duplicate), findsOneWidget);
      expect(find.byType(FileBlockIconButton), findsOneWidget);
      expect(find.byType(ArchiveExplorer), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      editor.dispose();
    }
  });
}

EditorState _editor(
  String source, {
  String name = 'fixture.zip',
  bool editable = true,
}) =>
    EditorState(
      document: Document(
        root: pageNode(
          children: [
            Node(
              type: FileBlockKeys.type,
              attributes: {
                FileBlockKeys.url: source,
                FileBlockKeys.urlType: FileUrlType.local.toIntValue(),
                FileBlockKeys.name: name,
                FileBlockKeys.displayMode: 'preview',
                FileBlockKeys.width: 620.0,
                FileBlockKeys.height: 420.0,
                FileBlockKeys.icon: '📦',
                FileBlockKeys.previewMetadata: {
                  FileBrowserViewSettings.key: 'list',
                  'unrelated': 7,
                },
              },
            ),
            paragraphNode(text: 'Unfinished neighboring draft'),
          ],
        ),
      ),
    )
      ..disableSealTimer = true
      ..editable = editable;

Widget _page(EditorState editor) => Provider<AppearanceSettingsCubit>.value(
      value: _Appearance(),
      child: AppFlowyEditor(
        editorState: editor,
        editable: editor.editable,
        disableAutoScroll: true,
        disableKeyboardService: true,
        editorStyle: const EditorStyle.desktop(padding: EdgeInsets.all(24)),
        blockComponentBuilders: {
          ...standardBlockComponentBuilderMap,
          FileBlockKeys.type: FileBlockComponentBuilder(),
        },
        contextMenuItems: const [],
      ),
    );

Future<void> _wait(WidgetTester tester, bool Function() ready) async {
  for (var i = 0; i < 120 && !ready(); i++) {
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
    await tester.pump(const Duration(milliseconds: 16));
  }
  expect(
    ready(),
    isTrue,
    reason: 'The isolated archive must finish its real IO',
  );
  await settleFileControls(tester);
}

class _TrackedArchive extends Fake implements File {
  _TrackedArchive(this.file);
  final File file;
  int reads = 0;
  @override
  String get path => file.path;
  @override
  Future<bool> exists() => file.exists();
  @override
  Future<int> length() => file.length();
  @override
  Future<Uint8List> readAsBytes() {
    reads++;
    return file.readAsBytes();
  }
}

class _Appearance extends Fake implements AppearanceSettingsCubit {
  @override
  AppearanceSettingsState get state => _AppearanceState();
}

class _AppearanceState extends Fake implements AppearanceSettingsState {
  @override
  UserDateFormatPB get dateFormat => UserDateFormatPB.values.first;
}
