import 'dart:async';

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'astrology_controls.dart';
import 'astrology_dashboard_model.dart';
import 'astrology_date_analysis.dart';
import 'astrology_date_time_picker.dart';
import 'astrology_location.dart';
import 'astrology_model.dart';
import 'astrology_place_dropdown.dart';
import 'astrology_style.dart';
import 'astrology_time.dart';

/// The Transit details tab: a date, a time and a place, applied together.
///
/// Typing, Now and the pickers only fill the fields; no reading changes until
/// Apply. [onApplied] then receives the instant (null: the current moment) and
/// the place (null: the birthplace); the caller owns where they are kept.
class AstrologyTransitForm extends StatefulWidget {
  const AstrologyTransitForm({
    super.key,
    required this.natal,
    required this.utc,
    required this.onApplied,
    this.place,
    this.applied = false,
    this.enabled = true,
    this.clock,
    this.locationService,
  });

  /// Supplies the birthplace: the clock and place used when none is chosen.
  final AstrologyInput natal;

  /// The applied moment. Null follows the current moment.
  final DateTime? utc;

  /// The applied place. Null is the birthplace.
  final AstrologyPlace? place;

  /// Whether a transit has been applied.
  final bool applied;

  final void Function(DateTime? utc, AstrologyPlace? place) onApplied;
  final bool enabled;

  /// The current moment, replaceable in tests.
  final DateTime Function()? clock;

  /// Device location and place search, replaceable in tests.
  final AstrologyLocationService? locationService;

  @override
  State<AstrologyTransitForm> createState() => _AstrologyTransitFormState();
}

class _AstrologyTransitFormState extends State<AstrologyTransitForm> {
  static const _searchDelay = Duration(milliseconds: 500);

  final _date = TextEditingController();
  final _time = TextEditingController();
  final _placeText = TextEditingController();
  final _scroll = ScrollController();
  late final FocusNode _placeFocus;
  Timer? _searchDebounce;

  /// The chosen transit place. Null is the birthplace.
  AstrologyPlace? _place;
  List<AstrologyPlace> _results = const [];
  int _highlighted = -1;
  int _searchGeneration = 0;
  int _locationGeneration = 0;
  bool _menuOpen = false;
  bool _searching = false;
  bool _locating = false;
  bool _picking = false;
  bool _wasComposing = false;

  /// The fields differ from what was last applied.
  bool _pending = false;
  String? _searchMessage;
  String? _notice;
  String? _error;

  AstrologyLocationService get _service =>
      widget.locationService ?? AstrologyLocationService.instance;

  DateTime get _nowUtc => (widget.clock?.call() ?? DateTime.now()).toUtc();

  bool get _composing =>
      _placeText.value.composing.isValid &&
      !_placeText.value.composing.isCollapsed;

  /// The clock the fields are read on: [place]'s, else the birthplace's.
  AstrologyInput _clockAt(AstrologyPlace? place) =>
      astrologyTransitInput(widget.natal, null, place: place);

  @override
  void initState() {
    super.initState();
    _placeFocus = FocusNode(
      debugLabel: 'Transit place',
      onKeyEvent: _placeKeyEvent,
    )..addListener(_placeFocusChanged);
    _placeText.addListener(_compositionChanged);
    _adopt();
  }

  @override
  void didUpdateWidget(AstrologyTransitForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    final place = widget.natal.place;
    final oldPlace = oldWidget.natal.place;
    if (widget.utc != oldWidget.utc ||
        widget.applied != oldWidget.applied ||
        !astrologySamePlace(widget.place, oldWidget.place) ||
        place?.timeZone != oldPlace?.timeZone ||
        widget.natal.utcOffsetMinutes != oldWidget.natal.utcOffsetMinutes) {
      _adopt();
    } else if (oldWidget.enabled && !widget.enabled) {
      _invalidatePlaceWork();
    }
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _placeFocus
      ..removeListener(_placeFocusChanged)
      ..dispose();
    _placeText.removeListener(_compositionChanged);
    _date.dispose();
    _time.dispose();
    _placeText.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Shows what is applied, discarding an unapplied draft.
  void _adopt() {
    _invalidatePlaceWork();
    _error = null;
    _notice = null;
    _pending = false;
    _place = widget.place;
    _placeText.text = widget.place == null ? '' : _placeLabel(widget.place!);
    final utc = widget.utc;
    if (utc == null) {
      _date.clear();
      _time.clear();
    } else {
      _writeMoment(utc, widget.place);
    }
  }

  /// Writes [utc] on [place]'s clock (null: the birthplace's).
  void _writeMoment(DateTime utc, AstrologyPlace? place) {
    try {
      final input = _clockAt(place);
      _date.text = astrologyLocalDate(input, utc);
      _time.text = astrologyLocalClock(input, utc, seconds: true);
    } on FormatException catch (error) {
      _error = _transitMessage(error.message);
    }
  }

  static String _placeLabel(AstrologyPlace place) {
    if (!place.isDeviceLocation) return place.name;
    String degrees(double value, String positive, String negative) =>
        '${value.abs().toStringAsFixed(2)}° ${value < 0 ? negative : positive}';
    return '${place.name} · ${degrees(place.latitude, 'N', 'S')}, '
        '${degrees(place.longitude, 'E', 'W')}';
  }

  static String _shortName(AstrologyPlace place) =>
      place.name.split(',').first.trim();

  void _invalidateSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchGeneration++;
    _searching = false;
    _highlighted = -1;
    _results = const [];
    _searchMessage = null;
  }

  void _invalidatePlaceWork() {
    _invalidateSearch();
    _locationGeneration++;
    _locating = false;
    _menuOpen = false;
  }

  void _edited() {
    _pending = true;
    _error = null;
  }

  /// Null when both fields are blank: the current moment.
  DateTime? _read() {
    final date = _date.text;
    final time = _time.text;
    if (date.trim().isEmpty && time.trim().isEmpty) return null;
    try {
      final input = _clockAt(_place);
      final place = input.place;
      if (place == null) {
        // No birthplace yet: the device clock, like the birth form.
        final wall = AstrologyTime.parseWallTime(
          date: date,
          time: time,
          now: _nowUtc.toLocal(),
        );
        return DateTime(
          wall.year,
          wall.month,
          wall.day,
          wall.hour,
          wall.minute,
          wall.second,
        ).toUtc();
      }
      return AstrologyTime.parseBirthTime(
        date: date,
        time: time,
        place: place,
        offsetMinutes: input.utcOffsetMinutes,
        now: _nowUtc,
      );
    } on FormatException catch (error) {
      throw FormatException(_transitMessage(error.message));
    }
  }

  static String _transitMessage(String message) {
    if (message.contains('occurred twice')) {
      return 'This local time occurred twice during a clock change. '
          'Choose a time outside that hour.';
    }
    return message
        .replaceAll('birth date', 'transit date')
        .replaceAll('birth time', 'transit time')
        .replaceAll('birth-time', 'transit-time');
  }

  void _apply() {
    if (!widget.enabled) return;
    if (_place == null && _placeText.text.trim().isNotEmpty) {
      setState(() {
        _error = 'Choose a place from the suggestions, or clear the place '
            'to use the birthplace.';
      });
      return;
    }
    try {
      final utc = _read();
      final place = _place;
      setState(() {
        _invalidatePlaceWork();
        _error = null;
        _notice = null;
        _pending = false;
      });
      widget.onApplied(utc, place);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
    }
  }

  /// Fills in the current moment, then the device's place once it is read.
  /// Nothing is applied: that is Apply's job.
  Future<void> _fillNow() async {
    if (!widget.enabled) return;
    final now = _nowUtc;
    _invalidatePlaceWork();
    final generation = _locationGeneration;
    setState(() {
      _edited();
      _notice = null;
      _locating = true;
      _writeMoment(now, _place);
    });
    final date = _date.text;
    final time = _time.text;
    try {
      // An explicit request retries a previously denied or failed one.
      final device = await _service.current(force: true);
      if (!_acceptLocation(generation)) return;
      device.validate();
      AstrologyTime.location(device.timeZone);
      setState(() {
        _place = device;
        _placeText.text = _placeLabel(device);
        // The same instant on the new place's clock, unless it was retyped.
        if (_date.text == date && _time.text == time) {
          _writeMoment(now, device);
        }
      });
    } on Object {
      if (_acceptLocation(generation)) {
        final kept = _place ?? widget.natal.place;
        setState(() {
          _notice = 'Current location is unavailable or permission was '
              'denied${kept == null ? '' : ', so ${_shortName(kept)} is kept'}. '
              'Search for a place, or enable Windows location services and '
              'press Now again.';
        });
      }
    } finally {
      if (mounted && generation == _locationGeneration) {
        setState(() => _locating = false);
      }
    }
  }

  bool _acceptLocation(int generation) =>
      mounted && widget.enabled && generation == _locationGeneration;

  Future<void> _pick(BuildContext anchor, {required bool focusTime}) async {
    if (!widget.enabled || _picking) return;
    _picking = true;
    _closeMenu();
    final date = _date.text;
    final time = _time.text;
    try {
      final input = _clockAt(_place);
      final place = input.place;
      final zone = place?.timeZone.trim() ?? '';
      final clock = _place == null
          ? 'Birthplace time'
          : 'Local time at ${_shortName(_place!)}';
      final now = _nowUtc;
      final selected = await showAstrologyDateTimePicker(
        context: anchor,
        date: date,
        time: time,
        localNow:
            place == null ? now.toLocal() : AstrologyTime.localTime(input, now),
        timeZoneLabel: place == null
            ? 'Device time until a birthplace is chosen'
            : zone.isEmpty
                ? '$clock · '
                    '${astrologyOffsetLabel(AstrologyTime.offsetAt(input, now))}'
                : '$clock · $zone',
        focusTime: focusTime,
        subject: 'Transit',
      );
      // Only fills the fields, and never over edits made while it was open.
      if (!mounted ||
          !widget.enabled ||
          selected == null ||
          _date.text != date ||
          _time.text != time ||
          (selected.date == date && selected.time == time)) {
        return;
      }
      setState(() {
        _date.text = selected.date;
        _time.text = selected.time;
        _edited();
      });
    } on FormatException catch (error) {
      if (mounted) setState(() => _error = _transitMessage(error.message));
    } finally {
      _picking = false;
    }
  }

  void _editClock(String _) {
    if (!widget.enabled) return;
    setState(_edited);
  }

  void _editPlace(String _) {
    if (!widget.enabled) return;
    setState(() {
      _invalidatePlaceWork();
      // A typed query is not a chosen place; Apply asks for a suggestion.
      _place = null;
      _notice = null;
      _edited();
      _menuOpen = _placeFocus.hasFocus;
    });
    _queueSearch();
  }

  void _placeFocusChanged() {
    if (!mounted) return;
    if (!_placeFocus.hasFocus || !widget.enabled) {
      _closeMenu();
    } else if (!_menuOpen) {
      setState(() => _menuOpen = true);
    }
  }

  void _compositionChanged() {
    final composing = _composing;
    if (composing == _wasComposing) return;
    _wasComposing = composing;
    if (!widget.enabled || !_placeFocus.hasFocus) return;
    if (composing) {
      setState(_invalidateSearch);
    } else {
      // IME composition can finish without another onChanged event.
      _queueSearch();
    }
  }

  void _queueSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    final query = _placeText.text.trim();
    if (!widget.enabled ||
        !_placeFocus.hasFocus ||
        _composing ||
        query.length < 3) {
      return;
    }
    final generation = _searchGeneration;
    _searchDebounce = Timer(_searchDelay, () {
      _searchDebounce = null;
      if (_acceptSearch(generation, query) &&
          _placeFocus.hasFocus &&
          !_composing) {
        unawaited(_search(automatic: true));
      }
    });
  }

  bool _acceptSearch(int generation, String query) =>
      mounted &&
      widget.enabled &&
      generation == _searchGeneration &&
      query == _placeText.text.trim();

  Future<void> _search({bool automatic = false}) async {
    if (!widget.enabled ||
        _searching ||
        _composing ||
        (automatic && !_placeFocus.hasFocus)) {
      return;
    }
    final query = _placeText.text.trim();
    _invalidatePlaceWork();
    final generation = _searchGeneration;
    if (!automatic) _placeFocus.requestFocus();
    if (query.length < 2) {
      setState(() {
        _menuOpen = true;
        _searchMessage = 'Enter at least two characters of a place name, or '
            'clear the place to use the birthplace.';
      });
      return;
    }
    setState(() {
      _menuOpen = true;
      _searching = true;
    });
    try {
      // Only the place query is sent: never a name, birth data or position.
      final results = await _service.search(query);
      if (!_acceptSearch(generation, query)) return;
      setState(() {
        _results = List<AstrologyPlace>.of(results);
        _searchMessage = results.isEmpty
            ? 'No places were returned. Try a more specific place.'
            : null;
      });
    } on Object {
      if (_acceptSearch(generation, query)) {
        setState(() {
          _searchMessage = 'Place search failed. Check the connection and '
              'try again, or clear the place to use the birthplace.';
        });
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  void _choose(AstrologyPlace place) {
    if (!widget.enabled) return;
    try {
      place.validate();
      AstrologyTime.location(place.timeZone);
    } on FormatException catch (error) {
      setState(() => _error = error.message);
      return;
    }
    setState(() {
      _invalidatePlaceWork();
      _place = place;
      _placeText.text = _placeLabel(place);
      _notice = null;
      _edited();
    });
  }

  void _clearPlace() {
    if (!widget.enabled) return;
    _placeText.clear();
    _editPlace('');
    _placeFocus.requestFocus();
  }

  void _closeMenu() {
    if (!_menuOpen &&
        !_searching &&
        _searchDebounce == null &&
        _results.isEmpty) {
      return;
    }
    setState(() {
      _menuOpen = false;
      _invalidateSearch();
    });
  }

  KeyEventResult _placeKeyEvent(FocusNode _, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!widget.enabled ||
        _composing ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && _menuOpen) {
      _closeMenu();
      return KeyEventResult.handled;
    }
    if (_menuOpen &&
        !_searching &&
        _results.isNotEmpty &&
        (key == LogicalKeyboardKey.arrowDown ||
            key == LogicalKeyboardKey.arrowUp)) {
      final down = key == LogicalKeyboardKey.arrowDown;
      setState(() {
        _highlighted = _highlighted < 0
            ? (down ? 0 : _results.length - 1)
            : (_highlighted + (down ? 1 : -1)) % _results.length;
      });
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submitPlace();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  /// Enter chooses a suggestion, searches a typed place, or applies.
  void _submitPlace() {
    if (!widget.enabled || _composing || _searching) return;
    if (_menuOpen && _results.isNotEmpty) {
      _choose(_results[_highlighted < 0 ? 0 : _highlighted]);
    } else if (_place == null && _placeText.text.trim().isNotEmpty) {
      unawaited(_search());
    } else {
      _apply();
    }
  }

  String _status() {
    if (_locating) return 'Finding your current location…';
    if (_pending) {
      return 'Not applied yet. Apply updates the transit chart, panchanga '
          'and dasha.';
    }
    if (!widget.applied) {
      return 'Nothing applied yet. Press Now or enter a moment, then Apply.';
    }
    final place = widget.place ?? widget.natal.place;
    final where = place == null ? '' : ' · ${_shortName(place)}';
    final utc = widget.utc;
    if (utc == null) {
      return 'Showing the current moment$where · updates every minute.';
    }
    try {
      final input = _clockAt(widget.place);
      return 'Showing ${astrologyLocalDate(input, utc)} · '
          '${astrologyLocalClock(input, utc, seconds: true)} · '
          '${astrologyOffsetLabel(AstrologyTime.offsetAt(input, utc))}$where';
    } on FormatException catch (error) {
      return _transitMessage(error.message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final muted = TextStyle(color: palette.muted, fontSize: 11.5, height: 1.4);
    final shown = widget.applied && !_pending && !_locating;
    return Material(
      key: const ValueKey('astrology-transit-surface'),
      color: palette.surface,
      borderRadius: BorderRadius.circular(PremiumTheme.surfaceRadius),
      clipBehavior: Clip.antiAlias,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _scroll,
          primary: false,
          padding: const EdgeInsets.all(12),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final width = constraints.maxWidth;
              if (width < 48) return const SizedBox.shrink();
              // One row when there is room; otherwise the place gets its own.
              final oneRow = width >= 720;
              final clockWidth = oneRow
                  ? (width - 20) * 0.28
                  : width >= 420
                      ? (width - 10) / 2
                      : width;
              final placeWidth = oneRow ? width - 20 - clockWidth * 2 : width;
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    children: [
                      SizedBox(
                        width: clockWidth,
                        child: _clockField(palette, date: true),
                      ),
                      SizedBox(
                        width: clockWidth,
                        child: _clockField(palette, date: false),
                      ),
                      SizedBox(width: placeWidth, child: _placeField(palette)),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      AstrologyButton(
                        id: 'astrology-transit-now',
                        label: 'Now',
                        icon: Icons.my_location_rounded,
                        busy: _locating,
                        tooltip: 'Fill in the current date, time and location',
                        onPressed:
                            widget.enabled ? () => unawaited(_fillNow()) : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Fills in the current date, time and location. '
                          'Blank date and time follow the live moment; a '
                          'blank place is the birthplace.',
                          style: muted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      AstrologyButton(
                        id: 'astrology-transit-apply',
                        label: 'Apply',
                        icon: Icons.check_rounded,
                        primary: true,
                        onPressed: widget.enabled ? _apply : null,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Semantics(
                          liveRegion: true,
                          child: Row(
                            children: [
                              WorkspaceGlyph(
                                _locating
                                    ? Icons.my_location_rounded
                                    : !shown
                                        ? Icons.edit_calendar_rounded
                                        : widget.utc == null
                                            ? Icons.timelapse_rounded
                                            : Icons.event_available_rounded,
                                size: 16,
                                color: shown ? palette.accent : palette.muted,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  _status(),
                                  key: const ValueKey(
                                    'astrology-transit-status',
                                  ),
                                  style: TextStyle(
                                    color: shown ? palette.ink : palette.muted,
                                    fontSize: 12.5,
                                    height: 1.35,
                                    fontWeight: FontWeight.w600,
                                    fontVariations: const [
                                      FontVariation.weight(600),
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                  for (final (id, message, color) in [
                    ('astrology-transit-error', _error, palette.danger),
                    ('astrology-transit-notice', _notice, palette.muted),
                  ])
                    if (message != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Semantics(
                          liveRegion: true,
                          child: Text(
                            message,
                            key: ValueKey(id),
                            style: TextStyle(
                              color: color,
                              fontSize: 12,
                              height: 1.4,
                            ),
                          ),
                        ),
                      ),
                  const SizedBox(height: 8),
                  Text(
                    'Apply moves the transit chart, panchanga, placements and '
                    'current dasha while this tab is open. Shadbala, '
                    'Ashtakavarga and the birth charts stay natal.',
                    style: muted,
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  InputDecoration _decoration(
    AstrologyPalette palette, {
    required String hint,
    required Widget suffixIcon,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: palette.control,
      hoverColor: palette.hover,
      hintText: hint,
      hintMaxLines: 1,
      hintStyle: TextStyle(color: palette.muted, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder: border.copyWith(
        borderSide: BorderSide(color: palette.accent),
      ),
      suffixIconConstraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      suffixIcon: suffixIcon,
    );
  }

  Widget _labeled(AstrologyPalette palette, String label, Widget field) =>
      Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(color: palette.muted, fontSize: 11.5),
          ),
          const SizedBox(height: 5),
          field,
        ],
      );

  Widget _placeField(AstrologyPalette palette) {
    final generation = _searchGeneration;
    final birthplace = widget.natal.place;
    return _labeled(
      palette,
      'Transit place',
      AstrologyPlaceDropdown(
        isOpen: widget.enabled && _menuOpen,
        results: _results,
        busy: _searching,
        highlightedIndex: _highlighted,
        message: _searchMessage ??
            (_searching || _results.isNotEmpty
                ? null
                : _composing
                    ? 'Finish typing to see place suggestions.'
                    : _placeText.text.trim().length < 3 || _place != null
                        ? 'Type at least 3 characters for place suggestions. '
                            'Leave it blank for the birthplace.'
                        : 'Finding matching places…'),
        onSelected: (index) {
          if (widget.enabled &&
              generation == _searchGeneration &&
              index >= 0 &&
              index < _results.length) {
            _choose(_results[index]);
          }
        },
        child: TextEntryShortcuts(
          child: TextField(
            key: const ValueKey('astrology-transit-place'),
            controller: _placeText,
            focusNode: _placeFocus,
            enabled: widget.enabled,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.search,
            style: TextStyle(color: palette.ink, fontSize: 13),
            cursorColor: palette.accent,
            decoration: _decoration(
              palette,
              hint: birthplace == null
                  ? 'Search city, town, or address'
                  : 'Birthplace · ${birthplace.name}',
              suffixIcon: _placeText.text.isEmpty
                  ? ExcludeSemantics(
                      child: WorkspaceGlyph(
                        Icons.place_rounded,
                        size: 17,
                        color: palette.muted,
                      ),
                    )
                  : IconButton(
                      key: const ValueKey('astrology-transit-clear-place'),
                      tooltip: 'Use the birthplace',
                      icon: WorkspaceGlyph(
                        Icons.close_rounded,
                        size: 16,
                        color: palette.muted,
                      ),
                      padding: const EdgeInsets.all(7),
                      constraints:
                          const BoxConstraints(minWidth: 34, minHeight: 34),
                      onPressed: widget.enabled ? _clearPlace : null,
                    ),
            ),
            onTap: () {
              if (widget.enabled && !_menuOpen) {
                setState(() => _menuOpen = true);
              }
            },
            onChanged: _editPlace,
            onEditingComplete: () {},
            onSubmitted: (_) => _submitPlace(),
          ),
        ),
      ),
    );
  }

  Widget _clockField(AstrologyPalette palette, {required bool date}) =>
      _labeled(
        palette,
        date ? 'Transit date' : 'Transit time · 24-hour',
        Builder(
          builder: (anchor) {
            void open() => unawaited(_pick(anchor, focusTime: !date));
            return TextEntryShortcuts(
              child: TextField(
                key: ValueKey(
                  date ? 'astrology-transit-date' : 'astrology-transit-time',
                ),
                controller: date ? _date : _time,
                enabled: widget.enabled,
                autocorrect: false,
                enableSuggestions: false,
                keyboardType: TextInputType.datetime,
                style: TextStyle(color: palette.ink, fontSize: 13),
                cursorColor: palette.accent,
                decoration: _decoration(
                  palette,
                  hint: date ? 'YYYY-MM-DD · today' : 'HH:mm:ss · now',
                  suffixIcon: IconButton(
                    key: ValueKey(
                      date
                          ? 'astrology-transit-pick-date'
                          : 'astrology-transit-pick-time',
                    ),
                    tooltip:
                        date ? 'Choose transit date' : 'Choose transit time',
                    icon: WorkspaceGlyph(
                      date
                          ? Icons.calendar_month_rounded
                          : Icons.schedule_rounded,
                      size: 17,
                      color: widget.enabled ? palette.accent : palette.muted,
                      role: widget.enabled
                          ? WorkspaceGlyphRole.standard
                          : WorkspaceGlyphRole.preserveInk,
                    ),
                    padding: const EdgeInsets.all(7),
                    constraints:
                        const BoxConstraints(minWidth: 34, minHeight: 34),
                    onPressed: widget.enabled ? open : null,
                  ),
                ),
                onTap: widget.enabled ? open : null,
                onChanged: _editClock,
                onSubmitted: (_) => _apply(),
              ),
            );
          },
        ),
      );
}
