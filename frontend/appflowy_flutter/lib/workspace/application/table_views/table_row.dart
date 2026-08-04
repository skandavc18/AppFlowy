import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/foundation.dart';

/// How one column of a row should be read, whichever view is reading it.
///
/// Every view of a table — slides, a timeline, a feed, a form, a gallery —
/// faces the same question: what shape does this column deserve? Answering it
/// once, here, is what makes those views siblings rather than lookalikes, and
/// keeps the decision testable without drawing anything.
enum TablePropertyKind {
  text,
  excerpt,
  number,
  progress,
  checkbox,
  badge,
  tags,
  date,
  person,
  image,
  files,
  location,
  relation,
  link,
  rating,
}

/// Headings that name a person rather than a thing.
const _peopleWords = [
  'assignee',
  'assigned',
  'owner',
  'person',
  'people',
  'author',
  'lead',
  'manager',
  'contact',
  'reviewer',
  'member',
  'who',
];

/// Headings that name a fraction of something finished.
const _progressWords = [
  'progress',
  'completion',
  'complete',
  'percent',
  'done',
];

/// Headings that name a score out of something.
const _ratingWords = [
  'rating',
  'stars',
  'score',
  'rank',
  'priority',
];

/// Headings that usually hold when something happens.
const _startWords = ['start', 'begin', 'from', 'opened', 'created'];
const _endWords = ['end', 'due', 'finish', 'to', 'deadline', 'closed'];

const _imageExtensions = [
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.bmp',
  '.heic',
  '.avif',
];

/// One column of one row, ready to be drawn.
@immutable
class TableProperty {
  const TableProperty({
    required this.fieldId,
    required this.name,
    required this.value,
    required this.kind,
    this.fraction,
    this.rating,
  });

  final String fieldId;
  final String name;
  final String value;
  final TablePropertyKind kind;

  /// How full a bar should be, when the kind is a progress.
  final double? fraction;

  /// How many marks are filled, when the kind is a rating.
  final int? rating;

  bool get isEmpty => value.trim().isEmpty;

  /// Whether the shape wants a whole row to itself.
  bool get isWide => const [
        TablePropertyKind.excerpt,
        TablePropertyKind.image,
        TablePropertyKind.location,
        TablePropertyKind.files,
        TablePropertyKind.relation,
        TablePropertyKind.progress,
      ].contains(kind);

  @override
  bool operator ==(Object other) =>
      other is TableProperty &&
      other.fieldId == fieldId &&
      other.name == name &&
      other.value == value &&
      other.kind == kind &&
      other.fraction == fraction &&
      other.rating == rating;

  @override
  int get hashCode => Object.hash(fieldId, name, value, kind, fraction, rating);
}

/// What a row's cover is made of.
enum TableCoverKind { picture, asset, colour, gradient }

/// The cover a row wears, whatever it is made of.
///
/// The row page draws colours and gradients as well as pictures, so a card
/// that only understood a URL could never show the same thing.
@immutable
class TableCover {
  const TableCover({required this.kind, required this.value});

  final TableCoverKind kind;
  final String value;

  @override
  bool operator ==(Object other) =>
      other is TableCover && other.kind == kind && other.value == value;

  @override
  int get hashCode => Object.hash(kind, value);
}

/// One row, ready to be drawn.
@immutable
class TableRowCard {
  const TableRowCard({
    required this.rowId,
    required this.title,
    this.subtitle = '',
    this.icon,
    this.coverUrl,
    this.cover,
    this.documentId = '',
    this.accent = '',
    this.properties = const [],
    this.lastModified,
    this.startsAt,
    this.endsAt,
  });

  final String rowId;
  final String title;
  final String subtitle;

  /// The row's own emoji, when it has one.
  final String? icon;

  /// A picture to stand behind the row's head.
  final String? coverUrl;

  /// The cover the row page would show, picture or not.
  final TableCover? cover;

  /// The page behind the row, for a view that wants to look inside it.
  final String documentId;

  /// The value that decides the row's colour, usually a status.
  final String accent;

  final List<TableProperty> properties;
  final DateTime? lastModified;

  /// When the row happens, for the views that place it in time.
  final DateTime? startsAt;
  final DateTime? endsAt;

  /// Whether the row occupies a stretch of time rather than a moment.
  bool get spansTime =>
      startsAt != null && endsAt != null && endsAt!.isAfter(startsAt!);

  /// Whether the row is a point in time — a milestone.
  bool get isMilestone => startsAt != null && !spansTime;

  /// The properties that hold something.
  List<TableProperty> get filled =>
      properties.where((property) => !property.isEmpty).toList();

  TableProperty? propertyOf(String fieldId) {
    for (final property in properties) {
      if (property.fieldId == fieldId) {
        return property;
      }
    }
    return null;
  }
}

/// What a column looks like across the whole table.
///
/// A single cell cannot say whether 42 is nearly finished or barely started;
/// the column can.
@immutable
class TableColumnFacts {
  const TableColumnFacts({this.lowest, this.highest});

  final double? lowest;
  final double? highest;

  bool get hasRange => lowest != null && highest != null && highest! > lowest!;
}

/// Works out how a cell should be read.
TablePropertyKind classifyTableProperty({
  required FieldPB field,
  required String value,
  bool isLocation = false,
  TableColumnFacts facts = const TableColumnFacts(),
}) {
  if (isLocation) {
    return TablePropertyKind.location;
  }
  final heading = field.name.toLowerCase();
  final trimmed = value.trim();

  switch (field.fieldType) {
    case FieldType.Checkbox:
      return TablePropertyKind.checkbox;
    case FieldType.SingleSelect:
      return TablePropertyKind.badge;
    case FieldType.MultiSelect:
      return _namesAPerson(heading)
          ? TablePropertyKind.person
          : TablePropertyKind.tags;
    case FieldType.Checklist:
      return TablePropertyKind.progress;
    case FieldType.DateTime:
    case FieldType.CreatedTime:
    case FieldType.LastEditedTime:
      return TablePropertyKind.date;
    case FieldType.Number:
      if (_namesRating(heading)) {
        return TablePropertyKind.rating;
      }
      if (_namesProgress(heading) || trimmed.endsWith('%') || facts.hasRange) {
        return TablePropertyKind.progress;
      }
      return TablePropertyKind.number;
    case FieldType.URL:
      return looksLikeTableImage(trimmed)
          ? TablePropertyKind.image
          : TablePropertyKind.link;
    case FieldType.Media:
      return trimmed.split(',').any(looksLikeTableImage)
          ? TablePropertyKind.image
          : TablePropertyKind.files;
    case FieldType.Relation:
      return TablePropertyKind.relation;
    default:
      break;
  }

  if (_namesAPerson(heading)) {
    return TablePropertyKind.person;
  }
  if (looksLikeTableImage(trimmed)) {
    return TablePropertyKind.image;
  }
  if (trimmed.contains('\n') || trimmed.length > 90) {
    return TablePropertyKind.excerpt;
  }
  return TablePropertyKind.text;
}

/// How full a bar should be for a cell, if it can be worked out.
double? tableFractionOf({
  required FieldPB field,
  required String value,
  TableColumnFacts facts = const TableColumnFacts(),
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (field.fieldType == FieldType.Checklist) {
    return tableRatioOf(trimmed);
  }
  if (trimmed.endsWith('%')) {
    final percent = double.tryParse(trimmed.substring(0, trimmed.length - 1));
    return percent == null ? null : (percent / 100).clamp(0.0, 1.0);
  }
  final number = double.tryParse(trimmed.replaceAll(',', ''));
  if (number == null) {
    return null;
  }
  if (facts.hasRange) {
    final span = facts.highest! - facts.lowest!;
    return ((number - facts.lowest!) / span).clamp(0.0, 1.0);
  }
  // Without a range to compare against, a bare number can only be read as a
  // percentage, and only when it could plausibly be one.
  if (number >= 0 && number <= 1) {
    return number;
  }
  if (number > 1 && number <= 100) {
    return number / 100;
  }
  return null;
}

/// How many marks a rating fills, out of five.
int? tableRatingOf(String value) {
  final number = double.tryParse(value.trim().replaceAll(',', ''));
  if (number == null) {
    return null;
  }
  // A score out of ten is halved rather than clipped, so nine reads as high
  // rather than as full.
  final outOfFive = number > 5 ? number / 2 : number;
  return outOfFive.round().clamp(0, 5);
}

/// Reads "3/8" as a fraction.
double? tableRatioOf(String value) {
  final parts = value.split('/');
  if (parts.length != 2) {
    return null;
  }
  final done = double.tryParse(parts.first.trim());
  final total = double.tryParse(parts.last.trim());
  if (done == null || total == null || total <= 0) {
    return null;
  }
  return (done / total).clamp(0.0, 1.0);
}

/// Whether a cell holds a picture rather than words.
bool looksLikeTableImage(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return false;
  }
  final withoutQuery = trimmed.split('?').first;
  return _imageExtensions.any(withoutQuery.endsWith);
}

/// The comma separated parts of a cell, with the blanks dropped.
List<String> tablePartsOf(String value) => value
    .split(',')
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList();

/// The letters that stand in for somebody with no picture.
String tableInitialsOf(String name) {
  final words = name
      .trim()
      .split(RegExp(r'[\s._-]+'))
      .where((word) => word.isNotEmpty)
      .toList();
  if (words.isEmpty) {
    return '?';
  }
  if (words.length == 1) {
    final word = words.first;
    return word.substring(0, word.length < 2 ? word.length : 2).toUpperCase();
  }
  return (words.first.substring(0, 1) + words[1].substring(0, 1)).toUpperCase();
}

/// Reads whatever a date column shows.
///
/// The backend hands dates over already written for the reader, so this has to
/// cope with what a person sees rather than with one machine format.
DateTime? parseTableDate(String value) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  // A range reads as its beginning; the end is a column of its own.
  final firstPart = trimmed.split(RegExp(r'\s*(?:→|->|–|—)\s*')).first.trim();
  final direct = DateTime.tryParse(firstPart);
  if (direct != null) {
    return direct;
  }
  final slashed = RegExp(r'^(\d{1,4})[/.-](\d{1,2})[/.-](\d{1,4})');
  final match = slashed.firstMatch(firstPart);
  if (match != null) {
    final first = int.parse(match.group(1)!);
    final second = int.parse(match.group(2)!);
    final third = int.parse(match.group(3)!);
    // A four digit part names the year wherever it sits.
    if (first > 31) {
      return DateTime(first, second, third);
    }
    if (third > 31) {
      // Day and month cannot be told apart below thirteen, and the application
      // writes month first, so that is what is read back.
      return DateTime(third, first, second);
    }
    return null;
  }
  return _parseWrittenDate(firstPart);
}

/// Reads a date written the way a person writes one — "Aug 04, 2026".
///
/// This is the shape the application's own date columns are formatted in, so
/// without it a table full of dates reads as a table with none.
DateTime? _parseWrittenDate(String value) {
  final match = RegExp(
    r'^(?:(\d{1,2})\s+)?([A-Za-z]{3,})\.?\s+(?:(\d{1,2})[,]?\s+)?(\d{4})',
  ).firstMatch(value);
  if (match == null) {
    return null;
  }
  final month = _monthNumber(match.group(2)!);
  if (month == null) {
    return null;
  }
  final day = int.tryParse(match.group(1) ?? match.group(3) ?? '1') ?? 1;
  final year = int.parse(match.group(4)!);
  if (day < 1 || day > 31) {
    return null;
  }
  final time = RegExp(r'(\d{1,2}):(\d{2})(?:\s*([AaPp])\.?[Mm])?').firstMatch(
    value.substring(match.end),
  );
  if (time == null) {
    return DateTime(year, month, day);
  }
  var hour = int.parse(time.group(1)!);
  final half = time.group(3)?.toLowerCase();
  if (half == 'p' && hour < 12) {
    hour += 12;
  } else if (half == 'a' && hour == 12) {
    hour = 0;
  }
  return DateTime(year, month, day, hour, int.parse(time.group(2)!));
}

const _monthNames = [
  'january',
  'february',
  'march',
  'april',
  'may',
  'june',
  'july',
  'august',
  'september',
  'october',
  'november',
  'december',
];

int? _monthNumber(String word) {
  final name = word.toLowerCase();
  for (var i = 0; i < _monthNames.length; i++) {
    if (_monthNames[i].startsWith(name) || name.startsWith(_monthNames[i])) {
      return i + 1;
    }
  }
  return null;
}

/// The column most likely to say when a row begins.
String? guessStartColumn(List<FieldPB> fields) =>
    _guessDateColumn(fields, _startWords) ?? _firstDateColumn(fields);

/// The column most likely to say when a row ends.
String? guessEndColumn(List<FieldPB> fields, {String? notThis}) {
  final guessed = _guessDateColumn(fields, _endWords);
  if (guessed != null && guessed != notThis) {
    return guessed;
  }
  for (final field in fields) {
    if (_isDateField(field) && field.id != notThis) {
      return field.id;
    }
  }
  return null;
}

String? _guessDateColumn(List<FieldPB> fields, List<String> words) {
  for (final field in fields) {
    if (!_isDateField(field)) {
      continue;
    }
    final heading = field.name.toLowerCase();
    if (words.any(heading.contains)) {
      return field.id;
    }
  }
  return null;
}

String? _firstDateColumn(List<FieldPB> fields) {
  for (final field in fields) {
    if (_isDateField(field)) {
      return field.id;
    }
  }
  return null;
}

/// Whether a column holds a moment in time.
bool isTableDateField(FieldPB field) => const [
      FieldType.DateTime,
      FieldType.CreatedTime,
      FieldType.LastEditedTime,
    ].contains(field.fieldType);

bool _isDateField(FieldPB field) => isTableDateField(field);

bool _namesAPerson(String heading) => _peopleWords.any(heading.contains);

bool _namesProgress(String heading) => _progressWords.any(heading.contains);

bool _namesRating(String heading) => _ratingWords.any(heading.contains);
