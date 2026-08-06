import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/foundation.dart';

/// How one column of a row should be read on a slide.
///
/// A slide is meant to be looked at rather than scanned, so a column earns a
/// shape rather than a cell: a number is a number, a status is a badge, a
/// place is a small map. The kind is worked out once, here, so the widgets
/// stay dumb and the decision stays testable.
enum SlidePropertyKind {
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
  'score',
  'done',
];

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
class SlideProperty {
  const SlideProperty({
    required this.fieldId,
    required this.name,
    required this.value,
    required this.kind,
    this.fraction,
  });

  final String fieldId;
  final String name;
  final String value;
  final SlidePropertyKind kind;

  /// How full a progress bar should be, when the kind is a progress.
  final double? fraction;

  bool get isEmpty => value.trim().isEmpty;

  /// Whether the shape wants a whole row of the slide to itself.
  bool get isWide => const [
        SlidePropertyKind.excerpt,
        SlidePropertyKind.image,
        SlidePropertyKind.location,
        SlidePropertyKind.files,
        SlidePropertyKind.relation,
        SlidePropertyKind.progress,
      ].contains(kind);

  @override
  bool operator ==(Object other) =>
      other is SlideProperty &&
      other.fieldId == fieldId &&
      other.name == name &&
      other.value == value &&
      other.kind == kind &&
      other.fraction == fraction;

  @override
  int get hashCode => Object.hash(fieldId, name, value, kind, fraction);
}

/// One row, ready to be drawn.
@immutable
class SlideCardData {
  const SlideCardData({
    required this.rowId,
    required this.title,
    this.subtitle = '',
    this.icon,
    this.coverUrl,
    this.documentId = '',
    this.accent = '',
    this.properties = const [],
    this.lastModified,
  });

  final String rowId;
  final String title;
  final String subtitle;

  /// The row's own emoji, when it has one.
  final String? icon;

  /// A picture to stand behind the slide's head.
  final String? coverUrl;

  /// The row's own page, which holds whatever does not fit in a column.
  final String documentId;

  /// The value that decides the slide's colour, usually a status.
  final String accent;

  final List<SlideProperty> properties;
  final DateTime? lastModified;

  /// The properties that hold something.
  List<SlideProperty> get filled =>
      properties.where((property) => !property.isEmpty).toList();
}

/// What a column looks like across the whole table.
///
/// A single cell cannot say whether 42 is nearly finished or barely started;
/// the column can.
@immutable
class SlideColumnFacts {
  const SlideColumnFacts({this.lowest, this.highest});

  final double? lowest;
  final double? highest;

  bool get hasRange => lowest != null && highest != null && highest! > lowest!;
}

/// Works out how a cell should be read.
SlidePropertyKind classifySlideProperty({
  required FieldPB field,
  required String value,
  bool isLocation = false,
  SlideColumnFacts facts = const SlideColumnFacts(),
}) {
  if (isLocation) {
    return SlidePropertyKind.location;
  }
  final heading = field.name.toLowerCase();
  final trimmed = value.trim();

  switch (field.fieldType) {
    case FieldType.Checkbox:
      return SlidePropertyKind.checkbox;
    case FieldType.SingleSelect:
      return SlidePropertyKind.badge;
    case FieldType.MultiSelect:
      return _namesAPerson(heading)
          ? SlidePropertyKind.person
          : SlidePropertyKind.tags;
    case FieldType.Checklist:
      return SlidePropertyKind.progress;
    case FieldType.DateTime:
    case FieldType.CreatedTime:
    case FieldType.LastEditedTime:
      return SlidePropertyKind.date;
    case FieldType.Number:
      if (_namesProgress(heading) || trimmed.endsWith('%') || facts.hasRange) {
        return SlidePropertyKind.progress;
      }
      return SlidePropertyKind.number;
    case FieldType.URL:
      return looksLikeSlideImage(trimmed)
          ? SlidePropertyKind.image
          : SlidePropertyKind.link;
    case FieldType.Media:
      return trimmed.split(',').any(looksLikeSlideImage)
          ? SlidePropertyKind.image
          : SlidePropertyKind.files;
    case FieldType.Relation:
      return SlidePropertyKind.relation;
    default:
      break;
  }

  if (_namesAPerson(heading)) {
    return SlidePropertyKind.person;
  }
  if (looksLikeSlideImage(trimmed)) {
    return SlidePropertyKind.image;
  }
  if (trimmed.contains('\n') || trimmed.length > 90) {
    return SlidePropertyKind.excerpt;
  }
  return SlidePropertyKind.text;
}

/// How full a progress bar should be for a cell, if it can be worked out.
double? slideFractionOf({
  required FieldPB field,
  required String value,
  SlideColumnFacts facts = const SlideColumnFacts(),
}) {
  final trimmed = value.trim();
  if (trimmed.isEmpty) {
    return null;
  }
  if (field.fieldType == FieldType.Checklist) {
    return slideRatioOf(trimmed);
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

/// Reads "3/8" as a fraction.
double? slideRatioOf(String value) {
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
bool looksLikeSlideImage(String value) {
  final trimmed = value.trim().toLowerCase();
  if (trimmed.isEmpty) {
    return false;
  }
  final withoutQuery = trimmed.split('?').first;
  return _imageExtensions.any(withoutQuery.endsWith);
}

/// The comma separated parts of a cell, with the blanks dropped.
List<String> slidePartsOf(String value) => value
    .split(',')
    .map((part) => part.trim())
    .where((part) => part.isNotEmpty)
    .toList();

/// The letters that stand in for somebody with no picture.
String slideInitialsOf(String name) {
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

bool _namesAPerson(String heading) => _peopleWords.any(heading.contains);

bool _namesProgress(String heading) => _progressWords.any(heading.contains);
