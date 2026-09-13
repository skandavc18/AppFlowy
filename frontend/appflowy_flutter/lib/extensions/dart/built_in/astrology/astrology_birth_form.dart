import 'dart:async';

import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:timezone/timezone.dart' as tz;

import 'astrology_date_time_picker.dart';
import 'astrology_location.dart';
import 'astrology_model.dart';
import 'astrology_place_dropdown.dart';
import 'astrology_time.dart';

/// A local draft, shared by the dashboard and horoscope dialogs.
///
/// Give the form a bounded width. A bounded height scrolls independently; an
/// unbounded height lets it size to its contents. Only the explicit buttons
/// invoke callbacks. Saving freezes live time without changing the live draft.
class AstrologyBirthForm extends StatefulWidget {
  const AstrologyBirthForm({
    super.key,
    required this.input,
    required this.onGenerate,
    this.onSave,
    this.saveLabel = 'Save horoscope',
    this.enabled = true,
    this.autoLocate = true,
    this.locationService,
  });

  final AstrologyInput input;
  final Future<void> Function(AstrologyInput) onGenerate;
  final Future<void> Function(AstrologyInput)? onSave;
  final String saveLabel;
  final bool enabled;
  final bool autoLocate;
  final AstrologyLocationService? locationService;

  @override
  State<AstrologyBirthForm> createState() => _AstrologyBirthFormState();
}

class _AstrologyBirthFormState extends State<AstrologyBirthForm> {
  static const _yearChoices = [365.25636, 365.25, 360.0];
  static const _searchDelay = Duration(milliseconds: 500);
  static const _manualFallback =
      'Search for a place, or enter coordinates and a time zone or UTC offset '
      'in Advanced.';

  final _name = TextEditingController();
  final _date = TextEditingController();
  final _time = TextEditingController();
  final _place = TextEditingController();
  final _latitude = TextEditingController();
  final _longitude = TextEditingController();
  final _zone = TextEditingController();
  final _offset = TextEditingController();
  final _ayanamsaDegrees = TextEditingController();
  final _ayanamsaMinutes = TextEditingController();
  final _ayanamsaSeconds = TextEditingController();
  final _scroll = ScrollController();
  final _feedbackKey = GlobalKey();
  late final FocusNode _placeFocus;
  Timer? _searchDebounce;

  late String _inputFingerprint;
  DateTime? _sourceUtc;
  AstrologyPlace? _selectedPlace;
  AstrologyAyanamsa _ayanamsa = AstrologyAyanamsa.lahiri;
  double _sourceAyanamsaOffset = 0;
  bool _adjustmentOpen = false;
  bool _subtractAdjustment = false;
  bool _adjustmentEdited = false;
  IndianChartStyle _style = IndianChartStyle.north;
  double _yearDays = 365.25636;
  bool _trueNode = false;
  bool _now = true;
  bool _timeEdited = false;
  bool _advanced = false;
  bool _autoLocateAttempted = false;
  bool _searching = false;
  bool _locating = false;
  bool _submitting = false;
  bool _saving = false;
  bool _clockPickerOpen = false;
  bool _placeMenuOpen = false;
  bool _writingPlace = false;
  bool _placeWasComposing = false;
  int _highlightedPlace = -1;
  int _inputGeneration = 0;
  int _searchGeneration = 0;
  int _locationGeneration = 0;
  List<AstrologyPlace> _results = const [];
  String? _searchMessage;
  String? _locationMessage;
  String? _error;
  String? _success;

  bool get _canEdit => widget.enabled && !_submitting;
  bool get _canSubmit => _canEdit && !_searching && !_locating;
  bool get _placeIsComposing =>
      _place.value.composing.isValid && !_place.value.composing.isCollapsed;
  bool get _needsDevicePlace =>
      _place.text.trim().isEmpty &&
      _latitude.text.trim().isEmpty &&
      _longitude.text.trim().isEmpty;

  // Lazy: a disabled template preview never even resolves the default service.
  AstrologyLocationService get _service =>
      widget.locationService ?? AstrologyLocationService.instance;

  @override
  void initState() {
    super.initState();
    _placeFocus = FocusNode(
      debugLabel: 'Astrology birthplace',
      onKeyEvent: _placeKeyEvent,
    )..addListener(_placeFocusChanged);
    _place.addListener(_placeCompositionChanged);
    _adoptInput(widget.input);
    _queueAutoLocate();
  }

  @override
  void didUpdateWidget(covariant AstrologyBirthForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Compare incoming values, not the draft or object identity. An unrelated
    // dashboard rebuild must not erase an incomplete date or move the caret.
    if (_fingerprintOf(widget.input) != _inputFingerprint) {
      _adoptInput(widget.input);
    }
    if ((oldWidget.enabled && !widget.enabled) ||
        oldWidget.locationService != widget.locationService) {
      _inputGeneration++;
      _invalidatePlaceWork();
    }
    _queueAutoLocate();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _place.removeListener(_placeCompositionChanged);
    _placeFocus
      ..removeListener(_placeFocusChanged)
      ..dispose();
    for (final controller in [
      _name,
      _date,
      _time,
      _place,
      _latitude,
      _longitude,
      _zone,
      _offset,
      _ayanamsaDegrees,
      _ayanamsaMinutes,
      _ayanamsaSeconds,
    ]) {
      controller.dispose();
    }
    _scroll.dispose();
    super.dispose();
  }

  static String _fingerprintOf(AstrologyInput input) {
    try {
      return input.fingerprint;
    } on Object {
      // JSON cannot encode NaN/infinity. Invalid incoming numbers still need
      // an editable form and an error, rather than a build-time exception.
      return [
        input.name,
        input.utc,
        input.place?.name,
        input.place?.latitude,
        input.place?.longitude,
        input.place?.timeZone,
        input.place?.isDeviceLocation,
        input.utcOffsetMinutes,
        input.style,
        input.ayanamsa,
        input.ayanamsaOffsetArcseconds,
        input.trueNode,
        input.dashaYearDays,
      ].toString();
    }
  }

  void _adoptInput(AstrologyInput input) {
    _inputFingerprint = _fingerprintOf(input);
    _inputGeneration++;
    _invalidatePlaceWork();
    _name.text = input.name;
    _sourceUtc = input.utc?.toUtc();
    _now = input.utc == null;
    _timeEdited = false;
    _ayanamsa = input.ayanamsa;
    _sourceAyanamsaOffset = input.ayanamsaOffsetArcseconds;
    _adjustmentOpen = _sourceAyanamsaOffset != 0;
    _subtractAdjustment = _sourceAyanamsaOffset < 0;
    _adjustmentEdited = false;
    final magnitude = _sourceAyanamsaOffset.abs();
    _ayanamsaDegrees.text = magnitude.isFinite
        ? (magnitude ~/ 3600).toString()
        : magnitude.toString();
    _ayanamsaMinutes.text =
        magnitude.isFinite ? (magnitude ~/ 60 % 60).toString() : '0';
    _ayanamsaSeconds.text = magnitude.isFinite
        ? (magnitude % 60).toString().replaceFirst(RegExp(r'\.0$'), '')
        : '0';
    _style = input.style;
    _trueNode = input.trueNode;
    _yearDays = input.dashaYearDays;
    _writePlace(input.place);
    _offset.text = input.utcOffsetMinutes == null
        ? ''
        : AstrologyTime.offsetLabel(Duration(minutes: input.utcOffsetMinutes!));
    _date.clear();
    _time.clear();
    _error = null;
    _success = null;
    try {
      input.validate();
      if (input.place != null) {
        _validateZone(input.place!.timeZone, input.utcOffsetMinutes);
      }
      if (_sourceUtc != null) {
        _writeWallTime(AstrologyTime.localTime(input, _sourceUtc!));
      }
    } on Object catch (error) {
      _error = _errorText(error);
      _advanced = true;
      if (_sourceUtc != null) {
        _writeWallTime(_sourceUtc!);
        _error = '$_error The input time is shown in UTC; '
            'check the location and birth time before submitting.';
      }
    }
  }

  void _writePlace(AstrologyPlace? place) {
    _selectedPlace = place;
    _writingPlace = true;
    try {
      _place.text = place?.name ?? '';
    } finally {
      _writingPlace = false;
    }
    // Keep the full precision in the draft. Only the summary is rounded.
    _latitude.text = place?.latitude.toString() ?? '';
    _longitude.text = place?.longitude.toString() ?? '';
    _zone.text = place?.timeZone ?? '';
  }

  void _writeWallTime(DateTime wall) {
    String two(int value) => value.toString().padLeft(2, '0');
    _date.text = '${wall.year.toString().padLeft(4, '0')}-'
        '${two(wall.month)}-${two(wall.day)}';
    _time.text = '${two(wall.hour)}:${two(wall.minute)}:${two(wall.second)}';
  }

  void _invalidateSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    _searchGeneration++;
    _searching = false;
    _highlightedPlace = -1;
    _results = const [];
    _searchMessage = null;
  }

  void _invalidatePlaceWork() {
    _invalidateSearch();
    _locationGeneration++;
    _locating = false;
    _placeMenuOpen = false;
    _locationMessage = null;
  }

  void _edited({bool time = false}) {
    _timeEdited = _timeEdited || time;
    _error = null;
    _success = null;
  }

  void _editClock(String _) {
    if (!_canEdit) return;
    setState(() {
      _now = false;
      _edited(time: true);
    });
  }

  Future<void> _pickClock(
    BuildContext anchor, {
    required bool focusTime,
  }) async {
    if (!_canEdit || _clockPickerOpen) return;
    final generation = _inputGeneration;
    final date = _date.text;
    final time = _time.text;
    final zoneText = _zone.text;
    final offsetText = _offset.text;
    _clockPickerOpen = true;
    _closePlaceMenu();
    try {
      final zone = zoneText.trim();
      final offset = AstrologyTime.parseOffset(offsetText);
      _validateZone(zone, offset, allowEmpty: true);
      final utcNow = DateTime.now().toUtc();
      final localNow = offset != null
          ? utcNow.add(Duration(minutes: offset))
          : zone.isNotEmpty
              ? tz.TZDateTime.from(utcNow, AstrologyTime.location(zone))
              : utcNow.toLocal();
      final zoneLabel = offset != null
          ? 'Local time · UTC ${AstrologyTime.offsetLabel(Duration(minutes: offset))} (manual)'
          : zone.isNotEmpty
              ? 'Local time · $zone'
              : 'Device time until a birthplace is chosen';
      final selected = await showAstrologyDateTimePicker(
        context: anchor,
        date: date,
        time: time,
        localNow: localNow,
        timeZoneLabel: zoneLabel,
        focusTime: focusTime,
      );
      // A popup is a separate draft. A new record, a newly resolved place, or
      // edits made while it was open must not be overwritten by its result.
      if (!mounted ||
          !_canEdit ||
          generation != _inputGeneration ||
          _date.text != date ||
          _time.text != time ||
          _zone.text != zoneText ||
          _offset.text != offsetText ||
          selected == null ||
          (selected.date == date && selected.time == time)) {
        return;
      }
      setState(() {
        _date.text = selected.date;
        _time.text = selected.time;
        _now = false;
        _edited(time: true);
      });
    } on Object catch (error) {
      if (mounted && _canEdit && generation == _inputGeneration) {
        setState(() => _error = _errorText(error));
        _revealFeedback();
      }
    } finally {
      _clockPickerOpen = false;
    }
  }

  void _editPlace(String _) {
    if (!_canEdit) return;
    setState(() {
      _invalidatePlaceWork();
      // Typing a different place must not silently reuse the old city's
      // coordinates. A typed query is not a selected geocoding result.
      _selectedPlace = null;
      _latitude.clear();
      _longitude.clear();
      _zone.clear();
      _edited(time: true);
      _placeMenuOpen = _placeFocus.hasFocus;
    });
    _queuePlaceSearch();
  }

  void _placeFocusChanged() {
    if (!mounted) return;
    if (!_placeFocus.hasFocus || !_canEdit) {
      _closePlaceMenu();
    } else {
      // Focusing a stored city is not permission to search it again. Only
      // user edits or an explicit Search/Enter start a network request.
      setState(() => _placeMenuOpen = true);
    }
  }

  void _placeCompositionChanged() {
    final composing = _placeIsComposing;
    if (composing == _placeWasComposing) return;
    _placeWasComposing = composing;
    if (_writingPlace || !_canEdit || !_placeFocus.hasFocus) return;
    if (composing) {
      setState(_invalidateSearch);
    } else {
      // IME composition can finish without another text/onChanged event.
      _queuePlaceSearch();
    }
  }

  void _queuePlaceSearch() {
    _searchDebounce?.cancel();
    _searchDebounce = null;
    final query = _place.text.trim();
    if (!_canEdit ||
        !_placeFocus.hasFocus ||
        _placeIsComposing ||
        query.length < 3) {
      return;
    }
    final generation = _searchGeneration;
    _searchDebounce = Timer(_searchDelay, () {
      _searchDebounce = null;
      if (_acceptSearch(generation, query) &&
          _placeFocus.hasFocus &&
          !_placeIsComposing) {
        unawaited(_search(automatic: true));
      }
    });
  }

  void _closePlaceMenu() {
    if (!_placeMenuOpen &&
        !_searching &&
        _searchDebounce == null &&
        _results.isEmpty) {
      return;
    }
    setState(() {
      _placeMenuOpen = false;
      _invalidateSearch();
    });
  }

  KeyEventResult _placeKeyEvent(FocusNode _, KeyEvent event) {
    final keyboard = HardwareKeyboard.instance;
    if (!_canEdit ||
        _placeIsComposing ||
        (event is! KeyDownEvent && event is! KeyRepeatEvent) ||
        keyboard.isAltPressed ||
        keyboard.isControlPressed ||
        keyboard.isMetaPressed ||
        keyboard.isShiftPressed) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.escape && _placeMenuOpen) {
      _closePlaceMenu();
      return KeyEventResult.handled;
    }
    if (_placeMenuOpen && !_searching && _results.isNotEmpty) {
      if (key == LogicalKeyboardKey.arrowDown ||
          key == LogicalKeyboardKey.arrowUp) {
        setState(() {
          _highlightedPlace = _highlightedPlace < 0
              ? (key == LogicalKeyboardKey.arrowDown ? 0 : _results.length - 1)
              : (_highlightedPlace +
                      (key == LogicalKeyboardKey.arrowDown ? 1 : -1)) %
                  _results.length;
        });
        return KeyEventResult.handled;
      }
    }
    if (key == LogicalKeyboardKey.enter ||
        key == LogicalKeyboardKey.numpadEnter) {
      _submitPlaceQuery();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  void _submitPlaceQuery() {
    if (!_canEdit || _placeIsComposing || _searching) return;
    if (_placeMenuOpen && _results.isNotEmpty) {
      _choosePlace(_results[_highlightedPlace < 0 ? 0 : _highlightedPlace]);
    } else {
      unawaited(_search());
    }
  }

  void _editLocationDetails({bool coordinates = false}) {
    if (!_canEdit) return;
    setState(() {
      _invalidatePlaceWork();
      if (coordinates) _selectedPlace = null;
      // Coordinates alone do not change the wall clock or its time zone.
      _edited(time: !coordinates);
    });
  }

  void _queueAutoLocate() {
    if (_autoLocateAttempted ||
        !widget.autoLocate ||
        !_canEdit ||
        widget.input.place != null ||
        !_needsDevicePlace) {
      return;
    }
    _autoLocateAttempted = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          widget.autoLocate &&
          _canEdit &&
          widget.input.place == null &&
          _needsDevicePlace) {
        unawaited(_locate(automatic: true));
      }
    });
  }

  Future<void> _locate({bool automatic = false}) async {
    if (!_canEdit || _locating) return;
    _invalidatePlaceWork();
    final generation = _locationGeneration;
    setState(() {
      _locating = true;
      _error = null;
      _success = null;
    });
    try {
      // The explicit button retries a previously denied/failed request.
      final place = await _service.current(force: !automatic);
      if (!_acceptLocation(generation)) return;
      place.validate();
      final offset = AstrologyTime.parseOffset(_offset.text);
      _validateZone(place.timeZone, offset);
      DateTime? wall;
      if (automatic && !_timeEdited && _sourceUtc != null) {
        wall = AstrologyTime.localTime(
          AstrologyInput(place: place, utcOffsetMinutes: offset),
          _sourceUtc!,
        );
      }
      setState(() {
        _writePlace(place);
        if (wall != null) _writeWallTime(wall);
        if (!automatic) _timeEdited = true;
      });
    } on Object catch (error) {
      if (_acceptLocation(generation)) {
        setState(() {
          _locationMessage = '${_errorText(error)} $_manualFallback';
        });
      }
    } finally {
      if (mounted && generation == _locationGeneration) {
        setState(() => _locating = false);
      }
    }
  }

  bool _acceptLocation(int generation) =>
      mounted && _canEdit && generation == _locationGeneration;

  Future<void> _search({bool automatic = false}) async {
    if (!_canEdit ||
        _searching ||
        _placeIsComposing ||
        (automatic && !_placeFocus.hasFocus)) {
      return;
    }
    final query = _place.text.trim();
    _invalidatePlaceWork();
    final generation = _searchGeneration;
    if (!automatic) _placeFocus.requestFocus();
    if (query.length < (automatic ? 3 : 2)) {
      setState(() {
        _placeMenuOpen = true;
        _searchMessage = 'Enter at least two characters of a place name, '
            'or keep typing for suggestions. $_manualFallback';
      });
      return;
    }
    setState(() {
      _placeMenuOpen = true;
      _searching = true;
      _error = null;
      _success = null;
    });
    try {
      // Photon supports search-as-you-type. The service receives ONLY the
      // place query, never the person's name, clock, or device coordinates.
      final results = await _service.search(query);
      if (!_acceptSearch(generation, query)) return;
      setState(() {
        _results = List<AstrologyPlace>.of(results);
        _searchMessage = results.isEmpty
            ? 'No places were returned. Try a more specific place, or use '
                'Advanced if search is unavailable.'
            : null;
      });
    } on Object catch (error) {
      if (_acceptSearch(generation, query)) {
        setState(() {
          _searchMessage = 'Place search failed. ${_errorText(error)} '
              'Enter coordinates and a time zone or UTC offset in Advanced.';
        });
      }
    } finally {
      if (mounted && generation == _searchGeneration) {
        setState(() => _searching = false);
      }
    }
  }

  bool _acceptSearch(int generation, String query) =>
      mounted &&
      _canEdit &&
      generation == _searchGeneration &&
      query == _place.text.trim();

  void _choosePlace(AstrologyPlace place) {
    if (!_canEdit) return;
    try {
      place.validate();
      _validateZone(place.timeZone, AstrologyTime.parseOffset(_offset.text));
      setState(() {
        _invalidatePlaceWork();
        _writePlace(place);
        _edited(time: true);
      });
    } on Object catch (error) {
      setState(() => _error = _errorText(error));
      _revealFeedback();
    }
  }

  static void _validateZone(
    String zone,
    int? offset, {
    bool allowEmpty = false,
  }) {
    if (zone.trim().isNotEmpty) {
      // An explicit offset may replace IANA rules, but must not hide a typo in
      // a nonempty zone field. Clearing that field opts into offset-only mode.
      AstrologyTime.location(zone.trim());
    } else if (offset == null && !allowEmpty) {
      throw const FormatException(
        'Enter an IANA time zone or a UTC offset in Advanced.',
      );
    }
  }

  double _readAyanamsaOffset() {
    // No-op Generate/Save preserves the stored sub-arcsecond value exactly.
    if (!_adjustmentEdited) return _sourceAyanamsaOffset;
    final degrees = int.tryParse(
      _ayanamsaDegrees.text.trim().isEmpty ? '0' : _ayanamsaDegrees.text.trim(),
    );
    final minutes = int.tryParse(
      _ayanamsaMinutes.text.trim().isEmpty ? '0' : _ayanamsaMinutes.text.trim(),
    );
    final seconds = double.tryParse(
      _ayanamsaSeconds.text.trim().isEmpty ? '0' : _ayanamsaSeconds.text.trim(),
    );
    if (degrees == null ||
        degrees < 0 ||
        degrees >= 360 ||
        minutes == null ||
        minutes < 0 ||
        minutes >= 60 ||
        seconds == null ||
        !seconds.isFinite ||
        seconds < 0 ||
        seconds >= 60) {
      throw const FormatException(
        'Ayanamsha adjustment: use whole degrees 0–359, minutes 0–59, '
        'and seconds from 0 up to (but not including) 60. '
        'Choose Add or Subtract for the direction.',
      );
    }
    return (degrees * 3600 + minutes * 60 + seconds) *
        (_subtractAdjustment ? -1 : 1);
  }

  void _editAdjustment(String _) {
    if (!_canEdit) return;
    setState(() {
      _adjustmentEdited = true;
      _edited();
    });
  }

  void _resetAdjustment() {
    if (!_canEdit) return;
    setState(() {
      _ayanamsaDegrees.text = '0';
      _ayanamsaMinutes.text = '0';
      _ayanamsaSeconds.text = '0';
      _subtractAdjustment = false;
      _adjustmentEdited = true;
      _edited();
    });
  }

  AstrologyPlace? _readPlace(int? offset) {
    final latitudeText = _latitude.text.trim();
    final longitudeText = _longitude.text.trim();
    if (latitudeText.isEmpty && longitudeText.isEmpty) {
      if (_place.text.trim().isNotEmpty) {
        throw const FormatException(
          'Choose a place suggestion or Search result, or enter coordinates in Advanced. '
          'A place name alone does not identify a location.',
        );
      }
      return null;
    }
    final latitude = double.tryParse(latitudeText);
    final longitude = double.tryParse(longitudeText);
    if (latitude == null ||
        longitude == null ||
        !latitude.isFinite ||
        !longitude.isFinite) {
      throw const FormatException(
        'Enter finite latitude and longitude numbers in Advanced.',
      );
    }
    final zone = _zone.text.trim();
    final selected = _selectedPlace;
    final place = selected != null &&
            selected.name == _place.text &&
            selected.latitude == latitude &&
            selected.longitude == longitude &&
            selected.timeZone == zone
        ? selected
        : AstrologyPlace(
            name: _place.text.trim().isEmpty
                ? 'Manual coordinates'
                : _place.text.trim(),
            latitude: latitude,
            longitude: longitude,
            timeZone: zone,
            isDeviceLocation: selected?.isDeviceLocation ?? false,
          );
    place.validate();
    _validateZone(place.timeZone, offset);
    return place;
  }

  Future<void> _submit({required bool save}) async {
    if (!_canSubmit) return;
    final callback = save ? widget.onSave : widget.onGenerate;
    if (callback == null) return;
    final generation = _inputGeneration;
    // Freeze at the click, not after a permission dialog or callback finishes.
    final clickedUtc = DateTime.now().toUtc();
    var resolvingPlace = false;
    var callbackStarted = false;
    setState(() {
      _placeMenuOpen = false;
      _invalidateSearch();
      _submitting = true;
      _saving = save;
      _error = null;
      _success = null;
    });
    try {
      final name = _name.text.trim();
      if (save && name.isEmpty) {
        throw const FormatException(
          'Enter a name before saving the horoscope.',
        );
      }
      // Everything the user can edit is read before the first await. Neither
      // changing parents nor a delayed response can change this submission.
      final date = _date.text;
      final time = _time.text;
      final live = _now;
      final sourceUtc = _timeEdited ? null : _sourceUtc;
      final zone = _zone.text.trim();
      final offset = AstrologyTime.parseOffset(_offset.text);
      final enteredPlace = _readPlace(offset);
      if (enteredPlace == null) {
        _validateZone(zone, offset, allowEmpty: true);
      }
      final draft = AstrologyInput(
        name: name,
        place: enteredPlace,
        utcOffsetMinutes: offset,
        style: _style,
        ayanamsa: _ayanamsa,
        ayanamsaOffsetArcseconds: _readAyanamsaOffset(),
        trueNode: _trueNode,
        dashaYearDays: _yearDays,
      );
      draft.validate();
      var place = draft.place;
      if (place == null) {
        resolvingPlace = true;
        final device = await _service.current();
        if (!_acceptSubmission(generation)) return;
        place = zone.isEmpty || zone == device.timeZone
            ? device
            : AstrologyPlace(
                name: device.name,
                latitude: device.latitude,
                longitude: device.longitude,
                timeZone: zone,
                isDeviceLocation: device.isDeviceLocation,
              );
        resolvingPlace = false;
      }
      place.validate();
      _validateZone(place.timeZone, offset);
      final resolved = draft.copyWith(place: place);
      DateTime? utc;
      if (live) {
        utc = save ? clickedUtc : null;
      } else {
        final knownInstant = sourceUtc ??
            (date.trim().isEmpty && time.trim().isEmpty ? clickedUtc : null);
        final parsed = AstrologyTime.parseBirthTime(
          date: date,
          time: time,
          place: place,
          offsetMinutes: knownInstant == null
              ? offset
              : offset ??
                  AstrologyTime.offsetAt(resolved, knownInstant).inMinutes,
          now: clickedUtc,
        );
        // An unchanged, already fixed instant is unambiguous, even in a DST
        // overlap, and may carry subsecond precision the fields do not show.
        // Two blank fields also mean an actual instant, not an ambiguous wall
        // clock reading if the current time happens to be in a DST overlap.
        utc = knownInstant ?? parsed;
      }
      final submitted = resolved.copyWith(
        utc: utc,
        useCurrentTime: live && !save,
      );
      submitted.validate();
      if (!_acceptSubmission(generation)) return;
      if (draft.place == null) {
        final resolvedPlace = place;
        setState(() {
          _writePlace(resolvedPlace);
          if (sourceUtc != null && !live) {
            _writeWallTime(AstrologyTime.localTime(submitted, sourceUtc));
          }
        });
      }
      callbackStarted = true;
      await callback(submitted);
      if (_acceptSubmission(generation)) {
        setState(() {
          _success = save ? 'Horoscope saved.' : 'Horoscope generated.';
        });
        _revealFeedback();
      }
    } on Object catch (error) {
      if (_acceptSubmission(generation)) {
        final prefix = callbackStarted
            ? (save ? 'Save failed. ' : 'Generation failed. ')
            : '';
        setState(() {
          _error = '$prefix${_errorText(error)}'
              '${resolvingPlace ? ' $_manualFallback' : ''}';
        });
        _revealFeedback();
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  bool _acceptSubmission(int generation) =>
      mounted && widget.enabled && generation == _inputGeneration;

  static String _errorText(Object error) => error is FormatException
      ? error.message
      : error
          .toString()
          .replaceFirst(RegExp(r'^(Exception|Bad state):\s*'), '');

  void _revealFeedback() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = _feedbackKey.currentContext;
      if (target != null) {
        unawaited(Scrollable.ensureVisible(target, alignment: 1));
      }
    });
  }

  String get _placeSummary {
    if (!widget.enabled) return 'Preview only · location lookup is disabled.';
    if (_latitude.text.isEmpty && _longitude.text.isEmpty) {
      return _place.text.trim().isEmpty
          ? 'No default city · Generate will request the device location.'
          : 'Choose a place suggestion, or enter coordinates in Advanced.';
    }
    final zone = _zone.text.trim();
    final offset = _offset.text.trim();
    return '${_coordinate(_latitude.text)}°, '
        '${_coordinate(_longitude.text)}° · '
        '${zone.isEmpty ? 'No IANA zone' : zone}'
        '${offset.isEmpty ? '' : ' · UTC $offset (manual)'}';
  }

  static String _coordinate(String text) {
    final value = double.tryParse(text);
    return value != null && value.isFinite ? value.toStringAsFixed(5) : text;
  }

  @override
  Widget build(BuildContext context) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: _buildForm(context),
      );

  Widget _buildForm(BuildContext context) {
    final colors = _BirthFormColors.of(context);
    return Material(
      key: const ValueKey('astrology-birth-surface'),
      color: colors.surface,
      borderRadius: BorderRadius.circular(PremiumTheme.surfaceRadius),
      clipBehavior: Clip.antiAlias,
      child: SingleChildScrollView(
        key: const ValueKey('astrology-birth-scroll'),
        controller: _scroll,
        primary: false,
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width =
                constraints.hasBoundedWidth ? constraints.maxWidth : 560.0;
            if (width < 48) return const SizedBox.shrink();
            return SizedBox(
              width: width,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Wrap(
                    spacing: 12,
                    runSpacing: 4,
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      Text(
                        'Birth details',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              color: colors.ink,
                            ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Switch(
                            key: const ValueKey('astrology-now'),
                            value: _now,
                            thumbColor: WidgetStateProperty.resolveWith(
                              (states) =>
                                  states.contains(WidgetState.selected) &&
                                          !states.contains(WidgetState.disabled)
                                      ? colors.accent
                                      : colors.muted,
                            ),
                            trackColor: WidgetStateProperty.resolveWith(
                              (states) => states.contains(WidgetState.selected)
                                  ? colors.accent.withValues(alpha: 0.15)
                                  : colors.field,
                            ),
                            trackOutlineColor: WidgetStatePropertyAll(
                              colors.accent.withValues(alpha: 0.15),
                            ),
                            onChanged: !_canEdit
                                ? null
                                : (value) => setState(() {
                                      _now = value;
                                      if (value) {
                                        _date.clear();
                                        _time.clear();
                                      }
                                      _edited(time: true);
                                    }),
                          ),
                          Flexible(
                            child: Text(
                              'Now · live',
                              style: TextStyle(color: colors.ink, fontSize: 12),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _fields(width, [
                    _field(
                      colors,
                      id: 'astrology-name',
                      label: 'Name',
                      hint: 'Required only for saving',
                      controller: _name,
                      onChanged: (_) => setState(() => _edited()),
                    ),
                    _clockField(colors, date: true),
                    _clockField(colors, date: false),
                  ]),
                  const SizedBox(height: 6),
                  _hint(
                    colors,
                    _now
                        ? 'Generate follows Now. Save captures the instant you click. '
                            'Editing a date or time turns Now off.'
                        : 'Local time at the birthplace. Blank date/time fields '
                            'use the current date/time there.',
                  ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      SizedBox(
                        width: width >= 600 ? width - 290 : width,
                        child: _placeField(colors),
                      ),
                      _button(
                        colors,
                        id: 'astrology-search',
                        label: 'Search',
                        icon: Icons.search_rounded,
                        busy: _searching,
                        onPressed: _canEdit && !_searching
                            ? () => unawaited(_search())
                            : null,
                      ),
                      _button(
                        colors,
                        id: 'astrology-current-location',
                        label: 'Current location',
                        icon: Icons.my_location_rounded,
                        busy: _locating,
                        onPressed: _canEdit && !_locating
                            ? () => unawaited(_locate())
                            : null,
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _hint(colors, _placeSummary, id: 'astrology-place-summary'),
                  if (_locating)
                    _hint(
                      colors,
                      'Requesting device location… '
                      'You can still enter a place manually.',
                    ),
                  if (_locationMessage != null)
                    _hint(
                      colors,
                      _locationMessage!,
                      id: 'astrology-location-message',
                    ),
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    crossAxisAlignment: WrapCrossAlignment.end,
                    children: [
                      SizedBox(
                        width: width < 300 ? width : 260,
                        child: _choice<AstrologyAyanamsa>(
                          colors,
                          id: 'astrology-ayanamsa',
                          label: 'Ayanamsha',
                          value: _ayanamsa,
                          items: [
                            for (final value in AstrologyAyanamsa.values)
                              _option(value, value.label),
                          ],
                          onChanged: (value) => _ayanamsa = value,
                        ),
                      ),
                      _button(
                        colors,
                        id: 'astrology-ayanamsa-adjust',
                        label: _adjustmentOpen
                            ? 'Hide adjustment'
                            : 'Custom adjustment',
                        icon: Icons.tune_rounded,
                        onPressed: _canEdit
                            ? () => setState(
                                  () => _adjustmentOpen = !_adjustmentOpen,
                                )
                            : null,
                      ),
                    ],
                  ),
                  if (_adjustmentOpen) ...[
                    const SizedBox(height: 10),
                    _fields(width, [
                      _choice<bool>(
                        colors,
                        id: 'astrology-ayanamsa-direction',
                        label: 'Correction to the selected preset',
                        value: _subtractAdjustment,
                        items: const [
                          DropdownMenuItem(
                            value: false,
                            child: Text('Add (+)'),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('Subtract (−)'),
                          ),
                        ],
                        onChanged: (value) {
                          _subtractAdjustment = value;
                          _adjustmentEdited = true;
                        },
                      ),
                      _field(
                        colors,
                        id: 'astrology-ayanamsa-degrees',
                        label: 'Degrees · °',
                        hint: '0–359',
                        controller: _ayanamsaDegrees,
                        onChanged: _editAdjustment,
                      ),
                      _field(
                        colors,
                        id: 'astrology-ayanamsa-minutes',
                        label: 'Arcminutes · ′',
                        hint: '0–59',
                        controller: _ayanamsaMinutes,
                        onChanged: _editAdjustment,
                      ),
                      _field(
                        colors,
                        id: 'astrology-ayanamsa-seconds',
                        label: 'Arcseconds · ″',
                        hint: '0–59.999…',
                        controller: _ayanamsaSeconds,
                        onChanged: _editAdjustment,
                      ),
                    ]),
                    const SizedBox(height: 6),
                    _hint(
                      colors,
                      'Add increases the ayanamsha and decreases sidereal '
                      'longitudes. Subtract does the reverse. '
                      'Generate applies the draft; Save stores it with this '
                      'horoscope. Hiding this panel does not reset the adjustment.',
                      id: 'astrology-ayanamsa-adjustment-help',
                    ),
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: _button(
                        colors,
                        id: 'astrology-ayanamsa-reset',
                        label: 'Reset adjustment to zero',
                        icon: Icons.restart_alt_rounded,
                        onPressed: _canEdit ? _resetAdjustment : null,
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: _button(
                      colors,
                      id: 'astrology-advanced',
                      label: 'Advanced',
                      icon: _advanced
                          ? Icons.expand_less_rounded
                          : Icons.expand_more_rounded,
                      onPressed: _canEdit
                          ? () => setState(() => _advanced = !_advanced)
                          : null,
                    ),
                  ),
                  if (_advanced) ...[
                    const SizedBox(height: 10),
                    _fields(width, [
                      _field(
                        colors,
                        id: 'astrology-latitude',
                        label: 'Latitude',
                        hint: '−90 < latitude < 90',
                        controller: _latitude,
                        onChanged: (_) =>
                            _editLocationDetails(coordinates: true),
                      ),
                      _field(
                        colors,
                        id: 'astrology-longitude',
                        label: 'Longitude',
                        hint: '−180 to +180',
                        controller: _longitude,
                        onChanged: (_) =>
                            _editLocationDetails(coordinates: true),
                      ),
                      _field(
                        colors,
                        id: 'astrology-timezone',
                        label: 'IANA time zone',
                        hint: 'e.g. Asia/Kolkata',
                        controller: _zone,
                        onChanged: (_) => _editLocationDetails(),
                      ),
                      _field(
                        colors,
                        id: 'astrology-utc-offset',
                        label: 'Manual UTC offset',
                        hint: 'e.g. +05:30 · optional',
                        controller: _offset,
                        onChanged: (_) => _editLocationDetails(),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    _hint(
                      colors,
                      'Leave the UTC offset blank for historical IANA/DST rules. '
                      'A manual offset disambiguates a repeated clock time. '
                      'For offset-only entry, clear the IANA field.',
                    ),
                    const SizedBox(height: 12),
                    _fields(width, [
                      _choice<bool>(
                        colors,
                        id: 'astrology-rahu',
                        label: 'Rahu / Ketu',
                        value: _trueNode,
                        items: const [
                          DropdownMenuItem(
                            value: false,
                            child: Text('Mean Rahu'),
                          ),
                          DropdownMenuItem(
                            value: true,
                            child: Text('True Rahu'),
                          ),
                        ],
                        onChanged: (value) => _trueNode = value,
                      ),
                      _choice<double>(
                        colors,
                        id: 'astrology-dasha-year',
                        label: 'Dasha year',
                        value: _yearDays.isFinite ? _yearDays : null,
                        items: [
                          for (final value in _yearChoices)
                            _option(
                              value,
                              '${value == 360 ? '360' : value} days',
                            ),
                          // Do not silently replace a valid stored convention.
                          if (_yearDays.isFinite &&
                              !_yearChoices.contains(_yearDays))
                            _option(_yearDays, '$_yearDays days (stored)'),
                        ],
                        onChanged: (value) => _yearDays = value,
                      ),
                      _choice<IndianChartStyle>(
                        colors,
                        id: 'astrology-chart-style',
                        label: 'Chart style',
                        value: _style,
                        items: [
                          for (final value in IndianChartStyle.values)
                            _option(value, value.label),
                        ],
                        onChanged: (value) => _style = value,
                      ),
                    ]),
                  ],
                  const SizedBox(height: 12),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _button(
                        colors,
                        id: 'astrology-generate',
                        label: _submitting && !_saving
                            ? 'Generating…'
                            : 'Generate',
                        icon: Icons.auto_awesome_rounded,
                        busy: _submitting && !_saving,
                        onPressed: _canSubmit
                            ? () => unawaited(_submit(save: false))
                            : null,
                      ),
                      if (widget.onSave != null)
                        _button(
                          colors,
                          id: 'astrology-save',
                          label: _submitting && _saving
                              ? 'Saving…'
                              : widget.saveLabel,
                          icon: Icons.bookmark_add_rounded,
                          busy: _submitting && _saving,
                          onPressed: _canSubmit
                              ? () => unawaited(_submit(save: true))
                              : null,
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  _hint(
                    colors,
                    'Place suggestions use Photon/OpenStreetMap. Only your place '
                    'query is sent — never names or birth dates.',
                  ),
                  if (_error != null || _success != null)
                    Padding(
                      key: _feedbackKey,
                      padding: const EdgeInsets.only(top: 8),
                      child: Semantics(
                        liveRegion: true,
                        child: Text(
                          _error ?? _success!,
                          key: ValueKey(
                            _error != null
                                ? 'astrology-error'
                                : 'astrology-success',
                          ),
                          style: TextStyle(
                            color:
                                _error != null ? colors.error : colors.accent,
                            fontSize: 12,
                            height: 1.4,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _fields(double width, List<Widget> children) {
    final columns = (width / 190).floor().clamp(1, 3);
    final fieldWidth = (width - (columns - 1) * 10) / columns;
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: [
        for (final child in children) SizedBox(width: fieldWidth, child: child),
      ],
    );
  }

  Widget _field(
    _BirthFormColors colors, {
    required String id,
    required String label,
    required String hint,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
  }) =>
      _labeled(
        colors,
        label,
        _editableField(
          colors,
          id: id,
          hint: hint,
          controller: controller,
          onChanged: onChanged,
        ),
      );

  Widget _editableField(
    _BirthFormColors colors, {
    required String id,
    required String hint,
    required TextEditingController controller,
    required ValueChanged<String> onChanged,
    FocusNode? focusNode,
    VoidCallback? onTap,
    ValueChanged<String>? onSubmitted,
    VoidCallback? onEditingComplete,
    Widget? suffixIcon,
  }) =>
      TextEntryShortcuts(
        child: TextField(
          key: ValueKey(id),
          controller: controller,
          focusNode: focusNode,
          enabled: _canEdit,
          autocorrect: false,
          enableSuggestions: false,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: colors.ink,
                fontSize: 13,
              ),
          cursorColor: colors.accent,
          decoration: _decoration(colors, hint: hint).copyWith(
            suffixIcon: suffixIcon,
            suffixIconConstraints:
                const BoxConstraints(minWidth: 34, minHeight: 34),
          ),
          onTap: _canEdit ? onTap : null,
          onSubmitted: onSubmitted,
          onEditingComplete: onEditingComplete,
          textInputAction: onSubmitted == null ? null : TextInputAction.search,
          onChanged: (value) {
            if (_canEdit) onChanged(value);
          },
        ),
      );

  Widget _clockField(_BirthFormColors colors, {required bool date}) => _labeled(
        colors,
        date ? 'Birth date' : 'Birth time · 24-hour',
        Builder(
          builder: (anchor) {
            void open() => unawaited(_pickClock(anchor, focusTime: !date));
            return _editableField(
              colors,
              id: date ? 'astrology-date' : 'astrology-time',
              hint: date ? 'YYYY-MM-DD' : 'HH:mm:ss',
              controller: date ? _date : _time,
              onChanged: _editClock,
              onTap: open,
              suffixIcon: IconButton(
                key: ValueKey(
                  date ? 'astrology-pick-date' : 'astrology-pick-time',
                ),
                tooltip: date ? 'Choose birth date' : 'Choose birth time',
                icon: Icon(
                  date ? Icons.calendar_month_rounded : Icons.schedule_rounded,
                  size: 17,
                ),
                color: colors.accent,
                disabledColor: colors.muted,
                padding: const EdgeInsets.all(7),
                constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
                onPressed: _canEdit ? open : null,
              ),
            );
          },
        ),
      );

  Widget _placeField(_BirthFormColors colors) {
    final generation = _searchGeneration;
    return _labeled(
      colors,
      'Birthplace',
      AstrologyPlaceDropdown(
        isOpen: _canEdit && _placeMenuOpen,
        results: _results,
        busy: _searching,
        highlightedIndex: _highlightedPlace,
        onManualEntry: () {
          if (!_canEdit || generation != _searchGeneration) return;
          _closePlaceMenu();
          _placeFocus.unfocus();
          setState(() => _advanced = true);
        },
        message: _searchMessage ??
            (_searching || _results.isNotEmpty
                ? null
                : _placeIsComposing
                    ? 'Finish typing to see place suggestions.'
                    : _place.text.trim().length < 3 || _selectedPlace != null
                        ? 'Type at least 3 characters for place suggestions.'
                        : 'Finding matching places…'),
        onSelected: (index) {
          if (_canEdit &&
              generation == _searchGeneration &&
              index >= 0 &&
              index < _results.length) {
            _choosePlace(_results[index]);
          }
        },
        child: _editableField(
          colors,
          id: 'astrology-place',
          hint: 'Search city, town, or address',
          controller: _place,
          focusNode: _placeFocus,
          onChanged: _editPlace,
          onTap: () {
            if (!_placeMenuOpen) setState(() => _placeMenuOpen = true);
          },
          onEditingComplete: () {},
          onSubmitted: (_) => _submitPlaceQuery(),
          suffixIcon: _place.text.isEmpty
              ? Icon(Icons.place_rounded, color: colors.muted, size: 17)
              : IconButton(
                  key: const ValueKey('astrology-clear-place'),
                  tooltip: 'Clear birthplace',
                  icon: const Icon(Icons.close_rounded, size: 16),
                  color: colors.muted,
                  padding: const EdgeInsets.all(7),
                  constraints:
                      const BoxConstraints(minWidth: 34, minHeight: 34),
                  onPressed: !_canEdit
                      ? null
                      : () {
                          _place.clear();
                          _editPlace('');
                          _placeFocus.requestFocus();
                        },
                ),
        ),
      ),
    );
  }

  DropdownMenuItem<T> _option<T>(T value, String label) => DropdownMenuItem(
        value: value,
        child: Text(label, overflow: TextOverflow.ellipsis),
      );

  Widget _choice<T>(
    _BirthFormColors colors, {
    required String id,
    required String label,
    required T? value,
    required List<DropdownMenuItem<T>> items,
    required ValueChanged<T> onChanged,
  }) {
    final generation = _inputGeneration;
    return _labeled(
      colors,
      label,
      InputDecorator(
        decoration: _decoration(colors),
        child: DropdownButtonHideUnderline(
          // Retiring DropdownButton's State dismisses its old popup. Flutter
          // otherwise delivers that popup's result to the NEW onChanged.
          key: ValueKey('$id-route-$generation'),
          child: DropdownButton<T>(
            key: ValueKey(id),
            value: value,
            items: items,
            isExpanded: true,
            isDense: true,
            dropdownColor: colors.surface,
            borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
            iconEnabledColor: colors.muted,
            hint: const Text('Choose a value'),
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: colors.ink,
                  fontSize: 13,
                ),
            onChanged: !_canEdit
                ? null
                : (value) {
                    if (!mounted ||
                        value == null ||
                        !_canEdit ||
                        generation != _inputGeneration) {
                      return;
                    }
                    setState(() {
                      onChanged(value);
                      _edited();
                    });
                  },
          ),
        ),
      ),
    );
  }

  Widget _labeled(_BirthFormColors colors, String label, Widget child) =>
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(color: colors.muted, fontSize: 11.5)),
          const SizedBox(height: 5),
          child,
        ],
      );

  InputDecoration _decoration(_BirthFormColors colors, {String? hint}) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
      borderSide: BorderSide.none,
    );
    return InputDecoration(
      isDense: true,
      filled: true,
      fillColor: colors.field,
      hoverColor: colors.hover,
      hintText: hint,
      hintStyle: TextStyle(color: colors.muted, fontSize: 12),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
      border: border,
      enabledBorder: border,
      disabledBorder: border,
      focusedBorder:
          border.copyWith(borderSide: BorderSide(color: colors.accent)),
    );
  }

  Widget _button(
    _BirthFormColors colors, {
    required String id,
    required String label,
    required IconData icon,
    required VoidCallback? onPressed,
    bool busy = false,
  }) {
    final generation = _inputGeneration;
    return TextButton(
      key: ValueKey(id),
      style: TextButton.styleFrom(
        foregroundColor: colors.accent,
        backgroundColor: colors.accent.withValues(alpha: 0.10),
        disabledForegroundColor: colors.muted,
        disabledBackgroundColor: colors.field,
        overlayColor: colors.accent.withValues(alpha: 0.10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        minimumSize: const Size(0, 34),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(PremiumTheme.controlRadius),
        ),
        textStyle: Theme.of(context).textTheme.labelMedium,
      ),
      onPressed: onPressed == null
          ? null
          : () {
              if (!mounted || !_canEdit || generation != _inputGeneration) {
                return;
              }
              onPressed();
            },
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (busy)
            SizedBox.square(
              dimension: 15,
              child: CircularProgressIndicator(
                strokeWidth: 1.7,
                color: colors.accent,
              ),
            )
          else
            Icon(icon, size: 16),
          const SizedBox(width: 6),
          Flexible(
            child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
        ],
      ),
    );
  }

  Widget _hint(_BirthFormColors colors, String text, {String? id}) => Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Semantics(
          liveRegion: id != null,
          child: Text(
            text,
            key: id == null ? null : ValueKey(id),
            style: TextStyle(color: colors.muted, fontSize: 11.5, height: 1.4),
          ),
        ),
      );
}

class _BirthFormColors {
  const _BirthFormColors({
    required this.surface,
    required this.field,
    required this.ink,
    required this.muted,
    required this.accent,
    required this.hover,
    required this.error,
  });

  factory _BirthFormColors.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final paper =
        theme.brightness == Brightness.light && PaperTheme.isEnabled(context);
    return _BirthFormColors(
      surface: EditorSurfaceStyle.previewBackgroundFor(
        theme.brightness,
        premium?.surface ?? theme.colorScheme.surface,
        isPaper: paper,
      ),
      field: EditorSurfaceStyle.codeBlockBackgroundFor(
        theme.brightness,
        premium?.mutedSurface ?? theme.colorScheme.surfaceContainerLow,
        isPaper: paper,
      ),
      ink: paper
          ? PaperTheme.textPrimary
          : premium?.textPrimary ?? theme.colorScheme.onSurface,
      muted: paper
          ? PaperTheme.textSecondary
          : premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
      accent: paper
          ? PaperTheme.accent
          : premium?.accent ?? theme.colorScheme.primary,
      hover: paper
          ? PaperTheme.hoverOverlay
          : premium?.hoverOverlay ?? theme.hoverColor,
      error: premium == null
          ? theme.colorScheme.error
          : PremiumTheme.semanticColorFor(theme.colorScheme.error, premium),
    );
  }

  final Color surface;
  final Color field;
  final Color ink;
  final Color muted;
  final Color accent;
  final Color hover;
  final Color error;
}
