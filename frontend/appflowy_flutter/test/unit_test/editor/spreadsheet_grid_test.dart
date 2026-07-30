import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_theme.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// The grid renders itself with a painter, so these tests drive it through the
/// controller and the keyboard rather than looking for a widget per cell.
void main() {
  SpreadsheetController? controller;

  SpreadsheetData sample() => SpreadsheetData.fromRows(
        [
          ['Item', 'Cost', 'Qty'],
          ['Desk', '250', '2'],
          ['Chair', '120', '4'],
          ['Lamp', '40', '3'],
        ],
        minRows: 8,
        minColumns: 4,
      );

  Future<SpreadsheetController> pumpGrid(
    WidgetTester tester, {
    Brightness brightness = Brightness.light,
    bool editable = true,
    SpreadsheetData? data,
  }) async {
    controller?.dispose();
    final sheet =
        SpreadsheetController(data: data ?? sample(), editable: editable);
    controller = sheet;
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(brightness: brightness),
        home: Scaffold(
          body: SizedBox(
            width: 700,
            height: 320,
            child: SpreadsheetGrid(
              controller: sheet,
              editable: editable,
              autofocus: true,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return sheet;
  }

  tearDown(() {
    controller?.dispose();
    controller = null;
  });

  testWidgets('renders in light and dark without exceptions', (tester) async {
    await pumpGrid(tester);
    expect(tester.takeException(), isNull);

    await pumpGrid(tester, brightness: Brightness.dark);
    expect(tester.takeException(), isNull);
  });

  testWidgets('arrow keys move the cursor', (tester) async {
    final sheet = await pumpGrid(tester);
    sheet.selectCell(const CellRef(1, 0));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(sheet.active, const CellRef(2, 0));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pump();
    expect(sheet.active, const CellRef(2, 1));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(sheet.active, const CellRef(1, 1));
  });

  testWidgets('shift and arrow extends the selection', (tester) async {
    final sheet = await pumpGrid(tester);
    sheet.selectCell(const CellRef(1, 0));
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    await tester.pump();

    expect(sheet.selection.rowCount, 2);
    expect(sheet.anchor, const CellRef(1, 0));
  });

  testWidgets('Tab moves right', (tester) async {
    final sheet = await pumpGrid(tester);
    sheet.selectCell(const CellRef(1, 0));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump();
    expect(sheet.active, const CellRef(1, 1));
  });

  testWidgets('typing a character opens the editor with that character',
      (tester) async {
    final sheet = await pumpGrid(tester);
    sheet.selectCell(const CellRef(1, 0));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();

    expect(sheet.editing, const CellRef(1, 0));
    expect(find.byType(TextField), findsOneWidget);
    expect(sheet.editingText, 'x');
  });

  testWidgets('Escape closes the editor without writing', (tester) async {
    final sheet = await pumpGrid(tester);
    sheet
      ..selectCell(const CellRef(0, 0))
      ..startEditing(initialText: 'changed');
    await tester.pump();
    expect(find.byType(TextField), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(sheet.editing, isNull);
    expect(sheet.data.rawAt(const CellRef(0, 0)), 'Desk');
  });

  testWidgets('Enter commits the editor and moves down', (tester) async {
    final sheet = await pumpGrid(tester);
    sheet
      ..selectCell(const CellRef(1, 0))
      ..startEditing(initialText: 'Table');
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(sheet.data.rawAt(const CellRef(1, 0)), 'Table');
    expect(sheet.active, const CellRef(2, 0));
  });

  testWidgets('a read-only sheet ignores typing', (tester) async {
    final sheet = await pumpGrid(tester, editable: false);
    sheet.selectCell(const CellRef(0, 0));
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.keyX);
    await tester.pump();

    expect(sheet.editing, isNull);
    expect(sheet.data.rawAt(const CellRef(0, 0)), 'Desk');
  });

  testWidgets('a single click selects immediately', (tester) async {
    final sheet = await pumpGrid(tester);
    final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
    await tester.tapAt(
      origin +
          const Offset(
            SpreadsheetMetrics.gutterWidth + SheetColumn.defaultWidth + 20,
            SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight / 2,
          ),
    );
    await tester.pump();
    // The frozen strip holds column names, so the first body row is row 1.
    expect(sheet.active, const CellRef(0, 1));
  });

  testWidgets('a double click opens the editor', (tester) async {
    final sheet = await pumpGrid(tester);
    final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
    final target = origin +
        const Offset(
          SpreadsheetMetrics.gutterWidth + 30,
          SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight / 2,
        );
    await tester.tapAt(target);
    await tester.pump(const Duration(milliseconds: 40));
    await tester.tapAt(target);
    await tester.pump();

    expect(sheet.editing, const CellRef(0, 0));
  });

  testWidgets('dragging the fill handle extends the series', (tester) async {
    final sheet = await pumpGrid(tester);
    final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));

    // The handle sits on the bottom-right corner of the selection.
    sheet.selectCell(const CellRef(0, 1));
    await tester.pump();
    final handle = origin +
        const Offset(
          SpreadsheetMetrics.gutterWidth + SheetColumn.defaultWidth * 2,
          SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight,
        );

    final gesture = await tester.startGesture(
      handle,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, SheetRow.defaultHeight));
    await tester.pump();
    await gesture.moveBy(const Offset(0, SheetRow.defaultHeight));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(sheet.data.rawAt(const CellRef(1, 1)), '251');
    expect(sheet.data.rawAt(const CellRef(2, 1)), '252');
  });

  testWidgets('a multi-cell selection fills by its own step', (tester) async {
    final sheet = await pumpGrid(
      tester,
      data: SpreadsheetData.fromRows(
        [
          ['Step'],
          ['2'],
          ['4'],
        ],
        minRows: 8,
      ),
    );
    final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));

    sheet.selectRange(const CellRef(0, 0), const CellRef(1, 0));
    await tester.pumpAndSettle();

    // The handle hangs off the bottom-right of the whole range.
    final handle = origin +
        const Offset(
          SpreadsheetMetrics.gutterWidth + SheetColumn.defaultWidth,
          SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight * 2,
        );
    final gesture = await tester.startGesture(
      handle,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await gesture.moveBy(const Offset(0, SheetRow.defaultHeight * 2));
    await tester.pump();
    await gesture.up();
    await tester.pumpAndSettle();

    expect(sheet.data.rawAt(const CellRef(2, 0)), '6');
    expect(sheet.data.rawAt(const CellRef(3, 0)), '8');
  });

  testWidgets('a range selected by dragging can then be filled',
      (tester) async {
    final sheet = await pumpGrid(
      tester,
      data: SpreadsheetData.fromRows(
        [
          ['Step'],
          ['2'],
          ['4'],
        ],
        minRows: 8,
      ),
    );
    final origin = tester.getTopLeft(find.byType(SpreadsheetGrid));
    Offset at(double row, double column) =>
        origin +
        Offset(
          SpreadsheetMetrics.gutterWidth + SheetColumn.defaultWidth * column,
          SpreadsheetMetrics.headerHeight + SheetRow.defaultHeight * row,
        );

    // Sweep across the two cells the way a person would.
    final select = await tester.startGesture(
      at(0.5, 0.5),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await select.moveTo(at(1.5, 0.5));
    await tester.pump();
    await select.up();
    await tester.pumpAndSettle();
    expect(sheet.selection.rowCount, 2);

    final fill = await tester.startGesture(
      at(2, 1),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(const Duration(milliseconds: 20));
    await fill.moveTo(at(4, 1));
    await tester.pump();
    await fill.up();
    await tester.pumpAndSettle();

    expect(sheet.data.rawAt(const CellRef(2, 0)), '6');
    expect(sheet.data.rawAt(const CellRef(3, 0)), '8');
  });

  group('polish', () {
    SheetBodyPainter bodyPainter(WidgetTester tester) {
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<SheetBodyPainter>();
      return paints.first;
    }

    SheetGutterPainter gutterPainter(WidgetTester tester) {
      final paints = tester
          .widgetList<CustomPaint>(find.byType(CustomPaint))
          .map((widget) => widget.painter)
          .whereType<SheetGutterPainter>();
      return paints.first;
    }

    testWidgets('an untouched sheet offers a placeholder', (tester) async {
      controller?.dispose();
      final sheet = SpreadsheetController(data: SpreadsheetData.empty());
      controller = sheet;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 600,
              height: 260,
              child: SpreadsheetGrid(
                controller: sheet,
                placeholder: 'Start typing…',
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(sheet.data.isEmpty, isTrue);
      expect(bodyPainter(tester).placeholder, 'Start typing…');

      sheet
        ..selectCell(const CellRef(1, 0))
        ..startEditing(initialText: 'x')
        ..commitEditing();
      await tester.pumpAndSettle();

      expect(sheet.data.isEmpty, isFalse);
      expect(bodyPainter(tester).placeholder, isNull);
    });

    testWidgets('row numbers stay faded until the pointer arrives',
        (tester) async {
      await pumpGrid(tester);
      expect(gutterPainter(tester).pointerInside, isFalse);

      final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer();
      addTearDown(gesture.removePointer);
      await gesture.moveTo(tester.getCenter(find.byType(SpreadsheetGrid)));
      await tester.pumpAndSettle();

      expect(gutterPainter(tester).pointerInside, isTrue);
    });

    testWidgets('the focus ring settles when the cursor moves', (tester) async {
      final sheet = await pumpGrid(tester);
      await tester.pumpAndSettle();
      expect(bodyPainter(tester).selectionSettle.value, 1);

      sheet.selectCell(const CellRef(2, 1));
      await tester.pump();
      expect(bodyPainter(tester).selectionSettle.value, lessThan(1));

      await tester.pumpAndSettle();
      expect(bodyPainter(tester).selectionSettle.value, 1);
    });
  });

  group('cell color', () {
    late SpreadsheetPalette palette;

    Future<void> resolvePalette(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              palette = SpreadsheetPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
    }

    TextStyle styleFor(
      CellStyle style, {
      Color base = const Color(0xFFEDEDED),
    }) {
      return cellTextStyle(
        base: TextStyle(color: base),
        style: style,
        palette: palette,
        isError: false,
      );
    }

    testWidgets('a light fill forces dark text so it stays legible',
        (tester) async {
      await resolvePalette(tester);
      final resolved = styleFor(const CellStyle(backgroundColor: 0xFFFDECEA));
      expect(resolved.color, const Color(0xFF1F2933));
    });

    testWidgets('a dark fill forces light text', (tester) async {
      await resolvePalette(tester);
      final resolved = styleFor(
        const CellStyle(backgroundColor: 0xFF2E5FA3),
        base: const Color(0xFF1F2933),
      );
      expect(resolved.color, const Color(0xFFF7F8F9));
    });

    testWidgets('an explicit text color still wins over the fill',
        (tester) async {
      await resolvePalette(tester);
      final resolved = styleFor(
        const CellStyle(backgroundColor: 0xFFFDECEA, textColor: 0xFF1E8449),
      );
      expect(resolved.color, const Color(0xFF1E8449));
      expect(resolved.decorationColor, const Color(0xFF1E8449));
    });

    testWidgets('an unfilled cell keeps the inherited body color',
        (tester) async {
      await resolvePalette(tester);
      final resolved = styleFor(const CellStyle());
      expect(resolved.color, const Color(0xFFEDEDED));
    });
  });

  group('palette', () {
    Future<SpreadsheetPalette> resolve(
      WidgetTester tester, {
      required Brightness brightness,
      required bool paper,
    }) async {
      late SpreadsheetPalette palette;
      await tester.pumpWidget(
        MaterialApp(
          // Re-pumping a different appearance otherwise reads the theme
          // mid-animation and resolves the previous palette.
          themeAnimationDuration: Duration.zero,
          theme: ThemeData(
            brightness: brightness,
            extensions: [PaperThemeExtension(enabled: paper)],
          ),
          home: Builder(
            builder: (context) {
              palette = SpreadsheetPalette.of(context);
              return const SizedBox();
            },
          ),
        ),
      );
      return palette;
    }

    testWidgets('paper mode sits flush on the warm page', (tester) async {
      final palette =
          await resolve(tester, brightness: Brightness.light, paper: true);
      expect(palette.isPaper, isTrue);
      // Flush, not a card: the cells take the page's own stationery colour.
      expect(palette.surface, PaperTheme.editorBackground);
      expect(palette.headerSurface, palette.surface);
      expect(palette.gutterSurface, palette.surface);
      expect(palette.accent, PaperTheme.accent);
      expect(palette.textPrimary, PaperTheme.textPrimary);
      // Menus and the floating toolbar still lift off it.
      expect(palette.floating, isNot(palette.surface));
    });

    testWidgets('light and dark stay on the ambient theme', (tester) async {
      final light =
          await resolve(tester, brightness: Brightness.light, paper: false);
      expect(light.isPaper, isFalse);
      expect(light.surface, isNot(PaperTheme.editorBackground));
      expect(light.headerSurface, light.surface);

      final dark =
          await resolve(tester, brightness: Brightness.dark, paper: false);
      expect(dark.isPaper, isFalse);
      expect(dark.surface, isNot(light.surface));
    });

    testWidgets('a dark theme never takes the paper palette', (tester) async {
      final palette =
          await resolve(tester, brightness: Brightness.dark, paper: true);
      expect(palette.isPaper, isFalse);
      expect(palette.surface, isNot(PaperTheme.editorBackground));
    });

    testWidgets('banding and grid lines stay quieter than the surface',
        (tester) async {
      for (final brightness in Brightness.values) {
        final palette = await resolve(
          tester,
          brightness: brightness,
          paper: false,
        );
        expect(palette.bandedSurface, isNot(palette.surface));
        expect(palette.gridLine.a, lessThan(palette.divider.a));
      }
    });
  });

  group('geometry', () {
    test('offsets skip hidden columns and rows', () {
      final data = SpreadsheetData.fromRows(
        [
          ['a', 'b', 'c'],
          ['1', '2', '3'],
          ['4', '5', '6'],
        ],
        minRows: 3,
      )
        ..setColumn(1, const SheetColumn(hidden: true))
        ..setColumn(2, const SheetColumn(width: 100));
      final sheet = SpreadsheetController(data: data);
      final geometry = SheetGeometry.from(sheet);

      expect(geometry.columnWidth(1), 0);
      expect(geometry.columnLeft(2), SheetColumn.defaultWidth);
      expect(
        geometry.totalWidth,
        SheetColumn.defaultWidth + 100,
      );
      // Column names live in the frozen strip, so every row is a body row.
      expect(geometry.bodyRows, [0, 1, 2]);
      sheet.dispose();
    });

    test('binary search finds the column and row under a point', () {
      final data = SpreadsheetData(rowCount: 40, columnCount: 6);
      final sheet = SpreadsheetController(data: data);
      final geometry = SheetGeometry.from(sheet);

      expect(geometry.columnAt(0), 0);
      expect(geometry.columnAt(SheetColumn.defaultWidth * 2.5), 2);
      expect(geometry.columnAt(geometry.totalWidth + 10), isNull);
      expect(geometry.bodyIndexAt(SheetRow.defaultHeight * 3.5), 3);
      expect(geometry.bodyIndexAt(-1), isNull);
      sheet.dispose();
    });

    test('the visible window overscans but stays in range', () {
      final data = SpreadsheetData(rowCount: 500, columnCount: 30);
      final sheet = SpreadsheetController(data: data);
      final geometry = SheetGeometry.from(sheet);

      final (firstRow, endRow) = geometry.visibleBodyRows(0, 300);
      expect(firstRow, 0);
      expect(endRow, lessThan(geometry.bodyRows.length));

      final (firstColumn, endColumn) = geometry.visibleColumns(0, 600);
      expect(firstColumn, 0);
      expect(endColumn, lessThanOrEqualTo(geometry.columnCount));
      sheet.dispose();
    });
    test('the add affordances extend the scrollable content', () {
      final data = SpreadsheetData(rowCount: 4, columnCount: 3);
      final sheet = SpreadsheetController(data: data);

      final editable = SheetGeometry.from(sheet);
      expect(
        editable.contentWidth,
        editable.totalWidth + SpreadsheetMetrics.addColumnWidth,
      );
      expect(
        editable.contentHeight,
        editable.totalHeight + SpreadsheetMetrics.addRowHeight,
      );
      expect(editable.isInAddColumn(editable.totalWidth + 1), isTrue);
      expect(editable.isInAddColumn(editable.totalWidth - 1), isFalse);
      expect(editable.isInAddRow(10, editable.totalHeight + 1), isTrue);
      expect(editable.isInAddRow(10, editable.totalHeight - 1), isFalse);
      // The band stops with the columns, so neither does the hit test run on.
      expect(
        editable.isInAddRow(editable.totalWidth + 1, editable.totalHeight + 1),
        isFalse,
      );

      // A read-only sheet offers neither.
      final readOnly = SheetGeometry.from(sheet, showAddAffordances: false);
      expect(readOnly.contentWidth, readOnly.totalWidth);
      expect(readOnly.contentHeight, readOnly.totalHeight);
      expect(readOnly.isInAddColumn(readOnly.totalWidth + 1), isFalse);
      expect(readOnly.isInAddRow(10, readOnly.totalHeight + 1), isFalse);
      sheet.dispose();
    });
  });
}
