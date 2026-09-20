import 'dart:ui' as ui;

import 'package:appflowy/extensions/dart/built_in/news_extension.dart';
import 'package:appflowy/extensions/dart/built_in/news_views.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_chrome.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_sync_indicator.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/tab_bar_add_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/book_embed_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/link_embed_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/link_preview_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/math_equation/math_equation_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/page_preview/page_preview_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block_frame.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block_style.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/charts/app_chart.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/shared/charts/chart_toolbar.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/maps/app_map_toolbar.dart';
import 'package:appflowy/shared/maps/app_map_view.dart';
import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/slides/slide_deck.dart';
import 'package:appflowy/shared/slides/slide_stage.dart';
import 'package:appflowy/shared/table_views/form_stage.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/charts/chart_source.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/slides/slide_source.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _appearances = ['light', 'dark', 'paper'];
const _frame = ValueKey('family-preview-frame');
const _outside = ValueKey('outside-preview');
const _visualAction = ValueKey('visual-action');
const _settle = Duration(milliseconds: 141);
const _table = ChartTable(
  columns: ['Team', 'Amount'],
  columnIds: ['team', 'amount'],
  rows: [
    ['North', '2'],
    ['South', '6'],
  ],
);

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final appearance in _appearances) {
    for (final kind in <CollectionKind?>[null, ...CollectionKind.values]) {
      testWidgets(
          '$appearance: ${kind?.name ?? 'plain folder'} dashboard '
          'preview retains one toolbar through hover and menu', (tester) async {
        final items = _Items();
        final controller = CollectionEmbedController(
          collection: _collection(kind),
          repository: items,
          listenForUpdates: false,
        );
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        try {
          await _mount(
            tester,
            appearance,
            CollectionEmbed(
              collection: controller.collection,
              controller: controller,
              // This is the dashboard's size-managed path, NOT a full page.
              fullscreen: true,
              settings: CollectionEmbedSettings(
                style:
                    kind == CollectionKind.book ? BookEmbedStyles.shelf : null,
              ),
              onSettingsChanged: (_) {},
            ),
          );
          final trigger = find.byType(AppMenuIconButton);
          expect(trigger, findsOneWidget);
          final toolbar = _toolbarFor(trigger);
          final element = tester.element(trigger);
          final frameRect = tester.getRect(find.byKey(_frame));
          _expectToolbar(tester, toolbar, visible: false);
          expect(trigger.hitTestable(), findsNothing);
          expect(items.reads, 1);

          await mouse.addPointer(location: const Offset(2, 2));
          await mouse.moveTo(frameRect.center);
          await _settleToolbar(tester);
          _expectToolbar(tester, toolbar, visible: true);
          expect(tester.element(trigger), same(element));
          // Use the same pointer, and park it outside before laying out the
          // popup. A second mouse left over the body can open a submenu when
          // the menu appears beneath it.
          await mouse.moveTo(tester.getCenter(trigger));
          await mouse.down(tester.getCenter(trigger));
          await mouse.up();
          await mouse.moveTo(const Offset(2, 2));
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuScope), findsOneWidget);
          expect(find.byType(AppMenuSurface), findsOneWidget);
          _expectToolbar(tester, toolbar, visible: true);

          // A submenu is a second surface in the SAME popup, not a duplicate
          // root menu. Its focus/pointer must keep the originating tools held.
          final sizeMenu = find.byWidgetPredicate(
            (widget) =>
                widget is AppMenuRow &&
                widget.label == LocaleKeys.collections_embed_size.tr(),
          );
          await mouse.moveTo(tester.getCenter(sizeMenu));
          await tester.pump();
          await tester.pump(AppMenuMetrics.submenuOpenDelay);
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuScope), findsOneWidget);
          expect(find.byType(AppMenuSurface), findsNWidgets(2));
          _expectToolbar(tester, toolbar, visible: true);
          await mouse.moveTo(const Offset(2, 2));
          await _settleToolbar(tester);
          _expectToolbar(tester, toolbar, visible: true);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuSurface), findsOneWidget);
          _expectToolbar(tester, toolbar, visible: true);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuScope), findsNothing);
          _focusOutside(tester);
          await _settleToolbar(tester);
          _expectToolbar(tester, toolbar, visible: false);
          expect(tester.element(trigger), same(element));
          expect(tester.getRect(find.byKey(_frame)), frameRect);
          expect(
            items.reads,
            1,
            reason: 'Hover/menu must not refetch the body.',
          );
          _expectAppearance(tester, appearance, trigger);
          expect(tester.takeException(), isNull);
        } finally {
          await mouse.removePointer();
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      });
    }

    for (final editable in [false, true]) {
      testWidgets(
          '$appearance: page card editable=$editable keeps identity '
          'and keyboard/menu access without a resizable host', (tester) async {
        var opened = 0;
        final cache = FolderGalleryPreviewCache(loader: _PageLoader());
        await _mount(
          tester,
          appearance,
          PagePreviewCard(
            view: ViewPB(id: 'page-preview-fixture', name: 'Project brief'),
            userProfile: null,
            previewCache: cache,
            onOpen: () => opened++,
            onChangePage: editable ? () {} : null,
            onPreviewModeChanged: editable ? (_) {} : null,
          ),
          width: 320,
        );
        final trigger = find.byKey(const ValueKey('page-preview-options'));
        final toolbar = _toolbarFor(trigger);
        _expectToolbar(tester, toolbar, visible: false);
        expect(find.text('Project brief'), findsOneWidget);
        expect(
          find.ancestor(
            of: find.text('Project brief'),
            matching: find.byType(PreviewToolbar),
          ),
          findsNothing,
        );
        await _tabTo(tester, trigger);
        _expectToolbar(tester, toolbar, visible: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        final rows = tester.widgetList<AppMenuRow>(find.byType(AppMenuRow));
        expect(rows.length, editable ? 3 : 1);
        await tester.tap(find.byType(AppMenuRow).first);
        await tester.pumpAndSettle();
        expect(opened, 1);
        _focusOutside(tester);
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: false);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets(
        '$appearance: visual frame focus, hover and menu never remount '
        'the renderer or expose hidden semantics', (tester) async {
      final semantics = tester.ensureSemantics();
      final width = ValueNotifier(620.0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      var activated = 0;
      var pressed = 0;
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, width, child) => Center(
              child: SizedBox(width: width, child: child),
            ),
            child: VisualBlockFrame(
              icon: Icons.account_tree_rounded,
              title: 'Diagram identity',
              onActivate: () => activated++,
              headerActions: [
                VisualBlockButton(
                  key: _visualAction,
                  icon: Icons.edit_rounded,
                  tooltip: 'Edit diagram',
                  onTap: () => pressed++,
                ),
              ],
              menuBuilder: (_) => [const AppMenuItem(label: 'Inspect diagram')],
              child: const _StatefulBody(),
            ),
          ),
        );
        final action = find.byKey(_visualAction);
        final toolbar = _toolbarFor(action);
        final renderer =
            tester.state<_StatefulBodyState>(find.byType(_StatefulBody));
        final controller = renderer.text;
        _expectToolbar(tester, toolbar, visible: false);
        await tester.enterText(find.byType(TextField), 'Unsaved draft');
        await tester.pump();
        await tester.pump();
        expect(tester.state(find.byType(_StatefulBody)), same(renderer));
        expect(renderer.text, same(controller));
        renderer.scroll.jumpTo(180);
        await tester.pump();
        // Body focus is not toolbar focus, and Enter must not activate the frame.
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(activated, 0);
        _expectToolbar(tester, toolbar, visible: false);

        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(tester.getCenter(find.byType(_StatefulBody)));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        expect(_paintedOpacity(tester, toolbar), inExclusiveRange(0, 1));
        await tester.pump(const Duration(milliseconds: 71));
        final button =
            find.descendant(of: action, matching: find.byType(IconButton));
        final node = tester.getSemantics(button);
        expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(
          node.getSemanticsData().hasAction(ui.SemanticsAction.tap),
          isTrue,
        );
        final visibleNodeId = node.id;
        await mouse.moveTo(const Offset(2, 2));
        await tester.pump();
        expect(button.hitTestable(), findsNothing);
        expect(_semanticsIds(tester), isNot(contains(visibleNodeId)));
        await tester.pump(_settle);
        _expectToolbar(tester, toolbar, visible: false);

        _focusOutside(tester);
        await _tabTo(tester, action);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(pressed, 1);
        expect(activated, 0);
        final more = find.byWidgetPredicate(
          (widget) =>
              widget is VisualBlockButton &&
              widget.icon == Icons.more_horiz_rounded,
        );
        await _tabTo(tester, more);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        _expectToolbar(tester, toolbar, visible: true);
        expect(tester.state(find.byType(_StatefulBody)), same(renderer));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        width.value = 260;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(_StatefulBody)), same(renderer));
        expect(renderer.text.text, 'Unsaved draft');
        expect(renderer.scroll.offset, 180);
        _expectToolbar(tester, toolbar, visible: true);
        _focusOutside(tester);
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: false);
        _expectAppearance(tester, appearance, action);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        width.dispose();
        semantics.dispose();
      }
    });

    testWidgets(
        '$appearance: chart menus pin the preview and preserve the '
        'actual chart while narrowing', (tester) async {
      var reads = 0;
      final source = ChartSource(
        viewId: 'chart-preview-fixture',
        loadTable: (_) async {
          reads++;
          return _table;
        },
      );
      final width = ValueNotifier(620.0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, width, child) => Center(
              child: SizedBox(width: width, child: child),
            ),
            child: PreviewToolbarRegion(
              child: ChartStage(
                viewId: source.viewId,
                source: source,
                title: 'Quarterly totals',
                spec: const ChartSpec(
                  categoryColumn: 'team',
                  valueColumns: ['amount'],
                  showControls: true,
                ),
                onSpecChanged: (_) {},
              ),
            ),
          ),
        );
        final chart = tester.state(find.byType(AppChart));
        final typeChip = find.byWidgetPredicate(
          (widget) =>
              widget is ChartChip &&
              widget.caption == LocaleKeys.charts_chartType.tr(),
        );
        expect(typeChip, findsOneWidget);
        final toolbar = _toolbarFor(typeChip);
        _expectToolbar(tester, toolbar, visible: false);
        expect(find.text('Quarterly totals'), findsOneWidget);
        await _tabTo(tester, typeChip);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await mouse.addPointer(location: const Offset(2, 2));
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: true);
        expect(tester.state(find.byType(AppChart)), same(chart));
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        _focusOutside(tester);
        width.value = 280;
        await tester.pumpAndSettle();
        _expectToolbar(tester, toolbar, visible: false);
        expect(tester.state(find.byType(AppChart)), same(chart));
        expect(reads, 1);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        width.dispose();
      }
    });

    testWidgets(
        '$appearance: table search draft and focus survive hover and '
        'narrow panes; leaving focus hides only idle actions', (tester) async {
      final width = ValueNotifier(620.0);
      final query = ValueNotifier(const TableQuery());
      final header = GlobalKey<TableViewHeaderState>();
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, width, child) => Center(
              child: SizedBox(width: width, child: child),
            ),
            child: PreviewToolbarRegion(
              child: Column(
                children: [
                  ValueListenableBuilder<TableQuery>(
                    valueListenable: query,
                    builder: (context, value, _) => TableViewHeader(
                      key: header,
                      palette: tableViewPaletteOf(context),
                      title: 'Reading list',
                      subtitle: '12 saved rows',
                      columns: [FieldPB(id: 'name', name: 'Name')],
                      query: value,
                      onQueryChanged: (value) => query.value = value,
                      valuesOf: (_) => ['One', 'Two'],
                      onAdd: () {},
                      optionsBuilder: () =>
                          [const AppMenuItem(label: 'Options')],
                    ),
                  ),
                  const Expanded(child: _StatefulBody(showField: false)),
                ],
              ),
            ),
          ),
        );
        final toolbar = find.byType(PreviewToolbar);
        _expectToolbar(tester, toolbar, visible: false);
        header.currentState!.openSearch();
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'retained search');
        await tester.pump();
        final field = tester.widget<TextField>(find.byType(TextField));
        final editable = tester.state(find.byType(EditableText));
        final selection = field.controller!.selection;
        for (final nextWidth in [280.0, 500.0, 320.0]) {
          width.value = nextWidth;
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(EditableText)), same(editable));
          expect(
            tester.widget<TextField>(find.byType(TextField)).controller,
            same(field.controller),
          );
          expect(field.controller!.text, 'retained search');
          expect(field.controller!.selection, selection);
          expect(field.focusNode!.hasFocus, isTrue);
          _expectToolbar(tester, toolbar, visible: true);
          expect(tester.takeException(), isNull);
        }
        header.currentState!.closeSearch();
        await tester.pumpAndSettle();
        _focusOutside(tester);
        await _settleToolbar(tester);
        expect(find.byType(TextField), findsNothing);
        expect(field.focusNode!.hasFocus, isFalse);
        expect(_focusedInside(find.byKey(_outside)), isTrue);
        expect(tester.widget<PreviewToolbar>(toolbar).keepVisible, isFalse);
        _expectToolbar(tester, toolbar, visible: false);
        expect(find.text('Reading list'), findsOneWidget);
        expect(query.value.search, isEmpty);
      } finally {
        await tester.pumpWidget(const SizedBox());
        width.dispose();
        query.dispose();
      }
    });

    testWidgets(
        '$appearance: actual map search retains its draft and camera; '
        'search focus does not reveal sibling zoom controls', (tester) async {
      final controller = AppMapController();
      final width = ValueNotifier(620.0);
      var tileRequests = 0;
      final client = MockClient((_) async {
        tileRequests++;
        return http.Response('', 204);
      });
      try {
        // Exercise the real map/camera without constructing a network client.
        await http.runWithClient(
          () => _mount(
            tester,
            appearance,
            ValueListenableBuilder<double>(
              valueListenable: width,
              builder: (_, width, child) => Center(
                child: SizedBox(width: width, child: child),
              ),
              child: PreviewToolbarRegion(
                child: AppMapView(
                  controller: controller,
                  initialCenter: const LatLng(20, 10),
                  initialZoom: 4,
                  autoFit: false,
                  showSearch: true,
                  onSearch: (_) async => null,
                ),
              ),
            ),
          ),
          () => client,
        );
        expect(tileRequests, greaterThan(0));
        final map = tester.state(find.byType(AppMapView));
        final camera = controller.camera!;
        final search = _toolbarFor(find.byType(TextField));
        final zoom = find.descendant(
          of: find.byType(AppMapToolbar),
          matching: find.byType(PreviewToolbar),
        );
        _expectToolbar(tester, search, visible: false);
        _expectToolbar(tester, zoom, visible: false);
        // Fewer than three characters never starts a geocoder request.
        await tester.enterText(find.byType(TextField), 'xy');
        await tester.pumpAndSettle();
        final field = tester.widget<TextField>(find.byType(TextField));
        final fieldState = tester.state(find.byType(EditableText));
        _expectToolbar(tester, search, visible: true);
        _expectToolbar(tester, zoom, visible: false);
        width.value = 280;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(AppMapView)), same(map));
        expect(tester.state(find.byType(EditableText)), same(fieldState));
        expect(field.controller!.text, 'xy');
        expect(controller.camera!.center, camera.center);
        expect(controller.camera!.zoom, camera.zoom);
        final searchRect = tester.getRect(find.byType(TextField));
        final zoomRect = tester.getRect(find.byType(AppMapToolbar));
        expect(searchRect.right, lessThan(zoomRect.left));
        _focusOutside(tester);
        await _settleToolbar(tester);
        _expectToolbar(tester, search, visible: false);
        expect(find.byType(MapAttribution), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
        width.dispose();
        client.close();
      }
    });

    testWidgets(
        '$appearance: real slide stage keeps its deck while actions '
        'hide and its search is resized', (tester) async {
      final source = SlideSource(viewId: '')
        ..readForTest(
          RepeatedRowTextPB(
            fieldIds: ['title'],
            rows: [
              RowTextPB(rowId: 'one', cells: ['First slide']),
              RowTextPB(rowId: 'two', cells: ['Second slide']),
            ],
          ),
          fields: [FieldPB(id: 'title', name: 'Title', isPrimary: true)],
        );
      final width = ValueNotifier(620.0);
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, width, child) => Center(
              child: SizedBox(width: width, child: child),
            ),
            child: PreviewToolbarRegion(
              child: SlideStage(
                viewId: '',
                source: source,
                title: 'Slide identity',
                spec: const SlideSpec(),
                onSpecChanged: (_) {},
              ),
            ),
          ),
        );
        final deck = tester.state(find.byType(SlideDeck));
        final searchButton = find.byWidgetPredicate(
          (widget) =>
              widget is SlideControlButton &&
              widget.icon == Icons.search_rounded,
        );
        final toolbar = find.byType(PreviewToolbar);
        _expectToolbar(tester, toolbar, visible: false);
        await _tabTo(tester, searchButton);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        await tester.enterText(find.byType(TextField), 'slide');
        await tester.pumpAndSettle();
        final field = tester.state(find.byType(EditableText));
        width.value = 320;
        await tester.pumpAndSettle();
        expect(tester.state(find.byType(SlideDeck)), same(deck));
        expect(tester.state(find.byType(EditableText)), same(field));
        expect(find.text('Slide identity'), findsOneWidget);
        expect(find.text('slide'), findsOneWidget);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox());
        source.dispose();
        width.dispose();
      }
    });

    testWidgets(
        '$appearance: a quiet dashboard calendar hides its controls '
        'without hiding the month or remounting it', (tester) async {
      final workspace = CalendarWorkspace(providers: []);
      final width = ValueNotifier(620.0);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          ValueListenableBuilder<double>(
            valueListenable: width,
            builder: (_, width, child) => Center(
              child: SizedBox(width: width, child: child),
            ),
            child: CalendarShell(
              workspace: workspace,
              delegate: CalendarViewDelegate(
                colorOf: (_) => Colors.green,
                canEdit: false,
              ),
              quiet: true,
            ),
          ),
          width: 620,
          height: 400,
        );
        final month = tester.state(find.byType(CalendarMonthView));
        final switcher = _toolbarFor(find.byType(CalendarViewSwitcher));
        _expectToolbar(tester, switcher, visible: false);
        expect(
          find.text(DateFormat.yMMMM().format(DateTime.now())),
          findsOneWidget,
        );
        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(tester.getCenter(find.byType(CalendarMonthView)));
        await _settleToolbar(tester);
        _expectToolbar(tester, switcher, visible: true);
        await mouse.moveTo(const Offset(2, 2));
        await _settleToolbar(tester);
        _expectToolbar(tester, switcher, visible: false);
        expect(tester.state(find.byType(CalendarMonthView)), same(month));
        for (final nextWidth in [280.0, 620.0]) {
          width.value = nextWidth;
          await tester.pumpAndSettle();
          expect(tester.state(find.byType(CalendarMonthView)), same(month));
          expect(
            find.text(DateFormat.yMMMM().format(DateTime.now())),
            findsOneWidget,
          );
          _expectToolbar(tester, switcher, visible: false);
          expect(tester.takeException(), isNull);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        workspace.dispose();
        width.dispose();
      }
    });

    testWidgets(
        '$appearance: news config hides on its direct dashboard host '
        'but headlines and error recovery remain visible', (tester) async {
      var configure = 0;
      await _mount(
        tester,
        appearance,
        NewsBody(
          channel: const NewsChannel(items: [NewsItem(title: 'Real headline')]),
          heading: 'News identity',
          count: 4,
          showSummary: true,
          onConfigure: () => configure++,
        ),
        width: 280,
      );
      final action = find.byType(IconButton);
      final toolbar = _toolbarFor(action);
      _expectToolbar(tester, toolbar, visible: false);
      expect(find.text('Real headline'), findsOneWidget);
      expect(find.text('News identity'), findsOneWidget);
      await _tabTo(tester, action);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      expect(configure, 1);
      await _mount(
        tester,
        appearance,
        NewsBody(
          channel: NewsChannel.failed('Offline fixture'),
          heading: 'News identity',
          count: 4,
          showSummary: true,
          onConfigure: () => configure++,
        ),
        width: 280,
      );
      expect(find.text('Offline fixture'), findsOneWidget);
      expect(find.text('Choose a feed').hitTestable(), findsOneWidget);
      expect(find.byType(PreviewToolbar), findsNothing);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$appearance: database add popover pins the preview after '
        'pointer leave and releases on dismissal', (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          appearance,
          PreviewToolbarRegion(
            child: Column(
              children: [
                PreviewToolbar(child: AddDatabaseViewButton(onTap: (_) {})),
                const Expanded(child: _StatefulBody(showField: false)),
              ],
            ),
          ),
        );
        final trigger = find.byType(AddDatabaseViewButton);
        final toolbar = _toolbarFor(trigger);
        _expectToolbar(tester, toolbar, visible: false);
        await _tabTo(tester, trigger);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(TabBarAddButtonAction), findsOneWidget);
        await mouse.addPointer(location: const Offset(2, 2));
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(TabBarAddButtonAction), findsNothing);
        _focusOutside(tester);
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: false);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  for (final editable in [false, true]) {
    testWidgets(
        'resized collection editable=$editable reveals at its exact '
        'frame, not the alignment margin, and right-click pins it',
        (tester) async {
      final controller = CollectionEmbedController(
        collection: _collection(CollectionKind.folder),
        repository: _Items(),
        listenForUpdates: false,
      );
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          'paper',
          CollectionEmbed(
            collection: controller.collection,
            controller: controller,
            width: 340,
            height: 240,
            editable: editable,
            settings: const CollectionEmbedSettings(),
            onSettingsChanged: (_) {},
          ),
        );
        expect(find.byType(ResizableMedia), findsOneWidget);
        final surface = find.byType(CollectionEmbedSurface);
        final inner = tester.getRect(surface);
        final outer = tester.getRect(find.byKey(_frame));
        final toolbar = _toolbarFor(find.byType(AppMenuIconButton));
        expect(inner.width, lessThan(outer.width));
        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(Offset(outer.left + 5, inner.center.dy));
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: false);
        await mouse.moveTo(inner.center);
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: true);
        final click = await tester.startGesture(
          inner.bottomRight - const Offset(20, 20),
          kind: PointerDeviceKind.mouse,
          buttons: kSecondaryMouseButton,
        );
        await click.up();
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await mouse.moveTo(const Offset(2, 2));
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        _focusOutside(tester);
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: false);
        // Hybrid Windows devices can reveal the same controls by touching it.
        await tester.tapAt(inner.topLeft + const Offset(14, 85));
        await _settleToolbar(tester);
        _expectToolbar(tester, toolbar, visible: true);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
        controller.dispose();
      }
    });
  }

  testWidgets(
      'cached chart failures retain the visible refresh action until '
      'recovery', (tester) async {
    var failing = false;
    final source = ChartSource(
      viewId: 'recovery-chart',
      loadTable: (_) async {
        if (failing) throw StateError('Synthetic chart failure');
        return _table;
      },
    );
    try {
      await _mount(
        tester,
        'paper',
        PreviewToolbarRegion(
          child: ChartStage(
            viewId: source.viewId,
            source: source,
            spec: const ChartSpec(),
            onSpecChanged: (_) {},
          ),
        ),
      );
      final refresh = find.byWidgetPredicate(
        (widget) =>
            widget is ChartIconAction && widget.icon == Icons.refresh_rounded,
      );
      final toolbar = _toolbarFor(refresh);
      _expectToolbar(tester, toolbar, visible: false);
      failing = true;
      await source.load();
      await tester.pumpAndSettle();
      expect(source.table, same(_table));
      _expectToolbar(tester, toolbar, visible: true);
      expect(refresh.hitTestable(), findsOneWidget);
      failing = false;
      await source.load();
      await tester.pumpAndSettle();
      _expectToolbar(tester, toolbar, visible: false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      source.dispose();
    }
  });

  testWidgets('collection failures keep their recovery menu visible',
      (tester) async {
    final items = _Items()..failing = true;
    final controller = CollectionEmbedController(
      collection: _collection(CollectionKind.folder),
      repository: items,
      listenForUpdates: false,
    );
    try {
      await _mount(
        tester,
        'paper',
        CollectionEmbed(
          collection: controller.collection,
          controller: controller,
          fullscreen: true,
          settings: const CollectionEmbedSettings(),
          onSettingsChanged: (_) {},
        ),
      );
      final toolbar = _toolbarFor(find.byType(AppMenuIconButton));
      _expectToolbar(tester, toolbar, visible: true);
      items.failing = false;
      await controller.refresh();
      await tester.pumpAndSettle();
      _expectToolbar(tester, toolbar, visible: false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
    }
  });

  testWidgets('calendar connection failures are visible without hover',
      (tester) async {
    final provider = _CalendarFailure();
    final workspace = CalendarWorkspace(providers: [provider]);
    try {
      await _mount(
        tester,
        'paper',
        PreviewToolbarRegion(
          child: CalendarShell(
            workspace: workspace,
            initialMode: CalendarViewMode.agenda,
            delegate: CalendarViewDelegate(
              colorOf: (_) => Colors.green,
              canEdit: false,
            ),
          ),
        ),
      );
      final toolbar = _toolbarFor(find.byType(CalendarSyncIndicator));
      _expectToolbar(tester, toolbar, visible: true);
      provider.recover();
      await tester.pumpAndSettle();
      _expectToolbar(tester, toolbar, visible: false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      workspace.dispose();
    }
  });

  testWidgets(
      'form header hides independently of a real field draft and '
      'retains empty-form setup actions', (tester) async {
    final source = TableRowSource(viewId: '')
      ..readForTest(
        RepeatedRowTextPB(fieldIds: ['title']),
        fields: [FieldPB(id: 'title', name: 'Name', isPrimary: true)],
      );
    final width = ValueNotifier(620.0);
    var writes = 0;
    try {
      await _mount(
        tester,
        'paper',
        ValueListenableBuilder<double>(
          valueListenable: width,
          builder: (_, width, child) =>
              Center(child: SizedBox(width: width, child: child)),
          child: PreviewToolbarRegion(
            child: FormStage(
              viewId: '',
              source: source,
              spec: const FormSpec(),
              onSpecChanged: (_) {
                writes++;
              },
            ),
          ),
        ),
      );
      final toolbar = find.byType(PreviewToolbar);
      _expectToolbar(tester, toolbar, visible: false);
      final draft = find.byKey(const ValueKey('form-draft-title'));
      await tester.enterText(draft, 'Not yet saved');
      await tester.pumpAndSettle();
      final field = tester.widget<TextField>(draft);
      final editable = tester.state(
        find.descendant(of: draft, matching: find.byType(EditableText)),
      );
      width.value = 280;
      await tester.pumpAndSettle();
      expect(
        tester.widget<TextField>(draft).controller,
        same(field.controller),
      );
      expect(
        tester.state(
          find.descendant(of: draft, matching: find.byType(EditableText)),
        ),
        same(editable),
      );
      expect(field.controller!.text, 'Not yet saved');
      _expectToolbar(tester, toolbar, visible: false);
      expect(find.byKey(const ValueKey('form-submit')), findsOneWidget);
      expect(writes, 0);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());

      source.readForTest(RepeatedRowTextPB());
      await _mount(
        tester,
        'paper',
        PreviewToolbarRegion(
          child: FormStage(
            viewId: '',
            source: source,
            spec: const FormSpec(),
            onSpecChanged: (_) {
              writes++;
            },
          ),
        ),
        width: 280,
      );
      _expectToolbar(tester, find.byType(PreviewToolbar), visible: true);
      expect(
        find.byKey(const ValueKey('form-add-field')).hitTestable(),
        findsOneWidget,
      );
      expect(writes, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      source.dispose();
      width.dispose();
    }
  });

  testWidgets(
      'chart zoom is keyboard accessible, preserves the chart and '
      'stays visible only while a nondefault viewport needs reset',
      (tester) async {
    await _mount(
      tester,
      'paper',
      PreviewToolbarRegion(
        child: Builder(
          builder: (context) => AppChart(
            data: buildChartData(_table, const ChartSpec()),
            spec: const ChartSpec(),
            palette: chartPaletteOf(context),
            animate: false,
          ),
        ),
      ),
    );
    final chart = tester.state(find.byType(AppChart));
    // IconButton owns focus outside its internal Tooltip subtree.
    final zoomIn = find.byWidgetPredicate(
      (widget) =>
          widget is IconButton &&
          widget.tooltip == LocaleKeys.canvas_zoom_zoomIn.tr(),
    );
    final toolbar = _toolbarFor(zoomIn);
    _expectToolbar(tester, toolbar, visible: false);
    await _tabTo(tester, zoomIn);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    _focusOutside(tester);
    await _settleToolbar(tester);
    _expectToolbar(tester, toolbar, visible: true);
    expect(tester.state(find.byType(AppChart)), same(chart));
    final reset = find.byTooltip(LocaleKeys.canvas_zoom_reset.tr());
    await _tabTo(tester, reset);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    _focusOutside(tester);
    await _settleToolbar(tester);
    _expectToolbar(tester, toolbar, visible: false);
    expect(tester.state(find.byType(AppChart)), same(chart));
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'visual segments and bookmark actions are native keyboard '
      'targets inside retained toolbar groups', (tester) async {
    var selected = '';
    var copied = 0;
    await _mount(
      tester,
      'paper',
      PreviewToolbarRegion(
        child: Builder(
          builder: (context) => Column(
            children: [
              PreviewToolbar(
                child: VisualBlockSegments<String>(
                  value: 'preview',
                  segments: const [
                    (
                      value: 'preview',
                      icon: Icons.visibility_rounded,
                      label: 'Preview'
                    ),
                    (
                      value: 'source',
                      icon: Icons.code_rounded,
                      label: 'Source'
                    ),
                  ],
                  onChanged: (value) => selected = value,
                ),
              ),
              PreviewToolbar(
                child: BookmarkAction(
                  theme: bookmarkThemeOf(context),
                  icon: Icons.copy_rounded,
                  tooltip: 'Copy bookmark',
                  onPressed: () => copied++,
                ),
              ),
              const Expanded(child: _StatefulBody(showField: false)),
            ],
          ),
        ),
      ),
      width: 280,
    );
    final source = find
        .ancestor(of: find.text('Source'), matching: find.byType(TextButton))
        .first;
    await _tabTo(tester, source);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(selected, 'source');
    await _tabTo(tester, find.byType(BookmarkAction));
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(copied, 1);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    for (final editable in [false, true]) {
      testWidgets(
          '$platform: collection actions remain available without '
          'hover, editable=$editable', (tester) async {
        final controller = CollectionEmbedController(
          collection: _collection(CollectionKind.folder),
          repository: _Items(),
          listenForUpdates: false,
        );
        try {
          await _mount(
            tester,
            'paper',
            CollectionEmbed(
              collection: controller.collection,
              controller: controller,
              fullscreen: true,
              editable: editable,
              settings: const CollectionEmbedSettings(),
              onSettingsChanged: (_) {},
            ),
            platform: platform,
            width: 320,
          );
          final trigger = find.byType(AppMenuIconButton);
          _expectToolbar(tester, _toolbarFor(trigger), visible: true);
          final entries = tester
              .widget<AppMenuIconButton>(trigger)
              .entries()
              .whereType<AppMenuItem>();
          expect(
            entries.any(
              (entry) =>
                  entry.label == LocaleKeys.collections_embed_rename.tr(),
            ),
            editable,
          );
          expect(
            entries.any(
              (entry) =>
                  entry.label == LocaleKeys.collections_embed_duplicate.tr(),
            ),
            editable,
          );
          await tester.tap(trigger);
          await tester.pumpAndSettle();
          expect(find.byType(AppMenuSurface), findsOneWidget);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          controller.dispose();
        }
      });
    }
  }

  for (final linkEmbed in [false, true]) {
    for (final editable in [false, true]) {
      testWidgets(
          'legacy ${linkEmbed ? 'embed' : 'link preview'} menu retains '
          'toolbar and balances editor focus, editable=$editable',
          (tester) async {
        final node = Node(
          type: 'link_preview',
          attributes: {'url': 'https://example.invalid'},
        );
        final editor =
            EditorState(document: Document(root: pageNode(children: [node])))
              ..disableSealTimer = true
              ..editable = editable;
        final before = keepEditorFocusNotifier.value;
        var reloads = 0;
        try {
          await _mount(
            tester,
            'paper',
            Provider<EditorState>.value(
              value: editor,
              child: PreviewToolbarRegion(
                child: Column(
                  children: [
                    PreviewToolbar(
                      child: linkEmbed
                          ? LinkEmbedMenu(
                              node: node,
                              editorState: editor,
                              onMenuShowed: () {},
                              onMenuHided: () {},
                              onReload: () => reloads++,
                            )
                          : CustomLinkPreviewMenu(
                              node: node,
                              onMenuShowed: () {},
                              onMenuHided: () {},
                              onReload: () => reloads++,
                            ),
                    ),
                    const Expanded(child: _StatefulBody(showField: false)),
                  ],
                ),
              ),
            ),
          );
          final toolbar = find.byType(PreviewToolbar);
          _expectToolbar(tester, toolbar, visible: false);
          final buttons = find.byType(FlowyIconButton);
          final trigger = linkEmbed && !editable ? buttons.first : buttons.last;
          await _tabTo(tester, trigger);
          _expectToolbar(tester, toolbar, visible: true);
          if (!linkEmbed || editable) {
            await tester.sendKeyEvent(LogicalKeyboardKey.enter);
            await tester.pumpAndSettle();
            expect(keepEditorFocusNotifier.value, before + 1);
            _expectToolbar(tester, toolbar, visible: true);
            await tester.tap(find.text(LinkPreviewMenuCommand.reload.title));
            await tester.pumpAndSettle();
            expect(reloads, 1);
            expect(keepEditorFocusNotifier.value, before);
          }
          _focusOutside(tester);
          await _settleToolbar(tester);
          _expectToolbar(tester, toolbar, visible: false);
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          editor.dispose();
        }
        expect(keepEditorFocusNotifier.value, before);
      });
    }
  }

  for (final accessible in [false, true]) {
    testWidgets(
        'visual and canvas actions obey reduced motion and accessible '
        'navigation=$accessible', (tester) async {
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await _mount(
          tester,
          'paper',
          PreviewToolbarRegion(
            child: Builder(
              builder: (context) => Column(
                children: [
                  CanvasToolbar(
                    palette: canvasPaletteOf(context),
                    tool: CanvasTool.select,
                    onToolChanged: (_) {},
                    onAdd: (_) {},
                    onMore: (_) {},
                  ),
                  Expanded(
                    child: VisualBlockFrame(
                      icon: Icons.draw_rounded,
                      title: 'Drawing',
                      headerActions: [
                        VisualBlockButton(
                          icon: Icons.edit_rounded,
                          tooltip: 'Edit drawing',
                          onTap: () {},
                        ),
                      ],
                      child: const _StatefulBody(showField: false),
                    ),
                  ),
                ],
              ),
            ),
          ),
          width: 280,
          accessibleNavigation: accessible,
          reducedMotion: true,
        );
        final bars = [
          for (var i = 0;
              i < find.byType(PreviewToolbar).evaluate().length;
              i++)
            find.byType(PreviewToolbar).at(i),
        ];
        expect(bars, hasLength(2));
        for (final bar in bars) {
          _expectToolbar(tester, bar, visible: accessible);
          expect(_opacityWidget(tester, bar).duration, Duration.zero);
        }
        await mouse.addPointer(location: const Offset(2, 2));
        await mouse.moveTo(tester.getCenter(find.byType(_StatefulBody)));
        await tester.pump();
        for (final bar in bars) {
          _expectToolbar(tester, bar, visible: true);
        }
        await mouse.moveTo(const Offset(2, 2));
        await tester.pump();
        for (final bar in bars) {
          _expectToolbar(tester, bar, visible: accessible);
        }
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets(
      'standalone chart/table/map/canvas controls stay visible without '
      'a preview region', (tester) async {
    await _mount(
      tester,
      'paper',
      Builder(
        builder: (context) => Column(
          children: [
            ChartToolbar(
              table: _table,
              spec: const ChartSpec(),
              palette: chartPaletteOf(context),
              onChanged: (_) {},
            ),
            TableViewHeader(
              palette: tableViewPaletteOf(context),
              title: 'Table',
              subtitle: '2 rows',
              columns: const [],
              query: const TableQuery(),
              onQueryChanged: (_) {},
              valuesOf: (_) => const [],
            ),
            CanvasToolbar(
              palette: canvasPaletteOf(context),
              tool: CanvasTool.select,
              onToolChanged: (_) {},
              onAdd: (_) {},
              onMore: (_) {},
            ),
            Expanded(
              child: Align(
                child: AppMapToolbar(
                  palette: mapPaletteOf(context),
                  onZoomIn: () {},
                  onZoomOut: () {},
                  onResetView: () {},
                ),
              ),
            ),
          ],
        ),
      ),
    );
    for (final element in find.byType(PreviewToolbar).evaluate()) {
      _expectToolbar(tester, find.byWidget(element.widget), visible: true);
    }
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets(
      'math read-only preview keeps identity, hides only options, and '
      'retains its equation through hover', (tester) async {
    final node = mathEquationNode(formula: 'x^2 + y^2');
    final editor =
        EditorState(document: Document(root: pageNode(children: [node])))
          ..disableSealTimer = true
          ..editable = false;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await _mount(
        tester,
        'paper',
        AppFlowyEditor(
          editorState: editor,
          editable: false,
          disableAutoScroll: true,
          disableKeyboardService: true,
          disableSelectionService: true,
          editorStyle: const EditorStyle.desktop(padding: EdgeInsets.all(16)),
          blockComponentBuilders: {
            ...standardBlockComponentBuilderMap,
            MathEquationBlockKeys.type: MathEquationBlockComponentBuilder(),
          },
          contextMenuItems: const [],
        ),
      );
      final equation = tester.element(find.byType(MathEquationView));
      final toolbar = find.byType(PreviewToolbar);
      _expectToolbar(tester, toolbar, visible: false);
      expect(find.text(LocaleKeys.diagrams_math_name.tr()), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsNothing);
      await mouse.addPointer(location: const Offset(2, 2));
      await mouse.moveTo(tester.getCenter(find.byType(MathEquationView)));
      await _settleToolbar(tester);
      _expectToolbar(tester, toolbar, visible: true);
      await mouse.moveTo(const Offset(2, 2));
      await _settleToolbar(tester);
      _expectToolbar(tester, toolbar, visible: false);
      expect(tester.element(find.byType(MathEquationView)), same(equation));
      expect(node.attributes[MathEquationBlockKeys.formula], 'x^2 + y^2');
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox());
      editor.dispose();
    }
  });
}

ViewPB _collection(CollectionKind? kind) => ViewPB(
      id: 'toolbar-fixture-${kind?.name ?? 'folder'}',
      name: 'Collection identity',
      extra: kind == null
          ? const WorkspaceItemMetadata.folder().mergeIntoExtra('')
          : CollectionMetadata.newExtra(kind),
    );

class _Items implements WorkspaceItemRepository {
  int reads = 0;
  bool failing = false;

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async {
    reads++;
    if (failing) {
      return FlowyResult.failure(
        FlowyError(msg: 'Synthetic collection failure'),
      );
    }
    return FlowyResult.success(const <ViewPB>[]);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _CalendarFailure extends CalendarProvider {
  bool failed = true;
  void recover() {
    failed = false;
    notifyListeners();
  }

  @override
  CalendarService get service => CalendarService.google;
  @override
  List<CalendarInfo> get calendars => const [];
  @override
  List<CalendarEvent> get events => const [];
  @override
  CalendarCapabilities get capabilities => CalendarCapabilities.readOnly;
  @override
  CalendarSyncStatus get status => CalendarSyncStatus(
        state: failed ? CalendarSyncState.expired : CalendarSyncState.idle,
      );
  @override
  Future<void> load(CalendarWindow window) async {}
  @override
  Future<void> refresh() async {}
}

class _PageLoader extends FolderGalleryPreviewLoader {
  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async =>
      const FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.document,
        blocks: [],
        wordCount: 0,
        readingMinutes: 0,
        tags: [],
        fileTypeLabel: 'PAGE',
      );
}

class _StatefulBody extends StatefulWidget {
  const _StatefulBody({this.showField = true});
  final bool showField;

  @override
  State<_StatefulBody> createState() => _StatefulBodyState();
}

class _StatefulBodyState extends State<_StatefulBody> {
  final text = TextEditingController();
  final scroll = ScrollController();

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Column(
        children: [
          if (widget.showField) TextField(controller: text),
          Expanded(
            child: ListView.builder(
              controller: scroll,
              itemCount: 40,
              itemExtent: 30,
              itemBuilder: (_, index) => Text('Content row $index'),
            ),
          ),
        ],
      );
}

Finder _toolbarFor(Finder child) =>
    find.ancestor(of: child, matching: find.byType(PreviewToolbar)).first;

Finder _opacity(Finder toolbar) =>
    find.descendant(of: toolbar, matching: find.byType(AnimatedOpacity)).first;

AnimatedOpacity _opacityWidget(WidgetTester tester, Finder toolbar) =>
    tester.widget<AnimatedOpacity>(_opacity(toolbar));

double _paintedOpacity(WidgetTester tester, Finder toolbar) =>
    tester.renderObject<RenderAnimatedOpacity>(_opacity(toolbar)).opacity.value;

void _expectToolbar(
  WidgetTester tester,
  Finder toolbar, {
  required bool visible,
}) {
  expect(toolbar, findsOneWidget);
  expect(
    _opacityWidget(tester, toolbar).opacity,
    visible ? 1 : 0,
    reason:
        'keepVisible=${tester.widget<PreviewToolbar>(toolbar).keepVisible}; '
        'focusedInside=${_focusedInside(toolbar)}; '
        'primaryFocus=${FocusManager.instance.primaryFocus}',
  );
  expect(_paintedOpacity(tester, toolbar), visible ? 1 : 0);
  expect(
    tester
        .widget<IgnorePointer>(
          find
              .descendant(of: toolbar, matching: find.byType(IgnorePointer))
              .first,
        )
        .ignoring,
    !visible,
  );
  expect(
    tester
        .widget<ExcludeSemantics>(
          find
              .descendant(of: toolbar, matching: find.byType(ExcludeSemantics))
              .first,
        )
        .excluding,
    !visible,
  );
}

Future<void> _settleToolbar(WidgetTester tester) async {
  // Focus notifications arrive after the first frame. Build that change at
  // time zero before advancing the opacity animation, rather than starting
  // the fade at the end of the duration we intended to measure.
  await tester.pump();
  await tester.pump();
  await tester.pump(_settle);
}

void _focusOutside(WidgetTester tester) {
  Focus.of(tester.element(find.text('Outside preview'))).requestFocus();
}

bool _focusedInside(Finder control) {
  final context = FocusManager.instance.primaryFocus?.context;
  if (context == null) return false;
  final target = control.evaluate().single;
  var found = identical(context, target);
  context.visitAncestorElements((element) {
    if (identical(element, target)) {
      found = true;
      return false;
    }
    return true;
  });
  return found;
}

Future<void> _tabTo(WidgetTester tester, Finder control) async {
  _focusOutside(tester);
  await tester.pump();
  await tester.pump();
  expect(_focusedInside(find.byKey(_outside)), isTrue);
  for (var index = 0; index < 40 && !_focusedInside(control); index++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    await tester.pump();
  }
  expect(
    _focusedInside(control),
    isTrue,
    reason: 'Hidden tools remain in the real Tab traversal.',
  );
  await tester.pump(_settle);
}

Set<int> _semanticsIds(WidgetTester tester) {
  final ids = <int>{};
  final root = tester
      .binding.renderViews.single.owner!.semanticsOwner!.rootSemanticsNode;
  void visit(SemanticsNode node) {
    ids.add(node.id);
    node.visitChildren((child) {
      visit(child);
      return true;
    });
  }

  if (root != null) visit(root);
  return ids;
}

void _expectAppearance(WidgetTester tester, String appearance, Finder child) {
  final context = tester.element(child);
  expect(PaperTheme.isEnabled(context), appearance == 'paper');
  expect(
    Theme.of(context).brightness,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
  );
  if (appearance == 'paper') {
    final palette = VisualBlockPalette.of(context);
    expect(palette.surface, PaperTheme.editorPreviewBackground);
    expect(palette.surface.r, greaterThan(palette.surface.b));
  }
}

Future<void> _mount(
  WidgetTester tester,
  String appearance,
  Widget child, {
  double width = 640,
  double height = 360,
  TargetPlatform platform = TargetPlatform.windows,
  bool accessibleNavigation = false,
  bool reducedMotion = false,
}) async {
  Widget app(Widget child) => _app(
        appearance,
        child,
        width: width,
        height: height,
        platform: platform,
        accessibleNavigation: accessibleNavigation,
        reducedMotion: reducedMotion,
      );
  await tester.pumpWidget(app(const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(app(child));
  await tester.pumpAndSettle();
}

Widget _app(
  String appearance,
  Widget child, {
  required double width,
  required double height,
  required TargetPlatform platform,
  required bool accessibleNavigation,
  required bool reducedMotion,
}) {
  final theme = DesktopAppearance()
      .getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        appearance == 'dark' ? Brightness.dark : Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      )
      .copyWith(platform: platform);
  final defaults = AppFlowyDefaultTheme();
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, navigator) => AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: appearance == 'dark' ? defaults.dark() : defaults.light(),
            palette: theme.extension<PremiumThemeExtension>()!,
            brightness: theme.brightness,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              accessibleNavigation: accessibleNavigation,
              disableAnimations: reducedMotion,
            ),
            child: TooltipVisibility(visible: false, child: navigator!),
          ),
        ),
        home: Scaffold(
          body: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              TextButton(
                key: _outside,
                onPressed: () {},
                child: const Text('Outside preview'),
              ),
              Center(
                child: SizedBox(
                  key: _frame,
                  width: width,
                  height: height,
                  child: child,
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
