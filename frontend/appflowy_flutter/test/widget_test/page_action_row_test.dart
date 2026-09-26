import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/presentation/widgets/workspace_cover_actions.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/collection/collection_icon_button.dart';
import 'package:appflowy/plugins/collection/collection_page.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/views/collection_page_scroll_scope.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/desktop_cover.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/document_cover_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/upload_image_menu/upload_image_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_action_row.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_gallery_header.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart' as user;
import 'package:appflowy_editor/appflowy_editor.dart' hide UploadImageMenu;
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

const _colorCover = PageStyleCover(
  type: PageStyleCoverImageType.pureColor,
  value: '#D9C7A4',
);
const _imageCover = PageStyleCover(
  type: PageStyleCoverImageType.builtInImage,
  value: 'n1',
);
const _outsideKey = ValueKey('action-row-outside');
const _bodyEdge = ValueKey('action-row-body-edge');
const _documentTitle = ValueKey('action-row-document-title');
const _away = Offset(-20, -20);

void main() {
  final previousRecents = RecentIcons.enable;
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = previousRecents);

  for (final appearance in vividIconTestAppearances) {
    testWidgets('$appearance: one flat row reveals as a unit without reflow',
        (tester) async {
      _viewport(tester);
      final frame = _Frame();
      final outside = FocusNode();
      final semantics = tester.ensureSemantics();
      final invoked = <String>[];
      final view = _folder(cover: _imageCover);
      final original = view.writeToBuffer();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _away);
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            frame,
            (context) => Column(
              children: [
                PreviewToolbarRegion(
                  child: ViewDecorationActions(
                    view: view,
                    visible: false,
                    children: _extras(context, invoked.add),
                  ),
                ),
                _outside(outside),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(WorkspaceActionRow);
        _expectFlatRow(tester, row, count: 8);
        final before = tester.getRect(row);
        final bodyBefore = tester.getRect(find.byKey(_outsideKey));
        expect(before.height, greaterThanOrEqualTo(32));
        _expectOneLine(tester, row);
        expect(_opacity(tester, row), 0);
        expect(_buttons(row).hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Search'), findsNothing);

        await mouse.moveTo(before.center);
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 1);
        expect(_buttons(row).hitTestable(), findsNWidgets(8));
        expect(tester.getRect(row), before);
        expect(tester.getRect(find.byKey(_outsideKey)), bodyBefore);
        for (final button in tester.widgetList<TextButton>(_buttons(row))) {
          expect(button.style!.backgroundColor!.resolve({})!.a, 0);
        }
        expect(
          PaperTheme.isEnabled(tester.element(row)),
          appearance == 'paper',
        );

        await mouse.moveTo(_away);
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 0);
        final search = find.widgetWithText(TextButton, 'Search');
        Focus.of(tester.element(find.text('Search'))).requestFocus();
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 1);
        final data = tester.getSemantics(search).getSemanticsData();
        expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        expect(invoked, ['Search']);
        outside.requestFocus();
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 0);

        // First touch reveals the entire retained row, not an invisible action.
        await tester.tapAt(Offset(before.right - 2, before.center.dy));
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 1);
        expect(invoked, ['Search']);
        expect(tester.getRect(row), before);
        expect(tester.getRect(find.byKey(_outsideKey)), bodyBefore);

        frame
          ..width = 320
          ..scale = 2
          ..direction = ui.TextDirection.rtl
          ..rebuild();
        await tester.pumpAndSettle();
        _expectFlatRow(tester, row, count: 8);
        _expectInside(tester, row);
        final wrapped = tester.getRect(row);
        expect(wrapped.height, greaterThan(before.height));
        await mouse.moveTo(wrapped.center);
        await mouse.moveTo(_away);
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 0);
        expect(tester.getRect(row), wrapped);
        frame
          ..accessible = true
          ..reducedMotion = true
          ..rebuild();
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 1);
        expect(_fade(tester, row).duration, Duration.zero);
        expect(view.writeToBuffer(), original);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await disposeVividIconPicker(tester);
        outside.dispose();
        frame.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '$appearance: gallery page menus hold their row and search survives resize',
        (tester) async {
      _viewport(tester);
      final frame = _Frame();
      // Both decorations are configured; missing-icon discovery is tested
      // separately and must not be mistaken for a hover-reveal regression.
      final view = _folder(cover: _colorCover)
        ..icon = EmojiIconData.emoji('📘').toViewIcon();
      final repository = _Repository(view);
      final controller = _controller(view, repository);
      final search = TextEditingController();
      final outside = FocusNode();
      final queries = <String>[];
      var menuOpens = 0;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _away);
      try {
        await controller.initialize();
        await tester.pumpWidget(
          _app(
            appearance,
            frame,
            // Deliberately above the header's reveal region, like the real
            // explorer's void callback. The header must hold its own scope.
            (ownerContext) => Navigator(
              onGenerateRoute: (settings) => MaterialPageRoute<void>(
                settings: settings,
                builder: (_) => SingleChildScrollView(
                  child: Column(
                    children: [
                      FolderGalleryHeader(
                        controller: controller,
                        searchController: search,
                        onSearchChanged: queries.add,
                        onNavigate: (_) {},
                        onAddFile: (_) {},
                        onCreateCollection: (_) {},
                        onCreateDatabase: (_) {},
                        onMore: (position) {
                          menuOpens++;
                          unawaited(
                            showAppMenu<void>(
                              context: ownerContext,
                              globalPosition: position,
                              entries: [
                                AppMenuItem(
                                  label: 'View options',
                                  onSelected: () {},
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      _outside(outside),
                    ],
                  ),
                ),
              ),
            ),
            scroll: false,
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(WorkspaceActionRow);
        final headerState = tester.state(find.byType(FolderGalleryHeader));
        final decorationState =
            tester.state(find.byType(ViewDecorationActions));
        _expectFlatRow(tester, row, count: 4);
        _expectSplitDecorations(tester, coverButtons: 2);
        _expectOneLine(tester, row);
        final wide = tester.getRect(row);
        final title =
            tester.getRect(find.byKey(const ValueKey('folder-gallery-title')));
        expect(_opacity(tester, row), 0);
        expect(_opacity(tester, _iconActions()), 0);
        expect(_opacity(tester, find.byType(WorkspacePageCover)), 0);
        final switcher =
            find.byKey(const ValueKey('folder-gallery-view-switcher'));
        expect(switcher.hitTestable(), findsNothing);

        for (final trigger in [
          switcher,
          find.descendant(
            of: find.byKey(const ValueKey('folder-gallery-options')),
            matching: find.byType(IconButton),
          ),
        ]) {
          await mouse.moveTo(tester.getCenter(trigger));
          await tester.pumpAndSettle();
          expect(_opacity(tester, _iconActions()), 1);
          expect(_opacity(tester, find.byType(WorkspacePageCover)), 0);
          await tester.tap(trigger, kind: PointerDeviceKind.mouse);
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuRow), findsOneWidget);
          expect(
            ModalRoute.of(tester.element(find.byType(FolderGalleryHeader)))!
                .isCurrent,
            isTrue,
            reason: 'The popup uses the root navigator, not this nested route.',
          );
          await mouse.moveTo(_away);
          await tester.pumpAndSettle();
          expect(_opacity(tester, row), 1);
          expect(tester.getRect(row), wide);
          expect(
            tester.getRect(find.byKey(const ValueKey('folder-gallery-title'))),
            title,
          );
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          outside.requestFocus();
          await tester.pumpAndSettle();
          expect(_opacity(tester, row), 0);
        }
        expect(menuOpens, 2);
        final searchButton = find.descendant(
          of: find.byKey(const ValueKey('folder-gallery-search')),
          matching: find.byType(IconButton),
        );
        await mouse.moveTo(tester.getCenter(searchButton));
        await tester.pumpAndSettle();
        await tester.tap(searchButton, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'Keep this query');
        final field = tester.widget<EditableText>(find.byType(EditableText));
        final fieldState = tester.state(find.byType(EditableText));
        const selection = TextSelection(baseOffset: 2, extentOffset: 8);
        search.selection = selection;
        await mouse.moveTo(_away);
        for (final width in [320.0, 720.0, 1400.0]) {
          frame
            ..width = width
            ..scale = 2
            ..direction = ui.TextDirection.rtl
            ..rebuild();
          await tester.pumpAndSettle();
          expect(
            tester.state(find.byType(FolderGalleryHeader)),
            same(headerState),
          );
          expect(
            tester.state(find.byType(ViewDecorationActions)),
            same(decorationState),
          );
          expect(tester.state(find.byType(EditableText)), same(fieldState));
          expect(field.focusNode.hasFocus, isTrue);
          expect(search.text, 'Keep this query');
          expect(search.selection, selection);
          expect(_opacity(tester, row), 1);
          _expectSplitDecorations(tester, coverButtons: 2);
          _expectInside(tester, row);
          expect(tester.takeException(), isNull);
        }
        expect(queries, ['Keep this query']);
        expect(repository.writes, 0);
      } finally {
        await mouse.removePointer();
        await disposeVividIconPicker(tester);
        controller.dispose();
        search.dispose();
        outside.dispose();
        frame.dispose();
      }
    });

    testWidgets(
        '$appearance: dashboard page tools stay separate from decorations',
        (tester) async {
      _viewport(tester);
      final frame = _Frame();
      final view = _folder(cover: _colorCover)
        ..icon = EmojiIconData.emoji('📘').toViewIcon();
      final controller = DashboardController(
        viewId: '',
        document: DashboardDocument.blank(),
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _away);
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            frame,
            (_) => DashboardPage(view: view, controller: controller),
            scroll: false,
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(WorkspaceActionRow);
        _expectFlatRow(tester, row, count: 2);
        _expectSplitDecorations(tester, coverButtons: 2);
        _expectOneLine(tester, row);
        expect(_opacity(tester, row), 0);
        final iconActions = _iconActions();
        final cover = find.byType(WorkspacePageCover);
        expect(_opacity(tester, iconActions), 0);
        expect(_opacity(tester, cover), 0);
        final decoration = tester.state(find.byType(ViewDecorationActions));
        final title = tester.element(
          find.byKey(const ValueKey('dashboard-page-title')),
        );
        await mouse.moveTo(tester.getCenter(row));
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 1);
        expect(_opacity(tester, iconActions), 1);
        expect(_opacity(tester, cover), 0);
        await mouse.moveTo(tester.getCenter(cover));
        await tester.pumpAndSettle();
        expect(_opacity(tester, cover), 1);
        expect(_buttons(cover).hitTestable(), findsNWidgets(2));
        expect(_opacity(tester, iconActions), 1);
        await mouse.moveTo(
          tester.getCenter(find.byKey(const ValueKey('workspace-page-icon'))),
        );
        await tester.pumpAndSettle();
        expect(_opacity(tester, iconActions), 1);
        expect(_buttons(iconActions).hitTestable(), findsOneWidget);
        expect(_opacity(tester, cover), 0);
        final options = find.descendant(
          of: find.byKey(const ValueKey('dashboard-options')),
          matching: find.byType(IconButton),
        );
        await tester.tap(options);
        await tester.pumpAndSettle();
        await mouse.moveTo(_away);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuRow), findsWidgets);
        expect(_opacity(tester, row), 1);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        for (final width in [320.0, 1400.0]) {
          frame
            ..width = width
            ..scale = 2
            ..rebuild();
          await tester.pumpAndSettle();
          _expectFlatRow(tester, row, count: 2);
          _expectSplitDecorations(tester, coverButtons: 2);
          _expectInside(tester, row);
          expect(
            tester.state(find.byType(ViewDecorationActions)),
            same(decoration),
          );
          expect(
            tester.element(find.byKey(const ValueKey('dashboard-page-title'))),
            same(title),
          );
          expect(tester.takeException(), isNull);
        }
        expect(controller.canUndo, isFalse);
      } finally {
        await mouse.removePointer();
        await disposeVividIconPicker(tester);
        controller.dispose();
        frame.dispose();
      }
    });

    testWidgets(
        '$appearance: workspace covers compose extras without granting permissions',
        (tester) async {
      _viewport(tester);
      final frame = _Frame();
      final outside = FocusNode();
      var workspace = user.UserWorkspacePB(
        workspaceId: 'action-row-workspace',
        workspaceType: user.WorkspaceTypePB.ServerW,
        role: user.AFRolePB.Owner,
        cover: WorkspaceCoverCodec.encode(_colorCover),
      );
      final original = workspace.writeToBuffer();
      final changes = <PageStyleCover?>[];
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _away);
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            frame,
            (context) => Column(
              children: [
                WorkspaceCoverActions(
                  workspace: workspace,
                  visible: false,
                  onCoverChanged: changes.add,
                  children: _extras(context, (_) {}),
                ),
                _outside(outside),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byType(WorkspaceActionRow);
        _expectFlatRow(tester, row, count: 6);
        final before = tester.getRect(row);
        await mouse.moveTo(before.center);
        await tester.pumpAndSettle();
        final change = find.widgetWithText(TextButton, 'Change Cover');
        await tester.tap(change, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await mouse.moveTo(_away);
        await tester.pumpAndSettle();
        expect(find.byType(UploadImageMenu), findsOneWidget);
        expect(_opacity(tester, row), 1);
        expect(tester.getRect(row), before);
        tester
            .widget<AppFlowyPopover>(
              find.byKey(const ValueKey('workspace-decoration-cover')),
            )
            .controller!
            .close();
        await tester.pumpAndSettle();
        outside.requestFocus();
        await tester.pumpAndSettle();
        expect(_opacity(tester, row), 0);
        expect(workspace.writeToBuffer(), original);
        expect(changes, isEmpty);
        workspace = user.UserWorkspacePB.fromBuffer(original)
          ..role = user.AFRolePB.Guest;
        frame
          ..width = 320
          ..scale = 2
          ..rebuild();
        await tester.pumpAndSettle();
        _expectFlatRow(tester, row, count: 4);
        expect(find.byType(DecorationActionButton), findsNothing);
        _expectInside(tester, row);
        expect(changes, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await disposeVividIconPicker(tester);
        outside.dispose();
        frame.dispose();
      }
    });

    for (final kind in CollectionKind.values) {
      testWidgets(
          '$appearance: ${kind.name} identity aligns with the 24px body edge',
          (tester) async {
        _viewport(tester);
        final frame = _Frame();
        final originalType = CollectionRegistry.typeFor(kind);
        CollectionRegistry.register(
          originalType.withViews([
            for (final mode in originalType.views)
              CollectionViewDefinition(
                id: mode.id,
                labelKey: mode.labelKey,
                icon: mode.icon,
                isAvailable: mode.isAvailable,
                builder: (_, __) => const _Reading(),
              ),
          ]),
        );
        final view = _folder()
          ..extra = CollectionMetadata(kind: kind).mergeIntoExtra(
            const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
          );
        final saved = view.writeToBuffer();
        final repository = _Repository(view);
        final controller = _controller(view, repository);
        final semantics = tester.ensureSemantics();
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: _away);
        try {
          await controller.initialize();
          await tester.pumpWidget(
            _app(
              appearance,
              frame,
              (_) => CollectionPage(
                view: view,
                controller: controller,
                shellOwnsBreadcrumbs: true,
              ),
              scroll: false,
            ),
          );
          await tester.pumpAndSettle();
          final header = tester
              .widget<WorkspacePageHeader>(find.byType(WorkspacePageHeader));
          final pane = tester.getRect(find.byType(CollectionPage));
          final title =
              tester.getRect(find.byKey(const ValueKey('collection-title')));
          final icon = tester
              .getRect(find.byKey(const ValueKey('collection-header-icon')));
          expect(header.maxWidth, double.infinity);
          expect(header.contentInset, CollectionMetrics.gutter);
          expect(CollectionMetrics.gutter, 24);
          expect(title.left, closeTo(pane.left + 24, 0.01));
          expect(icon.left, closeTo(title.left, 0.01));
          expect(
            tester.getTopLeft(find.byKey(_bodyEdge)).dx,
            closeTo(title.left, 0.01),
          );
          final reading = tester.state(find.byType(_Reading));
          final nested = tester
              .state<NestedScrollViewState>(find.byType(NestedScrollView));
          final borrowed = nested.innerController;
          final switcher = tester.widget<CollectionViewSwitcher>(
            find.byType(CollectionViewSwitcher),
          );
          expect(
            switcher.views.map((mode) => mode.id),
            originalType.views
                .where((mode) => mode.availableFor(view.source))
                .map((mode) => mode.id),
          );
          expect(
            _buttons(find.byType(CollectionViewSwitcher)).hitTestable(),
            findsNWidgets(switcher.views.length),
          );
          expect(_opacity(tester, find.byType(WorkspaceActionRow)), 0);
          final decoration = tester.state(find.byType(ViewDecorationActions));
          final iconActions = _iconActions();
          final addCover = find.byKey(const ValueKey('view-decoration-cover'));
          final addCoverButton = _buttons(addCover);
          final coverLabel = tester
              .widget<DecorationActionButton>(
                find.descendant(
                  of: addCover,
                  matching: find.byType(DecorationActionButton),
                ),
              )
              .label;
          final headerBounds = tester.getRect(find.byType(WorkspacePageHeader));
          expect(_opacity(tester, iconActions), 0);
          expect(_buttons(iconActions).hitTestable(), findsNothing);
          expect(find.semantics.byLabel(coverLabel), findsNothing);
          await mouse.moveTo(title.center);
          await tester.pumpAndSettle();
          expect(_opacity(tester, iconActions), 1);
          expect(_buttons(iconActions).hitTestable(), findsNWidgets(2));
          expect(
            tester.getRect(find.byType(WorkspacePageHeader)),
            headerBounds,
          );
          await mouse.moveTo(_away);
          await tester.pumpAndSettle();
          expect(_opacity(tester, iconActions), 0);
          expect(find.semantics.byLabel(coverLabel), findsNothing);

          final addCoverFocus = Focus.of(tester.element(find.text(coverLabel)));
          for (var i = 0; i < 20 && !addCoverFocus.hasPrimaryFocus; i++) {
            await tester.sendKeyEvent(LogicalKeyboardKey.tab);
            await tester.pumpAndSettle();
          }
          expect(addCoverFocus.hasPrimaryFocus, isTrue);
          expect(addCoverButton.hitTestable(), findsOneWidget);
          final data = tester.getSemantics(addCoverButton).getSemanticsData();
          expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
          expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await tester.pumpAndSettle();
          expect(find.byType(UploadImageMenu), findsOneWidget);
          expect(_opacity(tester, iconActions), 1);
          tester.widget<AppFlowyPopover>(addCover).controller!.close();
          await tester.pumpAndSettle();
          Focus.of(
            tester.element(
              find.descendant(
                of: find.byType(CollectionViewSwitcher),
                matching: find.text(switcher.views.first.label),
              ),
            ),
          ).requestFocus();
          await tester.pumpAndSettle();
          expect(_opacity(tester, iconActions), 0);

          // A first touch on quiet header space reveals, but cannot dispatch
          // an invisible mutation. Mouse entry/exit restores desktop hiding.
          await tester
              .tapAt(Offset(headerBounds.right - 2, headerBounds.top + 2));
          await tester.pumpAndSettle();
          expect(_opacity(tester, iconActions), 1);
          expect(repository.writes, 0);
          await mouse.moveTo(title.center);
          await mouse.moveTo(_away);
          await tester.pumpAndSettle();
          expect(_opacity(tester, iconActions), 0);
          for (final width in [320.0, 760.0, 1400.0]) {
            frame
              ..width = width
              ..scale = 2
              ..rebuild();
            await tester.pumpAndSettle();
            final tabs = find.byType(CollectionViewSwitcher);
            expect(
              find.descendant(
                of: tabs,
                matching: find.byType(SingleChildScrollView),
              ),
              findsNothing,
            );
            expect(_buttons(tabs), findsNWidgets(switcher.views.length));
            _expectInside(tester, tabs);
            _expectInside(tester, find.byType(WorkspaceActionRow));
            expect(tester.state(find.byType(_Reading)), same(reading));
            expect(nested.innerController, same(borrowed));
            expect(borrowed.positions, hasLength(1));
            expect(view.writeToBuffer(), saved);
            expect(repository.writes, 0);
            expect(tester.takeException(), isNull);
          }
          final covered = ViewPB.fromBuffer(saved)
            ..extra = ViewCoverCodec.mergeCover(view.extra, _colorCover);
          controller.updateRoot(covered);
          await tester.pumpAndSettle();
          final cover = tester.getRect(find.byType(WorkspacePageCover));
          final coveredIcon = tester.getRect(
            find.byKey(const ValueKey('collection-header-icon')),
          );
          expect(cover.bottom - coveredIcon.top, closeTo(22, .01));
          expect(
            tester.getTopLeft(iconActions).dy,
            greaterThanOrEqualTo(cover.bottom + 8),
          );
          expect(
            tester.state(find.byType(ViewDecorationActions)),
            same(decoration),
          );
          expect(tester.state(find.byType(_Reading)), same(reading));
          controller.updateRoot(
            ViewPB.fromBuffer(covered.writeToBuffer())..isLocked = true,
          );
          await tester.pumpAndSettle();
          expect(find.byType(DecorationActionButton), findsNothing);
          expect(find.byType(WorkspacePageCover), findsOneWidget);
          expect(tester.state(find.byType(_Reading)), same(reading));
          expect(repository.writes, 0);
          expect(view.writeToBuffer(), saved);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await disposeVividIconPicker(tester);
          // The page must not dispose its host's borrowed graph.
          expect(() => controller.updateRoot(view), returnsNormally);
          controller.dispose();
          frame.dispose();
          semantics.dispose();
          CollectionRegistry.register(originalType);
        }
      });
    }

    testWidgets(
        '$appearance: compact document tools retain title and cover state',
        (tester) async {
      _viewport(tester);
      final frame = _Frame();
      final editor = EditorState.blank()..disableSealTimer = true;
      editor.document.root.updateAttributes({
        DocumentHeaderBlockKeys.coverType: CoverType.color.toString(),
        DocumentHeaderBlockKeys.coverDetails: '0xffd9c7a4',
      });
      final documentBefore = editor.document.toJson();
      final title = TextEditingController(text: 'Document title');
      final titleFocus = FocusNode();
      final changes = <(CoverType, String?)>[];
      var showCover = true;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: _away);
      try {
        await tester.pumpWidget(
          _app(
            appearance,
            frame,
            (_) => PreviewToolbarRegion(
              child: DocumentCover(
                view: ViewPB(id: 'docked-document-cover'),
                node: editor.document.root,
                editorState: editor,
                coverType: CoverType.color,
                coverDetails: '0xffd9c7a4',
                showCoverActions: showCover,
                onChangeCover: (type, value) => changes.add((type, value)),
                layoutBuilder: (image, coverActions) => DocumentHeaderLayout(
                  editorStyle: EditorStyle.desktop(
                    maxWidth: 1400,
                    padding: const EdgeInsets.only(right: 63),
                  ),
                  cover: showCover ? image : null,
                  coverActions: coverActions.isEmpty
                      ? null
                      : Wrap(
                          spacing: WorkspaceTokens.space1,
                          runSpacing: WorkspaceTokens.space1,
                          children: coverActions,
                        ),
                  icon: DocumentIcon(
                    node: editor.document.root,
                    editorState: editor,
                    documentId: 'docked-document-cover',
                    icon: EmojiIconData.emoji('🌿'),
                    emojiSize: kTitleIconSize,
                    opticalRole: IconOpticalRole.header,
                    onChangeIcon: (_) {},
                  ),
                  title: TextField(
                    key: _documentTitle,
                    controller: title,
                    focusNode: titleFocus,
                  ),
                  iconActions: PreviewToolbar(
                    key: const ValueKey('docked-document-icon-actions'),
                    child: Wrap(
                      spacing: WorkspaceTokens.space2,
                      runSpacing: WorkspaceTokens.space1,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        DocumentIcon(
                          key: const ValueKey('docked-document-icon-action'),
                          node: editor.document.root,
                          editorState: editor,
                          documentId: 'docked-document-cover',
                          icon: EmojiIconData.emoji('🌿'),
                          onChangeIcon: (_) {},
                          child: const DecorationActionButton(
                            icon: FlowySvgs.add_icon_s,
                            label: 'Change icon',
                          ),
                        ),
                        if (!showCover)
                          DecorationActionButton(
                            icon: FlowySvgs.add_cover_s,
                            label: 'Add Cover',
                            onTap: () => changes.add((CoverType.asset, '1')),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final row = find.byKey(const ValueKey('docked-document-icon-actions'));
        final cover = find.byType(WorkspacePageCover);
        expect(find.byType(WorkspaceActionRow), findsNothing);
        expect(_buttons(row), findsOneWidget);
        expect(_buttons(cover), findsNWidgets(2));
        final coverState = tester.state(find.byType(DocumentCover));
        final before = tester.getRect(row);
        expect(
          before.bottom,
          lessThan(tester.getTopLeft(find.byKey(_documentTitle)).dy),
        );
        expect(
          find.descendant(
            of: find.byType(DesktopCover),
            matching: find.byType(DecorationActionButton),
          ),
          findsNothing,
        );
        expect(_opacity(tester, row), 0);
        expect(_opacity(tester, cover), 0);
        await mouse.moveTo(tester.getCenter(cover));
        await tester.pumpAndSettle();
        expect(_opacity(tester, cover), 1);
        expect(_buttons(cover).hitTestable(), findsNWidgets(2));
        expect(_opacity(tester, row), 1);
        _expectInside(tester, cover);
        final changeIcon =
            find.byKey(const ValueKey('docked-document-icon-action'));
        await mouse.moveTo(tester.getCenter(changeIcon));
        await tester.pumpAndSettle();
        await tester.tap(changeIcon, kind: PointerDeviceKind.mouse);
        await tester.pumpAndSettle();
        await mouse.moveTo(_away);
        await tester.pumpAndSettle();
        expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
        expect(_opacity(tester, row), 1);
        expect(_opacity(tester, cover), 0);
        expect(tester.getRect(row), before);
        tester
            .widget<AppFlowyPopover>(
              find.descendant(
                of: changeIcon,
                matching: find.byType(AppFlowyPopover),
              ),
            )
            .controller!
            .close();
        await tester.pumpAndSettle();
        await tester.enterText(find.byKey(_documentTitle), 'Unfinished title');
        final fieldState = tester.state(find.byType(EditableText));
        const selection = TextSelection(baseOffset: 2, extentOffset: 6);
        title.selection = selection;
        for (final width in [320.0, 1400.0]) {
          showCover = !showCover;
          frame
            ..width = width
            ..scale = 2
            ..rebuild();
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(DocumentCover)), same(coverState));
          expect(tester.state(find.byType(EditableText)), same(fieldState));
          expect(titleFocus.hasFocus, isTrue);
          expect(title.text, 'Unfinished title');
          expect(title.selection, selection);
          expect(find.byType(WorkspaceActionRow), findsNothing);
          expect(_buttons(row), findsNWidgets(showCover ? 1 : 2));
          expect(cover, showCover ? findsOneWidget : findsNothing);
          if (showCover) {
            expect(_buttons(cover), findsNWidgets(2));
            _expectInside(tester, cover);
          }
          _expectInside(tester, row);
          expect(changes, isEmpty);
          expect(editor.document.toJson(), documentBefore);
          expect(tester.takeException(), isNull);
        }
      } finally {
        await mouse.removePointer();
        await disposeVividIconPicker(tester);
        title.dispose();
        titleFocus.dispose();
        editor.dispose();
        frame.dispose();
      }
    });
  }

  testWidgets(
      'wrapping view tabs keep native keyboard activation and selection',
      (tester) async {
    _viewport(tester);
    final frame = _Frame();
    final semantics = tester.ensureSemantics();
    final selected = <String>[];
    var active = 'view-0';
    final views = [
      for (var i = 0; i < 7; i++)
        CollectionViewDefinition(
          id: 'view-$i',
          labelKey: 'Collection view $i',
          icon: Icons.view_agenda_rounded,
          builder: (_, __) => const SizedBox.shrink(),
        ),
    ];
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          frame,
          (context) => CollectionViewSwitcher(
            palette: CollectionPalette.of(context, CollectionKind.book),
            views: views,
            activeViewId: active,
            onChanged: (id) {
              selected.add(id);
              active = id;
              frame.rebuild();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final tabs = find.byType(CollectionViewSwitcher);
      final wideHeight = tester.getSize(tabs).height;
      final last = find.widgetWithText(TextButton, 'Collection view 6');
      final element = tester.element(last);
      Focus.of(tester.element(find.text('Collection view 6'))).requestFocus();
      await tester.pumpAndSettle();
      frame
        ..width = 320
        ..scale = 2
        ..direction = ui.TextDirection.rtl
        ..rebuild();
      await tester.pumpAndSettle();
      expect(tester.getSize(tabs).height, greaterThan(wideHeight));
      expect(tester.element(last), same(element));
      expect(_buttons(tabs).hitTestable(), findsNWidgets(7));
      _expectInside(tester, tabs);
      final data = tester.getSemantics(last).getSemanticsData();
      expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
      expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(selected, ['view-6']);
      expect(active, 'view-6');
      expect(find.byKey(const ValueKey('collection-view-menu')), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVividIconPicker(tester);
      frame.dispose();
      semantics.dispose();
    }
  });

  testWidgets('extra controls retain an open picker and its in-flight save',
      (tester) async {
    _viewport(tester);
    final frame = _Frame();
    final backend = _PendingCoverBackend();
    var view = _folder(cover: _colorCover);
    var extraControl = false;
    final updates = <ViewPB>[];
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          frame,
          (context) => PreviewToolbarRegion(
            child: ViewDecorationActions(
              view: view,
              coverBackend: backend,
              onViewChanged: updates.add,
              children: [
                ..._extras(context, (_) {}),
                if (extraControl)
                  TextButton(
                    key: const ValueKey('extra-contextual-control'),
                    onPressed: () {},
                    child: const Text('Contextual option'),
                  ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final state = tester.state(find.byType(ViewDecorationActions));
      await tester.tap(find.byKey(const ValueKey('view-decoration-cover')));
      await tester.pumpAndSettle();
      final menu = tester.widget<UploadImageMenu>(find.byType(UploadImageMenu));
      final picker = tester.state(find.byType(UploadImageMenu));
      extraControl = true;
      frame
        ..width = 320
        ..scale = 2
        ..rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ViewDecorationActions)), same(state));
      expect(tester.state(find.byType(UploadImageMenu)), same(picker));

      menu.onSelectedColor!('#557755');
      await tester.pumpAndSettle();
      expect(backend.targets, [view.id]);
      expect(updates, isEmpty);
      view = ViewPB.fromBuffer(view.writeToBuffer())
        ..name = 'A newer name'
        ..extra = ViewCoverCodec.mergeCover('{"retained":42}', _colorCover);
      extraControl = false;
      frame
        ..width = 1400
        ..scale = 1
        ..rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ViewDecorationActions)), same(state));
      // A stale picker callback must not start another save during reflow.
      menu.onSelectedColor!('#994422');
      await tester.pumpAndSettle();
      expect(backend.targets, [view.id]);
      backend.complete();
      await tester.pumpAndSettle();
      expect(updates, hasLength(1));
      expect(updates.single.id, view.id);
      expect(updates.single.name, 'A newer name');
      expect(updates.single.cover?.value, '#557755');
      expect(ViewCoverCodec.decodeExtra(updates.single.extra)['retained'], 42);
      expect(view.cover, _colorCover);
      expect(backend.targets, [view.id]);
      expect(tester.takeException(), isNull);
    } finally {
      backend.complete();
      await disposeVividIconPicker(tester);
      frame.dispose();
    }
  });

  testWidgets(
      'compact cover relocation retains the pending owner and target guard',
      (tester) async {
    _viewport(tester);
    final frame = _Frame();
    final backend = _PendingCoverBackend();
    final original = _folder(cover: _colorCover);
    final originalBytes = original.writeToBuffer();
    var view = original;
    final updates = <ViewPB>[];
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: _away);
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          frame,
          (_) => ViewDecorationActions(
            view: view,
            visible: false,
            coverBackend: backend,
            onViewChanged: updates.add,
            layoutBuilder: (iconActions, coverActions, pageActions) =>
                WorkspacePageHeader(
              cover: view.cover != null && !view.cover!.isNone
                  ? const ColoredBox(color: Color(0xFFD9C7A4))
                  : null,
              coverActions: coverActions,
              identity: WorkspacePageIdentity(
                icon: const WorkspaceGlyph(
                  Icons.folder_rounded,
                  size: WorkspaceTokens.pageIconSize,
                ),
                iconActions: iconActions,
                title: Text(view.name),
                actions: pageActions,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final owner = tester.state(find.byType(ViewDecorationActions));
      final coverButton = find.descendant(
        of: find.byKey(const ValueKey('view-decoration-cover')),
        matching: find.byType(TextButton),
      );
      expect(find.byType(WorkspaceActionRow), findsNothing);
      await mouse.moveTo(tester.getCenter(coverButton));
      await tester.pumpAndSettle();
      await tester.tap(coverButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      final picker = tester.state(find.byType(UploadImageMenu));
      final select = tester
          .widget<UploadImageMenu>(find.byType(UploadImageMenu))
          .onSelectedColor!;
      frame
        ..width = 320
        ..scale = 2
        ..rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
      expect(tester.state(find.byType(UploadImageMenu)), same(picker));
      select('#557755');
      await tester.pumpAndSettle();
      expect(backend.targets, [original.id]);
      expect(backend.pending.isCompleted, isFalse);
      expect(updates, isEmpty);

      // An authoritative removal moves Add Cover from the image to the icon
      // row while the dispatched request still belongs to the same owner.
      view = ViewPB.fromBuffer(originalBytes)
        ..extra = ViewCoverCodec.mergeCover(
          '{"retained":42}',
          const PageStyleCover.none(),
        );
      frame.rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
      expect(find.byType(WorkspacePageCover), findsNothing);
      expect(
        find.descendant(of: _iconActions(), matching: coverButton),
        findsOneWidget,
      );
      expect(find.widgetWithText(TextButton, 'Add Cover'), findsOneWidget);
      tester.widget<TextButton>(coverButton).onPressed!();
      select('#994422');
      await tester.pumpAndSettle();
      expect(find.byType(UploadImageMenu), findsNothing);
      expect(backend.targets, [original.id]);

      view = ViewPB.fromBuffer(view.writeToBuffer())
        ..id = 'next-decoration-target'
        ..name = 'Next target';
      final nextBytes = view.writeToBuffer();
      frame
        ..width = 1400
        ..scale = 1
        ..rebuild();
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
      tester.widget<TextButton>(coverButton).onPressed!();
      await tester.pumpAndSettle();
      expect(find.byType(UploadImageMenu), findsNothing);
      expect(backend.targets, [original.id]);
      backend.complete();
      await tester.pumpAndSettle();
      select('#994422');
      await tester.pumpAndSettle();
      expect(updates, isEmpty);
      expect(backend.targets, [original.id]);
      expect(view.writeToBuffer(), nextBytes);
      expect(original.writeToBuffer(), originalBytes);

      // Only a fresh interaction may write the next target after completion.
      await mouse.moveTo(tester.getCenter(coverButton));
      await tester.pumpAndSettle();
      await tester.tap(coverButton, kind: PointerDeviceKind.mouse);
      await tester.pumpAndSettle();
      tester
          .widget<UploadImageMenu>(find.byType(UploadImageMenu))
          .onSelectedColor!('#225577');
      await tester.pumpAndSettle();
      expect(backend.targets, [original.id, view.id]);
      expect(updates, hasLength(1));
      expect(updates.single.id, view.id);
      expect(updates.single.name, 'Next target');
      expect(updates.single.cover?.value, '#225577');
      expect(ViewCoverCodec.decodeExtra(updates.single.extra)['retained'], 42);
      expect(view.writeToBuffer(), nextBytes);
      expect(tester.state(find.byType(ViewDecorationActions)), same(owner));
      expect(tester.takeException(), isNull);
    } finally {
      backend.complete();
      await mouse.removePointer();
      await disposeVividIconPicker(tester);
      frame.dispose();
    }
  });

  testWidgets(
      'decoration defaults, permission gates and caller children remain independent',
      (tester) async {
    final frame = _Frame();
    var view = _folder(cover: _imageCover);
    var showCover = true;
    var showIcon = true;
    try {
      await tester.pumpWidget(
        _app(
          'paper',
          frame,
          (context) => ViewDecorationActions(
            view: view,
            showCoverAction: showCover,
            showIconAction: showIcon,
            children: _extras(context, (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final row = find.byType(WorkspaceActionRow);
      expect(
        _opacity(tester, row),
        1,
        reason: 'The default visible API is unchanged.',
      );
      _expectFlatRow(tester, row, count: 8);
      view = ViewPB.fromBuffer(view.writeToBuffer())..isLocked = true;
      frame.rebuild();
      await tester.pumpAndSettle();
      _expectFlatRow(tester, row, count: 5);
      expect(find.byType(ViewIconPicker), findsNothing);
      expect(find.byKey(const ValueKey('view-decoration-cover')), findsNothing);
      expect(
        find.byKey(const ValueKey('view-decoration-remove')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('view-decoration-download')),
        findsOneWidget,
      );
      showCover = false;
      showIcon = false;
      frame.rebuild();
      await tester.pumpAndSettle();
      _expectFlatRow(tester, row, count: 4);
      expect(find.byType(DecorationActionButton), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await disposeVividIconPicker(tester);
      frame.dispose();
    }
  });

  testWidgets(
      'header optics enlarge colorful choices only, without scaling default outlines',
      (tester) async {
    _viewport(tester);
    final frame = _Frame()..scale = 2;
    final view = _folder();
    try {
      for (final (saved, size) in [
        (EmojiIconData.none(), 56.0),
        (
          const EmojiIconData(
            FlowyIconType.icon,
            '{"groupName":"appflowy_default_office","iconName":"file-text","color":"0xFF123456"}',
          ),
          56.0,
        ),
        (EmojiIconData.emoji('🌿'), 66.0),
        (
          const EmojiIconData(
            FlowyIconType.icon,
            '{"groupName":"appflowy_vivid_essentials","iconName":"book","color":"0xFF123456"}',
          ),
          66.0,
        ),
      ]) {
        view.icon = saved.toViewIcon();
        final original = view.writeToBuffer();
        await tester.pumpWidget(
          _app(
            'paper',
            frame,
            (_) => Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CollectionIconButton(
                  key: const ValueKey('optical-collection'),
                  view: view,
                  iconSize: 56,
                  opticalRole: IconOpticalRole.header,
                  onViewChanged: (_) {},
                ),
                DatabasePageDecoration(
                  view: view,
                  userProfile: null,
                  horizontalPadding: 24,
                ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        for (final key in ['optical-collection', 'database-page-title-icon']) {
          expect(tester.getSize(find.byKey(ValueKey(key))), Size.square(size));
        }
        if (saved.isNotEmpty) {
          final icons = tester.widgetList<RawEmojiIconWidget>(
            find.byType(RawEmojiIconWidget),
          );
          for (final icon in icons) {
            expect(icon.emojiSize, 56);
            expect(
              icon.opticalRole,
              size == 66 ? IconOpticalRole.header : null,
            );
          }
        }
        expect(view.writeToBuffer(), original);
        expect(tester.takeException(), isNull);
      }
      expect(
        isColorfulViewIcon(
          const EmojiIconData(
            FlowyIconType.icon,
            '{"groupName":"phosphor_regular_office","iconName":"file-text","color":"0xFF123456"}',
          ),
        ),
        isFalse,
      );
      expect(isColorfulViewIcon(EmojiIconData.none()), isFalse);
      expect(
        isColorfulViewIcon(const EmojiIconData(FlowyIconType.icon, '{')),
        isFalse,
      );
    } finally {
      await disposeVividIconPicker(tester);
      frame.dispose();
    }
  });
}

void _viewport(WidgetTester tester) {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1800, 1800);
  addTearDown(tester.view.reset);
}

class _Frame extends ChangeNotifier {
  double width = 1400;
  double scale = 1;
  bool accessible = false;
  bool reducedMotion = false;
  ui.TextDirection direction = ui.TextDirection.ltr;
  final styles = ValueNotifier(DefaultIconStyle.monochrome);

  void rebuild() => notifyListeners();

  @override
  void dispose() {
    styles.dispose();
    super.dispose();
  }
}

Widget _app(
  String appearance,
  _Frame frame,
  WidgetBuilder builder, {
  bool scroll = true,
}) =>
    vividIconTestApp(
      appearance,
      AnimatedBuilder(
        animation: frame,
        builder: (context, _) => DefaultIconStyleScope(
          styles: frame.styles,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(frame.scale),
              accessibleNavigation: frame.accessible,
              disableAnimations: frame.reducedMotion,
            ),
            child: Directionality(
              textDirection: frame.direction,
              child: Align(
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: frame.width,
                  height: 1400,
                  child: scroll
                      ? SingleChildScrollView(child: Builder(builder: builder))
                      : Builder(builder: builder),
                ),
              ),
            ),
          ),
        ),
      ),
    );

List<Widget> _extras(BuildContext context, ValueChanged<String> onPressed) => [
      for (final label in ['Gallery view', 'Search', 'Add file', 'More'])
        TextButton(
          key: ValueKey('extra-$label'),
          onPressed: () => onPressed(label),
          style: WorkspaceChrome.controlStyle(context),
          child: Text(label),
        ),
    ];

Widget _outside(FocusNode focus) => TextButton(
      key: _outsideKey,
      focusNode: focus,
      onPressed: () {},
      child: const Text('Outside'),
    );

Finder _buttons(Finder scope) => find.descendant(
      of: scope,
      matching: find.byWidgetPredicate(
        (widget) => widget is TextButton || widget is IconButton,
      ),
    );

Finder _iconActions() =>
    find.byKey(const ValueKey('view-decoration-icon-actions'));

void _expectSplitDecorations(
  WidgetTester tester, {
  required int coverButtons,
}) {
  final row = find.byType(WorkspaceActionRow);
  final iconRow = find.byKey(const ValueKey('workspace-page-icon-row'));
  final cover = find.byType(WorkspacePageCover);
  expect(find.byType(ViewIconPicker), findsNWidgets(2));
  expect(_buttons(_iconActions()), findsOneWidget);
  expect(
    find.descendant(of: iconRow, matching: _iconActions()),
    findsOneWidget,
  );
  expect(
    find.descendant(of: row, matching: find.byType(DecorationActionButton)),
    findsNothing,
  );
  expect(
    find.descendant(
      of: cover,
      matching: find.byKey(const ValueKey('view-decoration-cover-actions')),
    ),
    findsOneWidget,
  );
  expect(_buttons(cover), findsNWidgets(coverButtons));
  _expectInside(tester, iconRow);
  _expectInside(tester, cover);
}

AnimatedOpacity _fade(WidgetTester tester, Finder row) =>
    tester.widget<AnimatedOpacity>(
      find.descendant(of: row, matching: find.byType(AnimatedOpacity)).first,
    );

double _opacity(WidgetTester tester, Finder row) => _fade(tester, row).opacity;

void _expectFlatRow(WidgetTester tester, Finder row, {required int count}) {
  expect(row, findsOneWidget);
  expect(
    find.descendant(of: row, matching: find.byType(PreviewToolbar)),
    findsOneWidget,
  );
  final wraps = find.descendant(of: row, matching: find.byType(Wrap));
  expect(wraps, findsOneWidget);
  expect(tester.widget<Wrap>(wraps).children, hasLength(count));
  expect(
    find.descendant(of: row, matching: find.byType(SingleChildScrollView)),
    findsNothing,
  );
}

void _expectOneLine(WidgetTester tester, Finder row) {
  final buttons = _buttons(row);
  final center = tester.getCenter(buttons.first).dy;
  for (final element in buttons.evaluate()) {
    expect(
      tester.getCenter(find.byWidget(element.widget)).dy,
      closeTo(center, 0.01),
    );
  }
}

void _expectInside(WidgetTester tester, Finder scope) {
  final bounds = tester.getRect(scope);
  for (final element in _buttons(scope).evaluate()) {
    final rect = tester.getRect(find.byWidget(element.widget));
    expect(rect.left, greaterThanOrEqualTo(bounds.left - 0.01));
    expect(rect.right, lessThanOrEqualTo(bounds.right + 0.01));
    expect(rect.top, greaterThanOrEqualTo(bounds.top - 0.01));
    expect(rect.bottom, lessThanOrEqualTo(bounds.bottom + 0.01));
  }
}

ViewPB _folder({PageStyleCover? cover}) => ViewPB(
      id: 'page-action-row-root',
      name: 'Research',
      layout: ViewLayoutPB.Document,
      extra: cover == null
          ? const WorkspaceItemMetadata.folder().mergeIntoExtra('')
          : ViewCoverCodec.mergeCover(
              const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
              cover,
            ),
    );

WorkspaceExplorerController _controller(
  ViewPB view,
  WorkspaceItemRepository repository,
) =>
    WorkspaceExplorerController(
      root: view,
      repository: repository,
      listenForUpdates: false,
    );

class _Repository implements WorkspaceItemRepository {
  _Repository(this.root);
  final ViewPB root;
  int writes = 0;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async =>
      FlowyResult.success([]);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async =>
      FlowyResult.success([root]);

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId) async =>
      FlowyResult.success(root);

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAncestors(
    String viewId,
  ) async =>
      FlowyResult.success([root]);

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    writes++;
    return FlowyResult.failure(
      FlowyError(msg: 'No writes expected from layout.'),
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _PendingCoverBackend extends ViewCoverActionsBackend {
  final targets = <String>[];
  final pending = Completer<FlowyResult<void, FlowyError>>();

  @override
  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required PageStyleCover cover,
  }) {
    targets.add(view.id);
    return pending.future;
  }

  void complete() {
    if (!pending.isCompleted) pending.complete(FlowyResult.success(null));
  }
}

/// Only the native/backend collection content boundary is substituted. The
/// actual page, registry, graph, header and nested scroll ownership are retained.
class _Reading extends StatefulWidget {
  const _Reading();

  @override
  State<_Reading> createState() => _ReadingState();
}

class _ReadingState extends State<_Reading> {
  @override
  Widget build(BuildContext context) => ListView(
        controller: CollectionPageScrollScope.maybeOf(context),
        padding: const EdgeInsets.symmetric(horizontal: 24),
        children: const [
          SizedBox(
            key: _bodyEdge,
            height: 40,
            child: Text('Retained collection content'),
          ),
          SizedBox(height: 1600),
        ],
      );
}
