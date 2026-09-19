import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/form_field_value.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter_test/flutter_test.dart';

import 'form_test_backend.dart';

void main() {
  test('native date payload keeps time, range and reminder on edit', () {
    final start = DateTime(2026, 9, 20, 14, 35);
    final end = DateTime(2026, 9, 21, 17, 50);
    final data = DateCellDataPB(
      timestamp: Int64(start.millisecondsSinceEpoch ~/ 1000),
      endTimestamp: Int64(end.millisecondsSinceEpoch ~/ 1000),
      includeTime: true,
      isRange: true,
      reminderId: 'kept-reminder',
    );
    final value = decodeFormCell(
      FieldPB(fieldType: FieldType.DateTime),
      data.writeToBuffer(),
    ) as FormDateValue;
    expect(value.start, start);
    expect(value.end, end);
    final changed = value.copyWith(start: start.add(const Duration(hours: 1)));
    final payload = formDateChangeset(CellIdPB(), changed);
    expect(
      payload.timestamp.toInt(),
      start.add(const Duration(hours: 1)).millisecondsSinceEpoch ~/ 1000,
    );
    expect(payload.endTimestamp, data.endTimestamp);
    expect(payload.includeTime, isTrue);
    expect(payload.isRange, isTrue);
    expect(payload.reminderId, 'kept-reminder');
  });

  test('empty and cleared dates do not become the epoch', () {
    final empty = decodeFormCell(
      FieldPB(fieldType: FieldType.DateTime),
      DateCellDataPB().writeToBuffer(),
    ) as FormDateValue;
    expect(empty.start, isNull);
    expect(empty.isEmpty, isTrue);
    final clear =
        formDateChangeset(CellIdPB(), const FormDateValue(reminderId: 'old'));
    expect(clear.clearFlag, isTrue);
    expect(clear.reminderId, '');
    expect(clear.hasTimestamp(), isFalse);
  });

  test(
      'file ids, links, upload type and order are not reconstructed from names',
      () {
    final files = [
      MediaFilePB(
        id: 'one',
        name: 'same.pdf',
        url: 'https://test.invalid/a',
        uploadType: FileUploadTypePB.CloudFile,
        fileType: MediaFileTypePB.Document,
      ),
      MediaFilePB(
        id: 'two',
        name: 'same.pdf',
        url: 'C:/test/b.pdf',
        uploadType: FileUploadTypePB.LocalFile,
        fileType: MediaFileTypePB.Document,
      ),
    ];
    final value = decodeFormCell(
      FieldPB(fieldType: FieldType.Media),
      MediaCellDataPB(files: files).writeToBuffer(),
    ) as FormFilesValue;
    expect(value.files.map((file) => file.file), files);
    expect(value.files.every((file) => file.pending == null), isTrue);
  });

  test('a choice name with commas remains one selected id', () {
    final selected = SelectOptionPB(id: 'id', name: 'Design, review');
    final value = decodeFormCell(
      FieldPB(fieldType: FieldType.SingleSelect),
      SelectOptionCellDataPB(selectOptions: [selected]).writeToBuffer(),
    ) as FormSelectionValue;
    expect(value.ids, ['id']);
    expect(value.text, 'Design, review');
  });

  test('standalone time remains a duration in minutes', () {
    final value = decodeFormCell(
      FieldPB(fieldType: FieldType.Time),
      TimeCellDataPB(time: Int64(135)).writeToBuffer(),
    );
    expect(value.text, '2h 15m');
    expect(formControlOf(FieldPB(fieldType: FieldType.Time)), FormControl.time);
  });

  test('URL and boolean use their own payloads', () {
    expect(
      decodeFormCell(
        FieldPB(fieldType: FieldType.URL),
        URLCellDataPB(content: 'https://example.test').writeToBuffer(),
      ).text,
      'https://example.test',
    );
    expect(
      decodeFormCell(
        FieldPB(fieldType: FieldType.Checkbox),
        CheckboxCellDataPB(isChecked: true).writeToBuffer(),
      ).text,
      'Yes',
    );
  });

  test('checklist changes toggle only ids whose completion actually changed',
      () {
    const old = FormChecklistValue([
      FormChecklistTask(id: 'a', name: 'Keep', checked: true),
      FormChecklistTask(id: 'b', name: 'Rename'),
      FormChecklistTask(id: 'c', name: 'Remove'),
    ]);
    const next = FormChecklistValue([
      FormChecklistTask(id: 'a', name: 'Keep', checked: true),
      FormChecklistTask(id: 'b', name: 'Renamed', checked: true),
      FormChecklistTask(id: 'draft:new', name: 'Added'),
    ]);
    final payload = formChecklistChangeset(CellIdPB(), old, next);
    expect(payload.completedTasks, ['b']);
    expect(payload.deleteTasks, ['c']);
    expect(payload.updateTasks.single.id, 'b');
    expect(payload.updateTasks.single.name, 'Renamed');
    expect(payload.insertTask.single.name, 'Added');
  });

  test('configured styles select controls before heading heuristics', () {
    final field =
        FieldPB(fieldType: FieldType.RichText, name: 'Location notes');
    expect(formControlOf(field, styleKind: 'button'), FormControl.button);
    expect(formControlOf(field, styleKind: 'counter'), FormControl.counter);
    expect(formControlOf(field, styleKind: 'progress'), FormControl.progress);
    expect(formControlOf(field, isLocation: true), FormControl.place);
    expect(
      formControlOf(FieldPB(fieldType: FieldType.Checklist)),
      FormControl.checklist,
    );
  });

  test('typed creation accepts files and dates without a text detour',
      () async {
    final backend = MemoryFormBackend();
    final date = FieldPB(id: 'date', fieldType: FieldType.DateTime);
    final files = FieldPB(id: 'files', fieldType: FieldType.Media);
    backend.columns.addAll([date, files]);
    final service = FormEntryService(viewId: '', backend: backend);
    final value =
        FormDateValue(start: DateTime(2026, 9, 20, 16), includeTime: true);
    final attachment = FormFilesValue([
      FormFileAttachment(
        file: MediaFilePB(
          id: 'a',
          name: 'a.pdf',
          url: 'https://test.invalid/a',
        ),
      ),
    ]);
    final row = await service
        .create({}, typedAnswers: {'date': value, 'files': attachment});
    expect(backend.typedRows[row]!['date'], same(value));
    expect(backend.typedRows[row]!['files'], same(attachment));
    expect(backend.writes, isEmpty);
  });

  test('external typed changes refuse stale edits without replacing metadata',
      () async {
    final backend = MemoryFormBackend();
    final field = FieldPB(id: 'date', fieldType: FieldType.DateTime);
    backend.columns.add(field);
    final old = FormDateValue(start: DateTime(2026, 9, 20));
    final current = old.copyWith(includeTime: true);
    backend.typedRows['row'] = {'date': current};
    final service = FormEntryService(viewId: '', backend: backend);
    await expectLater(
      service.updateValue(
        rowId: 'row',
        field: field,
        value: old.copyWith(start: DateTime(2026, 9, 21)),
        previous: old,
      ),
      throwsA(isA<FormEntryException>()),
    );
    expect(backend.typedWrites, isEmpty);
    expect(backend.typedRows['row']!['date'], same(current));
  });

  test('invalid range is rejected before creating a row', () async {
    final backend = MemoryFormBackend()
      ..columns.add(FieldPB(id: 'date', fieldType: FieldType.DateTime));
    final service = FormEntryService(viewId: '', backend: backend);
    await expectLater(
      service.create(
        {},
        typedAnswers: {
          'date': FormDateValue(
            start: DateTime(2026, 9, 21),
            end: DateTime(2026, 9, 20),
            isRange: true,
          ),
        },
      ),
      throwsA(isA<FormEntryException>()),
    );
    expect(backend.creations, 0);
  });
}
