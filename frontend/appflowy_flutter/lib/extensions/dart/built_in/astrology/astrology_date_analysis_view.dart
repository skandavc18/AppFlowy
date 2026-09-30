import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';

import 'astrology_chart_panel.dart' show AstrologyRuntime;
import 'astrology_controls.dart';
import 'astrology_date_analysis.dart';
import 'astrology_date_time_picker.dart';
import 'astrology_engine.dart';
import 'astrology_location.dart';
import 'astrology_model.dart';
import 'astrology_panchanga.dart';
import 'astrology_style.dart';
import 'astrology_time.dart';
import 'vimshottari.dart';

/// Natal settings + the moment to analyse → every value the card shows.
typedef AstrologyDateAnalyzer = Future<AstrologyDateAnalysis> Function(
  AstrologyInput natal,
  AstrologyInput moment,
);

Future<AstrologyDateAnalysis> _analyze(
  AstrologyInput natal,
  AstrologyInput moment,
) async {
  final engine = AstrologyEngine.instance;
  final natalChart = natal.utc != null && natal.place != null
      ? await engine.calculate(natal)
      : null;
  final chart = await engine.calculate(moment);
  final times = await engine.panchangaTimes(chart);
  return analyzeAstrologyDate(moment: chart, natal: natalChart, times: times);
}

enum _PlaceMode { birth, current, other }

/// Quick analysis of any date: natal Vimshottari periods through Sookshma
/// dasha, transits placed in the natal chart, panchanga with end times and
/// the day's muhurta windows. Time and place are optional (noon, birthplace).
class AstrologyDateAnalysisView extends StatefulWidget {
  const AstrologyDateAnalysisView({
    super.key,
    required this.natal,
    this.preview = false,
    this.analyzer,
    this.locationService,
    this.clock,
  });

  final AstrologyInput natal;
  final bool preview;
  final AstrologyDateAnalyzer? analyzer;
  final AstrologyLocationService? locationService;
  final DateTime Function()? clock;

  @override
  State<AstrologyDateAnalysisView> createState() =>
      _AstrologyDateAnalysisViewState();
}

class _AstrologyDateAnalysisViewState extends State<AstrologyDateAnalysisView> {
  final _scroll = ScrollController();
  final _search = TextEditingController();
  bool _useNow = true;
  String _date = '';
  String _time = '';
  late _PlaceMode _mode;
  AstrologyPlace? _other;
  AstrologyPlace? _place;
  AstrologyDateAnalysis? _analysis;
  String? _error;
  bool _loading = false;
  int _generation = 0;
  Timer? _searchTimer;
  int _searchGeneration = 0;
  List<AstrologyPlace> _results = const [];
  bool _searching = false;
  String? _searchMessage;

  bool get _active =>
      !widget.preview &&
      (AstrologyRuntime.active.value || widget.analyzer != null);

  AstrologyLocationService get _locations =>
      widget.locationService ?? AstrologyLocationService.instance;

  @override
  void initState() {
    super.initState();
    _mode = widget.natal.place == null ? _PlaceMode.current : _PlaceMode.birth;
    AstrologyRuntime.active.addListener(_runtimeChanged);
    // Loading updates state, which must not happen while this is mounting.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(_load());
    });
  }

  @override
  void didUpdateWidget(AstrologyDateAnalysisView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameInput(oldWidget.natal, widget.natal) ||
        oldWidget.preview != widget.preview) {
      if (widget.natal.place == null && _mode == _PlaceMode.birth) {
        _mode = _PlaceMode.current;
      }
      unawaited(_load());
    }
  }

  static bool _sameInput(AstrologyInput a, AstrologyInput b) {
    if (identical(a, b)) return true;
    try {
      return a.fingerprint == b.fingerprint;
    } on Object {
      return false;
    }
  }

  void _runtimeChanged() {
    if (!mounted) return;
    unawaited(_load());
  }

  @override
  void dispose() {
    _generation++;
    _searchGeneration++;
    _searchTimer?.cancel();
    AstrologyRuntime.active.removeListener(_runtimeChanged);
    _scroll.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<AstrologyPlace> _resolvePlace({bool force = false}) async {
    switch (_mode) {
      case _PlaceMode.birth:
        return widget.natal.place ?? await _locations.current(force: force);
      case _PlaceMode.current:
        return _locations.current(force: force);
      case _PlaceMode.other:
        final place = _other;
        if (place == null) {
          throw const FormatException('Search for a place, then choose it.');
        }
        return place;
    }
  }

  Future<void> _load({bool forceLocation = false}) async {
    if (!mounted || !_active) {
      if (mounted) setState(() {});
      return;
    }
    final generation = ++_generation;
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final natal = widget.natal;
      natal.validate();
      final place = await _resolvePlace(force: forceLocation);
      if (!mounted || generation != _generation) return;
      final noZone = place.timeZone.trim().isEmpty;
      final offset = noZone && identical(place, natal.place)
          ? natal.utcOffsetMinutes
          : null;
      if (noZone && offset == null) {
        throw const FormatException(
          'This place has no time zone. Choose another place.',
        );
      }
      final DateTime utc;
      if (_useNow) {
        final now = (widget.clock?.call() ?? DateTime.now()).toUtc();
        utc = DateTime.utc(now.year, now.month, now.day, now.hour, now.minute);
      } else {
        utc = AstrologyTime.parseBirthTime(
          date: _date,
          time: _time.trim().isEmpty ? '12:00' : _time,
          place: place,
          offsetMinutes: offset,
          now: widget.clock?.call().toUtc(),
        );
      }
      final moment = AstrologyInput(
        name: natal.name,
        utc: utc,
        place: place,
        utcOffsetMinutes: offset,
        style: natal.style,
        ayanamsa: natal.ayanamsa,
        ayanamsaOffsetArcseconds: natal.ayanamsaOffsetArcseconds,
        trueNode: natal.trueNode,
        dashaYearDays: natal.dashaYearDays,
      );
      final analysis = await (widget.analyzer ?? _analyze)(natal, moment);
      if (!mounted || generation != _generation) return;
      setState(() {
        _analysis = analysis;
        _place = place;
        _loading = false;
      });
    } on Object catch (error) {
      if (!mounted || generation != _generation) return;
      setState(() {
        _error = error is FormatException ? error.message : '$error';
        _loading = false;
      });
    }
  }

  Future<void> _pickDate(BuildContext anchor) async {
    final place = _place ?? widget.natal.place;
    final probe = AstrologyInput(place: place);
    DateTime localNow;
    try {
      localNow = AstrologyTime.localTime(
        probe,
        (widget.clock?.call() ?? DateTime.now()).toUtc(),
      );
    } on Object {
      localNow = DateTime.now();
    }
    final moment = _analysis?.moment;
    final shown =
        moment == null ? '' : astrologyLocalDate(moment.input, moment.utc);
    final selection = await showAstrologyDateTimePicker(
      context: anchor,
      date: _useNow ? shown : _date,
      time: _useNow ? '' : _time,
      localNow: localNow,
      timeZoneLabel: place?.timeZone ?? '',
    );
    if (selection == null || !mounted) return;
    setState(() {
      _useNow = false;
      _date = selection.date;
      _time = selection.time;
    });
    unawaited(_load());
  }

  void _setNow() {
    setState(() {
      _useNow = true;
      _date = '';
      _time = '';
    });
    unawaited(_load());
  }

  void _clearTime() {
    if (_useNow) {
      final moment = _analysis?.moment;
      _date =
          moment == null ? '' : astrologyLocalDate(moment.input, moment.utc);
    }
    setState(() {
      _useNow = false;
      _time = '';
    });
    unawaited(_load());
  }

  void _setMode(_PlaceMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      if (mode != _PlaceMode.other) {
        _results = const [];
        _searchMessage = null;
      }
    });
    if (mode != _PlaceMode.other || _other != null) unawaited(_load());
  }

  void _searchChanged(String query) {
    _searchTimer?.cancel();
    final generation = ++_searchGeneration;
    if (query.trim().length < 2) {
      setState(() {
        _results = const [];
        _searching = false;
        _searchMessage = null;
      });
      return;
    }
    _searchTimer = Timer(const Duration(milliseconds: 350), () async {
      if (!mounted || generation != _searchGeneration) return;
      setState(() => _searching = true);
      try {
        final results = await _locations.search(query);
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _results = results.take(6).toList();
          _searching = false;
          _searchMessage = results.isEmpty ? 'No places found.' : null;
        });
      } on Object {
        if (!mounted || generation != _searchGeneration) return;
        setState(() {
          _results = const [];
          _searching = false;
          _searchMessage = 'Place search is unavailable. Check the connection.';
        });
      }
    });
  }

  void _choose(AstrologyPlace place) {
    _searchGeneration++;
    _searchTimer?.cancel();
    setState(() {
      _other = place;
      _results = const [];
      _searchMessage = null;
      _search.text = place.name;
    });
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    if (widget.preview) {
      return _message(
        palette,
        'Pick any date to see its dashas, transits, panchanga and muhurta. '
        'No location is requested in a preview.',
      );
    }
    if (!_active) {
      return _message(palette, 'Enable Vedic astrology in Extensions.');
    }
    final theme = Theme.of(context);
    final analysis = _analysis;
    return ColoredBox(
      key: const ValueKey('astrology-date-analysis-surface'),
      color: palette.surface,
      child: Theme(
        data: theme.copyWith(
          hoverColor: palette.hover,
          focusColor: palette.selection,
          highlightColor: palette.hover,
          splashColor: palette.selection,
          colorScheme: theme.colorScheme.copyWith(
            surfaceTint: palette.surface.withValues(alpha: 0),
          ),
          textSelectionTheme: TextSelectionThemeData(
            cursorColor: palette.accent,
            selectionColor: palette.selection,
            selectionHandleColor: palette.accent,
          ),
        ),
        child: SizedBox.expand(
          child: ScrollConfiguration(
            behavior: NoScrollbarBehavior(ScrollConfiguration.of(context)),
            child: SingleChildScrollView(
              key: const ValueKey('astrology-date-analysis-scroll'),
              controller: _scroll,
              primary: false,
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  _controls(context, palette),
                  const SizedBox(height: 12),
                  if (_error != null)
                    _errorBox(palette, _error!)
                  else if (analysis == null)
                    const Center(
                      child: Padding(
                        padding: EdgeInsets.all(16),
                        child: SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    )
                  else
                    ..._sections(context, palette, analysis),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, AstrologyPalette palette) {
    final moment = _analysis?.moment;
    final String whenLabel;
    if (_useNow) {
      whenLabel = moment == null
          ? 'Now'
          : 'Now · ${astrologyLocalDate(moment.input, moment.utc)} '
              '${astrologyLocalClock(moment.input, moment.utc)}';
    } else {
      final day = _date.isEmpty ? 'Today' : _date;
      final clock = _time.trim().isEmpty ? 'noon (no time)' : _time;
      whenLabel = '$day · $clock';
    }
    final natalPlace = widget.natal.place;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Builder(
          builder: (anchor) => _ControlButton(
            key: const ValueKey('astrology-date-analysis-when'),
            icon: Icons.event_rounded,
            label: whenLabel,
            tooltip: 'Choose a date and optional time',
            onPressed: () => unawaited(_pickDate(anchor)),
          ),
        ),
        if (!_useNow)
          _ControlButton(
            key: const ValueKey('astrology-date-analysis-now'),
            icon: Icons.schedule_rounded,
            label: 'Now',
            onPressed: _setNow,
          ),
        if (_useNow || _time.trim().isNotEmpty)
          _ControlButton(
            key: const ValueKey('astrology-date-analysis-noon'),
            icon: Icons.wb_sunny_rounded,
            label: 'Date only (noon)',
            onPressed: _clearTime,
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.control,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<_PlaceMode>(
                key: const ValueKey('astrology-date-analysis-place'),
                value: _mode,
                dropdownColor: palette.raised,
                focusColor: palette.hover,
                borderRadius: BorderRadius.circular(10),
                style: _style(context, palette.ink, 13),
                icon: WorkspaceGlyph(
                  Icons.expand_more_rounded,
                  color: palette.muted,
                  role: WorkspaceGlyphRole.preserveInk,
                ),
                items: [
                  DropdownMenuItem(
                    value: _PlaceMode.birth,
                    child: Text(
                      natalPlace == null || natalPlace.name.isEmpty
                          ? 'Birthplace'
                          : 'Birthplace · ${natalPlace.name}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const DropdownMenuItem(
                    value: _PlaceMode.current,
                    child: Text('Current location'),
                  ),
                  const DropdownMenuItem(
                    value: _PlaceMode.other,
                    child: Text('Another place…'),
                  ),
                ],
                onChanged: (mode) {
                  if (mode != null) _setMode(mode);
                },
              ),
            ),
          ),
        ),
        if (_loading)
          const SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
        if (_mode == _PlaceMode.other) _placeSearch(context, palette),
      ],
    );
  }

  Widget _placeSearch(BuildContext context, AstrologyPalette palette) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 420),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            key: const ValueKey('astrology-date-analysis-place-search'),
            controller: _search,
            onChanged: _searchChanged,
            style: _style(context, palette.ink, 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Search a city or place',
              hintStyle: _style(context, palette.muted, 13),
              filled: true,
              fillColor: palette.control,
              prefixIcon: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: WorkspaceGlyph(
                  Icons.search_rounded,
                  color: palette.muted,
                ),
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 38, minHeight: 34),
              suffixIcon: _searching
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: SizedBox.square(
                        dimension: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : null,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          if (_searchMessage != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(
                _searchMessage!,
                style: _style(context, palette.muted, 12),
              ),
            ),
          if (_results.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                color: palette.raised,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: palette.line),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final place in _results)
                    InkWell(
                      onTap: () => _choose(place),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            WorkspaceGlyph(
                              Icons.place_rounded,
                              size: 16,
                              color: palette.muted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                place.name,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: _style(context, palette.ink, 13),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  List<Widget> _sections(
    BuildContext context,
    AstrologyPalette palette,
    AstrologyDateAnalysis analysis,
  ) {
    final moment = analysis.moment;
    final input = moment.input;
    final offset = AstrologyTime.offsetAt(input, moment.utc);
    final local = AstrologyTime.localTime(input, moment.utc);
    String at(DateTime? utc) => utc == null
        ? '—'
        : astrologyLocalTimeLabel(input, utc, referenceUtc: moment.utc);
    final moon = moment.planet(VedicBody.moon);
    final nakshatra = nakshatraIndex(moon.longitude);
    final halfTithi = (moment.elongation / 6).floor();
    final natal = analysis.natal;
    final noTime = !_useNow && _time.trim().isEmpty;
    final tara = analysis.tara;
    final taraQuality = switch (tara?.favourable) {
      true => 'favourable',
      false => 'unfavourable',
      null => 'mixed',
    };
    final chandra = analysis.chandra;
    final chandraQuality = chandra == null
        ? ''
        : chandra.house == 8
            ? 'Ashtama Chandra, avoid'
            : chandra.favourable
                ? 'favourable'
                : 'unfavourable';
    final hora = analysis.hora;
    return [
      Text(
        '${weekdayNames[local.weekday % 7]}, '
        '${astrologyLocalDate(input, moment.utc)} · '
        '${astrologyLocalClock(input, moment.utc)} '
        '${astrologyOffsetLabel(offset)}'
        '${input.place == null || input.place!.name.isEmpty ? '' : ' · ${input.place!.name}'}',
        key: const ValueKey('astrology-date-analysis-heading'),
        style: _style(context, palette.ink, 14, weight: FontWeight.w600),
      ),
      if (noTime)
        Padding(
          padding: const EdgeInsets.only(top: 2),
          child: Text(
            'No time given: noon is used. Add a time for the exact Moon, '
            'Sookshma dasha and hora.',
            style: _style(context, palette.muted, 12),
          ),
        ),
      _Heading('Natal dasha on this date', palette: palette),
      if (natal == null)
        _note(
          context,
          palette,
          'Save a birth date, time and place above to see dashas and '
          'natal houses.',
        )
      else if (analysis.dasha.isEmpty)
        _note(
          context,
          palette,
          'This date is outside the natal 120-year Vimshottari cycle.',
        )
      else
        _Table(
          id: 'astrology-date-analysis-dasha',
          headings: const ['Level', 'Lord', 'From', 'Until'],
          widths: const [1.5, 1.1, 1.6, 1.6],
          rows: [
            for (final period in analysis.dasha)
              [
                vimshottariLevelNames[period.level],
                period.lord.label,
                _dashaDate(natal.input, period.start),
                _dashaDate(natal.input, period.end),
              ],
          ],
          tint: {
            for (var row = 0; row < analysis.dasha.length; row++)
              (row, 1): analysis.dasha[row].lord,
          },
        ),
      _Heading('Transits', palette: palette),
      _Table(
        id: 'astrology-date-analysis-transits',
        headings: [
          'Graha',
          'Position',
          'Nakshatra',
          if (natal != null) ...['From Lagna', 'From Moon'],
        ],
        widths: [
          1.1,
          1.5,
          1.6,
          if (natal != null) ...[0.9, 0.9],
        ],
        rows: [
          for (final transit in analysis.transits)
            [
              '${transit.placement.name}'
                  '${transit.placement.retrograde ? ' (R)' : ''}',
              compactLongitude(transit.placement.longitude),
              '${transit.placement.nakshatra} ${transit.placement.pada}',
              if (natal != null) ...[
                ordinal(transit.fromLagna!),
                ordinal(transit.fromMoon!),
              ],
            ],
        ],
        tint: {
          for (var row = 0; row < analysis.transits.length; row++)
            (row, 0): analysis.transits[row].placement.body,
        },
      ),
      if (analysis.saturn != null)
        _note(context, palette, analysis.saturn!, emphasis: true),
      _Heading('Panchanga', palette: palette),
      _Facts(
        facts: [
          (
            'Vara',
            '${weekdayNames[moment.weekday]} · lord '
                '${weekdayLords[moment.weekday].label}',
          ),
          (
            'Tithi',
            '${pakshaName(moment.tithi)} ${tithiName(moment.tithi)} '
                '(${moment.tithi}/30) · until ${at(analysis.times.tithiEnd)}',
          ),
          (
            'Nakshatra',
            '${nakshatraNames[nakshatra]} pada ${moon.pada} · lord '
                '${nakshatraLord(nakshatra).label} · until '
                '${at(analysis.times.nakshatraEnd)}',
          ),
          (
            'Yoga',
            '${yogaNames[moment.yoga]} · until ${at(analysis.times.yogaEnd)}',
          ),
          (
            'Karana',
            '${karanaName(halfTithi)} · until ${at(analysis.times.karanaEnd)}',
          ),
          (
            'Sunrise / sunset',
            moment.sunrise == null
                ? 'Unavailable (polar day or night)'
                : '${at(moment.sunrise)} / ${at(moment.sunset)}',
          ),
          (
            'Moon sign',
            '${zodiacNames[moon.sign]} · Sun in '
                '${zodiacNames[moment.planet(VedicBody.sun).sign]}',
          ),
        ],
      ),
      _Heading('Muhurta', palette: palette),
      if (analysis.muhurtas.isEmpty)
        _note(
          context,
          palette,
          'Muhurta windows need a sunrise and sunset at this place.',
        )
      else
        _Facts(
          facts: [
            for (final window in analysis.muhurtas)
              (
                '${window.name}'
                    '${window.contains(moment.utc) ? ' · now' : ''}',
                '${at(window.start)} – ${at(window.end)}\n'
                    '${window.quality == MuhurtaQuality.avoid ? 'Avoid' : 'Favourable'}'
                    '${window.note.isEmpty ? '' : ' · ${window.note}'}',
              ),
            if (hora != null)
              (
                'Hora',
                '${hora.lord.label} · ${at(hora.start)} – ${at(hora.end)} '
                    '(${hora.isDay ? 'day' : 'night'} hora '
                    '${(hora.number - 1) % 12 + 1}/12)',
              ),
            if (tara != null)
              (
                'Tara bala',
                '${tara.name} (${tara.tara}) · $taraQuality · '
                    '${ordinal(tara.count)} from the birth star',
              ),
            if (chandra != null)
              (
                'Chandra bala',
                'Moon ${ordinal(chandra.house)} from the natal Moon · '
                    '$chandraQuality',
              ),
          ],
        ),
    ];
  }

  String _dashaDate(AstrologyInput natal, DateTime utc) =>
      '${astrologyLocalDate(natal, utc)} ${astrologyLocalClock(natal, utc)}';

  Widget _note(
    BuildContext context,
    AstrologyPalette palette,
    String text, {
    bool emphasis = false,
  }) =>
      Padding(
        padding: const EdgeInsets.only(top: 6),
        child: Text(
          text,
          style: _style(
            context,
            emphasis ? palette.accent : palette.muted,
            12.5,
            weight: emphasis ? FontWeight.w600 : null,
          ),
        ),
      );

  Widget _errorBox(AstrologyPalette palette, String text) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph(
            Icons.location_off_rounded,
            color: palette.danger,
            size: 24,
            role: WorkspaceGlyphRole.preserveInk,
          ),
          const SizedBox(height: 6),
          Text(
            text,
            textAlign: TextAlign.center,
            style: _style(context, palette.muted, 12.5),
          ),
          TextButton(
            onPressed: () => unawaited(_load(forceLocation: true)),
            child: const Text('Retry'),
          ),
        ],
      );

  Widget _message(AstrologyPalette palette, String text) => ColoredBox(
        color: palette.surface,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              text,
              textAlign: TextAlign.center,
              style: _style(context, palette.muted, 12.5),
            ),
          ),
        ),
      );
}

TextStyle _style(
  BuildContext context,
  Color color,
  double size, {
  FontWeight? weight,
}) {
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .merge(DefaultTextStyle.of(context).style);
  return base.copyWith(
    color: color,
    fontSize: size,
    height: 1.4,
    fontWeight: weight,
    fontFeatures: [
      ...?base.fontFeatures,
      const ui.FontFeature.tabularFigures(),
    ],
  );
}

class _ControlButton extends StatelessWidget {
  const _ControlButton({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.tooltip,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) => AstrologyButton(
        label: label,
        icon: icon,
        tooltip: tooltip,
        onPressed: onPressed,
      );
}

class _Heading extends StatelessWidget {
  const _Heading(this.text, {required this.palette});

  final String text;
  final AstrologyPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 6),
        child: Text(
          text,
          style: _style(context, palette.accent, 13.5, weight: FontWeight.w600),
        ),
      );
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});

  final List<(String, String)> facts;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = ((constraints.maxWidth + 8) / 240).floor().clamp(1, 4);
        final width = (constraints.maxWidth - (columns - 1) * 8) / columns;
        return Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final fact in facts)
              SizedBox(
                width: width,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: palette.control,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(10),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          fact.$1,
                          style: _style(context, palette.muted, 12),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          fact.$2,
                          style: _style(context, palette.ink, 13),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _Table extends StatefulWidget {
  const _Table({
    required this.id,
    required this.headings,
    required this.widths,
    required this.rows,
    this.tint = const {},
  });

  final String id;
  final List<String> headings;
  final List<double> widths;
  final List<List<String>> rows;

  /// (row, column) → planet whose ink colors that cell.
  final Map<(int, int), VedicBody?> tint;

  @override
  State<_Table> createState() => _TableState();
}

class _TableState extends State<_Table> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) => ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: _controller,
          primary: false,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: math.max(
              constraints.maxWidth,
              widget.widths.fold(0.0, (sum, width) => sum + width) * 90,
            ),
            child: Table(
              key: ValueKey(widget.id),
              defaultVerticalAlignment: TableCellVerticalAlignment.middle,
              columnWidths: {
                for (var column = 0; column < widget.widths.length; column++)
                  column: FlexColumnWidth(widget.widths[column]),
              },
              border: TableBorder(
                horizontalInside: BorderSide(
                  color: palette.line.withValues(alpha: 0.45),
                  width: 0.5,
                ),
              ),
              children: [
                TableRow(
                  decoration: BoxDecoration(color: palette.control),
                  children: [
                    for (final heading in widget.headings)
                      Padding(
                        padding: const EdgeInsets.all(7),
                        child: Text(
                          heading,
                          style: _style(context, palette.muted, 12),
                        ),
                      ),
                  ],
                ),
                for (var row = 0; row < widget.rows.length; row++)
                  TableRow(
                    children: [
                      for (var column = 0;
                          column < widget.rows[row].length;
                          column++)
                        Padding(
                          padding: const EdgeInsets.all(7),
                          child: Text(
                            widget.rows[row][column],
                            style: _style(
                              context,
                              widget.tint.containsKey((row, column))
                                  ? palette.planetColor(
                                      widget.tint[(row, column)],
                                    )
                                  : palette.ink,
                              13,
                            ),
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
