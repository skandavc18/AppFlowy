import 'astrology_model.dart';
import 'astrology_panchanga.dart';
import 'astrology_time.dart';
import 'vimshottari.dart';

/// A graha at the analysed instant, placed in the natal chart by whole signs.
class AstrologyTransit {
  const AstrologyTransit({
    required this.placement,
    this.fromLagna,
    this.fromMoon,
  });

  final VedicPlacement placement;

  /// 1–12 from the natal Lagna/Moon; null without a natal chart.
  final int? fromLagna;
  final int? fromMoon;
}

/// Everything shown for one analysed instant and place. The natal chart is
/// optional: without a birth time there are no dashas or natal houses.
class AstrologyDateAnalysis {
  const AstrologyDateAnalysis({
    required this.moment,
    required this.natal,
    required this.dasha,
    required this.transits,
    required this.times,
    required this.muhurtas,
    required this.hora,
    required this.tara,
    required this.chandra,
    required this.saturn,
  });

  final AstrologyChart moment;
  final AstrologyChart? natal;

  /// Mahadasha → Sookshma dasha containing the instant (may be shorter
  /// outside the natal 120-year cycle).
  final List<DashaPeriod> dasha;
  final List<AstrologyTransit> transits;
  final AstrologyPanchangaTimes times;
  final List<MuhurtaWindow> muhurtas;
  final HoraPeriod? hora;
  final TaraBala? tara;
  final ChandraBala? chandra;
  final String? saturn;
}

AstrologyDateAnalysis analyzeAstrologyDate({
  required AstrologyChart moment,
  AstrologyChart? natal,
  AstrologyPanchangaTimes times = const AstrologyPanchangaTimes(),
}) {
  final natalMoon = natal?.planet(VedicBody.moon).longitude;
  final lagnaSign = natal == null ? null : zodiacSign(natal.ascendant);
  final moonSign = natalMoon == null ? null : zodiacSign(natalMoon);
  final moon = moment.planet(VedicBody.moon).longitude;
  final saturn = moment.planet(VedicBody.saturn).longitude;
  return AstrologyDateAnalysis(
    moment: moment,
    natal: natal,
    dasha: natal == null
        ? const []
        : dashaAt(
            vimshottariPeriods(
              birthUtc: natal.utc,
              moonLongitude: natalMoon!,
              yearDays: natal.input.dashaYearDays,
            ),
            moment.utc,
          ),
    transits: [
      for (final placement in moment.planets)
        AstrologyTransit(
          placement: placement,
          fromLagna: lagnaSign == null
              ? null
              : houseFromSign(lagnaSign, placement.sign),
          fromMoon:
              moonSign == null ? null : houseFromSign(moonSign, placement.sign),
        ),
    ],
    times: times,
    muhurtas: muhurtaWindows(moment, previousSunset: times.previousSunset),
    hora: horaAt(moment),
    tara: natalMoon == null ? null : taraBala(natalMoon: natalMoon, moon: moon),
    chandra: natalMoon == null
        ? null
        : chandraBala(natalMoon: natalMoon, moon: moon),
    saturn: natalMoon == null
        ? null
        : saturnTransitNote(natalMoon: natalMoon, saturn: saturn),
  );
}

/// Values written into one Life events row.
class AstrologyEventValues {
  const AstrologyEventValues({
    required this.dasha,
    required this.moonNakshatra,
    required this.transits,
  });

  /// Mahadasha, Antardasha, Pratyantardasha and Sookshma lords. Shorter only
  /// outside the natal 120-year Vimshottari cycle.
  final List<VedicBody> dasha;
  final String moonNakshatra;
  final Map<VedicBody, String> transits;
}

/// "Leo 12°34′ R · H5 · M8": sign and degree, R when retrograde, then the
/// whole-sign house counted from the natal Lagna (H) and natal Moon (M).
String transitCellText(
  VedicPlacement placement, {
  required int lagnaSign,
  required int moonSign,
}) =>
    '${compactLongitude(placement.longitude)}'
    '${placement.retrograde ? ' R' : ''}'
    ' · H${houseFromSign(lagnaSign, placement.sign)}'
    ' · M${houseFromSign(moonSign, placement.sign)}';

/// "Rohini, pada 2 · lord Moon".
String moonNakshatraText(double moonLongitude) {
  final index = nakshatraIndex(moonLongitude);
  return '${nakshatraNames[index]}, pada ${nakshatraPada(moonLongitude)}'
      ' · lord ${nakshatraLord(index).label}';
}

AstrologyEventValues astrologyEventValues({
  required AstrologyChart natal,
  required List<VedicPlacement> positions,
  required DateTime utc,
  List<DashaPeriod>? periods,
}) {
  final natalMoon = natal.planet(VedicBody.moon).longitude;
  final path = dashaAt(
    periods ??
        vimshottariPeriods(
          birthUtc: natal.utc,
          moonLongitude: natalMoon,
          yearDays: natal.input.dashaYearDays,
        ),
    utc,
  );
  final lagnaSign = zodiacSign(natal.ascendant);
  final moonSign = zodiacSign(natalMoon);
  final moon = positions.firstWhere(
    (placement) => placement.body == VedicBody.moon,
  );
  return AstrologyEventValues(
    dasha: [for (final period in path) period.lord],
    moonNakshatra: moonNakshatraText(moon.longitude),
    transits: {
      for (final placement in positions)
        if (placement.body != null)
          placement.body!: transitCellText(
            placement,
            lagnaSign: lagnaSign,
            moonSign: moonSign,
          ),
    },
  );
}

String _two(int value) => value.toString().padLeft(2, '0');

/// "2026-09-28" in the chart's own clock (never this computer's zone).
String astrologyLocalDate(AstrologyInput input, DateTime utc) {
  final local = AstrologyTime.localTime(input, utc);
  return '${local.year.toString().padLeft(4, '0')}-'
      '${_two(local.month)}-${_two(local.day)}';
}

/// "14:05" or "14:05:09" in the chart's own clock.
String astrologyLocalClock(
  AstrologyInput input,
  DateTime utc, {
  bool seconds = false,
}) {
  final local = AstrologyTime.localTime(input, utc);
  return '${_two(local.hour)}:${_two(local.minute)}'
      '${seconds ? ':${_two(local.second)}' : ''}';
}

/// "UTC+05:30", including historical offset seconds when present.
String astrologyOffsetLabel(Duration offset) {
  final seconds = offset.inSeconds.abs() % 60;
  return 'UTC${AstrologyTime.offsetLabel(offset)}'
      '${seconds == 0 ? '' : ':${_two(seconds)}'}';
}

/// Clock time, prefixed by the date when it is not [referenceDate]'s date.
String astrologyLocalTimeLabel(
  AstrologyInput input,
  DateTime utc, {
  required DateTime referenceUtc,
}) {
  final date = astrologyLocalDate(input, utc);
  final clock = astrologyLocalClock(input, utc);
  return date == astrologyLocalDate(input, referenceUtc)
      ? clock
      : '$clock (${date.substring(5)})';
}
