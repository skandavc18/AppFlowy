import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_codec.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_format.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_formula.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_grid_render.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_model.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/spreadsheet/spreadsheet_table_conversion.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter_test/flutter_test.dart';

SpreadsheetData _sheet(List<List<String>> rows) => SpreadsheetData.fromRows(
      rows,
      headerRow: false,
      minRows: rows.length,
      minColumns: 1,
    );

/// A sheet with room below and to the right so scratch formulas have somewhere
/// to live without running off the edge of the grid.
SpreadsheetData _paddedSheet(List<List<String>> rows) =>
    SpreadsheetData.fromRows(
      rows,
      headerRow: false,
      minRows: 12,
      minColumns: 8,
    );

double? _number(SheetValue value) => value is NumberValue ? value.value : null;

void main() {
  group('cell references', () {
    test('parses and renders A1 notation', () {
      expect(CellRef.parseA1('A1'), const CellRef(0, 0));
      expect(CellRef.parseA1('b3'), const CellRef(2, 1));
      expect(CellRef.parseA1(r'$AA$10'), const CellRef(9, 26));
      expect(CellRef.parseA1('A'), isNull);
      expect(CellRef.parseA1('12'), isNull);
      expect(CellRef.parseA1('A0'), isNull);
    });

    test('column labels roll over past Z', () {
      expect(CellRef.columnLabel(0), 'A');
      expect(CellRef.columnLabel(25), 'Z');
      expect(CellRef.columnLabel(26), 'AA');
      expect(CellRef.columnLabel(27), 'AB');
      expect(CellRef.columnLabel(701), 'ZZ');
    });

    test('a range is normalised whichever corner it is dragged from', () {
      final forwards = CellRange(const CellRef(1, 1), const CellRef(3, 4));
      final backwards = CellRange(const CellRef(3, 4), const CellRef(1, 1));
      expect(forwards, backwards);
      expect(forwards.rowCount, 3);
      expect(forwards.columnCount, 4);
      expect(forwards.cellCount, 12);
      expect(forwards.contains(const CellRef(2, 2)), isTrue);
      expect(forwards.contains(const CellRef(0, 2)), isFalse);
    });
  });

  group('number parsing', () {
    test('reads the shapes people actually type', () {
      expect(parseCellNumber('42'), 42);
      expect(parseCellNumber('1,234.5'), 1234.5);
      expect(parseCellNumber(r'$1,200'), 1200);
      expect(parseCellNumber('45%'), closeTo(0.45, 1e-9));
      expect(parseCellNumber('(12)'), -12);
      expect(parseCellNumber('  -3.25 '), -3.25);
      expect(parseCellNumber('hello'), isNull);
      expect(parseCellNumber(''), isNull);
    });

    test('renders without trailing zeros or exponents', () {
      expect(formatPlainNumber(42), '42');
      expect(formatPlainNumber(42.5), '42.5');
      expect(formatPlainNumber(-0.125), '-0.125');
      expect(formatPlainNumber(1000000), '1000000');
    });
  });

  group('formula engine', () {
    late SpreadsheetData data;
    late SpreadsheetEvaluator evaluator;

    setUp(() {
      data = _paddedSheet([
        ['Item', 'Cost', 'Qty'],
        ['Desk', '250', '2'],
        ['Chair', '120.5', '4'],
        ['Lamp', '40', '3'],
      ]);
      evaluator = SpreadsheetEvaluator(data);
    });

    test('evaluates arithmetic with precedence', () {
      data.setRaw(const CellRef(5, 0), '=2+3*4');
      data.setRaw(const CellRef(5, 1), '=(2+3)*4');
      data.setRaw(const CellRef(5, 2), '=2^3^2');
      evaluator = SpreadsheetEvaluator(data);
      expect(_number(evaluator.valueAt(const CellRef(5, 0))), 14);
      expect(_number(evaluator.valueAt(const CellRef(5, 1))), 20);
      expect(_number(evaluator.valueAt(const CellRef(5, 2))), 512);
    });

    test('resolves cell references and ranges', () {
      data.setRaw(const CellRef(5, 0), '=B2+B3');
      data.setRaw(const CellRef(5, 1), '=SUM(B2:B4)');
      data.setRaw(const CellRef(5, 2), '=AVERAGE(B2:B4)');
      evaluator = SpreadsheetEvaluator(data);
      expect(_number(evaluator.valueAt(const CellRef(5, 0))), 370.5);
      expect(_number(evaluator.valueAt(const CellRef(5, 1))), 410.5);
      expect(
        _number(evaluator.valueAt(const CellRef(5, 2))),
        closeTo(136.833333, 1e-5),
      );
    });

    test('supports the documented function set', () {
      final cases = <String, double>{
        '=COUNT(B2:B4)': 3,
        '=MIN(B2:B4)': 40,
        '=MAX(B2:B4)': 250,
        '=ROUND(B3,0)': 121,
        '=ROUND(123.456,2)': 123.46,
        '=ABS(0-7)': 7,
        '=IF(B2>100,1,0)': 1,
        '=IF(B2<100,1,0)': 0,
        '=SUM(B2:B4)*2': 821,
      };
      cases.forEach((formula, expected) {
        data.setRaw(const CellRef(6, 0), formula);
        evaluator = SpreadsheetEvaluator(data);
        expect(
          _number(evaluator.valueAt(const CellRef(6, 0))),
          closeTo(expected, 1e-9),
          reason: formula,
        );
      });
    });

    test('COUNT ignores text while COUNTA counts it', () {
      data.setRaw(const CellRef(6, 0), '=COUNT(A2:A4)');
      data.setRaw(const CellRef(6, 1), '=COUNTA(A2:A4)');
      evaluator = SpreadsheetEvaluator(data);
      expect(_number(evaluator.valueAt(const CellRef(6, 0))), 0);
      expect(_number(evaluator.valueAt(const CellRef(6, 1))), 3);
    });

    test('reports errors instead of throwing', () {
      data.setRaw(const CellRef(6, 0), '=1/0');
      data.setRaw(const CellRef(6, 1), '=NOPE(1)');
      data.setRaw(const CellRef(6, 2), '=1+');
      evaluator = SpreadsheetEvaluator(data);
      expect(evaluator.valueAt(const CellRef(6, 0)), ErrorValue.divideByZero);
      expect(evaluator.valueAt(const CellRef(6, 1)), ErrorValue.name);
      expect(evaluator.valueAt(const CellRef(6, 2)), ErrorValue.parse);
    });

    test('a cycle resolves to an error rather than a stack overflow', () {
      data.setRaw(const CellRef(6, 0), '=A8');
      data.setRaw(const CellRef(7, 0), '=A7');
      evaluator = SpreadsheetEvaluator(data);
      expect(evaluator.valueAt(const CellRef(6, 0)), ErrorValue.cycle);
    });

    test('a reference outside the grid is a #REF! error', () {
      data.setRaw(const CellRef(6, 0), '=ZZ9000');
      evaluator = SpreadsheetEvaluator(data);
      expect(evaluator.valueAt(const CellRef(6, 0)), ErrorValue.reference);
    });

    test('text concatenation and comparison', () {
      data.setRaw(const CellRef(6, 0), '="a" & "b"');
      data.setRaw(const CellRef(6, 1), '=2>1');
      evaluator = SpreadsheetEvaluator(data);
      expect(evaluator.valueAt(const CellRef(6, 0)).asText, 'ab');
      expect(evaluator.valueAt(const CellRef(6, 1)), const BoolValue(true));
    });

    test('a cell marked as text is never read as a number', () {
      data
        ..setRaw(const CellRef(6, 0), '007')
        ..setStyle(
          const CellRef(6, 0),
          const CellStyle(format: CellNumberFormat.text),
        );
      evaluator = SpreadsheetEvaluator(data);
      expect(evaluator.valueAt(const CellRef(6, 0)), const TextValue('007'));
    });
  });

  group('structure', () {
    test('inserting rows moves the cells below down', () {
      final data = _sheet([
        ['a'],
        ['b'],
        ['c'],
      ]);
      data.insertRows(1, 2);
      expect(data.rowCount, 5);
      expect(data.rawAt(const CellRef(0, 0)), 'a');
      expect(data.rawAt(const CellRef(1, 0)), '');
      expect(data.rawAt(const CellRef(3, 0)), 'b');
      expect(data.rawAt(const CellRef(4, 0)), 'c');
    });

    test('deleting rows closes the gap', () {
      final data = _sheet([
        ['a'],
        ['b'],
        ['c'],
      ]);
      data.deleteRows(0, 1);
      expect(data.rowCount, 2);
      expect(data.rawAt(const CellRef(0, 0)), 'b');
      expect(data.rawAt(const CellRef(1, 0)), 'c');
    });

    test('the last row and column cannot be deleted away', () {
      final data = SpreadsheetData(rowCount: 1, columnCount: 1);
      data
        ..deleteRows(0, 1)
        ..deleteColumns(0, 1);
      expect(data.rowCount, 1);
      expect(data.columnCount, 1);
    });

    test('columns shift with their cells and widths', () {
      final data = _sheet([
        ['a', 'b', 'c'],
      ]);
      data
        ..setColumn(0, const SheetColumn(width: 200))
        ..insertColumns(1, 1);
      expect(data.columnCount, 4);
      expect(data.rawAt(const CellRef(0, 0)), 'a');
      expect(data.rawAt(const CellRef(0, 1)), '');
      expect(data.rawAt(const CellRef(0, 2)), 'b');
      expect(data.column(0).width, 200);
    });

    test('moving a column carries its cells', () {
      final data = _sheet([
        ['a', 'b', 'c'],
        ['1', '2', '3'],
      ]);
      data.moveColumn(0, 2);
      expect(data.toRows().first, ['b', 'c', 'a']);
      expect(data.toRows()[1], ['2', '3', '1']);
    });

    test('json round trips values, styles and layout', () {
      final data = _sheet([
        ['Rent', '=1200*2'],
      ])
        ..showHeader = true
        ..setColumnTitle(0, 'Name')
        ..setColumnTitle(1, 'Amount')
        ..setStyle(
          const CellRef(0, 1),
          const CellStyle(
            bold: true,
            align: CellAlign.end,
            format: CellNumberFormat.currency,
            decimals: 2,
            textColor: 0xFF112233,
          ),
        )
        ..setColumn(
          1,
          const SheetColumn(width: 180, hidden: true, title: 'Amount'),
        )
        ..setRowSpec(0, const SheetRow(height: 48));

      final restored = SpreadsheetData.fromJson(data.toJson());
      expect(restored.rowCount, data.rowCount);
      expect(restored.columnCount, data.columnCount);
      expect(restored.showHeader, isTrue);
      expect(restored.columnTitle(0), 'Name');
      expect(restored.columnTitle(1), 'Amount');
      expect(restored.rawAt(const CellRef(0, 1)), '=1200*2');
      expect(restored.styleAt(const CellRef(0, 1)).bold, isTrue);
      expect(restored.styleAt(const CellRef(0, 1)).align, CellAlign.end);
      expect(
        restored.styleAt(const CellRef(0, 1)).format,
        CellNumberFormat.currency,
      );
      expect(restored.styleAt(const CellRef(0, 1)).textColor, 0xFF112233);
      expect(restored.column(1).width, 180);
      expect(restored.column(1).hidden, isTrue);
      expect(restored.row(0).height, 48);
    });
  });

  group('delimited text', () {
    test('parses quoted CSV fields', () {
      final rows = parseDelimitedText(
        'a,b,c\n"one, two",3,"say ""hi"""\n',
      );
      expect(rows.length, 2);
      expect(rows[0], ['a', 'b', 'c']);
      expect(rows[1], ['one, two', '3', 'say "hi"']);
    });

    test('detects tabs', () {
      expect(detectDelimiter('a\tb\tc\n1\t2\t3'), '\t');
      expect(detectDelimiter('a,b,c\n1,2,3'), ',');
    });

    test('encoding quotes only what needs it', () {
      final text = encodeDelimitedText([
        ['plain', 'has,comma', 'has"quote'],
      ]);
      expect(text, 'plain,"has,comma","has""quote"');
    });

    test('round trips', () {
      final rows = [
        ['Name', 'Note'],
        ['Ada', 'first, and best'],
      ];
      expect(parseDelimitedText(encodeDelimitedText(rows)), rows);
    });
  });

  group('markdown tables', () {
    test('recognises a github table', () {
      final rows = parseMarkdownTable('''
| Name | Cost |
| --- | ---: |
| Desk | 250 |
| Chair | 120 |
''');
      expect(rows, [
        ['Name', 'Cost'],
        ['Desk', '250'],
        ['Chair', '120'],
      ]);
    });

    test('rejects text that is not a table', () {
      expect(parseMarkdownTable('just a paragraph'), isNull);
      expect(parseMarkdownTable('| a | b |'), isNull);
    });

    test('renders computed values, not formulas', () {
      final data = _sheet([
        ['Item', 'Cost'],
        ['Desk', '250'],
        ['Total', '=SUM(B2:B2)'],
      ]);
      final markdown = encodeMarkdownTable(data);
      expect(markdown, contains('| Total | 250 |'));
      expect(markdown, isNot(contains('SUM')));
    });

    test('escapes pipes inside a cell', () {
      final data = _sheet([
        ['a|b'],
      ]);
      expect(encodeMarkdownTable(data), contains(r'a\|b'));
    });
  });

  group('xlsx', () {
    test('a workbook round trips through the reader', () {
      final data = _sheet([
        ['Item', 'Cost'],
        ['Desk', '250'],
        ['Chair', '120.5'],
        ['Total', '=SUM(B2:B3)'],
      ])
        ..setStyle(
          const CellRef(1, 1),
          const CellStyle(format: CellNumberFormat.currency, bold: true),
        );

      final bytes = encodeSpreadsheetXlsx(data);
      expect(bytes.length, greaterThan(400));

      final rows = decodeSpreadsheetXlsx(bytes);
      expect(rows[0][0], 'Item');
      expect(rows[1][0], 'Desk');
      expect(rows[1][1], '250');
      expect(rows[2][1], '120.5');
      expect(rows[3][1], '=SUM(B2:B3)');
    });

    test('a package with no rows decodes to nothing rather than throwing', () {
      final bytes = encodeSpreadsheetXlsx(
        SpreadsheetData(rowCount: 3, columnCount: 3, showHeader: false),
      );
      expect(decodeSpreadsheetXlsx(bytes), isEmpty);
    });
  });

  group('formatting', () {
    test('renders each number format', () {
      String render(String raw, CellStyle style) {
        final data = _sheet([
          [raw],
        ])
          ..setStyle(const CellRef(0, 0), style);
        return formatCellValue(
          SpreadsheetEvaluator(data).valueAt(const CellRef(0, 0)),
          style,
          raw: raw,
        );
      }

      expect(
        render('1234.5', const CellStyle(format: CellNumberFormat.number)),
        '1,234.5',
      );
      expect(
        render(
          '1234.5',
          const CellStyle(format: CellNumberFormat.number, decimals: 2),
        ),
        '1,234.50',
      );
      expect(
        render(
          '0.25',
          const CellStyle(format: CellNumberFormat.percent),
        ),
        '25%',
      );
      expect(
        render(
          '007',
          const CellStyle(format: CellNumberFormat.text),
        ),
        '007',
      );
      expect(
        render(
          '1200',
          const CellStyle(
            format: CellNumberFormat.currency,
            currencySymbol: r'$',
          ),
        ),
        contains('1,200.00'),
      );
    });

    test('numbers right align by default and text does not', () {
      expect(
        isRightAlignedByDefault(const NumberValue(4), const CellStyle()),
        isTrue,
      );
      expect(
        isRightAlignedByDefault(const TextValue('four'), const CellStyle()),
        isFalse,
      );
      expect(
        isRightAlignedByDefault(
          const NumberValue(4),
          const CellStyle(format: CellNumberFormat.text),
        ),
        isFalse,
      );
    });

    test('detects what a column is holding', () {
      final numbers = _sheet([
        ['10'],
        ['20'],
        ['30'],
      ]);
      expect(detectColumnKind(numbers, 0), ColumnKind.number);

      final money = _sheet([
        [r'$10'],
        [r'$20'],
        [r'$30'],
      ]);
      expect(detectColumnKind(money, 0), ColumnKind.currency);

      final dates = _sheet([
        ['2024-01-04'],
        ['2024-02-11'],
        ['2024-03-19'],
      ]);
      expect(detectColumnKind(dates, 0), ColumnKind.date);

      final words = _sheet([
        ['Ada'],
        ['Grace'],
        ['Alan'],
      ]);
      expect(detectColumnKind(words, 0), ColumnKind.text);

      final tooFewSamples = _sheet([
        ['10'],
      ]);
      expect(detectColumnKind(tooFewSamples, 0), isNull);
    });
  });

  group('controller', () {
    late SpreadsheetController controller;

    setUp(() {
      controller = SpreadsheetController(
        data: SpreadsheetData.fromRows(
          [
            ['Item', 'Cost'],
            ['Desk', '250'],
            ['Chair', '120'],
            ['Lamp', '40'],
          ],
          minRows: 3,
          minColumns: 2,
        ),
      );
    });

    tearDown(() => controller.dispose());

    test('undo and redo walk the edit history', () {
      controller
        ..selectCell(const CellRef(0, 0))
        ..startEditing(initialText: 'Table')
        ..commitEditing();
      expect(controller.data.rawAt(const CellRef(0, 0)), 'Table');
      expect(controller.canUndo, isTrue);

      controller.undo();
      expect(controller.data.rawAt(const CellRef(0, 0)), 'Desk');

      controller.redo();
      expect(controller.data.rawAt(const CellRef(0, 0)), 'Table');
    });

    test('committing an unchanged value does not grow the undo stack', () {
      controller
        ..selectCell(const CellRef(0, 0))
        ..startEditing()
        ..commitEditing();
      expect(controller.canUndo, isFalse);
    });

    test('sorting reorders every row, names stay put', () {
      controller.sortByColumn(1, SortDirection.ascending);
      expect(controller.data.columnTitle(0), 'Item');
      expect(controller.data.rawAt(const CellRef(0, 0)), 'Lamp');
      expect(controller.data.rawAt(const CellRef(2, 0)), 'Desk');

      controller.sortByColumn(1, SortDirection.descending);
      expect(controller.data.rawAt(const CellRef(0, 0)), 'Desk');
    });

    test('filtering hides rows without deleting them', () {
      controller.setFilter(0, 'a');
      expect(controller.visibleRows, [1, 2]);
      expect(controller.data.rowCount, 3);

      controller.clearFilters();
      expect(controller.visibleRows, [0, 1, 2]);
    });

    test('arrow navigation skips filtered rows', () {
      controller
        ..setFilter(0, 'a')
        ..selectCell(const CellRef(1, 0))
        ..move(1, 0);
      expect(controller.active, const CellRef(2, 0));
    });

    test('Enter at the last row grows the sheet', () {
      controller
        ..selectCell(const CellRef(2, 0))
        ..advance(horizontal: false, backwards: false);
      expect(controller.data.rowCount, 4);
      expect(controller.active.row, 3);
    });

    test('Tab wraps to the next row', () {
      controller
        ..selectCell(const CellRef(0, 1))
        ..advance(horizontal: true, backwards: false);
      expect(controller.active, const CellRef(1, 0));
    });

    test('find, step and replace', () {
      controller.setSearch('a');
      expect(controller.searchMatches, isNotEmpty);
      final first = controller.currentSearchMatch;
      controller.stepSearch(1);
      expect(controller.currentSearchMatch, isNot(first));

      controller.setSearch('Desk');
      expect(controller.replaceAll('Table'), 1);
      expect(controller.data.rawAt(const CellRef(0, 0)), 'Table');
    });

    test('selection summary aggregates the numbers', () {
      controller.selectRange(const CellRef(0, 1), const CellRef(2, 1));
      final summary = controller.selectionSummary;
      expect(summary.cellCount, 3);
      expect(summary.numericCount, 3);
      expect(summary.sum, 410);
      expect(summary.minimum, 40);
      expect(summary.maximum, 250);
      expect(summary.average, closeTo(136.6666, 1e-3));
    });

    test('style toggles apply across the whole selection', () {
      controller
        ..selectRange(const CellRef(0, 0), const CellRef(2, 0))
        ..toggleBold();
      expect(controller.data.styleAt(const CellRef(1, 0)).bold, isTrue);
      controller.toggleBold();
      expect(controller.data.styleAt(const CellRef(1, 0)).bold, isFalse);
    });

    test('automatic column types only touch untouched cells', () {
      final sheet = SpreadsheetController(
        data: _sheet([
          ['10'],
          ['20'],
          ['30'],
        ])
          ..setStyle(
            const CellRef(0, 0),
            const CellStyle(format: CellNumberFormat.text),
          ),
      );
      sheet.applyAutomaticColumnTypes();
      expect(
        sheet.data.styleAt(const CellRef(0, 0)).format,
        CellNumberFormat.text,
      );
      expect(
        sheet.data.styleAt(const CellRef(1, 0)).format,
        CellNumberFormat.number,
      );
      sheet.dispose();
    });
  });

  group('fill handle', () {
    SpreadsheetController sheetWith(List<List<String>> rows) =>
        SpreadsheetController(data: _sheet(rows));

    test('a single number repeats by one', () {
      final controller = sheetWith([
        ['1'],
        [''],
        [''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(0, 0)),
        const CellRange.raw(top: 0, left: 0, bottom: 2, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(1, 0)), '2');
      expect(controller.data.rawAt(const CellRef(2, 0)), '3');
      controller.dispose();
    });

    test('two numbers continue their difference', () {
      final controller = sheetWith([
        ['5'],
        ['10'],
        [''],
        [''],
      ]);
      controller.fill(
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
        const CellRange.raw(top: 0, left: 0, bottom: 3, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(2, 0)), '15');
      expect(controller.data.rawAt(const CellRef(3, 0)), '20');
      controller.dispose();
    });

    test('a trailing number in text keeps counting', () {
      final controller = sheetWith([
        ['Week 1'],
        [''],
        [''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(0, 0)),
        const CellRange.raw(top: 0, left: 0, bottom: 2, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(1, 0)), 'Week 2');
      expect(controller.data.rawAt(const CellRef(2, 0)), 'Week 3');
      controller.dispose();
    });

    test('two labels set the step for the rest', () {
      final controller = sheetWith([
        ['Week 1'],
        ['Week 3'],
        [''],
        [''],
      ]);
      controller.fill(
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
        const CellRange.raw(top: 0, left: 0, bottom: 3, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(2, 0)), 'Week 5');
      expect(controller.data.rawAt(const CellRef(3, 0)), 'Week 7');
      controller.dispose();
    });

    test('a padded label keeps its width', () {
      final controller = sheetWith([
        ['Q08'],
        ['Q09'],
        [''],
      ]);
      controller.fill(
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
        const CellRange.raw(top: 0, left: 0, bottom: 2, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(2, 0)), 'Q10');
      controller.dispose();
    });

    test('labels that share no prefix just repeat', () {
      final controller = sheetWith([
        ['Week 1'],
        ['Day 2'],
        [''],
        [''],
      ]);
      controller.fill(
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
        const CellRange.raw(top: 0, left: 0, bottom: 3, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(2, 0)), 'Week 1');
      expect(controller.data.rawAt(const CellRef(3, 0)), 'Day 2');
      controller.dispose();
    });

    test('a date series continues by its own gap', () {
      final controller = sheetWith([
        ['2024-01-01'],
        ['2024-01-08'],
        [''],
        [''],
      ]);
      controller.fill(
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
        const CellRange.raw(top: 0, left: 0, bottom: 3, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(2, 0)), '2024-01-15');
      expect(controller.data.rawAt(const CellRef(3, 0)), '2024-01-22');
      controller.dispose();
    });

    test('a single date steps by a day and keeps its format', () {
      final controller = sheetWith([
        ['31/01/2024'],
        [''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(0, 0)),
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(1, 0)), '01/02/2024');
      controller.dispose();
    });

    test('plain text repeats', () {
      final controller = sheetWith([
        ['Yes'],
        [''],
        [''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(0, 0)),
        const CellRange.raw(top: 0, left: 0, bottom: 2, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(2, 0)), 'Yes');
      controller.dispose();
    });

    test('a currency prefix survives the series', () {
      final controller = sheetWith([
        [r'$10'],
        [r'$20'],
        [''],
      ]);
      controller.fill(
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
        const CellRange.raw(top: 0, left: 0, bottom: 2, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(2, 0)), r'$30');
      controller.dispose();
    });

    test('fills sideways too', () {
      final controller = sheetWith([
        ['1', '', ''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(0, 0)),
        const CellRange.raw(top: 0, left: 0, bottom: 0, right: 2),
      );
      expect(controller.data.rawAt(const CellRef(0, 2)), '3');
      controller.dispose();
    });

    test('a formula travels with its references', () {
      final controller = sheetWith([
        ['1', '2', '=A1+B1'],
        ['3', '4', ''],
        ['5', '6', ''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(0, 2)),
        const CellRange.raw(top: 0, left: 2, bottom: 2, right: 2),
      );
      expect(controller.data.rawAt(const CellRef(1, 2)), '=A2+B2');
      expect(controller.data.rawAt(const CellRef(2, 2)), '=A3+B3');
      expect(controller.valueAt(const CellRef(2, 2)).asNumber, 11);
      controller.dispose();
    });

    test('a sideways fill moves the columns instead of the rows', () {
      final controller = sheetWith([
        ['2', '3', '4', ''],
        ['=A1*2', '', '', ''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(1, 0)),
        const CellRange.raw(top: 1, left: 0, bottom: 1, right: 2),
      );
      expect(controller.data.rawAt(const CellRef(1, 1)), '=B1*2');
      expect(controller.data.rawAt(const CellRef(1, 2)), '=C1*2');
      controller.dispose();
    });

    test(r'a $ pins the half of the reference it marks', () {
      final controller = sheetWith([
        [r'=$A$1+B1'],
        [''],
      ]);
      controller.fill(
        CellRange.single(const CellRef(0, 0)),
        const CellRange.raw(top: 0, left: 0, bottom: 1, right: 0),
      );
      expect(controller.data.rawAt(const CellRef(1, 0)), r'=$A$1+B2');
      controller.dispose();
    });

    test('an uneven run still extends along its trend', () {
      final controller = sheetWith([
        ['1'],
        ['2'],
        ['4'],
        [''],
      ]);
      controller.fill(
        const CellRange.raw(top: 0, left: 0, bottom: 2, right: 0),
        const CellRange.raw(top: 0, left: 0, bottom: 3, right: 0),
      );
      // The old behaviour repeated the last value; a 1.5 slope reads better.
      expect(controller.data.rawAt(const CellRef(3, 0)), '5.5');
      controller.dispose();
    });
  });

  group('row numbering', () {
    // Headers are column names, not a row, so the first row a person sees is
    // row 1 and `=A1+B1` sums exactly what they are looking at. Getting this
    // wrong made the formula read an invisible header row and return 0.
    test('the first visible row is row 1 even with a header', () {
      final data = SpreadsheetData.fromRows([
        ['Cost', 'Qty', 'Total'],
        ['1', '2', '=A1+B1'],
      ]);
      expect(data.showHeader, isTrue);
      expect(data.columnTitle(0), 'Cost');
      expect(data.rawAt(const CellRef(0, 0)), '1');

      final controller = SpreadsheetController(data: data);
      expect(controller.visibleRows.first, 0);
      expect(SheetGeometry.from(controller).bodyRows.first, 0);
      expect(_number(controller.valueAt(const CellRef(0, 2))), 3);
      controller.dispose();
    });

    test('renaming a column never moves a cell', () {
      final data = SpreadsheetData.fromRows([
        ['Cost'],
        ['5'],
      ]);
      final controller = SpreadsheetController(data: data)
        ..startEditingHeader(0)
        ..updateEditingText('Price')
        ..commitEditing();

      expect(controller.data.columnTitle(0), 'Price');
      expect(controller.data.rawAt(const CellRef(0, 0)), '5');
      expect(controller.data.rowCount, greaterThanOrEqualTo(1));
      controller.dispose();
    });

    test('a version 1 payload lifts its header row into the column names', () {
      // What the old model stored: the header sat in row 0.
      final legacy = {
        'rows': 3,
        'columns': 2,
        'header': true,
        'cells': {
          '0:0': {'v': 'Name'},
          '0:1': {'v': 'Cost'},
          '1:0': {'v': 'Desk'},
          '1:1': {'v': '250'},
        },
      };

      final data = SpreadsheetData.fromJson(legacy);
      expect(data.showHeader, isTrue);
      expect(data.columnTitle(0), 'Name');
      expect(data.columnTitle(1), 'Cost');
      expect(data.rawAt(const CellRef(0, 0)), 'Desk');
      expect(data.rawAt(const CellRef(0, 1)), '250');
      expect(data.rowCount, 2);

      // Reading it back must not migrate a second time.
      final again = SpreadsheetData.fromJson(data.toJson());
      expect(again.columnTitle(0), 'Name');
      expect(again.rawAt(const CellRef(0, 0)), 'Desk');
    });
  });

  group('table conversion', () {
    test("a table's header row becomes the sheet's column names", () {
      final table = createSimpleTableBlockNode(
        columnCount: 2,
        rowCount: 3,
        contentBuilder: (row, column) => 'r${row}c$column',
      );
      table.updateAttributes({SimpleTableBlockKeys.enableHeaderRow: true});

      final data = spreadsheetFromTable(table);
      expect(data.showHeader, isTrue);
      expect(data.columnTitle(0), 'r0c0');
      expect(data.columnTitle(1), 'r0c1');
      // The two remaining table rows are the sheet's rows 1 and 2.
      expect(data.rowCount, 2);
      expect(data.columnCount, 2);
      expect(data.rawAt(const CellRef(0, 0)), 'r1c0');
      expect(data.rawAt(const CellRef(1, 1)), 'r2c1');
    });

    test('a table without a header keeps every row as data', () {
      final table = createSimpleTableBlockNode(
        columnCount: 2,
        rowCount: 3,
        contentBuilder: (row, column) => 'r${row}c$column',
      );

      final data = spreadsheetFromTable(table);
      expect(data.showHeader, isFalse);
      expect(data.rowCount, 3);
      expect(data.rawAt(const CellRef(0, 0)), 'r0c0');
      expect(data.rawAt(const CellRef(2, 1)), 'r2c1');
    });

    test('column widths and bold columns carry over', () {
      final table = createSimpleTableBlockNode(
        columnCount: 2,
        rowCount: 2,
        defaultContent: 'x',
      )..updateAttributes({
          SimpleTableBlockKeys.columnWidths: {'0': 210.0},
          SimpleTableBlockKeys.columnBoldAttributes: {'1': true},
        });

      final data = spreadsheetFromTable(table);
      expect(data.column(0).width, 210);
      expect(data.styleAt(const CellRef(0, 1)).bold, isTrue);
      expect(data.styleAt(const CellRef(0, 0)).bold, isFalse);
    });

    test('a sheet becomes a table with computed values', () {
      final data = _sheet([
        ['Desk', '250'],
        ['Total', '=SUM(B1:B1)'],
      ])
        ..showHeader = true
        ..setColumnTitle(0, 'Item')
        ..setColumnTitle(1, 'Cost');

      final table = simpleTableFromSpreadsheet(data);
      expect(table.type, SimpleTableBlockKeys.type);
      expect(table.attributes[SimpleTableBlockKeys.enableHeaderRow], isTrue);
      expect(table.children.length, 3);

      final lastRow = table.children.last;
      final total = lastRow.children.last.children.first.delta?.toPlainText();
      expect(total, '250');

      final headerCell =
          table.children.first.children.first.children.first.delta;
      expect(headerCell?.toPlainText(), 'Item');
      expect(headerCell?.first.attributes?[AppFlowyRichTextKeys.bold], isTrue);
    });

    test('sheet to table and back keeps the values and the names', () {
      final original = _sheet([
        ['Ada', '99'],
        ['Alan', '95'],
      ])
        ..showHeader = true
        ..setColumnTitle(0, 'Name')
        ..setColumnTitle(1, 'Score');

      final restored = spreadsheetFromTable(
        simpleTableFromSpreadsheet(original),
      );
      expect(restored.showHeader, isTrue);
      expect(restored.columnTitles, ['Name', 'Score']);
      expect(restored.toRows(), original.toRows());
    });

    test('only table blocks are convertible', () {
      expect(isConvertibleTable(paragraphNode(text: 'hi')), isFalse);
      expect(
        isConvertibleTable(
          createSimpleTableBlockNode(columnCount: 1, rowCount: 1),
        ),
        isTrue,
      );
    });
  });
}
