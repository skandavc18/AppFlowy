import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:flutter/foundation.dart';

/// How much of each row a mailbox line shows.
enum MailboxDensity {
  /// Sender, subject and the opening of the row's page.
  comfortable('comfortable', 74),

  /// Sender and subject on one line.
  compact('compact', 46);

  const MailboxDensity(this.id, this.rowHeight);

  final String id;
  final double rowHeight;

  bool get showsSnippet => this == MailboxDensity.comfortable;

  static MailboxDensity fromId(String? id) {
    for (final density in MailboxDensity.values) {
      if (density.id == id) {
        return density;
      }
    }
    return MailboxDensity.comfortable;
  }
}

/// How a table is read as a mailbox.
///
/// The columns are named by field id rather than by heading, so renaming a
/// column does not lose the arrangement.
@immutable
class MailboxSpec {
  const MailboxSpec({
    this.subjectColumn = '',
    this.senderColumn = '',
    this.dateColumn = '',
    this.snippetColumn = '',
    this.propertyColumns = const [],
    this.hiddenColumns = const [],
    this.density = MailboxDensity.comfortable,
    this.showReader = true,
    this.groupByDate = true,
  });

  /// The line a row is known by. Empty means the table's own primary column.
  final String subjectColumn;

  /// Who the row is from. Empty means the mailbox works it out from a person
  /// column, and falls back to nothing rather than guessing.
  final String senderColumn;

  /// When the row arrived. Empty means the row's own modified time.
  final String dateColumn;

  /// The second line of a row. Empty means the row's own page.
  final String snippetColumn;

  /// The columns worth reading in the open row.
  final List<String> propertyColumns;

  /// Columns the author has taken out of the mailbox.
  final List<String> hiddenColumns;

  final MailboxDensity density;

  /// Whether the open row is read beside the list or in its own page.
  final bool showReader;

  /// Whether the list breaks into Today, Yesterday, and so on.
  final bool groupByDate;

  TableReadSpec get readSpec => TableReadSpec(
        titleColumn: subjectColumn,
        propertyColumns: propertyColumns,
        hiddenColumns: hiddenColumns,
      );

  MailboxSpec copyWith({
    String? subjectColumn,
    String? senderColumn,
    String? dateColumn,
    String? snippetColumn,
    List<String>? propertyColumns,
    List<String>? hiddenColumns,
    MailboxDensity? density,
    bool? showReader,
    bool? groupByDate,
  }) =>
      MailboxSpec(
        subjectColumn: subjectColumn ?? this.subjectColumn,
        senderColumn: senderColumn ?? this.senderColumn,
        dateColumn: dateColumn ?? this.dateColumn,
        snippetColumn: snippetColumn ?? this.snippetColumn,
        propertyColumns: propertyColumns ?? this.propertyColumns,
        hiddenColumns: hiddenColumns ?? this.hiddenColumns,
        density: density ?? this.density,
        showReader: showReader ?? this.showReader,
        groupByDate: groupByDate ?? this.groupByDate,
      );

  Map<String, dynamic> toJson() => {
        if (subjectColumn.isNotEmpty) 'subject': subjectColumn,
        if (senderColumn.isNotEmpty) 'sender': senderColumn,
        if (dateColumn.isNotEmpty) 'date': dateColumn,
        if (snippetColumn.isNotEmpty) 'snippet': snippetColumn,
        if (propertyColumns.isNotEmpty) 'properties': propertyColumns,
        if (hiddenColumns.isNotEmpty) 'hidden': hiddenColumns,
        if (density != MailboxDensity.comfortable) 'density': density.id,
        if (!showReader) 'reader': false,
        if (!groupByDate) 'grouped': false,
      };

  static MailboxSpec fromJson(Map<String, dynamic> values) => MailboxSpec(
        subjectColumn: values['subject'] as String? ?? '',
        senderColumn: values['sender'] as String? ?? '',
        dateColumn: values['date'] as String? ?? '',
        snippetColumn: values['snippet'] as String? ?? '',
        propertyColumns: _strings(values['properties']),
        hiddenColumns: _strings(values['hidden']),
        density: MailboxDensity.fromId(values['density'] as String?),
        showReader: values['reader'] != false,
        groupByDate: values['grouped'] != false,
      );

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  @override
  bool operator ==(Object other) =>
      other is MailboxSpec &&
      other.subjectColumn == subjectColumn &&
      other.senderColumn == senderColumn &&
      other.dateColumn == dateColumn &&
      other.snippetColumn == snippetColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      listEquals(other.hiddenColumns, hiddenColumns) &&
      other.density == density &&
      other.showReader == showReader &&
      other.groupByDate == groupByDate;

  @override
  int get hashCode => Object.hash(
        subjectColumn,
        senderColumn,
        dateColumn,
        snippetColumn,
        Object.hashAll(propertyColumns),
        Object.hashAll(hiddenColumns),
        density,
        showReader,
        groupByDate,
      );
}

/// The band a row falls into when the list is broken up by date.
enum MailboxBand {
  today,
  yesterday,
  thisWeek,
  thisMonth,
  earlier,
  undated,
}

/// One heading and the rows under it.
@immutable
class MailboxSection<T> {
  const MailboxSection({required this.band, required this.rows});

  final MailboxBand band;
  final List<T> rows;
}

/// Breaks a list into the bands a mail client reads by.
///
/// The rows keep the order they arrived in; only the breaks are added, so a
/// mailbox sorted by something other than a date still groups sensibly.
List<MailboxSection<T>> groupMailboxRows<T>(
  List<T> rows, {
  required DateTime? Function(T row) dateOf,
  DateTime? now,
}) {
  final sections = <MailboxSection<T>>[];
  final today = _startOfDay(now ?? DateTime.now());
  for (final row in rows) {
    final band = mailboxBandOf(dateOf(row), today: today);
    if (sections.isNotEmpty && sections.last.band == band) {
      sections.last.rows.add(row);
      continue;
    }
    sections.add(MailboxSection<T>(band: band, rows: <T>[row]));
  }
  return List.unmodifiable(sections);
}

MailboxBand mailboxBandOf(DateTime? when, {required DateTime today}) {
  if (when == null) {
    return MailboxBand.undated;
  }
  final day = _startOfDay(when.toLocal());
  final gap = today.difference(day).inDays;
  if (gap <= 0) {
    return MailboxBand.today;
  }
  if (gap == 1) {
    return MailboxBand.yesterday;
  }
  if (gap < 7) {
    return MailboxBand.thisWeek;
  }
  if (gap < 31) {
    return MailboxBand.thisMonth;
  }
  return MailboxBand.earlier;
}

DateTime _startOfDay(DateTime when) =>
    DateTime(when.year, when.month, when.day);
