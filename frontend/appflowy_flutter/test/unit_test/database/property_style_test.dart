import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/column_heading_menu.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/row/cell_menu.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/plugins/database/widgets/field/property_type_picker.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/field_entities.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('a column style survives a round trip', () {
    test('through the view extra, beside whatever else is stored there', () {
      const other = '{"appflowy_chart":{"version":1}}';
      const styles = PropertyStyles(
        byField: {
          'f1': PropertyStyle(
            kind: PropertyStyleKind.progress,
            settings: {'maximum': 8.0},
          ),
        },
      );

      final extra = styles.mergeIntoExtra(other);
      final decoded = jsonDecode(extra) as Map<String, dynamic>;

      // The mark it was written beside is untouched.
      expect(decoded['appflowy_chart'], isNotNull);

      final read = PropertyStyles.fromExtra(extra);
      expect(read['f1']?.kind, PropertyStyleKind.progress);
      expect(read['f1']?.maximum, 8);
    });

    test('an unmarked view reads as no styles at all', () {
      expect(PropertyStyles.fromExtra('').byField, isEmpty);
      expect(PropertyStyles.fromExtra('not json').byField, isEmpty);
      expect(
        PropertyStyles.fromExtra('{"appflowy_property_styles":3}').byField,
        isEmpty,
      );
    });

    test('clearing a column removes the envelope rather than emptying it', () {
      const styles = PropertyStyles(
        byField: {'f1': PropertyStyle(kind: PropertyStyleKind.counter)},
      );
      final extra = styles.mergeIntoExtra('');
      expect(extra, contains(PropertyStyles.envelopeKey));

      final cleared = styles.withField('f1', null).mergeIntoExtra(extra);
      expect(cleared, isNot(contains(PropertyStyles.envelopeKey)));
    });

    test('a plain style is stored as no style', () {
      const styles = PropertyStyles();
      final next = styles.withField(
        'f1',
        const PropertyStyle(kind: PropertyStyleKind.plain),
      );
      expect(next.byField, isEmpty);
    });

    test('a plain column keeps an alignment of its own', () {
      const styles = PropertyStyles();
      final next = styles.withField(
        'f1',
        const PropertyStyle(
          kind: PropertyStyleKind.plain,
          settings: {'align': 'center'},
        ),
      );
      expect(next['f1']?.align, PropertyAlign.center);

      final read = PropertyStyles.fromExtra(next.mergeIntoExtra(''));
      expect(read['f1']?.align, PropertyAlign.center);
      expect(read['f1']?.kind, PropertyStyleKind.plain);
    });

    test('an unset alignment is not the same as left', () {
      const style = PropertyStyle(kind: PropertyStyleKind.progress);
      expect(style.align, isNull);
      expect(style.withSetting('align', 'right').align, PropertyAlign.right);
      expect(
        style.withSetting('align', 'sideways').align,
        isNull,
      );
    });

    test('an alignment answers for a box and for text alike', () {
      expect(PropertyAlign.center.alignment, Alignment.center);
      expect(PropertyAlign.right.textAlign, TextAlign.right);
      expect(PropertyAlign.left.rowAlignment, MainAxisAlignment.start);
      expect(PropertyAlign.right.wrapAlignment, WrapAlignment.end);
    });

    test('a thumbnail size is read back, and grows with the choice', () {
      expect(
        PropertyThumbnailSize.fromValue('large'),
        PropertyThumbnailSize.large,
      );
      expect(
        PropertyThumbnailSize.fromValue('enormous'),
        PropertyThumbnailSize.medium,
      );
      expect(
        PropertyThumbnailSize.small.extent,
        lessThan(PropertyThumbnailSize.large.extent),
      );
      expect(
        const PropertyStyle(kind: PropertyStyleKind.media).thumbnailSize,
        PropertyThumbnailSize.medium,
      );
    });

    test('settings are kept as they were written', () {
      const style = PropertyStyle(
        kind: PropertyStyleKind.button,
        settings: {'label': 'Open', 'action': 'openUrl', 'target': 'a.com'},
      );
      final read = PropertyStyle.fromJson(style.toJson());
      expect(read.kind, PropertyStyleKind.button);
      expect(read.buttonLabel, 'Open');
      expect(read.buttonAction, PropertyButtonAction.openUrl);
      expect(read.buttonTarget, 'a.com');
    });

    test('a nonsense maximum falls back rather than dividing by zero', () {
      const style = PropertyStyle(
        kind: PropertyStyleKind.progress,
        settings: {'maximum': 0},
      );
      expect(style.maximum, 100);
      expect(
        const PropertyStyle(
          kind: PropertyStyleKind.counter,
          settings: {'step': 0},
        ).step,
        1,
      );
    });
  });

  group('what the picker offers', () {
    test('every entry has its own id', () {
      final ids = propertyTypeEntries().map((entry) => entry.id).toList();
      expect(ids.toSet().length, ids.length);
    });

    test('the interactive types are text columns underneath', () {
      final interactive = propertyTypeEntries()
          .where((entry) => entry.group == PropertyTypeGroup.interactive);
      expect(interactive.length, 3);
      for (final entry in interactive) {
        expect(entry.fieldType, FieldType.RichText, reason: entry.id);
        expect(entry.style, isNotNull, reason: entry.id);
      }
    });

    test('every media type is the attachment column, narrowed', () {
      final media = propertyTypeEntries()
          .where((entry) => entry.group == PropertyTypeGroup.media)
          .toList();
      expect(media.length, PropertyMediaKind.values.length);
      for (final entry in media) {
        expect(entry.fieldType, FieldType.Media, reason: entry.id);
      }
      // The generic one carries no note, so it is a plain attachment column.
      expect(media.first.style, isNull);
    });

    test('a stored column maps back to the row that made it', () {
      final progress = propertyTypeEntryFor(
        fieldType: FieldType.RichText,
        style: const PropertyStyle(kind: PropertyStyleKind.progress),
      );
      expect(progress?.id, 'progress');

      final plainText = propertyTypeEntryFor(fieldType: FieldType.RichText);
      expect(plainText?.id, 'text');

      final bookmark = propertyTypeEntryFor(
        fieldType: FieldType.URL,
        style: const PropertyStyle(kind: PropertyStyleKind.link),
      );
      expect(bookmark?.id, 'bookmark');

      expect(propertyTypeEntryFor(fieldType: FieldType.URL)?.id, 'url');
    });

    test('a marked location column is named as one', () {
      final entry = propertyTypeEntryFor(
        fieldType: FieldType.RichText,
        isLocation: true,
      );
      expect(entry?.id, 'location');
    });

    test('one media kind does not answer for another', () {
      final video = propertyTypeEntryFor(
        fieldType: FieldType.Media,
        style: const PropertyStyle(
          kind: PropertyStyleKind.media,
          settings: {'media': 'video'},
        ),
      );
      expect(video?.id, 'media_video');
    });

    test('searching narrows the list', () {
      final matches =
          propertyTypeEntries().where((entry) => entry.matches('progress'));
      expect(matches.length, 1);
      expect(
        propertyTypeEntries().where((e) => e.matches('')).length,
        propertyTypeEntries().length,
      );
    });
  });

  group('a progress cell survives how a grid row is measured', () {
    // A grid row is laid out inside an IntrinsicHeight, and a LayoutBuilder
    // cannot be measured that way — it threw and took the whole table with it.
    Widget row({required Widget child}) => MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 400,
              child: IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(width: 120, height: 36),
                    Expanded(child: child),
                  ],
                ),
              ),
            ),
          ),
        );

    testWidgets('lays out inside an IntrinsicHeight', (tester) async {
      await tester.pumpWidget(
        row(
          child: const PropertyProgressTrack(
            fraction: 0.6,
            fill: Color(0xFF2F7FE4),
            track: Color(0x11000000),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.byType(PropertyProgressTrack), findsOneWidget);
    });

    testWidgets('reports where along the bar the pointer landed',
        (tester) async {
      final positions = <double>[];
      var ended = 0;
      await tester.pumpWidget(
        row(
          child: PropertyProgressTrack(
            fraction: 0,
            fill: const Color(0xFF2F7FE4),
            track: const Color(0x11000000),
            onScrub: positions.add,
            onScrubEnd: () => ended++,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(PropertyProgressTrack));
      await tester.tapAt(Offset(box.left + box.width / 4, box.center.dy));
      await tester.pump();

      expect(positions.first, closeTo(0.25, 0.02));
      expect(ended, 1);
    });

    testWidgets('is dragged even though the grid scrolls sideways',
        (tester) async {
      final positions = <double>[];
      await tester.pumpWidget(
        row(
          child: PropertyProgressTrack(
            fraction: 0,
            fill: const Color(0xFF2F7FE4),
            track: const Color(0x11000000),
            onScrub: positions.add,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final box = tester.getRect(find.byType(PropertyProgressTrack));
      final gesture =
          await tester.startGesture(Offset(box.left + 4, box.center.dy));
      await gesture.moveBy(Offset(box.width / 2, 0));
      await tester.pump();
      await gesture.up();
      await tester.pump();

      expect(positions.last, greaterThan(0.4));
    });

    testWidgets('a bar with no width reports nothing rather than NaN',
        (tester) async {
      final positions = <double>[];
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 0,
                child: PropertyProgressTrack(
                  fraction: 0.5,
                  fill: const Color(0xFF2F7FE4),
                  track: const Color(0x11000000),
                  onScrub: positions.add,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(positions, isEmpty);
    });
  });

  group('what a styled cell stores', () {
    test('a number is written back without a needless decimal point', () {
      expect(writeNumericCell(12), '12');
      expect(writeNumericCell(1.5), '1.5');
      expect(readNumericCell(' 42 '), 42);
      expect(readNumericCell('nothing'), isNull);
    });

    test('a reminder cell keeps both the moment and the reminder', () {
      final at = DateTime.utc(2026, 8, 12, 10, 30);
      final raw = encodeReminderCell(at, 'rem-1');
      final read = parseReminderCell(raw);
      expect(read.at, at);
      expect(read.reminderId, 'rem-1');
    });

    test('an empty or half written reminder cell does not throw', () {
      expect(parseReminderCell('').at, isNull);
      expect(parseReminderCell('rubbish').at, isNull);
      expect(parseReminderCell('2026-08-12T10:30:00Z').reminderId, '');
    });
  });

  group('what the column heading menu offers', () {
    Future<List<AppMenuEntry>> entriesFor(
      WidgetTester tester, {
      required FieldInfo fieldInfo,
      PropertyStyle? style,
      bool isLocation = false,
    }) async {
      late List<AppMenuEntry> entries;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              entries = columnHeadingMenuEntries(
                context: context,
                viewId: 'v1',
                fieldInfo: fieldInfo,
                style: style,
                isLocation: isLocation,
                onEditProperty: () {},
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return entries;
    }

    FieldInfo fieldOf({
      FieldType type = FieldType.RichText,
      bool isPrimary = false,
    }) =>
        FieldInfo.initial(
          FieldPB(
            id: 'f1',
            name: 'Status',
            fieldType: type,
            isPrimary: isPrimary,
          ),
        );

    List<String> labelsOf(List<AppMenuEntry> entries) => [
          for (final entry in entries)
            if (entry is AppMenuItem) entry.label,
        ];

    AppMenuItem itemNamed(List<AppMenuEntry> entries, String label) =>
        entries.whereType<AppMenuItem>().firstWhere((e) => e.label == label);

    testWidgets('an ordinary column can be renamed, sorted and deleted',
        (tester) async {
      final entries = await entriesFor(tester, fieldInfo: fieldOf());
      final labels = labelsOf(entries);

      expect(
        labels,
        containsAll(<String>[
          LocaleKeys.disclosureAction_rename.tr(),
          LocaleKeys.grid_field_editProperty.tr(),
          LocaleKeys.interactive_property_type.tr(),
          LocaleKeys.interactive_property_align.tr(),
          LocaleKeys.grid_field_wrapCellContent.tr(),
          LocaleKeys.grid_settings_sort.tr(),
          LocaleKeys.grid_field_insertLeft.tr(),
          LocaleKeys.grid_field_insertRight.tr(),
          LocaleKeys.grid_field_duplicate.tr(),
          LocaleKeys.grid_field_hide.tr(),
          LocaleKeys.grid_field_clear.tr(),
          LocaleKeys.grid_field_delete.tr(),
        ]),
      );
      expect(
        itemNamed(entries, LocaleKeys.grid_field_delete.tr()).destructive,
        isTrue,
      );
    });

    testWidgets('the primary column keeps the rows it cannot use, greyed',
        (tester) async {
      final entries = await entriesFor(
        tester,
        fieldInfo: fieldOf(isPrimary: true),
      );

      for (final label in <String>[
        LocaleKeys.interactive_property_type.tr(),
        LocaleKeys.grid_field_duplicate.tr(),
        LocaleKeys.grid_field_hide.tr(),
        LocaleKeys.grid_field_delete.tr(),
      ]) {
        expect(itemNamed(entries, label).enabled, isFalse, reason: label);
      }
      expect(
        itemNamed(entries, LocaleKeys.disclosureAction_rename.tr()).enabled,
        isTrue,
      );
    });

    testWidgets('every alignment is offered, with the current one ticked',
        (tester) async {
      final entries = await entriesFor(
        tester,
        fieldInfo: fieldOf(),
        style: const PropertyStyle(
          kind: PropertyStyleKind.plain,
          settings: {'align': 'right'},
        ),
      );
      final align =
          itemNamed(entries, LocaleKeys.interactive_property_align.tr());

      expect(align.submenu.length, PropertyAlign.values.length);
      expect(
        align.submenu.whereType<AppMenuItem>().where((e) => e.selected).length,
        1,
      );
    });

    testWidgets('a progress column is given its own settings', (tester) async {
      final entries = await entriesFor(
        tester,
        fieldInfo: fieldOf(),
        style: const PropertyStyle(kind: PropertyStyleKind.progress),
      );
      final labels = labelsOf(entries);

      expect(labels, contains(LocaleKeys.interactive_property_maximum.tr()));
      expect(
          labels, contains(LocaleKeys.interactive_progress_showPercent.tr()));
      expect(
        labels,
        isNot(contains(LocaleKeys.interactive_property_step.tr())),
      );
    });

    testWidgets('a plain column is not asked about a progress bar',
        (tester) async {
      final entries = await entriesFor(tester, fieldInfo: fieldOf());
      expect(
        labelsOf(entries),
        isNot(contains(LocaleKeys.interactive_property_maximum.tr())),
      );
    });

    testWidgets('only an attachment column is asked about thumbnails',
        (tester) async {
      final media = await entriesFor(
        tester,
        fieldInfo: fieldOf(type: FieldType.Media),
      );
      expect(
        labelsOf(media),
        contains(LocaleKeys.interactive_property_thumbnailSize.tr()),
      );

      final text = await entriesFor(tester, fieldInfo: fieldOf());
      expect(
        labelsOf(text),
        isNot(contains(LocaleKeys.interactive_property_thumbnailSize.tr())),
      );
    });

    testWidgets('the type row says what the column already is', (tester) async {
      final entries = await entriesFor(
        tester,
        fieldInfo: fieldOf(),
        style: const PropertyStyle(kind: PropertyStyleKind.progress),
      );
      final type =
          itemNamed(entries, LocaleKeys.interactive_property_type.tr());

      expect(type.shortcut, isNotNull);
      expect(
        type.submenu.whereType<AppMenuItem>().where((e) => e.selected).length,
        1,
      );
      expect(type.submenu.whereType<AppMenuHeader>(), isNotEmpty);
    });
  });

  group('a cell can differ from its column', () {
    const column = PropertyStyle(
      kind: PropertyStyleKind.button,
      settings: {'label': 'Open', 'action': 'openView', 'target': 'page-1'},
    );

    test('an override rides in the same envelope and merges over the column',
        () {
      const styles = PropertyStyles(byField: {'f1': column});
      final extra = styles.withCell('f1', 'r1', {
        'target': 'page-2',
        'target_name': 'Notes'
      }).mergeIntoExtra('{"appflowy_chart":{"version":1}}');

      final read = PropertyStyles.fromExtra(extra);
      expect(jsonDecode(extra)['appflowy_chart'], isNotNull);

      // The row that asked goes somewhere else; every other row does not.
      expect(read.cellStyle('f1', 'r1')?.buttonTarget, 'page-2');
      expect(read.cellStyle('f1', 'r1')?.buttonTargetName, 'Notes');
      expect(read.cellStyle('f1', 'r2')?.buttonTarget, 'page-1');

      // What it did not answer for still comes from the column.
      expect(read.cellStyle('f1', 'r1')?.buttonLabel, 'Open');
      expect(read.cellStyle('f1', 'r1')?.kind, PropertyStyleKind.button);
    });

    test('a cell of a column with no style has no style either', () {
      const styles = PropertyStyles();
      expect(
        styles.withCell('f1', 'r1', {'accent': 'blue'}).cellStyle('f1', 'r1'),
        isNull,
      );
    });

    test('giving a cell back to its column drops the override', () {
      const styles = PropertyStyles(byField: {'f1': column});
      final withCell = styles.withCell('f1', 'r1', {'target': 'page-2'});
      expect(withCell.byCell, isNotEmpty);

      final cleared = withCell.withCell('f1', 'r1', null);
      expect(cleared.byCell, isEmpty);
      expect(cleared.cellStyle('f1', 'r1')?.buttonTarget, 'page-1');
      expect(
        cleared.mergeIntoExtra(''),
        isNot(contains('page-2')),
      );
    });

    test('an empty override is the same as none at all', () {
      const styles = PropertyStyles(byField: {'f1': column});
      expect(styles.withCell('f1', 'r1', {}).byCell, isEmpty);
      expect(
        PropertyStyles.fromExtra(
          const PropertyStyles(byField: {'f1': column}).mergeIntoExtra(''),
        ).byCell,
        isEmpty,
      );
    });

    test('changing what the column is forgets what its cells said', () {
      final styles = const PropertyStyles(byField: {'f1': column})
          .withCell('f1', 'r1', {'target': 'page-2'});

      // The same kind keeps them — only the target moved.
      expect(
        styles.withField('f1', column.withSetting('label', 'Go')).byCell,
        isNotEmpty,
      );

      // A different kind means those settings mean nothing any more.
      expect(
        styles
            .withField(
                'f1', const PropertyStyle(kind: PropertyStyleKind.counter))
            .byCell,
        isEmpty,
      );
      expect(styles.withField('f1', null).byCell, isEmpty);
    });
  });

  group('what the cell menu offers', () {
    Future<List<AppMenuEntry>> entriesFor(
      WidgetTester tester, {
      required PropertyStyle? style,
      Map<String, Object?> override = const {},
    }) async {
      late List<AppMenuEntry> entries;
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              entries = cellStyleMenuEntries(
                context: context,
                viewId: 'v1',
                fieldId: 'f1',
                rowId: 'r1',
                style: style,
                override: override,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      return entries;
    }

    List<String> labelsOf(List<AppMenuEntry> entries) => [
          for (final entry in entries)
            if (entry is AppMenuItem) entry.label,
        ];

    AppMenuItem itemNamed(List<AppMenuEntry> entries, String label) =>
        entries.whereType<AppMenuItem>().firstWhere((e) => e.label == label);

    testWidgets('nothing at all for a plain cell', (tester) async {
      expect(await entriesFor(tester, style: null), isEmpty);
      expect(
        await entriesFor(
          tester,
          style: const PropertyStyle(kind: PropertyStyleKind.plain),
        ),
        isEmpty,
      );
    });

    testWidgets('a button cell chooses its own label, action and target',
        (tester) async {
      final entries = await entriesFor(
        tester,
        style: const PropertyStyle(
          kind: PropertyStyleKind.button,
          settings: {'action': 'openView', 'target_name': 'Notes'},
        ),
      );

      expect(
        labelsOf(entries),
        containsAll(<String>[
          LocaleKeys.interactive_property_buttonLabel.tr(),
          LocaleKeys.interactive_button_action.tr(),
          LocaleKeys.interactive_button_chooseView.tr(),
          LocaleKeys.interactive_menu_colour.tr(),
        ]),
      );
      expect(
        itemNamed(entries, LocaleKeys.interactive_button_chooseView.tr())
            .shortcut,
        'Notes',
      );
    });

    testWidgets('a button that opens nothing is not asked where to',
        (tester) async {
      final entries = await entriesFor(
        tester,
        style: const PropertyStyle(kind: PropertyStyleKind.button),
      );
      expect(
        labelsOf(entries),
        isNot(contains(LocaleKeys.interactive_button_chooseTarget.tr())),
      );
    });

    testWidgets('each kind is asked only about itself', (tester) async {
      final progress = await entriesFor(
        tester,
        style: const PropertyStyle(kind: PropertyStyleKind.progress),
      );
      expect(
        labelsOf(progress),
        contains(LocaleKeys.interactive_property_maximum.tr()),
      );
      expect(
        labelsOf(progress),
        isNot(contains(LocaleKeys.interactive_property_step.tr())),
      );

      final counter = await entriesFor(
        tester,
        style: const PropertyStyle(kind: PropertyStyleKind.counter),
      );
      expect(
        labelsOf(counter),
        contains(LocaleKeys.interactive_property_step.tr()),
      );
    });

    testWidgets('the way back to the column is offered only once it is left',
        (tester) async {
      final untouched = await entriesFor(
        tester,
        style: const PropertyStyle(kind: PropertyStyleKind.counter),
      );
      expect(
        itemNamed(untouched, LocaleKeys.interactive_property_useColumn.tr())
            .enabled,
        isFalse,
      );

      final overridden = await entriesFor(
        tester,
        style: const PropertyStyle(kind: PropertyStyleKind.counter),
        override: const {'step': 5},
      );
      expect(
        itemNamed(overridden, LocaleKeys.interactive_property_useColumn.tr())
            .enabled,
        isTrue,
      );
    });
  });
}
