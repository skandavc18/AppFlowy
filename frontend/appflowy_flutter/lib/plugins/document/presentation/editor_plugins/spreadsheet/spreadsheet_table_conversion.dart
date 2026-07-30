/// Conversions between the editor's table blocks and the spreadsheet model.
///
/// Values always survive the round trip; formatting survives wherever the two
/// models agree on what a thing means.
library;

import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table.dart';
import 'package:appflowy_editor/appflowy_editor.dart';

import 'spreadsheet_codec.dart';
import 'spreadsheet_model.dart';

/// Whether [node] is a table that can be upgraded to a spreadsheet.
bool isConvertibleTable(Node node) =>
    node.type == SimpleTableBlockKeys.type || node.type == TableBlockKeys.type;

/// Reads a table block into a spreadsheet, keeping bold, alignment, colours
/// and column widths where the table recorded them.
SpreadsheetData spreadsheetFromTable(Node node) {
  if (node.type == TableBlockKeys.type) {
    return _fromLegacyTable(node);
  }
  return _fromSimpleTable(node);
}

SpreadsheetData _fromSimpleTable(Node table) {
  final rows = table.children
      .where((child) => child.type == SimpleTableRowBlockKeys.type)
      .toList();
  final columnCount = rows.fold<int>(
    0,
    (best, row) => math.max(best, row.children.length),
  );
  final hasHeader =
      table.attributes[SimpleTableBlockKeys.enableHeaderRow] == true;
  // A table's header row becomes column names: the sheet keeps headers as
  // column metadata so `A1` always addresses the first visible cell.
  final bodyOffset = hasHeader ? 1 : 0;
  final data = SpreadsheetData(
    rowCount: math.max(rows.length - bodyOffset, 1),
    columnCount: math.max(columnCount, 1),
    showHeader: hasHeader,
  );

  final columnAligns = _stringMap(
    table.attributes[SimpleTableBlockKeys.columnAligns],
  );
  final rowAligns =
      _stringMap(table.attributes[SimpleTableBlockKeys.rowAligns]);
  final columnColors =
      _stringMap(table.attributes[SimpleTableBlockKeys.columnColors]);
  final rowColors =
      _stringMap(table.attributes[SimpleTableBlockKeys.rowColors]);
  final columnTextColors =
      _stringMap(table.attributes[SimpleTableBlockKeys.columnTextColors]);
  final rowTextColors =
      _stringMap(table.attributes[SimpleTableBlockKeys.rowTextColors]);
  final columnBold =
      _boolMap(table.attributes[SimpleTableBlockKeys.columnBoldAttributes]);
  final rowBold =
      _boolMap(table.attributes[SimpleTableBlockKeys.rowBoldAttributes]);
  final columnWidths =
      _doubleMap(table.attributes[SimpleTableBlockKeys.columnWidths]);

  for (final entry in columnWidths.entries) {
    data.setColumn(entry.key, SheetColumn(width: entry.value));
  }

  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final cells = rows[rowIndex]
        .children
        .where((child) => child.type == SimpleTableCellBlockKeys.type)
        .toList();
    for (var columnIndex = 0; columnIndex < cells.length; columnIndex++) {
      final inline = _readCell(cells[columnIndex]);
      if (hasHeader && rowIndex == 0) {
        if (inline.text.isNotEmpty) {
          data.setColumnTitle(columnIndex, inline.text);
        }
        continue;
      }
      final ref = CellRef(rowIndex - bodyOffset, columnIndex);
      if (inline.text.isEmpty &&
          !inline.bold &&
          inline.textColor == null &&
          inline.backgroundColor == null) {
        continue;
      }
      final align = CellAlign.fromName(columnAligns[columnIndex]) ??
          CellAlign.fromName(rowAligns[rowIndex]);
      final background = _parseColor(columnColors[columnIndex]) ??
          _parseColor(rowColors[rowIndex]) ??
          inline.backgroundColor;
      final foreground = inline.textColor ??
          _parseColor(columnTextColors[columnIndex]) ??
          _parseColor(rowTextColors[rowIndex]);
      data.setCell(
        ref,
        SheetCell(
          raw: inline.text,
          style: CellStyle(
            bold: inline.bold ||
                (columnBold[columnIndex] ?? false) ||
                (rowBold[rowIndex] ?? false),
            italic: inline.italic,
            underline: inline.underline,
            strikethrough: inline.strikethrough,
            align: align,
            textColor: foreground,
            backgroundColor: background,
          ),
        ),
      );
    }
  }
  return data;
}

SpreadsheetData _fromLegacyTable(Node table) {
  final columnCount =
      (table.attributes[TableBlockKeys.colsLen] as num?)?.toInt() ?? 0;
  final rowCount =
      (table.attributes[TableBlockKeys.rowsLen] as num?)?.toInt() ?? 0;
  final data = SpreadsheetData(
    rowCount: math.max(rowCount, 1),
    columnCount: math.max(columnCount, 1),
  );
  for (final cell in table.children) {
    final column =
        (cell.attributes[TableCellBlockKeys.colPosition] as num?)?.toInt();
    final row =
        (cell.attributes[TableCellBlockKeys.rowPosition] as num?)?.toInt();
    if (column == null || row == null) {
      continue;
    }
    final inline = _readCell(cell);
    if (inline.text.isEmpty) {
      continue;
    }
    data.setCell(
      CellRef(row, column),
      SheetCell(
        raw: inline.text,
        style: CellStyle(
          bold: inline.bold,
          italic: inline.italic,
          underline: inline.underline,
          strikethrough: inline.strikethrough,
          textColor: inline.textColor,
        ),
      ),
    );
  }
  return data;
}

/// Renders the sheet back into a simple table block.
///
/// Formulas are written as their computed values — a table has nowhere to keep
/// the expression, and showing `=SUM(A1:A4)` as literal text would be worse
/// than losing it.
Node simpleTableFromSpreadsheet(SpreadsheetData data) {
  final rows = spreadsheetDisplayRows(data, includeHeader: true);
  if (rows.isEmpty) {
    return createSimpleTableBlockNode(columnCount: 2, rowCount: 2);
  }
  final columnCount =
      rows.fold<int>(1, (best, row) => math.max(best, row.length));
  final bodyOffset = data.showHeader ? 1 : 0;

  final columnAligns = <String, String>{};
  final columnWidths = <String, double>{};
  for (var column = 0; column < columnCount; column++) {
    final spec = data.column(column);
    if (spec.width != SheetColumn.defaultWidth) {
      columnWidths['$column'] = spec.width;
    }
    final align = data.styleAt(CellRef(0, column)).align;
    if (align != null) {
      columnAligns['$column'] = align.name;
    }
  }

  final tableRows = <Node>[];
  for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
    final cells = <Node>[];
    final isHeader = data.showHeader && rowIndex == 0;
    for (var column = 0; column < columnCount; column++) {
      final style = isHeader
          ? const CellStyle(bold: true)
          : data.styleAt(CellRef(rowIndex - bodyOffset, column));
      final text = column < rows[rowIndex].length ? rows[rowIndex][column] : '';
      final attributes = <String, dynamic>{
        if (style.bold) AppFlowyRichTextKeys.bold: true,
        if (style.italic) AppFlowyRichTextKeys.italic: true,
        if (style.underline) AppFlowyRichTextKeys.underline: true,
        if (style.strikethrough) AppFlowyRichTextKeys.strikethrough: true,
        if (style.textColor != null)
          AppFlowyRichTextKeys.textColor: _hex(style.textColor!),
        if (style.backgroundColor != null)
          AppFlowyRichTextKeys.backgroundColor: _hex(style.backgroundColor!),
      };
      cells.add(
        simpleTableCellBlockNode(
          children: [
            paragraphNode(
              delta: text.isEmpty
                  ? Delta()
                  : (Delta()
                    ..insert(
                      text,
                      attributes: attributes.isEmpty ? null : attributes,
                    )),
            ),
          ],
        ),
      );
    }
    tableRows.add(simpleTableRowBlockNode(children: cells));
  }

  return simpleTableBlockNode(
    enableHeaderRow: data.showHeader,
    columnAligns: columnAligns.isEmpty ? null : columnAligns,
    columnWidths: columnWidths.isEmpty ? null : columnWidths,
    children: tableRows,
  );
}

class _InlineCell {
  const _InlineCell({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.textColor,
    this.backgroundColor,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final int? textColor;
  final int? backgroundColor;
}

/// Flattens a table cell's paragraphs into one line, reading the formatting
/// off the first run that carries any.
_InlineCell _readCell(Node cell) {
  final buffer = StringBuffer();
  Attributes? formatting;
  for (final child in cell.children) {
    final delta = child.delta;
    if (delta == null) {
      continue;
    }
    final text = delta.toPlainText();
    if (text.isEmpty) {
      continue;
    }
    if (buffer.isNotEmpty) {
      buffer.write(' ');
    }
    buffer.write(text);
    for (final operation in delta) {
      if (operation.attributes?.isNotEmpty ?? false) {
        formatting ??= operation.attributes;
        break;
      }
    }
  }
  return _InlineCell(
    text: buffer.toString(),
    bold: formatting?[AppFlowyRichTextKeys.bold] == true,
    italic: formatting?[AppFlowyRichTextKeys.italic] == true,
    underline: formatting?[AppFlowyRichTextKeys.underline] == true,
    strikethrough: formatting?[AppFlowyRichTextKeys.strikethrough] == true,
    textColor: _parseColor(formatting?[AppFlowyRichTextKeys.textColor]),
    backgroundColor:
        _parseColor(formatting?[AppFlowyRichTextKeys.backgroundColor]),
  );
}

Map<int, String> _stringMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final result = <int, String>{};
  for (final entry in value.entries) {
    final index = int.tryParse(entry.key.toString());
    if (index != null && entry.value is String) {
      result[index] = entry.value as String;
    }
  }
  return result;
}

Map<int, bool> _boolMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final result = <int, bool>{};
  for (final entry in value.entries) {
    final index = int.tryParse(entry.key.toString());
    if (index != null) {
      result[index] = entry.value == true;
    }
  }
  return result;
}

Map<int, double> _doubleMap(Object? value) {
  if (value is! Map) {
    return const {};
  }
  final result = <int, double>{};
  for (final entry in value.entries) {
    final index = int.tryParse(entry.key.toString());
    final width = entry.value;
    if (index != null && width is num) {
      result[index] = width.toDouble();
    }
  }
  return result;
}

/// Accepts the shapes AppFlowy stores colours in: `0xAARRGGBB` and `#RRGGBB`.
int? _parseColor(Object? value) {
  if (value is num) {
    return value.toInt();
  }
  if (value is! String || value.isEmpty) {
    return null;
  }
  var text = value.trim();
  if (text.startsWith('#')) {
    text = text.substring(1);
    if (text.length == 6) {
      text = 'ff$text';
    }
    return int.tryParse(text, radix: 16);
  }
  if (text.toLowerCase().startsWith('0x')) {
    return int.tryParse(text.substring(2), radix: 16);
  }
  return int.tryParse(text, radix: 16);
}

String _hex(int color) =>
    '0x${color.toRadixString(16).padLeft(8, '0').toUpperCase()}';
