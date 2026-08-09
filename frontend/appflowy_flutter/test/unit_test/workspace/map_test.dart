import 'package:appflowy/shared/maps/map_geo.dart';
import 'package:appflowy/shared/maps/map_tile_provider.dart';
import 'package:appflowy/workspace/application/maps/map_metadata.dart';
import 'package:appflowy/workspace/application/maps/map_source.dart';
import 'package:appflowy/workspace/application/maps/map_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB _view({
  required String extra,
  ViewLayoutPB layout = ViewLayoutPB.Grid,
}) =>
    ViewPB()
      ..id = 'view'
      ..name = 'Places'
      ..layout = layout
      ..extra = extra;

void main() {
  group('how a table is placed', () {
    test('settings survive being written and read back', () {
      const spec = MapSpec(
        locationColumns: ['field-1', 'field-2'],
        titleColumn: 'title',
        subtitleColumn: 'subtitle',
        colorColumn: 'status',
        propertyColumns: ['a', 'b'],
        provider: MapProviderKind.openStreetMap,
        style: MapStyleName.dark,
        clustering: false,
        center: LatLng(51.5, -0.12),
        zoom: 12.5,
      );

      final back = MapSpec.fromJson(spec.toJson());

      expect(back, spec);
      expect(back.locationColumns, ['field-1', 'field-2']);
      expect(back.center?.latitude, closeTo(51.5, 1e-9));
      expect(back.zoom, 12.5);
    });

    test('a map with nothing set is small on disk', () {
      expect(const MapSpec().toJson(), isEmpty);
    });

    test('a map needs a location column before it can place anything', () {
      expect(const MapSpec().isConfigured, isFalse);
      expect(
        const MapSpec(locationColumns: ['where']).isConfigured,
        isTrue,
      );
    });

    test('the style can be cleared back to following the appearance', () {
      const spec = MapSpec(style: MapStyleName.dark);
      expect(spec.copyWith(clearStyle: true).style, isNull);
      expect(
        spec.copyWith(style: MapStyleName.light).style,
        MapStyleName.light,
      );
    });

    test('an unknown provider or style falls back rather than throwing', () {
      final spec = MapSpec.fromJson(const {
        'provider': 'nonsense',
        'style': 'nonsense',
      });
      expect(spec.provider, MapProviderKind.google);
      expect(spec.style, isNull);
    });
  });

  group('the mark that turns a table into a map', () {
    test('it rides alongside whatever else the view carries', () {
      const other = '{"appflowy_workspace_item":{"version":1,"kind":"folder"}}';
      final extra = MapMetadata.newExtra();
      expect(MapMetadata.fromExtra(extra), isNotNull);

      final merged = const MapMetadata(spec: MapSpec()).mergeIntoExtra(other);
      expect(merged, contains('appflowy_workspace_item'));
      expect(MapMetadata.fromExtra(merged), isNotNull);
    });

    test('removing it leaves the rest of the view alone', () {
      const other = '{"cover":{"type":"built_in","value":"3"}}';
      final merged = const MapMetadata(spec: MapSpec()).mergeIntoExtra(other);

      final without = MapMetadata.removeFromExtra(merged);

      expect(MapMetadata.fromExtra(without), isNull);
      expect(without, contains('cover'));
    });

    test('a table with the mark is a map, and a plain one is not', () {
      expect(_view(extra: MapMetadata.newExtra()).isMap, isTrue);
      expect(_view(extra: '').isMap, isFalse);
      expect(_view(extra: '{"something":1}').isMap, isFalse);
    });

    test('a document is never a map, whatever it carries', () {
      final view = _view(
        extra: MapMetadata.newExtra(),
        layout: ViewLayoutPB.Document,
      );
      expect(view.isMap, isFalse);
    });

    test('a version from the future is not guessed at', () {
      const ahead = '{"appflowy_map":{"version":99,"spec":{}}}';
      expect(MapMetadata.fromExtra(ahead), isNull);
    });

    test('the settings ride inside the mark', () {
      const spec = MapSpec(locationColumns: ['where'], clustering: false);
      final extra = MapMetadata.newExtra(spec: spec);

      final read = MapMetadata.fromExtra(extra);

      expect(read?.spec.locationColumns, ['where']);
      expect(read?.spec.clustering, isFalse);
    });

    test('showing the rows instead of the map is remembered', () {
      final extra = const MapMetadata(spec: MapSpec(), showTable: true)
          .mergeIntoExtra('');
      expect(MapMetadata.fromExtra(extra)?.showTable, isTrue);
      // A map showing its rows is a grid again.
      expect(_view(extra: extra).isMap, isTrue);
    });
  });

  group('where a map can be made', () {
    test('the add menu offers one beside the table, board and calendar', () {
      expect(WorkspaceTableKind.values, contains(WorkspaceTableKind.map));
      expect(WorkspaceTableKind.map.layout, ViewLayoutPB.Grid);
      expect(WorkspaceTableKind.map.mapped, isTrue);
      expect(WorkspaceTableKind.map.charted, isFalse);
    });

    test('every kind still knows how to name and draw itself', () {
      for (final kind in WorkspaceTableKind.values) {
        expect(workspaceTableKindLabel(kind), isNotEmpty);
        expect(workspaceTableKindIcon(kind), isNotNull);
      }
    });
  });

  group('what the map counts', () {
    // The shape a real table comes back in: most rows are empty, and the rows
    // that were never opened carry no cells at all rather than blank ones.
    RepeatedRowTextPB tableWithOneAddress() => RepeatedRowTextPB()
      ..fieldIds.addAll(['name', 'type', 'done', 'relation', 'where'])
      ..rows.addAll([
        RowTextPB()
          ..rowId = 'a'
          ..cells.addAll(['hello', '', '', '', '']),
        RowTextPB()
          ..rowId = 'b'
          ..cells.addAll(['hi', '', '', '', '']),
        RowTextPB()
          ..rowId = 'c'
          ..cells.addAll([
            'hello',
            '',
            '',
            '',
            'BnM, 205, Mile End Road, Stepney, London, E1 4AA, United Kingdom',
          ]),
        // Never opened, so the backend hands back no cells for it.
        RowTextPB()..rowId = 'd',
      ]);

    List<FieldPB> fields() => [
          FieldPB()
            ..id = 'name'
            ..name = 'Name'
            ..isPrimary = true
            ..fieldType = FieldType.RichText,
          FieldPB()
            ..id = 'type'
            ..name = 'Type'
            ..fieldType = FieldType.RichText,
          FieldPB()
            ..id = 'done'
            ..name = 'Done'
            ..fieldType = FieldType.Checkbox,
          FieldPB()
            ..id = 'relation'
            ..name = 'Relation'
            ..fieldType = FieldType.Relation,
          FieldPB()
            ..id = 'where'
            ..name = 'Location'
            ..fieldType = FieldType.RichText,
        ];

    test('one row with an address counts as one, not none', () {
      final source = MapSource(viewId: 'view')
        ..updateSpec(const MapSpec(locationColumns: ['where']))
        ..readForTest(
          tableWithOneAddress(),
          fields: fields(),
          marked: {'where'},
        );

      expect(source.columnMissing, isFalse);
      expect(source.locationColumnName, 'Location');
      // One row holds a place; it just has not been looked up yet.
      expect(source.filled, 1);
      expect(source.unplaced, 1);
      source.dispose();
    });

    test('rows that carry no cells at all are skipped, not counted', () {
      final source = MapSource(viewId: 'view')
        ..updateSpec(const MapSpec(locationColumns: ['where']))
        ..readForTest(
          RepeatedRowTextPB()
            ..fieldIds.addAll(['name', 'where'])
            ..rows.addAll([
              RowTextPB()..rowId = 'a',
              RowTextPB()..rowId = 'b',
            ]),
          fields: fields(),
        );

      expect(source.filled, 0);
      expect(source.pins, isEmpty);
      source.dispose();
    });

    test('a coordinate pair is placed without any look up', () {
      final source = MapSource(viewId: 'view')
        ..updateSpec(const MapSpec(locationColumns: ['where']))
        ..readForTest(
          RepeatedRowTextPB()
            ..fieldIds.addAll(['name', 'where'])
            ..rows.addAll([
              RowTextPB()
                ..rowId = 'a'
                ..cells.addAll(['Home', '51.5221397, -0.0457475']),
            ]),
          fields: fields(),
        );

      expect(source.filled, 1);
      expect(source.unplaced, 0);
      expect(source.pins, hasLength(1));
      expect(source.pins.single.title, 'Home');
      expect(source.pins.single.point.latitude, closeTo(51.5221397, 1e-9));
      source.dispose();
    });

    test('a column the table does not hand back is called out', () {
      final source = MapSource(viewId: 'view')
        ..updateSpec(const MapSpec(locationColumns: ['gone']))
        ..readForTest(
          tableWithOneAddress(),
          fields: fields(),
        );

      expect(source.columnMissing, isTrue);
      source.dispose();
    });
  });
}
