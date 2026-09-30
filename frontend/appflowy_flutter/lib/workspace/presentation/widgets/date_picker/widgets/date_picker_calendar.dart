import 'dart:math' as math;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'date_picker.dart';

/// What [DatePickerCalendar] shows below its header.
enum DatePickerView { days, months, years }

const _gap = 6.0;
const _yearColumns = 4;

Duration _motion(BuildContext context) =>
    MediaQuery.maybeDisableAnimationsOf(context) ?? false
        ? Duration.zero
        : const Duration(milliseconds: 180);

double _cellHeight(BuildContext context) =>
    math.max(34.0, MediaQuery.textScalerOf(context).scale(13.5) + 18);

String? _locale(BuildContext context) =>
    Localizations.maybeLocaleOf(context)?.toLanguageTag();

/// A month of days under a header whose month and year each open a list to
/// jump straight to, instead of paging one month at a time.
class DatePickerCalendar extends StatefulWidget {
  const DatePickerCalendar({
    super.key,
    required this.focusedDay,
    required this.onFocusedDayChanged,
    this.isRange = false,
    this.selectedDay,
    this.startDay,
    this.endDay,
    this.onDaySelected,
    this.onRangeSelected,
    this.firstDay,
    this.lastDay,
    this.currentDay,
    this.horizontalPadding = 16,
    this.traversable = true,
  });

  /// Any day of the month on screen.
  final DateTime focusedDay;

  /// Called when paging, or choosing a month or year, moves the calendar.
  final ValueChanged<DateTime> onFocusedDayChanged;

  final bool isRange;
  final DateTime? selectedDay;
  final DateTime? startDay;
  final DateTime? endDay;
  final void Function(DateTime selectedDay, DateTime focusedDay)? onDaySelected;
  final void Function(DateTime? start, DateTime? end, DateTime focusedDay)?
      onRangeSelected;

  /// The earliest and latest days offered. Default to [kFirstDay] and
  /// [kLastDay].
  final DateTime? firstDay;
  final DateTime? lastDay;

  /// The day marked as today. Defaults to the device's date.
  final DateTime? currentDay;

  final double horizontalPadding;

  /// Whether Tab reaches the header and the month and year lists.
  final bool traversable;

  @override
  State<DatePickerCalendar> createState() => _DatePickerCalendarState();
}

class _DatePickerCalendarState extends State<DatePickerCalendar> {
  DatePickerView _view = DatePickerView.days;
  PageController? _pages;

  /// A fresh key per visit, so a year list still fading out never shares one
  /// with the list fading in.
  GlobalKey<_YearGridState> _years = GlobalKey();

  DateTime get _first => widget.firstDay ?? kFirstDay;
  DateTime get _last => widget.lastDay ?? kLastDay;
  DateTime get _today => widget.currentDay ?? DateTime.now();

  /// [year] and [month] as the first of a month the range allows.
  DateTime _monthWithin(int year, int month) {
    final first = DateTime(_first.year, _first.month);
    final last = DateTime(_last.year, _last.month);
    final day = DateTime(year, month);
    return day.isBefore(first)
        ? first
        : day.isAfter(last)
            ? last
            : day;
  }

  DateTime _dayWithin(DateTime day) {
    final date = DateTime(day.year, day.month, day.day);
    final first = DateTime(_first.year, _first.month, _first.day);
    final last = DateTime(_last.year, _last.month, _last.day);
    return date.isBefore(first)
        ? first
        : date.isAfter(last)
            ? last
            : day;
  }

  void _toggle(DatePickerView view) => setState(() {
        _view = _view == view ? DatePickerView.days : view;
        if (_view == DatePickerView.years) _years = GlobalKey();
      });

  void _jump(DateTime month) {
    setState(() => _view = DatePickerView.days);
    widget.onFocusedDayChanged(month);
  }

  void _step(int direction) {
    switch (_view) {
      case DatePickerView.days:
        final pages = _pages;
        if (pages == null || !pages.hasClients) return;
        const duration = Duration(milliseconds: 300);
        direction < 0
            ? pages.previousPage(duration: duration, curve: Curves.easeOut)
            : pages.nextPage(duration: duration, curve: Curves.easeOut);
      case DatePickerView.months:
        final day = widget.focusedDay;
        final next = _monthWithin(day.year + direction, day.month);
        if (next.year != day.year) widget.onFocusedDayChanged(next);
      case DatePickerView.years:
        _years.currentState?.page(direction);
    }
  }

  @override
  Widget build(BuildContext context) {
    final motion = _motion(context);
    final focused = _dayWithin(widget.focusedDay);
    final Widget body = switch (_view) {
      DatePickerView.days => DatePicker(
          key: const ValueKey('date_picker_days'),
          isRange: widget.isRange,
          selectedDay: widget.selectedDay,
          startDay: widget.startDay,
          endDay: widget.endDay,
          focusedDay: focused,
          firstDay: _first,
          lastDay: _last,
          currentDay: widget.currentDay,
          horizontalPadding: widget.horizontalPadding,
          onDaySelected: widget.onDaySelected,
          onRangeSelected: widget.onRangeSelected,
          onCalendarCreated: (controller) => _pages = controller,
          onPageChanged: (day) => widget.onFocusedDayChanged(
            DateTime(day.year, day.month, day.day),
          ),
        ),
      DatePickerView.months => _MonthGrid(
          key: const ValueKey('date_picker_month_grid'),
          shown: focused,
          today: _today,
          first: _monthWithin(_first.year, _first.month),
          last: _monthWithin(_last.year, _last.month),
          padding: widget.horizontalPadding,
          onPicked: (month) => _jump(_monthWithin(focused.year, month)),
        ),
      DatePickerView.years => _YearGrid(
          key: _years,
          shown: focused.year,
          today: _today.year,
          first: _first.year,
          last: _last.year,
          padding: widget.horizontalPadding,
          onPicked: (year) => _jump(_monthWithin(year, focused.month)),
        ),
    };
    return ExcludeFocusTraversal(
      excluding: !widget.traversable,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(context, focused),
          const SizedBox(height: 10),
          ClipRect(
            child: AnimatedSize(
              duration: motion,
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: AnimatedSwitcher(
                duration: motion,
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: Tween(begin: 0.97, end: 1.0).animate(animation),
                    child: child,
                  ),
                ),
                // Only the incoming view sizes the calendar; outgoing views
                // fade out on top of it.
                layoutBuilder: (current, previous) => Stack(
                  alignment: Alignment.topCenter,
                  children: [
                    for (final child in previous)
                      Positioned(top: 0, left: 0, right: 0, child: child),
                    if (current != null) current,
                  ],
                ),
                child: body,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context, DateTime focused) {
    final localizations = MaterialLocalizations.of(context);
    final locale = _locale(context);
    final month = DateFormat.MMMM(locale).format(focused);
    final year = DateFormat.y(locale).format(focused);
    final days = _view == DatePickerView.days;
    return Padding(
      padding: EdgeInsetsDirectional.only(
        start: widget.horizontalPadding,
        end: widget.horizontalPadding + 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: _HeaderButton(
                    key: const ValueKey('date_picker_month_button'),
                    label: month,
                    semanticsLabel: month,
                    open: _view == DatePickerView.months,
                    strong: true,
                    onTap: () => _toggle(DatePickerView.months),
                  ),
                ),
                const SizedBox(width: 2),
                _HeaderButton(
                  key: const ValueKey('date_picker_year_button'),
                  label: year,
                  semanticsLabel:
                      '$year, ${localizations.selectYearSemanticsLabel}',
                  open: _view == DatePickerView.years,
                  onTap: () => _toggle(DatePickerView.years),
                ),
              ],
            ),
          ),
          _ArrowButton(
            key: const ValueKey('date_picker_previous'),
            icon: FlowySvgs.arrow_left_s,
            semanticsLabel: days
                ? localizations.previousMonthTooltip
                : localizations.previousPageTooltip,
            onTap: () => _step(-1),
          ),
          const SizedBox(width: 4),
          _ArrowButton(
            key: const ValueKey('date_picker_next'),
            icon: FlowySvgs.arrow_right_s,
            semanticsLabel: days
                ? localizations.nextMonthTooltip
                : localizations.nextPageTooltip,
            onTap: () => _step(1),
          ),
        ],
      ),
    );
  }
}

/// Hover, keyboard focus and activation shared by the calendar's controls.
class _Pressable extends StatefulWidget {
  const _Pressable({
    required this.semanticsLabel,
    required this.onTap,
    required this.builder,
    this.selected,
  });

  final String semanticsLabel;
  final VoidCallback? onTap;
  final bool? selected;
  final Widget Function(BuildContext context, bool highlighted) builder;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _hovered = false;
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onTap;
    return Semantics(
      container: true,
      button: true,
      enabled: onTap != null,
      selected: widget.selected,
      label: widget.semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: FocusableActionDetector(
        enabled: onTap != null,
        mouseCursor:
            onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onShowHoverHighlight: (value) => setState(() => _hovered = value),
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              onTap?.call();
              return null;
            },
          ),
        },
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: widget.builder(context, _hovered || _focused),
        ),
      ),
    );
  }
}

class _HeaderButton extends StatelessWidget {
  const _HeaderButton({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.open,
    required this.onTap,
    this.strong = false,
  });

  final String label;
  final String semanticsLabel;
  final bool open;
  final bool strong;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final motion = _motion(context);
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    return _Pressable(
      semanticsLabel: semanticsLabel,
      selected: open,
      onTap: onTap,
      builder: (context, highlighted) => AnimatedContainer(
        duration: motion,
        curve: Curves.easeOut,
        padding: const EdgeInsetsDirectional.fromSTEB(6, 4, 3, 4),
        decoration: BoxDecoration(
          color: open
              ? scheme.primary.withValues(alpha: highlighted ? 0.16 : 0.1)
              : highlighted
                  ? theme.hoverColor
                  : theme.hoverColor.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: Text(
                label,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: base.copyWith(
                  fontSize: 14,
                  color: open ? scheme.primary : base.color,
                  fontWeight: strong ? FontWeight.w600 : FontWeight.w500,
                ),
              ),
            ),
            const SizedBox(width: 1),
            AnimatedRotation(
              turns: open ? 0.5 : 0,
              duration: motion,
              curve: Curves.easeOutCubic,
              child: FlowySvg(
                FlowySvgs.arrow_down_s,
                size: const Size.square(16),
                color: open ? scheme.primary : theme.hintColor,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ArrowButton extends StatelessWidget {
  const _ArrowButton({
    super.key,
    required this.icon,
    required this.semanticsLabel,
    required this.onTap,
  });

  final FlowySvgData icon;
  final String semanticsLabel;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _Pressable(
      semanticsLabel: semanticsLabel,
      onTap: onTap,
      builder: (context, highlighted) => AnimatedContainer(
        duration: _motion(context),
        width: 24,
        height: 24,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: highlighted
              ? theme.hoverColor
              : theme.hoverColor.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(6),
        ),
        child: FlowySvg(
          icon,
          color: theme.iconTheme.color,
          size: const Size.square(20.0),
        ),
      ),
    );
  }
}

/// A month or year to jump to: filled when shown, ringed when current.
class _PickerCell extends StatelessWidget {
  const _PickerCell({
    super.key,
    required this.label,
    required this.semanticsLabel,
    required this.height,
    required this.selected,
    required this.current,
    required this.onTap,
  });

  final String label;
  final String semanticsLabel;
  final double height;
  final bool selected;
  final bool current;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final base = theme.textTheme.bodyMedium ?? const TextStyle();
    final enabled = onTap != null;
    return _Pressable(
      semanticsLabel: semanticsLabel,
      selected: selected,
      onTap: onTap,
      builder: (context, highlighted) => AnimatedContainer(
        duration: _motion(context),
        curve: Curves.easeOut,
        height: height,
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primary.withValues(alpha: highlighted ? 0.86 : 1)
              : highlighted && enabled
                  ? theme.hoverColor
                  : theme.hoverColor.withValues(alpha: 0),
          borderRadius: BorderRadius.circular(height / 2),
          border: Border.all(
            color: current && !selected
                ? scheme.primary.withValues(alpha: 0.55)
                : scheme.primary.withValues(alpha: 0),
          ),
        ),
        child: Text(
          label,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.fade,
          style: base.copyWith(
            fontSize: 13.5,
            color: selected
                ? scheme.surface
                : !enabled
                    ? theme.disabledColor
                    : current
                        ? scheme.primary
                        : base.color,
            fontWeight: selected || current ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

class _MonthGrid extends StatelessWidget {
  const _MonthGrid({
    super.key,
    required this.shown,
    required this.today,
    required this.first,
    required this.last,
    required this.padding,
    required this.onPicked,
  });

  final DateTime shown;
  final DateTime today;

  /// The first days of the earliest and latest months allowed.
  final DateTime first;
  final DateTime last;
  final double padding;
  final ValueChanged<int> onPicked;

  @override
  Widget build(BuildContext context) {
    final locale = _locale(context);
    final short = DateFormat.MMM(locale);
    final full = DateFormat.yMMMM(locale);
    final height = _cellHeight(context);
    Widget cell(int month) {
      final date = DateTime(shown.year, month);
      final allowed = !date.isBefore(first) && !date.isAfter(last);
      return _PickerCell(
        key: ValueKey('date_picker_month_$month'),
        label: short.format(date),
        semanticsLabel: full.format(date),
        height: height,
        selected: month == shown.month,
        current: shown.year == today.year && month == today.month,
        onTap: allowed ? () => onPicked(month) : null,
      );
    }

    return Padding(
      padding: EdgeInsets.fromLTRB(padding, 2, padding, 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var row = 0; row < 4; row++) ...[
            if (row > 0) const SizedBox(height: _gap),
            Row(
              children: [
                for (var column = 0; column < 3; column++) ...[
                  if (column > 0) const SizedBox(width: _gap),
                  Expanded(child: cell(row * 3 + column + 1)),
                ],
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _YearGrid extends StatefulWidget {
  const _YearGrid({
    super.key,
    required this.shown,
    required this.today,
    required this.first,
    required this.last,
    required this.padding,
    required this.onPicked,
  });

  final int shown;
  final int today;
  final int first;
  final int last;
  final double padding;
  final ValueChanged<int> onPicked;

  @override
  State<_YearGrid> createState() => _YearGridState();
}

class _YearGridState extends State<_YearGrid> {
  static const _inset = 2.0;
  ScrollController? _scroll;

  double _extent(double cell) => cell + _gap;

  /// Five rows between two half rows, which fade out to show the list
  /// scrolls.
  double _viewport(double cell) => _extent(cell) * 6;

  /// Centres the shown year's row, within the list's scroll range.
  double _initialOffset(double cell) {
    final rows = (widget.last - widget.first) ~/ _yearColumns + 1;
    final content = rows * _extent(cell) - _gap + _inset * 2;
    final row = (widget.shown - widget.first) ~/ _yearColumns;
    final centre = _inset + row * _extent(cell) + cell / 2;
    final viewport = _viewport(cell);
    return (centre - viewport / 2)
        .clamp(0.0, math.max(0.0, content - viewport));
  }

  /// Scrolls a viewport's worth of whole rows, backwards when negative.
  void page(int direction) {
    final scroll = _scroll;
    if (scroll == null || !scroll.hasClients) return;
    final cell = _cellHeight(context);
    final rows = math.max(1, (_viewport(cell) / _extent(cell)).floor() - 1);
    final position = scroll.position;
    final target = (position.pixels + direction * rows * _extent(cell))
        .clamp(position.minScrollExtent, position.maxScrollExtent);
    final motion = _motion(context);
    motion == Duration.zero
        ? scroll.jumpTo(target)
        : scroll.animateTo(
            target,
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
          );
  }

  @override
  void dispose() {
    _scroll?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cell = _cellHeight(context);
    final format = DateFormat.y(_locale(context));
    final scroll =
        _scroll ??= ScrollController(initialScrollOffset: _initialOffset(cell));
    return SizedBox(
      height: _viewport(cell),
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (bounds) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            Color(0x00000000),
            Color(0xFF000000),
            Color(0xFF000000),
            Color(0x00000000),
          ],
          stops: [0, 0.12, 0.88, 1],
        ).createShader(bounds),
        child: GridView.builder(
          controller: scroll,
          primary: false,
          padding: EdgeInsets.fromLTRB(
            widget.padding,
            _inset,
            widget.padding,
            _inset,
          ),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: _yearColumns,
            mainAxisExtent: cell,
            mainAxisSpacing: _gap,
            crossAxisSpacing: _gap,
          ),
          itemCount: widget.last - widget.first + 1,
          itemBuilder: (context, index) {
            final year = widget.first + index;
            final label = format.format(DateTime(year));
            return _PickerCell(
              key: ValueKey('date_picker_year_$year'),
              label: label,
              semanticsLabel: label,
              height: cell,
              selected: year == widget.shown,
              current: year == widget.today,
              onTap: () => widget.onPicked(year),
            );
          },
        ),
      ),
    );
  }
}
