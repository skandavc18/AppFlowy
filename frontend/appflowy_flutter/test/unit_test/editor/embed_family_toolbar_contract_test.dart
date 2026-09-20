import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

// Supplementary wiring checks for hosts that need backend/native services.
// Interaction, semantics, focus and retained state are tested with real widgets
// in test/widget_test/embed_family_toolbar_test.dart, not inferred here.
void main() {
  const editor = 'lib/plugins/document/presentation/editor_plugins';

  for (final path in [
    '$editor/external/external_embed_block_component.dart',
    '$editor/folder_explorer/folder_explorer_block_component.dart',
    '$editor/canvas/canvas_block_component.dart',
    '$editor/math_equation/math_equation_block_component.dart',
    'lib/shared/charts/chart_stage.dart',
    'lib/shared/charts/chart_toolbar.dart',
    'lib/shared/charts/app_chart.dart',
    'lib/shared/maps/map_stage.dart',
    'lib/shared/maps/app_map_toolbar.dart',
    'lib/shared/slides/slide_stage.dart',
    'lib/shared/table_views/table_view_chrome.dart',
    'lib/shared/table_views/form_stage.dart',
    'lib/plugins/database/calendar/presentation/calendar_shell.dart',
    'lib/plugins/collection/views/bookmark/bookmark_reader.dart',
    'lib/extensions/dart/built_in/stock_extension.dart',
    'lib/extensions/dart/built_in/news_views.dart',
    'lib/extensions/dart/built_in/astrology/astrology_block.dart',
  ]) {
    test('$path adopts the shared toolbar instead of a second hide mechanism',
        () {
      final source = _read(path);
      expect(
        source,
        contains("import 'package:appflowy/shared/preview_toolbar.dart';"),
      );
      expect(source, contains('PreviewToolbar('));
    });
  }

  test('size-managed collection and direct page cards own a preview region',
      () {
    final collection = _read('$editor/collection_embed/collection_embed.dart');
    expect(collection, contains('return PreviewToolbarRegion(child: body)'));
    expect(collection, contains('if (!showHeading)'));
    expect(
      collection,
      isNot(contains('hovered || menuOpen || widget.fullscreen')),
    );
    expect(
      collection,
      contains('_showMenu(context, embed, details.globalPosition)'),
    );
    final page =
        _read('$editor/page_preview/page_preview_block_component.dart');
    final card = page.substring(page.indexOf('class _PagePreviewCardState'));
    expect(card, contains('return PreviewToolbarRegion('));
    expect(card, contains('child: PreviewToolbar('));
    expect(card, isNot(contains('ignoring: !hovered')));
  });

  test('a focused visual frame decorates rather than reparenting its body', () {
    final source = _read('$editor/visual_block/visual_block_frame.dart');
    expect(source, contains('foregroundDecoration: BoxDecoration('));
    expect(source, contains('node.hasPrimaryFocus'));
    expect(source, isNot(contains('if (_focused) {')));
    expect(source, isNot(contains('ignoring: !_controlsVisible')));
  });

  for (final path in [
    '$editor/link_preview/custom_link_preview_block_component.dart',
    '$editor/link_embed/link_embed_block_component.dart',
  ]) {
    test('$path retains the menu on desktop, touch and keyboard', () {
      final source = _read(path);
      expect(source, contains('child: PreviewToolbar('));
      expect(source, isNot(contains('if (showActions && UniversalPlatform')));
      expect(source, isNot(contains('if (!showActions || UniversalPlatform')));
    });
  }

  for (final path in [
    '$editor/link_preview/link_preview_menu.dart',
    '$editor/link_embed/link_embed_menu.dart',
    'lib/plugins/database/tab_bar/desktop/tab_bar_add_button.dart',
    'lib/plugins/database/widgets/setting/setting_button.dart',
    'lib/plugins/database/grid/presentation/widgets/toolbar/filter_button.dart',
    'lib/plugins/database/grid/presentation/widgets/toolbar/sort_button.dart',
  ]) {
    test('$path explicitly holds legacy programmatic popovers', () {
      final source = _read(path);
      expect(source, contains('PreviewToolbarRegion.hold(context)'));
      expect(source, contains('triggerActions: PopoverTriggerFlags.none'));
      expect(source, contains('onClose:'));
      expect(source, contains('void dispose()'));
    });
  }

  test('database action reveal excludes tab identity and the renderer', () {
    final header =
        _read('lib/plugins/database/tab_bar/desktop/tab_bar_header.dart');
    expect(header, contains('const Flexible(child: DatabaseTabBar())'));
    expect(header, contains('child: AddDatabaseViewButton('));
    expect(header, contains('PreviewToolbar('));
    final view = _read('lib/plugins/database/tab_bar/tab_bar_view.dart');
    expect(
      view,
      contains('tabBar.builder.settingBarExtension(context, controller)'),
    );
    expect(
      view,
      contains('keepVisible: extension is DatabaseViewSettingExtension'),
    );
    expect(view, contains('return Expanded(child: child)'));
    final dashboard =
        _read('lib/plugins/dashboard/presentation/widgets/data_widgets.dart');
    expect(dashboard, contains('child: PreviewToolbarRegion('));
    expect(dashboard, contains('child: DatabaseTabBarView('));
  });

  test('external recovery, form fields and submit/cancel are not toolbars', () {
    final external =
        _read('$editor/external/external_embed_block_component.dart');
    final failure = external.substring(external.indexOf('Widget _failure('));
    expect(failure, contains('ProviderStateView('));
    expect(failure, contains('onRetry:'));
    expect(failure, contains('onReconnect:'));
    expect(failure, isNot(contains('PreviewToolbar(')));
    final form = _read('lib/shared/table_views/form_stage.dart');
    final body = form.substring(form.indexOf('Widget _buildBody('));
    expect(body, isNot(contains('PreviewToolbar(')));
    expect(body, contains("ValueKey('form-submit')"));
    expect(
      form,
      contains('keepVisible: fields.isEmpty || _busy || _noticeIsError'),
    );
  });

  test(
      'bookmark full-window chrome is fixed and popup Close remains outside reveal',
      () {
    final source =
        _read('lib/plugins/collection/views/bookmark/bookmark_reader.dart');
    expect(source, contains('enabled: !widget.standalone'));
    final close =
        source.indexOf('tooltip: LocaleKeys.collections_bookmark_close');
    final headerEnd = source.indexOf('Widget _sourceToggle(');
    expect(close, greaterThan(0));
    expect(close, lessThan(headerEnd));
    expect(
      source,
      contains('keepVisible: widget.controller.isWorkingOn(entry.id)'),
    );
  });

  test('islands have no toolbar to hide and retain their native-view guards',
      () {
    final source =
        _read('lib/extensions/presentation/island_block_component.dart');
    expect(source, isNot(contains('PreviewToolbar(')));
    expect(source, contains('InAppWebView('));
    expect(source, contains('minimumSurface'));
    expect(source, contains('_routeSettled'));
    expect(source, contains('onPermissionRequest:'));
  });
}

String _read(String path) => File(path).readAsStringSync();
