import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_item.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

import '../slash_menu_metadata.dart';
import 'slash_menu_item_builder.dart';

/// The `/` menu on mobile: one group per desktop section, opening onto the
/// very same entries, so a phone offers every block a desktop does.
///
/// A section can be assembled from more than one list (extension islands
/// join the interactive blocks); they share one group, in first-seen order.
List<SelectionMenuItem> mobileSlashMenuGroups(
  List<SlashMenuSectionItems> sections,
) {
  final grouped = <SlashMenuSection, List<SelectionMenuItem>>{};
  for (final section in sections) {
    final items = grouped.putIfAbsent(section.section, () => []);
    for (final item in section.items) {
      if (!items.contains(item)) items.add(item);
    }
  }
  return [
    for (final MapEntry(key: section, value: items) in grouped.entries)
      if (items.isNotEmpty)
        MobileSelectionMenuItem(
          getName: () => slashMenuSectionLabel(section),
          handler: (_, __, ___) {},
          icon: (_, isSelected, style) => _sectionIcon(
            section,
            isSelected: isSelected,
            style: style,
          ),
          nameBuilder: slashMenuItemNameBuilder,
          children: items,
        ),
  ];
}

Widget _sectionIcon(
  SlashMenuSection section, {
  required bool isSelected,
  required SelectionMenuStyle style,
}) {
  final svg = switch (section) {
    SlashMenuSection.suggestions => FlowySvgs.ai_sparks_s,
    SlashMenuSection.basicBlocks => FlowySvgs.slash_menu_icon_text_s,
    SlashMenuSection.media => FlowySvgs.slash_menu_icon_file_s,
    SlashMenuSection.database => FlowySvgs.slash_menu_icon_grid_s,
    SlashMenuSection.advanced => FlowySvgs.drag_element_s,
    _ => null,
  };
  if (svg != null) {
    return SelectableSvgWidget(data: svg, isSelected: isSelected, style: style);
  }
  return SelectableIconWidget(
    icon: switch (section) {
      SlashMenuSection.interactive => Icons.touch_app_rounded,
      SlashMenuSection.canvas => Icons.dashboard_customize_rounded,
      SlashMenuSection.dashboards => Icons.dashboard_rounded,
      SlashMenuSection.widgets => Icons.widgets_rounded,
      SlashMenuSection.diagrams => Icons.schema_rounded,
      SlashMenuSection.collections => Icons.collections_bookmark_rounded,
      _ => Icons.add_box_rounded,
    },
    isSelected: isSelected,
    style: style,
  );
}
