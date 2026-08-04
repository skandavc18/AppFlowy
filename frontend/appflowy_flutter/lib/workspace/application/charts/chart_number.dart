/// Anything that is not part of a number: currency marks, units, spaces.
///
/// A database exports what it displays, so a Number column comes back already
/// dressed: `$1,204.50`, `12 %`, `(48)` for a negative, `1.204,50` in a
/// European format. Every one of those is still a number.
final RegExp _notNumeric = RegExp(r'[^\d,.\-+eE]');

final RegExp _digits = RegExp(r'\d');

/// `1:30`, `01:30:15` — a duration, read as seconds.
final RegExp _clock = RegExp(r'^(\d+):([0-5]?\d)(?::([0-5]?\d))?$');

/// `2h 30m`, `45m`, `1d 2h`, `90s`.
final RegExp _spelledDuration = RegExp(
  r'^(?:(\d+)\s*d)?\s*(?:(\d+)\s*h)?\s*(?:(\d+)\s*m)?\s*(?:(\d+)\s*s)?$',
);

final RegExp _durationUnits = RegExp('[dhms]');

const _trueWords = {'true', 'yes', 'y', 'on', 'done', 'checked', '✓', '✔'};
const _falseWords = {'false', 'no', 'n', 'off', 'unchecked', '✗', '✘'};

/// Reads a number out of whatever a column displays.
///
/// Deliberately generous: a chart is useless if it only understands a column
/// the database happens to call `Number`. A checkbox is 1 or 0, a date is its
/// instant, a duration is its seconds, and a formatted amount is its amount.
/// Anything with no number in it at all returns null.
double? parseChartNumber(String? raw) {
  final text = raw?.trim();
  if (text == null || text.isEmpty) {
    return null;
  }

  final lower = text.toLowerCase();
  if (_trueWords.contains(lower)) {
    return 1;
  }
  if (_falseWords.contains(lower)) {
    return 0;
  }

  final clock = _clock.firstMatch(text);
  if (clock != null) {
    final hours = int.parse(clock.group(1)!);
    final minutes = int.parse(clock.group(2)!);
    final seconds = int.tryParse(clock.group(3) ?? '') ?? 0;
    return (hours * 3600 + minutes * 60 + seconds).toDouble();
  }

  final duration = _readSpelledDuration(lower);
  if (duration != null) {
    return duration;
  }

  final instant = DateTime.tryParse(text);
  if (instant != null) {
    return instant.millisecondsSinceEpoch / 1000;
  }

  return _readDecimal(text);
}

/// Whether [values] hold enough numbers to be worth plotting.
///
/// One stray number in a column of names is not a numeric column, so a
/// majority has to read as a number before the column is offered.
bool looksNumeric(Iterable<String> values) {
  var seen = 0;
  var numeric = 0;
  for (final value in values) {
    if (value.trim().isEmpty) {
      continue;
    }
    seen++;
    if (parseChartNumber(value) != null) {
      numeric++;
    }
    if (seen >= 64) {
      break;
    }
  }
  return seen > 0 && numeric * 2 >= seen;
}

/// A number as an axis or a tooltip should show it.
///
/// Long runs are abbreviated so an axis stays readable, and trailing zeros are
/// dropped so 4.0 reads as 4.
String formatChartNumber(double value, {bool compact = true}) {
  if (value.isNaN || value.isInfinite) {
    return '—';
  }
  final magnitude = value.abs();
  if (compact && magnitude >= 1000) {
    for (final unit in _units) {
      if (magnitude >= unit.$1) {
        return '${_trimZeros(value / unit.$1, 1)}${unit.$2}';
      }
    }
  }
  if (magnitude >= 100) {
    return _trimZeros(value, 0);
  }
  if (magnitude >= 1) {
    return _trimZeros(value, 2);
  }
  if (magnitude == 0) {
    return '0';
  }
  return _trimZeros(value, magnitude < 0.01 ? 4 : 3);
}

const _units = <(double, String)>[
  (1000000000000, 'T'),
  (1000000000, 'B'),
  (1000000, 'M'),
  (1000, 'K'),
];

String _trimZeros(double value, int digits) {
  var text = value.toStringAsFixed(digits);
  if (text.contains('.')) {
    text = text.replaceFirst(RegExp(r'\.?0+$'), '');
  }
  return text.isEmpty || text == '-' ? '0' : text;
}

double? _readSpelledDuration(String lower) {
  if (!_digits.hasMatch(lower) || !_durationUnits.hasMatch(lower)) {
    return null;
  }
  final match = _spelledDuration.firstMatch(lower);
  if (match == null) {
    return null;
  }
  final days = int.tryParse(match.group(1) ?? '') ?? 0;
  final hours = int.tryParse(match.group(2) ?? '') ?? 0;
  final minutes = int.tryParse(match.group(3) ?? '') ?? 0;
  final seconds = int.tryParse(match.group(4) ?? '') ?? 0;
  final total = days * 86400 + hours * 3600 + minutes * 60 + seconds;
  return total == 0 ? null : total.toDouble();
}

double? _readDecimal(String text) {
  var body = text.trim();
  // Accountants write a negative in brackets.
  final bracketed = body.startsWith('(') && body.endsWith(')');
  if (bracketed) {
    body = body.substring(1, body.length - 1);
  }

  body = body.replaceAll(_notNumeric, '');
  if (body.isEmpty || !_digits.hasMatch(body)) {
    return null;
  }

  final lastComma = body.lastIndexOf(',');
  final lastDot = body.lastIndexOf('.');
  if (lastComma >= 0 && lastDot >= 0) {
    // Whichever separator comes last is the decimal point; the other groups.
    body = lastComma > lastDot
        ? '${body.substring(0, lastComma).replaceAll(RegExp('[.,]'), '')}'
            '.${body.substring(lastComma + 1)}'
        : body.replaceAll(',', '');
  } else if (lastComma >= 0) {
    final tail = body.length - lastComma - 1;
    final onlyComma = body.indexOf(',') == lastComma;
    // `1,5` is a decimal; `1,204` and `1,204,500` are grouped thousands.
    body = onlyComma && tail != 3
        ? '${body.substring(0, lastComma)}.${body.substring(lastComma + 1)}'
        : body.replaceAll(',', '');
  }

  final value = double.tryParse(body);
  if (value == null) {
    return null;
  }
  return bracketed ? -value : value;
}
