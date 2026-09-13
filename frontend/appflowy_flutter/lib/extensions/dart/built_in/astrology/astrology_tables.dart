import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:flutter/material.dart';

import 'ashtakavarga.dart';
import 'astrology_model.dart';
import 'astrology_strength_chart.dart';
import 'astrology_style.dart';
import 'astrology_time.dart';
import 'jaimini_karakas.dart';
import 'shadbala.dart';
import 'vedic_chart_view.dart';
import 'vimshottari.dart';

export 'astrology_dasha_view.dart' show AstrologyDashaTable;

/// Read-only contents for a bounded card or an Expanded dialog child.
/// Only supplied placements are listed; missing special lagnas are not invented.
class AstrologyPlacementsTable extends StatefulWidget {
  const AstrologyPlacementsTable({super.key, required this.chart});

  final AstrologyChart chart;

  @override
  State<AstrologyPlacementsTable> createState() =>
      _AstrologyPlacementsTableState();
}

class _AstrologyPlacementsTableState extends State<AstrologyPlacementsTable> {
  JaiminiKarakaScheme _scheme = JaiminiKarakaScheme.seven;

  @override
  Widget build(BuildContext context) {
    final chart = widget.chart;
    JaiminiKarakaResult? karakas;
    String? karakaError;
    try {
      karakas = calculateJaiminiKarakas(chart.planets, scheme: _scheme);
    } on FormatException catch (error) {
      karakaError = error.message;
    }
    return _Contents(
      id: 'astrology-placements',
      children: [
        const _Value('Sidereal D-1 placements', fontSize: 15),
        const SizedBox(height: 10),
        _Select<JaiminiKarakaScheme>(
          id: 'jaimini-karaka-scheme',
          label: 'Jaimini chara karakas',
          value: _scheme,
          options: {
            for (final scheme in JaiminiKarakaScheme.values)
              scheme: scheme.label,
          },
          onSelected: (scheme) => setState(() => _scheme = scheme),
        ),
        const SizedBox(height: 12),
        _ReadingTable(
          id: 'placements',
          headings: const [
            'Body / point',
            'Longitude (DMS)',
            'Jaimini karaka',
            'Retrograde',
            'Speed (°/day)',
            'Nakshatra',
            'Pada',
            'D-1 sign',
            'D-9 sign',
            'Whole-sign house',
          ],
          widths: const [150, 170, 150, 115, 130, 160, 65, 120, 120, 120],
          rows: [
            for (final placement in chart.placements)
              [
                _Value(
                  placement.body?.label ?? placement.name,
                  key: ValueKey('placements-${placement.shortName}-name'),
                  tinted: true,
                  body: placement.body,
                ),
                _Value(
                  placement.formatted,
                  key: ValueKey('placements-${placement.shortName}-longitude'),
                ),
                _Value(
                  karakas?.forBody(placement.body)?.abbreviation ??
                      (karakaError != null &&
                              (VedicBody.classical.contains(placement.body) ||
                                  (_scheme == JaiminiKarakaScheme.eight &&
                                      placement.body == VedicBody.rahu))
                          ? 'Unavailable'
                          : '—'),
                  key: ValueKey('placements-${placement.shortName}-karaka'),
                ),
                _Value(
                  placement.body == null
                      ? 'Not applicable'
                      : placement.retrograde
                          ? 'Yes'
                          : 'No',
                  key: ValueKey(
                    'placements-${placement.shortName}-retrograde',
                  ),
                ),
                _Value(
                  placement.body == null
                      ? 'Not applicable'
                      : _number(placement.speed, digits: 4),
                  key: ValueKey('placements-${placement.shortName}-speed'),
                ),
                _Value(
                  placement.nakshatra,
                  key: ValueKey('placements-${placement.shortName}-nakshatra'),
                ),
                _Value(
                  '${placement.pada}',
                  key: ValueKey('placements-${placement.shortName}-pada'),
                ),
                _Value(
                  zodiacNames[placement.sign],
                  key: ValueKey('placements-${placement.shortName}-d1'),
                ),
                _Value(
                  zodiacNames[divisionalSign(placement.longitude, 9)],
                  key: ValueKey('placements-${placement.shortName}-d9'),
                ),
                _Value(
                  '${(placement.sign - zodiacSign(chart.ascendant)) % 12 + 1}',
                  key: ValueKey('placements-${placement.shortName}-house'),
                ),
              ],
          ],
        ),
        const SizedBox(height: 10),
        const _Value(
          'Degrees, nakshatra and pada use the original D-1 longitude. '
          'D-9 uses the Parashari Navamsha sign mapping. '
          'Arudha positions are not supplied by this chart; no degrees '
          'are fabricated for them.',
          muted: true,
        ),
        const SizedBox(height: 16),
        const _Value(
          'Jaimini Karaka details',
          key: ValueKey('jaimini-karaka-heading'),
          fontSize: 15,
        ),
        const SizedBox(height: 8),
        _Value(
          '${_scheme.label}. Ranked by unrounded degrees within the D-1 sign, '
          'highest first (AK) through lowest (DK). '
          '${_scheme == JaiminiKarakaScheme.eight ? 'Rahu uses 30° minus its degree within the sign; Pitri is included. ' : 'Rahu and Ketu are excluded; Pitri is not a separate role. '}'
          'Retrograde motion does not reverse the other planets. '
          'Ketu and special lagnas are not chara karakas. '
          'Significations are traditional associations, not predictions.',
          key: const ValueKey('jaimini-karaka-method'),
          muted: true,
        ),
        if (karakaError != null) ...[
          const SizedBox(height: 8),
          _Value(karakaError, key: const ValueKey('jaimini-karaka-error')),
        ],
        if (karakas != null) ...[
          if (karakas.hasTies) ...[
            const SizedBox(height: 8),
            const _Value(
              'Tied ranking degrees: the affected roles are unresolved and '
              'listed together, not arbitrarily assigned. No secondary '
              'tie-breaking convention has been assumed.',
              key: ValueKey('jaimini-karaka-tie-warning'),
              muted: true,
            ),
          ],
          const SizedBox(height: 10),
          _ReadingTable(
            id: 'jaimini-karakas',
            headings: const [
              'Karaka',
              'Planet',
              'Ranking degree',
              'Traditional signification',
            ],
            widths: const [230, 130, 170, 250],
            rows: [
              for (final assignment in karakas.assignments)
                [
                  _Value(
                    assignment.karakas
                            .map(
                              (karaka) =>
                                  '${karaka.abbreviation} · ${karaka.label}',
                            )
                            .join(' / ') +
                        (assignment.isTied ? ' (tie)' : ''),
                    key: ValueKey(
                      'jaimini-${assignment.placement.body!.name}-role',
                    ),
                  ),
                  _Value(
                    assignment.placement.body!.label,
                    body: assignment.placement.body,
                    tinted: true,
                  ),
                  _Value(
                    '${assignment.rankDegrees.toStringAsFixed(8)}°',
                    key: ValueKey(
                      'jaimini-${assignment.placement.body!.name}-degree',
                    ),
                  ),
                  _Value(
                    assignment.karakas
                        .map((karaka) => karaka.signification)
                        .join(' / '),
                  ),
                ],
            ],
          ),
        ],
        for (final warning in chart.warnings) ...[
          const SizedBox(height: 8),
          _Value(warning, muted: true),
        ],
      ],
    );
  }
}

/// Panchanga facts at the chart's instant, without predictions or services.
class AstrologyPanchangaView extends StatefulWidget {
  const AstrologyPanchangaView({super.key, required this.chart});

  final AstrologyChart chart;

  @override
  State<AstrologyPanchangaView> createState() => _AstrologyPanchangaViewState();
}

class _AstrologyPanchangaViewState extends State<AstrologyPanchangaView> {
  late List<_Fact> _facts;

  @override
  void initState() {
    super.initState();
    _facts = _panchangaFacts(widget.chart);
  }

  @override
  void didUpdateWidget(covariant AstrologyPanchangaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chart, widget.chart)) {
      _facts = _panchangaFacts(widget.chart);
    }
  }

  @override
  Widget build(BuildContext context) => _Contents(
        id: 'astrology-panchanga',
        children: [
          _Facts(facts: _facts),
          const SizedBox(height: 12),
          const _Value(
            'Solar times describe the Vedic day surrounding this instant: '
            'sunrise can be on the preceding civil date. '
            'These are calculated calendar facts, not interpretations.',
            muted: true,
          ),
          for (final warning in widget.chart.warnings) ...[
            const SizedBox(height: 8),
            _Value(warning, muted: true),
          ],
        ],
      );
}

/// Seven-planet strength graph, full numeric table, and component breakdown.
class AstrologyShadbalaView extends StatefulWidget {
  const AstrologyShadbalaView({super.key, required this.chart});

  final AstrologyChart chart;

  @override
  State<AstrologyShadbalaView> createState() => _AstrologyShadbalaViewState();
}

class _AstrologyShadbalaViewState extends State<AstrologyShadbalaView> {
  late List<ShadbalaRow> _rows;
  bool _table = false;
  bool _methodDetails = false;
  VedicBody? _body;

  @override
  void initState() {
    super.initState();
    _readChart();
  }

  void _readChart() {
    _rows = calculateShadbala(widget.chart);
  }

  @override
  void didUpdateWidget(covariant AstrologyShadbalaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chart, widget.chart)) _readChart();
  }

  @override
  Widget build(BuildContext context) {
    final row = _rows.firstWhere(
      (row) => row.body == (_body ?? VedicBody.sun),
    );
    return _Contents(
      id: 'astrology-shadbala',
      children: [
        const _Value(
          'Shadbala',
          key: ValueKey('shadbala-title'),
          fontSize: 15,
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _Action(
              key: const ValueKey('shadbala-graph-toggle'),
              label: 'Graph',
              selected: !_table,
              onPressed: () => setState(() => _table = false),
            ),
            _Action(
              key: const ValueKey('shadbala-table-toggle'),
              label: 'Table',
              selected: _table,
              onPressed: () => setState(() => _table = true),
            ),
            _Action(
              key: const ValueKey('shadbala-method-details-toggle'),
              label: 'Method details',
              selected: _methodDetails,
              onPressed: () => setState(() => _methodDetails = !_methodDetails),
            ),
          ],
        ),
        if (_methodDetails) ...[
          const SizedBox(height: 10),
          const _Value(
            shadbalaMethod,
            key: ValueKey('shadbala-method'),
          ),
          const SizedBox(height: 6),
          const _Value(
            shadbalaMethodDetails,
            key: ValueKey('shadbala-method-details'),
            muted: true,
          ),
        ],
        if (_rows.any((row) => row.kala == null)) ...[
          const SizedBox(height: 10),
          const _Value(
            'Sunrise/sunset could not bracket this instant (polar day/night '
            'or missing solar events). Kala and full totals are Unavailable; '
            'missing components are not zero estimates.',
            key: ValueKey('shadbala-unavailable-note'),
            muted: true,
          ),
        ],
        const SizedBox(height: 12),
        if (_table)
          _ReadingTable(
            id: 'shadbala',
            headings: const [
              'Planet',
              'Sthana',
              'Dig',
              'Kala',
              'Cheshta',
              'Naisargika',
              'Drik',
              'Total (virupas)',
              'Total (rupas)',
              'Required (virupas)',
              'Ratio',
            ],
            widths: const [110, 95, 80, 110, 95, 110, 90, 130, 110, 140, 100],
            rows: [
              for (final strength in _rows)
                [
                  _Value(
                    strength.body.label,
                    key: ValueKey('shadbala-${strength.body.name}-name'),
                    tinted: true,
                    body: strength.body,
                  ),
                  for (final entry in _strengthValues(strength).entries)
                    _Value(
                      _number(
                        entry.value,
                        digits: entry.key == 'ratio' ? 3 : 2,
                      ),
                      key: ValueKey(
                        'shadbala-${strength.body.name}-${entry.key}',
                      ),
                    ),
                ],
            ],
          )
        else ...[
          const _Value(
            'Total ÷ minimum × 100. Hover or focus for raw strengths; select a planet '
            'to keep its breakdown below. Pan horizontally in narrow cards.',
            muted: true,
          ),
          const SizedBox(height: 10),
          AstrologyStrengthChart(
            rows: _rows,
            selected: _body,
            onSelected: (body) => setState(() => _body = body),
          ),
        ],
        const SizedBox(height: 12),
        _Select<VedicBody>(
          id: 'shadbala-breakdown-body',
          label: 'Component breakdown',
          value: row.body,
          options: {for (final body in VedicBody.classical) body: body.label},
          onSelected: (body) => setState(() => _body = body),
        ),
        const SizedBox(height: 8),
        _Value(
          '${row.body.label} · ${row.motion}',
          key: const ValueKey('shadbala-motion'),
        ),
        const SizedBox(height: 8),
        _Facts(
          facts: [
            for (final entry in row.breakdown.entries)
              _Fact(
                'shadbala-breakdown-${entry.key}',
                '${entry.key} (virupas)',
                _number(
                  row.kala == null && _solarComponents.contains(entry.key)
                      ? null
                      : entry.value,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

const _solarComponents = {
  'Tribhaga',
  'Varsha',
  'Masa',
  'Dina',
  'Hora',
  'Yuddha',
};

Map<String, double?> _strengthValues(ShadbalaRow row) => {
      'sthana': row.sthana,
      'dig': row.dig,
      'kala': row.kala,
      'cheshta': row.cheshta,
      'naisargika': row.naisargika,
      'drik': row.drik,
      'total': row.total,
      'rupas': row.rupas,
      'required': row.required,
      'ratio': row.ratio,
    };

/// Unreduced BAV/SAV charts and inspectable contributor-by-sign bindus.
/// The default overview includes SAV, all seven planetary BAVs and Lagna BAV.
class AstrologyAshtakavargaView extends StatefulWidget {
  const AstrologyAshtakavargaView({
    super.key,
    required this.chart,
    this.style,
  });

  final AstrologyChart chart;
  final IndianChartStyle? style;

  @override
  State<AstrologyAshtakavargaView> createState() =>
      _AstrologyAshtakavargaViewState();
}

class _AstrologyAshtakavargaViewState extends State<AstrologyAshtakavargaView> {
  late AshtakavargaResult _result;
  late List<VedicPlacement> _placements;
  int _subject = -1;
  int _sign = 0;
  bool _grid = true;
  bool _contributions = false;

  @override
  void initState() {
    super.initState();
    _readChart();
  }

  void _readChart() {
    _result = calculateAshtakavarga(widget.chart);
    _placements = widget.chart.placements;
  }

  @override
  void didUpdateWidget(covariant AstrologyAshtakavargaView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.chart, widget.chart)) _readChart();
  }

  List<int> _points(int subject) =>
      subject < 0 ? _result.sarva : _result.bhinna[subject];

  void _selectSubject(int subject) {
    setState(() {
      _subject = subject;
      _grid = false;
    });
  }

  int _contribution(int contributor) => _subject < 0
      ? _sum([
          for (var subject = 0; subject < 7; subject++)
            _result.prastara[subject][contributor][_sign],
        ])
      : _result.prastara[_subject][contributor][_sign];

  Widget _chart(int subject) => VedicChartView(
        key: ValueKey('ashtakavarga-chart-${subject < 0 ? 'sav' : subject}'),
        placements: _placements,
        ascendant: widget.chart.ascendant,
        style: widget.style ?? widget.chart.input.style,
        bindus: _points(subject),
        centerLabel: _ashtakavargaLabel(subject),
        onSignSelected: (sign) {
          setState(() {
            _subject = subject;
            _sign = sign;
            _contributions = true;
          });
        },
      );

  @override
  Widget build(BuildContext context) => _Contents(
        id: 'astrology-ashtakavarga',
        children: [
          _Value(
            'SAV · ${_sum(_result.sarva)} bindus',
            key: const ValueKey('ashtakavarga-sav-total'),
            fontSize: 15,
          ),
          const SizedBox(height: 6),
          const _Value(
            'Unreduced Parashari bindus. SAV sums the seven planetary BAVs '
            '(337 total); Lagna BAV is displayed separately, not added to SAV.',
            muted: true,
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: 260,
                child: _Select<int>(
                  id: 'ashtakavarga-subject',
                  label: 'Chart',
                  value: _subject,
                  options: {
                    for (var subject = -1; subject < 8; subject++)
                      subject: _ashtakavargaLabel(subject),
                  },
                  onSelected: _selectSubject,
                ),
              ),
              _Action(
                key: const ValueKey('ashtakavarga-grid-toggle'),
                label: 'All charts',
                selected: _grid,
                onPressed: () => setState(() => _grid = true),
              ),
              _Action(
                key: const ValueKey('ashtakavarga-single-toggle'),
                label: 'Single chart',
                selected: !_grid,
                onPressed: () => setState(() => _grid = false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_grid)
            LayoutBuilder(
              builder: (context, constraints) {
                final columns =
                    ((constraints.maxWidth + 12) / 232).floor().clamp(1, 4);
                final width =
                    (constraints.maxWidth - (columns - 1) * 12) / columns;
                return Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var subject = -1; subject < 8; subject++)
                      SizedBox(
                        width: width,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _Action(
                              key: ValueKey('ashtakavarga-open-$subject'),
                              label: _ashtakavargaLabel(subject),
                              selected: subject == _subject,
                              onPressed: () => _selectSubject(subject),
                            ),
                            _Value(
                              '${_sum(_points(subject))} bindus',
                              key: ValueKey('ashtakavarga-grid-total-$subject'),
                              muted: true,
                            ),
                            AspectRatio(aspectRatio: 1, child: _chart(subject)),
                          ],
                        ),
                      ),
                  ],
                );
              },
            )
          else
            Align(
              alignment: Alignment.topLeft,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 400),
                child: AspectRatio(aspectRatio: 1, child: _chart(_subject)),
              ),
            ),
          const SizedBox(height: 12),
          _Value(
            '${_ashtakavargaLabel(_subject)} · ${_sum(_points(_subject))} bindus',
            key: const ValueKey('ashtakavarga-selected-total'),
          ),
          const SizedBox(height: 8),
          _ReadingTable(
            id: 'ashtakavarga-signs',
            headings: const ['Sign', 'Whole-sign house', 'Bindus'],
            widths: const [140, 120, 90],
            rows: [
              for (var sign = 0; sign < 12; sign++)
                [
                  _Value(zodiacNames[sign]),
                  _Value(
                    '${(sign - zodiacSign(widget.chart.ascendant)) % 12 + 1}',
                  ),
                  _Value(
                    '${_points(_subject)[sign]}',
                    key: ValueKey('ashtakavarga-points-$sign'),
                  ),
                ],
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _Action(
                key: const ValueKey('ashtakavarga-contributions-toggle'),
                label: 'Prastara contributions',
                selected: _contributions,
                onPressed: () =>
                    setState(() => _contributions = !_contributions),
              ),
            ],
          ),
          if (_contributions) ...[
            const SizedBox(height: 8),
            _Select<int>(
              id: 'ashtakavarga-contribution-sign',
              label: 'Contribution sign',
              value: _sign,
              options: {
                for (var sign = 0; sign < 12; sign++) sign: zodiacNames[sign],
              },
              onSelected: (sign) => setState(() => _sign = sign),
            ),
            const SizedBox(height: 8),
            _Value(
              'Prastara · ${_ashtakavargaLabel(_subject)} · ${zodiacNames[_sign]}',
              key: const ValueKey('ashtakavarga-prastara-title'),
            ),
            const SizedBox(height: 6),
            _Value(
              _subject < 0
                  ? 'Each contributor is summed across the seven planetary BAVs. '
                      'Lagna contributes to those BAVs, but Lagna BAV itself '
                      'is excluded from SAV.'
                  : 'Each contributor supplies 0 or 1 bindu to this sign.',
              muted: true,
            ),
            const SizedBox(height: 8),
            _ReadingTable(
              id: 'ashtakavarga-prastara',
              headings: const ['Contributor', 'Bindus'],
              widths: const [150, 100],
              rows: [
                for (var contributor = 0; contributor < 8; contributor++)
                  [
                    _Value(_contributorLabel(contributor)),
                    _Value(
                      '${_contribution(contributor)}',
                      key: ValueKey('ashtakavarga-contribution-$contributor'),
                    ),
                  ],
              ],
            ),
            _Value(
              'Contribution total: ${_points(_subject)[_sign]} bindus',
              key: const ValueKey('ashtakavarga-contribution-total'),
            ),
          ],
        ],
      );
}

String _ashtakavargaLabel(int subject) =>
    subject < 0 ? 'SAV' : '${_contributorLabel(subject)} BAV';

String _contributorLabel(int contributor) =>
    contributor == 7 ? 'Lagna' : VedicBody.classical[contributor].label;

int _sum(Iterable<int> values) => values.fold(0, (sum, value) => sum + value);

const _tithiNames = [
  'Pratipada',
  'Dvitiya',
  'Tritiya',
  'Chaturthi',
  'Panchami',
  'Shashthi',
  'Saptami',
  'Ashtami',
  'Navami',
  'Dashami',
  'Ekadashi',
  'Dvadashi',
  'Trayodashi',
  'Chaturdashi',
  'Purnima',
];
const _yogaNames = [
  'Vishkambha',
  'Priti',
  'Ayushman',
  'Saubhagya',
  'Shobhana',
  'Atiganda',
  'Sukarma',
  'Dhriti',
  'Shula',
  'Ganda',
  'Vriddhi',
  'Dhruva',
  'Vyaghata',
  'Harshana',
  'Vajra',
  'Siddhi',
  'Vyatipata',
  'Variyana',
  'Parigha',
  'Shiva',
  'Siddha',
  'Sadhya',
  'Shubha',
  'Shukla',
  'Brahma',
  'Indra',
  'Vaidhriti',
];
const _karanaNames = [
  'Bava',
  'Balava',
  'Kaulava',
  'Taitila',
  'Gara',
  'Vanija',
  'Vishti',
];
const _weekdayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

String _karanaName(int halfTithi) => switch (halfTithi) {
      0 => 'Kimstughna',
      57 => 'Shakuni',
      58 => 'Chatushpada',
      59 => 'Naga',
      _ => _karanaNames[(halfTithi - 1) % 7],
    };

List<_Fact> _panchangaFacts(AstrologyChart chart) {
  final input = chart.input;
  final place = input.place;
  final moon = chart.planet(VedicBody.moon);
  final first = vimshottariPeriods(
    birthUtc: chart.utc,
    moonLongitude: moon.longitude,
    yearDays: input.dashaYearDays,
  ).first;
  final tithiName =
      chart.tithi == 30 ? 'Amavasya' : _tithiNames[(chart.tithi - 1) % 15];
  final paksha =
      chart.tithi <= 15 ? 'Shukla Paksha (waxing)' : 'Krishna Paksha (waning)';
  final halfTithi = (chart.elongation / 6).floor();
  String solar(DateTime? time) => time == null
      ? 'Unavailable (polar day/night or missing solar event)'
      : _localMoment(input, time);
  return [
    _Fact(
      'panchanga-tithi',
      'Tithi',
      '$tithiName · $paksha · ${chart.tithi}/30\n'
          '${(chart.tithiRemaining * 100).toStringAsFixed(2)}% remaining '
          '(fraction ${chart.tithiRemaining.toStringAsFixed(6)})',
    ),
    _Fact(
      'panchanga-nakshatra',
      'Moon nakshatra / birth balance',
      '${moon.nakshatra} · Pada ${moon.pada}\n'
          'Lord: ${first.lord.label} · '
          '${_yearsBetween(chart.utc, first.end, input).toStringAsFixed(6)} '
          'years remaining (${input.dashaYearDays} days/year)',
    ),
    _Fact(
      'panchanga-yoga',
      'Yoga',
      '${_yogaNames[chart.yoga]} · ${chart.yoga + 1}/27',
    ),
    _Fact(
      'panchanga-karana',
      'Karana',
      '${_karanaName(halfTithi)} · half-tithi ${halfTithi + 1}/60',
    ),
    _Fact(
      'panchanga-vara',
      'Vara',
      '${_weekdayNames[chart.weekday]} · '
          '${chart.sunrise == null ? 'civil weekday; sunrise unavailable' : 'sunrise-based weekday'}',
    ),
    _Fact(
      'panchanga-local-time',
      'Local date / time',
      _localMoment(input, chart.utc),
    ),
    _Fact(
      'panchanga-place',
      'Place',
      place == null ? 'Unavailable' : place.name,
    ),
    _Fact(
      'panchanga-coordinates',
      'Coordinates',
      place == null
          ? 'Unavailable'
          : '${place.latitude.abs().toStringAsFixed(5)}° '
              '${place.latitude < 0 ? 'S' : 'N'} · '
              '${place.longitude.abs().toStringAsFixed(5)}° '
              '${place.longitude < 0 ? 'W' : 'E'}',
    ),
    _Fact('panchanga-zone', 'Time zone', _zoneLabel(input)),
    _Fact(
      'panchanga-offset',
      'UTC offset',
      _offsetLabel(AstrologyTime.offsetAt(input, chart.utc)),
    ),
    _Fact('panchanga-sunrise', 'Sunrise', solar(chart.sunrise)),
    _Fact('panchanga-sunset', 'Sunset', solar(chart.sunset)),
    _Fact('panchanga-next-sunrise', 'Next sunrise', solar(chart.nextSunrise)),
    _Fact(
      'panchanga-ayanamsa',
      'Ayanamsa',
      '${input.ayanamsaLabel} · ${_number(chart.ayanamsaDegrees, digits: 6)}°',
    ),
    _Fact('panchanga-rahu', 'Rahu', input.trueNode ? 'True node' : 'Mean node'),
    _Fact(
      'panchanga-ephemeris',
      'Ephemeris version',
      chart.ephemerisVersion.isEmpty
          ? 'Unavailable (not supplied with this chart)'
          : 'Swiss Ephemeris ${chart.ephemerisVersion} · bundled offline',
    ),
  ];
}

String _number(double? value, {int digits = 2}) =>
    value == null || !value.isFinite
        ? 'Unavailable'
        : value.toStringAsFixed(digits);

double _yearsBetween(DateTime start, DateTime end, AstrologyInput input) =>
    end.difference(start).inMicroseconds /
    (input.dashaYearDays * Duration.microsecondsPerDay);

String _two(int value) => value.toString().padLeft(2, '0');

String _offsetLabel(Duration offset) {
  final seconds = offset.inSeconds.abs() % 60;
  return 'UTC${AstrologyTime.offsetLabel(offset)}'
      '${seconds == 0 ? '' : ':${_two(seconds)}'}';
}

String _zoneLabel(AstrologyInput input) {
  final zone = input.place?.timeZone;
  if (input.utcOffsetMinutes != null) {
    return '${zone == null || zone.isEmpty ? '' : '$zone · '}'
        'fixed UTC offset override';
  }
  return zone == null || zone.isEmpty ? 'Device time zone' : zone;
}

String _localMoment(AstrologyInput input, DateTime utc) {
  final local = AstrologyTime.localTime(input, utc);
  return '${local.year.toString().padLeft(4, '0')}-${_two(local.month)}-${_two(local.day)} '
      '${_two(local.hour)}:${_two(local.minute)}:${_two(local.second)} '
      '${_offsetLabel(AstrologyTime.offsetAt(input, utc))}';
}

TextStyle _textStyle(BuildContext context, Color color, double fontSize) {
  final base = (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
      .merge(DefaultTextStyle.of(context).style);
  // Preserve both fontWeight and variable-font axes from the surrounding page.
  return base.copyWith(
    color: color,
    fontSize: fontSize,
    height: 1.4,
    fontFeatures: [
      ...?base.fontFeatures,
      const ui.FontFeature.tabularFigures(),
    ],
  );
}

class _Value extends StatelessWidget {
  const _Value(
    this.text, {
    super.key,
    this.muted = false,
    this.tinted = false,
    this.body,
    this.fontSize = 13,
  });

  final String text;
  final bool muted;
  final bool tinted;
  final VedicBody? body;
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return SelectableText(
      text,
      style: _textStyle(
        context,
        muted
            ? palette.muted
            : tinted
                ? palette.planetColor(body)
                : palette.ink,
        fontSize,
      ),
    );
  }
}

/// Owns the vertical viewport. All controls scroll too, so a 100px-high card
/// cannot overflow just because its toolbar wraps at 220px width.
class _Contents extends StatefulWidget {
  const _Contents({required this.id, required this.children});

  final String id;
  final List<Widget> children;

  @override
  State<_Contents> createState() => _ContentsState();
}

class _ContentsState extends State<_Contents> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    final theme = Theme.of(context);
    return ColoredBox(
      key: ValueKey('${widget.id}-surface'),
      color: palette.surface,
      // Dropdown routes capture this theme, so their hover/selection/shadow
      // and selectable text handles stay in the same paper-aware palette.
      child: Theme(
        data: theme.copyWith(
          hoverColor: palette.hover,
          focusColor: palette.selection,
          highlightColor: palette.hover,
          splashColor: palette.selection,
          shadowColor: palette.ink.withValues(alpha: 0.15),
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
              key: ValueKey('${widget.id}-scroll'),
              controller: _controller,
              primary: false,
              padding: const EdgeInsets.all(12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: widget.children,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A wide table owns a different horizontal controller; it never borrows the
/// card's vertical/primary controller. Row heights follow selectable text.
class _ReadingTable extends StatefulWidget {
  const _ReadingTable({
    required this.id,
    required this.headings,
    required this.widths,
    required this.rows,
  });

  final String id;
  final List<String> headings;
  final List<double> widths;
  final List<List<Widget>> rows;

  @override
  State<_ReadingTable> createState() => _ReadingTableState();
}

class _ReadingTableState extends State<_ReadingTable> {
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
          key: ValueKey('${widget.id}-horizontal-scroll'),
          controller: _controller,
          primary: false,
          scrollDirection: Axis.horizontal,
          padding: EdgeInsets.zero,
          child: SizedBox(
            width: math.max(
              constraints.maxWidth,
              widget.widths.fold(0.0, (sum, width) => sum + width),
            ),
            child: Table(
              key: ValueKey('${widget.id}-table'),
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
                        padding: const EdgeInsets.all(8),
                        child: _Value(heading, muted: true, fontSize: 12),
                      ),
                  ],
                ),
                for (final row in widget.rows)
                  TableRow(
                    children: [
                      for (final cell in row)
                        Padding(padding: const EdgeInsets.all(8), child: cell),
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

class _Fact {
  const _Fact(this.id, this.label, this.value);

  final String id;
  final String label;
  final String value;
}

class _Facts extends StatelessWidget {
  const _Facts({required this.facts});

  final List<_Fact> facts;

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
                        _Value(fact.label, muted: true, fontSize: 12),
                        const SizedBox(height: 4),
                        _Value(fact.value, key: ValueKey('${fact.id}-value')),
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

class _Action extends StatelessWidget {
  const _Action({
    super.key,
    required this.label,
    required this.onPressed,
    this.selected = false,
  });

  final String label;
  final VoidCallback onPressed;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return Semantics(
      selected: selected,
      child: TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: palette.ink,
          backgroundColor: selected ? palette.selection : palette.control,
          textStyle: _textStyle(context, palette.ink, 13),
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ).copyWith(
          overlayColor: WidgetStatePropertyAll(palette.hover),
          animationDuration: Duration.zero,
        ),
        child: Text(label),
      ),
    );
  }
}

class _Select<T extends Object> extends StatelessWidget {
  const _Select({
    required this.id,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String id;
  final String label;
  final T value;
  final Map<T, String> options;
  final ValueChanged<T> onSelected;

  @override
  Widget build(BuildContext context) {
    final palette = AstrologyPalette.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Value(label, muted: true, fontSize: 12),
        const SizedBox(height: 4),
        DecoratedBox(
          decoration: BoxDecoration(
            color: palette.control,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<T>(
                key: ValueKey(id),
                value: value,
                isExpanded: true,
                dropdownColor: palette.raised,
                focusColor: palette.hover,
                borderRadius: BorderRadius.circular(10),
                style: _textStyle(context, palette.ink, 13),
                icon: Icon(Icons.expand_more_rounded, color: palette.muted),
                items: [
                  for (final entry in options.entries)
                    DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value, overflow: TextOverflow.ellipsis),
                    ),
                ],
                onChanged: (value) {
                  if (value != null) onSelected(value);
                },
              ),
            ),
          ),
        ),
      ],
    );
  }
}
