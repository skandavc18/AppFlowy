import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/cell_service.dart';
import 'package:appflowy/plugins/database/domain/date_cell_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/database/domain/location_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/user/application/reminder/reminder_service.dart';
import 'package:appflowy/user/application/reminder/reminder_extension.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/util/time.dart';
import 'package:appflowy/workspace/application/encryption/encrypted_column.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/form_field_value.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/reminder.pb.dart';
import 'package:fixnum/fixnum.dart';

/// Deliberately carries no backend response or field value: errors may be
/// displayed, and a backend refusal can contain the submitted secret.
class FormEntryException implements Exception {
  const FormEntryException(this.code, {this.partialRowId});

  final String code;
  final String? partialRowId;

  @override
  String toString() => 'FormEntryException: $code';
}

/// The persistence boundary is injectable so real form behaviour can be tested
/// without opening or changing the user's workspace.
class FormEntryBackend {
  const FormEntryBackend();

  Future<FormFieldValue> readValue(
    String viewId,
    String rowId,
    FieldPB field,
  ) async {
    final cell = _require(
      await CellBackendService.getCell(
        viewId: viewId,
        cellContext: CellContext(fieldId: field.id, rowId: rowId),
      ),
    );
    final value = decodeFormCell(field, cell.data);
    return field.fieldType == FieldType.RichText &&
            PropertyStyleRegistry.instance
                    .cellStyleFor(viewId, field.id, rowId)
                    ?.kind ==
                PropertyStyleKind.reminder
        ? FormReminderValue.fromText(value.text)
        : value;
  }

  Future<Map<String, String>> relatedRows(FieldPB field) async {
    final databaseId =
        RelationTypeOptionPB.fromBuffer(field.typeOptionData).databaseId;
    if (databaseId.isEmpty) return const {};
    final rows = _require(
      await DatabaseEventGetRelatedDatabaseRows(
        DatabaseIdPB(value: databaseId),
      ).send(),
    );
    return {for (final row in rows.rows) row.rowId: row.name};
  }

  Future<void> configureField(
    String viewId,
    String fieldId,
    FormCustomFieldKind kind,
  ) async {
    if (kind == FormCustomFieldKind.location) {
      _require(
        await LocationBackendService.setLocationField(
          viewId: viewId,
          fieldId: fieldId,
          enabled: true,
        ),
      );
      await LocationFieldRegistry.instance.refresh(viewId);
    }
    final style = switch (kind) {
      FormCustomFieldKind.button => PropertyStyleKind.button,
      FormCustomFieldKind.counter => PropertyStyleKind.counter,
      FormCustomFieldKind.progress => PropertyStyleKind.progress,
      _ => null,
    };
    if (style != null) {
      await PropertyStyleRegistry.instance.setStyle(
        viewId: viewId,
        fieldId: fieldId,
        style: PropertyStyle(kind: style),
      );
    }
  }

  Future<void> writeValue(
    String viewId,
    String rowId,
    FieldPB field,
    FormFieldValue value, {
    FormFieldValue? previous,
  }) async {
    final cellId = CellIdPB(viewId: viewId, rowId: rowId, fieldId: field.id);
    switch (value) {
      case FormTextValue():
        final text = field.fieldType == FieldType.Time && value.text.isNotEmpty
            ? parseTime(value.text)?.toString()
            : value.text;
        if (text == null) throw const FormEntryException('invalidTime');
        await writeCell(viewId, rowId, field, text);
      case FormDateValue():
        // Preserve the same reminder and its offset from the event. Do not
        // silently move a timed event to midnight or turn a range into a day.
        final old =
            previous is FormDateValue ? previous : const FormDateValue();
        final reminders = const ReminderService();
        final all = old.reminderId.isEmpty
            ? null
            : _require(await reminders.fetchReminders());
        final matching = all?.where((r) => r.id == old.reminderId);
        final reminder = matching?.isNotEmpty == true ? matching!.first : null;
        _require(
          await DatabaseEventUpdateDateCell(formDateChangeset(cellId, value))
              .send(),
        );
        if (reminder != null) {
          if (value.start == null) {
            _require(await reminders.removeReminder(reminderId: reminder.id));
          } else if (old.start != null) {
            final next = reminder.createEmptyInstance()
              ..mergeFromMessage(reminder);
            next.scheduledAt = reminder.scheduledAt +
                Int64(value.start!.difference(old.start!).inSeconds);
            _require(await reminders.updateReminder(reminder: next));
          }
        }
      case FormFilesValue():
        final files = <MediaFilePB>[];
        for (final attachment in value.files) {
          files.add(await storeAttachment(rowId, attachment));
        }
        _require(
          await DatabaseEventUpdateMediaCell(
            MediaCellChangesetPB(
              viewId: viewId,
              cellId: cellId,
              insertedFiles: files,
              removedIds: previous is FormFilesValue
                  ? previous.files.map((f) => f.file.id)
                  : const [],
            ),
          ).send(),
        );
      case FormSelectionValue():
        final oldIds =
            previous is FormSelectionValue ? previous.ids : const <String>[];
        if (field.fieldType == FieldType.Relation) {
          _require(
            await DatabaseEventUpdateRelationCell(
              RelationCellChangesetPB(
                viewId: viewId,
                cellId: cellId,
                insertedRowIds: value.ids.where((id) => !oldIds.contains(id)),
                removedRowIds: oldIds.where((id) => !value.ids.contains(id)),
              ),
            ).send(),
          );
        } else {
          _require(
            await DatabaseEventUpdateSelectOptionCell(
              SelectOptionCellChangesetPB(
                cellIdentifier: cellId,
                insertOptionIds: value.ids,
                deleteOptionIds: oldIds.where((id) => !value.ids.contains(id)),
              ),
            ).send(),
          );
        }
      case FormChecklistValue():
        final old = previous is FormChecklistValue
            ? previous
            : const FormChecklistValue([]);
        _require(
          await DatabaseEventUpdateChecklistCell(
            formChecklistChangeset(cellId, old, value),
          ).send(),
        );
        // Insert PBs deliberately have no 'completed' field. Read the actual
        // minted ids before toggling only NEW tasks that were checked in draft.
        final newTasks =
            value.tasks.where((task) => task.id.startsWith('draft:')).toList();
        if (newTasks.any((task) => task.checked)) {
          final read =
              await readValue(viewId, rowId, field) as FormChecklistValue;
          final oldIds = old.tasks.map((task) => task.id).toSet();
          final inserted =
              read.tasks.where((task) => !oldIds.contains(task.id)).toList();
          if (inserted.length != newTasks.length) {
            throw const FormEntryException('fieldChanged');
          }
          _require(
            await DatabaseEventUpdateChecklistCell(
              ChecklistCellDataChangesetPB(
                cellId: cellId,
                completedTasks: [
                  for (var i = 0; i < newTasks.length; i++)
                    if (newTasks[i].checked) inserted[i].id,
                ],
              ),
            ).send(),
          );
        }
      case FormReminderValue():
        await _writeReminder(viewId, rowId, field, value, previous);
    }
  }

  Future<void> _writeReminder(
    String viewId,
    String rowId,
    FieldPB field,
    FormReminderValue value,
    FormFieldValue? previous,
  ) async {
    const service = ReminderService();
    final prior =
        previous is FormReminderValue ? previous : const FormReminderValue();
    final reminders = prior.reminderId.isEmpty
        ? const <ReminderPB>[]
        : _require(await service.fetchReminders());
    final matching =
        reminders.where((reminder) => reminder.id == prior.reminderId);
    final old = matching.isEmpty ? null : matching.first;
    if (value.at == null) {
      await writeCell(viewId, rowId, field, '');
      if (old != null) {
        try {
          _require(await service.removeReminder(reminderId: old.id));
        } on Object {
          await writeCell(viewId, rowId, field, prior.storedText);
          rethrow;
        }
      }
      return;
    }
    final next = old == null
        ? AppReminder(
            id: value.reminderId,
            title: field.name,
            message: '',
            scheduledAt: value.at!,
            objectId: viewId,
            kind: ReminderKind.row,
            rowId: rowId,
            includeTime: value.includeTime,
          ).toPB()
        : (ReminderPB()..mergeFromMessage(old));
    next.scheduledAt = Int64(value.at!.millisecondsSinceEpoch ~/ 1000);
    next.meta[ReminderMetaKeys.includeTime] = value.includeTime.toString();
    next.meta[ReminderMetaKeys.date] =
        value.at!.millisecondsSinceEpoch.toString();
    _require(
      await (old == null
          ? service.addReminder(reminder: next)
          : service.updateReminder(reminder: next)),
    );
    try {
      await writeCell(viewId, rowId, field, value.storedText);
    } on Object {
      _require(
        await (old == null
            ? service.removeReminder(reminderId: next.id)
            : service.updateReminder(reminder: old)),
      );
      rethrow;
    }
  }

  Future<MediaFilePB> storeAttachment(
    String rowId,
    FormFileAttachment attachment,
  ) async {
    final pending = attachment.pending;
    if (pending == null) return attachment.file;
    final profile = _require(await UserBackendService.getCurrentUserProfile());
    final local = profile.workspaceType == WorkspaceTypePB.LocalW;
    final path = local
        ? await saveFileToLocalStorage(pending.path)
        : (await saveFileToCloudStorage(pending.path, rowId)).$1;
    if (path == null) throw const FormEntryException('uploadFailed');
    return MediaFilePB.fromBuffer(attachment.file.writeToBuffer())
      ..url = path
      ..uploadType =
          local ? FileUploadTypePB.LocalFile : FileUploadTypePB.CloudFile;
  }

  Future<List<FieldPB>> fields(String viewId) async =>
      _require(await FieldBackendService.getFields(viewId: viewId));

  Future<EncryptedColumns> encryptedColumns(String viewId) async {
    final columns = await EncryptedColumnRegistry.instance.readColumns(viewId);
    if (columns == null) throw const FormEntryException('protectionUnknown');
    return columns;
  }

  Future<String> createRow(String viewId) async =>
      _require(await RowBackendService.createRow(viewId: viewId)).id;

  Future<void> deleteRow(String viewId, String rowId) async {
    _require(await RowBackendService.deleteRows(viewId, [rowId]));
  }

  Future<FieldPB> createField(String viewId, FormCustomField field) async =>
      _require(
        await FieldBackendService.createField(
          viewId: viewId,
          fieldType: field.kind.fieldType,
          fieldName: field.name.trim(),
        ),
      );

  Future<void> renameField(String viewId, String fieldId, String name) async {
    _require(
      await FieldBackendService(viewId: viewId, fieldId: fieldId)
          .updateField(name: name.trim()),
    );
  }

  Future<void> deleteField(String viewId, String fieldId) async {
    _require(
      await FieldBackendService.deleteField(
        viewId: viewId,
        fieldId: fieldId,
      ),
    );
  }

  Future<void> setEncrypted(
    String viewId,
    String fieldId,
    bool encrypted,
  ) async {
    final registry = EncryptedColumnRegistry.instance;
    final result = await (encrypted
        ? registry.encryptColumn(viewId: viewId, fieldId: fieldId)
        : registry.decryptColumn(viewId: viewId, fieldId: fieldId));
    if (!result.succeeded) throw const FormEntryException('encryptionFailed');
  }

  Future<void> writeCell(
    String viewId,
    String rowId,
    FieldPB field,
    String value,
  ) async {
    final cellId = CellIdPB(
      viewId: viewId,
      rowId: rowId,
      fieldId: field.id,
    );
    switch (field.fieldType) {
      case FieldType.DateTime:
        final service = DateCellBackendService(
          viewId: viewId,
          rowId: rowId,
          fieldId: field.id,
        );
        final date = parseTableDate(value);
        if (value.isNotEmpty && date == null) {
          throw const FormEntryException('invalidDate');
        }
        _require(
          await (date == null
              ? service.clear()
              : service.update(date: date, isRange: false)),
        );
      case FieldType.SingleSelect:
      case FieldType.MultiSelect:
        final options =
            SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData).options;
        final names = value.isEmpty
            ? <String>[]
            : field.fieldType == FieldType.SingleSelect
                ? [value]
                : tablePartsOf(value);
        final ids = <String>[];
        for (final name in names) {
          final matching = options.where((option) => option.name == name);
          if (matching.isEmpty) {
            throw const FormEntryException('unknownOption');
          }
          ids.add(matching.first.id);
        }
        // One changeset replaces the selection, including clearing it. Never
        // delete an option from the schema just to unselect it on one entry.
        _require(
          await DatabaseEventUpdateSelectOptionCell(
            SelectOptionCellChangesetPB(
              cellIdentifier: cellId,
              insertOptionIds: ids,
              deleteOptionIds: options
                  .where((option) => !ids.contains(option.id))
                  .map((option) => option.id),
            ),
          ).send(),
        );
      case FieldType.Relation:
        _require(
          await DatabaseEventUpdateRelationCell(
            RelationCellChangesetPB(
              viewId: viewId,
              cellId: cellId,
              insertedRowIds: tablePartsOf(value),
            ),
          ).send(),
        );
      default:
        _require(
          await CellBackendService.updateCell(
            viewId: viewId,
            cellContext: CellContext(fieldId: field.id, rowId: rowId),
            data: value,
          ),
        );
    }
  }

  static T _require<T>(FlowyResult<T, FlowyError> result) => result.fold(
        (value) => value,
        (_) => throw const FormEntryException('writeFailed'),
      );
}

class FormEntryService {
  FormEntryService({
    required this.viewId,
    this.backend = const FormEntryBackend(),
  });

  final String viewId;
  final FormEntryBackend backend;

  Future<FieldPB> addField(FormCustomField spec) async {
    if (spec.name.trim().isEmpty) throw const FormEntryException('emptyName');
    if (spec.kind == FormCustomFieldKind.encrypted &&
        !EncryptionVault.instance.isUnlocked) {
      throw const WorkspaceLockedError();
    }
    final field = await backend.createField(viewId, spec);
    try {
      await backend.configureField(viewId, field.id, spec.kind);
      if (spec.kind == FormCustomFieldKind.encrypted) {
        await backend.setEncrypted(viewId, field.id, true);
      }
    } on Object {
      // Only this newly created empty field is rolled back, not an existing
      // column the user has filled. Do not leave it with the wrong input kind.
      await backend.deleteField(viewId, field.id);
      throw const FormEntryException('fieldChanged');
    }
    return field;
  }

  /// Prepares every value before creating anything. In particular, ciphertext
  /// is the only version of a protected answer ever handed to the backend.
  Future<String> create(
    Map<String, String> answers, {
    Map<String, FormFieldValue> typedAnswers = const {},
  }) async {
    final fields = await backend.fields(viewId);
    final columns = await backend.encryptedColumns(viewId);
    final prepared = <(FieldPB, FormFieldValue)>[];
    final values = <String, FormFieldValue>{
      for (final answer in answers.entries)
        answer.key: FormTextValue(answer.value),
      ...typedAnswers,
    };
    for (final answer in values.entries) {
      final matching = fields.where((field) => field.id == answer.key);
      if (matching.isEmpty || !isFormFillable(matching.first)) {
        throw const FormEntryException('fieldChanged');
      }
      final field = matching.first;
      prepared.add((field, _prepare(field, answer.value, columns)));
    }
    if (prepared.isEmpty) throw const FormEntryException('empty');
    final rowId = await backend.createRow(viewId);
    try {
      for (final (field, value) in prepared) {
        await backend.writeValue(viewId, rowId, field, value);
      }
      return rowId;
    } on Object {
      // Roll back ONLY the row this operation just made, never an existing
      // entry. If cleanup fails, expose its id so retry cannot duplicate it.
      try {
        await backend.deleteRow(viewId, rowId);
      } on Object {
        throw FormEntryException('partial', partialRowId: rowId);
      }
      throw const FormEntryException('writeFailed');
    }
  }

  Future<void> update({
    required String rowId,
    required FieldPB field,
    required String value,
    required String previousValue,
  }) async {
    final fields = await backend.fields(viewId);
    final current = fields.where((candidate) => candidate.id == field.id);
    if (current.isEmpty ||
        current.first.fieldType != field.fieldType ||
        !isFormInlineEditable(current.first)) {
      throw const FormEntryException('fieldChanged');
    }
    final columns = await backend.encryptedColumns(viewId);
    final stored = _encode(
      current.first,
      value,
      columns,
      wasSealed: looksSealed(previousValue),
    );
    await backend.writeCell(viewId, rowId, current.first, stored);
  }

  Future<void> updateValue({
    required String rowId,
    required FieldPB field,
    required FormFieldValue value,
    required FormFieldValue previous,
  }) async {
    final fields = await backend.fields(viewId);
    final matching = fields.where((candidate) => candidate.id == field.id);
    if (matching.isEmpty ||
        matching.first.fieldType != field.fieldType ||
        !isFormFillable(field)) {
      throw const FormEntryException('fieldChanged');
    }
    final columns = await backend.encryptedColumns(viewId);
    final prepared = _prepare(matching.first, value, columns);
    final current = await backend.readValue(viewId, rowId, matching.first);
    if (current.fingerprint != previous.fingerprint) {
      throw const FormEntryException('fieldChanged');
    }
    await backend.writeValue(
      viewId,
      rowId,
      matching.first,
      prepared,
      previous: current,
    );
  }

  FormFieldValue _prepare(
    FieldPB field,
    FormFieldValue value,
    EncryptedColumns columns,
  ) {
    if (value is FormTextValue) {
      if (field.fieldType == FieldType.Time &&
          value.text.isNotEmpty &&
          (parseTime(value.text) == null || parseTime(value.text)! < 0)) {
        throw const FormEntryException('invalidTime');
      }
      return FormTextValue(_encode(field, value.text, columns));
    }
    final supported = switch (value) {
      FormDateValue() => field.fieldType == FieldType.DateTime &&
          (!value.isRange ||
              (value.start != null &&
                  value.end != null &&
                  !value.end!.isBefore(value.start!))),
      FormFilesValue() => field.fieldType == FieldType.Media,
      FormChecklistValue() => field.fieldType == FieldType.Checklist &&
          value.tasks.every((task) => task.name.trim().isNotEmpty),
      FormSelectionValue() => const [
          FieldType.SingleSelect,
          FieldType.MultiSelect,
          FieldType.Relation,
        ].contains(field.fieldType),
      FormReminderValue() => field.fieldType == FieldType.RichText &&
          (value.at == null || value.reminderId.isNotEmpty),
      _ => false,
    };
    if (!supported || columns.contains(field.id)) {
      throw const FormEntryException('fieldChanged');
    }
    if (value is FormSelectionValue && field.fieldType != FieldType.Relation) {
      final available =
          SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData)
              .options
              .map((o) => o.id)
              .toSet();
      if (value.ids.any((id) => !available.contains(id)) ||
          (field.fieldType == FieldType.SingleSelect && value.ids.length > 1)) {
        throw const FormEntryException('unknownOption');
      }
    }
    return value;
  }

  String _encode(
    FieldPB field,
    String value,
    EncryptedColumns columns, {
    bool wasSealed = false,
  }) {
    if (columns.contains(field.id) || wasSealed) {
      if (!EncryptedColumnRegistry.canEncrypt(field.fieldType)) {
        throw const FormEntryException('fieldChanged');
      }
      if (!EncryptionVault.instance.isUnlocked) {
        throw const WorkspaceLockedError();
      }
      return EncryptionVault.instance
          .seal(value, context: encryptedCellContext);
    }
    if (field.fieldType == FieldType.Number && value.trim().isNotEmpty) {
      final number = double.tryParse(value.trim().replaceAll(',', ''));
      if (number == null || !number.isFinite) {
        throw const FormEntryException('invalidNumber');
      }
    }
    return value;
  }
}

DateCellChangesetPB formDateChangeset(CellIdPB cellId, FormDateValue value) =>
    DateCellChangesetPB(
      cellId: cellId,
      timestamp: value.start == null
          ? null
          : Int64(value.start!.millisecondsSinceEpoch ~/ 1000),
      endTimestamp: !value.isRange || value.end == null
          ? null
          : Int64(value.end!.millisecondsSinceEpoch ~/ 1000),
      includeTime: value.includeTime,
      isRange: value.isRange,
      clearFlag: value.start == null,
      reminderId: value.start == null ? '' : value.reminderId,
    );

ChecklistCellDataChangesetPB formChecklistChangeset(
  CellIdPB cellId,
  FormChecklistValue before,
  FormChecklistValue after,
) {
  final old = {for (final task in before.tasks) task.id: task};
  final ids = after.tasks.map((task) => task.id).toSet();
  return ChecklistCellDataChangesetPB(
    cellId: cellId,
    insertTask: [
      for (final task in after.tasks)
        if (task.id.startsWith('draft:'))
          ChecklistCellInsertPB(name: task.name),
    ],
    deleteTasks: old.keys.where((id) => !ids.contains(id)),
    updateTasks: [
      for (final task in after.tasks)
        if (old.containsKey(task.id) && old[task.id]!.name != task.name)
          SelectOptionPB(id: task.id, name: task.name),
    ],
    completedTasks: [
      for (final task in after.tasks)
        if (old.containsKey(task.id) && old[task.id]!.checked != task.checked)
          task.id,
    ],
  );
}
