import 'package:appflowy/workspace/application/charts/chart_data.dart';
import 'package:appflowy/workspace/application/finance/finance_table.dart';
import 'package:flutter/foundation.dart';

/// How much reading a quote is, which decides how it is set.
enum QuoteLength {
  /// A line: set large.
  short,

  /// A few sentences.
  medium,

  /// A paragraph: set as reading text.
  long,

  /// More than fits anywhere at once.
  epic;

  static QuoteLength of(String text) {
    final length = text.trim().length;
    if (length <= 90) {
      return short;
    }
    if (length <= 240) {
      return medium;
    }
    if (length <= 600) {
      return long;
    }
    return epic;
  }
}

/// One saved quote.
@immutable
class QuoteEntry {
  const QuoteEntry({
    required this.text,
    this.author = '',
    this.source = '',
    this.themes = const [],
    this.favourite = false,
    this.added,
    this.rowId,
  });

  final String text;
  final String author;
  final String source;
  final List<String> themes;
  final bool favourite;
  final DateTime? added;
  final String? rowId;

  QuoteLength get length => QuoteLength.of(text);

  /// The text with the quotation marks somebody pasted along with it removed,
  /// since the card draws its own.
  String get body {
    var value = text.trim();
    const marks = ['"', '“', '”', '«', '»', "'", '‘', '’'];
    while (value.length > 1 &&
        marks.contains(value[0]) &&
        marks.contains(value[value.length - 1])) {
      value = value.substring(1, value.length - 1).trim();
    }
    return value;
  }

  QuoteEntry withFavourite(bool value) => QuoteEntry(
        text: text,
        author: author,
        source: source,
        themes: themes,
        favourite: value,
        added: added,
        rowId: rowId,
      );
}

class QuoteRoles {
  static const text = FinanceRole('textColumn', [
    'quote',
    'quotation',
    'text',
    'saying',
    'words',
    'line',
  ]);
  static const author = FinanceRole('authorColumn', [
    'who said it',
    'author',
    'said by',
    'speaker',
    'by',
    'who',
  ]);
  static const source = FinanceRole('sourceColumn', [
    'where from',
    'source',
    'book',
    'from',
    'work',
    'reference',
  ]);
  static const themes = FinanceRole('themeColumn', [
    'theme',
    'themes',
    'tags',
    'topic',
    'topics',
    'category',
  ]);
  static const favourite = FinanceRole('favouriteColumn', [
    'favourite',
    'favorite',
    'starred',
    'loved',
    'fav',
  ]);
  static const added = FinanceRole('dateColumn', [
    'added',
    'saved',
    'date',
  ]);

  static const all = [author, source, themes, favourite, added, text];
}

/// Every quote a table holds, in its order.
List<QuoteEntry> readQuotes(
  ChartTable table, {
  Map<String, Object?> settings = const {},
}) {
  final columns = FinanceColumns.resolve(
    table,
    QuoteRoles.all,
    settings: settings,
  );
  final sheet = FinanceSheet(table);
  final textColumn = columns.has(QuoteRoles.text) ? columns[QuoteRoles.text] : 0;
  final quotes = <QuoteEntry>[];
  for (var row = 0; row < sheet.length; row++) {
    final text = sheet.text(row, textColumn);
    if (text.isEmpty) {
      continue;
    }
    quotes.add(
      QuoteEntry(
        text: text,
        author: sheet.text(row, columns[QuoteRoles.author]),
        source: sheet.text(row, columns[QuoteRoles.source]),
        themes: sheet.parts(row, columns[QuoteRoles.themes]),
        favourite: sheet.flag(row, columns[QuoteRoles.favourite]),
        added: sheet.date(row, columns[QuoteRoles.added]),
        rowId: sheet.rowId(row),
      ),
    );
  }
  return quotes;
}

/// Which of [count] quotes belongs to [day]. The same day always picks the
/// same quote, consecutive days rarely repeat one, and [salt] lets two cards
/// on one dashboard pick different quotes.
int quoteOfTheDay(int count, DateTime day, {int salt = 0}) {
  if (count <= 0) {
    return -1;
  }
  final days = DateTime.utc(day.year, day.month, day.day)
          .millisecondsSinceEpoch ~/
      Duration.millisecondsPerDay;
  // Walk the list in a fixed shuffled order rather than hashing each day,
  // so every quote comes round once before any comes round twice.
  final cycle = days ~/ count;
  final position = days % count;
  final step = _coprimeStep(count, cycle + salt);
  final offset = _mix(cycle * 31 + salt) % count;
  return (offset + position * step) % count;
}

int _coprimeStep(int count, int seed) {
  if (count <= 2) {
    return 1;
  }
  var step = 1 + _mix(seed) % (count - 1);
  while (_gcd(step, count) != 1) {
    step = step % (count - 1) + 1;
  }
  return step;
}

int _gcd(int a, int b) => b == 0 ? a : _gcd(b, a % b);

int _mix(int value) {
  var x = (value ^ 0x5bd1e995) & 0x7fffffff;
  x = ((x >> 16) ^ x) * 0x45d9f3b & 0x7fffffff;
  x = ((x >> 16) ^ x) * 0x45d9f3b & 0x7fffffff;
  return ((x >> 16) ^ x) & 0x7fffffff;
}
