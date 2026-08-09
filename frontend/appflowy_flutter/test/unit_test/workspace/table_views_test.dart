import 'dart:convert';

import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/mailbox_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/table_views/timeline_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:flutter_test/flutter_test.dart';

FieldPB _field(
  String id,
  String name,
  FieldType type,
) =>
    FieldPB()
      ..id = id
      ..name = name
      ..fieldType = type;

TableRowCard _card(
  String id,
  String title, {
  Map<String, String> cells = const {},
  DateTime? starts,
  DateTime? ends,
}) =>
    TableRowCard(
      rowId: id,
      title: title,
      startsAt: starts,
      endsAt: ends,
      properties: [
        for (final entry in cells.entries)
          TableProperty(
            fieldId: entry.key,
            name: entry.key,
            value: entry.value,
            kind: TablePropertyKind.text,
          ),
      ],
    );

void main() {
  group('reading a cell', () {
    test('a checklist reads as how far along it is', () {
      final field = _field('f', 'Steps', FieldType.Checklist);
      expect(
        classifyTableProperty(field: field, value: '3/8'),
        TablePropertyKind.progress,
      );
      expect(tableFractionOf(field: field, value: '3/8'), closeTo(0.375, 1e-9));
    });

    test('a column named for a person reads as one', () {
      expect(
        classifyTableProperty(
          field: _field('f', 'Assignee', FieldType.MultiSelect),
          value: 'Ada, Grace',
        ),
        TablePropertyKind.person,
      );
      expect(
        classifyTableProperty(
          field: _field('f', 'Labels', FieldType.MultiSelect),
          value: 'red, blue',
        ),
        TablePropertyKind.tags,
      );
    });

    test('a number is only a bar when something says how full', () {
      final plain = _field('f', 'Count', FieldType.Number);
      expect(
        classifyTableProperty(field: plain, value: '42'),
        TablePropertyKind.number,
      );
      expect(
        classifyTableProperty(
          field: plain,
          value: '42',
          facts: const TableColumnFacts(lowest: 0, highest: 84),
        ),
        TablePropertyKind.progress,
      );
      expect(
        classifyTableProperty(
          field: _field('f', 'Priority', FieldType.Number),
          value: '4',
        ),
        TablePropertyKind.rating,
      );
    });

    test('a link that ends in a picture is a picture', () {
      final url = _field('f', 'Link', FieldType.URL);
      expect(
        classifyTableProperty(field: url, value: 'https://a.test/b.png?w=40'),
        TablePropertyKind.image,
      );
      expect(
        classifyTableProperty(field: url, value: 'https://a.test/b'),
        TablePropertyKind.link,
      );
    });

    test('a score out of ten is halved rather than clipped', () {
      expect(tableRatingOf('9'), 5);
      expect(tableRatingOf('7'), 4);
      expect(tableRatingOf('3'), 3);
      expect(tableRatingOf('nope'), isNull);
    });

    test('initials fall back to a single letter and then a question mark', () {
      expect(tableInitialsOf('Ada Lovelace'), 'AL');
      expect(tableInitialsOf('Ada'), 'AD');
      expect(tableInitialsOf('A'), 'A');
      expect(tableInitialsOf('   '), '?');
    });

    test('a written date is read back', () {
      expect(parseTableDate('2024-03-09'), DateTime(2024, 3, 9));
      expect(parseTableDate('2024-03-09 → 2024-03-11'), DateTime(2024, 3, 9));
      expect(parseTableDate('03/09/2024'), DateTime(2024, 3, 9));
      expect(parseTableDate('2024/03/09'), DateTime(2024, 3, 9));
      expect(parseTableDate('not a date'), isNull);
    });

    test('a date written the way the table shows it is read back', () {
      // This is the shape AppFlowy's own date columns are formatted in.
      expect(parseTableDate('Aug 04, 2026'), DateTime(2026, 8, 4));
      expect(parseTableDate('August 4, 2026'), DateTime(2026, 8, 4));
      expect(parseTableDate('4 Aug 2026'), DateTime(2026, 8, 4));
      expect(parseTableDate('Sep 2026'), DateTime(2026, 9));
      expect(
        parseTableDate('Aug 04, 2026 → Aug 06, 2026'),
        DateTime(2026, 8, 4),
      );
      expect(parseTableDate('Someday, 2026'), isNull);
    });

    test('a time of day is kept when one is written', () {
      expect(
        parseTableDate('Aug 04, 2026 14:30'),
        DateTime(2026, 8, 4, 14, 30),
      );
      expect(
        parseTableDate('Aug 04, 2026 2:30 PM'),
        DateTime(2026, 8, 4, 14, 30),
      );
      expect(
        parseTableDate('Aug 04, 2026 12:05 AM'),
        DateTime(2026, 8, 4, 0, 5),
      );
    });
  });

  group('what the reader asked for', () {
    final cards = [
      _card('1', 'One', cells: {'c': 'Beta', 'n': '10'}),
      _card('2', 'Two', cells: {'c': '', 'n': '2'}),
      _card('3', 'Three', cells: {'c': 'Alpha', 'n': '30'}),
    ];

    test('an empty cell sinks either way round', () {
      final up = applyTableQuery(
        cards,
        const TableQuery(sortColumn: 'c'),
      );
      expect(up.map((card) => card.rowId), ['3', '1', '2']);

      final down = applyTableQuery(
        cards,
        const TableQuery(
          sortColumn: 'c',
          direction: TableSortDirection.descending,
        ),
      );
      expect(down.map((card) => card.rowId), ['1', '3', '2']);
    });

    test('numbers order by size rather than by letter', () {
      final sorted = applyTableQuery(cards, const TableQuery(sortColumn: 'n'));
      expect(sorted.map((card) => card.rowId), ['2', '1', '3']);
    });

    test('filtering on a column with no value keeps whatever is filled', () {
      final filled =
          applyTableQuery(cards, const TableQuery(filterColumn: 'c'));
      expect(filled.map((card) => card.rowId), ['1', '3']);
    });

    test('filtering matches one of several values in a cell', () {
      final many = [
        _card('1', 'One', cells: {'c': 'red, blue'}),
        _card('2', 'Two', cells: {'c': 'green'}),
      ];
      final result = applyTableQuery(
        many,
        const TableQuery(filterColumn: 'c', filterValue: 'blue'),
      );
      expect(result.map((card) => card.rowId), ['1']);
    });

    test('searching never removes a row, it only reports matches', () {
      const query = TableQuery(search: 'three');
      expect(applyTableQuery(cards, query).length, 3);
      expect(tableMatchesOf(cards, 'three'), {'3'});
    });

    test('whatever could not be gathered is gathered last', () {
      final groups = groupTableRows(cards, 'c', ungrouped: 'Rest');
      expect(groups.map((group) => group.label), ['Beta', 'Alpha', 'Rest']);
      expect(groups.last.rows.single.rowId, '2');
    });

    test('no column at all leaves one unnamed group', () {
      final groups = groupTableRows(cards, '');
      expect(groups.single.label, '');
      expect(groups.single.rows.length, 3);
    });
  });

  group('placing rows in time', () {
    test('rows that do not overlap share a lane', () {
      final events = layOutTimeline(
        [
          (
            rowId: 'a',
            start: DateTime(2024, 3),
            end: DateTime(2024, 3, 5),
          ),
          (
            rowId: 'b',
            start: DateTime(2024, 3, 20),
            end: DateTime(2024, 3, 25),
          ),
        ],
        dayWidth: 56,
      );
      expect(events.map((event) => event.lane), [0, 0]);
    });

    test('rows that overlap are stacked', () {
      final events = layOutTimeline(
        [
          (
            rowId: 'a',
            start: DateTime(2024, 3),
            end: DateTime(2024, 3, 20),
          ),
          (
            rowId: 'b',
            start: DateTime(2024, 3, 5),
            end: DateTime(2024, 3, 25),
          ),
          (
            rowId: 'c',
            start: DateTime(2024, 3, 8),
            end: DateTime(2024, 3, 9),
          ),
        ],
        dayWidth: 56,
      );
      expect(events.map((event) => event.lane), [0, 1, 2]);
    });

    test('a row with no end is a milestone', () {
      final events = layOutTimeline(
        [(rowId: 'a', start: DateTime(2024, 3), end: null)],
        dayWidth: 56,
      );
      expect(events.single.isMilestone, isTrue);
      expect(events.single.end, events.single.start);
    });

    test('the window has a margin either side', () {
      final window = timelineWindowFor(
        [DateTime(2024, 3, 10), DateTime(2024, 3, 20)],
        dayWidth: 10,
        margin: 5,
      );
      expect(window.first, DateTime(2024, 3, 5));
      expect(window.last, DateTime(2024, 3, 25));
      expect(window.days, 21);
      expect(window.width, 210);
    });

    test('a moment and its distance from the edge agree', () {
      final window = TimelineWindow(
        first: DateTime(2024, 3),
        last: DateTime(2024, 3, 31),
        dayWidth: 20,
      );
      expect(window.xOf(DateTime(2024, 3, 6)), 100);
      expect(window.whenAt(100), DateTime(2024, 3, 6));
    });

    test('a very wide window does not draw a million marks', () {
      final window = TimelineWindow(
        first: DateTime(1900),
        last: DateTime(2400),
        dayWidth: 1,
      );
      expect(timelineTicks(window, TimelineScale.day).length, 600);
    });

    test('zooming steps through the scales and stops', () {
      expect(TimelineScale.month.closer, TimelineScale.week);
      expect(TimelineScale.day.closer, TimelineScale.day);
      expect(TimelineScale.year.further, TimelineScale.year);
    });
  });

  group('sharing out a wall of cards', () {
    test('a width that nearly fits another card rounds up to it', () {
      // 3 cards of 272 with 18 between them want 880; 856 is 2.97 cards.
      final layout = galleryLayoutFor(available: 856, target: 272);
      expect(layout.columns, 3);
      expect(layout.cardWidth, closeTo(273.33, 0.01));
    });

    test('a card never grows past a quarter over its target', () {
      final layout = galleryLayoutFor(available: 700, target: 272);
      expect(layout.columns, 3);
      expect(layout.cardWidth, lessThan(272 * 1.25));
    });

    test('a narrow window still shows one card', () {
      final layout = galleryLayoutFor(available: 120, target: 272);
      expect(layout.columns, 1);
    });

    test('a card is a little taller than it is wide, within reason', () {
      expect(const GalleryLayout(columns: 1, cardWidth: 300).cardHeight, 348);
      expect(const GalleryLayout(columns: 1, cardWidth: 100).cardHeight, 210);
      expect(const GalleryLayout(columns: 1, cardWidth: 600).cardHeight, 420);
    });

    test('the cover shrinks with the card so the writing still fits', () {
      const small = GalleryLayout(columns: 1, cardWidth: 208);
      const large = GalleryLayout(columns: 1, cardWidth: 348);
      expect(small.coverHeight, lessThan(large.coverHeight));
      // Whatever the size, the cover leaves room for a title and a fact.
      for (final layout in [small, large]) {
        expect(layout.cardHeight - layout.coverHeight, greaterThan(110));
      }
    });

    test('a card leads with the page it stands for', () {
      const spec = GallerySpec();
      expect(spec.face, GalleryCardFace.page);
      expect(spec.face.showsCover, isFalse);
      expect(
        spec.toJson(),
        isEmpty,
        reason: 'the default is written by leaving it out',
      );
      expect(
        GallerySpec.fromJson(const {}).face,
        GalleryCardFace.page,
      );
      expect(GalleryCardFace.fromId('picture'), GalleryCardFace.cover);
      expect(GalleryCardFace.fromId('nonsense'), GalleryCardFace.page);
      expect(
        GallerySpec.fromJson(
          const GallerySpec(face: GalleryCardFace.portrait).toJson(),
        ).face,
        GalleryCardFace.portrait,
      );
    });
  });

  group('what a card is asked to show', () {
    test('an unread view shows its cover', () {
      expect(CardPreviewSetting.fromExtra('').mode, CardPreviewMode.cover);
      expect(CardPreviewSetting.fromExtra('{oops').mode, CardPreviewMode.cover);
      expect(CardPreviewMode.fromId(null), CardPreviewMode.cover);
      expect(CardPreviewMode.fromId('nonsense'), CardPreviewMode.cover);
      expect(CardPreviewMode.fromId('page'), CardPreviewMode.pageContent);
    });

    test('the choice survives a trip through the view extra', () {
      for (final mode in CardPreviewMode.values) {
        final extra = CardPreviewSetting(mode: mode).mergeIntoExtra('');
        expect(CardPreviewSetting.fromExtra(extra).mode, mode);
      }
    });

    test('it sits beside the other marks rather than over them', () {
      const mark = TableViewMark(kind: TableViewKind.gallery);
      final extra = const CardPreviewSetting(mode: CardPreviewMode.pageContent)
          .mergeIntoExtra(mark.mergeIntoExtra(''));

      expect(TableViewMark.fromExtra(extra, TableViewKind.gallery), isNotNull);
      expect(
        CardPreviewSetting.fromExtra(extra).mode,
        CardPreviewMode.pageContent,
      );
    });

    test('a reading from a later version is not guessed at', () {
      final extra = jsonEncode({
        CardPreviewSetting.envelopeKey: {'version': 99, 'mode': 'page'},
      });
      expect(CardPreviewSetting.fromExtra(extra).mode, CardPreviewMode.cover);
    });
  });

  group('laying out a form', () {
    final fields = [
      _field('a', 'Name', FieldType.RichText),
      _field('b', 'Created', FieldType.CreatedTime),
      _field('c', 'Status', FieldType.SingleSelect),
      _field('d', 'Notes', FieldType.RichText),
    ];

    test('a column the table works out for itself is never asked for', () {
      final asked = formFieldsOf(fields, const FormSpec());
      expect(asked.map((field) => field.id), ['a', 'c', 'd']);
    });

    test('a hidden column is not asked for either', () {
      final asked = formFieldsOf(
        fields,
        const FormSpec(hiddenColumns: ['c']),
      );
      expect(asked.map((field) => field.id), ['a', 'd']);
    });

    test('with no sections every field lands in one', () {
      final sections = formSectionsOf(fields, const FormSpec());
      expect(sections.single.fieldIds, ['a', 'c', 'd']);
    });

    test('a column added later joins the last section', () {
      final sections = formSectionsOf(
        fields,
        const FormSpec(
          sections: [
            FormSection(id: '1', title: 'Who', fieldIds: ['a']),
            FormSection(id: '2', title: 'What', fieldIds: ['c']),
          ],
        ),
      );
      expect(sections.first.fieldIds, ['a']);
      expect(sections.last.fieldIds, ['c', 'd']);
    });

    test('a blank answer to a required column is reported', () {
      const spec = FormSpec(requiredColumns: ['a', 'c']);
      expect(
        missingRequiredFields(spec, {'a': 'Ada', 'c': '   '}),
        ['c'],
      );
      expect(missingRequiredFields(spec, {'a': 'Ada', 'c': 'Done'}), isEmpty);
    });

    test('a control is chosen for every kind of column', () {
      expect(
        formControlOf(_field('f', 'Done', FieldType.Checkbox)),
        FormControl.toggle,
      );
      expect(
        formControlOf(_field('f', 'When', FieldType.DateTime)),
        FormControl.date,
      );
      expect(
        formControlOf(_field('f', 'Stage', FieldType.SingleSelect)),
        FormControl.choice,
      );
      expect(
        formControlOf(_field('f', 'Score', FieldType.Number)),
        FormControl.rating,
      );
      expect(
        formControlOf(_field('f', 'Total', FieldType.Number)),
        FormControl.number,
      );
    });
  });

  group('the mark a view wears', () {
    test('an envelope survives being written and read', () {
      const mark = TableViewMark(
        kind: TableViewKind.timeline,
        settings: {'scale': 'week'},
      );
      final extra = mark.mergeIntoExtra('');
      final read = TableViewMark.fromExtra(extra, TableViewKind.timeline);
      expect(read, isNotNull);
      expect(read!.settings['scale'], 'week');
      expect(read.showTable, isFalse);
    });

    test('one view of a table does not read another view s envelope', () {
      final extra = TableViewMark.newExtra(TableViewKind.feed);
      expect(TableViewMark.fromExtra(extra, TableViewKind.form), isNull);
      expect(TableViewMark.kindOf(extra), TableViewKind.feed);
    });

    test('whatever else the view already remembered is kept', () {
      const first = TableViewMark(kind: TableViewKind.gallery);
      const second = TableViewMark(kind: TableViewKind.feed);
      final extra = second.mergeIntoExtra(first.mergeIntoExtra(''));
      expect(TableViewMark.fromExtra(extra, TableViewKind.gallery), isNotNull);
      expect(TableViewMark.fromExtra(extra, TableViewKind.feed), isNotNull);
    });

    test('taking the mark off leaves a plain table', () {
      final extra = TableViewMark.newExtra(TableViewKind.form);
      final without = TableViewMark.removeFromExtra(extra, TableViewKind.form);
      expect(TableViewMark.kindOf(without), isNull);
    });

    test('an envelope from a later version is not guessed at', () {
      const extra = '{"appflowy_form":{"version":99,"spec":{}}}';
      expect(TableViewMark.fromExtra(extra, TableViewKind.form), isNull);
    });

    test('every kind has its own key and its own mark', () {
      final keys = TableViewKind.values.map((kind) => kind.envelopeKey).toSet();
      expect(keys.length, TableViewKind.values.length);
      for (final kind in TableViewKind.values) {
        expect(tableViewIcon(kind), isNotNull);
      }
    });
  });

  group('reading a table as a mailbox', () {
    test('an arrangement survives a round trip', () {
      const spec = MailboxSpec(
        subjectColumn: 'subject',
        senderColumn: 'owner',
        dateColumn: 'sent',
        snippetColumn: 'note',
        propertyColumns: ['status'],
        density: MailboxDensity.compact,
        showReader: false,
        groupByDate: false,
      );

      expect(MailboxSpec.fromJson(spec.toJson()), spec);
    });

    test('a mailbox nobody has arranged reads with a pane and by date', () {
      const spec = MailboxSpec();

      expect(spec.toJson(), isEmpty);
      expect(spec.showReader, isTrue);
      expect(spec.groupByDate, isTrue);
      expect(spec.density.showsSnippet, isTrue);
    });

    test('the bands are the ones a mail client reads by', () {
      final today = DateTime(2026, 8, 6);

      expect(mailboxBandOf(today, today: today), MailboxBand.today);
      expect(
        mailboxBandOf(DateTime(2026, 8, 5, 23), today: today),
        MailboxBand.yesterday,
      );
      expect(
        mailboxBandOf(DateTime(2026, 8, 2), today: today),
        MailboxBand.thisWeek,
      );
      expect(
        mailboxBandOf(DateTime(2026, 7, 20), today: today),
        MailboxBand.thisMonth,
      );
      expect(
        mailboxBandOf(DateTime(2025, 1, 2), today: today),
        MailboxBand.earlier,
      );
      expect(mailboxBandOf(null, today: today), MailboxBand.undated);
    });

    test('rows keep their order and only the breaks are added', () {
      final now = DateTime(2026, 8, 6, 10);
      final rows = <({String id, DateTime? at})>[
        (id: 'a', at: DateTime(2026, 8, 6, 9)),
        (id: 'b', at: DateTime(2026, 8, 6, 8)),
        (id: 'c', at: DateTime(2026, 8, 5, 8)),
        (id: 'd', at: null),
      ];

      final sections = groupMailboxRows(
        rows,
        dateOf: (row) => row.at,
        now: now,
      );

      expect(
        sections.map((section) => section.band).toList(),
        [MailboxBand.today, MailboxBand.yesterday, MailboxBand.undated],
      );
      expect(sections.first.rows.map((row) => row.id).toList(), ['a', 'b']);
      expect(sections.last.rows.single.id, 'd');
    });
  });
}
