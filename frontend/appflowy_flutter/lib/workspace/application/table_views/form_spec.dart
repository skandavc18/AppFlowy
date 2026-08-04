import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/foundation.dart';

/// A run of fields gathered under a heading.
@immutable
class FormSection {
  const FormSection({
    required this.id,
    this.title = '',
    this.description = '',
    this.fieldIds = const [],
    this.collapsed = false,
  });

  final String id;
  final String title;
  final String description;
  final List<String> fieldIds;
  final bool collapsed;

  FormSection copyWith({
    String? title,
    String? description,
    List<String>? fieldIds,
    bool? collapsed,
  }) =>
      FormSection(
        id: id,
        title: title ?? this.title,
        description: description ?? this.description,
        fieldIds: fieldIds ?? this.fieldIds,
        collapsed: collapsed ?? this.collapsed,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        if (title.isNotEmpty) 'title': title,
        if (description.isNotEmpty) 'description': description,
        if (fieldIds.isNotEmpty) 'fields': fieldIds,
        if (collapsed) 'collapsed': true,
      };

  static FormSection? fromJson(Map<String, dynamic> values) {
    final id = values['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return FormSection(
      id: id,
      title: values['title'] as String? ?? '',
      description: values['description'] as String? ?? '',
      fieldIds: values['fields'] is List
          ? List<String>.unmodifiable(
              (values['fields'] as List).whereType<String>(),
            )
          : const [],
      collapsed: values['collapsed'] == true,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is FormSection &&
      other.id == id &&
      other.title == title &&
      other.description == description &&
      listEquals(other.fieldIds, fieldIds) &&
      other.collapsed == collapsed;

  @override
  int get hashCode =>
      Object.hash(id, title, description, Object.hashAll(fieldIds), collapsed);
}

/// How a table is offered as a form.
@immutable
class FormSpec {
  const FormSpec({
    this.heading = '',
    this.description = '',
    this.sections = const [],
    this.requiredColumns = const [],
    this.hiddenColumns = const [],
    this.descriptions = const {},
  });

  final String heading;
  final String description;

  /// The sections, in order. Empty means one section holding every column.
  final List<FormSection> sections;

  final List<String> requiredColumns;
  final List<String> hiddenColumns;

  /// The note under a field, keyed by field id.
  final Map<String, String> descriptions;

  bool isRequired(String fieldId) => requiredColumns.contains(fieldId);

  bool isHidden(String fieldId) => hiddenColumns.contains(fieldId);

  String descriptionOf(String fieldId) => descriptions[fieldId] ?? '';

  FormSpec copyWith({
    String? heading,
    String? description,
    List<FormSection>? sections,
    List<String>? requiredColumns,
    List<String>? hiddenColumns,
    Map<String, String>? descriptions,
  }) =>
      FormSpec(
        heading: heading ?? this.heading,
        description: description ?? this.description,
        sections: sections ?? this.sections,
        requiredColumns: requiredColumns ?? this.requiredColumns,
        hiddenColumns: hiddenColumns ?? this.hiddenColumns,
        descriptions: descriptions ?? this.descriptions,
      );

  FormSpec withRequired(String fieldId, bool required) {
    final next = [...requiredColumns]..remove(fieldId);
    if (required) {
      next.add(fieldId);
    }
    return copyWith(requiredColumns: next);
  }

  FormSpec withHidden(String fieldId, bool hidden) {
    final next = [...hiddenColumns]..remove(fieldId);
    if (hidden) {
      next.add(fieldId);
    }
    return copyWith(hiddenColumns: next);
  }

  Map<String, dynamic> toJson() => {
        if (heading.isNotEmpty) 'heading': heading,
        if (description.isNotEmpty) 'description': description,
        if (sections.isNotEmpty)
          'sections': [for (final section in sections) section.toJson()],
        if (requiredColumns.isNotEmpty) 'required': requiredColumns,
        if (hiddenColumns.isNotEmpty) 'hidden': hiddenColumns,
        if (descriptions.isNotEmpty) 'notes': descriptions,
      };

  static FormSpec fromJson(Map<String, dynamic> values) => FormSpec(
        heading: values['heading'] as String? ?? '',
        description: values['description'] as String? ?? '',
        sections: values['sections'] is List
            ? List<FormSection>.unmodifiable(
                (values['sections'] as List)
                    .whereType<Map>()
                    .map(
                      (raw) =>
                          FormSection.fromJson(Map<String, dynamic>.from(raw)),
                    )
                    .whereType<FormSection>(),
              )
            : const [],
        requiredColumns: _strings(values['required']),
        hiddenColumns: _strings(values['hidden']),
        descriptions: values['notes'] is Map
            ? Map<String, String>.unmodifiable({
                for (final entry in (values['notes'] as Map).entries)
                  if (entry.value is String)
                    '${entry.key}': entry.value as String,
              })
            : const {},
      );

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  @override
  bool operator ==(Object other) =>
      other is FormSpec &&
      other.heading == heading &&
      other.description == description &&
      listEquals(other.sections, sections) &&
      listEquals(other.requiredColumns, requiredColumns) &&
      listEquals(other.hiddenColumns, hiddenColumns) &&
      mapEquals(other.descriptions, descriptions);

  @override
  int get hashCode => Object.hash(
        heading,
        description,
        Object.hashAll(sections),
        Object.hashAll(requiredColumns),
        Object.hashAll(hiddenColumns),
        Object.hashAll(descriptions.entries.map((e) => '${e.key}=${e.value}')),
      );
}

/// What a field is asked for with.
enum FormControl {
  line,
  paragraph,
  number,
  date,
  choice,
  tags,
  toggle,
  rating,
  people,
  link,
  files,
  place,
  relation,
}

/// The control a column deserves on a form.
///
/// A form is where a row is made rather than read, so this asks a different
/// question from the one the cards ask: not "what does this value look like"
/// but "how would somebody type it".
FormControl formControlOf(FieldPB field, {bool isLocation = false}) {
  if (isLocation) {
    return FormControl.place;
  }
  final heading = field.name.toLowerCase();
  switch (field.fieldType) {
    case FieldType.Checkbox:
      return FormControl.toggle;
    case FieldType.SingleSelect:
      return FormControl.choice;
    case FieldType.MultiSelect:
      return _namesAPerson(heading) ? FormControl.people : FormControl.tags;
    case FieldType.DateTime:
    case FieldType.CreatedTime:
    case FieldType.LastEditedTime:
      return FormControl.date;
    case FieldType.Number:
      return _namesARating(heading) ? FormControl.rating : FormControl.number;
    case FieldType.URL:
      return FormControl.link;
    case FieldType.Media:
      return FormControl.files;
    case FieldType.Relation:
      return FormControl.relation;
    case FieldType.Checklist:
      return FormControl.paragraph;
    default:
      break;
  }
  if (_namesAPerson(heading)) {
    return FormControl.people;
  }
  if (_namesAPlace(heading)) {
    return FormControl.place;
  }
  if (_namesProse(heading)) {
    return FormControl.paragraph;
  }
  return FormControl.line;
}

/// Whether a field can be filled in from a form at all.
///
/// A column the table works out for itself cannot be typed into, and offering
/// it would be a lie.
bool isFormFillable(FieldPB field) =>
    const [
      FieldType.CreatedTime,
      FieldType.LastEditedTime,
    ].contains(field.fieldType) ==
    false;

/// Which fields a form asks for, in order.
List<FieldPB> formFieldsOf(List<FieldPB> fields, FormSpec spec) => fields
    .where((field) => isFormFillable(field) && !spec.isHidden(field.id))
    .toList(growable: false);

/// The sections a form is laid out in, filling in the one implicit section
/// when the author has not made any.
List<FormSection> formSectionsOf(List<FieldPB> fields, FormSpec spec) {
  final available = formFieldsOf(fields, spec).map((field) => field.id).toSet();
  if (spec.sections.isEmpty) {
    return [
      FormSection(id: 'all', fieldIds: available.toList(growable: false)),
    ];
  }
  final placed = <String>{};
  final sections = <FormSection>[];
  for (final section in spec.sections) {
    final ids = section.fieldIds.where(available.contains).toList();
    placed.addAll(ids);
    sections.add(section.copyWith(fieldIds: ids));
  }
  // A column added to the table after the form was laid out still has to be
  // askable, so it joins the last section rather than disappearing.
  final left = available.where((id) => !placed.contains(id)).toList();
  if (left.isEmpty) {
    return sections;
  }
  if (sections.isEmpty) {
    return [FormSection(id: 'all', fieldIds: left)];
  }
  final last = sections.removeLast();
  sections.add(last.copyWith(fieldIds: [...last.fieldIds, ...left]));
  return sections;
}

/// The fields that were asked for and left blank.
List<String> missingRequiredFields(
  FormSpec spec,
  Map<String, String> answers,
) =>
    [
      for (final fieldId in spec.requiredColumns)
        if ((answers[fieldId] ?? '').trim().isEmpty) fieldId,
    ];

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

const _ratingWords = ['rating', 'stars', 'score', 'rank', 'priority'];

const _placeWords = [
  'location',
  'address',
  'place',
  'where',
  'city',
  'venue',
];

const _proseWords = [
  'note',
  'notes',
  'description',
  'summary',
  'detail',
  'details',
  'body',
  'comment',
  'about',
  'why',
];

bool _namesAPerson(String heading) => _peopleWords.any(heading.contains);

bool _namesARating(String heading) => _ratingWords.any(heading.contains);

bool _namesAPlace(String heading) => _placeWords.any(heading.contains);

bool _namesProse(String heading) => _proseWords.any(heading.contains);
