import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'spreadsheet_controller.dart';
import 'spreadsheet_model.dart';
import 'spreadsheet_theme.dart';

/// One row in a spreadsheet popup menu.
class SpreadsheetMenuEntry {
  const SpreadsheetMenuEntry({
    required this.label,
    required this.onSelected,
    this.icon,
    this.enabled = true,
    this.selected = false,
    this.destructive = false,
    this.trailing,
  });

  const SpreadsheetMenuEntry.divider()
      : label = '',
        onSelected = null,
        icon = null,
        enabled = false,
        selected = false,
        destructive = false,
        trailing = null;

  final String label;
  final IconData? icon;
  final VoidCallback? onSelected;
  final bool enabled;
  final bool selected;
  final bool destructive;
  final String? trailing;

  bool get isDivider => onSelected == null && label.isEmpty;
}

abstract final class SpreadsheetMenuStyle {
  static const double width = 232;
  static const double radius = 12;
  static const double rowHeight = 30;
  static const EdgeInsets padding = EdgeInsets.symmetric(vertical: 5);
}

/// Shows a menu anchored at [position] in global coordinates.
///
/// [alignRight] treats the anchor as the menu's right edge, which is what a
/// control sitting at the right of a header needs.
Future<void> showSpreadsheetMenu({
  required BuildContext context,
  required Offset position,
  required List<SpreadsheetMenuEntry> entries,
  double width = SpreadsheetMenuStyle.width,
  bool alignRight = false,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(
    from: context,
    to: navigator.context,
  );
  return navigator.push(
    _SpreadsheetMenuRoute<void>(
      position: alignRight ? position.translate(-width, 0) : position,
      entries: entries,
      width: width,
      capturedThemes: themes,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

/// Shows an arbitrary panel (colour grids, format controls) with the same
/// chrome, placement and motion as the menus.
Future<T?> showSpreadsheetPanel<T>({
  required BuildContext context,
  required Offset position,
  required WidgetBuilder builder,
  double width = 260,
}) {
  final navigator = Navigator.of(context, rootNavigator: true);
  final themes = InheritedTheme.capture(from: context, to: navigator.context);
  return navigator.push<T>(
    _SpreadsheetMenuRoute<T>(
      position: position,
      width: width,
      capturedThemes: themes,
      panelBuilder: builder,
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _SpreadsheetMenuRoute<T> extends PopupRoute<T> {
  _SpreadsheetMenuRoute({
    required this.position,
    required this.width,
    required this.capturedThemes,
    required this.barrierLabel,
    this.entries = const [],
    this.panelBuilder,
  });

  final Offset position;
  final List<SpreadsheetMenuEntry> entries;
  final double width;
  final CapturedThemes capturedThemes;
  final WidgetBuilder? panelBuilder;

  @override
  final String barrierLabel;

  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Duration get reverseTransitionDuration => const Duration(milliseconds: 100);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return Builder(
      builder: (context) => CustomSingleChildLayout(
        delegate: _SpreadsheetMenuLayout(
          position: position,
          windowPadding: MediaQuery.paddingOf(context),
        ),
        child: capturedThemes.wrap(
          panelBuilder != null
              ? _SpreadsheetPanelCard(width: width, builder: panelBuilder!)
              : _SpreadsheetMenuCard(entries: entries, width: width),
        ),
      ),
    );
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
      parent: animation,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.96, end: 1).animate(curved),
        alignment: Alignment.topLeft,
        child: child,
      ),
    );
  }
}

class _SpreadsheetMenuLayout extends SingleChildLayoutDelegate {
  const _SpreadsheetMenuLayout({
    required this.position,
    required this.windowPadding,
  });

  final Offset position;
  final EdgeInsets windowPadding;

  static const _inset = 8.0;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints.loose(constraints.biggest)
          .deflate(windowPadding + const EdgeInsets.all(_inset));

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final minX = windowPadding.left + _inset;
    final minY = windowPadding.top + _inset;
    final maxX = size.width - windowPadding.right - _inset - childSize.width;
    final maxY = size.height - windowPadding.bottom - _inset - childSize.height;
    return Offset(
      math.min(position.dx, math.max(minX, maxX)),
      math.min(position.dy, math.max(minY, maxY)),
    );
  }

  @override
  bool shouldRelayout(_SpreadsheetMenuLayout oldDelegate) =>
      position != oldDelegate.position ||
      windowPadding != oldDelegate.windowPadding;
}

/// The shared card chrome, used by both the row menus and the format panels.
class SpreadsheetPanelCard extends StatelessWidget {
  const SpreadsheetPanelCard({
    super.key,
    required this.child,
    this.width,
  });

  final Widget child;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: width,
        decoration: BoxDecoration(
          color: palette.floating,
          borderRadius: BorderRadius.circular(SpreadsheetMenuStyle.radius),
          boxShadow: [
            BoxShadow(
              color: palette.shadow,
              blurRadius: 30,
              spreadRadius: -10,
              offset: const Offset(0, 14),
            ),
            BoxShadow(
              color: palette.shadow.withValues(alpha: palette.shadow.a * 0.6),
              blurRadius: 6,
              spreadRadius: -2,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(SpreadsheetMenuStyle.radius),
          child: child,
        ),
      ),
    );
  }
}

class _SpreadsheetPanelCard extends StatelessWidget {
  const _SpreadsheetPanelCard({required this.width, required this.builder});

  final double width;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) =>
      SpreadsheetPanelCard(width: width, child: builder(context));
}

class _SpreadsheetMenuCard extends StatelessWidget {
  const _SpreadsheetMenuCard({required this.entries, required this.width});

  final List<SpreadsheetMenuEntry> entries;
  final double width;

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    return SpreadsheetPanelCard(
      width: width,
      child: SingleChildScrollView(
        padding: SpreadsheetMenuStyle.padding,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final entry in entries)
              entry.isDivider
                  ? Padding(
                      padding: const EdgeInsets.fromLTRB(12, 5, 12, 5),
                      child: Divider(
                        height: 1,
                        thickness: 1,
                        color: palette.gridLine,
                      ),
                    )
                  : _SpreadsheetMenuRow(entry: entry, palette: palette),
          ],
        ),
      ),
    );
  }
}

class _SpreadsheetMenuRow extends StatefulWidget {
  const _SpreadsheetMenuRow({required this.entry, required this.palette});

  final SpreadsheetMenuEntry entry;
  final SpreadsheetPalette palette;

  @override
  State<_SpreadsheetMenuRow> createState() => _SpreadsheetMenuRowState();
}

class _SpreadsheetMenuRowState extends State<_SpreadsheetMenuRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final palette = widget.palette;
    final color = !entry.enabled
        ? palette.textMuted.withValues(alpha: 0.5)
        : entry.destructive
            ? palette.danger
            : palette.textPrimary;
    final iconColor = !entry.enabled
        ? palette.textMuted.withValues(alpha: 0.5)
        : entry.destructive
            ? palette.danger
            : palette.textMuted;
    return MouseRegion(
      cursor:
          entry.enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: entry.enabled
            ? () {
                Navigator.of(context).pop();
                entry.onSelected?.call();
              }
            : null,
        child: Container(
          height: SpreadsheetMenuStyle.rowHeight,
          margin: const EdgeInsets.symmetric(horizontal: 5),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color:
                _hovered && entry.enabled ? palette.hover : Colors.transparent,
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              if (entry.icon != null) ...[
                Icon(entry.icon, size: 15, color: iconColor),
                const SizedBox(width: 10),
              ],
              Expanded(
                child: Text(
                  entry.label,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.2,
                    color: color,
                    fontWeight:
                        entry.selected ? FontWeight.w500 : FontWeight.w400,
                  ),
                ),
              ),
              if (entry.trailing != null)
                Text(
                  entry.trailing!,
                  style: TextStyle(fontSize: 11, color: palette.textMuted),
                ),
              if (entry.selected)
                Icon(Icons.check_rounded, size: 14, color: palette.accent),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Concrete menus
// ---------------------------------------------------------------------------

/// Opens the swatch panel that tints the current selection.
Future<void> showSpreadsheetColorPanel({
  required BuildContext context,
  required SpreadsheetController controller,
  required Offset position,
}) {
  return showSpreadsheetPanel<void>(
    context: context,
    position: position,
    width: 244,
    builder: (context) => SpreadsheetColorPanel(controller: controller),
  );
}

/// Opens the alignment choices for the current selection.
Future<void> showSpreadsheetAlignMenu({
  required BuildContext context,
  required SpreadsheetController controller,
  required Offset position,
}) {
  SpreadsheetMenuEntry entry(CellAlign? align, String label, IconData icon) =>
      SpreadsheetMenuEntry(
        label: label,
        icon: icon,
        selected: controller.selectionHas((style) => style.align == align),
        onSelected: () => controller.setAlign(align),
      );

  return showSpreadsheetMenu(
    context: context,
    position: position,
    width: 196,
    entries: [
      entry(
        null,
        LocaleKeys.spreadsheet_format_alignAuto.tr(),
        Icons.format_align_justify_rounded,
      ),
      entry(
        CellAlign.start,
        LocaleKeys.spreadsheet_format_alignLeft.tr(),
        Icons.format_align_left_rounded,
      ),
      entry(
        CellAlign.center,
        LocaleKeys.spreadsheet_format_alignCenter.tr(),
        Icons.format_align_center_rounded,
      ),
      entry(
        CellAlign.end,
        LocaleKeys.spreadsheet_format_alignRight.tr(),
        Icons.format_align_right_rounded,
      ),
    ],
  );
}

/// Text and background swatches, kept to a restrained palette.
class SpreadsheetColorPanel extends StatelessWidget {
  const SpreadsheetColorPanel({super.key, required this.controller});

  final SpreadsheetController controller;

  static const List<int> textSwatches = [
    0xFF1F2933,
    0xFF616E7C,
    0xFFB03A2E,
    0xFFC0642A,
    0xFFB7950B,
    0xFF1E8449,
    0xFF1A7F8E,
    0xFF2E5FA3,
    0xFF6C3EA3,
    0xFFA83A6E,
  ];

  static const List<int> fillSwatches = [
    0xFFFDECEA,
    0xFFFDF3E3,
    0xFFFBF7DF,
    0xFFE9F7EF,
    0xFFE4F4F6,
    0xFFE8F0FB,
    0xFFF1EAFA,
    0xFFFBEAF2,
    0xFFF2F3F5,
    0xFFE3E5E8,
  ];

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _label(LocaleKeys.spreadsheet_format_textColor.tr(), palette),
          const SizedBox(height: 8),
          _SwatchRow(
            palette: palette,
            colors: textSwatches,
            onPick: controller.setTextColor,
            onClear: () => controller.setTextColor(null),
          ),
          const SizedBox(height: 14),
          _label(LocaleKeys.spreadsheet_format_backgroundColor.tr(), palette),
          const SizedBox(height: 8),
          _SwatchRow(
            palette: palette,
            colors: fillSwatches,
            onPick: controller.setBackgroundColor,
            onClear: () => controller.setBackgroundColor(null),
          ),
        ],
      ),
    );
  }

  static Widget _label(String text, SpreadsheetPalette palette) => Text(
        text.toUpperCase(),
        style: TextStyle(
          fontSize: 9.5,
          letterSpacing: 0.7,
          fontWeight: FontWeight.w600,
          color: palette.textMuted,
        ),
      );
}

class _SwatchRow extends StatelessWidget {
  const _SwatchRow({
    required this.palette,
    required this.colors,
    required this.onPick,
    required this.onClear,
  });

  final SpreadsheetPalette palette;
  final List<int> colors;
  final ValueChanged<int> onPick;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 7,
      runSpacing: 7,
      children: [
        _Swatch(
          color: null,
          palette: palette,
          onTap: () {
            Navigator.of(context).pop();
            onClear();
          },
        ),
        for (final value in colors)
          _Swatch(
            color: Color(value),
            palette: palette,
            onTap: () {
              Navigator.of(context).pop();
              onPick(value);
            },
          ),
      ],
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.palette,
    required this.onTap,
  });

  final Color? color;
  final SpreadsheetPalette palette;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message:
          color == null ? LocaleKeys.spreadsheet_format_defaultColor.tr() : '',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: color ?? palette.surface,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: palette.divider),
            ),
            child: color == null
                ? Icon(
                    Icons.format_color_reset_rounded,
                    size: 12,
                    color: palette.textMuted,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

Future<void> showSpreadsheetCellMenu({
  required BuildContext context,
  required SpreadsheetController controller,
  required Offset position,
  required bool editable,
}) {
  final selection = controller.selection;
  return showSpreadsheetMenu(
    context: context,
    position: position,
    entries: [
      if (editable) ...[
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_format_bold.tr(),
          icon: Icons.format_bold_rounded,
          selected: controller.selectionHas((style) => style.bold),
          onSelected: controller.toggleBold,
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_format_italic.tr(),
          icon: Icons.format_italic_rounded,
          selected: controller.selectionHas((style) => style.italic),
          onSelected: controller.toggleItalic,
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_format_underline.tr(),
          icon: Icons.format_underline_rounded,
          selected: controller.selectionHas((style) => style.underline),
          onSelected: controller.toggleUnderline,
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_format_align.tr(),
          icon: Icons.format_align_left_rounded,
          onSelected: () => showSpreadsheetAlignMenu(
            context: context,
            controller: controller,
            position: position,
          ),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_format_color.tr(),
          icon: Icons.palette_outlined,
          onSelected: () => showSpreadsheetColorPanel(
            context: context,
            controller: controller,
            position: position,
          ),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_format_clearFormatting.tr(),
          icon: Icons.format_clear_rounded,
          onSelected: () => controller.applyStyle((_) => const CellStyle()),
        ),
        const SpreadsheetMenuEntry.divider(),
      ],
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_cut.tr(),
        icon: Icons.content_cut_rounded,
        enabled: editable,
        onSelected: controller.cutSelection,
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_copy.tr(),
        icon: Icons.copy_rounded,
        onSelected: controller.copySelection,
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_paste.tr(),
        icon: Icons.content_paste_rounded,
        enabled: editable,
        onSelected: controller.pasteFromClipboard,
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_clear.tr(),
        icon: Icons.backspace_outlined,
        enabled: editable,
        onSelected: controller.clearSelection,
      ),
      const SpreadsheetMenuEntry.divider(),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertRowAbove.tr(),
        icon: Icons.keyboard_arrow_up_rounded,
        enabled: editable,
        onSelected: () => controller.insertRowsAt(selection.top, 1),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertRowBelow.tr(),
        icon: Icons.keyboard_arrow_down_rounded,
        enabled: editable,
        onSelected: () => controller.insertRowsAt(selection.bottom + 1, 1),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertColumnLeft.tr(),
        icon: Icons.keyboard_arrow_left_rounded,
        enabled: editable,
        onSelected: () => controller.insertColumnsAt(selection.left, 1),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertColumnRight.tr(),
        icon: Icons.keyboard_arrow_right_rounded,
        enabled: editable,
        onSelected: () => controller.insertColumnsAt(selection.right + 1, 1),
      ),
      const SpreadsheetMenuEntry.divider(),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_deleteRow.tr(),
        icon: Icons.remove_circle_outline_rounded,
        enabled: editable && controller.data.rowCount > 1,
        destructive: true,
        onSelected: () =>
            controller.deleteRowsAt(selection.top, selection.rowCount),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_deleteColumn.tr(),
        icon: Icons.remove_circle_outline_rounded,
        enabled: editable && controller.data.columnCount > 1,
        destructive: true,
        onSelected: () =>
            controller.deleteColumnsAt(selection.left, selection.columnCount),
      ),
    ],
  );
}

Future<void> showSpreadsheetRowMenu({
  required BuildContext context,
  required SpreadsheetController controller,
  required int row,
  required Offset position,
  required bool editable,
}) {
  return showSpreadsheetMenu(
    context: context,
    position: position,
    entries: [
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertRowAbove.tr(),
        icon: Icons.keyboard_arrow_up_rounded,
        enabled: editable,
        onSelected: () => controller.insertRowsAt(row, 1),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertRowBelow.tr(),
        icon: Icons.keyboard_arrow_down_rounded,
        enabled: editable,
        onSelected: () => controller.insertRowsAt(row + 1, 1),
      ),
      const SpreadsheetMenuEntry.divider(),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_format_align.tr(),
        icon: Icons.format_align_left_rounded,
        enabled: editable,
        onSelected: () => showSpreadsheetAlignMenu(
          context: context,
          controller: controller,
          position: position,
        ),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_format_color.tr(),
        icon: Icons.palette_outlined,
        enabled: editable,
        onSelected: () => showSpreadsheetColorPanel(
          context: context,
          controller: controller,
          position: position,
        ),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_copy.tr(),
        icon: Icons.copy_rounded,
        onSelected: controller.copySelection,
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_clear.tr(),
        icon: Icons.backspace_outlined,
        enabled: editable,
        onSelected: controller.clearSelection,
      ),
      const SpreadsheetMenuEntry.divider(),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_deleteRow.tr(),
        icon: Icons.delete_outline_rounded,
        enabled: editable && controller.data.rowCount > 1,
        destructive: true,
        onSelected: () => controller.deleteRowsAt(row, 1),
      ),
    ],
  );
}

Future<void> showSpreadsheetColumnMenu({
  required BuildContext context,
  required SpreadsheetController controller,
  required int column,
  required Offset position,
  required VoidCallback onAutoFit,
  required bool editable,
}) async {
  final hasHiddenColumns = List.generate(
    controller.data.columnCount,
    (index) => index,
  ).any(controller.data.isColumnHidden);

  await showSpreadsheetMenu(
    context: context,
    position: position,
    entries: [
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_sortAscending.tr(),
        icon: Icons.arrow_upward_rounded,
        enabled: editable,
        selected: controller.data.sort?.column == column &&
            controller.data.sort?.direction == SortDirection.ascending,
        onSelected: () =>
            controller.sortByColumn(column, SortDirection.ascending),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_sortDescending.tr(),
        icon: Icons.arrow_downward_rounded,
        enabled: editable,
        selected: controller.data.sort?.column == column &&
            controller.data.sort?.direction == SortDirection.descending,
        onSelected: () =>
            controller.sortByColumn(column, SortDirection.descending),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_filter.tr(),
        icon: Icons.filter_alt_outlined,
        selected: controller.filterFor(column).isNotEmpty,
        onSelected: () => showSpreadsheetFilterPrompt(
          context: context,
          controller: controller,
          column: column,
        ),
      ),
      if (controller.data.filters.isNotEmpty)
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_clearFilters.tr(),
          icon: Icons.filter_alt_off_outlined,
          onSelected: controller.clearFilters,
        ),
      const SpreadsheetMenuEntry.divider(),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertColumnLeft.tr(),
        icon: Icons.keyboard_arrow_left_rounded,
        enabled: editable,
        onSelected: () => controller.insertColumnsAt(column, 1),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_insertColumnRight.tr(),
        icon: Icons.keyboard_arrow_right_rounded,
        enabled: editable,
        onSelected: () => controller.insertColumnsAt(column + 1, 1),
      ),
      const SpreadsheetMenuEntry.divider(),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_format_align.tr(),
        icon: Icons.format_align_left_rounded,
        enabled: editable,
        onSelected: () => showSpreadsheetAlignMenu(
          context: context,
          controller: controller,
          position: position,
        ),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_format_color.tr(),
        icon: Icons.palette_outlined,
        enabled: editable,
        onSelected: () => showSpreadsheetColorPanel(
          context: context,
          controller: controller,
          position: position,
        ),
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_autoFit.tr(),
        icon: Icons.width_normal_rounded,
        enabled: editable,
        onSelected: onAutoFit,
      ),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_hideColumn.tr(),
        icon: Icons.visibility_off_outlined,
        enabled: editable && controller.data.columnCount > 1,
        onSelected: () => controller.setColumnHidden(column, true),
      ),
      if (hasHiddenColumns)
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_showAllColumns.tr(),
          icon: Icons.visibility_outlined,
          enabled: editable,
          onSelected: controller.showAllColumns,
        ),
      const SpreadsheetMenuEntry.divider(),
      SpreadsheetMenuEntry(
        label: LocaleKeys.spreadsheet_menu_deleteColumn.tr(),
        icon: Icons.delete_outline_rounded,
        enabled: editable && controller.data.columnCount > 1,
        destructive: true,
        onSelected: () => controller.deleteColumnsAt(column, 1),
      ),
    ],
  );
}

Future<void> showSpreadsheetFilterPrompt({
  required BuildContext context,
  required SpreadsheetController controller,
  required int column,
}) async {
  final palette = SpreadsheetPalette.of(context);
  final textController =
      TextEditingController(text: controller.filterFor(column));
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: palette.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(
        '${LocaleKeys.spreadsheet_filter_title.tr()} · '
        '${CellRef.columnLabel(column)}',
        style: TextStyle(fontSize: 15, color: palette.textPrimary),
      ),
      content: SizedBox(
        width: 300,
        child: TextField(
          controller: textController,
          autofocus: true,
          style: TextStyle(fontSize: 13, color: palette.textPrimary),
          decoration: InputDecoration(
            hintText: LocaleKeys.spreadsheet_filter_placeholder.tr(),
            isDense: true,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
            ),
          ),
          onSubmitted: (value) => Navigator.of(context).pop(value),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: Text(LocaleKeys.spreadsheet_filter_clear.tr()),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(textController.text),
          child: Text(LocaleKeys.spreadsheet_filter_apply.tr()),
        ),
      ],
    ),
  );
  textController.dispose();
  if (result != null) {
    controller.setFilter(column, result);
  }
}
