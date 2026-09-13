import 'astrology_model.dart';

/// The two commonly used chara-karaka conventions. Ketu and special lagnas
/// participate in neither; the eight-karaka system adds Rahu and Pitri.
enum JaiminiKarakaScheme {
  seven('7 karakas · Sun–Saturn'),
  eight('8 karakas · including Rahu');

  const JaiminiKarakaScheme(this.label);
  final String label;

  List<JaiminiKaraka> get karakas => [
        for (final karaka in JaiminiKaraka.values)
          if (this == eight || karaka != JaiminiKaraka.pitri) karaka,
      ];
}

enum JaiminiKaraka {
  atma('AK', 'Atmakaraka', 'Self / soul'),
  amatya('AmK', 'Amatyakaraka', 'Counsel / vocation'),
  bhratri('BK', 'Bhratrikaraka', 'Siblings / courage'),
  matri('MK', 'Matrikaraka', 'Mother / nurture'),
  pitri('PiK', 'Pitrikaraka', 'Father / lineage'),
  putra('PK', 'Putrakaraka', 'Children / creativity'),
  gnati('GK', 'Gnatikaraka', 'Kin / challenges'),
  dara('DK', 'Darakaraka', 'Spouse / partnership');

  const JaiminiKaraka(this.abbreviation, this.label, this.signification);
  final String abbreviation;
  final String label;
  final String signification;
}

class JaiminiKarakaAssignment {
  const JaiminiKarakaAssignment({
    required this.placement,
    required this.rankDegrees,
    required this.karakas,
  });

  final VedicPlacement placement;

  /// Degrees traversed within the sign; Rahu uses 30 minus that longitude.
  final double rankDegrees;

  /// One role normally. Tied ranks name all affected roles, without an
  /// arbitrary planet-order tie-break or a claim that both roles are assigned.
  final List<JaiminiKaraka> karakas;
  bool get isTied => karakas.length > 1;
  String get abbreviation =>
      '${karakas.map((karaka) => karaka.abbreviation).join(' / ')}'
      '${isTied ? ' (tie)' : ''}';
}

class JaiminiKarakaResult {
  const JaiminiKarakaResult({required this.scheme, required this.assignments});

  final JaiminiKarakaScheme scheme;
  final List<JaiminiKarakaAssignment> assignments;
  bool get hasTies => assignments.any((assignment) => assignment.isTied);

  JaiminiKarakaAssignment? forBody(VedicBody? body) {
    for (final assignment in assignments) {
      if (assignment.placement.body == body) return assignment;
    }
    return null;
  }
}

/// Rank original sidereal D-1 degrees *within* each sign, highest first.
/// Retrograde physical planets still use their actual longitude; only Rahu
/// is reversed, regardless of the selected mean/true node's instantaneous
/// speed. At exactly 0° within a sign Rahu's rank is 30°, not 0°.
///
/// Ranking uses unrounded values. Differences at or below 1e-10 degrees are
/// treated as numerical ties; the UI reports them as unresolved. No tradition-
/// specific secondary tie-breaking rule is silently imposed.
JaiminiKarakaResult calculateJaiminiKarakas(
  Iterable<VedicPlacement> placements, {
  JaiminiKarakaScheme scheme = JaiminiKarakaScheme.seven,
}) {
  final bodies = [
    ...VedicBody.classical,
    if (scheme == JaiminiKarakaScheme.eight) VedicBody.rahu,
  ];
  final positions = <VedicBody, VedicPlacement>{};
  for (final placement in placements) {
    final body = placement.body;
    if (body == null || !bodies.contains(body)) continue;
    if (!placement.longitude.isFinite || positions.containsKey(body)) {
      throw FormatException(
        'Jaimini Karakas need one finite longitude for ${body.label}.',
      );
    }
    positions[body] = placement;
  }
  for (final body in bodies) {
    if (!positions.containsKey(body)) {
      throw FormatException(
        '${body.label} is missing; Jaimini Karakas are unavailable.',
      );
    }
  }
  double degrees(VedicBody body) {
    final withinSign = normalizeDegrees(positions[body]!.longitude) % 30;
    return body == VedicBody.rahu ? 30 - withinSign : withinSign;
  }

  final ordered = [...bodies]..sort((a, b) {
      final order = degrees(b).compareTo(degrees(a));
      // This only stabilizes the display order of ties, not their roles.
      return order != 0 ? order : a.index.compareTo(b.index);
    });
  final karakas = scheme.karakas;
  final assignments = <JaiminiKarakaAssignment>[];
  for (var first = 0; first < ordered.length;) {
    var end = first + 1;
    while (end < ordered.length &&
        (degrees(ordered[first]) - degrees(ordered[end])).abs() <= 1e-10) {
      end++;
    }
    final roles = List<JaiminiKaraka>.unmodifiable(karakas.sublist(first, end));
    for (var index = first; index < end; index++) {
      final body = ordered[index];
      assignments.add(
        JaiminiKarakaAssignment(
          placement: positions[body]!,
          rankDegrees: degrees(body),
          karakas: roles,
        ),
      );
    }
    first = end;
  }
  return JaiminiKarakaResult(
    scheme: scheme,
    assignments: List.unmodifiable(assignments),
  );
}
