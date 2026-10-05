import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_add_menu.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/page_block_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/dashboard_widget/dashboard_widget_block_component.dart';
import 'package:appflowy/plugins/document/presentation/embedded_blocks/page_block_catalog.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy_editor/appflowy_editor.dart' show EditorState;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// What a canvas can hold besides its own cards: every dashboard widget and
/// every block a page's `/` offers.
///
/// Both lists are read from their registries as a menu opens, so a widget or
/// a `/` entry added tomorrow — built in or by an extension — can be put on a
/// canvas with nothing here having to change.

/// A card holding [definition]'s widget — or, when [definition] is the
/// page-block carrier, a block card holding the blocks it was filled with.
///
/// The card's position is a placeholder; whoever puts it down places it.
CanvasNode canvasCardFor(DashboardWidgetDefinition definition) {
  if (definition.type == dashboardPageBlockType) {
    final document = definition.defaultSettings[dashboardPageBlockDocumentKey];
    final name = definition.defaultSettings[dashboardPageBlockNameKey];
    if (document is Map) {
      return canvasBlockCard(
        document: Map<String, Object?>.from(document),
        name: name is String ? name : '',
      );
    }
  }
  final spec = definition.create();
  return CanvasNode.create(
    kind: CanvasNodeKind.widget,
    position: Offset.zero,
    size: canvasWidgetCardSize(spec),
    data: {canvasWidgetSpecKey: spec.toJson()},
  );
}

/// A card holding blocks taken from a page's `/` menu.
CanvasNode canvasBlockCard({
  required Map<String, Object?> document,
  String name = '',
}) =>
    CanvasNode.create(
      kind: CanvasNodeKind.block,
      position: Offset.zero,
      data: {
        canvasBlockDocumentKey: document,
        if (name.isNotEmpty) canvasBlockNameKey: name,
      },
    );

/// The size a widget's card is first given: what the widget takes on a
/// dashboard, kept within what reads well as one card on a canvas.
Size canvasWidgetCardSize(DashboardWidgetSpec spec) {
  final dashboard = defaultDashboardWidgetBlockSize(spec);
  return Size(
    math.min(560, math.max(240, dashboard.width)),
    math.min(520, math.max(140, dashboard.height)),
  );
}

/// The "Widgets" and "From pages" rows of a canvas's Add menus.
///
/// [iconEditor] is handed to `/` icon builders, which expect an editor, and
/// [ink] colours those icons the way the menu colours its own.
List<AppMenuEntry> canvasWidgetAndBlockEntries({
  required EditorState iconEditor,
  required Color ink,
  required ValueChanged<DashboardWidgetDefinition> onWidget,
  required ValueChanged<PageBlockEntry> onBlock,
}) {
  final byGroup = <DashboardWidgetGroup, List<DashboardWidgetDefinition>>{};
  for (final definition in DashboardWidgetRegistry.offered()) {
    byGroup.putIfAbsent(definition.group, () => []).add(definition);
  }
  final blocks = pageBlockCatalog();
  return [
    if (byGroup.isNotEmpty)
      AppMenuItem(
        label: LocaleKeys.canvas_add_widgets.tr(),
        icon: Icons.widgets_rounded,
        submenu: [
          for (final group in DashboardWidgetGroup.values)
            if (byGroup[group]?.isNotEmpty ?? false)
              AppMenuItem(
                label: dashboardGroupLabel(group),
                icon: canvasWidgetGroupIcon(group),
                submenu: [
                  for (final definition in byGroup[group]!)
                    AppMenuItem(
                      label: definition.label(),
                      icon: definition.icon,
                      onSelected: () => onWidget(definition),
                    ),
                ],
              ),
        ],
      ),
    if (blocks.isNotEmpty)
      AppMenuItem(
        label: LocaleKeys.canvas_add_blocks.tr(),
        icon: Icons.dashboard_customize_rounded,
        submenu: [
          for (final entry in blocks)
            AppMenuItem(
              label: entry.name,
              iconWidget: entry.icon(iconEditor, ink),
              onSelected: () => onBlock(entry),
            ),
        ],
      ),
  ];
}

/// The glyph a group of widgets is filed under in a canvas's menus.
IconData canvasWidgetGroupIcon(DashboardWidgetGroup group) => switch (group) {
      DashboardWidgetGroup.text => Icons.text_fields_rounded,
      DashboardWidgetGroup.content => Icons.description_rounded,
      DashboardWidgetGroup.collections => Icons.auto_stories_rounded,
      DashboardWidgetGroup.data => Icons.bar_chart_rounded,
      DashboardWidgetGroup.money => Icons.payments_rounded,
      DashboardWidgetGroup.time => Icons.schedule_rounded,
      DashboardWidgetGroup.controls => Icons.tune_rounded,
      DashboardWidgetGroup.info => Icons.auto_awesome_rounded,
    };
