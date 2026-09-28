import 'dart:io';
import 'dart:ui' show ImageByteFormat, SemanticsAction, SemanticsFlag;

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/file_browser/file_browser_items.dart';
import 'package:appflowy/shared/file_browser/file_browser_view.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/explorer_toolbar.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_size.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_surface.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import '../util/home_profile_test_support.dart';
import '../util/workspace_explorer_permission_fakes.dart';
import 'file_controls_test_support.dart';

const _searchKey = ValueKey('folder-explorer-search-field');
const _titleKey = ValueKey('folder-gallery-title');
const _contentKey = ValueKey('folder-explorer-content');
const _actionsKey = ValueKey('folder-explorer-actions');
const _renameKey = ValueKey('workspace-inline-name-editor');
const _captureFolderShell = bool.fromEnvironment('FOLDER_SHELL_CAPTURE');
const _captureKey = ValueKey('folder-shell-capture');
const _captureSize = Size(1200, 800);
const _solidCover = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#C8B99A',
);
const _imageCover = PageStyleCover(
  type: PageStyleCoverImageType.builtInImage,
  value: '1',
);

void main() {
  fileControlTestSetup();
  setUp(() {
    GalleryCardSizeStore.reset();
    WorkspaceItemClipboard.instance.clear();
  });
  tearDown(() {
    GalleryCardSizeStore.reset();
    WorkspaceItemClipboard.instance.clear();
  });

  for (final appearance in fileControlAppearances) {
    for (final (width, scale) in [(1600.0, 1.0), (320.0, 2.0)]) {
      testWidgets(
        '$appearance/$width: seven modes retain one header, search and reading bounds',
        (tester) async {
          final repository = _Repository();
          final controller = _controller(repository, writable: false);
          try {
            await controller.initialize();
            await mountFileControls(
              tester,
              FolderExplorer(
                rootView: repository.root,
                controller: controller,
                onOpen: (_) {},
              ),
              mode: appearance,
              width: width,
              height: 900,
              textScale: scale,
              reduced: true,
              accessible: true,
            );
            await tester.binding.setSurfaceSize(Size(width, 1000));
            await settleFileControls(tester);
            final header =
                find.byType(FolderGalleryHeader, skipOffstage: false);
            final initial = tester.widget<FolderGalleryHeader>(header);
            initial.searchFocusNode!.requestFocus();
            await settleFileControls(tester);
            final search = find.byKey(_searchKey);
            await tester.enterText(search, '.bin');
            await settleFileControls(tester);
            controller.selection.selectOnly('first');
            initial.searchController.selection =
                const TextSelection(baseOffset: 1, extentOffset: 3);
            await settleFileControls(tester);

            final headerElement = tester.element(header);
            final titleElement =
                tester.element(find.byKey(_titleKey, skipOffstage: false));
            final searchElement = tester.element(search);
            final editable = find.descendant(
              of: search,
              matching: find.byType(EditableText),
            );
            final editorState = tester.state(editable);
            final actionsElement = tester.element(find.byKey(_actionsKey));
            final value = initial.searchController.value;
            final viewportBounds = tester.getRect(find.byKey(_contentKey));
            final inset =
                FolderExplorerLayout.horizontalPadding(viewportBounds.width);
            final contentBounds = Rect.fromLTRB(
                viewportBounds.left + inset,
                viewportBounds.top,
                viewportBounds.right - inset,
                viewportBounds.bottom);
            final titleBounds = _documentRect(
                tester, find.byKey(_titleKey, skipOffstage: false));
            final searchBounds = _documentRect(tester, search);
            final cache = tester
                .widget<FolderGallery>(
                  find.byType(FolderGallery),
                )
                .previewCache;
            final first = controller.viewForId('first')!;
            final preview = cache.previewFor(
              view: first,
              item: controller.itemForId(first.id)!,
            );
            final reads = List<String>.of(repository.reads);

            for (final mode in [
              ...FileBrowserViewMode.values,
              FileBrowserViewMode.gallery,
            ]) {
              // Exercise the real shell handler without a menu blur changing
              // the native text selection being tested here.
              tester
                  .widget<FolderGalleryHeader>(header)
                  .onViewModeChanged!(mode);
              await settleFileControls(tester);
              expect(tester.element(header), same(headerElement));
              expect(tester.element(find.byKey(_titleKey, skipOffstage: false)),
                  same(titleElement));
              expect(tester.element(search), same(searchElement));
              expect(tester.state(editable), same(editorState));
              expect(
                tester.element(find.byKey(_actionsKey)),
                same(actionsElement),
              );
              final current = tester.widget<FolderGalleryHeader>(header);
              expect(current.viewMode, mode);
              expect(current.controller, same(controller));
              expect(current.searchController, same(initial.searchController));
              expect(current.searchFocusNode, same(initial.searchFocusNode));
              expect(current.searchController.value, value);
              expect(controller.query, '.bin');
              expect(controller.selection.ids, {'first'});
              expect(controller.currentFolder.id, 'root');
              expect(controller.breadcrumbs.map((item) => item.id), ['root']);
              expect(tester.getRect(find.byKey(_contentKey)), viewportBounds);
              expect(
                  _documentRect(
                      tester, find.byKey(_titleKey, skipOffstage: false)),
                  titleBounds);
              expect(_documentRect(tester, search), searchBounds);
              expect(
                contentBounds.width,
                lessThanOrEqualTo(
                  FolderExplorerLayout.maxContentWidth,
                ),
              );
              expect(titleBounds.left, contentBounds.left);
              expect(titleBounds.right, lessThanOrEqualTo(contentBounds.right));
              expect(
                searchBounds.left,
                greaterThanOrEqualTo(contentBounds.left),
              );
              expect(
                searchBounds.right,
                lessThanOrEqualTo(contentBounds.right),
              );
              if (mode == FileBrowserViewMode.tiles) {
                expect(find.byType(FileBrowserItems), findsOneWidget);
                final tileBounds = tester.getRect(
                  find.byKey(const ValueKey('file-browser-tile-first')),
                );
                expect(
                  tileBounds.left,
                  greaterThanOrEqualTo(contentBounds.left),
                );
                expect(
                  tileBounds.right,
                  lessThanOrEqualTo(contentBounds.right),
                );
                expect(
                  tileBounds.width,
                  lessThanOrEqualTo((72 + 200 * scale) * 1.2),
                );
              }
              expect(find.text('Master', skipOffstage: false), findsOneWidget);
              expect(find.byType(ExplorerToolbar), findsNothing);
              expect(
                PaperTheme.isEnabled(tester.element(header)),
                appearance == 'paper',
              );
              expect(
                cache.previewFor(
                  view: first,
                  item: controller.itemForId(first.id)!,
                ),
                same(preview),
              );
              if (mode == FileBrowserViewMode.gallery ||
                  mode == FileBrowserViewMode.thumbnails) {
                expect(
                  tester
                      .widget<FolderGallery>(
                        find.byType(FolderGallery),
                      )
                      .previewCache,
                  same(cache),
                );
              }
              expect(repository.reads, reads);
              expect(repository.writes, isEmpty);
              expect(tester.takeException(), isNull, reason: mode.name);
            }
          } finally {
            await unmountFileControls(tester);
            controller.dispose();
          }
        },
        timeout: const Timeout(Duration(seconds: 30)),
      );
    }

    for (final workspaceRoot in [false, true]) {
      for (final cover in [null, _imageCover]) {
        testWidgets(
          '$appearance/workspace=$workspaceRoot/cover=${cover != null}: native identity actions survive seven modes and hidden controls',
          (tester) async {
            final repository = _Repository(cover: cover);
            final icon = cover == null ? null : EmojiIconData.emoji('🌿');
            if (icon != null) {
              repository.root.icon = icon.toViewIcon();
              repository.views[repository.root.id] =
                  ViewPB.fromBuffer(repository.root.writeToBuffer());
            }
            final controller = _controller(repository, writable: true);
            final workspace = workspaceRoot
                ? _WorkspaceBloc(
                    UserWorkspacePB(
                      workspaceId: repository.root.id,
                      name: repository.root.name,
                      workspaceType: WorkspaceTypePB.LocalW,
                      icon: icon?.toStorageString() ?? '',
                      cover: cover == null
                          ? ''
                          : WorkspaceCoverCodec.encode(cover),
                    ),
                  )
                : null;
            final controls = ValueNotifier(true);
            final semantics = tester.ensureSemantics();
            final mouse =
                await tester.createGesture(kind: PointerDeviceKind.mouse);
            await mouse.addPointer(location: const Offset(-20, -20));
            try {
              await controller.initialize();
              Widget shell = ValueListenableBuilder<bool>(
                valueListenable: controls,
                builder: (_, showControls, __) => FolderExplorer(
                  rootView: repository.root,
                  controller: controller,
                  showControls: showControls,
                  onOpen: (_) {},
                ),
              );
              if (workspace != null) {
                shell = BlocProvider<UserWorkspaceBloc>.value(
                  value: workspace,
                  child: shell,
                );
              }
              await mountFileControls(
                tester,
                shell,
                mode: appearance,
                width: 320,
                height: 900,
                textScale: 2,
                reduced: true,
              );
              final header = find.byType(FolderGalleryHeader);
              final owner = find.byType(
                workspaceRoot ? WorkspaceCoverActions : ViewDecorationActions,
              );
              final prefix = workspaceRoot ? 'workspace' : 'view';
              final coverKey = ValueKey('$prefix-decoration-cover');
              final coverButton = _decorationButton(coverKey);
              final iconButton = _decorationButton(
                ValueKey('$prefix-decoration-icon'),
              );
              final coverLabel = cover == null
                  ? LocaleKeys.document_plugins_cover_addCover.tr()
                  : LocaleKeys.document_plugins_cover_changeCover.tr();
              final iconLabel = icon == null
                  ? LocaleKeys.document_plugins_cover_addIcon.tr()
                  : LocaleKeys.document_plugins_cover_changeIcon.tr();
              final rootBytes = repository.root.writeToBuffer();

              for (final showControls in [true, false]) {
                controls.value = showControls;
                await settleFileControls(tester);
                // Hiding controls removes the shell's Find wrapper. Retention
                // is required across modes within each host chrome setting.
                final headerState = tester.state(header);
                final ownerState = tester.state(owner);
                final title = tester.element(find.byKey(_titleKey));
                final strip = showControls
                    ? tester.element(find.byKey(_actionsKey))
                    : null;
                for (final mode in FileBrowserViewMode.values) {
                  _header(tester).onViewModeChanged!(mode);
                  await settleFileControls(tester);
                  expect(_header(tester).viewMode, mode);
                  expect(tester.state(header), same(headerState));
                  expect(tester.state(owner), same(ownerState));
                  expect(tester.element(find.byKey(_titleKey)), same(title));
                  expect(
                    find.descendant(
                      of: header,
                      matching: find.byType(WorkspaceActionRow),
                    ),
                    showControls ? findsOneWidget : findsNothing,
                  );
                  if (showControls) {
                    expect(
                      tester.element(find.byKey(_actionsKey)),
                      same(strip),
                    );
                  } else {
                    expect(find.byKey(_actionsKey), findsNothing);
                    expect(find.byType(FileBrowserViewButton), findsNothing);
                    expect(
                      find.byKey(_searchKey, skipOffstage: false),
                      findsNothing,
                    );
                    expect(find.byType(ContextualFindRegion), findsNothing);
                    expect(
                      find.semantics.byLabel('View: ${mode.label}'),
                      findsNothing,
                    );
                  }
                  expect(
                    find.byType(ViewCoverImage),
                    cover == null ? findsNothing : findsOneWidget,
                  );
                  await _revealNativeDecoration(tester, mouse, iconButton);
                  _expectNativeDecoration(tester, iconButton, iconLabel);
                  for (final (suffix, label) in [
                    (
                      'remove',
                      LocaleKeys.document_plugins_cover_removeCover.tr(),
                    ),
                    (
                      'download',
                      LocaleKeys.document_plugins_cover_downloadCover.tr(),
                    ),
                  ]) {
                    final button = _decorationButton(
                      ValueKey('$prefix-decoration-$suffix'),
                    );
                    if (cover == null) {
                      expect(button, findsNothing);
                    } else {
                      await _revealNativeDecoration(tester, mouse, button);
                      _expectNativeDecoration(tester, button, label);
                    }
                  }

                  await _revealNativeDecoration(tester, mouse, coverButton);
                  _expectNativeDecoration(tester, coverButton, coverLabel);
                  await clickFileControl(tester, coverButton);
                  final menu = find.byType(UploadImageMenu);
                  expect(menu, findsOneWidget);
                  expect(tester.widget<UploadImageMenu>(menu).supportTypes, [
                    UploadImageType.color,
                    UploadImageType.local,
                    UploadImageType.url,
                    UploadImageType.unsplash,
                  ]);
                  expect(
                    PaperTheme.isEnabled(tester.element(menu)),
                    appearance == 'paper',
                  );
                  // Open the real native picker, but never select/save a cover
                  // or invoke a download's OS save dialog in this shell test.
                  tester
                      .widget<AppFlowyPopover>(find.byKey(coverKey))
                      .controller!
                      .close();
                  await settleFileControls(tester);
                  expect(menu, findsNothing);
                  expect(repository.root.writeToBuffer(), rootBytes);
                  expect(
                    controller.viewForId(repository.root.id)!.writeToBuffer(),
                    rootBytes,
                  );
                  expect(repository.writes, isEmpty);
                  expect(workspace?.events ?? [], isEmpty);
                  expect(tester.takeException(), isNull, reason: mode.name);
                }

                // Pointer reveal must not be the only way in. Traverse the
                // native buttons with the pointer outside both reveal scopes,
                // including when the shell's unrelated controls are hidden.
                await mouse.moveTo(const Offset(-20, -20));
                await _tabToDecoration(tester, iconButton, iconLabel);
                await tester.sendKeyEvent(
                  LogicalKeyboardKey.enter,
                  physicalKey: PhysicalKeyboardKey.enter,
                );
                await settleFileControls(tester);
                expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
                _closeDecorationPopover(
                  tester,
                  ValueKey('$prefix-decoration-icon'),
                );
                await settleFileControls(tester);
                expect(find.byType(FlowyIconEmojiPicker), findsNothing);

                await _tabToDecoration(tester, coverButton, coverLabel);
                await tester.sendKeyEvent(
                  LogicalKeyboardKey.space,
                  physicalKey: PhysicalKeyboardKey.space,
                );
                await settleFileControls(tester);
                expect(find.byType(UploadImageMenu), findsOneWidget);
                _closeDecorationPopover(tester, coverKey);
                await settleFileControls(tester);
                expect(find.byType(UploadImageMenu), findsNothing);
                expect(repository.root.writeToBuffer(), rootBytes);
                expect(
                  controller.viewForId(repository.root.id)!.writeToBuffer(),
                  rootBytes,
                );
                expect(repository.writes, isEmpty);
                expect(workspace?.events ?? [], isEmpty);
                expect(tester.takeException(), isNull);
              }
            } finally {
              try {
                await mouse.removePointer();
                await unmountFileControls(tester);
                if (workspace != null) {
                  await pumpHomeProfileClose(tester, workspace.close());
                }
              } finally {
                semantics.dispose();
                controls.dispose();
                controller.dispose();
              }
            }
          },
          timeout: const Timeout(Duration(seconds: 30)),
        );
      }
    }

    if (_captureFolderShell) {
      testWidgets(
        '$appearance: folder-shell capture seven modes',
        (tester) async {
          final repository = _Repository();
          final scratch = await tester.runAsync(
            () => Directory.systemTemp.createTemp('appflowy-folder-shell-'),
          );
          if (scratch == null) throw StateError('Capture fixture not created');
          WorkspaceExplorerController? controller;
          final mouse =
              await tester.createGesture(kind: PointerDeviceKind.mouse);
          await mouse.addPointer(location: const Offset(-20, -20));
          try {
            await tester.runAsync(
              () => _prepareFolderShellCapture(repository, scratch, appearance),
            );
            final graph = controller = _controller(repository, writable: true);
            await graph.initialize();
            await mountFileControls(
              tester,
              RepaintBoundary(
                key: _captureKey,
                child: FolderExplorer(
                  rootView: repository.root,
                  controller: graph,
                  onOpen: (_) {},
                ),
              ),
              mode: appearance,
              width: _captureSize.width,
              height: _captureSize.height,
              reduced: true,
            );
            // The shared harness starts at 1100px. Resize the actual surface,
            // not just its child, so no part of the 1200px capture is clipped.
            await tester.binding.setSurfaceSize(_captureSize);
            await settleFileControls(tester);
            await _settleCapturePreviews(tester, graph);
            final header = tester.state(find.byType(FolderGalleryHeader));
            final title = tester.element(find.byKey(_titleKey));
            final contentBounds = tester.getRect(find.byKey(_contentKey));

            for (final mode in FileBrowserViewMode.values) {
              _header(tester).onViewModeChanged!(mode);
              await settleFileControls(tester);
              // Hover the image itself, clear of its scrollbar and buttons.
              // This reveals both native decoration scopes without tooltips,
              // artificial keepVisible flags or accessibility overrides.
              await mouse.moveTo(
                tester.getTopLeft(
                      find.byKey(const ValueKey('workspace-page-cover')),
                    ) +
                    const Offset(32, 32),
              );
              await settleFileControls(tester);
              expect(_header(tester).viewMode, mode);
              expect(
                tester.state(find.byType(FolderGalleryHeader)),
                same(header),
              );
              expect(tester.element(find.byKey(_titleKey)), same(title));
              expect(
                find.descendant(
                  of: find.byKey(_titleKey),
                  matching: find.text('Sample files'),
                ),
                findsOneWidget,
              );
              expect(graph.childrenOf(graph.root.id), hasLength(3));
              for (final view in graph.childrenOf(graph.root.id)) {
                expect(find.text(view.name), findsOneWidget);
              }
              expect(tester.getSize(find.byKey(_captureKey)), _captureSize);
              expect(tester.getRect(find.byKey(_contentKey)), contentBounds);
              expect(
                PaperTheme.isEnabled(tester.element(find.byKey(_titleKey))),
                appearance == 'paper',
              );
              expect(repository.writes, isEmpty);
              expect(tester.takeException(), isNull, reason: mode.name);
              await _writeFolderShellCapture(tester, appearance, mode);
            }
          } finally {
            try {
              await mouse.removePointer();
              await unmountFileControls(tester);
            } finally {
              controller?.dispose();
              await tester.runAsync(() => scratch.delete(recursive: true));
            }
          }
        },
        timeout: const Timeout(Duration(seconds: 60)),
      );
    }

    testWidgets(
        '$appearance: persistent mode menu retains identity and action reveal',
        (tester) async {
      final repository = _Repository(cover: _solidCover);
      final controller = _controller(repository, writable: false);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(-20, -20));
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          FolderExplorer(
            rootView: repository.root,
            controller: controller,
            onOpen: (_) {},
          ),
          mode: appearance,
          height: 900,
          reduced: true,
        );
        final cover = tester.element(find.byType(ViewCoverImage));
        final title = tester.element(find.byKey(_titleKey));
        final header = tester.state(find.byType(FolderGalleryHeader));
        final actions = tester.element(find.byKey(_actionsKey));
        final bounds = _documentRect(tester, find.byKey(_actionsKey));
        for (final mode in FileBrowserViewMode.values) {
          final button = find.byKey(const ValueKey('file-browser-view-button'));
          await tester.ensureVisible(button);
          await settleFileControls(tester);
          expect(_actionOpacity(tester), 0);
          expect(button.hitTestable(), findsOneWidget);
          expect(
            tester.widget<WorkspaceActionRow>(find.byKey(_actionsKey)).leading,
            isNotNull,
          );
          expect(
            find.byKey(const ValueKey('folder-gallery-options')).hitTestable(),
            findsNothing,
          );
          expect(
            find.byKey(const ValueKey('folder-gallery-add')),
            findsNothing,
          );
          expect(
            find.byTooltip(LocaleKeys.workspaceFolderExplorer_newFolder.tr()),
            findsNothing,
          );
          await mouse.moveTo(tester.getCenter(button));
          await settleFileControls(tester);
          expect(_actionOpacity(tester), 1);
          await clickFileControl(tester, button);
          await mouse.moveTo(const Offset(-20, -20));
          await settleFileControls(tester);
          expect(
            _actionOpacity(tester),
            1,
            reason: 'The open menu holds reveal',
          );
          final choice = find.widgetWithText(AppMenuRow, mode.label);
          await tester.ensureVisible(choice);
          await clickFileControl(tester, choice);
          FocusManager.instance.primaryFocus?.unfocus();
          await mouse.moveTo(tester.getCenter(button));
          await mouse.moveTo(const Offset(-20, -20));
          await settleFileControls(tester);
          expect(_actionOpacity(tester), 0);
          expect(tester.state(find.byType(FolderGalleryHeader)), same(header));
          expect(tester.element(find.byType(ViewCoverImage)), same(cover));
          expect(tester.element(find.byKey(_titleKey)), same(title));
          expect(tester.element(find.byKey(_actionsKey)), same(actions));
          expect(_documentRect(tester, find.byKey(_actionsKey)), bounds);
          expect(_header(tester).viewMode, mode);
          expect(repository.writes, isEmpty);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await mouse.removePointer();
        await unmountFileControls(tester);
        controller.dispose();
      }
    });

    testWidgets(
        '$appearance: Gallery and Thumbnails differ in face and density',
        (tester) async {
      final repository = _Repository(previewDocument: true);
      final controller = _controller(repository, writable: false);
      final loader = _PreviewLoader();
      final cache = FolderGalleryPreviewCache(loader: loader);
      final thumbnails = ValueNotifier(false);
      var opened = 0;
      var menus = 0;
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          ValueListenableBuilder<bool>(
            valueListenable: thumbnails,
            builder: (_, value, __) => AnimatedBuilder(
              animation: controller,
              builder: (_, __) => FolderGallery(
                controller: controller,
                previewCache: cache,
                thumbnails: value,
                userProfile: null,
                onOpen: (_) => opened++,
                onNavigate: (_) {},
                onContextMenu: (_, __) => menus++,
                onRequestDelete: () {},
                onRename: (_) {},
              ),
            ),
          ),
          mode: appearance,
          width: 1000,
          height: 600,
          reduced: true,
        );
        SliverGridDelegateWithFixedCrossAxisCount grid() =>
            tester.widget<SliverGrid>(find.byType(SliverGrid)).gridDelegate
                as SliverGridDelegateWithFixedCrossAxisCount;
        final gallery = grid();
        final card = find.byKey(const ValueKey('gallery-card-first'));
        final future = tester.widget<FolderGalleryCard>(card).preview;
        expect(find.byType(GalleryCardFooter), findsWidgets);
        expect(find.byType(FolderThumbnailTile), findsNothing);
        expect(find.text('A real preview excerpt'), findsOneWidget);
        thumbnails.value = true;
        await settleFileControls(tester);
        expect(grid().crossAxisCount, greaterThan(gallery.crossAxisCount));
        expect(grid().mainAxisExtent, lessThan(gallery.mainAxisExtent!));
        expect(find.byType(GalleryCardFooter), findsNothing);
        expect(find.byType(GalleryCardSurface), findsNothing);
        expect(find.byType(FolderThumbnailTile), findsWidgets);
        expect(find.text('A real preview excerpt'), findsOneWidget);
        expect(find.byType(FolderGalleryRichTextPreview), findsOneWidget);
        for (final square in find
            .byKey(
              const ValueKey('folder-thumbnail-square'),
            )
            .evaluate()) {
          final size = (square.renderObject! as RenderBox).size;
          expect(size.width, size.height);
        }
        expect(tester.widget<FolderGalleryCard>(card).preview, same(future));
        expect(tester.widget<FolderGalleryCard>(card).thumbnail, isTrue);
        expect(
          tester
              .widgetList<FolderGalleryPreviewThumbnail>(
                find.byType(FolderGalleryPreviewThumbnail),
              )
              .every((preview) => preview.lightweight),
          isTrue,
        );
        final cardFocus = tester
            .widget<Focus>(
              find.descendant(
                of: card,
                matching: find.byWidgetPredicate(
                  (widget) =>
                      widget is Focus &&
                      widget.focusNode?.debugLabel == 'Folder gallery card',
                ),
              ),
            )
            .focusNode!;
        for (final key in [
          LogicalKeyboardKey.enter,
          LogicalKeyboardKey.space,
        ]) {
          cardFocus.requestFocus();
          await settleFileControls(tester);
          await tester.sendKeyEvent(key);
        }
        expect(opened, 2);
        cardFocus.requestFocus();
        await settleFileControls(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
        expect(menus, 1);
        expect(controller.selection.ids, {'first'});
        final thumbnailGeometry = grid();
        GalleryCardSizeStore.notifier.value = GalleryCardSize.large;
        await settleFileControls(tester);
        expect(grid().mainAxisExtent, thumbnailGeometry.mainAxisExtent);
        expect(grid().crossAxisCount, thumbnailGeometry.crossAxisCount);
        thumbnails.value = false;
        await settleFileControls(tester);
        expect(tester.widget<FolderGalleryCard>(card).preview, same(future));
        expect(loader.reads.values.every((count) => count == 1), isTrue);
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        thumbnails.dispose();
        cache.clear();
        controller.dispose();
      }
    });
  }

  testWidgets(
      'nested current folder, breadcrumbs and selection survive all seven modes',
      (tester) async {
    final repository = _Repository();
    final controller = _controller(repository, writable: false);
    try {
      await controller.initialize();
      await controller.navigateTo('folder');
      controller.selection.selectOnly('nested');
      await mountFileControls(
        tester,
        FolderExplorer(
          rootView: repository.root,
          controller: controller,
          onOpen: (_) {},
        ),
        mode: 'paper',
        reduced: true,
      );
      final header = tester.state(find.byType(FolderGalleryHeader));
      final title = tester.element(find.byKey(_titleKey));
      for (final mode in FileBrowserViewMode.values) {
        _header(tester).onViewModeChanged!(mode);
        await settleFileControls(tester);
        expect(tester.state(find.byType(FolderGalleryHeader)), same(header));
        expect(tester.element(find.byKey(_titleKey)), same(title));
        expect(controller.currentFolder.id, 'folder');
        expect(
          controller.breadcrumbs.map((item) => item.id),
          ['root', 'folder'],
        );
        expect(controller.selection.ids, {'nested'});
        expect(
          find.descendant(
            of: find.byKey(_titleKey),
            matching: find.text('Child folder'),
          ),
          findsOneWidget,
        );
        expect(
          find.descendant(
            of: find.byType(FolderGalleryHeader),
            matching: find.text('Master'),
          ),
          findsOneWidget,
        );
        expect(repository.reads, ['root', 'folder']);
        expect(repository.writes, isEmpty);
        expect(tester.takeException(), isNull);
      }
    } finally {
      await unmountFileControls(tester);
      controller.dispose();
    }
  });

  for (final mode in FileBrowserViewMode.values) {
    testWidgets(
        '${mode.name}: switches do not discard native rename/create drafts',
        (tester) async {
      final repository = _Repository();
      final controller = _controller(repository, writable: true);
      final requested = ValueNotifier(mode);
      try {
        await controller.initialize();
        await mountFileControls(
          tester,
          ValueListenableBuilder<FileBrowserViewMode>(
            valueListenable: requested,
            builder: (_, value, __) => FolderExplorer(
              rootView: repository.root,
              controller: controller,
              initialViewMode: value,
              onOpen: (_) {},
            ),
          ),
          mode: 'paper',
          height: 850,
          reduced: true,
        );
        for (final phase in ['title', 'item', 'create']) {
          if (phase == 'create') {
            controller.beginCreate(
              WorkspaceExplorerDraftKind.folder,
              parentId: 'root',
            );
          } else {
            controller.beginRename(phase == 'title' ? 'root' : 'first');
          }
          await settleFileControls(tester);
          final editor = find.byKey(_renameKey);
          await tester.enterText(editor, 'Unsubmitted $phase');
          final field = tester.widget<EditableText>(editor);
          field.controller.value = field.controller.value.copyWith(
            selection: const TextSelection(baseOffset: 2, extentOffset: 7),
            composing: const TextRange(start: 0, end: 4),
          );
          final draftValue = field.controller.value;
          final element = tester.element(editor);
          final draft = controller.draft;
          for (final next in FileBrowserViewMode.values) {
            _header(tester).onViewModeChanged!(next);
            requested.value = next;
            await settleFileControls(tester);
            expect(_header(tester).viewMode, mode);
            expect(tester.element(editor), same(element));
            expect(field.controller.value, draftValue);
            expect(controller.draft, same(draft));
            expect(repository.writes, isEmpty);
          }
          controller.cancelEditing();
          await settleFileControls(tester);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await unmountFileControls(tester);
        requested.dispose();
        controller.dispose();
      }
    });
  }

  testWidgets(
      'borrowed hosts independently hide identity and controls in every mode',
      (tester) async {
    final repository = _Repository();
    final controller = _controller(repository, writable: false);
    try {
      await controller.initialize();
      await controller.navigateTo('folder');
      for (final (identity, controls) in [
        (false, false),
        (false, true),
        (true, false),
        (true, true),
      ]) {
        for (final mode in FileBrowserViewMode.values) {
          await mountFileControls(
            tester,
            FolderExplorer(
              rootView: repository.root,
              controller: controller,
              embedded: true,
              showHeader: identity,
              showControls: controls,
              showFooter: false,
              initialViewMode: mode,
              onOpen: (_) {},
            ),
            width: 320,
            height: 240,
            textScale: 2,
            mode: 'paper',
            reduced: true,
          );
          expect(
            find.byKey(_titleKey),
            identity ? findsOneWidget : findsNothing,
          );
          expect(
            find.byKey(_actionsKey),
            controls ? findsOneWidget : findsNothing,
          );
          expect(
            find.descendant(
              of: find.byType(FolderGalleryHeader),
              matching: find.widgetWithText(TextButton, 'Master'),
            ),
            controls ? findsOneWidget : findsNothing,
          );
          final bounds = tester.getRect(find.byKey(_contentKey));
          expect(bounds.size.isFinite, isTrue);
          expect(bounds.height, greaterThan(0));
          expect(repository.writes, isEmpty);
          expect(
            tester.takeException(),
            isNull,
            reason: '$mode/$identity/$controls',
          );
        }
      }
    } finally {
      await unmountFileControls(tester);
      // The borrowing shell must not dispose the owning graph.
      expect(controller.viewForId('first'), isNotNull);
      controller.dispose();
    }
  });

  testWidgets(
      'folder hover claims Find from navigation using its actual search node',
      (tester) async {
    final repository = _Repository();
    final controller = _controller(repository, writable: false);
    final navigation = FocusNode(debugLabel: 'Unrelated navigation');
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final regions = ContextualFindRegion.debugRegisteredRegionCount;
    try {
      await controller.initialize();
      await mountFileControls(
        tester,
        Column(
          children: [
            TextButton(
              focusNode: navigation,
              onPressed: () {},
              child: const Text('Navigation'),
            ),
            Expanded(
              child: FolderExplorer(
                rootView: repository.root,
                controller: controller,
                initialViewMode: FileBrowserViewMode.tiles,
                onOpen: (_) {},
              ),
            ),
          ],
        ),
        reduced: true,
      );
      final header = _header(tester);
      final hiddenField = find.byKey(_searchKey, skipOffstage: false);
      final element = tester.element(hiddenField);
      expect(_actionOpacity(tester), 0);
      navigation.requestFocus();
      await settleFileControls(tester);
      expect(navigation.hasPrimaryFocus, isTrue);
      await mouse.addPointer(
        location: tester.getBottomLeft(find.byKey(_contentKey)) +
            const Offset(32, -32),
      );
      await tester.pump();
      await tester.sendKeyDownEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await tester.sendKeyEvent(
        LogicalKeyboardKey.keyF,
        physicalKey: PhysicalKeyboardKey.keyF,
      );
      await tester.sendKeyUpEvent(
        LogicalKeyboardKey.controlLeft,
        physicalKey: PhysicalKeyboardKey.controlLeft,
      );
      await settleFileControls(tester);
      expect(header.searchFocusNode!.hasPrimaryFocus, isTrue);
      expect(tester.element(find.byKey(_searchKey)), same(element));
      expect(
        tester.widget<TextField>(find.byKey(_searchKey)).focusNode,
        same(header.searchFocusNode),
      );
      expect(controller.query, isEmpty);
      expect(controller.selection.isEmpty, isTrue);
      await mouse.moveTo(const Offset(-20, -20));
      await settleFileControls(tester);
      expect(
        _actionOpacity(tester),
        1,
        reason: 'Focused search stays revealed',
      );
      await tester.enterText(find.byKey(_searchKey), '.bin');
      navigation.requestFocus();
      await settleFileControls(tester);
      expect(header.searchFocusNode!.hasFocus, isFalse);
      expect(controller.query, '.bin');
      expect(
        _actionOpacity(tester),
        1,
        reason: 'The query keeps search visible',
      );
      header.searchFocusNode!.requestFocus();
      await settleFileControls(tester);
      await tester.sendKeyEvent(
        LogicalKeyboardKey.escape,
        physicalKey: PhysicalKeyboardKey.escape,
      );
      navigation.requestFocus();
      await settleFileControls(tester);
      expect(header.searchController.text, isEmpty);
      expect(controller.query, isEmpty);
      expect(_actionOpacity(tester), 0);
      expect(tester.element(hiddenField), same(element));
      expect(repository.writes, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await unmountFileControls(tester);
      navigation.dispose();
      controller.dispose();
      expect(ContextualFindRegion.debugRegisteredRegionCount, regions);
    }
  });

  testWidgets(
      'lightweight PDF/video squares retain genuine types without native engines',
      (tester) async {
    for (final (extension, kind) in [
      ('pdf', FolderGalleryPreviewKind.pdf),
      ('mp4', FolderGalleryPreviewKind.video),
    ]) {
      final view = ViewPB(
        id: extension,
        name: 'Stored.$extension',
        layout: ViewLayoutPB.Document,
        extra: WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl: '/never-opened/file.$extension',
        ).mergeIntoExtra(''),
      );
      final item = WorkspaceExplorerItem.fromView(view);
      final data =
          FolderGalleryPreviewParser.withoutDocument(view: view, item: item)!;
      expect(data.kind, kind);
      await mountFileControls(
        tester,
        FolderGalleryCard(
          item: item,
          view: view,
          preview: Future.value(data),
          userProfile: null,
          selected: false,
          editing: false,
          thumbnail: true,
          onTap: () {},
          onRename: () {},
          onRenameSubmitted: (_) async => false,
          onRenameCancelled: () {},
          onMore: (_) {},
          onContextMenu: (_) {},
        ),
        width: 148,
        height: 198,
        reduced: true,
      );
      expect(
        find.byKey(const ValueKey('folder-thumbnail-media-identity')),
        findsOneWidget,
      );
      expect(find.byType(GalleryCardFooter), findsNothing);
      expect(find.text(view.name), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
    await unmountFileControls(tester);
  });
}

FolderGalleryHeader _header(WidgetTester tester) =>
    tester.widget<FolderGalleryHeader>(
        find.byType(FolderGalleryHeader, skipOffstage: false));

Rect _documentRect(WidgetTester tester, Finder finder) => tester
    .getRect(finder)
    .shift(Offset(0, Scrollable.of(tester.element(finder)).position.pixels));

double _actionOpacity(WidgetTester tester) => tester
    .widget<AnimatedOpacity>(
      find.descendant(
        of: find.byKey(_actionsKey),
        // Inspect the shared strip fade, not the search field's own fades.
        matching: find.ancestor(
          of: find.byKey(const ValueKey('folder-gallery-options')),
          matching: find.byType(AnimatedOpacity),
        ),
      ),
    )
    .opacity;

Finder _decorationButton(Key key) => find.descendant(
      of: find.byKey(key, skipOffstage: false),
      matching: find.byType(TextButton, skipOffstage: false),
      skipOffstage: false,
    );

Future<void> _revealNativeDecoration(
  WidgetTester tester,
  TestGesture mouse,
  Finder button,
) async {
  expect(button, findsOneWidget);
  expect(
    find.ancestor(
      of: button,
      matching: find.byWidgetPredicate(
        (widget) => widget is CustomScrollView,
        skipOffstage: false,
      ),
    ),
    findsOneWidget,
  );
  await mouse.moveTo(const Offset(-20, -20));
  // The cover and identity have separate reveal regions. Center the actual
  // control in the unified page viewport before hovering its new position;
  // a previous cover-button pointer position is not an identity hover.
  await Scrollable.ensureVisible(tester.element(button), alignment: 0.5);
  await settleFileControls(tester);
  _expectDecorationInViewport(tester, button);
  await mouse.moveTo(tester.getCenter(button));
  await settleFileControls(tester);
}

void _expectDecorationInViewport(WidgetTester tester, Finder button) {
  final bounds = tester.getRect(button);
  final viewport = tester.getRect(find.byKey(_contentKey));
  final screen = tester.getRect(find.byType(Scaffold));
  final position = Scrollable.of(tester.element(button)).position;
  final reason = '${_header(tester).viewMode.name}: action=$bounds, '
      'header=$viewport, screen=$screen, scroll=${position.pixels}/'
      '${position.maxScrollExtent}';
  expect(bounds.isEmpty, isFalse, reason: reason);
  for (final clip in [viewport, screen]) {
    expect(clip.inflate(0.01).contains(bounds.topLeft), isTrue, reason: reason);
    expect(
      clip.inflate(0.01).contains(bounds.bottomRight),
      isTrue,
      reason: reason,
    );
  }
}

void _expectNativeDecoration(WidgetTester tester, Finder button, String label) {
  expectFileControlPainted(tester, button);
  _expectDecorationInViewport(tester, button);
  expect(
    button.hitTestable(),
    findsOneWidget,
    reason: '$label must receive a pointer in ${_header(tester).viewMode.name}',
  );
  expect(tester.widget<TextButton>(button).onPressed, isNotNull);
  final node = tester.getSemantics(button);
  expect(node.attached, isTrue);
  final data = node.getSemanticsData();
  expect(data.label, label);
  expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(SemanticsFlag.isEnabled), isTrue);
  expect(data.hasAction(SemanticsAction.tap), isTrue);
}

Future<void> _tabToDecoration(
  WidgetTester tester,
  Finder button,
  String label,
) async {
  FocusManager.instance.primaryFocus?.unfocus();
  await settleFileControls(tester);
  for (var index = 0; index < 64; index++) {
    await tester.sendKeyEvent(
      LogicalKeyboardKey.tab,
      physicalKey: PhysicalKeyboardKey.tab,
    );
    await settleFileControls(tester);
    final focusedContext = FocusManager.instance.primaryFocus?.context;
    if (focusedContext?.findAncestorWidgetOfExactType<TextButton>() ==
        tester.widget<TextButton>(button)) {
      _expectNativeDecoration(tester, button, label);
      expect(
        tester
            .getSemantics(button)
            .getSemanticsData()
            .hasFlag(SemanticsFlag.isFocused),
        isTrue,
      );
      return;
    }
  }
  fail('Native Tab traversal did not reveal/reach $label');
}

void _closeDecorationPopover(WidgetTester tester, Key key) {
  final root = find.byKey(key);
  final popover = tester.widget(root) is AppFlowyPopover
      ? root
      : find.descendant(of: root, matching: find.byType(AppFlowyPopover));
  tester.widget<AppFlowyPopover>(popover).controller!.close();
}

File _folderShellCaptureFile(String appearance, FileBrowserViewMode mode) =>
    File('build/performance/folder-shell-$appearance-${mode.name}.png');

Future<void> _prepareFolderShellCapture(
  _Repository repository,
  Directory scratch,
  String appearance,
) async {
  await Directory('build/performance').create(recursive: true);
  // Do not let a failed capture leave an old screenshot masquerading as fresh.
  // No golden references or unrelated performance artifacts are touched.
  for (final mode in FileBrowserViewMode.values) {
    final output = _folderShellCaptureFile(appearance, mode);
    if (await output.exists()) await output.delete();
  }
  repository.root
    ..name = 'Sample files'
    ..extra = ViewCoverCodec.mergeCover(repository.root.extra, _solidCover);
  repository.views
    ..clear()
    ..[repository.root.id] = ViewPB.fromBuffer(repository.root.writeToBuffer());
  // Only authored, disposable samples enter the injected graph. Their actual
  // bytes feed the normal gallery loader; no collab/backend/network reads.
  for (final (index, (name, contents)) in [
    (
      'Overview.md',
      '# Example project\n\nA small folder for visual review.\n'
          '\n- Gather ideas\n- Keep notes together\n',
    ),
    (
      'Checklist.txt',
      'Sample checklist\nReview the layout\nCheck every view\n',
    ),
    (
      'Example.dart',
      'String greeting(String name) {\n  return "Hello, \$name";\n}\n',
    ),
  ].indexed) {
    final file = await File('${scratch.path}/$name').writeAsString(contents);
    final view = fileControlView('sample-$index', name, file.path)
      ..parentViewId = repository.root.id;
    repository.views[view.id] = view;
  }
}

Future<void> _settleCapturePreviews(
  WidgetTester tester,
  WorkspaceExplorerController controller,
) async {
  final cache =
      tester.widget<FolderGallery>(find.byType(FolderGallery)).previewCache;
  List<FolderGalleryPreview>? previews;
  final completion = Future.wait([
    for (final view in controller.childrenOf(controller.root.id))
      cache.previewFor(view: view, item: controller.itemForId(view.id)!),
  ]).then<void>((value) {
    previews = value;
  });
  // IO began while the real gallery mounted in FakeAsync. Alternate real IO
  // turns and frames rather than awaiting that fake-zone future in runAsync.
  for (var turn = 0; previews == null && turn < 200; turn++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
  expect(
    previews,
    isNotNull,
    reason: 'Sample previews must finish before capture',
  );
  await completion;
  for (final preview in previews!) {
    expect(preview.unavailable, isFalse);
    expect(preview.blocks, isNotEmpty);
  }
  await settleFileControls(tester);
}

Future<void> _writeFolderShellCapture(
  WidgetTester tester,
  String appearance,
  FileBrowserViewMode mode,
) async {
  final boundary =
      tester.renderObject<RenderRepaintBoundary>(find.byKey(_captureKey));
  expect(boundary.debugNeedsPaint, isFalse);
  await tester.runAsync(() async {
    final image = await boundary.toImage().timeout(const Duration(seconds: 10));
    try {
      expect(image.width, _captureSize.width.toInt());
      expect(image.height, _captureSize.height.toInt());
      final png = await image.toByteData(format: ImageByteFormat.png);
      if (png == null) throw StateError('Folder shell PNG encoding failed');
      final bytes =
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      expect(bytes.take(8), orderedEquals([137, 80, 78, 71, 13, 10, 26, 10]));
      await _folderShellCaptureFile(appearance, mode)
          .writeAsBytes(bytes, flush: true);
    } finally {
      image.dispose();
    }
  });
}

WorkspaceExplorerController _controller(
  _Repository repository, {
  required bool writable,
}) =>
    WorkspaceExplorerController(
      root: repository.root,
      repository: repository,
      listenForUpdates: false,
      canWrite: () => writable,
    );

class _Repository extends ExplorerPermissionRepository {
  _Repository({PageStyleCover? cover, bool previewDocument = false}) {
    root.name = 'Master';
    if (cover != null) {
      root.extra = ViewCoverCodec.mergeCover(root.extra, cover);
    }
    views[root.id] = ViewPB.fromBuffer(root.writeToBuffer());
    if (previewDocument) {
      views['first'] = ViewPB(
        id: 'first',
        parentViewId: 'root',
        name: 'Authored note',
        layout: ViewLayoutPB.Document,
      );
    }
    for (var index = 0; index < 12; index++) {
      final view = permissionFile('file-$index', 'root', 'File $index.bin');
      views[view.id] = view;
    }
  }

  final reads = <String>[];

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(String id) {
    reads.add(id);
    return super.getChildren(id);
  }
}

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc(UserWorkspacePB workspace)
      : super(
          UserWorkspaceState.initial(UserProfilePB()).copyWith(
            currentWorkspace: workspace,
            workspaces: [workspace],
          ),
        );

  final events = <UserWorkspaceEvent>[];

  @override
  void add(UserWorkspaceEvent event) => events.add(event);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PreviewLoader extends FolderGalleryPreviewLoader {
  final reads = <String, int>{};

  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async {
    reads.update(view.id, (value) => value + 1, ifAbsent: () => 1);
    if (item.kind == WorkspaceExplorerItemKind.document) {
      return const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.document,
        blocks: [
          FolderGalleryPreviewBlock(
            kind: FolderGalleryPreviewBlockKind.paragraph,
            runs: [FolderGalleryTextRun(text: 'A real preview excerpt')],
          ),
        ],
        wordCount: 4,
        readingMinutes: 1,
        tags: [],
        fileTypeLabel: 'PAGE',
      );
    }
    return FolderGalleryPreviewParser.withoutDocument(view: view, item: item)!;
  }
}
