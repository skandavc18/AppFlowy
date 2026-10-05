import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// The minus sign money is written with. A hyphen is too short to read as a
/// loss at a glance, and it would jump the column when a figure turns red.
const financeMinus = '\u2212';

/// How the digits of a large amount are grouped.
enum MoneyGrouping {
  /// 12,34,56,789 — lakh and crore.
  indian,

  /// 123,456,789 — thousands, millions and billions.
  international,
}

/// How money reads on a dashboard: the symbol in front of it, how its digits
/// are grouped, and how a long amount is shortened when space is tight.
@immutable
class MoneyStyle {
  const MoneyStyle({
    this.symbol = '₹',
    this.grouping = MoneyGrouping.indian,
  });

  /// The style a dashboard setting names. Unknown codes read as rupees, which
  /// is what every finance template starts with.
  factory MoneyStyle.forCurrency(String code) =>
      switch (code.trim().toUpperCase()) {
        'USD' => const MoneyStyle(
            symbol: r'$',
            grouping: MoneyGrouping.international,
          ),
        'EUR' => const MoneyStyle(
            symbol: '€',
            grouping: MoneyGrouping.international,
          ),
        'GBP' => const MoneyStyle(
            symbol: '£',
            grouping: MoneyGrouping.international,
          ),
        'JPY' => const MoneyStyle(
            symbol: '¥',
            grouping: MoneyGrouping.international,
          ),
        'NONE' => const MoneyStyle(
            symbol: '',
            grouping: MoneyGrouping.international,
          ),
        _ => rupee,
      };

  static const rupee = MoneyStyle();

  /// The codes a currency setting offers, in the order they are offered.
  static const currencies = ['INR', 'USD', 'EUR', 'GBP', 'JPY', 'NONE'];

  final String symbol;
  final MoneyGrouping grouping;

  /// A whole amount, `₹12,34,567`. Small amounts keep their paise so a
  /// ₹48.50 option premium does not read as ₹49.
  String format(double value, {int? decimals, bool signed = false}) {
    if (!value.isFinite) {
      return '—';
    }
    final places = decimals ?? (value.abs() < 100 && value != 0 ? 2 : 0);
    return _withSign(
      value,
      '$symbol${groupDigits(value.abs(), grouping, decimals: places)}',
      signed,
    );
  }

  /// A price, always with two decimals: `₹1,167.70`.
  String price(double value, {bool signed = false}) =>
      format(value, decimals: 2, signed: signed);

  /// A short amount for tight places: `₹12.4 L`, `₹1.25 Cr`, `$4.2M`.
  String compact(double value, {bool signed = false}) {
    if (!value.isFinite) {
      return '—';
    }
    final magnitude = value.abs();
    final units = grouping == MoneyGrouping.indian ? _indianUnits : _westUnits;
    for (final (size, suffix) in units) {
      if (magnitude >= size) {
        final scaled = magnitude / size;
        return _withSign(
          value,
          '$symbol${_trim(scaled, scaled < 10 ? 2 : (scaled < 100 ? 1 : 0))}'
          '$suffix',
          signed,
        );
      }
    }
    return format(value, signed: signed);
  }

  /// [compact] once an amount no longer fits comfortably, [format] before.
  String fit(double value, {bool signed = false, double from = 1e7}) =>
      value.abs() >= from
          ? compact(value, signed: signed)
          : format(value, signed: signed);

  @override
  bool operator ==(Object other) =>
      other is MoneyStyle &&
      other.symbol == symbol &&
      other.grouping == grouping;

  @override
  int get hashCode => Object.hash(symbol, grouping);
}

const _indianUnits = <(double, String)>[
  (1e7, ' Cr'),
  (1e5, ' L'),
  (1e3, 'K'),
];

const _westUnits = <(double, String)>[
  (1e12, 'T'),
  (1e9, 'B'),
  (1e6, 'M'),
  (1e3, 'K'),
];

String _withSign(double value, String body, bool signed) {
  if (value < 0 && _roundsToNonZero(value)) {
    return '$financeMinus$body';
  }
  if (signed && value > 0 && _roundsToNonZero(value)) {
    return '+$body';
  }
  return body;
}

bool _roundsToNonZero(double value) => value.abs() >= 0.005;

String _trim(double value, int digits) {
  var text = value.toStringAsFixed(digits);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return text;
}

/// The digits of [magnitude] grouped the way [grouping] reads them.
String groupDigits(
  double magnitude,
  MoneyGrouping grouping, {
  int decimals = 0,
}) {
  final fixed = magnitude.abs().toStringAsFixed(decimals);
  final dot = fixed.indexOf('.');
  final whole = dot < 0 ? fixed : fixed.substring(0, dot);
  final fraction = dot < 0 ? '' : fixed.substring(dot);
  final buffer = StringBuffer();
  if (grouping == MoneyGrouping.international || whole.length <= 3) {
    for (var index = 0; index < whole.length; index++) {
      if (index > 0 && (whole.length - index) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(whole[index]);
    }
  } else {
    // The last three digits stand alone; everything before goes in pairs.
    final head = whole.substring(0, whole.length - 3);
    for (var index = 0; index < head.length; index++) {
      if (index > 0 && (head.length - index).isEven) {
        buffer.write(',');
      }
      buffer.write(head[index]);
    }
    buffer
      ..write(',')
      ..write(whole.substring(whole.length - 3));
  }
  return '$buffer$fraction';
}

/// A percentage, `+12.40%`. [value] is already in percent.
String formatPercent(double? value, {int decimals = 2, bool signed = true}) {
  if (value == null || !value.isFinite) {
    return '—';
  }
  final digits = value.abs() >= 1000 ? 0 : decimals;
  return _withSign(
    value,
    '${value.abs().toStringAsFixed(digits)}%',
    signed,
  );
}

/// A count of shares or lots: whole numbers stay whole, fractional units of a
/// mutual fund keep three places.
String formatQuantity(double value) {
  if (!value.isFinite) {
    return '—';
  }
  if ((value - value.roundToDouble()).abs() < 1e-9) {
    return groupDigits(value, MoneyGrouping.international);
  }
  return _withSign(value, _trim(value.abs(), 3), false);
}

/// A plain number grouped for reading, such as a strike or an index level.
String formatLevel(double value, {int decimals = 0}) {
  if (!value.isFinite) {
    return '—';
  }
  return _withSign(
    value,
    groupDigits(value.abs(), MoneyGrouping.international, decimals: decimals),
    false,
  );
}

/// A count written short: 12.4K, 3.2M. Open interest and volume read this way.
String formatCount(double value) {
  final magnitude = value.abs();
  for (final (size, suffix) in _westUnits) {
    if (magnitude >= size) {
      final scaled = magnitude / size;
      return _withSign(
        value,
        '${_trim(scaled, scaled < 10 ? 2 : (scaled < 100 ? 1 : 0))}$suffix',
        false,
      );
    }
  }
  return _withSign(value, _trim(magnitude, 0), false);
}

final RegExp _moneySuffix = RegExp(
  r'^(.*?)\s*(cr|crore|crores|l|lakh|lakhs|lac|lacs|k|m|mn|b|bn)\.?$',
  caseSensitive: false,
);

/// Reads an amount out of whatever a cell shows.
///
/// Unlike a chart's generous reader this never mistakes a long amount for a
/// date: `10000000` is one crore, not the year 1000. It understands currency
/// marks, Indian and Western grouping, `(1,200)` and `−1,200` for a loss, a
/// trailing `%`, and the short forms people type — `1.2 Cr`, `45 L`, `12k`.
double? parseMoney(String? raw) {
  var text = raw?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }
  var negative = false;
  if (text.startsWith('(') && text.endsWith(')')) {
    negative = true;
    text = text.substring(1, text.length - 1).trim();
  }
  text = text
      .replaceAll(financeMinus, '-')
      .replaceAll('\u2013', '-')
      .replaceAll(
          RegExp(r'(?:rs\.?|inr|usd|eur|gbp)', caseSensitive: false), '')
      .replaceAll(RegExp(r'[₹$€£¥%\s\u00a0]'), '');
  if (text.isEmpty) {
    return null;
  }

  var multiplier = 1.0;
  final suffix = _moneySuffix.firstMatch(text);
  if (suffix != null && suffix.group(1)!.isNotEmpty) {
    multiplier = switch (suffix.group(2)!.toLowerCase()) {
      'cr' || 'crore' || 'crores' => 1e7,
      'l' || 'lakh' || 'lakhs' || 'lac' || 'lacs' => 1e5,
      'k' => 1e3,
      'm' || 'mn' => 1e6,
      _ => 1e9,
    };
    text = suffix.group(1)!;
  }

  if (text.startsWith('-')) {
    negative = !negative;
    text = text.substring(1);
  } else if (text.startsWith('+')) {
    text = text.substring(1);
  }

  final lastComma = text.lastIndexOf(',');
  final lastDot = text.lastIndexOf('.');
  if (lastComma > lastDot && lastDot >= 0) {
    // 1.204,50 — a comma decimal with dotted thousands.
    text = text.replaceAll('.', '').replaceAll(',', '.');
  } else if (lastComma >= 0 && lastDot < 0) {
    // Commas only: grouping, unless a single comma sits before one or two
    // digits at the very end, which is a decimal comma.
    final tail = text.length - lastComma - 1;
    final single = text.indexOf(',') == lastComma;
    text = single && tail > 0 && tail <= 2
        ? text.replaceAll(',', '.')
        : text.replaceAll(',', '');
  } else {
    text = text.replaceAll(',', '');
  }

  if (!RegExp(r'^\d*\.?\d+(?:[eE][-+]?\d+)?$').hasMatch(text) &&
      !RegExp(r'^\d+\.$').hasMatch(text)) {
    return null;
  }
  final value = double.tryParse(text);
  if (value == null || !value.isFinite) {
    return null;
  }
  return (negative ? -value : value) * multiplier;
}

/// The ratio of [part] to [whole] as a percentage, or null when meaningless.
double? percentOf(double part, double whole) {
  if (whole == 0 || !whole.isFinite || !part.isFinite) {
    return null;
  }
  return part / whole * 100;
}

/// A short relative age: "now", "4m", "3h", "2d".
String formatAge(Duration age) {
  if (age.inSeconds < 45) {
    return 'now';
  }
  if (age.inMinutes < 60) {
    return '${math.max(1, age.inMinutes)}m';
  }
  if (age.inHours < 24) {
    return '${age.inHours}h';
  }
  return '${age.inDays}d';
}
