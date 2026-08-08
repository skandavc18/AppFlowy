import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy/workspace/application/table_views/timeline_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// How a row was moved on the timeline.
typedef TimelineReschedule = Future<void> Function(
  String rowId,
  DateTime start,
  DateTime? end,
);

/// A table laid out in time.
///
/// Rows with a date become events, rows with two become bars, and rows with
/// only a beginning become milestones. The arrangement — which lane an event
/// sits on, where the ruler is marked — is worked out by [timeline_spec] as
/// plain arithmetic, so this only has to draw it.
class TimelineStage extends StatefulWidget {
  const TimelineStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.onOpenRow,
    this.onAddRow,
    this.onReschedule,
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final TimelineSpec spec;
  final ValueChanged<TimelineSpec> onSpecChanged;
  final String? title;

  final ValueChanged<String>? onOpenRow;
  final Future<String?> Function()? onAddRow;

  /// Writing a moved event back to the table.
  final TimelineReschedule? onReschedule;

  final EdgeInsets padding;

  @override
  State<TimelineStage> createState() => TimelineStageState();
}

class TimelineStageState extends State<TimelineStage> {
  late final TableRowSource _source = TableRowSource(viewId: widget.viewId);
  final ReminderStore _reminders = ReminderStore.instance;
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  final GlobalKey<TableViewHeaderState> _header =
      GlobalKey<TableViewHeaderState>();

  TableQuery _query = const TableQuery();
  List<TableRowCard> _visible = const [];
  Set<String> _matches = const {};

  /// The event being dragged, and how it is being changed.
  String? _dragging;
  _DragMode _mode = _DragMode.move;
  double _dragBy = 0;

  String? _hovered;
  Offset _hoverAt = Offset.zero;

  /// Whether the schedule has already been brought to today once.
  bool _settled = false;

  static const double laneHeight = 46;
  static const double eventHeight = 34;
  static const double rulerHeight = 34;
  static const double gutter = 20;

  /// Every event is drawn at least this wide, so it can carry its name.
  /// The lanes are worked out with the same figure, so nothing overlaps.
  static const double minimumEventWidth = 168;

  @override
  void initState() {
    super.initState();
    _source
      ..updateSpec(widget.spec.readSpec)
      ..addListener(_onSourceChanged);
    unawaited(_source.load());
    _reminders
      ..addListener(_onSourceChanged)
      ..start();
  }

  @override
  void didUpdateWidget(TimelineStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) {
      _source.updateSpec(widget.spec.readSpec);
    }
  }

  @override
  void dispose() {
    _reminders.removeListener(_onSourceChanged);
    _source.removeListener(_onSourceChanged);
    _source.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    super.dispose();
  }

  /// Reads the table again — the host calls this when a row changes.
  void reload() => _source.invalidate();

  /// The column a drag writes back into.
  String get startFieldId => _source.startColumn;

  void _onSourceChanged() {
    if (mounted) {
      setState(_refine);
      // A schedule that opens at the far left of a year-wide window shows
      // empty ruling, so it starts where today is.
      if (!_settled && _dated.isNotEmpty) {
        _settled = true;
        WidgetsBinding.instance.addPostFrameCallback((_) => _goToToday());
      }
    }
  }

  void _refine() {
    _visible = attachRemindersToCards(
      applyTableQuery(_source.cards, _query),
      _reminders.reminders,
    );
    _matches = tableMatchesOf(_visible, _query.search);
  }

  void _setQuery(TableQuery query) => setState(() {
        _query = query;
        _refine();
      });

  // ------------------------------------------------------------------ layout

  List<TableRowCard> get _dated =>
      _visible.where((card) => card.startsAt != null).toList();

  double get _dayWidth => timelineDayWidth(widget.spec.scale);

  TimelineWindow get _window => timelineWindowFor(
        [
          for (final card in _dated) ...[
            card.startsAt!,
            if (card.endsAt != null) card.endsAt!,
          ],
          DateTime.now(),
        ],
        dayWidth: _dayWidth,
        margin: widget.spec.scale.days * 2,
      );

  List<TimelineEvent> get _events => layOutTimeline(
        [
          for (final card in _dated)
            (rowId: card.rowId, start: card.startsAt!, end: card.endsAt),
        ],
        dayWidth: _dayWidth,
        minimumEventWidth: minimumEventWidth,
      );

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _header.currentState?.openSearch(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _header.currentState?.openSearch(),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _header.currentState?.closeSearch(),
      },
      child: Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(palette),
            const SizedBox(height: TableViewMetrics.space3),
            Expanded(child: _buildBody(palette)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TableViewPalette palette) => TableViewHeader(
        key: _header,
        palette: palette,
        title: widget.title?.trim().isNotEmpty == true
            ? widget.title!
            : LocaleKeys.timeline_name.tr(),
        subtitle: LocaleKeys.timeline_eventCount
            .tr(namedArgs: {'count': '${_dated.length}'}),
        columns: _source.fields,
        query: _query,
        onQueryChanged: _setQuery,
        valuesOf: (fieldId) => tableValuesOf(_source.cards, fieldId),
        onAdd: widget.onAddRow == null ? null : _addRow,
        optionsBuilder: _options,
        allowGrouping: false,
        actions: [
          _buildFlowPicker(palette),
          const SizedBox(width: TableViewMetrics.controlGap),
          if (widget.spec.flow == TimelineFlow.schedule) ...[
            TableViewButton(
              palette: palette,
              icon: Icons.today_rounded,
              tooltip: LocaleKeys.timeline_today.tr(),
              onTap: _goToToday,
            ),
            const SizedBox(width: TableViewMetrics.controlGap),
            TableViewButton(
              palette: palette,
              icon: Icons.zoom_out_rounded,
              tooltip: LocaleKeys.timeline_zoomOut.tr(),
              onTap: () => _setScale(widget.spec.scale.further),
            ),
            const SizedBox(width: 2),
            _buildScaleLabel(palette),
            const SizedBox(width: 2),
            TableViewButton(
              palette: palette,
              icon: Icons.zoom_in_rounded,
              tooltip: LocaleKeys.timeline_zoomIn.tr(),
              onTap: () => _setScale(widget.spec.scale.closer),
            ),
          ],
        ],
      );

  /// The three readings, offered as one segmented control.
  Widget _buildFlowPicker(TableViewPalette palette) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: palette.sunken,
          borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final flow in TimelineFlow.values)
              _FlowChoice(
                palette: palette,
                icon: _flowIcon(flow),
                tooltip: _flowLabel(flow),
                selected: widget.spec.flow == flow,
                onTap: () =>
                    widget.onSpecChanged(widget.spec.copyWith(flow: flow)),
              ),
          ],
        ),
      );

  static IconData _flowIcon(TimelineFlow flow) => switch (flow) {
        TimelineFlow.vertical => Icons.format_list_bulleted_rounded,
        TimelineFlow.horizontal => Icons.linear_scale_rounded,
        TimelineFlow.schedule => Icons.view_timeline_rounded,
      };

  static String _flowLabel(TimelineFlow flow) => switch (flow) {
        TimelineFlow.vertical => LocaleKeys.timeline_flowVertical.tr(),
        TimelineFlow.horizontal => LocaleKeys.timeline_flowHorizontal.tr(),
        TimelineFlow.schedule => LocaleKeys.timeline_flowSchedule.tr(),
      };

  Widget _buildScaleLabel(TableViewPalette palette) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
        ),
        child: Text(
          _scaleLabel(widget.spec.scale),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: palette.textSecondary,
          ),
        ),
      );

  static String _scaleLabel(TimelineScale scale) => switch (scale) {
        TimelineScale.day => LocaleKeys.timeline_scaleDay.tr(),
        TimelineScale.week => LocaleKeys.timeline_scaleWeek.tr(),
        TimelineScale.month => LocaleKeys.timeline_scaleMonth.tr(),
        TimelineScale.quarter => LocaleKeys.timeline_scaleQuarter.tr(),
        TimelineScale.year => LocaleKeys.timeline_scaleYear.tr(),
      };

  Widget _buildBody(TableViewPalette palette) {
    if (_source.isLoading && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.timeline_rounded,
        message: LocaleKeys.tableViews_loading.tr(),
      );
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.timeline_rounded,
        message: LocaleKeys.tableViews_couldNotRead.tr(),
        detail: error,
        actionLabel: LocaleKeys.tableViews_tryAgain.tr(),
        onAction: reload,
      );
    }
    if (_source.startColumn.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.event_rounded,
        message: LocaleKeys.timeline_noDates.tr(),
        detail: LocaleKeys.timeline_noDatesDetail.tr(),
      );
    }
    if (_dated.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.timeline_rounded,
        message: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatch.tr()
            : LocaleKeys.timeline_empty.tr(),
        detail: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatchDetail.tr()
            : LocaleKeys.timeline_emptyDetail.tr(),
        actionLabel: _query.isFiltering
            ? LocaleKeys.tableViews_clearFilter.tr()
            : LocaleKeys.tableViews_addRow.tr(),
        onAction: _query.isFiltering
            ? () => _setQuery(
                  _query.copyWith(filterColumn: '', filterValue: ''),
                )
            : (widget.onAddRow == null ? null : _addRow),
      );
    }

    return switch (widget.spec.flow) {
      TimelineFlow.vertical => _buildVertical(palette),
      TimelineFlow.horizontal => _buildHorizontal(palette),
      TimelineFlow.schedule => _buildTimeline(palette),
    };
  }

  /// The rows in the order they happen, newest last.
  List<TableRowCard> get _inOrder =>
      [..._dated]..sort((a, b) => a.startsAt!.compareTo(b.startsAt!));

  /// A spine down the middle, with each event on alternating sides.
  Widget _buildVertical(TableViewPalette palette) {
    final cards = _inOrder;
    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this there is no room for two columns, so the spine moves to
        // the left and every card hangs off it the same way.
        final split = constraints.maxWidth >= 720;
        return Scrollbar(
          controller: _vertical,
          child: ListView.builder(
            controller: _vertical,
            padding: const EdgeInsets.symmetric(vertical: 12),
            itemCount: cards.length,
            itemBuilder: (context, index) => _VerticalEvent(
              palette: palette,
              card: cards[index],
              colour: _colourOf(palette, cards[index]),
              split: split,
              onLeft: split && index.isEven,
              first: index == 0,
              last: index == cards.length - 1,
              quiet:
                  _query.isSearching && !_matches.contains(cards[index].rowId),
              onOpen: () => widget.onOpenRow?.call(cards[index].rowId),
              onContextMenu: (at) => _showRowMenu(cards[index], at),
            ),
          ),
        );
      },
    );
  }

  /// A track running left to right, with events hung above and below it.
  Widget _buildHorizontal(TableViewPalette palette) {
    final cards = _inOrder;
    const stride = 210.0;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        boxShadow: palette.cardShadow(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        child: Scrollbar(
          controller: _horizontal,
          child: SingleChildScrollView(
            controller: _horizontal,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: SizedBox(
              width: math.max(cards.length * stride + 64, 640),
              height: double.infinity,
              child: Stack(
                children: [
                  Positioned(
                    left: stride / 2,
                    right: stride / 2,
                    top: 0,
                    bottom: 0,
                    child: CustomPaint(
                      painter: _TimelineTrackPainter(
                        rail: palette.border.withValues(alpha: 0.55),
                        done: palette.accent,
                        // The track fills as far as today has reached.
                        progress: _progressThrough(cards),
                      ),
                    ),
                  ),
                  Row(
                    children: [
                      for (var i = 0; i < cards.length; i++)
                        SizedBox(
                          width: stride,
                          child: _HorizontalEvent(
                            palette: palette,
                            card: cards[i],
                            colour: _colourOf(palette, cards[i]),
                            above: i.isEven,
                            passed: !cards[i].startsAt!.isAfter(DateTime.now()),
                            quiet: _query.isSearching &&
                                !_matches.contains(cards[i].rowId),
                            onOpen: () =>
                                widget.onOpenRow?.call(cards[i].rowId),
                            onContextMenu: (at) => _showRowMenu(cards[i], at),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// How far along the run of events today stands, from 0 to 1.
  double _progressThrough(List<TableRowCard> cards) {
    if (cards.length < 2) {
      return cards.isEmpty || cards.first.startsAt!.isAfter(DateTime.now())
          ? 0
          : 1;
    }
    final passed =
        cards.where((card) => !card.startsAt!.isAfter(DateTime.now())).length;
    return ((passed - 0.5) / (cards.length - 1)).clamp(0.0, 1.0);
  }

  Color _colourOf(TableViewPalette palette, TableRowCard card) =>
      palette.swatchFor(card.accent.isEmpty ? card.title : card.accent);

  Widget _buildTimeline(TableViewPalette palette) {
    final window = _window;
    final events = _events;
    final lanes = events.fold<int>(0, (most, e) => math.max(most, e.lane + 1));
    final byId = {for (final card in _visible) card.rowId: card};

    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        boxShadow: palette.cardShadow(),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The ruler and the grid fill the card whatever the dates cover,
            // so a short run does not leave the right-hand side blank.
            final width = math.max(window.width, constraints.maxWidth);
            final body = math.max(
              lanes * laneHeight + gutter,
              constraints.maxHeight - rulerHeight,
            );
            return Scrollbar(
              controller: _horizontal,
              child: SingleChildScrollView(
                controller: _horizontal,
                scrollDirection: Axis.horizontal,
                child: SizedBox(
                  width: width,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildRuler(palette, window),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: _vertical,
                          child: SizedBox(
                            height: body,
                            child: MouseRegion(
                              opaque: false,
                              onHover: (event) {
                                if (_hovered != null) {
                                  setState(
                                    () => _hoverAt = event.localPosition,
                                  );
                                }
                              },
                              child: Stack(
                                clipBehavior: Clip.none,
                                children: [
                                  Positioned.fill(
                                    child: CustomPaint(
                                      painter: _TimelineGridPainter(
                                        window: window,
                                        scale: widget.spec.scale,
                                        line: palette.border
                                            .withValues(alpha: 0.5),
                                        today: palette.accent,
                                        lanes: lanes,
                                        laneHeight: laneHeight,
                                        gutter: gutter,
                                        lane: palette.sunken
                                            .withValues(alpha: 0.45),
                                      ),
                                    ),
                                  ),
                                  for (final event in events)
                                    _buildEvent(palette, window, event, byId),
                                  if (_hovered != null &&
                                      byId[_hovered] != null)
                                    _buildPreview(palette, byId[_hovered]!),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildRuler(TableViewPalette palette, TimelineWindow window) {
    // A tick that starts before the window would have its name clipped by the
    // edge, so the leading part is ruled but not labelled.
    final ticks = timelineTicks(window, widget.spec.scale)
        .where((tick) => window.xOf(tick) >= 0)
        .toList();
    return Container(
      height: rulerHeight,
      decoration: BoxDecoration(
        color: palette.sunken.withValues(alpha: 0.55),
        border: Border(
          bottom: BorderSide(
            color: palette.border.withValues(alpha: 0.55),
          ),
        ),
      ),
      child: ClipRect(
        child: Stack(
          children: [
            for (final tick in ticks)
              Positioned(
                left: window.xOf(tick),
                top: 0,
                bottom: 0,
                child: Row(
                  children: [
                    Container(
                      width: 1,
                      height: 9,
                      margin: const EdgeInsets.only(top: 12),
                      color: palette.border.withValues(alpha: 0.8),
                    ),
                    const SizedBox(width: 7),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        timelineTickLabel(tick, widget.spec.scale),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 0.2,
                          color: palette.textMuted,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEvent(
    TableViewPalette palette,
    TimelineWindow window,
    TimelineEvent event,
    Map<String, TableRowCard> byId,
  ) {
    final card = byId[event.rowId];
    if (card == null) {
      return const SizedBox.shrink();
    }
    final dragging = _dragging == event.rowId;
    final shift = dragging && _mode == _DragMode.move ? _dragBy : 0.0;
    final stretch = dragging && _mode == _DragMode.end ? _dragBy : 0.0;
    final pull = dragging && _mode == _DragMode.start ? _dragBy : 0.0;

    final left = window.xOf(event.start) + shift + pull;
    final rawWidth = window.xOf(event.end) - window.xOf(event.start);
    // Even a single day is drawn wide enough to be read, so every row on the
    // timeline is a named card rather than a dot.
    final width = math.max(minimumEventWidth, rawWidth + stretch - pull);
    final colour =
        palette.swatchFor(card.accent.isEmpty ? card.title : card.accent);
    final quiet = _query.isSearching && !_matches.contains(card.rowId);

    return AnimatedPositioned(
      duration: dragging ? Duration.zero : TableViewMetrics.change,
      curve: TableViewMetrics.settleCurve,
      left: left,
      top: event.lane * laneHeight + gutter / 2,
      width: width,
      height: eventHeight,
      child: Opacity(
        opacity: quiet ? 0.35 : 1,
        child: _TimelineEventBar(
          palette: palette,
          card: card,
          colour: colour,
          isMilestone: event.isMilestone && widget.spec.showMilestones,
          canDrag: widget.onReschedule != null,
          onOpen: () => widget.onOpenRow?.call(card.rowId),
          onContextMenu: (position) => _showRowMenu(card, position),
          onHover: (on, at) => setState(() {
            _hovered =
                on ? card.rowId : (_hovered == card.rowId ? null : _hovered);
            _hoverAt = at;
          }),
          onDragStart: (mode) => setState(() {
            _dragging = card.rowId;
            _mode = mode;
            _dragBy = 0;
          }),
          onDragUpdate: (by) => setState(() => _dragBy += by),
          onDragEnd: () => unawaited(_commitDrag(event, window)),
        ),
      ),
    );
  }

  /// The card that floats beside an event while the pointer rests on it.
  Widget _buildPreview(TableViewPalette palette, TableRowCard card) {
    const width = 268.0;
    final properties = card.filled.take(4).toList();
    return Positioned(
      left: _hoverAt.dx + 16,
      top: _hoverAt.dy + 14,
      width: width,
      child: IgnorePointer(
        child: AnimatedOpacity(
          duration: TableViewMetrics.hover,
          opacity: 1,
          child: Container(
            padding: const EdgeInsets.all(TableViewMetrics.space3),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(TableViewMetrics.panelRadius),
              boxShadow: palette.cardShadow(),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  card.title.trim().isEmpty ? '—' : card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
                if (card.reminderAt case final at?) ...[
                  const SizedBox(height: TableViewMetrics.space2),
                  Row(
                    children: [
                      Icon(
                        card.reminderDone
                            ? Icons.notifications_off_rounded
                            : Icons.notifications_rounded,
                        size: 12,
                        color: card.reminderDone
                            ? palette.textMuted
                            : palette.accent,
                      ),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          DateFormat.MMMEd().add_jm().format(at),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: palette.textSecondary,
                            decoration: card.reminderDone
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                for (final property in properties) ...[
                  const SizedBox(height: TableViewMetrics.space3),
                  TablePropertyView(
                    property: property,
                    palette: palette,
                    compact: true,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _commitDrag(TimelineEvent event, TimelineWindow window) async {
    final reschedule = widget.onReschedule;
    final by = _dragBy;
    final mode = _mode;
    setState(() {
      _dragging = null;
      _dragBy = 0;
    });
    if (reschedule == null || by.abs() < 1) {
      return;
    }
    // A day is the smallest thing a reader can aim at, so a drag lands on one
    // rather than somewhere between two.
    final days = (by / window.dayWidth).round();
    if (days == 0) {
      return;
    }
    final shift = Duration(days: days);
    final start = switch (mode) {
      _DragMode.move => event.start.add(shift),
      _DragMode.start => event.start.add(shift),
      _DragMode.end => event.start,
    };
    final end = switch (mode) {
      _DragMode.move => event.isMilestone ? null : event.end.add(shift),
      _DragMode.start => event.isMilestone ? null : event.end,
      _DragMode.end => event.end.add(shift),
    };
    if (end != null && !end.isAfter(start)) {
      return;
    }
    await reschedule(event.rowId, start, end);
    reload();
  }

  // ------------------------------------------------------------------ action

  void _setScale(TimelineScale scale) {
    if (scale == widget.spec.scale) {
      return;
    }
    widget.onSpecChanged(widget.spec.copyWith(scale: scale));
  }

  void _goToToday() {
    if (!_horizontal.hasClients) {
      return;
    }
    final window = _window;
    final at = window.xOf(DateTime.now()) - 160;
    unawaited(
      _horizontal.animateTo(
        at.clamp(0, _horizontal.position.maxScrollExtent),
        duration: TableViewMetrics.settle,
        curve: TableViewMetrics.settleCurve,
      ),
    );
  }

  void _addRow() {
    final add = widget.onAddRow;
    if (add == null) {
      return;
    }
    unawaited(add());
  }

  List<AppMenuEntry> _options() => [
        AppMenuHeader(LocaleKeys.tableViews_options.tr()),
        AppMenuItem(
          label: LocaleKeys.timeline_milestones.tr(),
          icon: Icons.change_history_rounded,
          selected: widget.spec.showMilestones,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(showMilestones: !widget.spec.showMilestones),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.timeline_startColumn.tr(),
          icon: Icons.play_arrow_rounded,
          submenu: _dateColumnEntries(
            chosen: _source.startColumn,
            onPicked: (id) =>
                widget.onSpecChanged(widget.spec.copyWith(startColumn: id)),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.timeline_endColumn.tr(),
          icon: Icons.stop_rounded,
          submenu: _dateColumnEntries(
            chosen: _source.endColumn,
            onPicked: (id) =>
                widget.onSpecChanged(widget.spec.copyWith(endColumn: id)),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.tableViews_reload.tr(),
          icon: Icons.refresh_rounded,
          onSelected: reload,
        ),
      ];

  List<AppMenuEntry> _dateColumnEntries({
    required String chosen,
    required ValueChanged<String> onPicked,
  }) =>
      [
        for (final field in _source.fields)
          if (isTableDateField(field))
            AppMenuItem(
              label: field.name,
              selected: chosen == field.id,
              onSelected: () => onPicked(field.id),
            ),
      ];

  Future<void> _showRowMenu(TableRowCard card, Offset position) async {
    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: LocaleKeys.tableViews_openRow.tr(),
          icon: Icons.open_in_new_rounded,
          enabled: widget.onOpenRow != null,
          onSelected: () => widget.onOpenRow?.call(card.rowId),
        ),
        AppMenuItem(
          label: LocaleKeys.tableViews_copyTitle.tr(),
          icon: Icons.copy_rounded,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: card.title))),
        ),
        const AppMenuSeparator(),
        ..._options(),
      ],
    );
  }
}

enum _DragMode { move, start, end }

/// One of the three readings, offered as a segment of a control.
class _FlowChoice extends StatefulWidget {
  const _FlowChoice({
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final TableViewPalette palette;
  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_FlowChoice> createState() => _FlowChoiceState();
}

class _FlowChoiceState extends State<_FlowChoice> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: TableViewMetrics.hover,
            curve: TableViewMetrics.enterCurve,
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
            decoration: BoxDecoration(
              color: widget.selected
                  ? palette.raised
                  : (_hovered ? palette.hover : palette.hoverAtRest),
              borderRadius: BorderRadius.circular(7),
              boxShadow:
                  widget.selected ? palette.cardShadow(prominence: 0.6) : null,
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: widget.selected ? palette.accent : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// One event on the vertical spine: a dated card beside a marked node.
class _VerticalEvent extends StatefulWidget {
  const _VerticalEvent({
    required this.palette,
    required this.card,
    required this.colour,
    required this.split,
    required this.onLeft,
    required this.first,
    required this.last,
    required this.quiet,
    required this.onOpen,
    required this.onContextMenu,
  });

  final TableViewPalette palette;
  final TableRowCard card;
  final Color colour;

  /// Whether there is room to hang cards either side of the spine.
  final bool split;
  final bool onLeft;
  final bool first;
  final bool last;
  final bool quiet;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_VerticalEvent> createState() => _VerticalEventState();
}

class _VerticalEventState extends State<_VerticalEvent> {
  static const double spine = 64;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final card = _TimelineCard(
      palette: palette,
      card: widget.card,
      colour: widget.colour,
      alignEnd: widget.split && widget.onLeft,
      onOpen: widget.onOpen,
      onContextMenu: widget.onContextMenu,
    );

    return Opacity(
      opacity: widget.quiet ? 0.4 : 1,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (widget.split)
              Expanded(
                child: widget.onLeft
                    ? Padding(
                        padding: const EdgeInsets.only(bottom: 18),
                        child: card,
                      )
                    : const SizedBox.shrink(),
              ),
            SizedBox(
              width: spine,
              child: _Spine(
                palette: palette,
                colour: widget.colour,
                date: widget.card.startsAt!,
                first: widget.first,
                last: widget.last,
              ),
            ),
            Expanded(
              child: widget.split && widget.onLeft
                  ? const SizedBox.shrink()
                  : Padding(
                      padding: const EdgeInsets.only(bottom: 18),
                      child: card,
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// The rail behind the events, and the node this one sits at.
class _Spine extends StatelessWidget {
  const _Spine({
    required this.palette,
    required this.colour,
    required this.date,
    required this.first,
    required this.last,
  });

  final TableViewPalette palette;
  final Color colour;
  final DateTime date;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    final rail = palette.border.withValues(alpha: 0.6);
    const centre = 22.0;
    return Stack(
      alignment: Alignment.topCenter,
      children: [
        // The rail arrives from above and leaves below, so the run reads as
        // one line rather than a column of separate marks.
        if (!first)
          Positioned(
            top: 0,
            height: centre,
            width: 2,
            child: ColoredBox(color: rail),
          ),
        if (!last)
          Positioned(
            top: centre,
            bottom: 0,
            width: 2,
            child: ColoredBox(color: rail),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: colour, width: 2.5),
              boxShadow: palette.cardShadow(prominence: 0.7),
            ),
          ),
        ),
      ],
    );
  }
}

/// The card an event is written on, wherever it is hung.
class _TimelineCard extends StatefulWidget {
  const _TimelineCard({
    required this.palette,
    required this.card,
    required this.colour,
    required this.onOpen,
    required this.onContextMenu,
    this.alignEnd = false,
    this.compact = false,
  });

  final TableViewPalette palette;
  final TableRowCard card;
  final Color colour;
  final bool alignEnd;
  final bool compact;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onContextMenu;

  @override
  State<_TimelineCard> createState() => _TimelineCardState();
}

class _TimelineCardState extends State<_TimelineCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final card = widget.card;
    final detail = card.subtitle.trim();

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTapUp: (details) =>
            widget.onContextMenu(details.globalPosition),
        child: AnimatedContainer(
          duration: TableViewMetrics.hover,
          curve: TableViewMetrics.enterCurve,
          transform: Matrix4.translationValues(0, _hovered ? -2 : 0, 0),
          padding: const EdgeInsets.fromLTRB(16, 13, 16, 14),
          decoration: BoxDecoration(
            color: palette.raised,
            borderRadius: BorderRadius.circular(TableViewMetrics.panelRadius),
            boxShadow: palette.cardShadow(
              prominence: _hovered ? 1 : 0.7,
              lift: _hovered ? 3 : 0,
            ),
          ),
          child: Column(
            crossAxisAlignment: widget.alignEnd
                ? CrossAxisAlignment.end
                : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: widget.alignEnd
                    ? MainAxisAlignment.end
                    : MainAxisAlignment.start,
                children: [
                  Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: widget.colour,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(width: 7),
                  Text(
                    _dayLabel(card.startsAt!),
                    style: TextStyle(
                      fontSize: 10.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.6,
                      color: palette.textMuted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 7),
              Text(
                card.title.trim().isEmpty
                    ? LocaleKeys.grid_row_titlePlaceholder.tr()
                    : card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.alignEnd ? TextAlign.end : TextAlign.start,
                style: TextStyle(
                  fontSize: 14.5,
                  height: 1.3,
                  fontWeight: FontWeight.w600,
                  color: palette.textPrimary,
                ),
              ),
              if (detail.isNotEmpty && !widget.compact) ...[
                const SizedBox(height: 5),
                Text(
                  detail,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: widget.alignEnd ? TextAlign.end : TextAlign.start,
                  style: TextStyle(
                    fontSize: 12.5,
                    height: 1.45,
                    color: palette.textSecondary,
                  ),
                ),
              ],
              if (!widget.compact && card.filled.isNotEmpty) ...[
                const SizedBox(height: 10),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  alignment:
                      widget.alignEnd ? WrapAlignment.end : WrapAlignment.start,
                  children: [
                    for (final property in card.filled.take(3))
                      TablePropertyView(
                        property: property,
                        palette: palette,
                        showLabel: false,
                        compact: true,
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// One event on the horizontal track: a node with its card above or below.
class _HorizontalEvent extends StatelessWidget {
  const _HorizontalEvent({
    required this.palette,
    required this.card,
    required this.colour,
    required this.above,
    required this.passed,
    required this.quiet,
    required this.onOpen,
    required this.onContextMenu,
  });

  final TableViewPalette palette;
  final TableRowCard card;
  final Color colour;
  final bool above;
  final bool passed;
  final bool quiet;
  final VoidCallback onOpen;
  final ValueChanged<Offset> onContextMenu;

  @override
  Widget build(BuildContext context) {
    final entry = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: _TimelineCard(
        palette: palette,
        card: card,
        colour: colour,
        compact: true,
        onOpen: onOpen,
        onContextMenu: onContextMenu,
      ),
    );

    return Opacity(
      opacity: quiet ? 0.4 : 1,
      child: Column(
        children: [
          Expanded(
            child: above
                ? Align(alignment: Alignment.bottomCenter, child: entry)
                : const SizedBox.shrink(),
          ),
          const SizedBox(height: 12),
          _TrackNode(palette: palette, colour: colour, passed: passed),
          const SizedBox(height: 12),
          Expanded(
            child: above
                ? const SizedBox.shrink()
                : Align(alignment: Alignment.topCenter, child: entry),
          ),
        ],
      ),
    );
  }
}

/// The mark an event leaves on the horizontal track.
class _TrackNode extends StatelessWidget {
  const _TrackNode({
    required this.palette,
    required this.colour,
    required this.passed,
  });

  final TableViewPalette palette;
  final Color colour;
  final bool passed;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 30,
      height: 30,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: passed ? colour : palette.surface,
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: passed ? colour : palette.border.withValues(alpha: 0.9),
          width: 2,
        ),
        boxShadow: palette.cardShadow(prominence: 0.7),
      ),
      child: passed
          ? const Icon(Icons.check_rounded, size: 15, color: Colors.white)
          : Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: palette.textMuted,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
    );
  }
}

/// The rail the horizontal events stand on, filled as far as today.
class _TimelineTrackPainter extends CustomPainter {
  const _TimelineTrackPainter({
    required this.rail,
    required this.done,
    required this.progress,
  });

  final Color rail;
  final Color done;
  final double progress;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    final line = Paint()
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(0, y), Offset(size.width, y), line..color = rail);
    if (progress > 0) {
      canvas.drawLine(
        Offset(0, y),
        Offset(size.width * progress, y),
        line..color = done,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelineTrackPainter old) =>
      old.progress != progress || old.rail != rail || old.done != done;
}

/// The day an event falls on, in the shape a date badge wants.
String _dayLabel(DateTime when) =>
    DateFormat('MMM d, yyyy').format(when).toUpperCase();

/// One event, and the handles that let it be moved and stretched.
class _TimelineEventBar extends StatefulWidget {
  const _TimelineEventBar({
    required this.palette,
    required this.card,
    required this.colour,
    required this.isMilestone,
    required this.canDrag,
    required this.onOpen,
    required this.onContextMenu,
    required this.onHover,
    required this.onDragStart,
    required this.onDragUpdate,
    required this.onDragEnd,
  });

  final TableViewPalette palette;
  final TableRowCard card;
  final Color colour;
  final bool isMilestone;
  final bool canDrag;
  final VoidCallback onOpen;
  final void Function(Offset globalPosition) onContextMenu;
  final void Function(bool hovering, Offset at) onHover;
  final void Function(_DragMode mode) onDragStart;
  final ValueChanged<double> onDragUpdate;
  final VoidCallback onDragEnd;

  @override
  State<_TimelineEventBar> createState() => _TimelineEventBarState();
}

class _TimelineEventBarState extends State<_TimelineEventBar> {
  bool _hovered = false;

  static const double handleWidth = 8;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final colour = widget.colour;

    final body = AnimatedContainer(
      duration: TableViewMetrics.hover,
      curve: TableViewMetrics.enterCurve,
      transform: Matrix4.translationValues(0, _hovered ? -1.5 : 0, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            colour.withValues(alpha: palette.isDark ? 0.42 : 0.24),
            colour.withValues(alpha: palette.isDark ? 0.26 : 0.13),
          ],
        ),
        borderRadius: BorderRadius.circular(9),
        border: Border.all(
          color: colour.withValues(alpha: _hovered ? 0.6 : 0.34),
        ),
        boxShadow: palette.cardShadow(
          prominence: _hovered ? 1 : 0.5,
          lift: _hovered ? 2 : 0,
        ),
      ),
      // A milestone is a moment rather than a stretch, so it is marked with a
      // square instead of a run, but it is still a card carrying its name.
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          children: [
            if (widget.isMilestone)
              Container(
                width: 9,
                height: 9,
                margin: const EdgeInsets.fromLTRB(9, 6, 8, 6),
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(2),
                ),
              )
            else
              Container(
                width: 3,
                margin: const EdgeInsets.fromLTRB(5, 6, 7, 6),
                decoration: BoxDecoration(
                  color: colour,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            // Below this there is no room for a name, and a clipped word
            // reads worse than none.
            if (constraints.maxWidth >= 58)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(right: 9),
                  child: Text(
                    widget.card.title.trim().isEmpty ? '—' : widget.card.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12.5,
                      height: 1.1,
                      fontWeight: FontWeight.w600,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
              ),
            // A reminder is a marker, never a badge: the bell says there is
            // one and hovering the bar says when.
            if (widget.card.hasReminder && constraints.maxWidth >= 44)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: Icon(
                  widget.card.reminderDone
                      ? Icons.notifications_off_rounded
                      : widget.card.reminderRepeats
                          ? Icons.notifications_active_rounded
                          : Icons.notifications_rounded,
                  size: 12,
                  color: widget.card.reminderDone ? palette.textMuted : colour,
                ),
              ),
          ],
        ),
      ),
    );

    return MouseRegion(
      opaque: false,
      cursor: SystemMouseCursors.click,
      onEnter: (event) {
        setState(() => _hovered = true);
        widget.onHover(true, event.position);
      },
      onExit: (_) {
        setState(() => _hovered = false);
        widget.onHover(false, Offset.zero);
      },
      child: GestureDetector(
        onTap: widget.onOpen,
        onSecondaryTapUp: (details) =>
            widget.onContextMenu(details.globalPosition),
        onHorizontalDragStart:
            widget.canDrag ? (_) => widget.onDragStart(_DragMode.move) : null,
        onHorizontalDragUpdate:
            widget.canDrag ? (d) => widget.onDragUpdate(d.delta.dx) : null,
        onHorizontalDragEnd: widget.canDrag ? (_) => widget.onDragEnd() : null,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(child: body),
            if (widget.canDrag && !widget.isMilestone) ...[
              _buildHandle(alignLeft: true),
              _buildHandle(alignLeft: false),
            ],
          ],
        ),
      ),
    );
  }

  /// The grab strips that stretch an event rather than move it.
  Widget _buildHandle({required bool alignLeft}) => Positioned(
        left: alignLeft ? 0 : null,
        right: alignLeft ? null : 0,
        top: 0,
        bottom: 0,
        width: handleWidth,
        child: MouseRegion(
          cursor: SystemMouseCursors.resizeLeftRight,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onHorizontalDragStart: (_) =>
                widget.onDragStart(alignLeft ? _DragMode.start : _DragMode.end),
            onHorizontalDragUpdate: (d) => widget.onDragUpdate(d.delta.dx),
            onHorizontalDragEnd: (_) => widget.onDragEnd(),
            child: AnimatedOpacity(
              duration: TableViewMetrics.hover,
              opacity: _hovered ? 1 : 0,
              child: Center(
                child: Container(
                  width: 3,
                  height: 14,
                  decoration: BoxDecoration(
                    color: widget.colour,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

/// The ruled lines behind the events, and the mark for today.
class _TimelineGridPainter extends CustomPainter {
  const _TimelineGridPainter({
    required this.window,
    required this.scale,
    required this.line,
    required this.today,
    required this.lanes,
    required this.laneHeight,
    required this.gutter,
    required this.lane,
  });

  final TimelineWindow window;
  final TimelineScale scale;
  final Color line;
  final Color today;

  /// How many rows of events there are, and how tall each one stands.
  final int lanes;
  final double laneHeight;
  final double gutter;
  final Color lane;

  @override
  void paint(Canvas canvas, Size size) {
    // Every other row is washed, so a bar reads as sitting on a line rather
    // than floating in the middle of the card.
    final band = Paint()..color = lane;
    for (var i = 0; i < lanes; i++) {
      if (i.isOdd) {
        canvas.drawRect(
          Rect.fromLTWH(0, gutter / 2 + i * laneHeight, size.width, laneHeight),
          band,
        );
      }
    }

    final rule = Paint()
      ..color = line
      ..strokeWidth = 1;
    for (final tick in timelineTicks(window, scale)) {
      final x = window.xOf(tick);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), rule);
    }

    final now = DateTime.now();
    if (now.isAfter(window.first) && now.isBefore(window.last)) {
      final x = window.xOf(now);
      // A soft wash behind the line so today reads without shouting.
      canvas.drawRect(
        Rect.fromLTWH(x - 5, 0, 10, size.height),
        Paint()..color = today.withValues(alpha: 0.07),
      );
      canvas.drawLine(
        Offset(x, 0),
        Offset(x, size.height),
        Paint()
          ..color = today.withValues(alpha: 0.7)
          ..strokeWidth = 1.4,
      );
    }
  }

  @override
  bool shouldRepaint(_TimelineGridPainter old) =>
      old.window.first != window.first ||
      old.window.dayWidth != window.dayWidth ||
      old.scale != scale ||
      old.lanes != lanes ||
      old.line != line;
}
