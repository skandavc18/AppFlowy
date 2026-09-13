import 'astrology_model.dart';

/// Classical Parashari benefic-house rules (1-based, counted from contributor).
/// Order for BOTH dimensions: Sun, Moon, Mars, Mercury, Jupiter, Venus,
/// Saturn, Lagna. Cross-checked against Maitreya's Ashtakavarga.cpp REKHA_MAP.
/// See doc/vedic-astrology.md for sources and conventions.
const _rules = <List<List<int>>>[
  [
    // Sun, 48
    [1, 2, 4, 7, 8, 9, 10, 11], [3, 6, 10, 11], [1, 2, 4, 7, 8, 9, 10, 11],
    [3, 5, 6, 9, 10, 11, 12], [5, 6, 9, 11], [6, 7, 12],
    [1, 2, 4, 7, 8, 9, 10, 11], [3, 4, 6, 10, 11, 12],
  ],
  [
    // Moon, 49
    [3, 6, 7, 8, 10, 11], [1, 3, 6, 7, 10, 11], [2, 3, 5, 6, 9, 10, 11],
    [1, 3, 4, 5, 7, 8, 10, 11], [1, 2, 4, 7, 8, 10, 11],
    [3, 4, 5, 7, 9, 10, 11],
    [3, 5, 6, 11], [3, 6, 10, 11],
  ],
  [
    // Mars, 39
    [3, 5, 6, 10, 11], [3, 6, 11], [1, 2, 4, 7, 8, 10, 11], [3, 5, 6, 11],
    [6, 10, 11, 12], [6, 8, 11, 12], [1, 4, 7, 8, 9, 10, 11], [1, 3, 6, 10, 11],
  ],
  [
    // Mercury, 54
    [5, 6, 9, 11, 12], [2, 4, 6, 8, 10, 11], [1, 2, 4, 7, 8, 9, 10, 11],
    [1, 3, 5, 6, 9, 10, 11, 12], [6, 8, 11, 12], [1, 2, 3, 4, 5, 8, 9, 11],
    [1, 2, 4, 7, 8, 9, 10, 11], [1, 2, 4, 6, 8, 10, 11],
  ],
  [
    // Jupiter, 56
    [1, 2, 3, 4, 7, 8, 9, 10, 11], [2, 5, 7, 9, 11], [1, 2, 4, 7, 8, 10, 11],
    [1, 2, 4, 5, 6, 9, 10, 11], [1, 2, 3, 4, 7, 8, 10, 11],
    [2, 5, 6, 9, 10, 11],
    [3, 5, 6, 12], [1, 2, 4, 5, 6, 7, 9, 10, 11],
  ],
  [
    // Venus, 52
    [8, 11, 12], [1, 2, 3, 4, 5, 8, 9, 11, 12], [3, 4, 6, 9, 11, 12],
    [3, 5, 6, 9, 11],
    [5, 8, 9, 10, 11], [1, 2, 3, 4, 5, 8, 9, 10, 11], [3, 4, 5, 8, 9, 10, 11],
    [1, 2, 3, 4, 5, 8, 9, 11],
  ],
  [
    // Saturn, 39
    [1, 2, 4, 7, 8, 10, 11], [3, 6, 11], [3, 5, 6, 10, 11, 12],
    [6, 8, 9, 10, 11, 12],
    [5, 6, 11, 12], [6, 11, 12], [3, 5, 6, 11], [1, 3, 4, 6, 10, 11],
  ],
  [
    // Lagna, 49 (displayed separately; excluded from the 337-point SAV)
    [3, 4, 6, 10, 11, 12], [3, 6, 10, 11, 12], [1, 3, 6, 10, 11],
    [1, 2, 4, 6, 8, 10, 11],
    [1, 2, 4, 5, 6, 7, 9, 10, 11], [1, 2, 3, 4, 5, 8, 9], [1, 3, 4, 6, 10, 11],
    [3, 6, 10, 11],
  ],
];

class AshtakavargaResult {
  const AshtakavargaResult(
      {required this.bhinna, required this.sarva, required this.prastara});
  final List<List<int>> bhinna;
  final List<int> sarva;
  final List<List<List<int>>> prastara;
}

AshtakavargaResult calculateAshtakavarga(AstrologyChart chart) =>
    ashtakavargaForSigns([
      for (final body in VedicBody.classical) chart.planet(body).sign,
      zodiacSign(chart.ascendant),
    ]);

AshtakavargaResult ashtakavargaForSigns(List<int> signs) {
  if (signs.length != 8 || signs.any((sign) => sign < 0 || sign > 11)) {
    throw ArgumentError(
        'Seven planet signs and the Lagna sign (0–11) are required.');
  }
  final bhinna = List.generate(8, (_) => List.filled(12, 0));
  final prastara =
      List.generate(8, (_) => List.generate(8, (_) => List.filled(12, 0)));
  final sarva = List.filled(12, 0);
  for (var subject = 0; subject < 8; subject++) {
    for (var contributor = 0; contributor < 8; contributor++) {
      for (final house in _rules[subject][contributor]) {
        final sign = (signs[contributor] + house - 1) % 12;
        bhinna[subject][sign]++;
        prastara[subject][contributor][sign] = 1;
        if (subject < 7) sarva[sign]++;
      }
    }
  }
  return AshtakavargaResult(bhinna: bhinna, sarva: sarva, prastara: prastara);
}
