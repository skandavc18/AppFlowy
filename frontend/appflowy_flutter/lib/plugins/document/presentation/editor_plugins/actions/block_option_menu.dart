import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/actions/block_action_option_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/toolbar_item/text_suggestions_toolbar_item.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart' hide QuoteBlockKeys;
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';

/// The `⋮⋮` block menu, expressed as entries rather than a stack of popovers.
///
/// Turn into, colour, alignment and depth used to be popovers that only opened
/// on a click; here they are ordinary submenus, so they behave exactly like
/// every other nested menu in the application.
List<AppMenuEntry> buildBlockOptionMenu({
  required BuildContext context,
  required EditorState editorState,
  required Node node,
  required List<OptionAction> actions,
  required BlockActionOptionCubit cubit,
}) {
  final entries = <AppMenuEntry>[];

  for (final action in actions) {
    if (action == OptionAction.splitIntoColumns && node.isInColumnsBlock) {
      continue;
    }
    if (action == OptionAction.stackColumns && !node.isInColumnsBlock) {
      continue;
    }

    switch (action) {
      case OptionAction.divider:
        entries.add(const AppMenuSeparator());
      case OptionAction.turnInto:
        entries.add(
          AppMenuItem(
            label: LocaleKeys.document_plugins_optionAction_turnInto.tr(),
            icon: blockOptionIcon(action),
            submenu: _turnIntoEntries(editorState),
          ),
        );
      case OptionAction.color:
        entries.add(
          AppMenuItem(
            label: LocaleKeys.document_plugins_optionAction_color.tr(),
            icon: blockOptionIcon(action),
            submenu: _colorEntries(context, editorState, node),
          ),
        );
      case OptionAction.align:
        entries.add(
          AppMenuItem(
            label: LocaleKeys.document_plugins_optionAction_align.tr(),
            icon: blockOptionIcon(action),
            submenu: _alignEntries(editorState, node),
          ),
        );
      case OptionAction.depth:
        entries.add(
          AppMenuItem(
            label: LocaleKeys.document_plugins_optionAction_depth.tr(),
            icon: blockOptionIcon(action),
            submenu: _depthEntries(editorState, node),
          ),
        );
      default:
        entries.add(
          AppMenuItem(
            label: action.description,
            icon: blockOptionIcon(action),
            destructive: action == OptionAction.delete,
            onSelected: () => cubit.handleAction(action, node),
          ),
        );
    }
  }

  return entries;
}

/// One Material glyph per block action, so the block menu shares its icon
/// family with every other menu instead of the editor's private SVG set.
IconData blockOptionIcon(OptionAction action) => switch (action) {
      OptionAction.addAbove => Icons.vertical_align_top_rounded,
      OptionAction.addBelow => Icons.vertical_align_bottom_rounded,
      OptionAction.delete => Icons.delete_outline_rounded,
      OptionAction.cut => Icons.content_cut_rounded,
      OptionAction.copy => Icons.copy_rounded,
      OptionAction.paste => Icons.content_paste_rounded,
      OptionAction.duplicate => Icons.control_point_duplicate_rounded,
      OptionAction.turnInto => Icons.swap_horiz_rounded,
      OptionAction.moveUp => Icons.keyboard_arrow_up_rounded,
      OptionAction.moveDown => Icons.keyboard_arrow_down_rounded,
      OptionAction.splitIntoColumns => Icons.view_column_rounded,
      OptionAction.stackColumns => Icons.table_rows_rounded,
      OptionAction.copyLinkToBlock => Icons.link_rounded,
      OptionAction.color => Icons.palette_rounded,
      OptionAction.divider => Icons.horizontal_rule_rounded,
      OptionAction.align => Icons.format_align_left_rounded,
      OptionAction.depth => Icons.format_list_numbered_rounded,
      OptionAction.setToPageWidth => Icons.fit_screen_rounded,
      OptionAction.distributeColumnsEvenly => Icons.view_week_rounded,
      OptionAction.convertToSpreadsheet => Icons.grid_on_rounded,
    };

List<AppMenuEntry> _alignEntries(EditorState editorState, Node node) {
  final action = AlignOptionAction(editorState: editorState);
  final current = action.align;
  final canJustify = editorJustifiableBlockTypes.contains(node.type);
  return [
    for (final align in OptionAlignType.values)
      if (align != OptionAlignType.justify || canJustify)
        AppMenuItem(
          label: align.description,
          icon: switch (align) {
            OptionAlignType.left => Icons.format_align_left_rounded,
            OptionAlignType.center => Icons.format_align_center_rounded,
            OptionAlignType.right => Icons.format_align_right_rounded,
            OptionAlignType.justify => Icons.format_align_justify_rounded,
          },
          selected: align == current,
          onSelected: () => action.onAlignChanged(align),
        ),
  ];
}

List<AppMenuEntry> _depthEntries(EditorState editorState, Node node) {
  final action = DepthOptionAction(editorState: editorState);
  final current = action.depth(node);
  return [
    for (final depth in OptionDepthType.values)
      AppMenuItem(
        label: depth.description,
        selected: depth == current,
        onSelected: () => action.onDepthChanged(depth),
      ),
  ];
}

List<AppMenuEntry> _turnIntoEntries(EditorState editorState) {
  final selection = editorState.selection?.normalized;
  if (selection == null) {
    return const [];
  }
  final node = editorState.getNodeAtPath(selection.start.path);
  if (node == null) {
    return const [];
  }

  final unsupported = editorState.getNodesInSelection(selection).any(
      (n) => !EditorOptionActionType.turnInto.supportTypes.contains(n.type));
  if (unsupported) {
    return [_turnIntoItem(editorState, pateItem, null)];
  }

  final current = _currentSuggestionType(editorState, node);
  final matching = <SuggestionItem>[];
  final others = <SuggestionItem>[];
  for (final item in suggestions) {
    if (current != null &&
        item.type.group == current.group &&
        item.type != current) {
      matching.add(item);
    } else {
      others.add(item);
    }
  }

  return [
    if (matching.isNotEmpty) ...[
      AppMenuHeader(LocaleKeys.document_toolbar_suggestions.tr()),
      for (final item in matching) _turnIntoItem(editorState, item, current),
    ],
    AppMenuHeader(LocaleKeys.document_toolbar_turnInto.tr()),
    for (final item in others) _turnIntoItem(editorState, item, current),
  ];
}

AppMenuItem _turnIntoItem(
  EditorState editorState,
  SuggestionItem item,
  SuggestionType? current,
) =>
    AppMenuItem(
      label: item.title,
      iconWidget: _BlockGlyph(item.svg),
      selected: item.type == current,
      onSelected: () => item.onTap.call(editorState, false),
    );

SuggestionType? _currentSuggestionType(EditorState editorState, Node node) {
  if (node.type == HeadingBlockKeys.type) {
    return switch (node.attributes[HeadingBlockKeys.level] ?? 1) {
      1 => SuggestionType.h1,
      2 => SuggestionType.h2,
      3 => SuggestionType.h3,
      _ => null,
    };
  }
  if (node.type == ToggleListBlockKeys.type) {
    return switch (node.attributes[ToggleListBlockKeys.level]) {
      null => SuggestionType.toggle,
      1 => SuggestionType.toggleH1,
      2 => SuggestionType.toggleH2,
      3 => SuggestionType.toggleH3,
      _ => null,
    };
  }
  return nodeType2SuggestionType[node.type];
}

List<AppMenuEntry> _colorEntries(
  BuildContext context,
  EditorState editorState,
  Node node,
) {
  final selectedId =
      node.attributes[blockComponentBackgroundColor] as String? ??
          optionActionColorDefaultColor;
  final defaultColor = node.type == CalloutBlockKeys.type
      ? AFThemeExtension.of(context).calloutBGColor
      : Colors.transparent;

  Future<void> apply(String id) async {
    final transaction = editorState.transaction;
    final selection = editorState.selection;
    if (editorState.selectionType == SelectionType.block && selection != null) {
      for (final target in editorState.getNodesInSelection(
        selection.normalized,
      )) {
        transaction.updateNode(target, {blockComponentBackgroundColor: id});
      }
    } else {
      transaction.updateNode(node, {blockComponentBackgroundColor: id});
    }
    await editorState.apply(transaction);
  }

  return [
    AppMenuItem(
      label: LocaleKeys.document_plugins_optionAction_defaultColor.tr(),
      iconWidget: _Swatch(color: defaultColor),
      selected: selectedId == optionActionColorDefaultColor,
      onSelected: () => apply(optionActionColorDefaultColor),
    ),
    for (final tint in FlowyTint.values)
      AppMenuItem(
        label: tint.tintName(AppFlowyEditorL10n.current),
        iconWidget: _Swatch(color: tint.color(context)),
        selected: selectedId == tint.id,
        onSelected: () => apply(tint.id),
      ),
  ];
}

/// A block-type glyph, tinted so the editor's own icon set reads as part of
/// the menu rather than as artwork dropped into it.
class _BlockGlyph extends StatelessWidget {
  const _BlockGlyph(this.data);

  final FlowySvgData data;

  @override
  Widget build(BuildContext context) => FlowySvg(
        data,
        size: const Size.square(AppMenuMetrics.iconSize),
        color: AppMenuStyle.of(context).icon,
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = AppMenuStyle.of(context);
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: style.border, width: 0.8),
      ),
    );
  }
}
