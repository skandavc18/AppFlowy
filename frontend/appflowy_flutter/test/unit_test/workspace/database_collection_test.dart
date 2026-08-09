import 'package:appflowy/workspace/application/collections/database/database_collection_state.dart';
import 'package:appflowy/workspace/application/collections/database/database_schema.dart';
import 'package:appflowy/workspace/application/collections/database/database_table.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('tables in a collection', () {
    test('keeps the databases and leaves everything else alone', () {
      final tables = databaseTablesFrom([
        _view(id: '1', name: 'People', layout: ViewLayoutPB.Grid),
        _view(id: '2', name: 'Notes', layout: ViewLayoutPB.Document),
        _view(id: '3', name: 'Sprint', layout: ViewLayoutPB.Board),
        _view(id: '4', name: 'Shifts', layout: ViewLayoutPB.Calendar),
      ]);

      expect(tables.map((table) => table.id), ['1', '3', '4']);
      expect(tables.map((table) => table.layout), [
        ViewLayoutPB.Grid,
        ViewLayoutPB.Board,
        ViewLayoutPB.Calendar,
      ]);
    });

    test('names a table that has never been named', () {
      final table = DatabaseTable(
        view: _view(id: '1', name: '', layout: ViewLayoutPB.Grid),
      );
      expect(table.name, untitledTableName);
    });
  });

  group('relations between tables', () {
    test('joins a relation column to the table it points at', () {
      final relations = buildDatabaseRelations([
        _summary(
          viewId: 'people',
          databaseId: 'db-people',
          fields: [
            _field(id: 'f1', name: 'Name', type: FieldType.RichText),
            _field(
              id: 'f2',
              name: 'Team',
              type: FieldType.Relation,
              relatedDatabaseId: 'db-teams',
            ),
          ],
        ),
        _summary(viewId: 'teams', databaseId: 'db-teams'),
      ]);

      expect(relations, hasLength(1));
      expect(relations.single.fromViewId, 'people');
      expect(relations.single.fieldName, 'Team');
      expect(relations.single.toViewId, 'teams');
      expect(relations.single.isInternal, isTrue);
    });

    test('reports a relation that leaves the collection rather than hiding it',
        () {
      final relations = buildDatabaseRelations([
        _summary(
          viewId: 'people',
          databaseId: 'db-people',
          fields: [
            _field(
              id: 'f1',
              name: 'Vendor',
              type: FieldType.Relation,
              relatedDatabaseId: 'db-elsewhere',
            ),
          ],
        ),
      ]);

      expect(relations.single.toViewId, isNull);
      expect(relations.single.isInternal, isFalse);
      expect(relations.single.toDatabaseId, 'db-elsewhere');
    });

    test('ignores a relation column that has not been pointed anywhere', () {
      final relations = buildDatabaseRelations([
        _summary(
          viewId: 'people',
          databaseId: 'db-people',
          fields: [
            _field(id: 'f1', name: 'Team', type: FieldType.Relation),
          ],
        ),
      ]);

      expect(relations, isEmpty);
    });
  });

  group('table summary', () {
    test('answers with the primary column, then the first one', () {
      final withPrimary = _summary(
        viewId: 'a',
        databaseId: 'db',
        fields: [
          _field(id: 'f1', name: 'Notes', type: FieldType.RichText),
          _field(
            id: 'f2',
            name: 'Name',
            type: FieldType.RichText,
            isPrimary: true,
          ),
        ],
      );
      expect(withPrimary.primaryField?.name, 'Name');

      final withoutPrimary = _summary(
        viewId: 'a',
        databaseId: 'db',
        fields: [_field(id: 'f1', name: 'Notes', type: FieldType.RichText)],
      );
      expect(withoutPrimary.primaryField?.name, 'Notes');
      expect(DatabaseTableSummary.empty.primaryField, isNull);
    });
  });

  group('workbench state', () {
    test('round trips through the collection envelope', () {
      const state = DatabaseCollectionState(
        activeTableId: 'people',
        showRail: false,
        showSchema: true,
      );

      final restored = DatabaseCollectionState.fromJson(state.toJson());
      expect(restored.activeTableId, 'people');
      expect(restored.showRail, isFalse);
      expect(restored.showSchema, isTrue);
    });

    test('opens with the rail shown and the rows, not the columns', () {
      final fresh = DatabaseCollectionState.fromJson(const {});
      expect(fresh.activeTableId, isNull);
      expect(fresh.showRail, isTrue);
      expect(fresh.showSchema, isFalse);
    });

    test('clears the open table without losing the pane layout', () {
      const state = DatabaseCollectionState(
        activeTableId: 'people',
        showSchema: true,
      );
      final cleared = state.copyWith(clearActiveTable: true);
      expect(cleared.activeTableId, isNull);
      expect(cleared.showSchema, isTrue);
    });
  });
}

ViewPB _view({
  required String id,
  required String name,
  required ViewLayoutPB layout,
}) =>
    ViewPB()
      ..id = id
      ..name = name
      ..layout = layout;

DatabaseTableSummary _summary({
  required String viewId,
  required String databaseId,
  List<DatabaseFieldSummary> fields = const [],
  int rowCount = 0,
}) =>
    DatabaseTableSummary(
      viewId: viewId,
      databaseId: databaseId,
      fields: fields,
      rowCount: rowCount,
    );

DatabaseFieldSummary _field({
  required String id,
  required String name,
  required FieldType type,
  bool isPrimary = false,
  String? relatedDatabaseId,
}) =>
    DatabaseFieldSummary(
      id: id,
      name: name,
      type: type,
      isPrimary: isPrimary,
      relatedDatabaseId: relatedDatabaseId,
    );
