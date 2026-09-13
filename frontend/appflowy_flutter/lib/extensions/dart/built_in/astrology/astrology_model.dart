import 'dart:convert';

/// Stored configuration only. Computed positions never become document edits.
enum AstrologyView {
  chart('Charts'),
  dasha('Dasha table'),
  shadbala('Shadbala'),
  ashtakavarga('Ashtakavarga'),
  placements('Planetary & special lagnas'),
  panchanga('Panchanga & key info');

  const AstrologyView(this.label);
  final String label;

  static AstrologyView fromValue(Object? value) => values.firstWhere(
        (view) => view.name == value,
        orElse: () => chart,
      );
}

enum IndianChartStyle {
  north('North Indian'),
  south('South Indian');

  const IndianChartStyle(this.label);
  final String label;

  static IndianChartStyle fromValue(Object? value) =>
      value == 'south' ? south : north;
}

enum AstrologyAyanamsa {
  lahiri('Lahiri', 1),
  raman('B.V. Raman', 3),
  krishnamurti('KP (Krishnamurti)', 5),
  pushyaPaksha('Pushya Paksha', 29),
  yukteshwar('Yukteshwar', 7),
  suryaSiddhanta('Surya Siddhanta', 21),
  trueChitra('True Chitra', 27);

  const AstrologyAyanamsa(this.label, this.swissId);
  final String label;
  final int swissId;

  static AstrologyAyanamsa fromValue(Object? value) => values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => lahiri,
      );
}

enum VedicBody {
  sun('Sun', 'Su', 0),
  moon('Moon', 'Mo', 1),
  mars('Mars', 'Ma', 4),
  mercury('Mercury', 'Me', 2),
  jupiter('Jupiter', 'Ju', 5),
  venus('Venus', 'Ve', 3),
  saturn('Saturn', 'Sa', 6),
  rahu('Rahu', 'Ra', 10),
  ketu('Ketu', 'Ke', -1);

  const VedicBody(this.label, this.shortName, this.swissId);
  final String label;
  final String shortName;
  final int swissId;

  static const classical = [sun, moon, mars, mercury, jupiter, venus, saturn];
}

const zodiacNames = [
  'Aries',
  'Taurus',
  'Gemini',
  'Cancer',
  'Leo',
  'Virgo',
  'Libra',
  'Scorpio',
  'Sagittarius',
  'Capricorn',
  'Aquarius',
  'Pisces',
];
const zodiacShortNames = [
  'Ar',
  'Ta',
  'Ge',
  'Cn',
  'Le',
  'Vi',
  'Li',
  'Sc',
  'Sg',
  'Cp',
  'Aq',
  'Pi',
];
const nakshatraNames = [
  'Ashwini',
  'Bharani',
  'Krittika',
  'Rohini',
  'Mrigashira',
  'Ardra',
  'Punarvasu',
  'Pushya',
  'Ashlesha',
  'Magha',
  'Purva Phalguni',
  'Uttara Phalguni',
  'Hasta',
  'Chitra',
  'Swati',
  'Vishakha',
  'Anuradha',
  'Jyeshtha',
  'Mula',
  'Purva Ashadha',
  'Uttara Ashadha',
  'Shravana',
  'Dhanishta',
  'Shatabhisha',
  'Purva Bhadrapada',
  'Uttara Bhadrapada',
  'Revati',
];
const signLords = [
  VedicBody.mars,
  VedicBody.venus,
  VedicBody.mercury,
  VedicBody.moon,
  VedicBody.sun,
  VedicBody.mercury,
  VedicBody.venus,
  VedicBody.mars,
  VedicBody.jupiter,
  VedicBody.saturn,
  VedicBody.saturn,
  VedicBody.jupiter,
];

const astrologyDivisions = <int, String>{
  1: 'D-1 · Lagna / Rasi',
  2: 'D-2 · Hora (Parashari)',
  3: 'D-3 · Drekkana',
  4: 'D-4 · Chaturthamsa',
  7: 'D-7 · Saptamsa',
  9: 'D-9 · Navamsha',
  10: 'D-10 · Dasamsa',
  12: 'D-12 · Dwadasamsa',
  30: 'D-30 · Trimsamsa (Parashari)',
};

double normalizeDegrees(double value) {
  final result = value % 360;
  // A tiny negative floating-point angle can round its remainder up to 360.
  return result >= 360 ? 0 : result;
}

double angularDistance(double a, double b) {
  final distance = normalizeDegrees(a - b);
  return distance > 180 ? 360 - distance : distance;
}

int zodiacSign(double longitude) => normalizeDegrees(longitude) ~/ 30;
int nakshatraIndex(double longitude) =>
    (normalizeDegrees(longitude) * 3 / 40).floor().clamp(0, 26);
int nakshatraPada(double longitude) =>
    (normalizeDegrees(longitude) * 3 / 10).floor() % 4 + 1;

/// Round within the sign, without ever displaying 60 minutes/seconds or
/// changing the sign of a planet just below a cusp.
String formatZodiacLongitude(double longitude) {
  final normalized = normalizeDegrees(longitude);
  final seconds = ((normalized % 30) * 3600).round().clamp(0, 107999);
  final degree = seconds ~/ 3600;
  final minute = seconds ~/ 60 % 60;
  final second = seconds % 60;
  return '$degree° ${zodiacShortNames[zodiacSign(normalized)]} '
      '${minute.toString().padLeft(2, '0')}′ '
      '${second.toString().padLeft(2, '0')}″';
}

/// Classical Parashari sign mappings, not a generic harmonic multiplication.
/// D2 and D30 in particular are not equal cyclic harmonic charts.
int divisionalSign(double longitude, int division) {
  if (!astrologyDivisions.containsKey(division) || !longitude.isFinite) {
    throw ArgumentError('A supported varga and finite longitude are required.');
  }
  final sign = zodiacSign(longitude);
  final degree = normalizeDegrees(longitude) % 30;
  final part = (degree * division / 30).floor().clamp(0, division - 1);
  switch (division) {
    case 1:
      return sign;
    case 2:
      return (sign.isEven == (degree < 15)) ? 4 : 3;
    case 3:
      return (sign + part * 4) % 12;
    case 4:
      return (sign + part * 3) % 12;
    case 7:
      return (sign + (sign.isOdd ? 6 : 0) + part) % 12;
    case 9:
      return (sign * 9 + part) % 12;
    case 10:
      return (sign + (sign.isOdd ? 8 : 0) + part) % 12;
    case 12:
      return (sign + part) % 12;
    case 30:
      if (sign.isEven) {
        if (degree < 5) return 0;
        if (degree < 10) return 10;
        if (degree < 18) return 8;
        if (degree < 25) return 2;
        return 6;
      }
      if (degree < 5) return 1;
      if (degree < 12) return 5;
      if (degree < 20) return 11;
      if (degree < 25) return 9;
      return 7;
    default:
      throw ArgumentError.value(
        division,
        'division',
        'Unsupported varga',
      );
  }
}

Map<String, Object?> astrologyMap(Object? value) => value is Map
    ? {
        for (final entry in value.entries)
          if (entry.key is String) entry.key as String: entry.value,
      }
    : const {};

class AstrologyPlace {
  const AstrologyPlace({
    required this.name,
    required this.latitude,
    required this.longitude,
    required this.timeZone,
    this.isDeviceLocation = false,
  });

  factory AstrologyPlace.fromJson(Map<String, Object?> json) {
    final lat = json['latitude'];
    final lon = json['longitude'];
    if (lat is! num || lon is! num) {
      throw const FormatException('The place needs latitude and longitude.');
    }
    final place = AstrologyPlace(
      name: json['name'] is String ? json['name']! as String : '',
      latitude: lat.toDouble(),
      longitude: lon.toDouble(),
      timeZone: json['timezone'] is String ? json['timezone']! as String : '',
      isDeviceLocation: json['device'] == true,
    );
    place.validate();
    return place;
  }

  final String name;
  final double latitude;
  final double longitude;
  final String timeZone;
  final bool isDeviceLocation;

  void validate() {
    if (!latitude.isFinite ||
        !longitude.isFinite ||
        latitude.abs() >= 90 ||
        longitude.abs() > 180) {
      throw const FormatException(
        'Latitude must be between −90° and 90° (excluding the poles), '
        'and longitude between −180° and 180°.',
      );
    }
  }

  Map<String, Object?> toJson() => {
        'name': name,
        'latitude': latitude,
        'longitude': longitude,
        'timezone': timeZone,
        if (isDeviceLocation) 'device': true,
      };
}

class AstrologyInput {
  const AstrologyInput({
    this.name = '',
    this.utc,
    this.place,
    this.utcOffsetMinutes,
    this.style = IndianChartStyle.north,
    this.ayanamsa = AstrologyAyanamsa.lahiri,
    this.ayanamsaOffsetArcseconds = 0,
    this.trueNode = false,
    this.dashaYearDays = 365.25636,
  });

  factory AstrologyInput.fromJson(Map<String, Object?> json) {
    final version = json['version'];
    if (version != null && version != 1) {
      throw const FormatException(
        'This horoscope uses an unsupported version.',
      );
    }
    final stamp = json['utc'];
    final utc = stamp is String ? DateTime.tryParse(stamp) : null;
    if (stamp != null && (utc == null || !utc.isUtc)) {
      throw const FormatException(
        'A saved birth time must include its UTC zone.',
      );
    }
    final ayanamsaOffset = json['ayanamsa_offset_arcseconds'];
    if (ayanamsaOffset != null && ayanamsaOffset is! num) {
      throw const FormatException('The ayanamsha adjustment must be a number.');
    }
    return AstrologyInput(
      name: json['name'] is String ? json['name']! as String : '',
      utc: utc,
      place: json['place'] == null
          ? null
          : AstrologyPlace.fromJson(astrologyMap(json['place'])),
      utcOffsetMinutes: (json['offset_minutes'] as num?)?.round(),
      style: IndianChartStyle.fromValue(json['style']),
      ayanamsa: AstrologyAyanamsa.fromValue(json['ayanamsa']),
      ayanamsaOffsetArcseconds: (ayanamsaOffset as num?)?.toDouble() ?? 0,
      trueNode: json['true_node'] == true,
      dashaYearDays: (json['year_days'] as num?)?.toDouble() ?? 365.25636,
    );
  }

  final String name;

  /// Null = the clock now, NOT the time at which the block was inserted.
  final DateTime? utc;

  /// Null = request device location; never silently substitute a default city.
  final AstrologyPlace? place;

  /// Null = IANA rules at the requested instant, including historical DST.
  /// An explicit offset also disambiguates a repeated autumn clock time.
  final int? utcOffsetMinutes;
  final IndianChartStyle style;
  final AstrologyAyanamsa ayanamsa;

  /// Constant correction ADDED to the chosen preset, in arcseconds. Positive
  /// corrections therefore decrease every sidereal longitude by this angle.
  /// Kept separate from the preset so fixed-star modes retain their motion.
  final double ayanamsaOffsetArcseconds;
  final bool trueNode;
  final double dashaYearDays;
  bool get isTransit => utc == null;

  String get ayanamsaLabel {
    if (ayanamsaOffsetArcseconds == 0) return ayanamsa.label;
    final sign = ayanamsaOffsetArcseconds < 0 ? '−' : '+';
    final amount = ayanamsaOffsetArcseconds.abs().toString().replaceFirst(
          RegExp(r'\.0$'),
          '',
        );
    return '${ayanamsa.label} ($sign$amount″)';
  }

  void validate() {
    place?.validate();
    if (utc != null && (utc!.year < 1800 || utc!.year >= 2400)) {
      throw const FormatException('The bundled ephemeris covers 1800–2399.');
    }
    if (utcOffsetMinutes != null && utcOffsetMinutes!.abs() > 14 * 60) {
      throw const FormatException(
        'The UTC offset must be between −14 and +14 hours.',
      );
    }
    if (!ayanamsaOffsetArcseconds.isFinite ||
        ayanamsaOffsetArcseconds.abs() >= 360 * 3600) {
      throw const FormatException(
        'The ayanamsha adjustment must be finite and less than 360° in magnitude.',
      );
    }
    if (!dashaYearDays.isFinite || dashaYearDays < 360 || dashaYearDays > 366) {
      throw const FormatException('The dasha year must contain 360–366 days.');
    }
  }

  AstrologyInput copyWith({
    String? name,
    DateTime? utc,
    AstrologyPlace? place,
    IndianChartStyle? style,
    AstrologyAyanamsa? ayanamsa,
    double? ayanamsaOffsetArcseconds,
    bool useCurrentTime = false,
    bool useCurrentLocation = false,
  }) =>
      AstrologyInput(
        name: name ?? this.name,
        utc: useCurrentTime ? null : utc?.toUtc() ?? this.utc,
        place: useCurrentLocation ? null : place ?? this.place,
        utcOffsetMinutes: useCurrentLocation ? null : utcOffsetMinutes,
        style: style ?? this.style,
        ayanamsa: ayanamsa ?? this.ayanamsa,
        ayanamsaOffsetArcseconds:
            ayanamsaOffsetArcseconds ?? this.ayanamsaOffsetArcseconds,
        trueNode: trueNode,
        dashaYearDays: dashaYearDays,
      );

  Map<String, Object?> toJson() => {
        'version': 1,
        'name': name,
        if (utc != null) 'utc': utc!.toUtc().toIso8601String(),
        if (place != null) 'place': place!.toJson(),
        if (utcOffsetMinutes != null) 'offset_minutes': utcOffsetMinutes,
        'style': style.name,
        'ayanamsa': ayanamsa.name,
        if (ayanamsaOffsetArcseconds != 0)
          'ayanamsa_offset_arcseconds': ayanamsaOffsetArcseconds,
        'true_node': trueNode,
        'year_days': dashaYearDays,
      };

  String get fingerprint => jsonEncode(toJson());
}

class VedicPlacement {
  const VedicPlacement({
    required this.name,
    required this.shortName,
    required this.longitude,
    this.body,
    this.latitude = 0,
    this.declination = 0,
    this.speed = 0,
  });

  final String name;
  final String shortName;
  final VedicBody? body;
  final double longitude;
  final double latitude;
  final double declination;
  final double speed;
  bool get retrograde => body != null && speed < 0;
  int get sign => zodiacSign(longitude);
  String get nakshatra => nakshatraNames[nakshatraIndex(longitude)];
  int get pada => nakshatraPada(longitude);
  String get formatted => formatZodiacLongitude(longitude);
}

class AstrologyChart {
  const AstrologyChart({
    required this.input,
    required this.utc,
    required this.julianDay,
    required this.ayanamsaDegrees,
    required this.ascendant,
    required this.midheaven,
    required this.planets,
    required this.specialLagnas,
    required this.sunrise,
    required this.sunset,
    required this.nextSunrise,
    required this.weekday,
    required this.localMeanHours,
    this.signCrossingsBeforeStation = const {},
    this.shadbalaReferenceAyanamsaDegrees,
    this.apparentDiameters = const {},
    this.ephemerisVersion = '',
    this.warnings = const [],
  });

  /// Resolved place and a fixed instant; the originating UI owns live mode.
  final AstrologyInput input;
  final DateTime utc;
  final double julianDay;
  final double ayanamsaDegrees;
  final double ascendant;
  final double midheaven;
  final List<VedicPlacement> planets;
  final List<VedicPlacement> specialLagnas;

  /// The Vedic day surrounding the instant (previous sunrise for pre-dawn).
  /// Null during polar day/night: time-dependent results are unavailable.
  final DateTime? sunrise;
  final DateTime? sunset;
  final DateTime? nextSunrise;
  final int weekday;
  final double localMeanHours;
  final Map<VedicBody, bool> signCrossingsBeforeStation;

  /// Native Lahiri reference for the traditional mean-motion tables. A
  /// synthetic chart omitting this supplies longitudes already in that frame.
  final double? shadbalaReferenceAyanamsaDegrees;

  /// Apparent diameters in arcseconds, for the planetary-war strength term.
  final Map<VedicBody, double> apparentDiameters;
  final String ephemerisVersion;
  final List<String> warnings;

  VedicPlacement planet(VedicBody body) =>
      planets.firstWhere((position) => position.body == body);

  VedicPlacement get lagna => VedicPlacement(
        name: 'Lagna',
        shortName: 'As',
        longitude: ascendant,
      );

  List<VedicPlacement> get placements => [lagna, ...planets, ...specialLagnas];

  double get elongation => normalizeDegrees(
        planet(VedicBody.moon).longitude - planet(VedicBody.sun).longitude,
      );
  int get tithi => (elongation / 12).floor() + 1;
  double get tithiRemaining => 1 - (elongation % 12) / 12;
  int get yoga => (normalizeDegrees(
            planet(VedicBody.moon).longitude + planet(VedicBody.sun).longitude,
          ) *
          3 /
          40)
      .floor()
      .clamp(0, 26);
}
