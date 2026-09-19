import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/encryption/encryption.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_test_backend.dart';

void main() {
  final vault = EncryptionVault.instance;
  late MemoryFormBackend backend;
  late FormEntryService service;
  setUp(() {
    backend = MemoryFormBackend();
    service = FormEntryService(viewId: 'test-form', backend: backend);
    vault.seedForTest(
      policy:
          const EncryptionPolicy(enabled: true, salt: 'test', verifier: 'test'),
      key: randomBytes(32),
    );
  });
  tearDown(vault.resetForTest);

  test('masking round trips independently of hiding and encryption', () {
    final spec = const FormSpec()
        .withMasked('password', true)
        .withHidden('username', true);
    final extra = TableViewMark(
            kind: TableViewKind.form, settings: spec.toJson())
        .mergeIntoExtra(
            const EncryptedColumns(fieldIds: {'separate'}).mergeIntoExtra(''));
    final restored = FormSpec.fromJson(
        TableViewMark.fromExtra(extra, TableViewKind.form)!.settings);
    expect(restored, spec);
    expect(restored.isMasked('password'), isTrue);
    expect(restored.isHidden('password'), isFalse);
    expect(EncryptedColumns.fromExtra(extra).fieldIds, {'separate'});
    expect(jsonEncode(restored.toJson()), isNot(contains('encrypted')));
    expect(FormSpec.fromJson(const {}).maskedColumns, isEmpty);
    expect(spec.withMasked('password', true).maskedColumns, ['password']);
    expect(spec.withMasked('password', false).maskedColumns, isEmpty);
  });

  test('required fields that are hidden or gone cannot block submission', () {
    const spec = FormSpec(
        requiredColumns: ['title', 'hidden', 'deleted'],
        hiddenColumns: ['hidden']);
    expect(
        missingRequiredFields(spec, {'title': 'Present'},
            fieldIds: ['title', 'hidden']),
        isEmpty);
  });

  test('a field occurs once even if legacy sections repeat it', () {
    final sections = formSectionsOf(
      backend.columns,
      const FormSpec(
        sections: [
          FormSection(id: 'a', fieldIds: ['title', 'title']),
          FormSection(id: 'b', fieldIds: ['title', 'username']),
        ],
      ),
    );
    expect(sections.expand((section) => section.fieldIds),
        ['title', 'username', 'password']);
  });

  test('the raw reader keeps whitespace, empty values and ciphertext', () {
    final sealed = vault.seal('secret', context: encryptedCellContext);
    backend.rows['a'] = {'title': '  Entry  ', 'password': sealed};
    final source = MemoryFormSource(backend);
    expect(source.cellValuesFor('a'),
        {'title': '  Entry  ', 'username': '', 'password': sealed});
    expect(source.cellValuesFor('missing'), isEmpty);
    source.dispose();
  });

  test('custom kinds use only backend-supported field types', () {
    expect(FormCustomFieldKind.encrypted.fieldType, FieldType.RichText);
    expect(FormCustomFieldKind.hidden.fieldType, FieldType.RichText);
    expect(FormCustomFieldKind.boolean.fieldType, FieldType.Checkbox);
    expect(FormCustomFieldKind.encrypted.masked, isTrue);
    expect(FormCustomFieldKind.text.masked, isFalse);
    for (final type in [
      FieldType.Summary,
      FieldType.Translate,
      FieldType.CreatedTime
    ]) {
      expect(isFormFillable(FieldPB(fieldType: type)), isFalse);
    }
    for (final type in [
      FieldType.Media,
      FieldType.Checklist,
      FieldType.DateTime,
      FieldType.Time,
      FieldType.Relation
    ]) {
      expect(isFormFillable(FieldPB(fieldType: type)), isTrue);
    }
  });

  test('creating an encrypted entry sends only ciphertext to persistence',
      () async {
    backend.protection = const EncryptedColumns(fieldIds: {'password'});
    final row = await service
        .create({'title': 'Work', 'password': '  exact secret\n '});
    final value = backend.rows[row]!['password']!;
    expect(looksSealed(value), isTrue);
    expect(value, isNot(contains('exact secret')));
    expect(
        vault.open(value, context: encryptedCellContext), '  exact secret\n ');
    expect(backend.writes.any((write) => write.$3.contains('exact secret')),
        isFalse);
  });

  test('plain and mask-only text preserves all whitespace too', () async {
    final row = await service.create({'password': ' \n exact \t '});
    expect(backend.rows[row]!['password'], ' \n exact \t ');
  });

  test('a locked key stops creation before a row exists', () async {
    backend.protection = const EncryptedColumns(fieldIds: {'password'});
    vault.lock();
    await expectLater(service.create({'password': 'secret'}),
        throwsA(isA<WorkspaceLockedError>()));
    expect(backend.creations, 0);
    expect(backend.writes, isEmpty);
  });

  test('a failed protection read is not treated as plaintext', () async {
    backend.failProtection = true;
    await expectLater(
        service.create({'title': 'Entry'}), throwsA(isA<FormEntryException>()));
    expect(backend.creations, 0);
  });

  test('an encrypted update remains sealed with a fresh nonce', () async {
    backend.protection = const EncryptedColumns(fieldIds: {'password'});
    final old = vault.seal('old', context: encryptedCellContext);
    backend.rows['a'] = {'title': 'Entry', 'password': old};
    await service.update(
        rowId: 'a',
        field: backend.columns.last,
        value: '  replacement  ',
        previousValue: old);
    final value = backend.rows['a']!['password']!;
    expect(looksSealed(value), isTrue);
    expect(value, isNot(old));
    expect(vault.open(value, context: encryptedCellContext), '  replacement  ');
    expect(backend.rows['a']!['title'], 'Entry');
  });

  test('ciphertext stays protected even if its marker has not arrived',
      () async {
    final old = vault.seal('old', context: encryptedCellContext);
    backend.rows['a'] = {'password': old};
    await service.update(
        rowId: 'a', field: backend.columns.last, value: '', previousValue: old);
    final value = backend.rows['a']!['password']!;
    expect(looksSealed(value), isTrue);
    expect(vault.open(value, context: encryptedCellContext), '');
  });

  test('schema changes refuse an edit instead of corrupting the field',
      () async {
    final previous = FieldPB.fromBuffer(backend.columns.last.writeToBuffer());
    backend.columns.last.fieldType = FieldType.Number;
    await expectLater(
        service.update(
            rowId: 'a', field: previous, value: 'words', previousValue: ''),
        throwsA(isA<FormEntryException>()));
    expect(backend.writes, isEmpty);
  });

  for (final value in ['words', 'NaN', 'Infinity']) {
    test('invalid number $value is refused before creation', () async {
      backend.columns.last.fieldType = FieldType.Number;
      await expectLater(service.create({'password': value}),
          throwsA(isA<FormEntryException>()));
      expect(backend.creations, 0);
    });
  }

  test('success waits for the last cell write', () async {
    backend.pendingWrite = Completer<void>();
    var finished = false;
    final future = service.create({'title': 'Entry', 'username': 'Ada'}).then(
        (_) => finished = true);
    await Future<void>.delayed(Duration.zero);
    expect(finished, isFalse);
    backend.pendingWrite!.complete();
    await future;
    expect(backend.writes, hasLength(2));
  });

  test('a failed new entry removes only its own partial row', () async {
    backend.rows['existing'] = {'title': 'Kept'};
    backend.failField = 'password';
    await expectLater(service.create({'title': 'New', 'password': 'secret'}),
        throwsA(isA<FormEntryException>()));
    expect(backend.deleted, ['created-1']);
    expect(backend.rows, {
      'existing': {'title': 'Kept'}
    });
  });

  test('failed cleanup reports the row to prevent a duplicate retry', () async {
    backend.failField = 'password';
    backend.failDelete = true;
    await expectLater(
      service.create({'title': 'New', 'password': 'secret'}),
      throwsA(
        isA<FormEntryException>()
            .having((error) => error.partialRowId, 'partial row', 'created-1')
            .having((error) => error.toString(), 'safe error',
                isNot(contains('secret'))),
      ),
    );
  });

  test('a new encrypted custom field is protected before accepting values',
      () async {
    final field = await service.addField(const FormCustomField(
        name: 'Recovery code', kind: FormCustomFieldKind.encrypted));
    expect(backend.protection.contains(field.id), isTrue);
    final rowId = await service.create({field.id: 'one-use-code'});
    expect(looksSealed(backend.rows[rowId]![field.id]), isTrue);
    expect(
        vault.open(backend.rows[rowId]![field.id]!,
            context: encryptedCellContext),
        'one-use-code');
  });

  test('failed encryption removes only the newly created empty column',
      () async {
    backend.failEncryption = true;
    await expectLater(
        service.addField(const FormCustomField(
            name: 'Recovery code', kind: FormCustomFieldKind.encrypted)),
        throwsA(isA<FormEntryException>()));
    expect(backend.columns.map((field) => field.id),
        ['title', 'username', 'password']);
  });

  test('locked custom-field creation does not create an unprotected column',
      () async {
    vault.lock();
    await expectLater(
        service.addField(const FormCustomField(
            name: 'Secret', kind: FormCustomFieldKind.encrypted)),
        throwsA(isA<WorkspaceLockedError>()));
    expect(backend.columns, hasLength(3));
  });
}
