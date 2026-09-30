import 'astrology_model.dart';
import 'vimshottari.dart';

/// Shared panchanga names and day-division rules. Pure Dart: no ephemeris,
/// time-zone lookup or widgets, so every rule is unit-testable offline.

const tithiNames = [
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

const yogaNames = [
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

const weekdayNames = [
  'Sunday',
  'Monday',
  'Tuesday',
  'Wednesday',
  'Thursday',
  'Friday',
  'Saturday',
];

/// Lords of the weekdays, Sunday first (the same index as [weekdayNames]).
const weekdayLords = [
  VedicBody.sun,
  VedicBody.moon,
  VedicBody.mars,
  VedicBody.mercury,
  VedicBody.jupiter,
  VedicBody.venus,
  VedicBody.saturn,
];

/// Descending Chaldean order used for successive horas.
const _horaSequence = [
  VedicBody.sun,
  VedicBody.venus,
  VedicBody.mercury,
  VedicBody.moon,
  VedicBody.saturn,
  VedicBody.jupiter,
  VedicBody.mars,
];

/// [halfTithi] is 0–59 from the new moon.
String karanaName(int halfTithi) => switch (halfTithi) {
      0 => 'Kimstughna',
      57 => 'Shakuni',
      58 => 'Chatushpada',
      59 => 'Naga',
      _ => _karanaNames[(halfTithi - 1) % 7],
    };

/// [tithi] is 1–30; 15 is Purnima and 30 is Amavasya.
String tithiName(int tithi) =>
    tithi == 30 ? 'Amavasya' : tithiNames[(tithi - 1) % 15];

String pakshaName(int tithi) => tithi <= 15 ? 'Shukla' : 'Krishna';

/// The Vimshottari lord of a nakshatra (Ashwini = Ketu, Bharani = Venus…).
VedicBody nakshatraLord(int nakshatra) => vimshottariLords[nakshatra % 9];

/// Whole-sign house of [sign] counted from [fromSign] (both 0–11): 1–12.
int houseFromSign(int fromSign, int sign) => (sign - fromSign) % 12 + 1;

String ordinal(int value) {
  final teen = value % 100;
  if (teen >= 11 && teen <= 13) return '${value}th';
  return switch (value % 10) {
    1 => '${value}st',
    2 => '${value}nd',
    3 => '${value}rd',
    _ => '${value}th',
  };
}

/// "Leo 12°34′": rounded to the second, then truncated to whole minutes so a
/// planet just below a cusp never displays the next sign or 60 minutes.
String compactLongitude(double longitude) {
  final normalized = normalizeDegrees(longitude);
  final seconds = ((normalized % 30) * 3600).round().clamp(0, 107999);
  return '${zodiacNames[zodiacSign(normalized)]} ${seconds ~/ 3600}°'
      '${(seconds ~/ 60 % 60).toString().padLeft(2, '0')}′';
}

/// End instants of the limbs current at a chart's instant, and the sunset
/// before its sunrise. A null value could not be calculated reliably.
class AstrologyPanchangaTimes {
  const AstrologyPanchangaTimes({
    this.tithiEnd,
    this.nakshatraEnd,
    this.yogaEnd,
    this.karanaEnd,
    this.previousSunset,
  });

  final DateTime? tithiEnd;
  final DateTime? nakshatraEnd;
  final DateTime? yogaEnd;
  final DateTime? karanaEnd;
  final DateTime? previousSunset;
}

enum MuhurtaQuality { favourable, avoid }

/// A traditional window of one Vedic day, in UTC.
class MuhurtaWindow {
  const MuhurtaWindow({
    required this.name,
    required this.start,
    required this.end,
    required this.quality,
    this.note = '',
  });

  final String name;
  final DateTime start;
  final DateTime end;
  final MuhurtaQuality quality;
  final String note;

  bool contains(DateTime utc) => !utc.isBefore(start) && utc.isBefore(end);
}

// 1-based eighths of daytime (sunrise to sunset), Sunday first.
const _rahuKalam = [8, 2, 7, 5, 6, 4, 3];
const _yamaganda = [5, 4, 3, 2, 1, 7, 6];
const _gulikaKalam = [7, 6, 5, 4, 3, 2, 1];

DateTime _fraction(DateTime start, DateTime end, int numerator, int parts) =>
    start.add(
      Duration(
        microseconds:
            (end.difference(start).inMicroseconds * numerator / parts).round(),
      ),
    );

/// Brahma muhurta, Rahu Kalam, Yamaganda, Gulika Kalam and Abhijit for the
/// Vedic day of [chart] (its sunrise to sunset), ordered by start time.
/// Unavailable during polar day/night, when sunrise/sunset do not exist.
List<MuhurtaWindow> muhurtaWindows(
  AstrologyChart chart, {
  DateTime? previousSunset,
}) {
  final rise = chart.sunrise;
  final set = chart.sunset;
  if (rise == null || set == null || !set.isAfter(rise)) return const [];
  final weekday = chart.weekday % 7;
  MuhurtaWindow eighth(String name, int part, String note) => MuhurtaWindow(
        name: name,
        start: _fraction(rise, set, part - 1, 8),
        end: _fraction(rise, set, part, 8),
        quality: MuhurtaQuality.avoid,
        note: note,
      );
  final windows = [
    if (previousSunset != null && previousSunset.isBefore(rise))
      MuhurtaWindow(
        name: 'Brahma muhurta',
        start: _fraction(previousSunset, rise, 13, 15),
        end: _fraction(previousSunset, rise, 14, 15),
        quality: MuhurtaQuality.favourable,
        note: '14th of the 15 night muhurtas before sunrise',
      ),
    eighth(
      'Rahu Kalam',
      _rahuKalam[weekday],
      '${ordinal(_rahuKalam[weekday])} eighth of daytime',
    ),
    eighth(
      'Yamaganda',
      _yamaganda[weekday],
      '${ordinal(_yamaganda[weekday])} eighth of daytime',
    ),
    eighth(
      'Gulika Kalam',
      _gulikaKalam[weekday],
      '${ordinal(_gulikaKalam[weekday])} eighth of daytime',
    ),
    MuhurtaWindow(
      name: 'Abhijit muhurta',
      start: _fraction(rise, set, 7, 15),
      end: _fraction(rise, set, 8, 15),
      quality: weekday == 3 ? MuhurtaQuality.avoid : MuhurtaQuality.favourable,
      note: weekday == 3
          ? 'Traditionally not used on Wednesday'
          : '8th of the 15 day muhurtas',
    ),
  ]..sort((a, b) => a.start.compareTo(b.start));
  return windows;
}

/// One of the 24 unequal planetary hours of a Vedic day.
class HoraPeriod {
  const HoraPeriod({
    required this.lord,
    required this.start,
    required this.end,
    required this.number,
  });

  final VedicBody lord;
  final DateTime start;
  final DateTime end;

  /// 1–12 during the day, 13–24 during the night.
  final int number;
  bool get isDay => number <= 12;
}

/// Day and night are each split into 12 equal horas; the first hora after
/// sunrise belongs to the weekday lord, then the Chaldean order continues.
HoraPeriod? horaAt(AstrologyChart chart) {
  final rise = chart.sunrise;
  final set = chart.sunset;
  final next = chart.nextSunrise;
  final utc = chart.utc;
  if (rise == null ||
      set == null ||
      next == null ||
      utc.isBefore(rise) ||
      !utc.isBefore(next)) {
    return null;
  }
  final day = utc.isBefore(set);
  final start = day ? rise : set;
  final end = day ? set : next;
  final span = end.difference(start).inMicroseconds;
  if (span <= 0) return null;
  final index =
      (utc.difference(start).inMicroseconds * 12 ~/ span).clamp(0, 11);
  final number = (day ? 0 : 12) + index;
  final first = _horaSequence.indexOf(weekdayLords[chart.weekday % 7]);
  return HoraPeriod(
    lord: _horaSequence[(first + number) % 7],
    start: _fraction(start, end, index, 12),
    end: _fraction(start, end, index + 1, 12),
    number: number + 1,
  );
}

const taraNames = [
  'Janma',
  'Sampat',
  'Vipat',
  'Kshema',
  'Pratyak',
  'Sadhana',
  'Naidhana',
  'Mitra',
  'Parama Mitra',
];

/// Nakshatra count from the natal Moon's nakshatra (Janma = 1).
class TaraBala {
  const TaraBala(this.count);

  /// 1–27, counting the birth nakshatra itself as 1.
  final int count;

  /// 1–9 (Janma … Parama Mitra).
  int get tara => (count - 1) % 9 + 1;
  String get name => taraNames[tara - 1];

  /// Null for Janma tara, which is traditionally mixed.
  bool? get favourable => switch (tara) {
        1 => null,
        3 || 5 || 7 => false,
        _ => true,
      };
}

TaraBala taraBala({required double natalMoon, required double moon}) =>
    TaraBala((nakshatraIndex(moon) - nakshatraIndex(natalMoon)) % 27 + 1);

/// The transiting Moon's sign counted from the natal Moon's sign.
class ChandraBala {
  const ChandraBala(this.house);

  /// 1–12.
  final int house;
  bool get favourable => const {1, 3, 6, 7, 10, 11}.contains(house);
}

ChandraBala chandraBala({required double natalMoon, required double moon}) =>
    ChandraBala(houseFromSign(zodiacSign(natalMoon), zodiacSign(moon)));

/// Sade Sati and the other Saturn transits counted from the natal Moon.
String? saturnTransitNote({required double natalMoon, required double saturn}) {
  final house = houseFromSign(zodiacSign(natalMoon), zodiacSign(saturn));
  return switch (house) {
    12 => 'Sade Sati · rising phase (Saturn 12th from natal Moon)',
    1 => 'Sade Sati · peak phase (Saturn in the natal Moon sign)',
    2 => 'Sade Sati · setting phase (Saturn 2nd from natal Moon)',
    4 => 'Ardhashtama Shani (Saturn 4th from natal Moon)',
    8 => 'Ashtama Shani (Saturn 8th from natal Moon)',
    _ => null,
  };
}

/// The five Sun-based aprakasha (shadow) upagrahas of Parashara.
List<VedicPlacement> sunUpagrahas(double sunLongitude) {
  final dhuma = normalizeDegrees(sunLongitude + 133 + 1 / 3);
  final vyatipata = normalizeDegrees(360 - dhuma);
  final parivesha = normalizeDegrees(vyatipata + 180);
  final indrachapa = normalizeDegrees(360 - parivesha);
  final upaketu = normalizeDegrees(indrachapa + 16 + 2 / 3);
  return [
    VedicPlacement(name: 'Dhuma', shortName: 'Dh', longitude: dhuma),
    VedicPlacement(name: 'Vyatipata', shortName: 'Vy', longitude: vyatipata),
    VedicPlacement(name: 'Parivesha', shortName: 'Pv', longitude: parivesha),
    VedicPlacement(name: 'Indrachapa', shortName: 'Ic', longitude: indrachapa),
    VedicPlacement(name: 'Upaketu', shortName: 'Uk', longitude: upaketu),
  ];
}
