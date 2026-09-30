import 'dart:math' as math;

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/workspace/presentation/widgets/date_picker/widgets/date_picker_calendar.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'astrology_style.dart';
import 'astrology_time.dart';

/// Birthplace wall-clock strings, not a resolved instant or a time-zone change.
@immutable
class AstrologyDateTimeSelection {
  const AstrologyDateTimeSelection({required this.date, required this.time});

  final String date;
  final String time;
}

/// Opens an isolated draft anchored to the field that owns [context].
///
/// [localNow] must already contain the birthplace's wall-clock components.
/// Opening, browsing, and cancelling never change the caller's draft. Only
/// Apply returns a selection; the caller decides whether to adopt it.
/// [subject] names the moment being edited, e.g. "Birth" or "Transit".
Future<AstrologyDateTimeSelection?> showAstrologyDateTimePicker({
  required BuildContext context,
  required String date,
  required String time,
  required DateTime localNow,
  required String timeZoneLabel,
  bool focusTime = false,
  String subject = 'Birth',
}) {
  if (!context.mounted) return Future.value();
  final box = context.findRenderObject();
  final navigator = Navigator.of(context, rootNavigator: true);
  final overlay = navigator.overlay?.context.findRenderObject();
  if (box is! RenderBox ||
      !box.hasSize ||
      overlay is! RenderBox ||
      !overlay.hasSize) {
    return Future.value();
  }
  final anchor = Rect.fromPoints(
    overlay.globalToLocal(box.localToGlobal(Offset.zero)),
    overlay.globalToLocal(
      box.localToGlobal(Offset(box.size.width, box.size.height)),
    ),
  );
  return navigator.push<AstrologyDateTimeSelection>(
    _AstrologyDateTimeRoute(
      anchor: anchor,
      date: date,
      time: time,
      localNow: localNow,
      timeZoneLabel: timeZoneLabel,
      focusTime: focusTime,
      subject: subject,
      themes: InheritedTheme.capture(from: context, to: navigator.context),
      mediaQuery: MediaQuery.of(context),
      textDirection: Directionality.of(context),
      barrierLabel: MaterialLocalizations.of(context).modalBarrierDismissLabel,
    ),
  );
}

class _AstrologyDateTimeRoute extends PopupRoute<AstrologyDateTimeSelection> {
  _AstrologyDateTimeRoute({
    required this.anchor,
    required this.date,
    required this.time,
    required this.localNow,
    required this.timeZoneLabel,
    required this.focusTime,
    required this.subject,
    required this.themes,
    required this.mediaQuery,
    required this.textDirection,
    required this.barrierLabel,
  });

  final Rect anchor;
  final String date;
  final String time;
  final DateTime localNow;
  final String timeZoneLabel;
  final bool focusTime;
  final String subject;
  final CapturedThemes themes;
  final MediaQueryData mediaQuery;
  final TextDirection textDirection;

  @override
  final String barrierLabel;

  @override
  Color get barrierColor => Colors.transparent;

  @override
  bool get barrierDismissible => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 140);

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    final viewport = MediaQuery.of(context);
    final insets = EdgeInsets.fromLTRB(
      math.max(viewport.padding.left, viewport.viewInsets.left),
      math.max(viewport.padding.top, viewport.viewInsets.top),
      math.max(viewport.padding.right, viewport.viewInsets.right),
      math.max(viewport.padding.bottom, viewport.viewInsets.bottom),
    );
    return themes.wrap(
      MediaQuery(
        // Keep card-local typography, but respond to window/keyboard changes.
        data: mediaQuery.copyWith(
          size: viewport.size,
          padding: viewport.padding,
          viewPadding: viewport.viewPadding,
          viewInsets: viewport.viewInsets,
        ),
        child: Directionality(
          textDirection: textDirection,
          child: CustomSingleChildLayout(
            delegate: _PickerPlacement(
              anchor: anchor,
              insets: insets,
              width:
                  300 * (mediaQuery.textScaler.scale(14) / 14).clamp(1.0, 1.25),
            ),
            child: FadeTransition(
              opacity: animation,
              child: _AstrologyDateTimePicker(
                date: date,
                time: time,
                localNow: localNow,
                timeZoneLabel: timeZoneLabel,
                focusTime: focusTime,
                subject: subject,
                onFinished: (selection) {
                  if (isCurrent) navigator?.pop(selection);
                },
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _PickerPlacement extends SingleChildLayoutDelegate {
  const _PickerPlacement({
    required this.anchor,
    required this.insets,
    required this.width,
  });

  final Rect anchor;
  final EdgeInsets insets;
  final double width;

  Rect _available(Size size) {
    final left = (insets.left + 8).clamp(0.0, size.width);
    final top = (insets.top + 8).clamp(0.0, size.height);
    return Rect.fromLTRB(
      left,
      top,
      math.max(left, size.width - insets.right - 8),
      math.max(top, size.height - insets.bottom - 8),
    );
  }

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final available = _available(constraints.biggest);
    final actualWidth = math.min(width, available.width);
    return BoxConstraints(
      minWidth: actualWidth,
      maxWidth: actualWidth,
      maxHeight: available.height,
    );
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final available = _available(size);
    final below = anchor.bottom + 6;
    final above = anchor.top - 6 - childSize.height;
    final y = below + childSize.height <= available.bottom
        ? below
        : above >= available.top
            ? above
            : below;
    return Offset(
      anchor.left.clamp(available.left, available.right - childSize.width),
      y.clamp(available.top, available.bottom - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_PickerPlacement oldDelegate) =>
      anchor != oldDelegate.anchor ||
      insets != oldDelegate.insets ||
      width != oldDelegate.width;
}

class _AstrologyDateTimePicker extends StatefulWidget {
  const _AstrologyDateTimePicker({
    required this.date,
    required this.time,
    required this.localNow,
    required this.timeZoneLabel,
    required this.focusTime,
    required this.subject,
    required this.onFinished,
  });

  final String date;
  final String time;
  final DateTime localNow;
  final String timeZoneLabel;
  final bool focusTime;
  final String subject;
  final ValueChanged<AstrologyDateTimeSelection?> onFinished;

  @override
  State<_AstrologyDateTimePicker> createState() =>
      _AstrologyDateTimePickerState();
}

class _AstrologyDateTimePickerState extends State<_AstrologyDateTimePicker> {
  late final TextEditingController _date;
  late final TextEditingController _time;
  final _dateFocus = FocusNode(debugLabel: 'Astrology picker date');
  final _timeFocus = FocusNode(debugLabel: 'Astrology picker time');
  final _scroll = ScrollController();
  DateTime? _calendarDate;

  /// The month the calendar shows.
  late DateTime _displayedMonth;
  String? _error;
  bool _closing = false;

  static const _radius = 10.0;
  static final _firstDay = DateTime.utc(1800);
  static final _lastDay = DateTime.utc(2399, 12, 31);

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: widget.date);
    _time = TextEditingController(text: widget.time);
    _calendarDate = _readDate(widget.date);
    _displayedMonth = _monthOf(_calendarDate ?? _fallbackDay);
  }

  @override
  void dispose() {
    // A popped route's Future resolves before its reverse animation finishes.
    // These belong to the mounted picker, never to that Future's completion.
    _date.dispose();
    _time.dispose();
    _dateFocus.dispose();
    _timeFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static DateTime _monthOf(DateTime day) => DateTime(day.year, day.month);

  /// The day the calendar shows while the date field is blank or invalid.
  DateTime get _fallbackDay {
    final now = widget.localNow;
    if (now.year < 1800) return DateTime(1800);
    if (now.year > 2399) return DateTime(2399, 12, 31);
    return DateTime(now.year, now.month, now.day);
  }

  DateTime? _readDate(String value) {
    if (value.trim().isEmpty) return null;
    try {
      return AstrologyTime.parseWallTime(
        date: value,
        time: '00:00',
        now: widget.localNow,
      );
    } on FormatException {
      return null;
    }
  }

  DateTime? _readClock(String value) {
    if (value.trim().isEmpty) return null;
    try {
      return AstrologyTime.parseWallTime(
        date: '2000-01-01',
        time: value,
        now: widget.localNow,
      );
    } on FormatException {
      return null;
    }
  }

  void _editDate(String value) {
    final day = _readDate(value);
    setState(() {
      if (!DateUtils.isSameDay(day, _calendarDate)) {
        _calendarDate = day;
        _displayedMonth = _monthOf(day ?? _fallbackDay);
      }
      _error = null;
    });
  }

  void _chooseDay(DateTime day) {
    if (_closing) return;
    setState(() {
      final text = '${day.year.toString().padLeft(4, '0')}-'
          '${_two(day.month)}-${_two(day.day)}';
      _date.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _calendarDate = _readDate(text);
      _displayedMonth = _monthOf(_calendarDate ?? _fallbackDay);
      _error = null;
    });
  }

  String _retainOriginal(
    String value,
    String original,
    DateTime? Function(String) parse,
  ) {
    if (value == original) return original;
    if (value.trim().isEmpty && original.trim().isEmpty) return original;
    // Choosing an explicit value is different from leaving a fallback blank.
    if (value.trim().isEmpty || original.trim().isEmpty) return value;
    final parsed = parse(value);
    return parsed != null && parsed == parse(original) ? original : value;
  }

  void _apply() {
    if (_closing) return;
    try {
      AstrologyTime.parseWallTime(
        date: _date.text,
        time: _time.text,
        now: widget.localNow,
      );
      _finish(
        AstrologyDateTimeSelection(
          date: _retainOriginal(_date.text, widget.date, _readDate),
          time: _retainOriginal(_time.text, widget.time, _readClock),
        ),
      );
    } on FormatException catch (error) {
      _showError(error.message);
    }
  }

  void _showError(String message) {
    setState(() => _error = message);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing && _error != null && _scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  void _finish(AstrologyDateTimeSelection? selection) {
    if (_closing) return;
    _closing = true;
    widget.onFinished(selection);
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final theme = Theme.of(context);
    final content = Semantics(
      scopesRoute: true,
      namesRoute: true,
      explicitChildNodes: true,
      label: '${widget.subject} date and time',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
            ),
            shadows: [
              BoxShadow(
                color: palette.shadow,
                blurRadius: 24,
                spreadRadius: -4,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Material(
            key: const ValueKey('astrology-date-time-picker'),
            color: palette.raised,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_radius),
              side: BorderSide(color: palette.line, width: 0.5),
            ),
            clipBehavior: Clip.antiAlias,
            child: LayoutBuilder(
              builder: (context, constraints) {
                if (constraints.maxWidth < 80 || constraints.maxHeight <= 0) {
                  return const SizedBox.shrink();
                }
                return SingleChildScrollView(
                  controller: _scroll,
                  primary: false,
                  physics: const ClampingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                  child: _contents(context, palette, constraints.maxWidth - 28),
                );
              },
            ),
          ),
        ),
      ),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: palette.accent,
          onPrimary: palette.onAccent,
          surface: palette.raised,
          onSurface: palette.ink,
          onSurfaceVariant: palette.muted,
          outline: palette.line,
          error: palette.danger,
        ),
        // Unselected day cells are drawn in the card colour.
        cardColor: palette.raised,
        canvasColor: palette.raised,
        hoverColor: palette.hover,
        focusColor: palette.selection,
        highlightColor: palette.selection,
        splashColor: palette.selection,
        dividerColor: palette.line,
        disabledColor: palette.muted,
        hintColor: palette.muted,
        textTheme: theme.textTheme.copyWith(
          titleSmall: theme.textTheme.titleSmall?.copyWith(fontSize: 12),
        ),
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: palette.accent,
          selectionColor: palette.accent.withValues(alpha: 0.20),
          selectionHandleColor: palette.accent,
        ),
      ),
      // A compact popup: no scroll rails, including the year list's.
      child: ScrollbarTheme(
        data: const ScrollbarThemeData(
          thickness: WidgetStatePropertyAll(0),
          thumbColor: WidgetStatePropertyAll(Colors.transparent),
          trackVisibility: WidgetStatePropertyAll(false),
          interactive: false,
        ),
        child: ScrollConfiguration(
          // Do not inherit an inactive dashboard card's gated physics.
          behavior: const MaterialScrollBehavior().copyWith(
            scrollbars: false,
            overscroll: false,
            physics: const ClampingScrollPhysics(),
          ),
          child: PrimaryScrollController.none(
            child: Shortcuts(
              shortcuts: const {
                SingleActivator(LogicalKeyboardKey.escape): DismissIntent(),
              },
              child: Actions(
                actions: {
                  DismissIntent: CallbackAction<DismissIntent>(
                    onInvoke: (_) {
                      _finish(null);
                      return null;
                    },
                  ),
                },
                child: FocusTraversalGroup(child: content),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _contents(
    BuildContext context,
    AstrologyPalette palette,
    double width,
  ) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${widget.subject} date and time',
          style: TextStyle(
            color: palette.ink,
            fontSize: 13.5,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          widget.timeZoneLabel.isEmpty
              ? 'Birthplace wall time'
              : widget.timeZoneLabel,
          style: TextStyle(color: palette.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        _entry(context, palette, width),
        const SizedBox(height: 14),
        // Preserve legible day cells on exceptionally narrow windows without
        // overflowing the route or shrinking the caller's accessibility scale.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: math.max(240, width),
            // The month and the year in its header open lists to jump to.
            // Browsing never chooses a day; only a day click does.
            child: DatePickerCalendar(
              key: const ValueKey('astrology-picker-calendar'),
              focusedDay: _displayedMonth,
              selectedDay: _calendarDate,
              firstDay: _firstDay,
              lastDay: _lastDay,
              currentDay: widget.localNow,
              horizontalPadding: 0,
              onDaySelected: (day, _) => _chooseDay(day),
              onFocusedDayChanged: (day) =>
                  setState(() => _displayedMonth = _monthOf(day)),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Text(
          'Blank fields use the current date/time at the birthplace.',
          style: TextStyle(color: palette.muted, fontSize: 11.5, height: 1.3),
        ),
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Semantics(
              liveRegion: true,
              child: Text(
                _error!,
                key: const ValueKey('astrology-picker-error'),
                style: TextStyle(color: palette.danger, fontSize: 12),
              ),
            ),
          ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            _button(
              palette,
              'today',
              'Today',
              () => _chooseDay(widget.localNow),
            ),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _button(palette, 'cancel', 'Cancel', () => _finish(null)),
                _button(palette, 'apply', 'Apply', _apply),
              ],
            ),
          ],
        ),
      ],
    );
  }

  /// One outlined box holding the date and the time, like a date cell's.
  Widget _entry(BuildContext context, AstrologyPalette palette, double width) {
    final stacked = width < MediaQuery.textScalerOf(context).scale(200);
    return ListenableBuilder(
      listenable: Listenable.merge([_dateFocus, _timeFocus]),
      builder: (context, _) {
        final focused = _dateFocus.hasFocus || _timeFocus.hasFocus;
        final date = _field(palette, date: true);
        final time = _field(palette, date: false);
        return AnimatedContainer(
          key: const ValueKey('astrology-picker-entry'),
          duration: MediaQuery.disableAnimationsOf(context)
              ? Duration.zero
              : const Duration(milliseconds: 140),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: focused ? palette.accent : palette.line,
            ),
          ),
          child: stacked
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    date,
                    Divider(height: 1, thickness: 1, color: palette.line),
                    time,
                  ],
                )
              : Row(
                  children: [
                    Expanded(child: date),
                    Container(width: 1, height: 18, color: palette.line),
                    Expanded(child: time),
                  ],
                ),
        );
      },
    );
  }

  Widget _field(AstrologyPalette palette, {required bool date}) {
    final label =
        date ? '${widget.subject} date' : '${widget.subject} time · 24-hour';
    return Semantics(
      label: label,
      child: TextEntryShortcuts(
        child: TextField(
          key: ValueKey(
            date ? 'astrology-picker-date' : 'astrology-picker-time',
          ),
          controller: date ? _date : _time,
          focusNode: date ? _dateFocus : _timeFocus,
          autofocus: date ? !widget.focusTime : widget.focusTime,
          autocorrect: false,
          enableSuggestions: false,
          keyboardType: TextInputType.datetime,
          textInputAction: date ? TextInputAction.next : TextInputAction.done,
          scrollPadding: EdgeInsets.zero,
          style: TextStyle(color: palette.ink, fontSize: 13),
          cursorColor: palette.accent,
          // The surrounding box draws the outline; themed borders and fills
          // must not add a second one inside it.
          decoration: InputDecoration(
            isCollapsed: true,
            filled: false,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: InputBorder.none,
            hintText: date ? 'YYYY-MM-DD' : 'HH:mm:ss',
            hintStyle: TextStyle(color: palette.muted, fontSize: 13),
            contentPadding: EdgeInsetsDirectional.fromSTEB(
              date ? 12 : 10,
              9,
              date ? 8 : 12,
              9,
            ),
          ),
          onChanged: date ? _editDate : (_) => setState(() => _error = null),
          onSubmitted: (_) => date ? _timeFocus.requestFocus() : _apply(),
        ),
      ),
    );
  }

  Widget _button(
    AstrologyPalette palette,
    String id,
    String label,
    VoidCallback onPressed,
  ) {
    final primary = id == 'apply';
    return TextButton(
      key: ValueKey('astrology-picker-$id'),
      onPressed: onPressed,
      style: TextButton.styleFrom(
        foregroundColor: primary
            ? palette.onAccent
            : id == 'today'
                ? palette.accent
                : palette.ink,
        backgroundColor: primary ? palette.accent : Colors.transparent,
        overlayColor: primary ? palette.onAccent : palette.ink,
        minimumSize: const Size(0, 32),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
        // A button's own text style replaces the theme's, font included.
        textStyle: (Theme.of(context).textTheme.labelLarge ?? const TextStyle())
            .copyWith(
          fontSize: 12.5,
          fontWeight: primary ? FontWeight.w600 : FontWeight.w500,
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: Text(label),
    );
  }
}
