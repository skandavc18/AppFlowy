import 'dart:async';
import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_browser_presentations.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import '../util/workspace_explorer_permission_fakes.dart';
import 'file_controls_test_support.dart';

const _newModes = [
  FileBrowserViewMode.tiles,
  FileBrowserViewMode.list,
  FileBrowserViewMode.details,
  FileBrowserViewMode.columns,
];

void main() {
  fileControlTestSetup();
  setUp(() => WorkspaceItemClipboard.instance.clear());
  tearDown(() => WorkspaceItemClipboard.instance.clear());

  test('mode codecs roundtrip and preserve unrelated metadata', () {
    expect(FileBrowserViewMode.values.map((mode) => mode.id), [
      'gallery',
      'compact',
      'tiles',
      'list',
      'details',
      'columns',
      'tree',
    ]);
    expect(FolderEmbedStyles.tiles, 'tiles');
    expect(FileBrowserViewMode.tiles.labelKey, 'Tiles');
    for (final mode in FileBrowserViewMode.values) {
      final source = <String, dynamic>{
        'cover': {'url': 'untouched'},
        'future': 7,
      };
      final stored = FileBrowserViewSettings.withMode(source, mode);
      expect(
        FileBrowserViewSettings.read(jsonDecode(jsonEncode(stored))),
        mode,
      );
      final archiveExtra = WorkspaceFilePreviewCodec.merge(
        const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl: '/fixture/archive.zip',
        ).mergeIntoExtra('{"other":true}'),
        stored,
      );
      expect(
        FileBrowserViewSettings.read(
          WorkspaceFilePreviewCodec.decode(archiveExtra),
        ),
        mode,
      );
      expect(jsonDecode(archiveExtra)['other'], isTrue);
      expect(source.containsKey(FileBrowserViewSettings.key), isFalse);
      final extra =
          FileBrowserViewSettings.mergeExtra(jsonEncode(source), mode);
      expect(FileBrowserViewSettings.fromExtra(extra), mode);
      expect(jsonDecode(extra)['cover'], source['cover']);
      expect(jsonDecode(extra)['future'], 7);
      final embed = CollectionEmbedSettings.fromJson(
        {'style': mode.id, 'items': 6, 'sort': 'name'},
      );
      expect(CollectionEmbedSettings.fromJson(embed.toJson()), embed);
      expect(embed.folderViewMode, mode);
    }
    expect(
      FileBrowserViewSettings.fromExtra('{broken'),
      FileBrowserViewMode.gallery,
    );
    expect(
      () => FileBrowserViewSettings.mergeExtra(
        '{broken',
        FileBrowserViewMode.list,
      ),
      throwsFormatException,
    );
    expect(
      () => FileBrowserViewSettings.mergeExtra('[]', FileBrowserViewMode.list),
      throwsFormatException,
    );
    for (final (stored, mode) in [
      ('gallery', FileBrowserViewMode.gallery),
      ('compact', FileBrowserViewMode.thumbnails),
      ('thumbnails', FileBrowserViewMode.thumbnails),
      ('tiles', FileBrowserViewMode.tiles),
      ('list', FileBrowserViewMode.list),
      ('details', FileBrowserViewMode.details),
      ('columns', FileBrowserViewMode.columns),
      ('tree', FileBrowserViewMode.tree),
    ]) {
      expect(
        CollectionEmbedSettings.fromJson({'style': stored}).folderViewMode,
        mode,
      );
    }
    expect(
      FileBrowserViewMode.fromValue('future-mode'),
      FileBrowserViewMode.gallery,
    );
    expect(
      FolderExplorerPresentation.values,
      [FolderExplorerPresentation.gallery, FolderExplorerPresentation.tree],
    );
  });

  test('plain and collection folders expose the same real modes and labels',
      () {
    for (final kind in [null, CollectionKind.folder]) {
      final definition = buildFolderEmbedDefinition(kind: kind);
      expect(
        definition.styles.map((style) => style.id),
        FileBrowserViewMode.values.map((mode) => mode.id),
      );
      for (final mode in FileBrowserViewMode.values) {
        expect(definition.styleFor(mode.id).labelKey, mode.labelKey);
        expect(definition.styleFor(mode.id).icon, mode.icon);
      }
    }
  });

  for (final appearance in fileControlAppearances) {
    for (final width in [320.0, 780.0]) {
      for (final embedded in [false, true]) {
        for (final mode in _newModes) {
          testWidgets(
            '$appearance/$width/embed=$embedded/${mode.id}: 2x layout, modes and read-only selection',
            (tester) async {
              final repository = _Repository();
              final controller = WorkspaceExplorerController(
                root: repository.root,
                repository: repository,
                listenForUpdates: false,
                canWrite: () => false,
              );
              final storedModes = <FileBrowserViewMode>[];
              try {
                await controller.initialize();
                await mountFileControls(
                  tester,
                  FolderExplorer(
                    rootView: repository.root,
                    controller: controller,
                    initialViewMode: mode,
                    onViewModeChanged: storedModes.add,
                    embedded: embedded,
                    showHeader: false,
                    onOpen: (_) {},
                  ),
                  width: width,
                  height: 560,
                  textScale: 2,
                  mode: appearance,
                  accessible: true,
                  reduced: true,
                );
                final state = tester.state(find.byType(FolderExplorer));
                controller.selection.selectOnly('first');
                await settleFileControls(tester);
                expect(find.byType(FileBrowserItems), findsOneWidget);
                expect(
                  find.byKey(const ValueKey('file-browser-tiles')),
                  mode == FileBrowserViewMode.tiles
                      ? findsOneWidget
                      : findsNothing,
                );
                expect(
                  find.byType(FolderGalleryPreviewThumbnail),
                  findsNothing,
                );
                expect(
                  find.byKey(const ValueKey('file-browser-details-heading')),
                  mode == FileBrowserViewMode.details
                      ? findsOneWidget
                      : findsNothing,
                );
                expect(
                  find.byType(FileBrowserColumns),
                  mode == FileBrowserViewMode.columns
                      ? findsOneWidget
                      : findsNothing,
                );
                expect(
                  PaperTheme.isEnabled(
                    tester.element(find.byType(FolderExplorer)),
                  ),
                  appearance == 'paper',
                );
                expect(
                  find.byType(TextField),
                  findsOneWidget,
                  reason: 'Search remains available in every mode',
                );
                final reads = List<String>.of(repository.reads);
                await clickFileControl(
                  tester,
                  find.byKey(const ValueKey('file-browser-view-button')),
                );
                for (final choice in FileBrowserViewMode.values) {
                  expect(
                    find.widgetWithText(AppMenuRow, choice.label),
                    findsOneWidget,
                  );
                }
                final next = mode == FileBrowserViewMode.details
                    ? FileBrowserViewMode.list
                    : FileBrowserViewMode.details;
                await clickFileControl(
                  tester,
                  find.widgetWithText(AppMenuRow, next.label),
                );
                expect(tester.state(find.byType(FolderExplorer)), same(state));
                expect(
                  tester
                      .widget<FolderBrowserPresentation>(
                        find.byType(FolderBrowserPresentation),
                      )
                      .controller,
                  same(controller),
                );
                expect(controller.selection.ids, {'first'});
                expect(
                  repository.reads,
                  reads,
                  reason: 'A mode switch does not reload the graph',
                );
                expect(storedModes, isEmpty);
                expect(repository.writes, isEmpty);
                expect(tester.takeException(), isNull);
              } finally {
                await unmountFileControls(tester);
                controller.dispose();
              }
            },
            timeout: const Timeout(Duration(seconds: 30)),
          );
        }
      }
    }

    testWidgets(
        '$appearance: Columns navigates actual children; Enter opens the selected file',
        (tester) async {
      final repository = _Repository();
      final opened = <String>[];
      final controller = WorkspaceExplorerController(
        root: repository.root,
        repository: repository,
        listenForUpdates: false,
        canWrite: () => false,
      );
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          FolderExplorer(
            rootView: repository.root,
            controller: controller,
            initialViewMode: FileBrowserViewMode.columns,
            showHeader: false,
            onOpen: (view) => opened.add(view.id),
          ),
          mode: appearance,
          width: 320,
          reduced: true,
        );
        await _tapRow(tester, 'folder');
        expect(controller.currentFolder.id, 'folder');
        expect(
          controller.breadcrumbs.map((item) => item.id),
          ['root', 'folder'],
        );
        expect(repository.reads, ['root', 'folder']);
        expect(
          find.byKey(const ValueKey('file-browser-column-root')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('file-browser-column-folder')),
          findsOneWidget,
        );
        final columns = tester.widget<SingleChildScrollView>(
          find.byKey(const ValueKey('file-browser-columns-scroll')),
        );
        expect(columns.controller!.offset, greaterThan(0));
        await _tapRow(tester, 'nested');
        expect(
          opened,
          isEmpty,
          reason: 'A column file selects before activation',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await settleFileControls(tester);
        expect(opened, ['nested']);
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
        await settleFileControls(tester);
        expect(controller.currentFolder.id, 'root');
        expect(repository.reads, ['root', 'folder']);
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        controller.dispose();
      }
    });
  }

  testWidgets(
      'Details uses stored size/date, unknown values stay unknown and horizontal scrolling works',
      (tester) async {
    final repository = _Repository();
    final controller = WorkspaceExplorerController(
      root: repository.root,
      repository: repository,
      listenForUpdates: false,
      canWrite: () => false,
    );
    try {
      await controller.initialize();
      await mountFileControls(
        tester,
        FolderExplorer(
          rootView: repository.root,
          controller: controller,
          initialViewMode: FileBrowserViewMode.details,
          showHeader: false,
          onOpen: (_) {},
        ),
        width: 320,
        mode: 'paper',
        textScale: 2,
        reduced: true,
      );
      final table =
          tester.widget<FileBrowserItems>(find.byType(FileBrowserItems));
      final known = table.entries.singleWhere((entry) => entry.id == 'first');
      final unknown =
          table.entries.singleWhere((entry) => entry.id == 'second');
      expect(known.byteSize, 2048);
      final modified = DateTime.utc(2026, 9, 25);
      expect(known.date?.toUtc(), modified);
      expect(known.date!.isUtc, isFalse);
      expect(
        find.text(DateFormat.yMMMd().format(modified.toLocal())),
        findsOneWidget,
      );
      expect(known.type, 'application/octet-stream');
      expect(unknown.byteSize, isNull);
      expect(unknown.date, isNull);
      expect(find.text('2.0 KB'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      for (final name in ['Name', 'Type', 'Size', 'Date modified']) {
        expect(find.widgetWithText(TextButton, name), findsOneWidget);
      }
      final scroll = tester.widget<SingleChildScrollView>(
        find.descendant(
          of: find.byType(FileBrowserItems),
          matching: find.byType(SingleChildScrollView),
        ),
      );
      final origin = tester.getTopLeft(find.byType(FileBrowserItems));
      await tester.dragFrom(
        origin + const Offset(220, 24),
        const Offset(-180, 0),
      );
      await settleFileControls(tester);
      expect(scroll.controller!.offset, greaterThan(0));
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      controller.dispose();
    }
  });

  for (final mode in [FileBrowserViewMode.list, FileBrowserViewMode.tiles]) {
    testWidgets(
        '${mode.id} keeps modifier selection, clipboard and read-only keyboard guards',
        (tester) async {
      final repository = _Repository();
      var writable = false;
      final controller = WorkspaceExplorerController(
        root: repository.root,
        repository: repository,
        listenForUpdates: false,
        canWrite: () => writable,
      );
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          FolderExplorer(
            rootView: repository.root,
            controller: controller,
            initialViewMode: mode,
            showHeader: false,
            onOpen: (_) {},
          ),
        );
        await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
        await _tapRow(tester, 'first');
        await _tapRow(tester, 'second');
        await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
        expect(controller.selection.ids, {'first', 'second'});
        await _command(tester, LogicalKeyboardKey.keyC);
        expect(
          controller.clipboard.data!.views.map((view) => view.id),
          ['first', 'second'],
        );
        await _command(tester, LogicalKeyboardKey.keyX);
        await _command(tester, LogicalKeyboardKey.keyV);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await tester.sendKeyEvent(LogicalKeyboardKey.delete);
        await settleFileControls(tester);
        expect(repository.writes, isEmpty);
        expect(controller.editingId, isNull);
        expect(find.byType(AlertDialog), findsNothing);
        writable = true;
        controller.selection.selectOnly('first');
        await settleFileControls(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.f2);
        await settleFileControls(tester);
        final editor =
            find.byKey(const ValueKey('workspace-inline-name-editor'));
        expect(editor, findsOneWidget);
        await tester.enterText(editor, 'Renamed.bin');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await settleFileControls(tester);
        expect(repository.writes, ['rename:first']);
        expect(controller.viewForId('first')!.name, 'Renamed.bin');
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        controller.dispose();
      }
    });
  }

  for (final writable in [false, true]) {
    for (final initialMode in [
      FileBrowserViewMode.details,
      FileBrowserViewMode.tiles,
    ]) {
      testWidgets(
        'embed ${initialMode.id} menu keeps preview futures and fullscreen controller; writable=$writable',
        (tester) async {
          final repository = _Repository();
          final loader = _PreviewLoader();
          final controller = CollectionEmbedController(
            collection: repository.root,
            repository: repository,
            previewLoader: loader,
            listenForUpdates: false,
          );
          final stored = <CollectionEmbedSettings>[];
          try {
            await tester.pump();
            final cachedView =
                controller.children.singleWhere((view) => view.id == 'first');
            final future = controller.folderPreviewFor(cachedView);
            await tester.pump();
            await mountFileControls(
              tester,
              Provider<TabsBloc>.value(
                value: _Tabs(),
                child: CollectionEmbed(
                  collection: repository.root,
                  controller: controller,
                  settings: const CollectionEmbedSettings(
                    style: FolderEmbedStyles.gallery,
                  ),
                  onSettingsChanged: stored.add,
                  editable: writable,
                  height: 420,
                ),
              ),
              mode: 'paper',
              textScale: 2,
              accessible: true,
              reduced: true,
            );
            final state = tester.state(find.byType(CollectionEmbed));
            final inlineRoute =
                ModalRoute.of(tester.element(find.byType(CollectionEmbed)))!;
            await _chooseEmbedMode(tester, initialMode);
            expect(
              find.byKey(const ValueKey('file-browser-details-heading')),
              initialMode == FileBrowserViewMode.details
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(
              find.byKey(const ValueKey('file-browser-tiles')),
              initialMode == FileBrowserViewMode.tiles
                  ? findsOneWidget
                  : findsNothing,
            );
            expect(find.byType(FolderGalleryPreviewThumbnail), findsNothing);
            expect(tester.state(find.byType(CollectionEmbed)), same(state));
            expect(controller.folderPreviewFor(cachedView), same(future));
            expect(stored.length, writable ? 1 : 0);
            await clickFileControl(
              tester,
              find.byTooltip(LocaleKeys.collections_embed_fullscreen.tr()),
            );
            final fullscreen = find.byWidgetPredicate(
              (widget) => widget is CollectionEmbed && widget.fullscreen,
            );
            expect(fullscreen, findsOneWidget);
            final fullscreenRoute = ModalRoute.of(tester.element(fullscreen))!;
            expect(fullscreenRoute.isCurrent, isTrue);
            expect(inlineRoute.isCurrent, isFalse);
            expect(
              tester.widget<CollectionEmbed>(fullscreen).controller,
              same(controller),
            );
            expect(repository.reads, ['root']);
            if (initialMode == FileBrowserViewMode.tiles) {
              expect(
                find.byElementPredicate(
                  (element) =>
                      element.widget.key ==
                          const ValueKey('file-browser-tiles') &&
                      ModalRoute.of(element)?.isCurrent != false,
                ),
                findsOneWidget,
              );
            }
            await _chooseEmbedMode(tester, FileBrowserViewMode.columns);
            await _tapRow(tester, 'folder');
            expect(
              controller.folderPath.map((view) => view.id),
              ['root', 'folder'],
            );
            expect(controller.folderPreviewFor(cachedView), same(future));
            final focusedContext = FocusManager.instance.primaryFocus?.context;
            expect(focusedContext, isNotNull);
            expect(
              ModalRoute.of(focusedContext!),
              same(fullscreenRoute),
              reason: 'The covered inline column must not steal keyboard focus',
            );
            expect(
              tester.takeException(),
              isNull,
              reason: 'Column navigation at 2x text scale must not overflow',
            );
            if (initialMode == FileBrowserViewMode.tiles) {
              await _chooseEmbedMode(tester, FileBrowserViewMode.tiles);
            }
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await settleFileControls(tester);
            expect(
              fullscreen,
              findsNothing,
              reason: 'Escape must close the actual fullscreen route',
            );
            expect(fullscreenRoute.isActive, isFalse);
            expect(inlineRoute.isCurrent, isTrue);
            expect(find.byType(CollectionEmbed), findsOneWidget);
            expect(tester.state(find.byType(CollectionEmbed)), same(state));
            expect(
              find.byType(FileBrowserColumns),
              initialMode == FileBrowserViewMode.tiles
                  ? findsNothing
                  : findsOneWidget,
            );
            if (initialMode == FileBrowserViewMode.tiles) {
              expect(
                find.byKey(const ValueKey('file-browser-tile-nested')),
                findsOneWidget,
              );
            }
            expect(controller.folderPath.last.id, 'folder');
            expect(repository.reads, ['root', 'folder']);
            expect(
              stored.length,
              writable ? (initialMode == FileBrowserViewMode.tiles ? 3 : 2) : 0,
            );
            if (writable) {
              expect(stored.first.toJson()['style'], initialMode.id);
              expect(
                CollectionEmbedSettings.fromJson(stored.last.toJson()),
                stored.last,
              );
            }
            expect(repository.writes, isEmpty);
            expect(tester.takeException(), isNull);
          } finally {
            await unmountFileControls(tester);
            controller.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }
  }

  for (final appearance in fileControlAppearances) {
    testWidgets(
      '$appearance: actual inline/fullscreen embed frames support every mode at 2x',
      (tester) async {
        final repository = _Repository();
        final loader = _PreviewLoader();
        final controller = CollectionEmbedController(
          collection: repository.root,
          repository: repository,
          previewLoader: loader,
          listenForUpdates: false,
        );
        try {
          await tester.pump();
          for (final width in [320.0, 720.0]) {
            for (final fullscreen in [false, true]) {
              for (final mode in FileBrowserViewMode.values) {
                await mountFileControls(
                  tester,
                  CollectionEmbed(
                    collection: repository.root,
                    controller: controller,
                    settings:
                        CollectionEmbedSettings(style: mode.id, itemLimit: 3),
                    onSettingsChanged: (_) =>
                        fail('Read-only embed must not persist'),
                    editable: false,
                    fullscreen: fullscreen,
                    height: 400,
                  ),
                  mode: appearance,
                  width: width,
                  height: 500,
                  textScale: 2,
                  reduced: true,
                  accessible: true,
                );
                expect(find.byType(FolderEmbedPreview), findsOneWidget);
                expect(
                  PaperTheme.isEnabled(
                    tester.element(find.byType(FolderEmbedPreview)),
                  ),
                  appearance == 'paper',
                );
                final box = tester
                    .renderObject<RenderBox>(find.byType(FolderEmbedPreview));
                expect(box.hasSize, isTrue);
                expect(box.size.isFinite, isTrue);
                expect(
                  find.byKey(const ValueKey('file-browser-tiles')),
                  mode == FileBrowserViewMode.tiles
                      ? findsOneWidget
                      : findsNothing,
                );
                expect(
                  find.byKey(const ValueKey('file-browser-details-heading')),
                  mode == FileBrowserViewMode.details
                      ? findsOneWidget
                      : findsNothing,
                );
                expect(
                  find.byType(FileBrowserColumns),
                  mode == FileBrowserViewMode.columns
                      ? findsOneWidget
                      : findsNothing,
                );
                expect(
                  tester.takeException(),
                  isNull,
                  reason: '$mode/$width/fullscreen=$fullscreen',
                );
              }
            }
          }
          expect(repository.reads, ['root']);
          expect(repository.writes, isEmpty);
          expect(loader.reads, lessThanOrEqualTo(3));
        } finally {
          await unmountFileControls(tester);
          controller.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 60)),
    );
  }

  testWidgets('Tiles embed honors optional metadata without preview reads',
      (tester) async {
    final repository = _Repository();
    final loader = _PreviewLoader();
    final controller = CollectionEmbedController(
      collection: repository.root,
      repository: repository,
      previewLoader: loader,
      listenForUpdates: false,
    );
    try {
      await tester.pump();
      for (final showMetadata in [true, false]) {
        await mountFileControls(
          tester,
          CollectionEmbed(
            collection: repository.root,
            controller: controller,
            settings: CollectionEmbedSettings(
              style: FolderEmbedStyles.tiles,
              showMetadata: showMetadata,
            ),
            onSettingsChanged: (_) => fail('Read-only persistence'),
            editable: false,
            height: 400,
          ),
          mode: 'paper',
          width: 320,
          textScale: 2,
          reduced: true,
        );
        expect(
          find.byKey(const ValueKey('file-browser-tiles')),
          findsOneWidget,
        );
        final items =
            tester.widget<FileBrowserItems>(find.byType(FileBrowserItems));
        expect(items.showTileMetadata, showMetadata);
        expect(
          find.text('BIN file · 2.0 KB'),
          showMetadata ? findsOneWidget : findsNothing,
        );
        expect(find.byType(FolderGalleryPreviewThumbnail), findsNothing);
        expect(loader.reads, 0);
        expect(tester.takeException(), isNull);
      }
      expect(repository.reads, ['root']);
      expect(repository.writes, isEmpty);
    } finally {
      await unmountFileControls(tester);
      controller.dispose();
    }
  });

  testWidgets('filter and nested path survive returning to legacy embed modes',
      (tester) async {
    final repository = _Repository();
    final controller = CollectionEmbedController(
      collection: repository.root,
      repository: repository,
      previewLoader: _PreviewLoader(),
      listenForUpdates: false,
    );
    try {
      await tester.pump();
      await mountFileControls(
        tester,
        CollectionEmbed(
          collection: repository.root,
          controller: controller,
          settings:
              const CollectionEmbedSettings(style: FolderEmbedStyles.columns),
          onSettingsChanged: (_) => fail('Read-only persistence'),
          editable: false,
          fullscreen: true,
        ),
        mode: 'paper',
        accessible: true,
        reduced: true,
      );
      final filter = find.byKey(const ValueKey('folder-browser-filter'));
      final field = tester.widget<TextField>(filter).controller;
      await tester.enterText(filter, 'First');
      await settleFileControls(tester);
      await _chooseEmbedMode(tester, FileBrowserViewMode.list);
      expect(tester.widget<TextField>(filter).controller, same(field));
      expect(field!.text, 'First');
      expect(
        find.byKey(const ValueKey('folder-embed-item-first')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('folder-embed-item-second')),
        findsNothing,
      );
      await tester.enterText(filter, '');
      await settleFileControls(tester);
      await _chooseEmbedMode(tester, FileBrowserViewMode.columns);
      await _tapRow(tester, 'folder');
      expect(controller.folderPath.last.id, 'folder');
      await _chooseEmbedMode(tester, FileBrowserViewMode.list);
      expect(
        find.byKey(const ValueKey('folder-embed-item-nested')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('folder-embed-item-first')),
        findsNothing,
      );
      await clickFileControl(
        tester,
        find.widgetWithText(TextButton, repository.root.name),
      );
      expect(controller.folderPath.last.id, 'root');
      expect(repository.reads, ['root', 'folder']);
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      controller.dispose();
    }
  });

  testWidgets('ancestor columns stay mounted while a child listing is pending',
      (tester) async {
    final repository = _Repository();
    final pending = Completer<FlowyResult<List<ViewPB>, FlowyError>>();
    repository.folderRead = pending.future;
    final controller = WorkspaceExplorerController(
      root: repository.root,
      repository: repository,
      listenForUpdates: false,
      canWrite: () => false,
    );
    try {
      await controller.initialize();
      await mountFileControls(
        tester,
        FolderExplorer(
          rootView: repository.root,
          controller: controller,
          initialViewMode: FileBrowserViewMode.columns,
          showHeader: false,
          onOpen: (_) {},
        ),
        width: 320,
        reduced: true,
      );
      final ancestor = tester
          .element(find.byKey(const ValueKey('file-browser-column-root')));
      final state = tester.state(find.byType(FileBrowserColumns));
      await _tapRow(tester, 'folder');
      expect(controller.isLoading, isTrue);
      expect(
        tester.element(find.byKey(const ValueKey('file-browser-column-root'))),
        same(ancestor),
      );
      expect(tester.state(find.byType(FileBrowserColumns)), same(state));
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      pending.complete(FlowyResult.success([repository.nested]));
      await settleFileControls(tester);
      expect(
        find.byKey(const ValueKey('file-browser-row-nested')),
        findsOneWidget,
      );
      expect(repository.reads, ['root', 'folder']);
      expect(tester.takeException(), isNull);
    } finally {
      if (!pending.isCompleted) pending.complete(FlowyResult.success([]));
      await unmountFileControls(tester);
      controller.dispose();
    }
  });

  for (final mode in [FileBrowserViewMode.details, FileBrowserViewMode.tiles]) {
    testWidgets('saved ${mode.id} reopens from native folder view metadata',
        (tester) async {
      final repository = _Repository();
      final root = ViewPB.fromBuffer(repository.root.writeToBuffer())
        ..extra =
            FileBrowserViewSettings.mergeExtra(repository.root.extra, mode);
      final controller = WorkspaceExplorerController(
        root: root,
        repository: repository,
        listenForUpdates: false,
        canWrite: () => false,
      );
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          FolderExplorer(
            rootView: root,
            controller: controller,
            showHeader: false,
            onOpen: (_) {},
          ),
        );
        expect(
          find.byKey(const ValueKey('file-browser-details-heading')),
          mode == FileBrowserViewMode.details ? findsOneWidget : findsNothing,
        );
        expect(
          find.byKey(const ValueKey('file-browser-tiles')),
          mode == FileBrowserViewMode.tiles ? findsOneWidget : findsNothing,
        );
        expect(
          tester
              .widget<FileBrowserViewButton>(
                find.byType(FileBrowserViewButton),
              )
              .mode,
          mode,
        );
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        controller.dispose();
      }
    });
  }

  testWidgets(
      'nested embed read errors stay distinct from empty and retry without preview reads',
      (tester) async {
    final repository = _Repository()..failFolder = true;
    final loader = _PreviewLoader();
    final controller = CollectionEmbedController(
      collection: repository.root,
      repository: repository,
      previewLoader: loader,
      listenForUpdates: false,
    );
    try {
      await tester.pump();
      await mountFileControls(
        tester,
        CollectionEmbed(
          collection: repository.root,
          controller: controller,
          settings: const CollectionEmbedSettings(
            style: FolderEmbedStyles.columns,
          ),
          onSettingsChanged: (_) => fail('Read-only persistence'),
          editable: false,
          fullscreen: true,
        ),
        accessible: true,
      );
      await _tapRow(tester, 'folder');
      expect(
        find.byKey(const ValueKey('folder-browser-retry-folder')),
        findsOneWidget,
      );
      expect(controller.hasLoaded('folder'), isFalse);
      expect(loader.reads, 0);
      repository.failFolder = false;
      await clickFileControl(
        tester,
        find.byKey(const ValueKey('folder-browser-retry-folder')),
      );
      expect(
        find.byKey(const ValueKey('file-browser-row-nested')),
        findsOneWidget,
      );
      expect(controller.hasLoaded('folder'), isTrue);
      expect(repository.reads, ['root', 'folder', 'folder']);
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await unmountFileControls(tester);
      controller.dispose();
    }
  });
}

Future<void> _tapRow(WidgetTester tester, String id) async {
  final row = find.byElementPredicate(
    (element) =>
        element.widget.key == ValueKey('file-browser-row-$id') &&
        ModalRoute.of(element)?.isCurrent != false,
  );
  await tester.ensureVisible(row);
  await tester.tap(row, kind: PointerDeviceKind.mouse);
  await tester.pump(const Duration(milliseconds: 400));
  await settleFileControls(tester);
}

Future<void> _command(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(key);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  await settleFileControls(tester);
}

Future<void> _chooseEmbedMode(
  WidgetTester tester,
  FileBrowserViewMode mode,
) async {
  await clickFileControl(
    tester,
    find.byTooltip(LocaleKeys.collections_embed_blockOptions.tr()),
  );
  await clickFileControl(
    tester,
    find.widgetWithText(
      AppMenuRow,
      LocaleKeys.collections_embed_preview.tr(),
    ),
  );
  await clickFileControl(tester, find.widgetWithText(AppMenuRow, mode.label));
}

class _Repository extends ExplorerPermissionRepository {
  _Repository() {
    views['first'] = ViewPB.fromBuffer(first.writeToBuffer())
      ..extra = WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        size: 2048,
        mimeType: 'application/octet-stream',
        modifiedAt: DateTime.utc(2026, 9, 25),
      ).mergeIntoExtra('');
  }
  final reads = <String>[];
  bool failFolder = false;
  Future<FlowyResult<List<ViewPB>, FlowyError>>? folderRead;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) {
    reads.add(id);
    if (id == 'folder' && folderRead != null) return folderRead!;
    if (id == 'folder' && failFolder) {
      return Future.value(
        FlowyResult.failure(FlowyError(msg: 'Fixture read failure')),
      );
    }
    return super.getChildren(id);
  }
}

class _PreviewLoader extends FolderGalleryPreviewLoader {
  int reads = 0;
  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    reads++;
    return FolderGalleryPreviewParser.withoutDocument(view: view, item: item)!;
  }
}

class _Tabs extends Fake implements TabsBloc {}
