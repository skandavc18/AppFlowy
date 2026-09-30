import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:sweph/sweph.dart';

import 'astrology_model.dart';
import 'astrology_panchanga.dart';
import 'astrology_time.dart';

class _EphemerisAssets with AssetLoader {
  @override
  Future<Uint8List> load(String assetPath) async {
    final data = await rootBundle.load(assetPath);
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  }
}

/// All native calls stay on one isolate and run synchronously after loading.
/// Swiss Ephemeris has mutable process state (ayanamsa, files): changing its
/// mode across concurrently running isolates would mix two people's charts.
class AstrologyEngine {
  AstrologyEngine();
  static final instance = AstrologyEngine();
  static Future<void>? _initializing;
  static bool _initialized = false;
  static final _flags =
      SwephFlag.SEFLG_SWIEPH | SwephFlag.SEFLG_SIDEREAL | SwephFlag.SEFLG_SPEED;
  final Map<String, AstrologyChart> _cache = {};

  Future<void> initialize({
    String? modulePath,
    String? ephemerisDirectory,
  }) async {
    if (_initialized) return;
    final pending = _initializing;
    if (pending != null) return pending;
    final operation = _initialize(modulePath, ephemerisDirectory);
    _initializing = operation;
    try {
      await operation;
      _initialized = true;
    } finally {
      // A failed load can be retried, never latch a failed Future forever.
      _initializing = null;
    }
  }

  Future<void> _initialize(String? modulePath, String? directory) async {
    AstrologyTime.initialize();
    final path = directory ??
        p.join(
          (await getApplicationSupportDirectory()).path,
          'astrology',
          'ephemeris-2.10.3',
        );
    await Sweph.init(
      modulePath: modulePath,
      epheFilesPath: path,
      assetLoader: _EphemerisAssets(),
      epheAssets: const [
        'packages/sweph/assets/ephe/sepl_18.se1',
        'packages/sweph/assets/ephe/semo_18.se1',
        'packages/sweph/assets/ephe/sefstars.txt',
      ],
    );
  }

  Future<AstrologyChart> calculate(
    AstrologyInput input, {
    DateTime? now,
  }) async {
    input.validate();
    if (input.place == null) {
      throw const FormatException(
        'Choose a birth place or allow current location.',
      );
    }
    final utc = (input.utc ?? now ?? DateTime.now()).toUtc();
    final resolved = input.copyWith(utc: utc);
    resolved.validate();
    await initialize();
    final key = resolved.fingerprint;
    final cached = _cache[key];
    if (cached != null) return cached;
    final chart = _calculate(resolved);
    if (_cache.length >= 24) _cache.remove(_cache.keys.first);
    _cache[key] = chart;
    return chart;
  }

  void clearCache() => _cache.clear();

  /// Sidereal positions of the nine grahas only, for transit tables. No
  /// houses, sunrise or lagnas are calculated, so no place is needed. Uses
  /// [settings]' ayanamsha, adjustment and node exactly like [calculate].
  Future<List<VedicPlacement>> positions(
    AstrologyInput settings,
    DateTime utc,
  ) async {
    final instant = utc.toUtc();
    AstrologyInput(
      utc: instant,
      ayanamsaOffsetArcseconds: settings.ayanamsaOffsetArcseconds,
      dashaYearDays: settings.dashaYearDays,
    ).validate();
    await initialize();
    Sweph.swe_set_sid_mode(SiderealMode(settings.ayanamsa.swissId));
    final jd = julianDay(instant);
    final adjustment = settings.ayanamsaOffsetArcseconds / 3600;
    final planets = <VedicPlacement>[];
    for (final body in VedicBody.values) {
      if (body == VedicBody.ketu) continue;
      final id =
          body == VedicBody.rahu && settings.trueNode ? 11 : body.swissId;
      final position = Sweph.swe_calc_ut(jd, HeavenlyBody(id), _flags);
      planets.add(
        VedicPlacement(
          body: body,
          name: body.label,
          shortName: body.shortName,
          longitude: normalizeDegrees(position.longitude - adjustment),
          latitude: position.latitude,
          speed: position.speedInLongitude,
        ),
      );
    }
    final rahu = planets.last;
    planets.add(
      VedicPlacement(
        body: VedicBody.ketu,
        name: 'Ketu',
        shortName: 'Ke',
        longitude: normalizeDegrees(rahu.longitude + 180),
        latitude: -rahu.latitude,
        speed: rahu.speed,
      ),
    );
    return List.unmodifiable(planets);
  }

  /// When the tithi, nakshatra, yoga and karana current at [chart]'s instant
  /// end, plus the sunset before its sunrise (for Brahma muhurta).
  ///
  /// Each end is the next boundary crossing, found by Newton iteration on the
  /// actual sidereal longitudes and speeds; a limb that does not converge is
  /// returned as null rather than guessed.
  Future<AstrologyPanchangaTimes> panchangaTimes(AstrologyChart chart) async {
    await initialize();
    final input = chart.input;
    Sweph.swe_set_sid_mode(SiderealMode(input.ayanamsa.swissId));
    final adjustment = input.ayanamsaOffsetArcseconds / 3600;
    final start = chart.julianDay;
    final cache = <double, (CoordinatesWithSpeed, CoordinatesWithSpeed)>{};
    (CoordinatesWithSpeed, CoordinatesWithSpeed) luminaries(double jd) =>
        cache[jd] ??= (
          Sweph.swe_calc_ut(jd, HeavenlyBody.SE_SUN, _flags),
          Sweph.swe_calc_ut(jd, HeavenlyBody.SE_MOON, _flags),
        );
    (double, double) elongation(double jd) {
      final (sun, moon) = luminaries(jd);
      return (
        normalizeDegrees(moon.longitude - sun.longitude),
        moon.speedInLongitude - sun.speedInLongitude,
      );
    }

    (double, double) moon(double jd) {
      final (_, moon) = luminaries(jd);
      return (
        normalizeDegrees(moon.longitude - adjustment),
        moon.speedInLongitude,
      );
    }

    (double, double) yoga(double jd) {
      final (sun, moon) = luminaries(jd);
      return (
        normalizeDegrees(sun.longitude + moon.longitude - 2 * adjustment),
        sun.speedInLongitude + moon.speedInLongitude,
      );
    }

    DateTime? previousSunset;
    final sunrise = chart.sunrise;
    final place = input.place;
    if (sunrise != null && place != null) {
      final rise = julianDay(sunrise);
      final set = Sweph.swe_rise_trans(
        rise - 1,
        HeavenlyBody.SE_SUN,
        SwephFlag.SEFLG_SWIEPH,
        RiseSetTransitFlag.SE_CALC_SET | RiseSetTransitFlag.SE_BIT_HINDU_RISING,
        GeoPosition(place.longitude, place.latitude),
        0,
        15,
      );
      if (set != null && set < rise && set > rise - 1) {
        previousSunset = _fromJulian(set);
      }
    }
    return AstrologyPanchangaTimes(
      tithiEnd: _nextBoundary(start, 12, elongation),
      nakshatraEnd: _nextBoundary(start, 40 / 3, moon),
      yogaEnd: _nextBoundary(start, 40 / 3, yoga),
      karanaEnd: _nextBoundary(start, 6, elongation),
      previousSunset: previousSunset,
    );
  }

  /// The first instant after [jd] at which [sample]'s angle reaches the next
  /// multiple of [step]. The angle must increase (positive rate).
  static DateTime? _nextBoundary(
    double jd,
    double step,
    (double, double) Function(double jd) sample,
  ) {
    final (initial, _) = sample(jd);
    final target = normalizeDegrees(((initial / step).floor() + 1) * step);
    var time = jd;
    for (var iteration = 0; iteration < 40; iteration++) {
      final (angle, rate) = sample(time);
      if (!rate.isFinite || rate <= 0) return null;
      var remaining = normalizeDegrees(target - angle);
      // After the first step, a small overshoot must be corrected backwards.
      if (iteration > 0 && remaining > 180) remaining -= 360;
      final delta = remaining / rate;
      time += delta;
      if (time - jd > 2 || time < jd) return null;
      if (delta.abs() * 86400 < 0.005) return _fromJulian(time);
    }
    return null;
  }

  static double julianDay(DateTime utc) => Sweph.swe_utc_to_jd(
        utc.year,
        utc.month,
        utc.day,
        utc.hour,
        utc.minute,
        utc.second + utc.millisecond / 1000 + utc.microsecond / 1000000,
        CalendarType.SE_GREG_CAL,
      )[1];

  static DateTime _fromJulian(double jd) =>
      Sweph.swe_jdut1_to_utc(jd, CalendarType.SE_GREG_CAL);

  static HouseCuspData _houses(double jd, AstrologyPlace place) =>
      Sweph.swe_houses_ex2(
        jd,
        SwephFlag.SEFLG_SIDEREAL,
        place.latitude,
        place.longitude,
        Hsys.W,
      );

  AstrologyChart _calculate(AstrologyInput input) {
    final place = input.place!;
    final utc = input.utc!;
    final jd = julianDay(utc);
    Sweph.swe_set_sid_mode(SiderealMode(AstrologyAyanamsa.lahiri.swissId));
    final shadbalaReferenceAyanamsa =
        Sweph.swe_get_ayanamsa_ex_ut(jd, SwephFlag.SEFLG_SWIEPH);
    Sweph.swe_set_sid_mode(SiderealMode(input.ayanamsa.swissId));
    final houses = _houses(jd, place);
    final adjustment = input.ayanamsaOffsetArcseconds / 3600;
    double sidereal(double longitude) =>
        normalizeDegrees(longitude - adjustment);
    final planets = <VedicPlacement>[];
    final diameters = <VedicBody, double>{};
    for (final body in VedicBody.values) {
      if (body == VedicBody.ketu) continue;
      final id = body == VedicBody.rahu && input.trueNode ? 11 : body.swissId;
      final position = Sweph.swe_calc_ut(jd, HeavenlyBody(id), _flags);
      final equatorial = Sweph.swe_calc_ut(
        jd,
        HeavenlyBody(id),
        SwephFlag.SEFLG_SWIEPH | SwephFlag.SEFLG_EQUATORIAL,
      );
      if (body.index >= 2 && body.index < 7) {
        diameters[body] = Sweph.swe_pheno_ut(
              jd,
              HeavenlyBody(id),
              SwephFlag.SEFLG_SWIEPH,
            )[3] *
            3600;
      }
      planets.add(
        VedicPlacement(
          body: body,
          name: body.label,
          shortName: body.shortName,
          longitude: sidereal(position.longitude),
          latitude: position.latitude,
          declination: equatorial.latitude,
          speed: position.speedInLongitude,
        ),
      );
    }
    final rahu = planets.last;
    planets.add(
      VedicPlacement(
        body: VedicBody.ketu,
        name: 'Ketu',
        shortName: 'Ke',
        longitude: normalizeDegrees(rahu.longitude + 180),
        latitude: -rahu.latitude,
        declination: -rahu.declination,
        speed: rahu.speed,
      ),
    );

    final local = AstrologyTime.localTime(input, utc);
    final midnight = DateTime.utc(local.year, local.month, local.day)
        .subtract(AstrologyTime.offsetAt(input, utc));
    final geo = GeoPosition(place.longitude, place.latitude);
    double? solarEvent(double after, RiseSetTransitFlag event) =>
        Sweph.swe_rise_trans(
          after,
          HeavenlyBody.SE_SUN,
          SwephFlag.SEFLG_SWIEPH,
          event | RiseSetTransitFlag.SE_BIT_HINDU_RISING,
          geo,
          0,
          15,
        );
    var rise = solarEvent(julianDay(midnight), RiseSetTransitFlag.SE_CALC_RISE);
    if (rise != null && rise > jd) {
      rise =
          solarEvent(julianDay(midnight) - 1, RiseSetTransitFlag.SE_CALC_RISE);
    }
    final set =
        rise == null ? null : solarEvent(rise, RiseSetTransitFlag.SE_CALC_SET);
    final next = rise == null
        ? null
        : solarEvent(rise + 0.01, RiseSetTransitFlag.SE_CALC_RISE);
    final solarValid = rise != null &&
        set != null &&
        next != null &&
        rise <= jd &&
        rise < set &&
        set < next &&
        next > jd &&
        next - rise < 1.1;
    final weekday = solarValid
        ? AstrologyTime.localTime(input, _fromJulian(rise)).weekday % 7
        : local.weekday % 7;

    final special = <VedicPlacement>[];
    if (solarValid) {
      final sunriseSun = sidereal(
        Sweph.swe_calc_ut(rise, HeavenlyBody.SE_SUN, _flags).longitude,
      );
      final minutes = (jd - rise) * 1440;
      for (final entry in const [
        ('Bhava Lagna', 'BL', 0.25),
        ('Hora Lagna', 'HL', 0.5),
        ('Ghati Lagna', 'GL', 1.25),
      ]) {
        special.add(
          VedicPlacement(
            name: entry.$1,
            shortName: entry.$2,
            longitude: normalizeDegrees(sunriseSun + minutes * entry.$3),
          ),
        );
      }
      final dayBirth = jd < set;
      final partStart = dayBirth ? rise : set;
      final partEnd = dayBirth ? set : next;
      final firstLord = dayBirth ? weekday : (weekday + 4) % 7;
      final saturnPart = (6 - firstLord) % 7;
      for (final entry in const [
        ('Gulika', 'Gk', 0.0),
        ('Maandi', 'Md', 0.5),
      ]) {
        final instant =
            partStart + (partEnd - partStart) * (saturnPart + entry.$3) / 8;
        special.add(
          VedicPlacement(
            name: entry.$1,
            shortName: entry.$2,
            longitude: sidereal(_houses(instant, place).ascmc[0]),
          ),
        );
      }
    }
    final moon = planets[1];
    final mansion = normalizeDegrees(moon.longitude) * 3 / 40;
    special.add(
      VedicPlacement(
        name: 'Sri Lagna',
        shortName: 'SL',
        longitude: normalizeDegrees(
          sidereal(houses.ascmc[0]) + (mansion - mansion.floor()) * 360,
        ),
      ),
    );

    return AstrologyChart(
      input: input,
      utc: utc,
      julianDay: jd,
      ayanamsaDegrees:
          Sweph.swe_get_ayanamsa_ex_ut(jd, SwephFlag.SEFLG_SWIEPH) + adjustment,
      ascendant: sidereal(houses.ascmc[0]),
      midheaven: sidereal(houses.ascmc[1]),
      planets: List.unmodifiable(planets),
      specialLagnas: List.unmodifiable(special),
      sunrise: solarValid ? _fromJulian(rise) : null,
      sunset: solarValid ? _fromJulian(set) : null,
      nextSunrise: solarValid ? _fromJulian(next) : null,
      weekday: weekday,
      localMeanHours: ((jd + 0.5) % 1 * 24 + place.longitude / 15) % 24,
      shadbalaReferenceAyanamsaDegrees: shadbalaReferenceAyanamsa,
      apparentDiameters: Map.unmodifiable(diameters),
      ephemerisVersion: Sweph.swe_version(),
      warnings: solarValid
          ? const []
          : const [
              'Sunrise/sunset could not bracket this instant (polar day/night). '
                  'Sunrise-dependent lagnas and full Shadbala are unavailable.',
            ],
    );
  }
}
