/// Turns evaluated values into the text a cell shows, and infers what a
/// column is holding so a freshly pasted table already looks right.
library;

import 'package:intl/intl.dart' as intl;

import 'spreadsheet_formula.dart';
import 'spreadsheet_model.dart';

/// Common date input patterns, tried in order.
final List<intl.DateFormat> _dateInputFormats = [
  intl.DateFormat('yyyy-MM-dd'),
  intl.DateFormat('yyyy/MM/dd'),
  intl.DateFormat('dd/MM/yyyy'),
  intl.DateFormat('MM/dd/yyyy'),
  intl.DateFormat('d MMM yyyy'),
  intl.DateFormat('MMM d, yyyy'),
];

final List<intl.DateFormat> _timeInputFormats = [
  intl.DateFormat('HH:mm:ss'),
  intl.DateFormat('HH:mm'),
  intl.DateFormat('h:mm a'),
  intl.DateFormat('h:mma'),
];

DateTime? parseCellDate(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  final iso = DateTime.tryParse(text);
  if (iso != null) {
    return iso;
  }
  for (final format in _dateInputFormats) {
    try {
      return format.parseStrict(text);
    } on FormatException {
      continue;
    }
  }
  return null;
}

/// Writes [date] back in the shape [source] was typed in, so continuing a
/// date series does not silently reformat the column.
String formatCellDateLike(String source, DateTime date) {
  final text = source.trim();
  for (final format in _dateInputFormats) {
    try {
      format.parseStrict(text);
      return format.format(date);
    } on FormatException {
      continue;
    }
  }
  return date.toIso8601String().split('T').first;
}

DateTime? parseCellTime(String raw) {
  final text = raw.trim();
  if (text.isEmpty) {
    return null;
  }
  for (final format in _timeInputFormats) {
    try {
      return format.parseStrict(text);
    } on FormatException {
      continue;
    }
  }
  return parseCellDate(text);
}

/// The text a cell displays once its value has been evaluated and its number
/// format applied.
String formatCellValue(SheetValue value, CellStyle style, {String raw = ''}) {
  if (value is ErrorValue) {
    return value.code;
  }
  switch (style.format) {
    case CellNumberFormat.text:
      return raw;
    case CellNumberFormat.date:
      final date = parseCellDate(value.asText.isEmpty ? raw : value.asText);
      if (date != null) {
        return intl.DateFormat.yMMMd().format(date);
      }
      return value.asText;
    case CellNumberFormat.time:
      final time = parseCellTime(value.asText.isEmpty ? raw : value.asText);
      if (time != null) {
        return intl.DateFormat.Hm().format(time);
      }
      return value.asText;
    case CellNumberFormat.number:
      final number = value.asNumber;
      if (number == null) {
        return value.asText;
      }
      return _decimalFormat(style.decimals).format(number);
    case CellNumberFormat.currency:
      final number = value.asNumber;
      if (number == null) {
        return value.asText;
      }
      final symbol = style.currencySymbol ?? r'$';
      final digits = style.decimals ?? 2;
      final formatted = intl.NumberFormat.currency(
        symbol: symbol,
        decimalDigits: digits,
      ).format(number);
      return formatted;
    case CellNumberFormat.percent:
      final number = value.asNumber;
      if (number == null) {
        return value.asText;
      }
      final digits = style.decimals ?? 0;
      return '${_decimalFormat(digits).format(number * 100)}%';
    case CellNumberFormat.automatic:
      if (value is NumberValue) {
        return style.decimals == null
            ? formatPlainNumber(value.value)
            : _decimalFormat(style.decimals).format(value.value);
      }
      return value.asText;
  }
}

intl.NumberFormat _decimalFormat(int? decimals) {
  if (decimals == null) {
    return intl.NumberFormat('#,##0.##########');
  }
  final buffer = StringBuffer('#,##0');
  if (decimals > 0) {
    buffer
      ..write('.')
      ..write('0' * decimals);
  }
  return intl.NumberFormat(buffer.toString());
}

/// Whether a value should sit against the right edge when no explicit
/// alignment is set — numbers and dates do, everything else does not.
bool isRightAlignedByDefault(SheetValue value, CellStyle style) {
  if (style.format == CellNumberFormat.text) {
    return false;
  }
  if (style.format.isNumeric) {
    return true;
  }
  if (style.format == CellNumberFormat.date ||
      style.format == CellNumberFormat.time) {
    return true;
  }
  return value is NumberValue;
}

/// What a column looks like it is holding, used for automatic formatting.
enum ColumnKind { text, number, currency, percent, date, time, boolean }

/// Inspects a column's body cells and guesses its type.
///
/// Returns null when there is not enough evidence — a column of two values is
/// not worth reformatting behind the user's back.
ColumnKind? detectColumnKind(
  SpreadsheetData data,
  int column, {
  int minimumSamples = 2,
}) {
  var samples = 0;
  var numbers = 0;
  var currencies = 0;
  var percents = 0;
  var dates = 0;
  var times = 0;
  var booleans = 0;

  for (var row = 0; row < data.rowCount; row++) {
    final raw = data.rawAt(CellRef(row, column)).trim();
    if (raw.isEmpty) {
      continue;
    }
    if (raw.startsWith('=')) {
      continue;
    }
    samples++;
    final upper = raw.toUpperCase();
    if (upper == 'TRUE' || upper == 'FALSE') {
      booleans++;
      continue;
    }
    if (RegExp(r'^[\$€£¥₹]').hasMatch(raw) ||
        RegExp(r'[\$€£¥₹]$').hasMatch(raw)) {
      if (parseCellNumber(raw) != null) {
        currencies++;
        numbers++;
        continue;
      }
    }
    if (raw.endsWith('%') && parseCellNumber(raw) != null) {
      percents++;
      numbers++;
      continue;
    }
    if (parseCellNumber(raw) != null) {
      numbers++;
      continue;
    }
    if (parseCellDate(raw) != null) {
      dates++;
      continue;
    }
    if (parseCellTime(raw) != null) {
      times++;
      continue;
    }
  }

  if (samples < minimumSamples) {
    return null;
  }
  final threshold = (samples * 0.8).ceil();
  if (currencies >= threshold) {
    return ColumnKind.currency;
  }
  if (percents >= threshold) {
    return ColumnKind.percent;
  }
  if (numbers >= threshold) {
    return ColumnKind.number;
  }
  if (dates >= threshold) {
    return ColumnKind.date;
  }
  if (times >= threshold) {
    return ColumnKind.time;
  }
  if (booleans >= threshold) {
    return ColumnKind.boolean;
  }
  return ColumnKind.text;
}

CellNumberFormat formatForColumnKind(ColumnKind kind) => switch (kind) {
      ColumnKind.number => CellNumberFormat.number,
      ColumnKind.currency => CellNumberFormat.currency,
      ColumnKind.percent => CellNumberFormat.percent,
      ColumnKind.date => CellNumberFormat.date,
      ColumnKind.time => CellNumberFormat.time,
      ColumnKind.text || ColumnKind.boolean => CellNumberFormat.automatic,
    };
