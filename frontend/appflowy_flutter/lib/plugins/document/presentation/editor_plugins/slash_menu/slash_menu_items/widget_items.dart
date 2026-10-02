import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/dashboard_widget/dashboard_widget_block_component.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';

import 'slash_menu_item_builder.dart';

/// The dashboard widgets a page can hold, each as a `/` entry.
///
/// Read from the registry every time the menu opens, so a widget registered
/// tomorrow — built in, or added by an extension — is in `/` with nothing
/// else to change. A widget whose page twin already exists (its `pageBlock`)
/// is left to that block's own entry rather than offered twice.
List<SelectionMenuItem> dashboardWidgetSlashMenuItems() => [
      for (final definition in dashboardWidgetsForPages())
        _widgetItem(definition),
    ];

/// The widgets a page hosts as themselves.
List<DashboardWidgetDefinition> dashboardWidgetsForPages() => [
      for (final definition in DashboardWidgetRegistry.offered())
        if (definition.pageBlock == null) definition,
    ];

/// What each widget entry is for, from the widget's own description.
Map<SelectionMenuItem, String> dashboardWidgetSlashMenuDescriptions(
  List<SelectionMenuItem> items,
) {
  final definitions = dashboardWidgetsForPages();
  return {
    for (var index = 0;
        index < items.length && index < definitions.length;
        index++)
      items[index]: definitions[index].description?.call() ??
          LocaleKeys.dashboard_slash_widgetDescription.tr(),
  };
}

SelectionMenuItem _widgetItem(DashboardWidgetDefinition definition) =>
    SelectionMenuItem.node(
      getName: definition.label,
      keywords: [
        definition.type,
        if (definition.slashName != null) definition.slashName!.toLowerCase(),
        ...definition.keywords,
        'widget',
        'dashboard',
      ],
      nodeBuilder: (_, __) => dashboardWidgetNode(definition.create()),
      replace: (_, node) => node.delta?.isEmpty ?? false,
      nameBuilder: slashMenuItemNameBuilder,
      iconBuilder: (_, isSelected, style) => SelectableIconWidget(
        icon: definition.icon,
        isSelected: isSelected,
        style: style,
      ),
    );
