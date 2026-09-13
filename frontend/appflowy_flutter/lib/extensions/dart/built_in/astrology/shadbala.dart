import 'dart:math' as math;

import 'astrology_model.dart';
import 'astrology_time.dart';

/// The legacy JHora 8 convention, checked against its component tables.
/// Keep these choices together rather than mixing different traditions.
const shadbalaMethod = 'Parashari · mean-longitude Cheshta';
const shadbalaMethodDetails =
    'Virupas (60 = 1 rupa). JHora 8 reference convention: whole-sign Kendradi; '
    'equal-house angular Dig and solar-arc Natonnata; natal compound '
    'friendships; 360-day/30-day year and month lords; equal hours from sunrise. '
    'Ayana uses the traditional 15° kranti table with a fixed 23° reference. '
    'The bright Moon is benefic; '
    'Mercury is malefic when sharing a sign with a malefic. '
    'Sun Ayana and Moon Paksha are doubled; their Cheshta is not counted again. '
    'Planetary Cheshta uses continuous mean-longitude kendra, not speed buckets. '
    'The Sun minimum is 300 virupas. Yuddha uses northern latitude and '
    'apparent disc diameters. Ephemeris versions and other JHora preferences '
    'can produce small differences.';

const _exaltation = [10.0, 33.0, 298.0, 165.0, 95.0, 357.0, 200.0];
const _required = [300.0, 360.0, 300.0, 420.0, 390.0, 330.0, 300.0];
// Fixed legacy weights, including Mercury's 25.70, verified in JHora's table.
const _natural = [60.0, 51.43, 17.14, 25.70, 34.28, 42.85, 8.57];
const shadbalaMeanSpeeds = [
  0.9856,
  13.1764,
  0.5240,
  4.0923,
  0.0831,
  1.6021,
  0.033439,
];
const _friendships = <List<int>>[
  [0, 1, 1, 0, 1, -1, -1],
  [1, 0, 0, 1, 0, 0, 0],
  [1, 1, 0, -1, 1, 0, 0],
  [1, -1, 0, 0, 0, 1, 0],
  [1, 1, 1, -1, 0, -1, 0],
  [-1, -1, 0, 1, 0, 0, 1],
  [-1, -1, -1, 1, 0, 1, 0],
];
const _weekdayLords = [
  VedicBody.sun,
  VedicBody.moon,
  VedicBody.mars,
  VedicBody.mercury,
  VedicBody.jupiter,
  VedicBody.venus,
  VedicBody.saturn,
];
const _horaSequence = [
  VedicBody.saturn,
  VedicBody.jupiter,
  VedicBody.mars,
  VedicBody.sun,
  VedicBody.venus,
  VedicBody.mercury,
  VedicBody.moon,
];

class ShadbalaRow {
  const ShadbalaRow({
    required this.body,
    required this.sthana,
    required this.dig,
    required this.kala,
    required this.cheshta,
    required this.naisargika,
    required this.drik,
    required this.breakdown,
    required this.motion,
  });
  final VedicBody body;
  final double sthana;
  final double dig;
  final double? kala;
  final double cheshta;
  final double naisargika;
  final double drik;
  final Map<String, double> breakdown;
  final String motion;
  double? get total =>
      kala == null ? null : sthana + dig + kala! + cheshta + naisargika + drik;
  double? get rupas => total == null ? null : total! / 60;
  double get required => _required[body.index];
  double? get ratio => total == null ? null : total! / required;
}

double uchchaBala(VedicBody body, double longitude) =>
    angularDistance(longitude, _exaltation[body.index] + 180) / 3;

/// Continuous Cheshta kendra. All three longitudes must share one frame.
/// Unwrap before averaging: the midpoint of 359° and 1° is 0°, not 180°.
double cheshtaKendraBala({
  required double meanLongitude,
  required double trueLongitude,
  required double apogeeLongitude,
}) {
  if (![meanLongitude, trueLongitude, apogeeLongitude]
      .every((value) => value.isFinite)) {
    throw ArgumentError('Cheshta requires finite longitudes.');
  }
  final displacement =
      normalizeDegrees(trueLongitude - meanLongitude + 180) - 180;
  final midpoint = meanLongitude + displacement / 2;
  return angularDistance(apogeeLongitude, midpoint) / 3;
}

/// Raman, Graha and Bhava Balas (1942), mean-motion tables §§87–107.
/// Epoch: 1900-01-01 midnight at 76°E LMT, NOT midnight UT or IST.
/// The argument is in the tabulated sidereal reference frame; the native
/// engine supplies its Lahiri reference so other presets/custom rotations
/// cannot accidentally mix their true longitude with an unrotated mean.
double meanLongitudeCheshtaBala({
  required VedicBody body,
  required double julianDay,
  required int year,
  required double referenceLongitude,
}) {
  if (!VedicBody.classical.contains(body) ||
      !julianDay.isFinite ||
      !referenceLongitude.isFinite) {
    throw ArgumentError(
      'A classical planet and finite coordinates are required.',
    );
  }
  if (body == VedicBody.sun || body == VedicBody.moon) return 0;
  const epochs = [257.4568, 0.0, 270.22, 164.0, 220.04, 328.51, 236.74];
  const rates = [
    0.98560265,
    0.0,
    0.524019,
    4.092318,
    0.08309596,
    1.602146,
    0.033439,
  ];
  final days = julianDay - 2415020.5 + 76 / 360;
  final years = year - 1900;
  final correction = switch (body) {
    VedicBody.mercury => 6.67 - 0.00133 * years,
    VedicBody.jupiter => -3.33 - 0.0067 * years,
    VedicBody.venus => -5 - 0.001 * years,
    VedicBody.saturn => 5 + 0.001 * years,
    _ => 0.0,
  };
  final meanSun = normalizeDegrees(epochs[0] + rates[0] * days);
  final meanPlanet = normalizeDegrees(
    epochs[body.index] + rates[body.index] * days + correction,
  );
  final inferior = body == VedicBody.mercury || body == VedicBody.venus;
  return cheshtaKendraBala(
    meanLongitude: inferior ? meanSun : meanPlanet,
    trueLongitude: referenceLongitude,
    apogeeLongitude: inferior ? meanPlanet : meanSun,
  );
}

/// Traditional 360-day years / 30-day months, not Gregorian Jan 1 / month 1.
/// The condensed ahargana starts inclusively on Wednesday, 1827-05-02.
({VedicBody year, VedicBody month}) shadbalaPeriodLords(DateTime vedicDate) {
  final day = DateTime.utc(vedicDate.year, vedicDate.month, vedicDate.day);
  final ahargana = day.difference(DateTime.utc(1827, 5, 2)).inDays + 1;
  return (
    year: _weekdayLords[(3 * (ahargana / 360).floor() + 3) % 7],
    month: _weekdayLords[(2 * (ahargana / 30).floor() + 3) % 7],
  );
}

/// Tabular kranti from a sidereal longitude and an explicit reference angle.
/// JHora 8's legacy Shadbala uses 23° (confirmed in 1900, 1999 and 2026),
/// not the chart's current ayanamsha or physical equatorial declination.
/// Neither the sidereal longitude nor `referenceDegrees` is rounded.
double tabularAyanaBala(
  VedicBody body,
  double siderealLongitude,
  double referenceDegrees,
) {
  if (!VedicBody.classical.contains(body) ||
      !siderealLongitude.isFinite ||
      !referenceDegrees.isFinite) {
    throw ArgumentError('Ayana requires a classical planet and finite angles.');
  }
  final longitude = normalizeDegrees(
    siderealLongitude + referenceDegrees,
  );
  final bhuja = math.min(
    angularDistance(longitude, 0),
    angularDistance(longitude, 180),
  );
  // Cumulative declination arcminutes at 0,15,...,90 degrees.
  const kranti = [0, 362, 703, 1002, 1238, 1388, 1440];
  final segment = (bhuja ~/ 15).clamp(0, 5);
  var declination = (kranti[segment] +
          (kranti[segment + 1] - kranti[segment]) *
              (bhuja - segment * 15) /
              15) /
      60;
  if (longitude >= 180) declination = -declination;
  if (body == VedicBody.mercury) {
    declination = declination.abs();
  } else if (body == VedicBody.moon || body == VedicBody.saturn) {
    declination = -declination;
  }
  return (30 + 1.25 * declination).clamp(0.0, 60.0) *
      (body == VedicBody.sun ? 2 : 1);
}

/// Eight classical motion states as used by the Maitreya family of methods.
/// The crossing flag is found by ephemeris sampling, never a fabricated speed.
/// Retained for callers of the older method; not used by calculateShadbala.
({double value, String name}) motionStateBala(
  VedicBody body,
  double speed, {
  bool crossesSignBeforeStation = false,
}) {
  if (body == VedicBody.sun || body == VedicBody.moon) {
    return (value: 0, name: 'Counted in Kala');
  }
  final ratio = speed / shadbalaMeanSpeeds[body.index];
  if (ratio.abs() < 0.1) return (value: 15, name: 'Vikala');
  if (ratio < 0) {
    return crossesSignBeforeStation
        ? (value: 30, name: 'Anuvakra')
        : (value: 60, name: 'Vakra');
  }
  if (ratio < 0.5) return (value: 15, name: 'Mandatara');
  if (ratio < 1) return (value: 30, name: 'Manda');
  if (ratio < 1.5) return (value: 7.5, name: 'Sama');
  return crossesSignBeforeStation
      ? (value: 30, name: 'Atichara')
      : (value: 45, name: 'Chara');
}

bool _moolatrikona(VedicBody body, double longitude) {
  const ranges = [
    (4, 0.0, 20.0),
    (1, 3.0, 30.0),
    (0, 0.0, 12.0),
    (5, 15.0, 20.0),
    (8, 0.0, 10.0),
    (6, 0.0, 15.0),
    (10, 0.0, 20.0),
  ];
  final range = ranges[body.index];
  final degree = normalizeDegrees(longitude) % 30;
  return zodiacSign(longitude) == range.$1 &&
      degree >= range.$2 &&
      degree < range.$3;
}

double _vargaDignity(AstrologyChart chart, VedicBody body, int division) {
  final position = chart.planet(body);
  final sign = divisionalSign(position.longitude, division);
  final owner = signLords[sign];
  if (division == 1 && _moolatrikona(body, position.longitude)) return 45;
  if (owner == body) return 30;
  final difference = (chart.planet(owner).sign - position.sign) % 12;
  final temporaryFriend = const [1, 2, 3, 9, 10, 11].contains(difference);
  final relationship =
      _friendships[body.index][owner.index] + (temporaryFriend ? 1 : -1);
  const dignities = [1.875, 3.75, 7.5, 15.0, 22.5];
  return dignities[relationship + 2];
}

/// Piecewise sphuta-drishti, 0..60 virupas; special full aspects replace their
/// ordinary strength, not add unbounded bonuses. Directed angle is important.
double grahaDrishti(VedicBody body, double angle) {
  final a = normalizeDegrees(angle);
  final knots = <double, double>{
    0: 0,
    30: 0,
    60: 15,
    90: 45,
    120: 30,
    150: 0,
    180: 60,
    210: 45,
    240: 30,
    270: 15,
    300: 0,
    330: 0,
    360: 0,
  };
  if (body == VedicBody.mars) {
    knots[90] = 60;
    knots[210] = 60;
  } else if (body == VedicBody.jupiter) {
    knots[120] = 60;
    knots[240] = 60;
  } else if (body == VedicBody.saturn) {
    knots[60] = 60;
    knots[270] = 60;
  }
  final left = (a ~/ 30) * 30.0;
  return knots[left]! + (knots[left + 30]! - knots[left]!) * (a - left) / 30;
}

List<ShadbalaRow> calculateShadbala(AstrologyChart chart) {
  final sun = chart.planet(VedicBody.sun);
  final moon = chart.planet(VedicBody.moon);
  final moonBenefic = chart.elongation >= 90 && chart.elongation <= 270;
  final mercury = chart.planet(VedicBody.mercury);
  const malefics = [
    VedicBody.sun,
    VedicBody.mars,
    VedicBody.saturn,
    VedicBody.rahu,
    VedicBody.ketu,
  ];
  final mercuryBenefic = !chart.planets.any(
    (position) =>
        position.body != VedicBody.mercury &&
        position.sign == mercury.sign &&
        (malefics.contains(position.body) ||
            (position.body == VedicBody.moon && !moonBenefic)),
  );
  final benefics = <VedicBody>{
    VedicBody.jupiter,
    VedicBody.venus,
    if (moonBenefic) VedicBody.moon,
    if (mercuryBenefic) VedicBody.mercury,
  };
  final rise = chart.sunrise;
  final set = chart.sunset;
  final next = chart.nextSunrise;
  final solarValid = rise != null && set != null && next != null;
  final details = <Map<String, double>>[];
  final sthana = <double>[];
  final dig = <double>[];
  final kala = <double>[];
  final drik = <double>[];
  final motions = <({double value, String name})>[];
  final dayStrength = angularDistance(sun.longitude, chart.ascendant + 90) / 3;
  final periodLords = solarValid
      ? shadbalaPeriodLords(AstrologyTime.localTime(chart.input, rise))
      : null;

  for (final body in VedicBody.classical) {
    final planet = chart.planet(body);
    final values = <String, double>{};
    values['Uchcha'] = uchchaBala(body, planet.longitude);
    values['Saptavargaja'] = const [1, 2, 3, 7, 9, 12, 30].fold(
      0.0,
      (sum, division) => sum + _vargaDignity(chart, body, division),
    );
    final feminine = body == VedicBody.moon || body == VedicBody.venus;
    values['Ojayugma'] = [planet.sign, divisionalSign(planet.longitude, 9)]
            .where((sign) => sign.isOdd == feminine)
            .length *
        15.0;
    final house = (planet.sign - zodiacSign(chart.ascendant)) % 12;
    const kendradiStrengths = [60.0, 30.0, 15.0];
    values['Kendradi'] = kendradiStrengths[house % 3];
    final decan = (normalizeDegrees(planet.longitude) % 30) ~/ 10;
    final wantedDecan = feminine
        ? 2
        : (body == VedicBody.mercury || body == VedicBody.saturn ? 1 : 0);
    values['Drekkana'] = decan == wantedDecan ? 15 : 0;
    sthana.add(values.values.fold(0, (sum, value) => sum + value));

    final weakPoint = switch (body) {
      VedicBody.sun || VedicBody.mars => chart.ascendant + 90,
      VedicBody.moon || VedicBody.venus => chart.ascendant + 270,
      VedicBody.mercury || VedicBody.jupiter => chart.ascendant + 180,
      _ => chart.ascendant,
    };
    dig.add(angularDistance(planet.longitude, weakPoint) / 3);
    final nightPlanet = const [
      VedicBody.moon,
      VedicBody.mars,
      VedicBody.saturn,
    ].contains(body);
    values['Natonnata'] = body == VedicBody.mercury
        ? 60
        : (nightPlanet ? 60 - dayStrength : dayStrength);
    final phase = angularDistance(moon.longitude, sun.longitude) / 3;
    values['Paksha'] = (benefics.contains(body) ? phase : 60 - phase) *
        (body == VedicBody.moon ? 2 : 1);
    values['Tribhaga'] = 0;
    values['Varsha'] = 0;
    values['Masa'] = 0;
    values['Dina'] = 0;
    values['Hora'] = 0;
    if (solarValid) {
      final daytime = chart.utc.isBefore(set);
      final start = daytime ? rise : set;
      final end = daytime ? set : next;
      final fraction = chart.utc.difference(start).inMicroseconds /
          end.difference(start).inMicroseconds;
      final third = (fraction * 3).floor().clamp(0, 2);
      final thirdLords = daytime
          ? const [
              VedicBody.mercury,
              VedicBody.sun,
              VedicBody.saturn,
            ]
          : const [
              VedicBody.moon,
              VedicBody.venus,
              VedicBody.mars,
            ];
      final thirdLord = thirdLords[third];
      values['Tribhaga'] =
          body == VedicBody.jupiter || body == thirdLord ? 60 : 0;
      final dayLord = _weekdayLords[chart.weekday];
      final hora = chart.utc.difference(rise).inMicroseconds ~/
          Duration.microsecondsPerHour;
      final horaLord =
          _horaSequence[(_horaSequence.indexOf(dayLord) + hora) % 7];
      values['Varsha'] = body == periodLords!.year ? 15 : 0;
      values['Masa'] = body == periodLords.month ? 30 : 0;
      values['Dina'] = body == dayLord ? 45 : 0;
      values['Hora'] = body == horaLord ? 60 : 0;
    }
    values['Ayana'] = tabularAyanaBala(
      body,
      planet.longitude,
      23,
    );
    values['Yuddha'] = 0;
    kala.add(
      const [
        'Natonnata',
        'Paksha',
        'Tribhaga',
        'Varsha',
        'Masa',
        'Dina',
        'Hora',
        'Ayana',
      ].fold(0, (sum, name) => sum + values[name]!),
    );
    var aspect = 0.0;
    for (final other in VedicBody.classical) {
      if (other == body) continue;
      aspect += grahaDrishti(
            other,
            planet.longitude - chart.planet(other).longitude,
          ) *
          (benefics.contains(other) ? 1 : -1) /
          4;
    }
    drik.add(aspect);
    motions.add(
      (
        value: meanLongitudeCheshtaBala(
          body: body,
          julianDay: chart.julianDay,
          year: chart.utc.year,
          referenceLongitude: planet.longitude +
              chart.ayanamsaDegrees -
              (chart.shadbalaReferenceAyanamsaDegrees ?? chart.ayanamsaDegrees),
        ),
        name: body == VedicBody.sun || body == VedicBody.moon
            ? 'Counted in Kala'
            : '${planet.retrograde ? 'Retrograde' : 'Direct'} '
                '· mean-longitude Cheshta',
      ),
    );
    details.add(values);
  }

  // Planetary war excludes the luminaries and nodes. Work from the pre-war
  // totals, so iterating another pair cannot feed back into the calculation.
  if (solarValid) {
    for (var a = 2; a < 7; a++) {
      for (var b = a + 1; b < 7; b++) {
        final first = chart.planet(VedicBody.classical[a]);
        final second = chart.planet(VedicBody.classical[b]);
        if (angularDistance(first.longitude, second.longitude) >= 1) continue;
        final diameterA = chart.apparentDiameters[first.body];
        final diameterB = chart.apparentDiameters[second.body];
        if (diameterA == null || diameterB == null) continue;
        final difference = (diameterA - diameterB).abs();
        if (difference < 0.001) continue;
        final firstTotal = sthana[a] + dig[a] + kala[a] - details[a]['Ayana']!;
        final secondTotal = sthana[b] + dig[b] + kala[b] - details[b]['Ayana']!;
        final transfer = (firstTotal - secondTotal).abs() / difference;
        final firstWins = first.latitude >= second.latitude;
        details[a]['Yuddha'] =
            details[a]['Yuddha']! + (firstWins ? transfer : -transfer);
        details[b]['Yuddha'] =
            details[b]['Yuddha']! + (firstWins ? -transfer : transfer);
      }
    }
  }
  return [
    for (var index = 0; index < 7; index++)
      ShadbalaRow(
        body: VedicBody.classical[index],
        sthana: sthana[index],
        dig: dig[index],
        kala: solarValid ? kala[index] + details[index]['Yuddha']! : null,
        cheshta: motions[index].value,
        motion: motions[index].name,
        naisargika: _natural[index],
        drik: drik[index],
        breakdown: Map.unmodifiable(details[index]),
      ),
  ];
}
