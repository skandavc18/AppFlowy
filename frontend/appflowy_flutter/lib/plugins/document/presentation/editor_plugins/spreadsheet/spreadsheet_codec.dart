/// Conversions in and out of the spreadsheet block: delimited text, markdown
/// tables and Excel workbooks.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:xml/xml.dart';

import 'spreadsheet_format.dart';
import 'spreadsheet_formula.dart';
import 'spreadsheet_model.dart';

// ---------------------------------------------------------------------------
// Delimited text
// ---------------------------------------------------------------------------

/// Parses CSV/TSV following RFC 4180 quoting rules.
List<List<String>> parseDelimitedText(String input, {String? delimiter}) {
  if (input.isEmpty) {
    return const [];
  }
  final separator = delimiter ?? detectDelimiter(input);
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var quoted = false;
  var index = 0;

  while (index < input.length) {
    final char = input[index];
    if (quoted) {
      if (char == '"') {
        if (index + 1 < input.length && input[index + 1] == '"') {
          field.write('"');
          index += 2;
          continue;
        }
        quoted = false;
        index++;
        continue;
      }
      field.write(char);
      index++;
      continue;
    }
    if (char == '"' && field.isEmpty) {
      quoted = true;
      index++;
      continue;
    }
    if (char == separator) {
      row.add(field.toString());
      field.clear();
      index++;
      continue;
    }
    if (char == '\r') {
      index++;
      continue;
    }
    if (char == '\n') {
      row.add(field.toString());
      field.clear();
      rows.add(row);
      row = <String>[];
      index++;
      continue;
    }
    field.write(char);
    index++;
  }

  if (field.isNotEmpty || row.isNotEmpty) {
    row.add(field.toString());
    rows.add(row);
  }
  // Drop a single trailing empty row produced by a final newline.
  if (rows.isNotEmpty &&
      rows.last.length == 1 &&
      rows.last.first.trim().isEmpty) {
    rows.removeLast();
  }
  return rows;
}

/// Picks the delimiter by counting candidates in the first few lines.
String detectDelimiter(String input) {
  final sample = const LineSplitter().convert(input).take(5).join('\n');
  var best = ',';
  var bestCount = 0;
  for (final candidate in const [',', '\t', ';', '|']) {
    final count = candidate.allMatches(sample).length;
    if (count > bestCount) {
      best = candidate;
      bestCount = count;
    }
  }
  return bestCount == 0 ? ',' : best;
}

String encodeDelimitedText(
  List<List<String>> rows, {
  String delimiter = ',',
}) {
  final buffer = StringBuffer();
  for (var index = 0; index < rows.length; index++) {
    final row = rows[index];
    for (var column = 0; column < row.length; column++) {
      if (column > 0) {
        buffer.write(delimiter);
      }
      buffer.write(_escapeDelimitedField(row[column], delimiter));
    }
    if (index < rows.length - 1) {
      buffer.write('\n');
    }
  }
  return buffer.toString();
}

String _escapeDelimitedField(String value, String delimiter) {
  final needsQuotes = value.contains(delimiter) ||
      value.contains('"') ||
      value.contains('\n') ||
      value.contains('\r');
  if (!needsQuotes) {
    return value;
  }
  return '"${value.replaceAll('"', '""')}"';
}

// ---------------------------------------------------------------------------
// Markdown tables
// ---------------------------------------------------------------------------

/// Recognises a GitHub-flavoured markdown table and returns its rows.
List<List<String>>? parseMarkdownTable(String input) {
  final lines = const LineSplitter()
      .convert(input.trim())
      .where((line) => line.trim().isNotEmpty)
      .toList();
  if (lines.length < 2) {
    return null;
  }
  if (!_isMarkdownDivider(lines[1])) {
    return null;
  }
  final rows = <List<String>>[];
  for (var index = 0; index < lines.length; index++) {
    if (index == 1) {
      continue;
    }
    final line = lines[index].trim();
    if (!line.contains('|')) {
      continue;
    }
    rows.add(_splitMarkdownRow(line));
  }
  return rows.isEmpty ? null : rows;
}

bool _isMarkdownDivider(String line) {
  final trimmed = line.trim();
  if (!trimmed.contains('-')) {
    return false;
  }
  return RegExp(r'^\|?\s*:?-{1,}:?\s*(\|\s*:?-{1,}:?\s*)*\|?$')
      .hasMatch(trimmed);
}

List<String> _splitMarkdownRow(String line) {
  var text = line.trim();
  if (text.startsWith('|')) {
    text = text.substring(1);
  }
  if (text.endsWith('|') && !text.endsWith(r'\|')) {
    text = text.substring(0, text.length - 1);
  }
  final cells = <String>[];
  final buffer = StringBuffer();
  for (var index = 0; index < text.length; index++) {
    final char = text[index];
    if (char == r'\' && index + 1 < text.length && text[index + 1] == '|') {
      buffer.write('|');
      index++;
      continue;
    }
    if (char == '|') {
      cells.add(buffer.toString().trim());
      buffer.clear();
      continue;
    }
    buffer.write(char);
  }
  cells.add(buffer.toString().trim());
  return cells;
}

/// Renders the sheet as a markdown table, using evaluated values so a formula
/// column reads as numbers rather than expressions.
String encodeMarkdownTable(SpreadsheetData data, {bool evaluate = true}) {
  final rows = spreadsheetDisplayRows(
    data,
    evaluate: evaluate,
    includeHeader: true,
  );
  if (rows.isEmpty) {
    return '';
  }
  final columnCount =
      rows.fold<int>(0, (best, row) => row.length > best ? row.length : best);
  final buffer = StringBuffer();

  String renderRow(List<String> row) {
    final cells = [
      for (var index = 0; index < columnCount; index++)
        (index < row.length ? row[index] : '').replaceAll('|', r'\|'),
    ];
    return '| ${cells.join(' | ')} |';
  }

  buffer.writeln(renderRow(rows.first));
  buffer.writeln('|${List.filled(columnCount, ' --- ').join('|')}|');
  for (final row in rows.skip(1)) {
    buffer.writeln(renderRow(row));
  }
  return buffer.toString();
}

/// The grid as the user sees it — formatted values rather than raw input.
///
/// With [includeHeader] the column names are prepended as a first row, which
/// is what every text format expects even though the sheet keeps them as
/// column metadata.
List<List<String>> spreadsheetDisplayRows(
  SpreadsheetData data, {
  bool evaluate = true,
  bool trim = true,
  bool includeHeader = false,
}) {
  final evaluator = evaluate ? SpreadsheetEvaluator(data) : null;
  final raw = data.toRows(trim: trim);
  final rows = evaluator == null
      ? raw
      : [
          for (var row = 0; row < raw.length; row++)
            [
              for (var column = 0; column < raw[row].length; column++)
                formatCellValue(
                  evaluator.valueAt(CellRef(row, column)),
                  data.styleAt(CellRef(row, column)),
                  raw: raw[row][column],
                ),
            ],
        ];
  if (!includeHeader || !data.showHeader) {
    return rows;
  }
  final width = rows.isEmpty ? data.columnCount : rows.first.length;
  return [
    [for (var column = 0; column < width; column++) data.headerLabel(column)],
    ...rows,
  ];
}

/// Moves every row reference in a formula by [delta].
///
/// Used when a format writes the column names as a real first row: the values
/// shift down, so the references have to follow or the workbook opens wrong.
/// The whole sheet moves here, so `$` markers move with it.
String shiftFormulaRows(String formula, int delta) =>
    translateFormula(formula, rowDelta: delta, respectAbsolute: false);

/// Rewrites a formula as if its cell moved [rowDelta] rows and [columnDelta]
/// columns, the way copying or filling a formula translates its references.
///
/// With [respectAbsolute] a `$` pins that half of the reference, as it does in
/// every other spreadsheet.
String translateFormula(
  String formula, {
  int rowDelta = 0,
  int columnDelta = 0,
  bool respectAbsolute = true,
}) {
  if ((rowDelta == 0 && columnDelta == 0) || formula.isEmpty) {
    return formula;
  }
  final buffer = StringBuffer();
  final pattern = RegExp(r'(\$?)([A-Za-z]{1,3})(\$?)(\d+)');
  var index = 0;
  var quoted = false;
  while (index < formula.length) {
    final char = formula[index];
    if (char == '"') {
      quoted = !quoted;
      buffer.write(char);
      index++;
      continue;
    }
    if (quoted) {
      buffer.write(char);
      index++;
      continue;
    }
    final match = pattern.matchAsPrefix(formula, index);
    // A function name is letters followed by '(', never a reference.
    final followedByCall = match != null &&
        match.end < formula.length &&
        formula[match.end] == '(';
    final startsWord =
        index > 0 && RegExp('[A-Za-z0-9_.]').hasMatch(formula[index - 1]);
    if (match != null && !followedByCall && !startsWord) {
      final columnFixed = respectAbsolute && match.group(1) == r'$';
      final rowFixed = respectAbsolute && match.group(3) == r'$';
      final ref = CellRef.parseA1('${match.group(2)}${match.group(4)}');
      if (ref != null) {
        final row = rowFixed ? ref.row : ref.row + rowDelta;
        final column = columnFixed ? ref.column : ref.column + columnDelta;
        if (row >= 0 && column >= 0) {
          buffer.write(
            '${match.group(1)}${CellRef.columnLabel(column)}'
            '${match.group(3)}${row + 1}',
          );
          index = match.end;
          continue;
        }
      }
    }
    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

// ---------------------------------------------------------------------------
// Excel workbooks
// ---------------------------------------------------------------------------

const _xmlHeader = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>';

/// Builds a real `.xlsx` package from the sheet, preserving formulas, number
/// formats, fonts, alignment and fills.
Uint8List encodeSpreadsheetXlsx(
  SpreadsheetData data, {
  String sheetName = 'Sheet1',
}) {
  final styles = _XlsxStyleTable();
  final evaluator = SpreadsheetEvaluator(data);
  final rowsXml = StringBuffer();

  final lastRow = data.rowCount;
  final lastColumn = data.columnCount;
  // Column names become a real first row in a workbook, so the data below it
  // moves down one and every formula reference moves with it.
  final offset = data.showHeader ? 1 : 0;

  if (offset == 1) {
    final headerXml = StringBuffer();
    for (var column = 0; column < lastColumn; column++) {
      final styleIndex = styles.indexFor(const CellStyle(), header: true);
      headerXml.write(
        '<c r="${CellRef(0, column).a1}" s="$styleIndex" t="inlineStr">'
        '<is><t xml:space="preserve">'
        '${_escapeXml(data.headerLabel(column))}</t></is></c>',
      );
    }
    rowsXml.write('<row r="1">$headerXml</row>');
  }

  for (var row = 0; row < lastRow; row++) {
    final cellsXml = StringBuffer();
    for (var column = 0; column < lastColumn; column++) {
      final ref = CellRef(row, column);
      final cell = data.cellAt(ref);
      if (cell.raw.isEmpty && cell.style.isEmpty) {
        continue;
      }
      final styleIndex = styles.indexFor(cell.style);
      cellsXml.write(
        _xlsxCell(ref, cell, styleIndex, evaluator, offset),
      );
    }
    if (cellsXml.isEmpty) {
      continue;
    }
    final height = data.row(row).height;
    final heightAttribute = height == SheetRow.defaultHeight
        ? ''
        : ' ht="${(height * 0.75).toStringAsFixed(2)}" customHeight="1"';
    rowsXml.write(
      '<row r="${row + 1 + offset}"$heightAttribute>$cellsXml</row>',
    );
  }

  final columnsXml = StringBuffer();
  for (var column = 0; column < lastColumn; column++) {
    final spec = data.column(column);
    // Excel column width is measured in character widths.
    final width = (spec.width / 7.5).clamp(2.0, 96.0);
    columnsXml.write(
      '<col min="${column + 1}" max="${column + 1}" '
      'width="${width.toStringAsFixed(2)}" customWidth="1"'
      '${spec.hidden ? ' hidden="1"' : ''}/>',
    );
  }

  final freeze = data.showHeader
      ? '<sheetViews><sheetView workbookViewId="0">'
          '<pane ySplit="1" topLeftCell="A2" activePane="bottomLeft" state="frozen"/>'
          '</sheetView></sheetViews>'
      : '';

  final sheetXml = '$_xmlHeader'
      '<worksheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
      '$freeze'
      '${columnsXml.isEmpty ? '' : '<cols>$columnsXml</cols>'}'
      '<sheetData>$rowsXml</sheetData>'
      '</worksheet>';

  final parts = <String, String>{
    '[Content_Types].xml': '$_xmlHeader'
        '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
        '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
        '<Default Extension="xml" ContentType="application/xml"/>'
        '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
        '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
        '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
        '</Types>',
    '_rels/.rels': '$_xmlHeader'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
        '</Relationships>',
    'xl/workbook.xml': '$_xmlHeader'
        '<workbook xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main" '
        'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships">'
        '<sheets><sheet name="${_escapeXml(sheetName)}" sheetId="1" r:id="rId1"/></sheets>'
        '</workbook>',
    'xl/_rels/workbook.xml.rels': '$_xmlHeader'
        '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
        '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
        '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
        '</Relationships>',
    'xl/styles.xml': styles.toXml(),
    'xl/worksheets/sheet1.xml': sheetXml,
  };

  final archive = Archive();
  for (final entry in parts.entries) {
    final bytes = utf8.encode(entry.value);
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  final encoded = ZipEncoder().encode(archive);
  if (encoded == null) {
    throw StateError('Unable to build the workbook.');
  }
  return Uint8List.fromList(encoded);
}

String _xlsxCell(
  CellRef ref,
  SheetCell cell,
  int styleIndex,
  SpreadsheetEvaluator evaluator,
  int rowOffset,
) {
  final reference = CellRef(ref.row + rowOffset, ref.column).a1;
  final styleAttribute = styleIndex == 0 ? '' : ' s="$styleIndex"';
  if (cell.raw.isEmpty) {
    return '<c r="$reference"$styleAttribute/>';
  }
  if (cell.isFormula) {
    final value = evaluator.valueAt(ref);
    final number = value is NumberValue ? value.value : null;
    final formula = _escapeXml(
      shiftFormulaRows(cell.raw.substring(1), rowOffset),
    );
    if (number != null) {
      return '<c r="$reference"$styleAttribute>'
          '<f>$formula</f><v>${_xlsxNumber(number)}</v></c>';
    }
    return '<c r="$reference"$styleAttribute t="str">'
        '<f>$formula</f><v>${_escapeXml(value.asText)}</v></c>';
  }
  if (cell.style.format != CellNumberFormat.text) {
    final number = parseCellNumber(cell.raw);
    if (number != null) {
      return '<c r="$reference"$styleAttribute>'
          '<v>${_xlsxNumber(number)}</v></c>';
    }
  }
  return '<c r="$reference"$styleAttribute t="inlineStr">'
      '<is><t xml:space="preserve">${_escapeXml(cell.raw)}</t></is></c>';
}

String _xlsxNumber(double value) {
  if (value == value.roundToDouble() && value.abs() < 1e15) {
    return value.toInt().toString();
  }
  return value.toString();
}

/// Accumulates the distinct fonts, fills, alignments and number formats a
/// sheet uses and emits `styles.xml`.
class _XlsxStyleTable {
  final List<String> _fonts = [
    '<font><sz val="11"/><name val="Calibri"/></font>',
  ];
  final List<String> _fills = [
    '<fill><patternFill patternType="none"/></fill>',
    '<fill><patternFill patternType="gray125"/></fill>',
  ];
  final List<String> _numberFormats = [];
  final List<String> _borders = [
    '<border><left/><right/><top/><bottom/><diagonal/></border>',
  ];
  final List<String> _cellXfs = [
    '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>',
  ];
  final Map<String, int> _index = {};

  static const _firstCustomNumberFormat = 164;

  int indexFor(CellStyle style, {bool header = false}) {
    final key = '${style.hashCode}:$header';
    final existing = _index[key];
    if (existing != null) {
      return existing;
    }
    final fontId = _fontId(style, header: header);
    final fillId = _fillId(style, header: header);
    final borderId = _borderId(style);
    final numberFormatId = _numberFormatId(style);
    final alignment = switch (style.align) {
      CellAlign.center => '<alignment horizontal="center" vertical="center"/>',
      CellAlign.end => '<alignment horizontal="right" vertical="center"/>',
      CellAlign.start => '<alignment horizontal="left" vertical="center"/>',
      null => '<alignment vertical="center"/>',
    };
    final xf = '<xf numFmtId="$numberFormatId" fontId="$fontId" '
        'fillId="$fillId" borderId="$borderId" xfId="0" '
        'applyFont="1" applyFill="1" applyBorder="1" '
        'applyNumberFormat="1" applyAlignment="1">$alignment</xf>';
    _cellXfs.add(xf);
    final index = _cellXfs.length - 1;
    _index[key] = index;
    return index;
  }

  int _fontId(CellStyle style, {required bool header}) {
    final bold = style.bold || header;
    final buffer = StringBuffer('<font>');
    if (bold) {
      buffer.write('<b/>');
    }
    if (style.italic) {
      buffer.write('<i/>');
    }
    if (style.underline) {
      buffer.write('<u/>');
    }
    if (style.strikethrough) {
      buffer.write('<strike/>');
    }
    if (style.textColor != null) {
      buffer.write('<color rgb="${_argb(style.textColor!)}"/>');
    }
    buffer.write('<sz val="11"/><name val="Calibri"/></font>');
    return _intern(_fonts, buffer.toString());
  }

  int _fillId(CellStyle style, {required bool header}) {
    final color = style.backgroundColor ?? (header ? 0xFFF2F2F2 : null);
    if (color == null) {
      return 0;
    }
    final fill = '<fill><patternFill patternType="solid">'
        '<fgColor rgb="${_argb(color)}"/><bgColor indexed="64"/>'
        '</patternFill></fill>';
    return _intern(_fills, fill);
  }

  int _borderId(CellStyle style) {
    if (style.borders == CellBorders.none) {
      return 0;
    }
    String side(String name, bool enabled) =>
        enabled ? '<$name style="thin"><color auto="1"/></$name>' : '<$name/>';
    final border = '<border>'
        '${side('left', style.borders.left)}'
        '${side('right', style.borders.right)}'
        '${side('top', style.borders.top)}'
        '${side('bottom', style.borders.bottom)}'
        '<diagonal/></border>';
    return _intern(_borders, border);
  }

  int _numberFormatId(CellStyle style) {
    switch (style.format) {
      case CellNumberFormat.automatic:
        return 0;
      case CellNumberFormat.text:
        return 49;
      case CellNumberFormat.number:
        final decimals = style.decimals ?? 2;
        return _customNumberFormat(_decimalPattern(decimals));
      case CellNumberFormat.percent:
        final decimals = style.decimals ?? 0;
        return _customNumberFormat('${_decimalPattern(decimals)}%');
      case CellNumberFormat.currency:
        final decimals = style.decimals ?? 2;
        final symbol = style.currencySymbol ?? r'$';
        return _customNumberFormat(
          '"${_escapeXml(symbol)}"${_decimalPattern(decimals)}',
        );
      case CellNumberFormat.date:
        return 14;
      case CellNumberFormat.time:
        return 20;
    }
  }

  static String _decimalPattern(int decimals) =>
      decimals <= 0 ? '#,##0' : '#,##0.${'0' * decimals}';

  int _customNumberFormat(String code) {
    final existing = _numberFormats.indexOf(code);
    if (existing >= 0) {
      return _firstCustomNumberFormat + existing;
    }
    _numberFormats.add(code);
    return _firstCustomNumberFormat + _numberFormats.length - 1;
  }

  static int _intern(List<String> list, String value) {
    final existing = list.indexOf(value);
    if (existing >= 0) {
      return existing;
    }
    list.add(value);
    return list.length - 1;
  }

  static String _argb(int color) =>
      color.toRadixString(16).padLeft(8, '0').toUpperCase();

  String toXml() {
    final numberFormatsXml = StringBuffer();
    for (var index = 0; index < _numberFormats.length; index++) {
      numberFormatsXml.write(
        '<numFmt numFmtId="${_firstCustomNumberFormat + index}" '
        'formatCode="${_numberFormats[index]}"/>',
      );
    }
    return '$_xmlHeader'
        '<styleSheet xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main">'
        '${_numberFormats.isEmpty ? '' : '<numFmts count="${_numberFormats.length}">$numberFormatsXml</numFmts>'}'
        '<fonts count="${_fonts.length}">${_fonts.join()}</fonts>'
        '<fills count="${_fills.length}">${_fills.join()}</fills>'
        '<borders count="${_borders.length}">${_borders.join()}</borders>'
        '<cellStyleXfs count="1"><xf numFmtId="0" fontId="0" fillId="0" borderId="0"/></cellStyleXfs>'
        '<cellXfs count="${_cellXfs.length}">${_cellXfs.join()}</cellXfs>'
        '<cellStyles count="1"><cellStyle name="Normal" xfId="0" builtinId="0"/></cellStyles>'
        '</styleSheet>';
  }
}

String _escapeXml(String value) => value
    .replaceAll('&', '&amp;')
    .replaceAll('<', '&lt;')
    .replaceAll('>', '&gt;')
    .replaceAll('"', '&quot;')
    .replaceAll("'", '&apos;');

/// Reads the first worksheet of an `.xlsx` package into raw cell text.
///
/// Styles are not imported: the point is to get the numbers into the note, and
/// automatic type detection then formats them the AppFlowy way.
List<List<String>> decodeSpreadsheetXlsx(Uint8List bytes) {
  final archive = ZipDecoder().decodeBytes(bytes);
  final files = {
    for (final file in archive.files)
      if (file.isFile) file.name.replaceAll('\\', '/'): file,
  };

  final sharedStrings = <String>[];
  final sharedFile = files['xl/sharedStrings.xml'];
  if (sharedFile != null) {
    final document =
        XmlDocument.parse(utf8.decode(sharedFile.content as List<int>));
    for (final item in document.findAllElements('si')) {
      sharedStrings.add(
        item.findAllElements('t').map((node) => node.innerText).join(),
      );
    }
  }

  final sheetName = files.keys
      .where(
        (name) => name.startsWith('xl/worksheets/') && name.endsWith('.xml'),
      )
      .toList()
    ..sort();
  if (sheetName.isEmpty) {
    return const [];
  }
  final sheetFile = files[sheetName.first]!;
  final document =
      XmlDocument.parse(utf8.decode(sheetFile.content as List<int>));

  final values = <int, Map<int, String>>{};
  var maxColumn = 0;
  for (final rowNode in document.findAllElements('row')) {
    for (final cellNode in rowNode.findElements('c')) {
      final reference = cellNode.getAttribute('r');
      if (reference == null) {
        continue;
      }
      final ref = CellRef.parseA1(reference);
      if (ref == null) {
        continue;
      }
      final type = cellNode.getAttribute('t');
      String text;
      if (type == 'inlineStr') {
        text =
            cellNode.findAllElements('t').map((node) => node.innerText).join();
      } else {
        final raw =
            cellNode.findElements('v').map((node) => node.innerText).join();
        if (type == 's') {
          final index = int.tryParse(raw);
          text = index != null && index < sharedStrings.length
              ? sharedStrings[index]
              : '';
        } else {
          text = raw;
        }
      }
      final formula =
          cellNode.findElements('f').map((node) => node.innerText).join();
      if (formula.isNotEmpty) {
        text = '=$formula';
      }
      if (text.isEmpty) {
        continue;
      }
      values.putIfAbsent(ref.row, () => <int, String>{})[ref.column] = text;
      if (ref.column > maxColumn) {
        maxColumn = ref.column;
      }
    }
  }

  if (values.isEmpty) {
    return const [];
  }
  final maxRow = values.keys.reduce((a, b) => a > b ? a : b);
  return [
    for (var row = 0; row <= maxRow; row++)
      [
        for (var column = 0; column <= maxColumn; column++)
          values[row]?[column] ?? '',
      ],
  ];
}
