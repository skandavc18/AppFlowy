import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_node_body.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_setup.dart';
import 'package:appflowy/plugins/canvas/presentation/canvas_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/canvas/canvas_controller.dart';
import 'package:appflowy/workspace/application/canvas/canvas_geometry.dart';
import 'package:appflowy/workspace/application/canvas/canvas_layout.dart';
import 'package:appflowy/workspace/application/canvas/canvas_model.dart';
import 'package:appflowy/workspace/application/canvas/canvas_templates.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Every menu the canvas offers.
///
/// The rows are built as plain data so what a menu offers can be checked
/// without opening one, and so the same rows can be reached from the toolbar
/// and from a right click.

/// What the canvas can do to whatever is selected. Shared by the card menu,
/// the frame menu and the toolbar's overflow.
List<AppMenuEntry> canvasArrangeEntries({
  required CanvasController controller,
  required VoidCallback onChanged,
}) {
  final count = controller.selection.length;
  void run(VoidCallback action) {
    action();
    onChanged();
  }

  return [
    AppMenuItem(
      label: LocaleKeys.canvas_align_title.tr(),
      icon: Icons.align_horizontal_left_rounded,
      enabled: count > 1,
      submenu: [
        AppMenuItem(
          label: LocaleKeys.canvas_align_left.tr(),
          icon: Icons.align_horizontal_left_rounded,
          onSelected: () =>
              run(() => controller.alignSelection(CanvasAlign.left)),
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_align_centerX.tr(),
          icon: Icons.align_horizontal_center_rounded,
          onSelected: () =>
              run(() => controller.alignSelection(CanvasAlign.centerX)),
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_align_right.tr(),
          icon: Icons.align_horizontal_right_rounded,
          onSelected: () =>
              run(() => controller.alignSelection(CanvasAlign.right)),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.canvas_align_top.tr(),
          icon: Icons.align_vertical_top_rounded,
          onSelected: () =>
              run(() => controller.alignSelection(CanvasAlign.top)),
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_align_centerY.tr(),
          icon: Icons.align_vertical_center_rounded,
          onSelected: () =>
              run(() => controller.alignSelection(CanvasAlign.centerY)),
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_align_bottom.tr(),
          icon: Icons.align_vertical_bottom_rounded,
          onSelected: () =>
              run(() => controller.alignSelection(CanvasAlign.bottom)),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.canvas_align_distributeHorizontally.tr(),
          icon: Icons.horizontal_distribute_rounded,
          enabled: count > 2,
          onSelected: () => run(
            () => controller.distributeSelection(CanvasAxis.horizontal),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_align_distributeVertically.tr(),
          icon: Icons.vertical_distribute_rounded,
          enabled: count > 2,
          onSelected: () =>
              run(() => controller.distributeSelection(CanvasAxis.vertical)),
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_align_spaceHorizontally.tr(),
          icon: Icons.swap_horiz_rounded,
          onSelected: () =>
              run(() => controller.spaceSelection(CanvasAxis.horizontal)),
        ),
        AppMenuItem(
          label: LocaleKeys.canvas_align_spaceVertically.tr(),
          icon: Icons.swap_vert_rounded,
          onSelected: () =>
              run(() => controller.spaceSelection(CanvasAxis.vertical)),
        ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_layout_title.tr(),
      icon: Icons.auto_awesome_mosaic_rounded,
      submenu: [
        for (final kind in CanvasLayoutKind.values)
          AppMenuItem(
            label: _layoutLabel(kind),
            icon: _layoutIcon(kind),
            onSelected: () => run(() => controller.autoLayout(kind)),
          ),
      ],
    ),
  ];
}

/// Right-clicking a card.
List<AppMenuEntry> canvasNodeMenuEntries({
  required CanvasController controller,
  required CanvasNode node,
  required VoidCallback onChanged,
  required VoidCallback onOpen,
  required VoidCallback onConvertToPage,
  required VoidCallback onSetUp,
  required void Function(CanvasNodeKind kind) onChangeType,
}) {
  final selection = controller.selection;
  final multiple = selection.length > 1;

  void run(VoidCallback action) {
    action();
    onChanged();
  }

  return [
    if (node.needsSetUp)
      AppMenuItem(
        label: switch (node.kind) {
          CanvasNodeKind.image => LocaleKeys.canvas_image_title.tr(),
          CanvasNodeKind.diagram => LocaleKeys.canvas_diagram_title.tr(),
          CanvasNodeKind.web ||
          CanvasNodeKind.bookmark =>
            LocaleKeys.canvas_card_addUrl.tr(),
          _ => LocaleKeys.canvas_card_chooseObject.tr(),
        },
        icon: canvasNodeIcon(node.kind),
        onSelected: onSetUp,
      ),
    if (node.diagramKind == CanvasDiagramKind.drawing)
      AppMenuItem(
        label: LocaleKeys.canvas_diagram_edit.tr(),
        icon: Icons.draw_rounded,
        onSelected: onOpen,
      ),
    if (node.kind == CanvasNodeKind.image && !node.needsSetUp)
      AppMenuItem(
        label: LocaleKeys.canvas_image_title.tr(),
        icon: Icons.image_rounded,
        onSelected: onSetUp,
      ),
    if ((node.kind == CanvasNodeKind.web ||
            node.kind == CanvasNodeKind.bookmark) &&
        !node.needsSetUp) ...[
      AppMenuItem(
        label: LocaleKeys.canvas_menu_open.tr(),
        icon: Icons.open_in_new_rounded,
        onSelected: onOpen,
      ),
      AppMenuItem(
        label: LocaleKeys.canvas_card_addUrl.tr(),
        icon: Icons.link_rounded,
        onSelected: onSetUp,
      ),
    ],
    if (node.kind.referencesWorkspaceObject && node.reference.isNotEmpty)
      AppMenuItem(
        label: LocaleKeys.canvas_menu_open.tr(),
        icon: Icons.arrow_outward_rounded,
        onSelected: onOpen,
      ),
    if (node.typesItsOwnText)
      AppMenuItem(
        label: node.kind == CanvasNodeKind.diagram
            ? LocaleKeys.canvas_diagram_editSource.tr()
            : LocaleKeys.canvas_menu_edit.tr(),
        icon: Icons.edit_rounded,
        onSelected: () => controller.beginEditing(node.id),
      ),
    if (node.kind == CanvasNodeKind.code)
      AppMenuItem(
        label: LocaleKeys.canvas_card_language.tr(),
        icon: Icons.code_rounded,
        submenu: [
          for (final language in canvasCodeLanguages)
            AppMenuItem(
              label: language,
              selected: (node.stringData(canvasCodeLanguageKey) ?? 'text') ==
                  language,
              onSelected: () => run(
                () => controller.updateNode(
                  node.id,
                  (current) =>
                      current.withData(canvasCodeLanguageKey, language),
                ),
              ),
            ),
        ],
      ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_duplicate.tr(),
      icon: Icons.content_copy_rounded,
      shortcut: 'Ctrl+D',
      onSelected: () => run(controller.duplicateSelection),
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_changeType.tr(),
      icon: Icons.swap_horiz_rounded,
      enabled: !multiple,
      submenu: [
        for (final kind in CanvasNodeKind.values)
          AppMenuItem(
            label: canvasNodeLabel(kind),
            icon: canvasNodeIcon(kind),
            selected: kind == node.kind,
            onSelected: () => onChangeType(kind),
          ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_colour.tr(),
      icon: Icons.palette_rounded,
      submenu: [
        AppMenuCustom(
          builder: (context) => CanvasSwatchRow(
            palette: canvasPaletteOf(
              context,
              theme: controller.settings.theme,
            ),
            selected: node.color,
            onPicked: (colour) {
              controller.colourSelection(colour);
              onChanged();
              AppMenuScope.maybeOf(context)?.close();
            },
          ),
        ),
      ],
    ),
    ...canvasArrangeEntries(controller: controller, onChanged: onChanged),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_group.tr(),
      icon: Icons.crop_free_rounded,
      enabled: multiple,
      shortcut: 'Ctrl+G',
      onSelected: () => run(() => controller.groupSelection()),
    ),
    if (node.frameId != null)
      AppMenuItem(
        label: LocaleKeys.canvas_menu_removeFromFrame.tr(),
        icon: Icons.output_rounded,
        onSelected: () => run(controller.ungroupSelection),
      ),
    if (node.kind == CanvasNodeKind.text && !multiple)
      AppMenuItem(
        label: LocaleKeys.canvas_menu_convertToPage.tr(),
        icon: Icons.description_rounded,
        onSelected: onConvertToPage,
      ),
    AppMenuItem(
      label: node.locked
          ? LocaleKeys.canvas_menu_unlock.tr()
          : LocaleKeys.canvas_menu_lock.tr(),
      icon: node.locked ? Icons.lock_open_rounded : Icons.lock_rounded,
      onSelected: () => run(
        () => controller.updateNode(
          node.id,
          (current) => current.copyWith(locked: !current.locked),
        ),
      ),
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_delete.tr(),
      icon: Icons.delete_outline_rounded,
      destructive: true,
      shortcut: 'Del',
      onSelected: () => run(controller.deleteSelection),
    ),
  ];
}

/// Right-clicking a frame.
List<AppMenuEntry> canvasFrameMenuEntries({
  required CanvasController controller,
  required CanvasFrame frame,
  required VoidCallback onChanged,
  required VoidCallback onConvertToPage,
}) {
  void run(VoidCallback action) {
    action();
    onChanged();
  }

  return [
    AppMenuItem(
      label: LocaleKeys.canvas_frame_selectContents.tr(),
      icon: Icons.select_all_rounded,
      onSelected: () => controller.selectInsideFrame(frame.id),
    ),
    AppMenuItem(
      label: frame.collapsed
          ? LocaleKeys.canvas_frame_expand.tr()
          : LocaleKeys.canvas_frame_collapse.tr(),
      icon: frame.collapsed
          ? Icons.unfold_more_rounded
          : Icons.unfold_less_rounded,
      onSelected: () => run(
        () => controller.updateFrame(
          frame.id,
          (current) => current.copyWith(collapsed: !current.collapsed),
        ),
      ),
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_duplicate.tr(),
      icon: Icons.content_copy_rounded,
      onSelected: () => run(controller.duplicateSelection),
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_colour.tr(),
      icon: Icons.palette_rounded,
      submenu: [
        AppMenuCustom(
          builder: (context) => CanvasSwatchRow(
            palette: canvasPaletteOf(
              context,
              theme: controller.settings.theme,
            ),
            selected: frame.color,
            onPicked: (colour) {
              controller.colourSelection(colour);
              onChanged();
              AppMenuScope.maybeOf(context)?.close();
            },
          ),
        ),
      ],
    ),
    ...canvasArrangeEntries(controller: controller, onChanged: onChanged),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_convertToPage.tr(),
      icon: Icons.description_rounded,
      onSelected: onConvertToPage,
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_ungroup.tr(),
      icon: Icons.output_rounded,
      onSelected: () => run(controller.ungroupSelection),
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_delete.tr(),
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onSelected: () => run(controller.deleteSelection),
    ),
  ];
}

/// Right-clicking a connection.
List<AppMenuEntry> canvasEdgeMenuEntries({
  required CanvasController controller,
  required CanvasEdge edge,
  required VoidCallback onChanged,
  required VoidCallback onEditLabel,
}) {
  void run(VoidCallback action) {
    action();
    onChanged();
  }

  return [
    AppMenuItem(
      label: LocaleKeys.canvas_menu_editLabel.tr(),
      icon: Icons.label_outline_rounded,
      onSelected: onEditLabel,
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_changeStyle.tr(),
      icon: Icons.line_style_rounded,
      submenu: [
        for (final style in CanvasEdgeStyle.values)
          AppMenuItem(
            label: _edgeStyleLabel(style),
            selected: edge.style == style,
            onSelected: () => run(
              () => controller.updateEdge(
                edge.id,
                (current) => current.copyWith(style: style),
              ),
            ),
          ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_edge_endMarker.tr(),
      icon: Icons.arrow_right_alt_rounded,
      submenu: [
        for (final marker in CanvasEdgeMarker.values)
          AppMenuItem(
            label: _markerLabel(marker),
            selected: edge.endMarker == marker,
            onSelected: () => run(
              () => controller.updateEdge(
                edge.id,
                (current) => current.copyWith(endMarker: marker),
              ),
            ),
          ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_edge_startMarker.tr(),
      icon: Icons.keyboard_backspace_rounded,
      submenu: [
        for (final marker in CanvasEdgeMarker.values)
          AppMenuItem(
            label: _markerLabel(marker),
            selected: edge.startMarker == marker,
            onSelected: () => run(
              () => controller.updateEdge(
                edge.id,
                (current) => current.copyWith(startMarker: marker),
              ),
            ),
          ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_colour.tr(),
      icon: Icons.palette_rounded,
      submenu: [
        AppMenuCustom(
          builder: (context) => CanvasSwatchRow(
            palette: canvasPaletteOf(
              context,
              theme: controller.settings.theme,
            ),
            selected: edge.color,
            onPicked: (colour) {
              controller.updateEdge(
                edge.id,
                (current) => current.copyWith(color: colour),
              );
              onChanged();
              AppMenuScope.maybeOf(context)?.close();
            },
          ),
        ),
      ],
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_delete.tr(),
      icon: Icons.delete_outline_rounded,
      destructive: true,
      onSelected: () => run(() => controller.deleteEdge(edge.id)),
    ),
  ];
}

/// Right-clicking the canvas itself.
List<AppMenuEntry> canvasBackgroundMenuEntries({
  required CanvasController controller,
  required VoidCallback onChanged,
  required void Function(CanvasNodeKind kind) onAdd,
  required VoidCallback onAddFrame,
  required VoidCallback onPaste,
  required VoidCallback onZoomToFit,
  required VoidCallback onTemplates,
}) {
  return [
    AppMenuItem(
      label: LocaleKeys.canvas_add_text.tr(),
      icon: canvasNodeIcon(CanvasNodeKind.text),
      onSelected: () => onAdd(CanvasNodeKind.text),
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_toolbar_add.tr(),
      icon: Icons.add_rounded,
      submenu: [
        for (final kind in CanvasNodeKind.values)
          if (kind != CanvasNodeKind.text)
            AppMenuItem(
              label: canvasNodeLabel(kind),
              icon: canvasNodeIcon(kind),
              onSelected: () => onAdd(kind),
            ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_newFrame.tr(),
      icon: Icons.crop_free_rounded,
      onSelected: onAddFrame,
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_paste.tr(),
      icon: Icons.content_paste_rounded,
      shortcut: 'Ctrl+V',
      onSelected: onPaste,
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_menu_selectAll.tr(),
      icon: Icons.select_all_rounded,
      shortcut: 'Ctrl+A',
      onSelected: () {
        controller.selectAll();
        onChanged();
      },
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_zoom_fit.tr(),
      icon: Icons.fit_screen_rounded,
      onSelected: onZoomToFit,
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_templates_title.tr(),
      icon: Icons.auto_awesome_rounded,
      onSelected: onTemplates,
    ),
  ];
}

/// The canvas's own settings, offered from the toolbar's overflow.
List<AppMenuEntry> canvasSettingsEntries({
  required CanvasController controller,
  required VoidCallback onChanged,
  required VoidCallback onExport,
  required VoidCallback onTemplates,
  VoidCallback? onOpenStandalone,
}) {
  final settings = controller.settings;
  void write(CanvasSettings Function(CanvasSettings settings) change) {
    controller.updateSettings(change);
    onChanged();
  }

  return [
    AppMenuItem(
      label: LocaleKeys.canvas_background_title.tr(),
      icon: Icons.grid_4x4_rounded,
      submenu: [
        for (final background in CanvasBackground.values)
          AppMenuItem(
            label: _backgroundLabel(background),
            selected: settings.background == background,
            onSelected: () =>
                write((current) => current.copyWith(background: background)),
          ),
        const AppMenuSeparator(),
        AppMenuHeader(LocaleKeys.canvas_background_spacing.tr()),
        for (final spacing in const [16.0, 24.0, 32.0, 48.0])
          AppMenuItem(
            label: '${spacing.round()}',
            selected: settings.gridSize == spacing,
            onSelected: () =>
                write((current) => current.copyWith(gridSize: spacing)),
          ),
      ],
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_theme_title.tr(),
      icon: Icons.palette_outlined,
      submenu: [
        for (final theme in CanvasTheme.values)
          AppMenuItem(
            label: _themeLabel(theme),
            selected: settings.theme == theme,
            onSelected: () =>
                write((current) => current.copyWith(theme: theme)),
          ),
      ],
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_settings_snapToGrid.tr(),
      icon: Icons.grid_on_rounded,
      selected: settings.snapToGrid,
      closeOnSelect: false,
      onSelected: () =>
          write((current) => current.copyWith(snapToGrid: !current.snapToGrid)),
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_settings_snapToObjects.tr(),
      icon: Icons.straighten_rounded,
      selected: settings.snapToObjects,
      closeOnSelect: false,
      onSelected: () => write(
        (current) => current.copyWith(snapToObjects: !current.snapToObjects),
      ),
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: settings.showMinimap
          ? LocaleKeys.canvas_minimap_hide.tr()
          : LocaleKeys.canvas_minimap_show.tr(),
      icon: Icons.map_rounded,
      onSelected: () => write(
        (current) => current.copyWith(showMinimap: !current.showMinimap),
      ),
    ),
    AppMenuItem(
      label: settings.showOutline
          ? LocaleKeys.canvas_outline_hide.tr()
          : LocaleKeys.canvas_outline_show.tr(),
      icon: Icons.list_rounded,
      onSelected: () => write(
        (current) => current.copyWith(showOutline: !current.showOutline),
      ),
    ),
    const AppMenuSeparator(),
    AppMenuItem(
      label: LocaleKeys.canvas_templates_title.tr(),
      icon: Icons.auto_awesome_rounded,
      onSelected: onTemplates,
    ),
    AppMenuItem(
      label: LocaleKeys.canvas_export_title.tr(),
      icon: Icons.ios_share_rounded,
      onSelected: onExport,
    ),
    if (onOpenStandalone != null)
      AppMenuItem(
        label: LocaleKeys.canvas_openStandalone.tr(),
        icon: Icons.open_in_full_rounded,
        onSelected: onOpenStandalone,
      ),
  ];
}

/// The templates, offered as a menu rather than as a gallery: a template only
/// puts objects down, so choosing one should cost one click.
List<AppMenuEntry> canvasTemplateEntries({
  required void Function(CanvasTemplate template) onChosen,
}) =>
    [
      AppMenuHeader(LocaleKeys.canvas_templates_title.tr()),
      for (final template in canvasTemplates())
        AppMenuItem(
          label: template.nameKey.tr(),
          subtitle: template.descriptionKey.tr(),
          icon: Icons.auto_awesome_mosaic_rounded,
          onSelected: () => onChosen(template),
        ),
    ];

String _layoutLabel(CanvasLayoutKind kind) => switch (kind) {
      CanvasLayoutKind.flow => LocaleKeys.canvas_layout_flow.tr(),
      CanvasLayoutKind.tree => LocaleKeys.canvas_layout_tree.tr(),
      CanvasLayoutKind.mindMap => LocaleKeys.canvas_layout_mindMap.tr(),
      CanvasLayoutKind.grid => LocaleKeys.canvas_layout_grid.tr(),
    };

IconData _layoutIcon(CanvasLayoutKind kind) => switch (kind) {
      CanvasLayoutKind.flow => Icons.arrow_right_alt_rounded,
      CanvasLayoutKind.tree => Icons.account_tree_rounded,
      CanvasLayoutKind.mindMap => Icons.hub_rounded,
      CanvasLayoutKind.grid => Icons.grid_view_rounded,
    };

String _edgeStyleLabel(CanvasEdgeStyle style) => switch (style) {
      CanvasEdgeStyle.solid => LocaleKeys.canvas_edge_solid.tr(),
      CanvasEdgeStyle.dashed => LocaleKeys.canvas_edge_dashed.tr(),
      CanvasEdgeStyle.dotted => LocaleKeys.canvas_edge_dotted.tr(),
    };

String _markerLabel(CanvasEdgeMarker marker) => switch (marker) {
      CanvasEdgeMarker.none => LocaleKeys.canvas_edge_none.tr(),
      CanvasEdgeMarker.arrow => LocaleKeys.canvas_edge_arrow.tr(),
      CanvasEdgeMarker.dot => LocaleKeys.canvas_edge_dot.tr(),
    };

String _backgroundLabel(CanvasBackground background) => switch (background) {
      CanvasBackground.blank => LocaleKeys.canvas_background_blank.tr(),
      CanvasBackground.dots => LocaleKeys.canvas_background_dots.tr(),
      CanvasBackground.grid => LocaleKeys.canvas_background_grid.tr(),
      CanvasBackground.lines => LocaleKeys.canvas_background_lines.tr(),
    };

String _themeLabel(CanvasTheme theme) => switch (theme) {
      CanvasTheme.auto => LocaleKeys.canvas_theme_auto.tr(),
      CanvasTheme.paper => LocaleKeys.canvas_theme_paper.tr(),
      CanvasTheme.dark => LocaleKeys.canvas_theme_dark.tr(),
      CanvasTheme.blueprint => LocaleKeys.canvas_theme_blueprint.tr(),
      CanvasTheme.minimal => LocaleKeys.canvas_theme_minimal.tr(),
    };
