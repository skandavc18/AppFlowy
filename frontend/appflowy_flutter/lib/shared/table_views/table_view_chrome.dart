import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One of the small buttons every table view's chrome is made of.
class TableViewButton extends StatefulWidget {
  const TableViewButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final TableViewPalette palette;
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  State<TableViewButton> createState() => _TableViewButtonState();
}

class _TableViewButtonState extends State<TableViewButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    // Fading from a transparent black would pass through grey; the hover
    // colour at zero alpha keeps the tween in one hue.
    final resting = widget.active
        ? palette.accent.withValues(alpha: 0.14)
        : palette.hoverAtRest;
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TableViewMetrics.hover,
          curve: TableViewMetrics.enterCurve,
          width: TableViewMetrics.controlSize,
          height: TableViewMetrics.controlSize,
          decoration: BoxDecoration(
            color: _hovered && !widget.active ? palette.hover : resting,
            borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
          ),
          child: Icon(
            widget.icon,
            size: 17,
            color: widget.active ? palette.accent : palette.textSecondary,
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) {
      return button;
    }
    return Tooltip(
      message: tooltip,
      waitDuration: TableViewMetrics.hover,
      child: button,
    );
  }
}

/// The bar every table view wears: what it is, how many rows, and the handful
/// of controls that mean the same thing wherever they appear.
class TableViewHeader extends StatefulWidget {
  const TableViewHeader({
    super.key,
    required this.palette,
    required this.title,
    required this.subtitle,
    required this.columns,
    required this.query,
    required this.onQueryChanged,
    required this.valuesOf,
    this.onAdd,
    this.optionsBuilder,
    this.actions = const [],
    this.allowGrouping = true,
  });

  final TableViewPalette palette;
  final String title;
  final String subtitle;
  final List<FieldPB> columns;
  final TableQuery query;
  final ValueChanged<TableQuery> onQueryChanged;

  /// The values a column holds, so a filter can offer them.
  final List<String> Function(String fieldId) valuesOf;

  final VoidCallback? onAdd;

  /// The rows of the ⋯ menu, which is where a view puts what only it can do.
  final List<AppMenuEntry> Function()? optionsBuilder;

  /// Controls that belong to one view only, shown before the shared ones.
  final List<Widget> actions;

  final bool allowGrouping;

  @override
  State<TableViewHeader> createState() => TableViewHeaderState();
}

class TableViewHeaderState extends State<TableViewHeader> {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'TableViewSearch');
  bool _open = false;

  @override
  void didUpdateWidget(TableViewHeader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.query.search != _search.text) {
      _search.text = widget.query.search;
    }
  }

  @override
  void dispose() {
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  void openSearch() {
    setState(() => _open = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void closeSearch() {
    if (!_open) {
      return;
    }
    _search.clear();
    setState(() => _open = false);
    widget.onQueryChanged(widget.query.copyWith(search: ''));
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final query = widget.query;

    return SizedBox(
      height: TableViewMetrics.headerHeight,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    widget.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.subtitle,
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
              ],
            ),
          ),
          ...widget.actions,
          if (widget.actions.isNotEmpty)
            const SizedBox(width: TableViewMetrics.controlGap),
          if (_open)
            _buildSearchField(palette)
          else
            TableViewButton(
              palette: palette,
              icon: Icons.search_rounded,
              tooltip: LocaleKeys.tableViews_search.tr(),
              onTap: openSearch,
            ),
          const SizedBox(width: TableViewMetrics.controlGap),
          Builder(
            builder: (context) => TableViewButton(
              palette: palette,
              icon: Icons.swap_vert_rounded,
              tooltip: LocaleKeys.tableViews_sort.tr(),
              active: query.isSorting,
              onTap: () => unawaited(_showSortMenu(context)),
            ),
          ),
          const SizedBox(width: TableViewMetrics.controlGap),
          Builder(
            builder: (context) => TableViewButton(
              palette: palette,
              icon: Icons.filter_alt_rounded,
              tooltip: LocaleKeys.tableViews_filter.tr(),
              active: query.isFiltering,
              onTap: () => unawaited(_showFilterMenu(context)),
            ),
          ),
          if (widget.allowGrouping) ...[
            const SizedBox(width: TableViewMetrics.controlGap),
            Builder(
              builder: (context) => TableViewButton(
                palette: palette,
                icon: Icons.workspaces_rounded,
                tooltip: LocaleKeys.tableViews_group.tr(),
                active: query.isGrouping,
                onTap: () => unawaited(_showGroupMenu(context)),
              ),
            ),
          ],
          if (widget.onAdd != null) ...[
            const SizedBox(width: TableViewMetrics.controlGap),
            TableViewButton(
              palette: palette,
              icon: Icons.add_rounded,
              tooltip: LocaleKeys.tableViews_addRow.tr(),
              onTap: widget.onAdd!,
            ),
          ],
          if (widget.optionsBuilder != null) ...[
            const SizedBox(width: TableViewMetrics.controlGap),
            Builder(
              builder: (context) => TableViewButton(
                palette: palette,
                icon: Icons.more_horiz_rounded,
                tooltip: LocaleKeys.tableViews_options.tr(),
                onTap: () => unawaited(
                  showAppMenuForWidget<void>(
                    context: context,
                    entries: widget.optionsBuilder!(),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSearchField(TableViewPalette palette) => SizedBox(
        width: TableViewMetrics.searchWidth,
        height: TableViewMetrics.controlSize,
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          autofocus: true,
          style: TextStyle(fontSize: 13, color: palette.textPrimary),
          onChanged: (value) =>
              widget.onQueryChanged(widget.query.copyWith(search: value)),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: palette.raised,
            hintText: LocaleKeys.tableViews_searchHint.tr(),
            hintStyle: TextStyle(fontSize: 13, color: palette.textMuted),
            prefixIcon:
                Icon(Icons.search_rounded, size: 15, color: palette.textMuted),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            suffixIcon: IconButton(
              icon: Icon(
                Icons.close_rounded,
                size: 14,
                color: palette.textMuted,
              ),
              splashRadius: 12,
              onPressed: closeSearch,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: _searchBorder(palette, focused: false),
            enabledBorder: _searchBorder(palette, focused: false),
            focusedBorder: _searchBorder(palette, focused: true),
          ),
        ),
      );

  OutlineInputBorder _searchBorder(
    TableViewPalette palette, {
    required bool focused,
  }) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
        borderSide: focused
            ? BorderSide(color: palette.accent, width: 1.2)
            : BorderSide.none,
      );

  Future<void> _showSortMenu(BuildContext context) async {
    final query = widget.query;
    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.tableViews_sortBy.tr()),
        AppMenuItem(
          label: LocaleKeys.tableViews_tableOrder.tr(),
          icon: Icons.list_rounded,
          selected: !query.isSorting,
          onSelected: () =>
              widget.onQueryChanged(query.copyWith(sortColumn: '')),
        ),
        for (final field in widget.columns)
          AppMenuItem(
            label: field.name,
            icon: query.sortColumn == field.id
                ? (query.direction == TableSortDirection.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded)
                : Icons.sort_rounded,
            selected: query.sortColumn == field.id,
            onSelected: () => widget.onQueryChanged(
              query.copyWith(
                sortColumn: field.id,
                direction: query.sortColumn == field.id
                    ? query.direction.flipped
                    : TableSortDirection.ascending,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showFilterMenu(BuildContext context) async {
    final query = widget.query;
    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.tableViews_filterBy.tr()),
        AppMenuItem(
          label: LocaleKeys.tableViews_everything.tr(),
          icon: Icons.all_inclusive_rounded,
          selected: !query.isFiltering,
          onSelected: () => widget.onQueryChanged(
            query.copyWith(filterColumn: '', filterValue: ''),
          ),
        ),
        for (final field in widget.columns)
          AppMenuItem(
            label: field.name,
            icon: Icons.filter_alt_rounded,
            selected: query.filterColumn == field.id,
            submenu: _filterValuesOf(field),
          ),
      ],
    );
  }

  List<AppMenuEntry> _filterValuesOf(FieldPB field) {
    final query = widget.query;
    final values = widget.valuesOf(field.id).take(40).toList();
    return [
      AppMenuItem(
        label: LocaleKeys.tableViews_hasAnything.tr(),
        icon: Icons.check_circle_outline_rounded,
        selected: query.filterColumn == field.id && query.filterValue.isEmpty,
        onSelected: () => widget.onQueryChanged(
          query.copyWith(filterColumn: field.id, filterValue: ''),
        ),
      ),
      if (values.isNotEmpty) const AppMenuSeparator(),
      for (final value in values)
        AppMenuItem(
          label: value,
          selected: query.filterColumn == field.id &&
              query.filterValue.toLowerCase() == value.toLowerCase(),
          onSelected: () => widget.onQueryChanged(
            query.copyWith(filterColumn: field.id, filterValue: value),
          ),
        ),
    ];
  }

  Future<void> _showGroupMenu(BuildContext context) async {
    final query = widget.query;
    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.tableViews_groupBy.tr()),
        AppMenuItem(
          label: LocaleKeys.tableViews_noGrouping.tr(),
          icon: Icons.remove_rounded,
          selected: !query.isGrouping,
          onSelected: () =>
              widget.onQueryChanged(query.copyWith(groupColumn: '')),
        ),
        for (final field in widget.columns)
          AppMenuItem(
            label: field.name,
            icon: Icons.workspaces_rounded,
            selected: query.groupColumn == field.id,
            onSelected: () =>
                widget.onQueryChanged(query.copyWith(groupColumn: field.id)),
          ),
      ],
    );
  }
}

/// What a view shows instead of nothing.
///
/// A blank rectangle tells a reader that something is broken. A drawn stack of
/// empty cards, a sentence and a button tells them what to do next.
class TableViewEmpty extends StatelessWidget {
  const TableViewEmpty({
    super.key,
    required this.palette,
    required this.icon,
    required this.message,
    this.detail = '',
    this.actionLabel = '',
    this.onAction,
  });

  final TableViewPalette palette;
  final IconData icon;
  final String message;
  final String detail;
  final String actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildIllustration(),
          const SizedBox(height: TableViewMetrics.space5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              letterSpacing: -0.2,
              color: palette.textPrimary,
            ),
          ),
          if (detail.isNotEmpty) ...[
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 320),
              child: Text(
                detail,
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.45,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
          if (onAction != null && actionLabel.isNotEmpty) ...[
            const SizedBox(height: TableViewMetrics.space4),
            TableViewAction(
              palette: palette,
              label: actionLabel,
              icon: Icons.add_rounded,
              onTap: onAction!,
            ),
          ],
        ],
      ),
    );
  }

  /// Three empty cards leaning behind one another, with the view's own mark on
  /// the front of them.
  Widget _buildIllustration() {
    return SizedBox(
      width: 148,
      height: 104,
      child: Stack(
        alignment: Alignment.center,
        children: [
          _ghost(width: 118, height: 74, dy: -8, tilt: -0.09, alpha: 0.35),
          _ghost(width: 118, height: 74, dy: -4, tilt: 0.07, alpha: 0.55),
          Container(
            width: 118,
            height: 74,
            decoration: BoxDecoration(
              color: palette.raised,
              borderRadius: BorderRadius.circular(TableViewMetrics.panelRadius),
              boxShadow: palette.chromeShadow,
            ),
            alignment: Alignment.center,
            child: Icon(
              icon,
              size: 26,
              color: palette.accent.withValues(alpha: 0.75),
            ),
          ),
        ],
      ),
    );
  }

  Widget _ghost({
    required double width,
    required double height,
    required double dy,
    required double tilt,
    required double alpha,
  }) =>
      Transform(
        alignment: Alignment.center,
        transform: Matrix4.identity()
          ..translate(0.0, dy)
          ..rotateZ(tilt),
        child: Container(
          width: width,
          height: height,
          decoration: BoxDecoration(
            color: palette.raised.withValues(alpha: alpha),
            borderRadius: BorderRadius.circular(TableViewMetrics.panelRadius),
          ),
        ),
      );
}

/// The one button shape a table view offers an action with.
class TableViewAction extends StatefulWidget {
  const TableViewAction({
    super.key,
    required this.palette,
    required this.label,
    required this.onTap,
    this.icon,
    this.primary = true,
  });

  final TableViewPalette palette;
  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final bool primary;

  @override
  State<TableViewAction> createState() => _TableViewActionState();
}

class _TableViewActionState extends State<TableViewAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final tint = widget.primary ? palette.accent : palette.textSecondary;
    final fill = widget.primary
        ? palette.accent.withValues(alpha: _hovered ? 0.2 : 0.12)
        : (_hovered ? palette.hover : palette.hoverAtRest);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TableViewMetrics.hover,
          curve: TableViewMetrics.enterCurve,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, size: 15, color: tint),
                const SizedBox(width: 7),
              ],
              Text(
                widget.label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: tint,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The heading above a run of rows that share a value.
class TableGroupHeading extends StatelessWidget {
  const TableGroupHeading({
    super.key,
    required this.palette,
    required this.label,
    required this.count,
  });

  final TableViewPalette palette;
  final String label;
  final int count;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: TableViewMetrics.space3),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 14,
            decoration: BoxDecoration(
              color: palette.swatchFor(label),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 9),
          Text(
            label,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.1,
              color: palette.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            '$count',
            style: TextStyle(fontSize: 11.5, color: palette.textMuted),
          ),
        ],
      ),
    );
  }
}
