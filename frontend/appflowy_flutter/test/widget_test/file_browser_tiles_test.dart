import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_browser.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_explorer.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_gallery.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_selection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:archive/archive.dart' as zip;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/intl.dart';

import 'file_controls_test_support.dart';

const _gridKey = ValueKey('file-browser-tiles');
const _archiveName = 'Tiles archive.zip';
final _modified = DateTime.utc(2026, 9, 25, 12);

void main() {
  fileControlTestSetup();

  for (final appearance in fileControlAppearances) {
    testWidgets(
        '$appearance: Tiles are lazy, adaptive left-icon layouts, including narrow 2x',
        (tester) async {
      final entries = _entries(60);
      final selection = WorkspaceExplorerSelection()..selectOnly(entries[0].id);
      try {
        for (final (width, textScale, columns) in [
          (240.0, 2.0, 1),
          (320.0, 2.0, 1),
          (780.0, 1.0, 2),
          (1000.0, 1.0, 3),
          (1000.0, 2.0, 2),
        ]) {
          await mountFileControls(
            tester,
            FileBrowserItems(
              entries: entries,
              selection: selection,
              tiles: true,
              onOpen: (_) {},
            ),
            mode: appearance,
            width: width,
            height: 400,
            textScale: textScale,
            reduced: textScale == 2,
          );
          final grid = tester.widget<GridView>(find.byKey(_gridKey));
          final delegate =
              grid.gridDelegate as SliverGridDelegateWithFixedCrossAxisCount;
          expect(delegate.crossAxisCount, columns);
          expect(grid.childrenDelegate, isA<SliverChildBuilderDelegate>());
          expect(
            find.byType(WorkspaceItemIcon).evaluate().length,
            lessThan(entries.length),
            reason: 'Offscreen tiles remain lazy',
          );
          expect(find.byType(FolderGalleryCard), findsNothing);
          expect(find.byType(FolderGalleryPreviewThumbnail), findsNothing);
          expect(
            find.byType(Image),
            findsNothing,
            reason: 'A stored image URL must not start a preview per tile',
          );
          expect(find.byType(AnimatedSwitcher), findsNothing);
          expect(
            find.byKey(const ValueKey('file-browser-details-heading')),
            findsNothing,
          );

          final first = tester.getRect(_tile(entries[0].id));
          final second = tester.getRect(_tile(entries[1].id));
          final nextRow = tester.getRect(_tile(entries[columns].id));
          if (columns > 1) {
            expect(second.top, closeTo(first.top, 0.01));
            expect(second.left, greaterThan(first.right));
          } else {
            expect(second.top, greaterThan(first.bottom));
            expect(second.left, closeTo(first.left, 0.01));
          }
          expect(nextRow.top, greaterThan(first.bottom));
          expect(nextRow.left, closeTo(first.left, 0.01));
          final tile = _tile(entries[0].id);
          final icon = find.descendant(
            of: tile,
            matching: find.byType(WorkspaceItemIcon),
          );
          expect(tester.widget<WorkspaceItemIcon>(icon).showThumbnail, isFalse);
          expect(tester.getSize(icon), const Size.square(36));
          final iconRect = tester.getRect(icon);
          final palette = FolderExplorerPalette.of(tester.element(tile));
          expect(
            PaperTheme.isEnabled(tester.element(tile)),
            appearance == 'paper',
          );
          for (final text in [
            entries[0].item.name,
            'PNG image · 2.0 KB',
            'Modified ${DateFormat.yMMMd().format(_modified.toLocal())}',
          ]) {
            final label = find.descendant(of: tile, matching: find.text(text));
            expect(label, findsOneWidget);
            final rect = tester.getRect(label);
            expect(rect.left, greaterThan(iconRect.right));
            expect(rect.right, lessThanOrEqualTo(first.right));
            expect(rect.top, greaterThanOrEqualTo(first.top));
            expect(rect.bottom, lessThanOrEqualTo(first.bottom + 0.01));
            final widget = tester.widget<Text>(label);
            expect(widget.maxLines, 1);
            expect(widget.overflow, TextOverflow.ellipsis);
            expect(
              widget.style!.color,
              text == entries[0].item.name
                  ? palette.textPrimary
                  : palette.textSecondary,
            );
          }
          final material = tester.widget<Material>(
            find.ancestor(of: tile, matching: find.byType(Material)).first,
          );
          final ink = tester.widget<InkWell>(
            find.ancestor(of: tile, matching: find.byType(InkWell)).first,
          );
          expect(material.color, palette.selected);
          expect(ink.hoverColor, palette.hover);
          expect(
            find.descendant(
              of: _tile(entries[1].id),
              matching: find.text('PNG image'),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: _tile(entries[1].id),
              matching: find.text('Modified —'),
            ),
            findsNothing,
          );
          expect(entries[1].byteSize, isNull);
          expect(entries[1].date, isNull);
          expect(entries[2].byteSize, 0, reason: 'Known empty is not unknown');
          expect(grid.controller!.position.maxScrollExtent, greaterThan(0));
          final horizontal = tester.widget<SingleChildScrollView>(
            find.descendant(
              of: find.byType(FileBrowserItems),
              matching: find.byType(SingleChildScrollView),
            ),
          );
          expect(
            horizontal.controller!.position.maxScrollExtent,
            0,
            reason: 'Tiles adapt instead of using the Details overflow table',
          );
          expect(
            tester.takeException(),
            isNull,
            reason: '$appearance/$width/$textScale',
          );
        }
      } finally {
        await unmountFileControls(tester);
        selection.dispose();
      }
    });
  }

  testWidgets(
      'Tiles, List and Details have distinct geometry with retained state',
      (tester) async {
    final entries = _entries(8);
    final selection = WorkspaceExplorerSelection()..selectOnly(entries[0].id);
    final mode = ValueNotifier(FileBrowserViewMode.tiles);
    try {
      await mountFileControls(
        tester,
        ValueListenableBuilder<FileBrowserViewMode>(
          valueListenable: mode,
          builder: (_, value, __) => FileBrowserItems(
            entries: entries,
            selection: selection,
            tiles: value == FileBrowserViewMode.tiles,
            details: value == FileBrowserViewMode.details,
            onOpen: (_) {},
          ),
        ),
        height: 420,
        reduced: true,
      );
      final state = tester.state(find.byType(FileBrowserItems));
      final scroll = tester.widget<GridView>(find.byKey(_gridKey)).controller;
      final tileRect = tester.getRect(_tile(entries[0].id));
      for (final next in [
        FileBrowserViewMode.list,
        FileBrowserViewMode.details,
      ]) {
        mode.value = next;
        await settleFileControls(tester);
        expect(tester.state(find.byType(FileBrowserItems)), same(state));
        expect(find.byKey(_gridKey), findsNothing);
        final row = tester.getRect(_row(entries[0].id));
        expect(row.width, greaterThan(tileRect.width));
        expect(row.height, lessThan(tileRect.height));
        expect(
          tester.widget<ListView>(find.byType(ListView)).controller,
          same(scroll),
        );
        expect(
          find.byKey(const ValueKey('file-browser-details-heading')),
          next == FileBrowserViewMode.details ? findsOneWidget : findsNothing,
        );
        expect(selection.ids, {entries[0].id});
      }
      mode.value = FileBrowserViewMode.tiles;
      await settleFileControls(tester);
      expect(tester.state(find.byType(FileBrowserItems)), same(state));
      expect(
        tester.widget<GridView>(find.byKey(_gridKey)).controller,
        same(scroll),
      );
      expect(tester.getRect(_tile(entries[0].id)), tileRect);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      mode.dispose();
      selection.dispose();
    }
  });

  for (final direction in [ui.TextDirection.ltr, ui.TextDirection.rtl]) {
    testWidgets('$direction: grid keys, ranges, resize and context anchors',
        (tester) async {
      final entries = _entries(24);
      final selection = WorkspaceExplorerSelection();
      final width = ValueNotifier(1000.0);
      final opened = <String>[];
      final menus = <(String, Offset)>[];
      final background = <Offset>[];
      var parents = 0;
      try {
        await mountFileControls(
          tester,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, value, __) => Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: value,
                height: 360,
                child: Directionality(
                  textDirection: direction,
                  child: FileBrowserItems(
                    entries: entries,
                    selection: selection,
                    tiles: true,
                    autofocus: true,
                    openOnTap: false,
                    onOpen: (entry) => opened.add(entry.id),
                    onContextMenu: (entry, point) =>
                        menus.add((entry.id, point)),
                    onBackgroundContextMenu: background.add,
                    onParent: () => parents++,
                  ),
                ),
              ),
            ),
          ),
          width: 1000,
          height: 400,
          reduced: true,
        );
        final next = direction == ui.TextDirection.ltr
            ? LogicalKeyboardKey.arrowRight
            : LogicalKeyboardKey.arrowLeft;
        await _key(tester, next);
        expect(selection.ids, {entries[0].id});
        await _key(tester, next);
        expect(selection.ids, {entries[1].id});
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          selection.ids,
          {entries[4].id},
          reason: 'Down moves one grid row',
        );
        await _key(tester, LogicalKeyboardKey.arrowUp);
        expect(selection.ids, {entries[1].id});
        await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(selection.ids, entries.sublist(1, 5).map((e) => e.id).toSet());
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(selection.ids, entries.sublist(1, 8).map((e) => e.id).toSet());
        await _key(tester, LogicalKeyboardKey.arrowUp);
        expect(selection.ids, entries.sublist(1, 5).map((e) => e.id).toSet());
        await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
        expect(opened, isEmpty);
        await _key(tester, LogicalKeyboardKey.contextMenu);
        expect(menus.last.$1, entries[4].id);
        expect(
          (menus.last.$2 - tester.getCenter(_tile(entries[4].id))).distance,
          lessThan(0.1),
        );
        await _key(tester, LogicalKeyboardKey.enter);
        await _key(tester, LogicalKeyboardKey.space);
        expect(opened, [entries[4].id, entries[4].id]);

        final scroll =
            tester.widget<GridView>(find.byKey(_gridKey)).controller!;
        final offset = scroll.offset;
        await _tapTile(tester, entries[0].id);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await _tapTile(tester, entries[1].id);
        await _tapTile(tester, entries[4].id);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(selection.ids, {entries[0].id, entries[1].id, entries[4].id});
        expect(
          scroll.offset,
          offset,
          reason: 'Clicking visible tiles must not scroll an earlier row away',
        );
        expect(_tile(entries[1].id).hitTestable(), findsOneWidget);
        await tester.tapAt(
          tester.getCenter(_tile(entries[1].id).hitTestable()),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await settleFileControls(tester);
        expect(menus.last.$1, entries[1].id);
        expect(selection.ids, {entries[0].id, entries[1].id, entries[4].id});
        expect(background, isEmpty);
        await tester.tapAt(
          tester.getTopLeft(find.byKey(_gridKey)) + const Offset(2, 2),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await settleFileControls(tester);
        expect(background, hasLength(1));

        final state = tester.state(find.byType(FileBrowserItems));
        width.value = 320;
        await settleFileControls(tester);
        expect(tester.state(find.byType(FileBrowserItems)), same(state));
        await _key(tester, LogicalKeyboardKey.arrowDown);
        expect(
          selection.ids,
          {entries[5].id},
          reason: 'Resize changes the stride',
        );
        await _key(tester, LogicalKeyboardKey.end);
        expect(selection.ids, {entries.last.id});
        expect(_tile(entries.last.id).hitTestable(), findsOneWidget);
        expect(
          tester.widget<GridView>(find.byKey(_gridKey)).controller!.offset,
          greaterThan(0),
        );
        await _key(tester, LogicalKeyboardKey.home);
        expect(selection.ids, {entries[0].id});
        expect(_tile(entries[0].id).hitTestable(), findsOneWidget);
        await tester.sendKeyDownEvent(LogicalKeyboardKey.altLeft);
        await _key(tester, LogicalKeyboardKey.arrowLeft);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.altLeft);
        expect(parents, 1, reason: 'Alt+Left still goes to the parent folder');
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await _key(tester, LogicalKeyboardKey.keyA);
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(selection.ids, entries.map((entry) => entry.id).toSet());
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        width.dispose();
        selection.dispose();
      }
    });
  }

  testWidgets('covered browser ignores deferred autofocus without remounting',
      (tester) async {
    final entries = _entries(6);
    final selection = WorkspaceExplorerSelection()..selectOnly(entries[0].id);
    final autofocus = ValueNotifier(false);
    final modalFocus = FocusNode(debugLabel: 'Browser regression dialog');
    const fieldKey = ValueKey('browser-regression-dialog-field');
    try {
      await mountFileControls(
        tester,
        Builder(
          builder: (context) => Column(
            children: [
              TextButton(
                onPressed: () => unawaited(
                  showDialog<void>(
                    context: context,
                    builder: (dialogContext) => AlertDialog(
                      content: TextField(
                        key: fieldKey,
                        focusNode: modalFocus,
                        autofocus: true,
                      ),
                      actions: [
                        TextButton(
                          onPressed: () => Navigator.of(dialogContext).pop(),
                          child: const Text('Close dialog'),
                        ),
                      ],
                    ),
                  ),
                ),
                child: const Text('Open dialog'),
              ),
              Expanded(
                child: ValueListenableBuilder<bool>(
                  valueListenable: autofocus,
                  builder: (_, value, __) => FileBrowserItems(
                    entries: entries,
                    selection: selection,
                    tiles: true,
                    autofocus: value,
                    onOpen: (_) {},
                  ),
                ),
              ),
            ],
          ),
        ),
        mode: 'paper',
        width: 320,
        textScale: 2,
        accessible: true,
        reduced: true,
      );
      final browser = tester.state(find.byType(FileBrowserItems));
      await clickFileControl(tester, find.text('Open dialog'));
      final route = ModalRoute.of(tester.element(find.byKey(fieldKey)))!;
      expect(modalFocus.hasPrimaryFocus, isTrue);
      autofocus.value = true;
      await settleFileControls(tester);
      expect(tester.state(find.byType(FileBrowserItems)), same(browser));
      expect(
        FocusManager.instance.primaryFocus,
        same(modalFocus),
        reason: 'A covered browser must not steal focus after the frame',
      );
      expect(route.isCurrent, isTrue);
      await tester.enterText(find.byKey(fieldKey), 'Draft stays in dialog');
      await settleFileControls(tester);
      expect(find.text('Draft stays in dialog'), findsOneWidget);
      expect(selection.ids, {entries[0].id});
      expect(tester.takeException(), isNull);
      await clickFileControl(tester, find.text('Close dialog'));
      expect(find.byKey(fieldKey), findsNothing);
      expect(tester.state(find.byType(FileBrowserItems)), same(browser));
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      modalFocus.dispose();
      autofocus.dispose();
      selection.dispose();
    }
  });

  testWidgets(
      'tile Tab focus, semantics and native rename keep editor shortcuts',
      (tester) async {
    final entries = _entries(3);
    final selection = WorkspaceExplorerSelection();
    final opened = <String>[];
    final renamed = <String>[];
    final menus = <String>[];
    final semantics = tester.ensureSemantics();
    String? editing;
    var writable = true;
    var deleted = 0;
    late StateSetter rebuild;
    try {
      await mountFileControls(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return FileBrowserItems(
              entries: entries,
              selection: selection,
              tiles: true,
              editingId: editing,
              onOpen: (entry) => opened.add(entry.id),
              onContextMenu: (entry, _) => menus.add(entry.id),
              onRename: writable
                  ? (entry) => setState(() => editing = entry.id)
                  : null,
              onRenameCancelled: () => setState(() => editing = null),
              onRenameSubmitted: (entry, name) async {
                renamed.add(name);
                setState(() {
                  entries[0] = FileBrowserEntry.fromView(
                    ViewPB.fromBuffer(entry.view.writeToBuffer())..name = name,
                  );
                  editing = null;
                });
                return true;
              },
              onDelete: writable ? () => deleted++ : null,
            );
          },
        ),
        mode: 'paper',
        width: 320,
        textScale: 2,
        reduced: true,
      );
      final focus = tester
          .widget<Focus>(
            find.descendant(
              of: _row(entries[0].id),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is Focus &&
                    widget.focusNode?.debugLabel == 'File browser row',
              ),
            ),
          )
          .focusNode!;
      for (var i = 0; i < 12 && !focus.hasPrimaryFocus; i++) {
        await _key(tester, LogicalKeyboardKey.tab);
      }
      expect(focus.hasPrimaryFocus, isTrue);
      final node =
          tester.getSemantics(find.bySemanticsLabel(entries[0].item.name));
      expect(
        node.getSemanticsData().hasFlag(ui.SemanticsFlag.isButton),
        isTrue,
      );
      expect(
        node.getSemanticsData().hasFlag(ui.SemanticsFlag.isSelected),
        isTrue,
      );
      expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
      expect(node.value, contains('2.0 KB'));
      await _key(tester, LogicalKeyboardKey.space);
      expect(opened, [entries[0].id]);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await _key(tester, LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      expect(menus, [entries[0].id]);
      await _key(tester, LogicalKeyboardKey.f2);
      final editor = find.byKey(const ValueKey('workspace-inline-name-editor'));
      expect(editor, findsOneWidget);
      expect(find.byType(WorkspaceInlineNameEditor), findsOneWidget);
      final text = tester.widget<EditableText>(editor).controller;
      expect(
        text.selection.textInside(text.text),
        entries[0].item.name.replaceFirst(RegExp(r'\.png$'), ''),
      );
      await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
      await _key(tester, LogicalKeyboardKey.keyA);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
      await _key(tester, LogicalKeyboardKey.delete);
      expect(selection.ids, {entries[0].id});
      expect(
        deleted,
        0,
        reason: 'Delete belongs to the active filename editor',
      );
      await tester.enterText(editor, 'Renamed.png');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await settleFileControls(tester);
      expect(renamed, ['Renamed.png']);
      expect(editor, findsNothing);
      expect(find.text('Renamed.png'), findsOneWidget);
      rebuild(() => writable = false);
      await settleFileControls(tester);
      focus.requestFocus();
      await settleFileControls(tester);
      await _key(tester, LogicalKeyboardKey.f2);
      await _key(tester, LogicalKeyboardKey.delete);
      expect(editor, findsNothing);
      expect(renamed, ['Renamed.png']);
      expect(deleted, 0);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await unmountFileControls(tester);
      selection.dispose();
    }
  });

  group('archive Tiles', () {
    late Directory directory;
    late File file;
    late Uint8List original;
    late FileStat originalStat;
    setUp(() async {
      directory = await Directory.systemTemp.createTemp('file-browser-tiles-');
      final archive = zip.Archive();
      for (final (name, size) in [('Top.bin', 3), ('sub/Nested.bin', 2048)]) {
        archive.addFile(
          zip.ArchiveFile(name, size, Uint8List(size))
            ..lastModTime = _modified.millisecondsSinceEpoch ~/ 1000,
        );
      }
      original = Uint8List.fromList(zip.ZipEncoder().encode(archive)!);
      file = await File('${directory.path}/tiles.zip').writeAsBytes(original);
      originalStat = await file.stat();
    });
    tearDown(() async => directory.delete(recursive: true));

    for (final appearance in fileControlAppearances) {
      for (final embedded in [false, true]) {
        for (final writable in [false, true]) {
          testWidgets(
            '$appearance/embedded=$embedded/writable=$writable: mode and metadata roundtrip without reloading the native archive',
            (tester) async {
              final metadata = <String, dynamic>{
                FileBrowserViewSettings.key: 'tiles',
                'future-setting': {'untouched': true},
              };
              final view =
                  fileControlView('tiles-archive', _archiveName, file.path);
              view.extra =
                  WorkspaceFilePreviewCodec.merge(view.extra, metadata);
              final backend = FileControlBackend(view, file);
              final saved = <Map<String, dynamic>>[];
              var byteWrites = 0;
              try {
                await mountFileControls(
                  tester,
                  embedded
                      ? ArchiveExplorer(
                          file: file,
                          name: _archiveName,
                          editable: writable,
                          metadata: metadata,
                          onMetadataChanged: (value) =>
                              saved.add(Map.of(value)),
                          onChanged: () => byteWrites++,
                        )
                      : backend.viewer(editable: writable),
                  mode: appearance,
                  width: 320,
                  height: 660,
                  textScale: 2,
                  reduced: true,
                  accessible: true,
                );
                await _waitForArchive(tester, 2);
                expect(_currentKey(_gridKey), findsOneWidget);
                final explorer = tester.state(_currentArchive());
                final browser =
                    tester.widget<ArchiveBrowser>(_currentBrowser());
                final selection = browser.selection;
                final fileEntry =
                    browser.entries.singleWhere((entry) => entry.entry.isFile);
                final folder = browser.entries
                    .singleWhere((entry) => entry.entry.isDirectory);
                final items = tester.widget<FileBrowserItems>(
                  find.descendant(
                    of: _currentBrowser(),
                    matching: find.byType(FileBrowserItems),
                  ),
                );
                final folderRow = items.entries
                    .singleWhere((entry) => entry.id == folder.view.id);
                expect(folderRow.byteSize, folder.entry.size);
                expect(folderRow.date, folder.entry.modified);
                expect(find.text('Folder · 2.0 KB'), findsOneWidget);
                expect(
                  find.byType(FolderGalleryPreviewThumbnail),
                  findsNothing,
                );
                await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
                await _tapTile(tester, fileEntry.view.id);
                await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
                await _key(tester, LogicalKeyboardKey.f2);
                final editor =
                    find.byKey(const ValueKey('workspace-inline-name-editor'));
                expect(editor, writable ? findsOneWidget : findsNothing);
                if (writable) await _key(tester, LogicalKeyboardKey.escape);
                await tester.tapAt(
                  tester.getCenter(_tile(fileEntry.view.id)),
                  kind: PointerDeviceKind.mouse,
                  buttons: kSecondaryMouseButton,
                );
                await settleFileControls(tester);
                expect(find.widgetWithText(AppMenuRow, 'Open'), findsOneWidget);
                expect(
                  find.widgetWithText(AppMenuRow, 'Extract to…'),
                  findsOneWidget,
                );
                expect(
                  find.widgetWithText(AppMenuRow, 'Rename'),
                  writable ? findsOneWidget : findsNothing,
                );
                await _key(tester, LogicalKeyboardKey.escape);
                final loads = backend.loads;
                final modes = [
                  ...FileBrowserViewMode.values
                      .where((mode) => mode != FileBrowserViewMode.tiles),
                  FileBrowserViewMode.tiles,
                ];
                for (final mode in modes) {
                  await _chooseArchiveMode(tester, mode);
                  expect(tester.state(_currentArchive()), same(explorer));
                  expect(
                    tester
                        .widget<FileBrowserViewButton>(
                          find.ancestor(
                            of: _currentKey(
                              const ValueKey('file-browser-view-button'),
                            ),
                            matching: find.byType(FileBrowserViewButton),
                          ),
                        )
                        .mode,
                    mode,
                  );
                  expect(
                    _currentKey(_gridKey),
                    mode == FileBrowserViewMode.tiles
                        ? findsOneWidget
                        : findsNothing,
                  );
                  expect(
                    backend.loads,
                    loads,
                    reason: 'The native file renderer must not be rebound',
                  );
                  expect(selection.ids, {fileEntry.view.id});
                  if (mode == FileBrowserViewMode.thumbnails) {
                    expect(find.byType(FolderThumbnailTile), findsWidgets);
                    expect(find.byType(GalleryCardFooter), findsNothing);
                    expect(
                      tester
                          .widgetList<FolderGalleryCard>(
                            find.byType(FolderGalleryCard),
                          )
                          .every((card) => card.thumbnail),
                      isTrue,
                    );
                    expect(
                      tester
                          .widgetList<FolderGalleryPreviewThumbnail>(
                            find.byType(FolderGalleryPreviewThumbnail),
                          )
                          .every((preview) => preview.lightweight),
                      isTrue,
                    );
                  }
                  expect(tester.takeException(), isNull, reason: mode.id);
                }
                final restored =
                    tester.widget<ArchiveBrowser>(_currentBrowser());
                expect(restored.selection, same(selection));
                expect(
                  restored.entries,
                  same(browser.entries),
                  reason: 'A mode switch reuses the cached directory listing',
                );
                expect(restored.path, browser.path);
                expect(metadata[FileBrowserViewSettings.key], 'tiles');
                if (embedded) {
                  expect(saved.length, writable ? modes.length : 0);
                  if (writable) {
                    expect(saved.map(FileBrowserViewSettings.read), modes);
                    expect(
                      saved.last['future-setting'],
                      metadata['future-setting'],
                    );
                  }
                } else {
                  expect(backend.loads, 1);
                  expect(
                    backend.extraWrites.length,
                    writable ? modes.length : 0,
                  );
                  final persisted =
                      WorkspaceFilePreviewCodec.decode(backend.stored.extra);
                  expect(
                    FileBrowserViewSettings.read(persisted),
                    FileBrowserViewMode.tiles,
                  );
                  expect(
                    persisted['future-setting'],
                    metadata['future-setting'],
                  );
                  expect(
                    jsonDecode(backend.stored.extra)['unrelated'],
                    'preserve me',
                  );
                }
                expect(byteWrites, 0);
                expect(file.readAsBytesSync(), original);
                expect(file.statSync().modified, originalStat.modified);
                expect(tester.takeException(), isNull);
              } finally {
                await unmountFileControls(tester);
              }
            },
            timeout: const Timeout(Duration(seconds: 60)),
          );
        }
      }
    }

    for (final writable in [false, true]) {
      testWidgets(
        'inline/fullscreen Tiles and nested path roundtrip; writable=$writable',
        (tester) async {
          final saved = <Map<String, dynamic>>[];
          var byteWrites = 0;
          try {
            await mountFileControls(
              tester,
              ArchiveExplorer(
                file: file,
                name: _archiveName,
                editable: writable,
                metadata: const {
                  FileBrowserViewSettings.key: 'tiles',
                  'retained': 9,
                },
                onMetadataChanged: (value) => saved.add(Map.of(value)),
                onChanged: () => byteWrites++,
              ),
              mode: 'paper',
              width: 320,
              height: 660,
              textScale: 2,
              reduced: true,
              accessible: true,
            );
            await tester.binding.setSurfaceSize(const Size(320, 720));
            await settleFileControls(tester);
            await _waitForArchive(tester, 2);
            final inline = tester.state(_currentArchive());
            await clickFileControl(tester, find.byTooltip('Open full window'));
            await _waitForArchive(tester, 2);
            expect(
              _currentKey(_gridKey),
              findsOneWidget,
              reason: 'Fullscreen must open directly in Tiles, not Gallery',
            );
            final expanded = tester.state(_currentArchive());
            final browser = tester.widget<ArchiveBrowser>(_currentBrowser());
            final folder =
                browser.entries.singleWhere((entry) => entry.entry.isDirectory);
            await _tapTile(tester, folder.view.id);
            await _waitForArchive(tester, 1);
            expect(
              tester.widget<ArchiveBrowser>(_currentBrowser()).path,
              'sub',
            );
            await _chooseArchiveMode(tester, FileBrowserViewMode.details);
            await _chooseArchiveMode(tester, FileBrowserViewMode.tiles);
            final nested = tester.widget<ArchiveBrowser>(_currentBrowser());
            expect(nested.path, 'sub');
            expect(nested.paths, ['', 'sub']);
            expect(tester.state(_currentArchive()), same(expanded));
            expect(
              _tile(nested.entries.single.view.id).hitTestable(),
              findsOneWidget,
            );
            await clickFileControl(
              tester,
              _currentKey(const ValueKey('archive-fullscreen-close')),
            );
            expect(tester.state(_currentArchive()), same(inline));
            expect(_currentKey(_gridKey), findsOneWidget);
            expect(saved.length, writable ? 2 : 0);
            if (writable) {
              expect(saved.last[FileBrowserViewSettings.key], 'tiles');
              expect(saved.last['retained'], 9);
            }
            expect(byteWrites, 0);
            expect(file.readAsBytesSync(), original);
            expect(file.statSync().modified, originalStat.modified);
            expect(tester.takeException(), isNull);
          } finally {
            await unmountFileControls(tester);
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  });
}

List<FileBrowserEntry> _entries(int count) => [
      for (var index = 0; index < count; index++)
        FileBrowserEntry.fromView(
          ViewPB(
            id: 'tile-$index',
            name: 'Image $index with a very long filename.png',
            layout: ViewLayoutPB.Document,
            extra: WorkspaceItemMetadata.file(
              contentKind: WorkspaceFileContentKind.binary,
              storageUrl: '/fixture/not-loaded-$index.png',
              mimeType: index == 0 ? 'image/png' : null,
              size: index == 0
                  ? 2048
                  : index == 2
                      ? 0
                      : null,
              modifiedAt: index == 0 ? _modified : null,
            ).mergeIntoExtra(''),
          ),
        ),
    ];

Finder _currentKey(Key key) => find.byElementPredicate(
      (element) =>
          element.widget.key == key &&
          ModalRoute.of(element)?.isCurrent != false,
    );

Finder _tile(String id) => _currentKey(ValueKey('file-browser-tile-$id'));
Finder _row(String id) => _currentKey(ValueKey('file-browser-row-$id'));
Finder _currentArchive() => find.byElementPredicate(
      (element) =>
          element.widget is ArchiveExplorer &&
          ModalRoute.of(element)?.isCurrent != false,
    );
Finder _currentBrowser() => find.descendant(
      of: _currentArchive(),
      matching: find.byType(ArchiveBrowser),
    );

Future<void> _key(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyEvent(key);
  await settleFileControls(tester);
}

Future<void> _tapTile(WidgetTester tester, String id) async {
  final tile = _tile(id);
  // ensureVisible aligns to the top even when the tile is already visible.
  // Do not manufacture a scroll between real modifier/context-menu clicks.
  if (tile.hitTestable().evaluate().isEmpty) {
    await tester.ensureVisible(tile);
    await settleFileControls(tester);
  }
  expect(tile.hitTestable(), findsOneWidget);
  await tester.tapAt(
    tester.getCenter(tile.hitTestable()),
    kind: PointerDeviceKind.mouse,
  );
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
  await settleFileControls(tester);
}

Future<void> _chooseArchiveMode(
  WidgetTester tester,
  FileBrowserViewMode mode,
) async {
  await clickFileControl(
    tester,
    _currentKey(const ValueKey('file-browser-view-button')),
  );
  for (final choice in FileBrowserViewMode.values) {
    expect(find.widgetWithText(AppMenuRow, choice.label), findsOneWidget);
  }
  final choice = find.widgetWithText(AppMenuRow, mode.label);
  await tester.ensureVisible(choice);
  await clickFileControl(tester, choice);
}

Future<void> _waitForArchive(WidgetTester tester, int count) async {
  for (var attempt = 0; attempt < 100; attempt++) {
    final browsers = _currentBrowser();
    if (browsers.evaluate().isNotEmpty) {
      final browser = tester.widget<ArchiveBrowser>(browsers);
      if (!browser.loading && browser.entries.length == count) return;
    }
    final galleries = find.descendant(
      of: _currentArchive(),
      matching: find.byType(ArchiveGallery),
    );
    if (galleries.evaluate().isNotEmpty &&
        tester.widget<ArchiveGallery>(galleries).entries.length == count) {
      return;
    }
    await tester
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await settleFileControls(tester);
  }
  fail('Archive listing did not finish loading $count entries');
}
