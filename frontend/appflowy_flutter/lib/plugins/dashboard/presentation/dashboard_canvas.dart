import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_add_menu.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_board.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One band of a dashboard: its heading, and the canvas underneath it.
class DashboardSectionView extends StatefulWidget {
  const DashboardSectionView({
    super.key,
    required this.controller,
    required this.section,
    required this.palette,
  });

  final DashboardController controller;
  final DashboardSection section;
  final DashboardPalette palette;

  @override
  State<DashboardSectionView> createState() => _DashboardSectionViewState();
}

class _DashboardSectionViewState extends State<DashboardSectionView> {
  bool _hovered = false;
  bool _renaming = false;

  DashboardController get controller => widget.controller;

  DashboardSection get section => widget.section;

  DashboardPalette get palette => widget.palette;

  @override
  Widget build(BuildContext context) {
    final editable = controller.isEditable;
    final visible = dashboardVisibilityHolds(
      section.visibleWhen,
      controller.state,
    );
    if (!visible && !editable) {
      return const SizedBox.shrink();
    }

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Padding(
        padding: const EdgeInsets.only(bottom: DashboardMetrics.sectionGap),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (section.hasHeading || editable)
              _buildHeading(context, editable),
            if (section.showDivider)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Container(height: 1, color: palette.gridLine),
              ),
            AnimatedCrossFade(
              duration: DashboardMetrics.settle,
              sizeCurve: DashboardMetrics.curve,
              crossFadeState: section.collapsed
                  ? CrossFadeState.showFirst
                  : CrossFadeState.showSecond,
              firstChild: const SizedBox(width: double.infinity, height: 0),
              secondChild: DashboardCanvas(
                controller: controller,
                section: section,
                palette: palette,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeading(BuildContext context, bool editable) {
    final title = section.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Row(
        children: [
          if (section.hasHeading || section.collapsed)
            _Chevron(
              collapsed: section.collapsed,
              palette: palette,
              onPressed: () => controller.edit(
                (document) => document.withSection(
                  section.copyWith(collapsed: !section.collapsed),
                ),
              ),
            ),
          Flexible(
            // A section is named the way a page is named: double click it.
            child: editable
                ? WorkspaceInlineEditableText(
                    text: title,
                    editingValue: title,
                    editing: _renaming,
                    style: DashboardType.sectionLabel(palette).copyWith(
                      color: title.isEmpty
                          ? palette.textMuted
                          : palette.textSecondary,
                    ),
                    display: Text(
                      title.isEmpty
                          ? LocaleKeys.dashboard_section_untitled.tr()
                          : title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.sectionLabel(palette).copyWith(
                        color: title.isEmpty
                            ? palette.textMuted
                            : palette.textSecondary,
                      ),
                    ),
                    onDoubleTap: () => setState(() => _renaming = true),
                    onCancelled: () => setState(() => _renaming = false),
                    onSubmitted: (name) async {
                      setState(() => _renaming = false);
                      controller.edit(
                        (document) => document.withSection(
                          section.copyWith(title: name.trim()),
                        ),
                      );
                      return true;
                    },
                  )
                : Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: DashboardType.sectionLabel(palette).copyWith(
                      color: palette.textSecondary,
                    ),
                  ),
          ),
          if (editable) ...[
            const SizedBox(width: 6),
            // Beside the name, not adrift at the far edge of the board.
            AnimatedOpacity(
              duration: DashboardMetrics.hover,
              opacity: _hovered ? 1 : 0,
              child: IgnorePointer(
                ignoring: !_hovered,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DashboardIconButton(
                      icon: Icons.add_rounded,
                      palette: palette,
                      size: 24,
                      tooltip: LocaleKeys.dashboard_add_widget.tr(),
                      onPressed: () => _addWidget(context),
                    ),
                    Builder(
                      builder: (anchor) => DashboardIconButton(
                        icon: Icons.more_horiz_rounded,
                        palette: palette,
                        size: 24,
                        tooltip: LocaleKeys.dashboard_section_options.tr(),
                        onPressed: () => _showMenu(anchor),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          const Spacer(),
        ],
      ),
    );
  }

  Future<void> _addWidget(BuildContext context) async {
    final definition = await showDashboardWidgetPicker(
      context: context,
      palette: palette,
    );
    if (definition == null) {
      return;
    }
    controller.edit(
      (document) => document.addWidget(
        definition.create(
          placement: DashboardPlacement(
            row: _nextRow(),
            columnSpan: definition.defaultColumnSpan,
            rowSpan: definition.defaultRowSpan,
          ),
        ),
        sectionId: section.id,
      ),
    );
  }

  int _nextRow() {
    var row = 0;
    for (final widget in section.widgets) {
      row = math.max(row, widget.placement.endRow);
    }
    return row;
  }

  void _showMenu(BuildContext context) {
    final document = controller.document;
    showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuItem(
          label: LocaleKeys.dashboard_section_rename.tr(),
          icon: Icons.edit_rounded,
          onSelected: () => setState(() => _renaming = true),
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_section_arrange.tr(),
          icon: Icons.dashboard_customize_rounded,
          submenu: [
            for (final layout in DashboardSectionLayout.values)
              AppMenuItem(
                label: dashboardSectionLayoutLabel(layout),
                icon: dashboardSectionLayoutIcon(layout),
                selected: section.layout == layout,
                onSelected: () => controller.edit(
                  (document) => document.withSection(
                    section.copyWith(
                      layout: layout,
                      widgets: applySectionLayout(section.widgets, layout),
                    ),
                  ),
                ),
              ),
          ],
        ),
        AppMenuItem(
          label: LocaleKeys.dashboard_section_divider.tr(),
          icon: Icons.horizontal_rule_rounded,
          selected: section.showDivider,
          onSelected: () => controller.edit(
            (document) => document.withSection(
              section.copyWith(showDivider: !section.showDivider),
            ),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.dashboard_section_addBelow.tr(),
          icon: Icons.playlist_add_rounded,
          onSelected: () => controller.edit((document) {
            final index = document.sections.indexOf(section);
            final sections = [...document.sections];
            sections.insert(
              index < 0 ? sections.length : index + 1,
              DashboardSection(id: newDashboardId('section')),
            );
            return document.copyWith(sections: sections);
          }),
        ),
        AppMenuItem(
          label: LocaleKeys.button_delete.tr(),
          icon: Icons.delete_outline_rounded,
          destructive: true,
          enabled: document.sections.length > 1,
          onSelected: () => controller.edit(
            (document) => document.copyWith(
              sections: [
                for (final existing in document.sections)
                  if (existing.id != section.id) existing,
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The responsive grid one section's widgets are arranged on.
///
/// Cards are placed absolutely and animate to where the settled layout puts
/// them, so moving one pushes its neighbours out of the way while the pointer
/// is still down rather than after it is let go.
class DashboardCanvas extends StatefulWidget {
  const DashboardCanvas({
    super.key,
    required this.controller,
    required this.section,
    required this.palette,
  });

  final DashboardController controller;
  final DashboardSection section;
  final DashboardPalette palette;

  @override
  State<DashboardCanvas> createState() => _DashboardCanvasState();
}

class _DashboardCanvasState extends State<DashboardCanvas> {
  String? _activeId;
  DashboardPlacement? _livePlacement;
  DashboardPlacement? _originPlacement;
  Offset _accumulated = Offset.zero;
  DashboardResizeEdge? _resizing;

  /// Where the pointer last was, so a card let go over another section can be
  /// handed to it.
  Offset _pointer = Offset.zero;

  /// The height this band had when a drag began.
  ///
  /// A section that grows to fit the card being dragged pushes the section
  /// below it away, so the pointer can never reach it. Holding the height
  /// still keeps the board where the person can see it.
  double? _frozenHeight;
  double _lastHeight = 0;

  final GlobalKey _board = GlobalKey();
  DashboardSectionRegistry? _registry;

  /// The last grid the canvas was drawn on, so a drag can keep working while
  /// the page scrolls under it.
  DashboardGridMetrics? _lastMetrics;
  int _lastColumns = DashboardPlacement.referenceColumns;
  Timer? _autoScroll;
  double _autoStep = 0;

  /// Where the card being moved actually is, in pixels.
  ///
  /// Kept out of [setState] on purpose: a card must follow the pointer every
  /// frame, and rebuilding a board of databases and calendars sixty times a
  /// second is what makes a drag stutter. The board is only rebuilt when the
  /// card lands on a different cell and its neighbours have to move.
  final ValueNotifier<_DragFrame?> _frame = ValueNotifier<_DragFrame?>(null);

  DashboardController get controller => widget.controller;

  DashboardSection get section => widget.section;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final registry = DashboardBoard.maybeOf(context);
    if (registry != _registry) {
      _registry?.unregister(section.id, _board);
      _registry = registry?..register(section.id, _board);
    }
  }

  @override
  void dispose() {
    _autoScroll?.cancel();
    _registry?.unregister(section.id, _board);
    _frame.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final settings = controller.document.settings;
    final editable = controller.isEditable;

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width <= 0) {
          return const SizedBox.shrink();
        }
        final pinned = settings.columns > 0;
        final columns = pinned
            ? math.min(settings.columns, dashboardColumnsFor(width))
            : dashboardColumnsFor(width);
        final metrics = dashboardGridMetrics(
          width: width,
          columns: columns,
          gap: settings.density.gap,
          rowHeight: settings.density.rowHeight,
        );

        final visible = [
          for (final spec in section.widgets)
            if (editable || _isVisible(spec)) spec,
        ];

        if (visible.isEmpty) {
          return editable
              ? _buildEmpty(context)
              : const SizedBox(width: double.infinity, height: 0);
        }

        final slots = resolveDashboardLayout(
          [
            for (final spec in visible)
              DashboardSlot(
                id: spec.id,
                placement: spec.id == _activeId && _livePlacement != null
                    ? _livePlacement!
                    : _forCanvas(spec.placement, columns, pinned),
              ),
          ],
          columns: columns,
          // The live placement is already in canvas columns; the rest are
          // stored against the reference grid and scaled here.
          storedColumns: columns,
          floating: _activeId,
          compact: section.layout != DashboardSectionLayout.free,
        );

        final placements = {
          for (final slot in slots) slot.id: slot.placement,
        };
        final rows = dashboardLayoutHeight(slots);
        final height = metrics.heightOf(math.max(rows, 1)) +
            (editable ? metrics.rowHeight + metrics.gap : 0);
        _lastHeight = height;
        _lastMetrics = metrics;
        _lastColumns = columns;

        // Painted top to bottom, so a card's shadow always falls into the
        // gutter under it and is covered where it reaches the next card —
        // otherwise it prints a hard-edged smudge across its neighbour. The
        // one being dragged is painted last so it rides over the rest.
        final ordered = [...visible]..sort((a, b) {
            if (a.id == _activeId) {
              return 1;
            }
            if (b.id == _activeId) {
              return -1;
            }
            final first = placements[a.id] ?? a.placement;
            final second = placements[b.id] ?? b.placement;
            final byRow = first.row.compareTo(second.row);
            return byRow != 0 ? byRow : first.column.compareTo(second.column);
          });

        return SizedBox(
          key: _board,
          height: _frozenHeight ?? height,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              if (_activeId != null) _buildLanding(metrics),
              for (final spec in ordered)
                _buildPositioned(
                  spec: spec,
                  placement: placements[spec.id] ?? spec.placement,
                  metrics: metrics,
                  columns: columns,
                  pinned: pinned,
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildPositioned({
    required DashboardWidgetSpec spec,
    required DashboardPlacement placement,
    required DashboardGridMetrics metrics,
    required int columns,
    required bool pinned,
  }) {
    final active = spec.id == _activeId;
    final card = RepaintBoundary(
      child: DashboardCard(
        key: ValueKey(spec.id),
        controller: controller,
        spec: spec,
        palette: widget.palette,
        selected: controller.selectedWidgetId == spec.id,
        dragging: active && _resizing == null,
        onDragStart: () => _begin(spec, placement, null),
        onDragUpdate: (delta, pointer) =>
            _move(delta, pointer, metrics, columns),
        onDragEnd: () => _commit(spec, columns, pinned, metrics),
        onResizeStart: (edge) => _begin(spec, placement, edge),
        onResizeUpdate: (edge, delta) => _resize(spec, delta, metrics, columns),
        onResizeEnd: () => _commit(spec, columns, pinned, metrics),
      ),
    );

    final left = metrics.leftOf(placement.column);
    final top = metrics.topOf(placement.row);
    final width = metrics.widthOf(placement.columnSpan);
    final cardHeight = metrics.heightOf(placement.rowSpan);

    // Always the same widget, whether or not this card is the one being
    // moved. Swapping `AnimatedPositioned` for `Positioned` mid-gesture gives
    // the element a different runtimeType, so Flutter throws the subtree away
    // and rebuilds it — taking the card's State, and with it the recogniser
    // holding the drag, on the very first frame of the drag.
    return AnimatedPositioned(
      key: ValueKey(spec.id),
      duration: active || controller.document.settings.reduceMotion
          ? Duration.zero
          : DashboardMetrics.settle,
      curve: DashboardMetrics.curve,
      left: left,
      top: top,
      width: width,
      height: cardHeight,
      child: ValueListenableBuilder<_DragFrame?>(
        valueListenable: _frame,
        // The card is handed through untouched, so following the pointer
        // costs a transform and a layout, never a rebuild.
        child: card,
        builder: (context, frame, child) {
          final live = active ? frame : null;
          return Transform.translate(
            offset: live?.offset ?? Offset.zero,
            child: OverflowBox(
              alignment: Alignment.topLeft,
              minWidth: live == null ? null : 0,
              maxWidth: live?.size.width,
              minHeight: live == null ? null : 0,
              maxHeight: live?.size.height,
              child: SizedBox(
                width: live?.size.width,
                height: live?.size.height,
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  /// The outline of where the card will land.
  Widget _buildLanding(DashboardGridMetrics metrics) {
    final placement = _livePlacement;
    if (placement == null) {
      return const SizedBox.shrink();
    }
    return AnimatedPositioned(
      key: const ValueKey('dashboard-landing'),
      duration: DashboardMetrics.hover,
      curve: DashboardMetrics.curve,
      left: metrics.leftOf(placement.column),
      top: metrics.topOf(placement.row),
      width: metrics.widthOf(placement.columnSpan),
      height: metrics.heightOf(placement.rowSpan),
      child: IgnorePointer(
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: widget.palette.accent.withValues(alpha: 0.07),
            borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
            border: Border.all(
              color: widget.palette.accent.withValues(alpha: 0.32),
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => _add(context),
        child: Container(
          height: 132,
          decoration: BoxDecoration(
            color: widget.palette.sunken.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
          ),
          child: DashboardPlaceholder(
            palette: widget.palette,
            icon: Icons.add_rounded,
            message: LocaleKeys.dashboard_empty_section.tr(),
            action: LocaleKeys.dashboard_add_widget.tr(),
            onAction: () => _add(context),
          ),
        ),
      );

  Future<void> _add(BuildContext context) async {
    final definition = await showDashboardWidgetPicker(
      context: context,
      palette: widget.palette,
    );
    if (definition == null) {
      return;
    }
    controller.edit(
      (document) => document.addWidget(
        definition.create(),
        sectionId: section.id,
      ),
    );
  }

  bool _isVisible(DashboardWidgetSpec spec) =>
      !spec.hidden &&
      dashboardVisibilityHolds(spec.visibleWhen, controller.state);

  /// Stored spans are written against the reference grid and scaled to fit
  /// whatever the window allows. A COLUMN COUNT THE PERSON CHOSE is not that:
  /// it is a coarser or finer grid, so the spans are taken at face value and
  /// a card really does become wider when there are fewer columns.
  DashboardPlacement _forCanvas(
    DashboardPlacement placement,
    int columns,
    bool pinned,
  ) =>
      pinned
          ? placement
          : scaleDashboardPlacement(
              placement,
              from: DashboardPlacement.referenceColumns,
              to: columns,
            );

  void _begin(
    DashboardWidgetSpec spec,
    DashboardPlacement placement,
    DashboardResizeEdge? edge,
  ) {
    _accumulated = Offset.zero;
    _frame.value = null;
    setState(() {
      _activeId = spec.id;
      _originPlacement = placement;
      _livePlacement = placement;
      _resizing = edge;
      _frozenHeight = edge == null ? _lastHeight : null;
    });
    controller.select(spec.id);
  }

  void _move(
    Offset delta,
    Offset pointer,
    DashboardGridMetrics metrics,
    int columns,
  ) {
    final origin = _originPlacement;
    if (origin == null) {
      return;
    }
    _pointer = pointer;
    _accumulated += delta;
    _driveAutoScroll(pointer);
    final left = metrics.leftOf(origin.column) + _accumulated.dx;
    final top = metrics.topOf(origin.row) + _accumulated.dy;
    final column = metrics.columnAt(left).clamp(0, columns - origin.columnSpan);
    final row = metrics.rowAt(top);
    final next = origin.copyWith(column: column, row: row);

    // What is carried is only the difference between the pointer and the cell
    // the card has settled on, so letting go lands it without a jump.
    _frame.value = _DragFrame(
      offset: Offset(
        left - metrics.leftOf(next.column),
        top - metrics.topOf(next.row),
      ),
      size: Size(
        metrics.widthOf(origin.columnSpan),
        metrics.heightOf(origin.rowSpan),
      ),
    );
    if (next != _livePlacement) {
      setState(() => _livePlacement = next);
    }
  }

  /// A card held near the top or bottom of the window scrolls the board, so a
  /// section that is off screen can still be dropped into.
  void _driveAutoScroll(Offset pointer) {
    final scrollable = Scrollable.maybeOf(context);
    final viewport = scrollable?.context.findRenderObject() as RenderBox?;
    if (scrollable == null || viewport == null || !viewport.hasSize) {
      _stopAutoScroll();
      return;
    }
    const edge = 80.0;
    final local = viewport.globalToLocal(pointer).dy;
    final double reach;
    if (local < edge) {
      reach = local - edge;
    } else if (local > viewport.size.height - edge) {
      reach = local - (viewport.size.height - edge);
    } else {
      _stopAutoScroll();
      return;
    }
    _autoStep = (reach / edge).clamp(-1.0, 1.0) * 16;
    _autoScroll ??= Timer.periodic(
      const Duration(milliseconds: 16),
      (_) => _tickAutoScroll(scrollable.position),
    );
  }

  void _tickAutoScroll(ScrollPosition position) {
    final metrics = _lastMetrics;
    if (_activeId == null || metrics == null) {
      _stopAutoScroll();
      return;
    }
    final next = (position.pixels + _autoStep)
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final moved = next - position.pixels;
    if (moved == 0) {
      return;
    }
    position.jumpTo(next);
    // The content moved under a pointer that did not, so the card has to be
    // told it travelled.
    _move(Offset(0, moved), _pointer, metrics, _lastColumns);
  }

  void _stopAutoScroll() {
    _autoScroll?.cancel();
    _autoScroll = null;
    _autoStep = 0;
  }

  void _resize(
    DashboardWidgetSpec spec,
    Offset delta,
    DashboardGridMetrics metrics,
    int columns,
  ) {
    final origin = _originPlacement;
    final edge = _resizing;
    if (origin == null || edge == null) {
      return;
    }
    // A widget says how small it can be drawn; below that it does not shrink,
    // it breaks.
    final definition = DashboardWidgetRegistry.definitionFor(spec.type);
    final leastColumns = math.max(
      DashboardMetrics.minimumColumnSpan,
      definition?.minimumColumnSpan ?? 1,
    );
    final leastRows = math.max(
      DashboardMetrics.minimumRowSpan,
      definition?.minimumRowSpan ?? 1,
    );

    _accumulated += delta;
    final grown = Size(
      math.max(
        metrics.widthOf(leastColumns),
        metrics.widthOf(origin.columnSpan) +
            (edge == DashboardResizeEdge.bottom ? 0 : _accumulated.dx),
      ),
      math.max(
        metrics.heightOf(leastRows),
        metrics.heightOf(origin.rowSpan) +
            (edge == DashboardResizeEdge.right ? 0 : _accumulated.dy),
      ),
    );
    _frame.value = _DragFrame(offset: Offset.zero, size: grown);

    var columnSpan = origin.columnSpan;
    var rowSpan = origin.rowSpan;
    if (edge != DashboardResizeEdge.bottom) {
      columnSpan = metrics
          .spanForWidth(grown.width)
          .clamp(leastColumns, math.max(leastColumns, columns - origin.column));
    }
    if (edge != DashboardResizeEdge.right) {
      rowSpan = math.max(leastRows, metrics.spanForHeight(grown.height));
    }
    final next = origin.copyWith(columnSpan: columnSpan, rowSpan: rowSpan);
    if (next != _livePlacement) {
      setState(() => _livePlacement = next);
    }
  }

  void _commit(
    DashboardWidgetSpec spec,
    int columns,
    bool pinned,
    DashboardGridMetrics metrics,
  ) {
    final placement = _livePlacement;
    final moving = _resizing == null;
    final pointer = _pointer;
    _stopAutoScroll();
    _accumulated = Offset.zero;
    _frame.value = null;
    setState(() {
      _activeId = null;
      _livePlacement = null;
      _originPlacement = null;
      _resizing = null;
      _frozenHeight = null;
    });
    if (placement == null) {
      return;
    }

    // Let go over another band and the widget belongs to it. Sections share a
    // width and a density, so this canvas's metrics read the target too.
    final landed = moving ? _registry?.sectionAt(pointer) : null;
    final target = landed != null && landed.id != section.id ? landed.id : null;
    final settled = target == null
        ? placement
        : placement.copyWith(row: metrics.rowAt(landed!.local.dy));

    final stored = pinned
        ? settled
        : scaleDashboardPlacement(
            settled,
            from: columns,
            to: DashboardPlacement.referenceColumns,
          );
    if (target == null && stored == spec.placement) {
      return;
    }
    controller.edit((document) {
      final next = document.withWidget(spec.copyWith(placement: stored));
      return target == null ? next : next.moveWidget(spec.id, target);
    });
  }
}

/// Where the card being moved is right now, in pixels.
@immutable
class _DragFrame {
  const _DragFrame({required this.offset, required this.size});

  final Offset offset;
  final Size size;
}

String dashboardSectionLayoutLabel(DashboardSectionLayout layout) =>
    switch (layout) {
      DashboardSectionLayout.free => LocaleKeys.dashboard_layout_free.tr(),
      DashboardSectionLayout.oneColumn =>
        LocaleKeys.dashboard_layout_oneColumn.tr(),
      DashboardSectionLayout.twoColumn =>
        LocaleKeys.dashboard_layout_twoColumn.tr(),
      DashboardSectionLayout.threeColumn =>
        LocaleKeys.dashboard_layout_threeColumn.tr(),
      DashboardSectionLayout.fourColumn =>
        LocaleKeys.dashboard_layout_fourColumn.tr(),
      DashboardSectionLayout.asymmetric =>
        LocaleKeys.dashboard_layout_asymmetric.tr(),
      DashboardSectionLayout.sidebarLeft =>
        LocaleKeys.dashboard_layout_sidebarLeft.tr(),
      DashboardSectionLayout.sidebarRight =>
        LocaleKeys.dashboard_layout_sidebarRight.tr(),
    };

IconData dashboardSectionLayoutIcon(DashboardSectionLayout layout) =>
    switch (layout) {
      DashboardSectionLayout.free => Icons.dashboard_rounded,
      DashboardSectionLayout.oneColumn => Icons.crop_16_9_rounded,
      DashboardSectionLayout.twoColumn => Icons.vertical_split_rounded,
      DashboardSectionLayout.threeColumn => Icons.view_column_rounded,
      DashboardSectionLayout.fourColumn => Icons.view_module_rounded,
      DashboardSectionLayout.asymmetric => Icons.view_quilt_rounded,
      DashboardSectionLayout.sidebarLeft => Icons.view_sidebar_rounded,
      DashboardSectionLayout.sidebarRight => Icons.vertical_split_rounded,
    };

class _Chevron extends StatelessWidget {
  const _Chevron({
    required this.collapsed,
    required this.palette,
    required this.onPressed,
  });

  final bool collapsed;
  final DashboardPalette palette;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => AnimatedRotation(
        duration: DashboardMetrics.hover,
        turns: collapsed ? -0.25 : 0,
        child: DashboardIconButton(
          icon: Icons.keyboard_arrow_down_rounded,
          palette: palette,
          size: 22,
          iconSize: 17,
          onPressed: onPressed,
        ),
      );
}
