import 'dart:math' as math;

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/premium_theme.dart';
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
Future<AstrologyDateTimeSelection?> showAstrologyDateTimePicker({
  required BuildContext context,
  required String date,
  required String time,
  required DateTime localNow,
  required String timeZoneLabel,
  bool focusTime = false,
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
                  360 * (mediaQuery.textScaler.scale(14) / 14).clamp(1.0, 1.25),
            ),
            child: FadeTransition(
              opacity: animation,
              child: _AstrologyDateTimePicker(
                date: date,
                time: time,
                localNow: localNow,
                timeZoneLabel: timeZoneLabel,
                focusTime: focusTime,
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
    required this.onFinished,
  });

  final String date;
  final String time;
  final DateTime localNow;
  final String timeZoneLabel;
  final bool focusTime;
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
  int _calendarGeneration = 0;
  String? _error;
  bool _closing = false;

  @override
  void initState() {
    super.initState();
    _date = TextEditingController(text: widget.date);
    _time = TextEditingController(text: widget.time);
    _calendarDate = _readDate(widget.date);
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
        _calendarGeneration++;
      }
      _error = null;
    });
  }

  void _chooseDay(DateTime day, {bool resetCalendar = false}) {
    if (_closing) return;
    setState(() {
      final text = '${day.year.toString().padLeft(4, '0')}-'
          '${_two(day.month)}-${_two(day.day)}';
      _date.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      _calendarDate = _readDate(text);
      if (resetCalendar) _calendarGeneration++;
      _error = null;
    });
  }

  void _chooseClock(int part, int value) {
    if (_closing) return;
    try {
      final clock = AstrologyTime.parseWallTime(
        date: '2000-01-01',
        time: _time.text,
        now: widget.localNow,
      );
      final parts = [clock.hour, clock.minute, clock.second];
      if (_time.text.trim().isNotEmpty && parts[part] == value) return;
      parts[part] = value;
      final text = parts.map(_two).join(':');
      setState(() {
        _time.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
        _error = null;
      });
    } on FormatException catch (error) {
      // A dropdown must not silently replace an invalid manual clock with Now.
      _showError(error.message);
    }
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
      label: 'Birth date and time',
      child: Listener(
        behavior: HitTestBehavior.opaque,
        child: Material(
          key: const ValueKey('astrology-date-time-picker'),
          color: palette.raised,
          surfaceTintColor: Colors.transparent,
          shadowColor: palette.ink.withValues(alpha: 0.14),
          elevation: 4,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PremiumTheme.surfaceRadius),
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
                padding: const EdgeInsets.all(12),
                child: _contents(context, palette, constraints.maxWidth - 24),
              );
            },
          ),
        ),
      ),
    );
    return Theme(
      data: theme.copyWith(
        colorScheme: theme.colorScheme.copyWith(
          primary: palette.accent,
          onPrimary: palette.ink,
          surface: palette.raised,
          onSurface: palette.ink,
          onSurfaceVariant: palette.muted,
          outline: palette.line,
          error: palette.danger,
        ),
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
      // DropdownButton adds its own always-visible Scrollbar. Its captured
      // theme must suppress that rail as well as automatic desktop scrollbars.
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
    final scaler = MediaQuery.textScalerOf(context);
    final fieldWidth = width >= scaler.scale(300) ? (width - 8) / 2 : width;
    final clock = _readClock(_time.text);
    final columns = (width / (math.max(80, scaler.scale(13) * 2 + 40) + 8))
        .floor()
        .clamp(1, 3);
    final clockWidth = (width - (columns - 1) * 8) / columns;
    final parts = [
      (id: 'hour', label: 'Hour', count: 24, value: clock?.hour),
      (id: 'minute', label: 'Minute', count: 60, value: clock?.minute),
      (id: 'second', label: 'Second', count: 60, value: clock?.second),
    ];
    // The calendar can browse a boundary even if a synthetic/current date is
    // outside the ephemeris range. This display seed never fills either field.
    final initialDay = _calendarDate ??
        (widget.localNow.year < 1800
            ? DateTime.utc(1800)
            : widget.localNow.year > 2399
                ? DateTime.utc(2399, 12, 31)
                : null);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Birth date and time',
          style: TextStyle(
            color: palette.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          widget.timeZoneLabel.isEmpty
              ? 'Birthplace wall time'
              : widget.timeZoneLabel,
          style: TextStyle(color: palette.muted, fontSize: 11.5),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            SizedBox(
              width: fieldWidth,
              child: _field(palette, date: true),
            ),
            SizedBox(
              width: fieldWidth,
              child: _field(palette, date: false),
            ),
          ],
        ),
        const SizedBox(height: 8),
        // Preserve legible day cells on exceptionally narrow windows without
        // overflowing the route or shrinking the caller's accessibility scale.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          primary: false,
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: math.max(240, width),
            child: DatePickerTheme(
              data: _calendarTheme(palette),
              child: IconButtonTheme(
                data: IconButtonThemeData(
                  style: ButtonStyle(
                    backgroundColor: WidgetStateProperty.resolveWith((states) {
                      if (states.contains(WidgetState.focused)) {
                        return palette.selection;
                      }
                      return states.contains(WidgetState.hovered)
                          ? palette.hover
                          : Colors.transparent;
                    }),
                    overlayColor: WidgetStatePropertyAll(palette.selection),
                    shape: WidgetStatePropertyAll(
                      RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(PremiumTheme.controlRadius),
                      ),
                    ),
                  ),
                ),
                child: KeyedSubtree(
                  key: ValueKey(_calendarGeneration),
                  child: CalendarDatePicker(
                    key: const ValueKey('astrology-picker-calendar'),
                    initialDate: initialDay,
                    firstDate: DateTime.utc(1800),
                    lastDate: DateTime.utc(2399, 12, 31),
                    currentDate: widget.localNow,
                    onDateChanged: _chooseDay,
                  ),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final (index, part) in parts.indexed)
              SizedBox(
                width: clockWidth,
                child: _labeled(
                  palette,
                  part.label,
                  Semantics(
                    label: 'Birth time ${part.id}',
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: palette.control,
                        borderRadius:
                            BorderRadius.circular(PremiumTheme.controlRadius),
                        border: Border.all(color: palette.line, width: 0.5),
                      ),
                      child: DropdownButtonHideUnderline(
                        child: DropdownButton<int>(
                          key: ValueKey('astrology-picker-${part.id}'),
                          value: part.value,
                          isExpanded: true,
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          iconSize: 20,
                          iconEnabledColor: palette.muted,
                          focusColor: palette.selection,
                          dropdownColor: palette.raised,
                          elevation: 0,
                          borderRadius:
                              BorderRadius.circular(PremiumTheme.controlRadius),
                          itemHeight: math.max(48, scaler.scale(13) * 1.5 + 16),
                          menuMaxHeight: 240,
                          style: TextStyle(color: palette.ink, fontSize: 13),
                          hint: const Text('—'),
                          items: [
                            for (var value = 0; value < part.count; value++)
                              DropdownMenuItem(
                                value: value,
                                child: Text(
                                  _two(value),
                                  // A dropdown is another route, which captures
                                  // themes but not a card's local MediaQuery.
                                  textScaler: scaler,
                                  semanticsLabel:
                                      '${part.label} ${_two(value)}',
                                ),
                              ),
                          ],
                          onChanged: (value) {
                            if (value != null) _chooseClock(index, value);
                          },
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ],
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
          children: [
            _button(
              palette,
              'today',
              'Today',
              () => _chooseDay(widget.localNow, resetCalendar: true),
            ),
            _button(palette, 'cancel', 'Cancel', () => _finish(null)),
            _button(palette, 'apply', 'Apply', _apply),
          ],
        ),
      ],
    );
  }

  Widget _field(AstrologyPalette palette, {required bool date}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
      borderSide: BorderSide(color: palette.line, width: 0.5),
    );
    final label = date ? 'Birth date' : 'Birth time · 24-hour';
    return _labeled(
      palette,
      label,
      Semantics(
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
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: palette.control,
              hoverColor: palette.hover,
              hintText: date ? 'YYYY-MM-DD' : 'HH:mm:ss',
              hintStyle: TextStyle(color: palette.muted, fontSize: 13),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: palette.accent),
              ),
            ),
            onChanged: date ? _editDate : (_) => setState(() => _error = null),
            onSubmitted: (_) => date ? _timeFocus.requestFocus() : _apply(),
          ),
        ),
      ),
    );
  }

  Widget _labeled(AstrologyPalette palette, String label, Widget child) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ExcludeSemantics(
            child: Text(
              label,
              style: TextStyle(color: palette.muted, fontSize: 11.5),
            ),
          ),
          const SizedBox(height: 5),
          child,
        ],
      );

  Widget _button(
    AstrologyPalette palette,
    String id,
    String label,
    VoidCallback onPressed,
  ) =>
      TextButton(
        key: ValueKey('astrology-picker-$id'),
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: id == 'apply' ? palette.accent : palette.ink,
          backgroundColor: id == 'apply'
              ? palette.accent.withValues(alpha: 0.10)
              : palette.control,
          overlayColor: palette.hover,
          minimumSize: const Size(0, 36),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
          textStyle: const TextStyle(fontSize: 12.5),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
          ),
        ),
        child: Text(label),
      );

  DatePickerThemeData _calendarTheme(AstrologyPalette palette) {
    final foreground = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) return palette.muted;
      return states.contains(WidgetState.selected)
          ? palette.accent
          : palette.ink;
    });
    final background = WidgetStateProperty.resolveWith<Color>(
      (states) => states.contains(WidgetState.selected)
          ? palette.selection
          : palette.raised,
    );
    final overlay = WidgetStateProperty.resolveWith<Color>((states) {
      if (states.contains(WidgetState.disabled)) return Colors.transparent;
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.focused)) {
        return palette.selection;
      }
      return states.contains(WidgetState.hovered)
          ? palette.hover
          : Colors.transparent;
    });
    return DatePickerThemeData(
      backgroundColor: palette.raised,
      surfaceTintColor: Colors.transparent,
      headerBackgroundColor: palette.raised,
      headerForegroundColor: palette.ink,
      weekdayStyle: TextStyle(color: palette.muted, fontSize: 12),
      dayStyle: const TextStyle(fontSize: 12),
      dayForegroundColor: foreground,
      dayBackgroundColor: background,
      dayOverlayColor: overlay,
      dayShape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
        ),
      ),
      todayForegroundColor: WidgetStatePropertyAll(palette.accent),
      todayBackgroundColor: background,
      todayBorder: BorderSide(color: palette.accent),
      yearStyle: const TextStyle(fontSize: 13),
      yearForegroundColor: foreground,
      yearBackgroundColor: background,
      yearOverlayColor: overlay,
      dividerColor: palette.line,
    );
  }
}
