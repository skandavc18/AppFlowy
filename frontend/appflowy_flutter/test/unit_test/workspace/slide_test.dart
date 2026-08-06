import 'package:appflowy/shared/slides/slide_geometry.dart';
import 'package:appflowy/shared/slides/slide_query.dart';
import 'package:appflowy/workspace/application/slides/slide_metadata.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/slides/slide_source.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/painting.dart';
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

FieldPB _field(
  String id,
  String name,
  FieldType type, {
  bool primary = false,
}) =>
    FieldPB()
      ..id = id
      ..name = name
      ..fieldType = type
      ..isPrimary = primary;

SlideProperty _property(
  String fieldId,
  String value, {
  SlidePropertyKind kind = SlidePropertyKind.text,
}) =>
    SlideProperty(
      fieldId: fieldId,
      name: fieldId,
      value: value,
      kind: kind,
    );

SlideCardData _card(String rowId, List<SlideProperty> properties) =>
    SlideCardData(rowId: rowId, title: rowId, properties: properties);

void main() {
  group('how a deck is arranged', () {
    test('settings survive being written and read back', () {
      const spec = SlideSpec(
        titleColumn: 'title',
        coverColumn: 'cover',
        propertyColumns: ['a', 'b'],
        hiddenColumns: ['c'],
        flow: SlideFlow.coverFlow,
        wrap: true,
        showEmptyProperties: true,
        showPageContent: true,
        index: 7,
      );

      expect(SlideSpec.fromJson(spec.toJson()), spec);
    });

    test('a deck with nothing set is small on disk', () {
      expect(const SlideSpec().toJson(), isEmpty);
    });

    test('a deck reads only its columns until it is asked for the page', () {
      expect(const SlideSpec().showPageContent, isFalse);
      expect(
        SlideSpec.fromJson(const {'page': true}).showPageContent,
        isTrue,
      );
    });

    test('an unknown arrangement falls back rather than throwing', () {
      final spec = SlideSpec.fromJson(const {'flow': 'nonsense'});
      expect(spec.flow, SlideFlow.deck);
    });
  });

  group('the mark that turns a table into a deck', () {
    test('it rides alongside whatever else the view carries', () {
      const other = '{"appflowy_map":{"version":1}}';
      final extra =
          const SlideMetadata(spec: SlideSpec()).mergeIntoExtra(other);
      expect(extra, contains('appflowy_map'));
      expect(SlideMetadata.fromExtra(extra), isNotNull);
    });

    test('removing it leaves the rest of the view alone', () {
      final extra = const SlideMetadata(spec: SlideSpec())
          .mergeIntoExtra('{"appflowy_map":{"version":1}}');
      final without = SlideMetadata.removeFromExtra(extra);
      expect(without, contains('appflowy_map'));
      expect(SlideMetadata.fromExtra(without), isNull);
    });

    test('a table with the mark is a deck, and a plain one is not', () {
      expect(_view(extra: SlideMetadata.newExtra()).isSlideDeck, isTrue);
      expect(_view(extra: '').isSlideDeck, isFalse);
    });

    test('a document is never a deck, whatever it carries', () {
      final view = _view(
        extra: SlideMetadata.newExtra(),
        layout: ViewLayoutPB.Document,
      );
      expect(view.isSlideDeck, isFalse);
    });

    test('a version from the future is not guessed at', () {
      expect(
        SlideMetadata.fromExtra('{"appflowy_slide":{"version":99}}'),
        isNull,
      );
    });

    test('the settings ride inside the mark', () {
      const spec = SlideSpec(titleColumn: 'name', flow: SlideFlow.coverFlow);
      final extra = const SlideMetadata(spec: spec).mergeIntoExtra('');
      expect(SlideMetadata.fromExtra(extra)?.spec, spec);
    });
  });

  group('what shape a column earns', () {
    test('a checkbox is a toggle and a single select is a badge', () {
      expect(
        classifySlideProperty(
          field: _field('a', 'Done', FieldType.Checkbox),
          value: 'Yes',
        ),
        SlidePropertyKind.checkbox,
      );
      expect(
        classifySlideProperty(
          field: _field('b', 'Status', FieldType.SingleSelect),
          value: 'Shipped',
        ),
        SlidePropertyKind.badge,
      );
    });

    test('a heading that names somebody wins over the column type', () {
      expect(
        classifySlideProperty(
          field: _field('a', 'Assignee', FieldType.MultiSelect),
          value: 'Ada, Grace',
        ),
        SlidePropertyKind.person,
      );
      expect(
        classifySlideProperty(
          field: _field('b', 'Tags', FieldType.MultiSelect),
          value: 'red, blue',
        ),
        SlidePropertyKind.tags,
      );
    });

    test('a marked location column is a place, whatever it holds', () {
      expect(
        classifySlideProperty(
          field: _field('a', 'Where', FieldType.RichText),
          value: '51.5, -0.1',
          isLocation: true,
        ),
        SlidePropertyKind.location,
      );
    });

    test('a number is a bar when the column has a spread to compare to', () {
      expect(
        classifySlideProperty(
          field: _field('a', 'Weight', FieldType.Number),
          value: '42',
        ),
        SlidePropertyKind.number,
      );
      expect(
        classifySlideProperty(
          field: _field('a', 'Weight', FieldType.Number),
          value: '42',
          facts: const SlideColumnFacts(lowest: 0, highest: 100),
        ),
        SlidePropertyKind.progress,
      );
    });

    test('long writing is an excerpt and short writing is not', () {
      final long = 'a' * 120;
      expect(
        classifySlideProperty(
          field: _field('a', 'Notes', FieldType.RichText),
          value: long,
        ),
        SlidePropertyKind.excerpt,
      );
      expect(
        classifySlideProperty(
          field: _field('a', 'Notes', FieldType.RichText),
          value: 'short',
        ),
        SlidePropertyKind.text,
      );
    });

    test('a link to a picture is a picture, and anything else is a link', () {
      expect(
        classifySlideProperty(
          field: _field('a', 'Link', FieldType.URL),
          value: 'https://example.com/a.png?size=2',
        ),
        SlidePropertyKind.image,
      );
      expect(
        classifySlideProperty(
          field: _field('a', 'Link', FieldType.URL),
          value: 'https://example.com/about',
        ),
        SlidePropertyKind.link,
      );
    });

    test('a checklist reads as how much of it is done', () {
      expect(
        slideFractionOf(
          field: _field('a', 'Steps', FieldType.Checklist),
          value: '3/4',
        ),
        closeTo(0.75, 1e-9),
      );
    });

    test('a percentage and a bare fraction both fill a bar', () {
      final field = _field('a', 'Progress', FieldType.Number);
      expect(slideFractionOf(field: field, value: '40%'), closeTo(0.4, 1e-9));
      expect(slideFractionOf(field: field, value: '0.25'), closeTo(0.25, 1e-9));
      expect(slideFractionOf(field: field, value: '80'), closeTo(0.8, 1e-9));
    });

    test('a number is placed within its own column when there is a spread', () {
      expect(
        slideFractionOf(
          field: _field('a', 'Weight', FieldType.Number),
          value: '25',
          facts: const SlideColumnFacts(lowest: 0, highest: 50),
        ),
        closeTo(0.5, 1e-9),
      );
    });

    test('initials stand in for somebody with no picture', () {
      expect(slideInitialsOf('Ada Lovelace'), 'AL');
      expect(slideInitialsOf('grace'), 'GR');
      expect(slideInitialsOf('   '), '?');
    });

    test('a comma separated cell reads as its parts', () {
      expect(slidePartsOf('a, b , ,c'), ['a', 'b', 'c']);
    });
  });

  group('where a slide sits', () {
    const stage = Size(1200, 600);

    test('a slide is never wider than the deck can hold', () {
      const narrow = SlideDeckLayout(viewport: Size(400, 500));
      const wide = SlideDeckLayout(viewport: Size(4000, 900));
      expect(
        narrow.cardSize.width,
        greaterThanOrEqualTo(SlideDeckLayout.minimumCardWidth),
      );
      expect(
        wide.cardSize.width,
        lessThanOrEqualTo(SlideDeckLayout.maximumCardWidth),
      );
    });

    test('only the slides near the middle are built at all', () {
      const layout = SlideDeckLayout(viewport: stage);
      final placements = layout.placements(0, 500);
      expect(placements.length, lessThanOrEqualTo(2 * layout.span + 1));
      expect(
        placements.map((placement) => placement.index),
        everyElement(lessThan(2 * SlideDeckLayout.maximumSpan + 1)),
      );
    });

    test('the slide in front is drawn last so it stands on top', () {
      const layout = SlideDeckLayout(viewport: stage);
      final placements = layout.placements(3, 10);
      expect(placements.last.index, 3);
      expect(placements.last.isActive, isTrue);
    });

    test('a deck stands its neighbours square; cover flow turns them', () {
      const deck = SlideDeckLayout(viewport: stage);
      const rack = SlideDeckLayout(viewport: stage, flow: SlideFlow.coverFlow);
      final beside = deck.placements(0, 5).firstWhere((p) => p.index == 1);
      final turned = rack.placements(0, 5).firstWhere((p) => p.index == 1);
      expect(beside.tilt, 0);
      expect(turned.tilt.abs(), greaterThan(0.3));
      // The rack overlaps, so its neighbour sits nearer the middle.
      expect(turned.dx.abs(), lessThan(beside.dx.abs()));
    });

    test('the middle slide is upright, whole and opaque', () {
      const layout =
          SlideDeckLayout(viewport: stage, flow: SlideFlow.coverFlow);
      final active = layout.placements(2, 6).last;
      expect(active.dx, closeTo(0, 1e-9));
      expect(active.scale, closeTo(1, 1e-9));
      expect(active.opacity, closeTo(1, 1e-9));
      expect(active.tilt, closeTo(0, 1e-9));
    });

    test('the deck stops at its ends unless it is asked to loop', () {
      const straight = SlideDeckLayout(viewport: stage);
      const looped = SlideDeckLayout(viewport: stage, wrap: true);
      expect(straight.clampPosition(-3, 5), 0);
      expect(straight.clampPosition(9, 5), 4);
      expect(looped.clampPosition(9, 5), 9);
    });

    test('a looping deck names the slide it settled on, not the count', () {
      const looped = SlideDeckLayout(viewport: stage, wrap: true);
      expect(looped.settledIndex(5, 5), 0);
      expect(looped.settledIndex(-1, 5), 4);
    });

    test('a loop takes the shorter way round', () {
      expect(
        slideTargetPosition(from: 0, target: 4, count: 5, wrap: true),
        -1,
      );
      expect(
        slideTargetPosition(from: 0, target: 1, count: 5, wrap: true),
        1,
      );
      expect(
        slideTargetPosition(from: 0, target: 4, count: 5, wrap: false),
        4,
      );
    });
  });

  group('what the reader asked to see', () {
    final cards = [
      _card('a', [_property('n', '10'), _property('s', 'Open')]),
      _card('b', [_property('n', '2'), _property('s', 'Done')]),
      _card('c', [_property('n', ''), _property('s', 'Open')]),
    ];

    test('nothing asked for leaves the table in its own order', () {
      final result = applySlideQuery(cards, const SlideQuery());
      expect(result.map((card) => card.rowId), ['a', 'b', 'c']);
    });

    test('numbers sort by size rather than by letter', () {
      final result = applySlideQuery(
        cards,
        const SlideQuery(sortColumn: 'n'),
      );
      expect(result.map((card) => card.rowId), ['b', 'a', 'c']);
    });

    test('an empty cell sinks to the bottom whichever way the sort runs', () {
      final down = applySlideQuery(
        cards,
        const SlideQuery(
          sortColumn: 'n',
          direction: SlideSortDirection.descending,
        ),
      );
      expect(down.map((card) => card.rowId).last, 'c');
    });

    test('narrowing by a value keeps only the rows that hold it', () {
      final result = applySlideQuery(
        cards,
        const SlideQuery(filterColumn: 's', filterValue: 'Open'),
      );
      expect(result.map((card) => card.rowId), ['a', 'c']);
    });

    test('narrowing by a column keeps the rows that filled it', () {
      final result = applySlideQuery(
        cards,
        const SlideQuery(filterColumn: 'n'),
      );
      expect(result.map((card) => card.rowId), ['a', 'b']);
    });

    test('a search names its matches without removing anything', () {
      expect(slideMatchesOf(cards, 'done'), {'b'});
      expect(slideMatchesOf(cards, ''), isEmpty);
    });

    test('a column offers the values it actually holds', () {
      expect(slideValuesOf(cards, 's'), ['Done', 'Open']);
    });
  });

  group('a table read as a deck', () {
    RepeatedRowTextPB table() => RepeatedRowTextPB()
      ..fieldIds.addAll(['name', 'status', 'notes'])
      ..rows.addAll([
        RowTextPB()
          ..rowId = 'a'
          ..cells.addAll(['Ada', 'Open', '']),
        RowTextPB()
          ..rowId = 'b'
          ..cells.addAll(['Grace', 'Done', 'a note']),
        // Never opened, so the backend hands back no cells for it.
        RowTextPB()..rowId = 'c',
      ]);

    List<FieldPB> fields() => [
          _field('name', 'Name', FieldType.RichText, primary: true),
          _field('status', 'Status', FieldType.SingleSelect),
          _field('notes', 'Notes', FieldType.RichText),
        ];

    test('every row becomes a slide, titled by the primary column', () {
      final source = SlideSource(viewId: 'view')
        ..readForTest(table(), fields: fields());

      expect(source.cards, hasLength(3));
      expect(source.cards.first.title, 'Ada');
      expect(source.cards.last.title, '');
      source.dispose();
    });

    test('an empty cell takes up no room unless it is asked to', () {
      final quiet = SlideSource(viewId: 'view')
        ..readForTest(table(), fields: fields());
      expect(quiet.cards.first.properties.map((p) => p.fieldId), ['status']);
      quiet.dispose();

      final full = SlideSource(viewId: 'view')
        ..updateSpec(const SlideSpec(showEmptyProperties: true))
        ..readForTest(table(), fields: fields());
      expect(full.cards.first.properties, hasLength(2));
      full.dispose();
    });

    test('the title column never repeats itself down the slide', () {
      final source = SlideSource(viewId: 'view')
        ..readForTest(table(), fields: fields());
      expect(
        source.cards.first.properties.map((property) => property.fieldId),
        isNot(contains('name')),
      );
      source.dispose();
    });

    test('a status stands in as the slide’s subtitle and its colour', () {
      final source = SlideSource(viewId: 'view')
        ..readForTest(table(), fields: fields());
      expect(source.cards.first.subtitle, 'Open');
      expect(source.cards.first.accent, 'Open');
      source.dispose();
    });

    test('a chosen order of columns is honoured', () {
      final source = SlideSource(viewId: 'view')
        ..updateSpec(const SlideSpec(propertyColumns: ['notes', 'status']))
        ..readForTest(table(), fields: fields());
      expect(
        source.cards[1].properties.map((property) => property.fieldId),
        ['notes', 'status'],
      );
      source.dispose();
    });

    test('a hidden column is left off the slide', () {
      final source = SlideSource(viewId: 'view')
        ..updateSpec(const SlideSpec(hiddenColumns: ['status']))
        ..readForTest(table(), fields: fields());
      expect(
        source.cards[1].properties.map((property) => property.fieldId),
        ['notes'],
      );
      source.dispose();
    });
  });
}
