import 'astrology_model.dart';

const vimshottariLords = [
  VedicBody.ketu,
  VedicBody.venus,
  VedicBody.sun,
  VedicBody.moon,
  VedicBody.mars,
  VedicBody.rahu,
  VedicBody.jupiter,
  VedicBody.saturn,
  VedicBody.mercury,
];
const vimshottariYears = [7, 20, 6, 10, 7, 18, 16, 19, 17];

const vimshottariLevelNames = [
  'Mahadasha',
  'Antardasha',
  'Pratyantardasha',
  'Sookshma dasha',
];

class DashaPeriod {
  const DashaPeriod({
    required this.lord,
    required this.start,
    required this.end,
    this.level = 0,
  });

  final VedicBody lord;
  final DateTime start;
  final DateTime end;
  final int level;

  bool contains(DateTime time) => !time.isBefore(start) && time.isBefore(end);

  /// Subdivide the FULL parent's duration, including the portion before birth.
  /// Clipping the first mahadasha to birth before subdividing is a subtle but
  /// serious error: every antardasha of the birth mahadasha would shift.
  List<DashaPeriod> get children {
    if (level >= vimshottariLevelNames.length - 1) return const [];
    final first = vimshottariLords.indexOf(lord);
    final duration = end.difference(start).inMicroseconds;
    var elapsed = 0;
    // Round cumulative fractions using integers. The final endpoint is
    // exactly the parent's, including sub-second precision at Sookshma level.
    int boundary(int years) => (duration * years + 60) ~/ 120;
    return [
      for (var i = 0; i < 9; i++)
        DashaPeriod(
          lord: vimshottariLords[(first + i) % 9],
          start: start.add(
            Duration(microseconds: boundary(elapsed)),
          ),
          end: start.add(
            Duration(
              microseconds: boundary(
                elapsed += vimshottariYears[(first + i) % 9],
              ),
            ),
          ),
          level: level + 1,
        ),
    ];
  }
}

/// One 120-year cycle beginning at the actual start of the birth mahadasha.
List<DashaPeriod> vimshottariPeriods({
  required DateTime birthUtc,
  required double moonLongitude,
  double yearDays = 365.25636,
}) {
  if (!moonLongitude.isFinite || !yearDays.isFinite || yearDays <= 0) {
    throw ArgumentError(
      'A finite longitude and positive year length are required.',
    );
  }
  final mansion = normalizeDegrees(moonLongitude) * 3 / 40;
  final lord = mansion.floor() % 9;
  final yearMicros = yearDays * Duration.microsecondsPerDay;
  final elapsed = (mansion - mansion.floor()) * vimshottariYears[lord];
  final start = birthUtc.toUtc().subtract(
        Duration(microseconds: (elapsed * yearMicros).round()),
      );
  var years = 0;
  return [
    for (var i = 0; i < 9; i++)
      DashaPeriod(
        lord: vimshottariLords[(lord + i) % 9],
        start: start.add(Duration(microseconds: (years * yearMicros).round())),
        end: start.add(
          Duration(
            microseconds:
                ((years += vimshottariYears[(lord + i) % 9]) * yearMicros)
                    .round(),
          ),
        ),
      ),
  ];
}

/// The four lords at a life event's instant, through Sookshma dasha.
/// No made-up period outside the
/// displayed cycle; callers can leave the cells blank in that case.
List<DashaPeriod> dashaAt(List<DashaPeriod> periods, DateTime utc) {
  final result = <DashaPeriod>[];
  var candidates = periods;
  for (var level = 0; level < vimshottariLevelNames.length; level++) {
    DashaPeriod? found;
    for (final period in candidates) {
      if (period.contains(utc)) {
        found = period;
        break;
      }
    }
    if (found == null) break;
    result.add(found);
    candidates = found.children;
  }
  return result;
}
