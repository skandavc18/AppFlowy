import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_event_chip.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/time_grid_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/year_view.dart';
import 'package:appflowy/plugins/database/find/database_find_calendar.dart';
import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/database/widgets/card/card.dart';
import 'package:appflowy/plugins/database/widgets/card/card_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/text_card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_style_maps/desktop_board_card_cell_style.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_support.dart' show CalendarFixtureProvider;
import 'database_find_grid_test_support.dart';
import 'database_find_test_support.dart';

void main() {
  setUpDatabaseFindTests();

  testWidgets(
    'real card title is revealed on both axes; an omitted property reveals only its actual card',
    (tester) async {
      final page = DatabaseFindHarness(layout: ViewLayoutPB.Board);
      final model = DatabaseFindGridModel(page.reads, rowCount: 1);
      model.setText(findGridNearRow, 'find-field-2', 'hidden property needle');
      final card = CardBloc(
        fieldController: model.fields,
        groupFieldId: null,
        viewId: databaseFindViewId,
        isEditing: false,
        rowController: model.rowController(findGridNearRow),
      )..add(const CardEvent.initial());
      final x = ScrollController();
      final y = ScrollController();
      page.content = DatabaseFindLayout(
        viewId: databaseFindViewId,
        snapshot: model.snapshot,
        child: SingleChildScrollView(
          controller: x,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: 1700,
            child: SingleChildScrollView(
              controller: y,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(1250, 1100, 100, 100),
                child: BlocProvider.value(
                  value: card,
                  child: Builder(
                    builder: (context) => RowCardContent(
                      rowMeta: card.state.rowMeta,
                      cells: card.state.cells,
                      cellBuilder: _CardCells(model),
                      styleConfiguration: RowCardStyleConfiguration(
                        cellStyleMap: desktopBoardCardCellStyleMap(context),
                        preview: CardPreviewMode.none,
                        showProperties: false,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      try {
        await page.mount(tester);
        final title = tester.state<EditableTextState>(
          find.descendant(
            of: find.byType(TextCardCell),
            matching: find.byType(EditableText),
          ),
        );
        final native = title.renderEditable;
        final start = title.widget.controller.text.indexOf('needle');
        expect(start, greaterThanOrEqualTo(0));
        final selection =
            TextSelection(baseOffset: start, extentOffset: start + 6);
        final word = native.getBoxesForSelection(selection).single.toRect();
        final verticalViewport = RenderAbstractViewport.of(native);
        final horizontalViewport =
            RenderAbstractViewport.of(verticalViewport.parent);
        // showOnScreen uses the nearest trailing-edge offset for a word below
        // the viewport, not an arbitrary amount of scroll (nor row alignment).
        // Capture both native offsets BEFORE Find moves either axis.
        final expectedY = verticalViewport
            .getOffsetToReveal(native, 1, rect: word)
            .offset
            .clamp(y.position.minScrollExtent, y.position.maxScrollExtent);
        final expectedX = horizontalViewport
            .getOffsetToReveal(native, 1, rect: word)
            .offset
            .clamp(x.position.minScrollExtent, x.position.maxScrollExtent);
        expect(x.offset, 0);
        expect(y.offset, 0);
        expect(expectedY, greaterThan(0));
        final before = page.reads.snapshot();
        await page.open(tester, hover: false);
        await page.query(tester, 'needle');
        final navigation = _navigation(tester);
        await settleDatabaseFindNavigation(tester, navigation);
        expect(databaseFindBar(tester).matchCount, 2);
        expect(
          navigation.reveal,
          DatabaseFindReveal.exact,
          reason: navigation.message,
        );
        final nativeRects = native
            .getBoxesForSelection(selection)
            .map(
              (box) => MatrixUtils.transformRect(
                native.getTransformTo(null),
                box.toRect(),
              ),
            )
            .toList();
        expect(nativeRects, isNotEmpty);
        expect(navigation.visibleMatchRects, nativeRects);
        final pane =
            tester.getRect(find.byType(DatabaseFindLayout)).inflate(0.1);
        for (final rect in nativeRects) {
          expect(pane.contains(rect.topLeft), isTrue);
          expect(pane.contains(rect.bottomRight), isTrue);
        }
        expect(x.offset, greaterThan(800));
        expect(x.offset, closeTo(expectedX, 0.1));
        expect(
          y.offset,
          closeTo(expectedY, 0.1),
          reason: 'The exact native word determines the minimal reveal offset',
        );
        final field = tester.widget<TextField>(
          find.descendant(
            of: find.byType(TextCardCell),
            matching: find.byType(TextField),
          ),
        );
        final editor = field.controller;
        final value = editor!.value;
        expect(field.readOnly, isTrue);
        expect(field.focusNode!.hasFocus, isFalse);
        await databaseFindKey(
          tester,
          LogicalKeyboardKey.f3,
          PhysicalKeyboardKey.f3,
        );
        await settleDatabaseFindNavigation(tester, navigation);
        expect(
          databaseFindSession(tester).current!.part.id,
          'row:$findGridNearRow:find-field-2',
        );
        expect(navigation.reveal, DatabaseFindReveal.row);
        expect(navigation.visibleMatchRects, isEmpty);
        expect(navigation.message, contains('does not display'));
        expect(find.byType(TextCardCell), findsOneWidget);
        expect(editor.value, value);
        expect(field.focusNode!.hasFocus, isFalse);
        expect(model.writes, isEmpty);
        expect(page.reads.snapshot(), before);
        expect(tester.takeException(), isNull);
      } finally {
        await page.dispose(tester);
        await tester.runAsync(card.close);
        model.dispose();
        x.dispose();
        y.dispose();
      }
    },
    timeout: const Timeout(Duration(seconds: 30)),
  );

  for (final mode in [CalendarViewMode.day, CalendarViewMode.year]) {
    testWidgets(
      'calendar $mode preserves mode/filters and never confuses event titles with density tiles',
      (tester) async {
        final page = DatabaseFindHarness(layout: ViewLayoutPB.Calendar);
        final model = DatabaseFindGridModel(page.reads, rowCount: 2);
        model.setText('find-row-1', findGridNearField, 'far needle event');
        final farDay = DateTime(2031, 4, 15);
        final events = [
          CalendarEvent(
            id: 'row:$findGridNearRow',
            rowId: findGridNearRow,
            calendarId: 'calendar-fixture',
            title: model.text(
              const CellContext(
                rowId: findGridNearRow,
                fieldId: findGridNearField,
              ),
            ),
            start: ZonedDateTime.local(DateTime(2026, 9, 26, 9)),
            end: ZonedDateTime.local(DateTime(2026, 9, 26, 10)),
          ),
          CalendarEvent(
            id: 'row:find-row-1',
            rowId: 'find-row-1',
            calendarId: 'calendar-fixture',
            title: 'far needle event',
            start: ZonedDateTime.local(DateTime(2031, 4, 15, 19)),
            end: ZonedDateTime.local(DateTime(2031, 4, 15, 20)),
          ),
        ];
        final provider = CalendarFixtureProvider(events: events);
        final workspace = CalendarWorkspace(providers: [provider]);
        const filter = CalendarFilter(query: 'needle', showReminders: false);
        workspace.setFilter(filter);
        final shell = GlobalKey<CalendarShellState>();
        final modeWrites = <CalendarViewMode>[];
        page.content = DatabaseFindLayout(
          viewId: databaseFindViewId,
          snapshot: model.snapshot,
          materialize: (request) async {
            if (!request.isCurrent || request.target.rowId == null) return null;
            final event = events
                .firstWhere((event) => event.rowId == request.target.rowId);
            shell.currentState!.revealDateForFind(event.startDay);
            return 'Only rendered titles have word boxes; year-view density has no event text.';
          },
          child: DatabaseFindCalendarScope(
            viewId: databaseFindViewId,
            calendarId: 'calendar-fixture',
            primaryFieldId: findGridNearField,
            child: CalendarShell(
              key: shell,
              workspace: workspace,
              delegate: CalendarViewDelegate(
                colorOf: (_) => const Color(0xFF43955A),
                canEdit: false,
              ),
              initialDate: DateTime(2026, 9, 26),
              initialMode: mode,
              mode: mode,
              onModeChanged: modeWrites.add,
              quiet: true,
            ),
          ),
        );
        try {
          await page.mount(tester);
          final before = page.reads.snapshot();
          await page.open(tester, hover: false);
          await page.query(tester, 'needle');
          final navigation = _navigation(tester);
          await settleDatabaseFindNavigation(tester, navigation);
          expect(databaseFindBar(tester).matchCount, 2);
          await databaseFindKey(
            tester,
            LogicalKeyboardKey.f3,
            PhysicalKeyboardKey.f3,
          );
          await settleDatabaseFindNavigation(tester, navigation);
          expect(
            databaseFindSession(tester).current!.part.id,
            'row:find-row-1:$findGridNearField',
          );
          if (mode == CalendarViewMode.day) {
            expect(
              tester
                  .widget<CalendarTimeGridView>(
                    find.byType(CalendarTimeGridView),
                  )
                  .days,
              [farDay],
            );
            expect(find.byType(CalendarEventChip), findsOneWidget);
            expect(
              navigation.reveal,
              DatabaseFindReveal.exact,
              reason: navigation.message,
            );
            expect(navigation.visibleMatchRects, isNotEmpty);
          } else {
            expect(
              tester
                  .widget<CalendarYearView>(find.byType(CalendarYearView))
                  .year,
              2031,
            );
            expect(navigation.reveal, DatabaseFindReveal.unavailable);
            expect(navigation.visibleMatchRects, isEmpty);
            expect(navigation.message, contains('density'));
          }
          expect(workspace.filter, same(filter));
          expect(modeWrites, isEmpty);
          expect(model.writes, isEmpty);
          expect(page.reads.snapshot(), before);
          expect(tester.takeException(), isNull);
        } finally {
          await page.dispose(tester);
          workspace.dispose();
          model.dispose();
        }
      },
      timeout: const Timeout(Duration(seconds: 30)),
    );
  }

  testWidgets(
      'typed option matches map to the actual separate labels, including the second occurrence',
      (tester) async {
    final page = DatabaseFindHarness();
    final options = [
      SelectOptionPB(id: 'one-guid', name: 'first needle'),
      SelectOptionPB(id: 'two-guid', name: 'second needle'),
    ];
    page.view.name = 'Table';
    page.reads.fields[databaseFindViewId] = [
      FieldPB(
        id: 'tags',
        name: 'Tags',
        fieldType: FieldType.MultiSelect,
        typeOptionData:
            MultiSelectTypeOptionPB(options: options).writeToBuffer(),
      ),
    ];
    page.reads.cells[(databaseFindViewId, databaseFindRowId, 'tags')] = CellPB(
      rowId: databaseFindRowId,
      fieldId: 'tags',
      fieldType: FieldType.MultiSelect,
      data: SelectOptionCellDataPB(selectOptions: options).writeToBuffer(),
    );
    const target =
        DatabaseFindTarget.cell(databaseFindViewId, databaseFindRowId, 'tags');
    page.content = Align(
      alignment: Alignment.bottomLeft,
      child: DatabaseFindAnchor(
        target: target,
        child: Wrap(
          children: [
            for (final option in options) Chip(label: Text(option.name)),
          ],
        ),
      ),
    );
    try {
      await page.mount(tester);
      final before = page.reads.snapshot();
      await page.open(tester, hover: false);
      await page.query(tester, 'needle');
      final navigation = _navigation(tester);
      await settleDatabaseFindNavigation(tester, navigation);
      final first = navigation.visibleMatchRects.single;
      expect(databaseFindBar(tester).matchCount, 2);
      expect(navigation.reveal, DatabaseFindReveal.exact);
      await databaseFindKey(
        tester,
        LogicalKeyboardKey.f3,
        PhysicalKeyboardKey.f3,
      );
      await settleDatabaseFindNavigation(tester, navigation);
      expect(navigation.reveal, DatabaseFindReveal.exact);
      expect(navigation.visibleMatchRects.single.left, greaterThan(first.left));
      expect(
        databaseFindSession(tester).current!.range.start,
        greaterThan(options.first.name.length),
      );
      expect(page.reads.snapshot(), before);
    } finally {
      await page.dispose(tester);
    }
  });

  testWidgets(
      'checkbox Yes remains a native checkbox, not a fabricated highlighted word',
      (tester) async {
    final page = DatabaseFindHarness();
    var changes = 0;
    page.content = Align(
      alignment: Alignment.bottomLeft,
      child: DatabaseFindAnchor(
        target: const DatabaseFindTarget.cell(
          databaseFindViewId,
          databaseFindRowId,
          'checkbox-field-guid',
        ),
        child: Checkbox(value: true, onChanged: (_) => changes++),
      ),
    );
    try {
      await page.mount(tester);
      final before = page.reads.snapshot();
      await page.open(tester, hover: false);
      await page.query(tester, 'Yes');
      final navigation = _navigation(tester);
      await settleDatabaseFindNavigation(tester, navigation);
      expect(databaseFindBar(tester).matchCount, 1);
      expect(navigation.reveal, DatabaseFindReveal.cell);
      expect(navigation.visibleMatchRects, isEmpty);
      expect(tester.widget<Checkbox>(find.byType(Checkbox)).value, isTrue);
      expect(changes, 0);
      expect(page.reads.snapshot(), before);
    } finally {
      await page.dispose(tester);
    }
  });
}

DatabaseFindController _navigation(WidgetTester tester) =>
    tester.widget<DatabaseFindScope>(find.byType(DatabaseFindScope)).controller;

class _CardCells extends Fake implements CardCellBuilder {
  _CardCells(this.model);
  final DatabaseFindGridModel model;

  @override
  Widget build({
    required CellContext cellContext,
    required CardCellStyleMap styleMap,
    EditableCardNotifier? cellNotifier,
    required bool hasNotes,
  }) {
    expectSync(
      cellContext.fieldId,
      findGridNearField,
      reason: 'This face must not construct hidden properties',
    );
    return TextCardCell(
      databaseController: model.database,
      cellContext: cellContext,
      cellController: model.cellController(cellContext),
      editableNotifier: cellNotifier,
      style: styleMap[FieldType.RichText]! as TextCardCellStyle,
    );
  }
}
