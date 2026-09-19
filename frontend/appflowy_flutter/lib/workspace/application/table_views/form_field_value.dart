import 'dart:convert';

import 'package:appflowy/util/time.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:cross_file/cross_file.dart';

/// Form drafts are typed, not a serialization of the display label. A date's
/// time/range, a file's id/url and a relation's row ids must survive editing.
sealed class FormFieldValue {
  const FormFieldValue();

  String get text;
  String get fingerprint;
  bool get isEmpty => text.isEmpty;
}

class FormTextValue extends FormFieldValue {
  const FormTextValue(this.text);

  @override
  final String text;
  @override
  String get fingerprint => text;
}

class FormDateValue extends FormFieldValue {
  const FormDateValue({
    this.start,
    this.end,
    this.includeTime = false,
    this.isRange = false,
    this.reminderId = '',
  });

  factory FormDateValue.fromPB(DateCellDataPB data) => FormDateValue(
        start: data.hasTimestamp()
            ? DateTime.fromMillisecondsSinceEpoch(data.timestamp.toInt() * 1000)
            : null,
        end: data.hasEndTimestamp()
            ? DateTime.fromMillisecondsSinceEpoch(
                data.endTimestamp.toInt() * 1000,
              )
            : null,
        includeTime: data.includeTime,
        isRange: data.isRange,
        reminderId: data.reminderId,
      );

  final DateTime? start;
  final DateTime? end;
  final bool includeTime;
  final bool isRange;
  final String reminderId;

  FormDateValue copyWith({
    DateTime? start,
    DateTime? end,
    bool? includeTime,
    bool? isRange,
  }) =>
      FormDateValue(
        start: start ?? this.start,
        end: end ?? this.end,
        includeTime: includeTime ?? this.includeTime,
        isRange: isRange ?? this.isRange,
        reminderId: reminderId,
      );

  @override
  String get text => start == null
      ? ''
      : '${_format(start!)}${isRange && end != null ? ' → ${_format(end!)}' : ''}';

  String _format(DateTime date) {
    final day = '${date.year}-${_two(date.month)}-${_two(date.day)}';
    return includeTime ? '$day ${_two(date.hour)}:${_two(date.minute)}' : day;
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  @override
  String get fingerprint => jsonEncode([
        start?.millisecondsSinceEpoch,
        end?.millisecondsSinceEpoch,
        includeTime,
        isRange,
        reminderId,
      ]);
}

/// A reminder is scheduled only when its containing draft is saved.
class FormReminderValue extends FormFieldValue {
  const FormReminderValue({
    this.at,
    this.reminderId = '',
    this.includeTime = true,
  });

  factory FormReminderValue.fromText(String text) {
    final parts = text.split('|');
    return FormReminderValue(
      at: DateTime.tryParse(parts.first),
      reminderId: parts.length > 1 ? parts[1] : '',
    );
  }

  final DateTime? at;
  final String reminderId;
  final bool includeTime;

  String get storedText =>
      at == null ? '' : '${at!.toIso8601String()}|$reminderId';
  @override
  String get text => FormDateValue(start: at, includeTime: includeTime).text;
  @override
  String get fingerprint => storedText;
}

/// Local picks are not uploaded or copied into workspace storage until Save.
class FormFileAttachment {
  const FormFileAttachment({required this.file, this.pending});

  final MediaFilePB file;
  final XFile? pending;
}

class FormFilesValue extends FormFieldValue {
  const FormFilesValue(this.files);

  final List<FormFileAttachment> files;

  @override
  String get text => files.map((file) => file.file.name).join(', ');
  @override
  String get fingerprint => jsonEncode([
        for (final file in files)
          [base64Encode(file.file.writeToBuffer()), file.pending?.path],
      ]);
}

class FormChecklistTask {
  const FormChecklistTask({
    required this.id,
    required this.name,
    this.checked = false,
  });
  final String id;
  final String name;
  final bool checked;

  FormChecklistTask copyWith({String? name, bool? checked}) =>
      FormChecklistTask(
        id: id,
        name: name ?? this.name,
        checked: checked ?? this.checked,
      );
}

class FormChecklistValue extends FormFieldValue {
  factory FormChecklistValue.fromPB(ChecklistCellDataPB data) =>
      FormChecklistValue([
        for (final option in data.options)
          FormChecklistTask(
            id: option.id,
            name: option.name,
            checked: data.selectedOptions
                .any((selected) => selected.id == option.id),
          ),
      ]);
  const FormChecklistValue(this.tasks);
  final List<FormChecklistTask> tasks;

  @override
  String get text => tasks
      .map((task) => '${task.checked ? '[x]' : '[ ]'} ${task.name}')
      .join('\n');
  @override
  String get fingerprint => jsonEncode([
        for (final task in tasks) [task.id, task.name, task.checked],
      ]);
}

class FormSelectionValue extends FormFieldValue {
  const FormSelectionValue(this.ids, {this.labels = const {}});
  final List<String> ids;
  final Map<String, String> labels;

  @override
  String get text => ids.map((id) => labels[id] ?? id).join(', ');
  @override
  String get fingerprint => jsonEncode(ids);
}

FormFieldValue emptyFormValue(FieldPB field) => switch (field.fieldType) {
      FieldType.DateTime => const FormDateValue(),
      FieldType.Media => const FormFilesValue([]),
      FieldType.Checklist => const FormChecklistValue([]),
      FieldType.SingleSelect ||
      FieldType.MultiSelect ||
      FieldType.Relation =>
        const FormSelectionValue([]),
      _ => const FormTextValue(''),
    };

FormFieldValue decodeFormCell(FieldPB field, List<int> bytes) {
  if (bytes.isEmpty) return emptyFormValue(field);
  switch (field.fieldType) {
    case FieldType.DateTime:
      return FormDateValue.fromPB(DateCellDataPB.fromBuffer(bytes));
    case FieldType.Media:
      return FormFilesValue([
        for (final file in MediaCellDataPB.fromBuffer(bytes).files)
          FormFileAttachment(file: file),
      ]);
    case FieldType.Checklist:
      return FormChecklistValue.fromPB(ChecklistCellDataPB.fromBuffer(bytes));
    case FieldType.Relation:
      return FormSelectionValue(
        RelationCellDataPB.fromBuffer(bytes).rowIds.toList(),
      );
    case FieldType.SingleSelect:
    case FieldType.MultiSelect:
      final options = SelectOptionCellDataPB.fromBuffer(bytes).selectOptions;
      return FormSelectionValue(
        options.map((option) => option.id).toList(),
        labels: {for (final option in options) option.id: option.name},
      );
    case FieldType.Checkbox:
      return FormTextValue(
        CheckboxCellDataPB.fromBuffer(bytes).isChecked ? 'Yes' : 'No',
      );
    case FieldType.Time:
      return FormTextValue(
        formatTime(TimeCellDataPB.fromBuffer(bytes).time.toInt()),
      );
    case FieldType.URL:
      return FormTextValue(URLCellDataPB.fromBuffer(bytes).content);
    default:
      return FormTextValue(utf8.decode(bytes));
  }
}
