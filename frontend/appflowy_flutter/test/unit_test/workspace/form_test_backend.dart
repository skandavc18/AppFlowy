import 'dart:async';

import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/workspace/application/encryption/encrypted_column.dart';
import 'package:appflowy/workspace/application/encryption/encryption_vault.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/form_field_value.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';

class MemoryFormBackend extends FormEntryBackend {
  final columns = <FieldPB>[
    FieldPB(
      id: 'title',
      name: 'Name',
      fieldType: FieldType.RichText,
      isPrimary: true,
    ),
    FieldPB(id: 'username', name: 'Username', fieldType: FieldType.RichText),
    FieldPB(id: 'password', name: 'Password', fieldType: FieldType.RichText),
  ];
  final rows = <String, Map<String, String>>{};
  final typedRows = <String, Map<String, FormFieldValue>>{};
  final styles = <String, PropertyStyle>{};
  final locations = <String>{};
  final related = <String, String>{};
  final typedWrites = <(String, String, FormFieldValue)>[];
  final writes = <(String, String, String)>[];
  final deleted = <String>[];
  EncryptedColumns protection = const EncryptedColumns();
  bool failProtection = false;
  bool failEncryption = false;
  String? failField;
  bool failDelete = false;
  Completer<void>? pendingWrite;
  void Function()? changed;
  int creations = 0;

  @override
  Future<List<FieldPB>> fields(String viewId) async => columns;

  @override
  Future<FormFieldValue> readValue(
    String viewId,
    String rowId,
    FieldPB field,
  ) async =>
      typedRows[rowId]?[field.id] ??
      (const [
        FieldType.RichText,
        FieldType.Number,
        FieldType.Checkbox,
        FieldType.URL,
        FieldType.Time,
      ].contains(field.fieldType)
          ? FormTextValue(rows[rowId]?[field.id] ?? '')
          : emptyFormValue(field));

  @override
  Future<void> writeValue(
    String viewId,
    String rowId,
    FieldPB field,
    FormFieldValue value, {
    FormFieldValue? previous,
  }) async {
    if (value is FormTextValue) {
      return writeCell(viewId, rowId, field, value.text);
    }
    if (pendingWrite != null) await pendingWrite!.future;
    if (field.id == failField) throw const FormEntryException('writeFailed');
    typedWrites.add((rowId, field.id, value));
    typedRows.putIfAbsent(rowId, () => {})[field.id] = value;
    rows[rowId]![field.id] = value.text;
    changed?.call();
  }

  @override
  Future<Map<String, String>> relatedRows(FieldPB field) async => related;

  @override
  Future<void> configureField(
    String viewId,
    String fieldId,
    FormCustomFieldKind kind,
  ) async {
    if (kind == FormCustomFieldKind.location) locations.add(fieldId);
    final style = switch (kind) {
      FormCustomFieldKind.button => PropertyStyleKind.button,
      FormCustomFieldKind.counter => PropertyStyleKind.counter,
      FormCustomFieldKind.progress => PropertyStyleKind.progress,
      _ => null,
    };
    if (style != null) styles[fieldId] = PropertyStyle(kind: style);
  }

  @override
  Future<EncryptedColumns> encryptedColumns(String viewId) async {
    if (failProtection) throw const FormEntryException('protectionUnknown');
    return protection;
  }

  @override
  Future<String> createRow(String viewId) async {
    final id = 'created-${++creations}';
    rows[id] = {};
    return id;
  }

  @override
  Future<void> deleteRow(String viewId, String rowId) async {
    if (failDelete) throw StateError('test failure');
    deleted.add(rowId);
    rows.remove(rowId);
    changed?.call();
  }

  @override
  Future<void> writeCell(
    String viewId,
    String rowId,
    FieldPB field,
    String value,
  ) async {
    if (pendingWrite != null) await pendingWrite!.future;
    if (field.id == failField) {
      throw StateError('test-only secret must not surface');
    }
    writes.add((rowId, field.id, value));
    rows[rowId]![field.id] = value;
    typedRows[rowId]?[field.id] = FormTextValue(value);
    changed?.call();
  }

  @override
  Future<FieldPB> createField(String viewId, FormCustomField field) async {
    final result = FieldPB(
      id: 'custom-${columns.length}',
      name: field.name,
      fieldType: field.kind.fieldType,
    );
    columns.add(result);
    changed?.call();
    return result;
  }

  @override
  Future<void> renameField(String viewId, String fieldId, String name) async {
    columns.firstWhere((field) => field.id == fieldId).name = name;
    changed?.call();
  }

  @override
  Future<void> deleteField(String viewId, String fieldId) async {
    columns.removeWhere((field) => field.id == fieldId);
    changed?.call();
  }

  @override
  Future<void> setEncrypted(
    String viewId,
    String fieldId,
    bool encrypted,
  ) async {
    if (failEncryption) throw const FormEntryException('encryptionFailed');
    final result = await rewriteColumnEncryption(
      key: EncryptionVault.instance.keyForBulkWork!,
      values: {
        for (final row in rows.entries) row.key: row.value[fieldId] ?? '',
      },
      encrypt: encrypted,
      write: (rowId, value) async {
        rows[rowId]![fieldId] = value;
        return true;
      },
      mark: () async {
        protection = protection.with_(fieldId, sealed: encrypted);
        EncryptedColumnRegistry.instance.seedForTest(viewId, protection);
        return true;
      },
    );
    if (!result.succeeded) throw const FormEntryException('encryptionFailed');
    changed?.call();
  }
}

class MemoryFormSource extends TableRowSource {
  MemoryFormSource(this.backend) : super(viewId: '') {
    backend.changed = refresh;
    refresh();
  }

  final MemoryFormBackend backend;

  void refresh() => readForTest(
        RepeatedRowTextPB(
          fieldIds: backend.columns.map((field) => field.id),
          rows: backend.rows.entries.map(
            (entry) => RowTextPB(
              rowId: entry.key,
              cells:
                  backend.columns.map((field) => entry.value[field.id] ?? ''),
            ),
          ),
        ),
        fields: backend.columns,
        marked: backend.locations,
      );

  @override
  PropertyStyle? styleForField(String fieldId, {String rowId = ''}) =>
      backend.styles[fieldId];

  @override
  Future<void> load() async => refresh();

  @override
  void dispose() {
    backend.changed = null;
    super.dispose();
  }
}
