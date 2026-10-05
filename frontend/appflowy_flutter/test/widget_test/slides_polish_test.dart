import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/slides/slide_card.dart';
import 'package:appflowy/shared/slides/slide_deck.dart';
import 'package:appflowy/shared/slides/slide_stage.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/property_values.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/slides/slide_source.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

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

RowMetaPB _meta(String id, CoverTypePB type, String data) => RowMetaPB()
  ..id = id
  ..cover = (RowCoverPB()
    ..coverType = type
    ..data = data);

const _rows = ['gradient', 'asset', 'colour', 'file', 'plain', 'removed'];

RepeatedRowTextPB _table() => RepeatedRowTextPB()
  ..fieldIds.addAll(['name', 'picture', 'files'])
  ..rows.addAll([
    for (final id in _rows)
      RowTextPB()
        ..rowId = id
        ..cells.addAll([
          id,
          id == 'plain' ? 'https://example.com/hero.png' : '',
          'brief.pdf',
        ]),
  ]);

List<FieldPB> _fields() => [
      _field('name', 'Name', FieldType.RichText, primary: true),
      _field('picture', 'Picture', FieldType.URL),
      _field('files', 'Files', FieldType.Media),
    ];

List<RowMetaPB> _metas() => [
      _meta(
        'gradient',
        CoverTypePB.GradientCover,
        FlowyGradientColor.gradient3.id,
      ),
      _meta('asset', CoverTypePB.AssetCover, 'n2'),
      _meta('colour', CoverTypePB.ColorCover, '0xffe8e0ff'),
      _meta('file', CoverTypePB.FileCover, r'C:\covers\a.png'),
      RowMetaPB()..id = 'plain',
      _meta('removed', CoverTypePB.FileCover, ''),
    ];

Widget _host(Widget child, {Size size = const Size(1100, 760)}) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: size.width, height: size.height, child: child),
        ),
      ),
    );

void main() {
  group('a slide wears what its row page wears', () {
    test('every kind of cover is kept, and an undressed page its gradient', () {
      final source = SlideSource(viewId: 'view')
        ..readForTest(_table(), fields: _fields(), metas: _metas());
      addTearDown(source.dispose);
      final byRow = {for (final card in source.cards) card.rowId: card};

      expect(
        byRow['gradient']!.cover,
        TableCover(
          kind: TableCoverKind.gradient,
          value: FlowyGradientColor.gradient3.id,
        ),
      );
      expect(
        byRow['asset']!.cover,
        const TableCover(kind: TableCoverKind.asset, value: 'n2'),
      );
      expect(byRow['colour']!.cover!.kind, TableCoverKind.colour);
      expect(
        byRow['file']!.cover,
        const TableCover(
          kind: TableCoverKind.picture,
          value: r'C:\covers\a.png',
        ),
      );
      // Nobody chose a cover: the page falls back to its own gradient.
      expect(byRow['plain']!.cover, isNull);
      expect(
        byRow['plain']!.fallbackCover,
        TableCover(
          kind: TableCoverKind.gradient,
          value: FlowyGradientColor.forSeed('plain').id,
        ),
      );
      // A cover taken off on purpose leaves nothing at all.
      expect(byRow['removed']!.cover, isNull);
      expect(byRow['removed']!.fallbackCover, isNull);
      expect(byRow['gradient']!.fallbackCover, isNull);
    });

    test('a picture in the chosen cover column wins over the row cover', () {
      final source = SlideSource(viewId: 'view')
        ..updateSpec(const SlideSpec(coverColumn: 'picture'))
        ..readForTest(_table(), fields: _fields(), metas: _metas());
      addTearDown(source.dispose);
      final plain = source.cards.firstWhere((card) => card.rowId == 'plain');
      expect(
        plain.cover,
        const TableCover(
          kind: TableCoverKind.picture,
          value: 'https://example.com/hero.png',
        ),
      );
    });

    test('a media column is read as files, not as their names', () {
      final source = SlideSource(viewId: 'view')
        ..readForTest(_table(), fields: _fields(), metas: _metas());
      addTearDown(source.dispose);
      final properties = source.cards.first.properties;
      expect(
        properties.firstWhere((p) => p.fieldId == 'files').isMedia,
        isTrue,
      );
    });
  });

  group('a slide card', () {
    testWidgets('fits a short deck without spilling', (tester) async {
      final card = SlideCardData(
        rowId: 'row',
        title: 'Aurora launch with a title long enough to wrap twice over',
        subtitle: 'In progress',
        icon: 'A',
        cover: const TableCover(kind: TableCoverKind.asset, value: 'n2'),
        lastModified: DateTime(2026, 10, 2),
        properties: const [
          SlideProperty(
            fieldId: 'progress',
            name: 'Progress',
            value: '64%',
            kind: SlidePropertyKind.progress,
            fraction: 0.64,
          ),
          SlideProperty(
            fieldId: 'status',
            name: 'Status',
            value: 'In progress',
            kind: SlidePropertyKind.badge,
          ),
        ],
      );
      for (final height in [240.0, 300.0, 420.0, 620.0]) {
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) => SlideCard(
                card: card,
                palette: slidePaletteOf(context),
                size: Size(520, height),
                live: true,
              ),
            ),
            size: Size(520, height),
          ),
        );
        await tester.pump();
        expect(tester.takeException(), isNull, reason: 'at $height');
        expect(find.byType(PropertyPill), findsWidgets);
      }
    });

    testWidgets('names each property with the mark of its kind',
        (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) => SlideCard(
              card: const SlideCardData(
                rowId: 'row',
                title: 'Nimbus',
                properties: [
                  SlideProperty(
                    fieldId: 'due',
                    name: 'Due',
                    value: 'Oct 18, 2026',
                    kind: SlidePropertyKind.date,
                  ),
                  SlideProperty(
                    fieldId: 'files',
                    name: 'Files',
                    value: 'brief.pdf',
                    kind: SlidePropertyKind.files,
                  ),
                ],
              ),
              palette: slidePaletteOf(context),
              size: const Size(560, 620),
              live: true,
            ),
          ),
        ),
      );
      await tester.pump();

      final labels =
          tester.widgetList<PropertyLabel>(find.byType(PropertyLabel));
      expect(
        labels.map((label) => label.icon),
        [Icons.calendar_today_rounded, Icons.attach_file_rounded],
      );
      final file = tester.widget<WorkspaceGlyph>(
        find.descendant(
          of: find.byType(PropertyFileTile),
          matching: find.byType(WorkspaceGlyph),
        ),
      );
      expect(file.name, 'file-pdf');
    });

    testWidgets('shows the status under the title once, not again below',
        (tester) async {
      Future<void> show(SlideCardData card) async {
        await tester.pumpWidget(
          _host(
            Builder(
              builder: (context) => SlideCard(
                card: card,
                palette: slidePaletteOf(context),
                size: const Size(560, 620),
                live: true,
              ),
            ),
          ),
        );
        await tester.pump();
      }

      await show(
        const SlideCardData(
          rowId: 'row',
          title: 'Nimbus',
          subtitle: 'Done',
          properties: [
            SlideProperty(
              fieldId: 'status',
              name: 'Status',
              value: 'Done',
              kind: SlidePropertyKind.badge,
            ),
            SlideProperty(
              fieldId: 'tags',
              name: 'Tags',
              value: 'Done',
              kind: SlidePropertyKind.badge,
            ),
          ],
        ),
      );
      // The status leads under the title; a later field with the same
      // words is still its own fact.
      expect(find.text('Status'), findsNothing);
      expect(find.text('Tags'), findsOneWidget);
      expect(find.text('Done'), findsNWidgets(2));

      await show(
        const SlideCardData(
          rowId: 'row',
          title: 'Nimbus',
          subtitle: 'Priya Raman, Leo Park',
          properties: [
            SlideProperty(
              fieldId: 'owner',
              name: 'Owner',
              value: 'Priya Raman, Leo Park',
              kind: SlidePropertyKind.person,
            ),
          ],
        ),
      );
      // People lead as faces, not as a comma-joined pill.
      expect(find.text('Owner'), findsNothing);
      expect(find.byType(PropertyPeople), findsOneWidget);
      expect(find.text('Priya Raman'), findsOneWidget);
      expect(find.text('Priya Raman, Leo Park'), findsNothing);
      expect(tester.takeException(), isNull);
    });
  });

  testWidgets('the deck chrome draws every control with the app glyphs',
      (tester) async {
    final source = SlideSource(viewId: 'view')
      ..readForTest(_table(), fields: _fields(), metas: _metas());
    addTearDown(source.dispose);
    await tester.pumpWidget(
      _host(
        SlideStage(
          viewId: 'view',
          spec: const SlideSpec(),
          onSpecChanged: (_) {},
          source: source,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));

    final controls = find.byType(SlideControlButton);
    expect(controls, findsWidgets);
    expect(
      find.descendant(of: controls, matching: find.byType(WorkspaceGlyph)),
      findsNWidgets(tester.widgetList(controls).length),
    );
    expect(
      find.descendant(of: controls, matching: find.byType(Icon)),
      findsNothing,
    );
    // Where in the deck the reader is.
    expect(find.text('1 / ${_rows.length}'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the rail and counter follow every slide the deck turns to',
      (tester) async {
    final source = SlideSource(viewId: 'view')
      ..readForTest(_table(), fields: _fields(), metas: _metas());
    addTearDown(source.dispose);
    final saved = <int>[];
    await tester.pumpWidget(
      _host(
        SlideStage(
          viewId: 'view',
          spec: const SlideSpec(),
          onSpecChanged: (spec) => saved.add(spec.index),
          source: source,
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('1 / ${_rows.length}'), findsOneWidget);

    final next = find.byWidgetPredicate(
      (widget) =>
          widget is SlideControlButton &&
          widget.icon == Icons.chevron_right_rounded,
    );
    // A second press while the first is still gliding goes one further,
    // rather than repeating the slide the deck was leaving.
    await tester.tap(next);
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(next);
    for (var i = 0; i < 50; i++) {
      await tester.pump(const Duration(milliseconds: 16));
    }
    expect(find.text('3 / ${_rows.length}'), findsOneWidget);
    expect(tester.widget<SlideRail>(find.byType(SlideRail)).index, 2);

    // The place is kept once the reader has settled on it.
    expect(saved, isEmpty);
    await tester.pump(const Duration(seconds: 1));
    expect(saved, [2]);
    expect(tester.takeException(), isNull);
  });

  group('values every table view shares', () {
    test('a link reads as its site, then the rest', () {
      expect(
        splitPropertyLink('https://www.aurora.example.com/launch?x=1'),
        ('aurora.example.com', '/launch?x=1'),
      );
      expect(splitPropertyLink('https://example.com/'), ('example.com', ''));
      expect(splitPropertyLink('not a link'), ('not a link', ''));
    });

    testWidgets('a table card draws progress, files and places polished',
        (tester) async {
      await tester.pumpWidget(
        _host(
          Builder(
            builder: (context) {
              final palette = tableViewPaletteOf(context);
              return ListView(
                children: [
                  for (final property in const [
                    TableProperty(
                      fieldId: 'complete',
                      name: 'Complete',
                      value: '100%',
                      kind: TablePropertyKind.progress,
                      fraction: 1,
                    ),
                    TableProperty(
                      fieldId: 'files',
                      name: 'Files',
                      value: 'brief.pdf, budget.xlsx',
                      kind: TablePropertyKind.files,
                    ),
                    TableProperty(
                      fieldId: 'place',
                      name: 'Venue',
                      value: '28.61390, 77.20900',
                      kind: TablePropertyKind.location,
                    ),
                    TableProperty(
                      fieldId: 'done',
                      name: 'Shipped',
                      value: 'Yes',
                      kind: TablePropertyKind.checkbox,
                    ),
                  ])
                    SizedBox(
                      width: 380,
                      child: TablePropertyView(
                        property: property,
                        palette: palette,
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(PropertyProgress), findsOneWidget);
      expect(find.text('100%'), findsOneWidget);
      expect(find.byType(PropertyFileTile), findsNWidgets(2));
      // Not live, so the place is framed without fetching map pictures.
      expect(find.byType(PropertyMap), findsOneWidget);
      expect(find.text('28.61390, 77.20900'), findsOneWidget);
      expect(find.byType(PropertyCheck), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
