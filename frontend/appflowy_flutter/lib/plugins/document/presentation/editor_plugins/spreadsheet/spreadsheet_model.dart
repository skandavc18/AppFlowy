/// The data model behind the inline spreadsheet block.
///
/// Everything here is plain Dart with no Flutter widget dependency so the
/// grid, the formula engine, the importers and the tests can all share it.
library;

import 'dart:math' as math;
import 'dart:ui' show Color;

/// A zero-based cell coordinate.
class CellRef implements Comparable<CellRef> {
  const CellRef(this.row, this.column);

  final int row;
  final int column;

  /// Parses `A1`, `$A$1`, `bc12` style references. Returns null when the text
  /// is not a reference.
  static CellRef? parseA1(String input) {
    final text = input.replaceAll(r'$', '').trim();
    if (text.isEmpty) {
      return null;
    }
    var index = 0;
    var column = 0;
    while (index < text.length) {
      final code = text.codeUnitAt(index);
      final upper = code >= 97 && code <= 122 ? code - 32 : code;
      if (upper < 65 || upper > 90) {
        break;
      }
      column = column * 26 + (upper - 64);
      index++;
    }
    if (index == 0 || index >= text.length) {
      return null;
    }
    final row = int.tryParse(text.substring(index));
    if (row == null || row < 1) {
      return null;
    }
    return CellRef(row - 1, column - 1);
  }

  /// `0` -> `A`, `25` -> `Z`, `26` -> `AA`.
  static String columnLabel(int column) {
    if (column < 0) {
      return '';
    }
    final buffer = StringBuffer();
    var value = column;
    while (value >= 0) {
      buffer.write(String.fromCharCode(65 + value % 26));
      value = value ~/ 26 - 1;
    }
    return String.fromCharCodes(buffer.toString().codeUnits.reversed);
  }

  String get a1 => '${columnLabel(column)}${row + 1}';

  CellRef translate(int rowDelta, int columnDelta) =>
      CellRef(row + rowDelta, column + columnDelta);

  @override
  int compareTo(CellRef other) {
    final byRow = row.compareTo(other.row);
    return byRow != 0 ? byRow : column.compareTo(other.column);
  }

  @override
  bool operator ==(Object other) =>
      other is CellRef && other.row == row && other.column == column;

  @override
  int get hashCode => Object.hash(row, column);

  @override
  String toString() => a1;
}

/// A rectangular block of cells, always stored normalised.
class CellRange {
  CellRange(CellRef a, CellRef b)
      : top = math.min(a.row, b.row),
        left = math.min(a.column, b.column),
        bottom = math.max(a.row, b.row),
        right = math.max(a.column, b.column);

  const CellRange.raw({
    required this.top,
    required this.left,
    required this.bottom,
    required this.right,
  });

  CellRange.single(CellRef ref)
      : top = ref.row,
        left = ref.column,
        bottom = ref.row,
        right = ref.column;

  final int top;
  final int left;
  final int bottom;
  final int right;

  int get rowCount => bottom - top + 1;
  int get columnCount => right - left + 1;
  int get cellCount => rowCount * columnCount;
  bool get isSingle => cellCount == 1;

  CellRef get anchor => CellRef(top, left);

  bool contains(CellRef ref) =>
      ref.row >= top &&
      ref.row <= bottom &&
      ref.column >= left &&
      ref.column <= right;

  Iterable<CellRef> get cells sync* {
    for (var row = top; row <= bottom; row++) {
      for (var column = left; column <= right; column++) {
        yield CellRef(row, column);
      }
    }
  }

  @override
  bool operator ==(Object other) =>
      other is CellRange &&
      other.top == top &&
      other.left == left &&
      other.bottom == bottom &&
      other.right == right;

  @override
  int get hashCode => Object.hash(top, left, bottom, right);

  @override
  String toString() => '${CellRef(top, left).a1}:${CellRef(bottom, right).a1}';
}

/// How a cell's value is presented once it has been evaluated.
enum CellNumberFormat {
  /// Infer from the value — numbers right aligned, text left aligned.
  automatic,

  /// Never interpret the input as a number or a date.
  text,
  number,
  currency,
  percent,
  date,
  time;

  bool get isNumeric => this == number || this == currency || this == percent;

  static CellNumberFormat fromName(Object? value) {
    if (value is! String) {
      return CellNumberFormat.automatic;
    }
    return CellNumberFormat.values.firstWhere(
      (format) => format.name == value,
      orElse: () => CellNumberFormat.automatic,
    );
  }
}

enum CellAlign {
  start,
  center,
  end;

  static CellAlign? fromName(Object? value) {
    if (value is! String) {
      return null;
    }
    for (final align in CellAlign.values) {
      if (align.name == value) {
        return align;
      }
    }
    return null;
  }
}

/// Visual attributes of one cell. Immutable — cells are cheap to copy.
class CellStyle {
  const CellStyle({
    this.bold = false,
    this.italic = false,
    this.underline = false,
    this.strikethrough = false,
    this.align,
    this.textColor,
    this.backgroundColor,
    this.format = CellNumberFormat.automatic,
    this.decimals,
    this.currencySymbol,
    this.borders = CellBorders.none,
  });

  static const empty = CellStyle();

  final bool bold;
  final bool italic;
  final bool underline;
  final bool strikethrough;
  final CellAlign? align;
  final int? textColor;
  final int? backgroundColor;
  final CellNumberFormat format;
  final int? decimals;
  final String? currencySymbol;
  final CellBorders borders;

  bool get isEmpty =>
      !bold &&
      !italic &&
      !underline &&
      !strikethrough &&
      align == null &&
      textColor == null &&
      backgroundColor == null &&
      format == CellNumberFormat.automatic &&
      decimals == null &&
      currencySymbol == null &&
      borders == CellBorders.none;

  CellStyle copyWith({
    bool? bold,
    bool? italic,
    bool? underline,
    bool? strikethrough,
    CellAlign? align,
    bool clearAlign = false,
    int? textColor,
    bool clearTextColor = false,
    int? backgroundColor,
    bool clearBackgroundColor = false,
    CellNumberFormat? format,
    int? decimals,
    bool clearDecimals = false,
    String? currencySymbol,
    CellBorders? borders,
  }) {
    return CellStyle(
      bold: bold ?? this.bold,
      italic: italic ?? this.italic,
      underline: underline ?? this.underline,
      strikethrough: strikethrough ?? this.strikethrough,
      align: clearAlign ? null : (align ?? this.align),
      textColor: clearTextColor ? null : (textColor ?? this.textColor),
      backgroundColor: clearBackgroundColor
          ? null
          : (backgroundColor ?? this.backgroundColor),
      format: format ?? this.format,
      decimals: clearDecimals ? null : (decimals ?? this.decimals),
      currencySymbol: currencySymbol ?? this.currencySymbol,
      borders: borders ?? this.borders,
    );
  }

  Map<String, dynamic> toJson() => {
        if (bold) 'b': true,
        if (italic) 'i': true,
        if (underline) 'u': true,
        if (strikethrough) 's': true,
        if (align != null) 'a': align!.name,
        if (textColor != null) 'fg': textColor,
        if (backgroundColor != null) 'bg': backgroundColor,
        if (format != CellNumberFormat.automatic) 'nf': format.name,
        if (decimals != null) 'dp': decimals,
        if (currencySymbol != null) 'cur': currencySymbol,
        if (borders != CellBorders.none) 'bd': borders.mask,
      };

  static CellStyle fromJson(Map<dynamic, dynamic> json) => CellStyle(
        bold: json['b'] == true,
        italic: json['i'] == true,
        underline: json['u'] == true,
        strikethrough: json['s'] == true,
        align: CellAlign.fromName(json['a']),
        textColor: (json['fg'] as num?)?.toInt(),
        backgroundColor: (json['bg'] as num?)?.toInt(),
        format: CellNumberFormat.fromName(json['nf']),
        decimals: (json['dp'] as num?)?.toInt(),
        currencySymbol: json['cur'] as String?,
        borders: CellBorders.fromMask((json['bd'] as num?)?.toInt() ?? 0),
      );

  @override
  bool operator ==(Object other) =>
      other is CellStyle &&
      other.bold == bold &&
      other.italic == italic &&
      other.underline == underline &&
      other.strikethrough == strikethrough &&
      other.align == align &&
      other.textColor == textColor &&
      other.backgroundColor == backgroundColor &&
      other.format == format &&
      other.decimals == decimals &&
      other.currencySymbol == currencySymbol &&
      other.borders == borders;

  @override
  int get hashCode => Object.hash(
        bold,
        italic,
        underline,
        strikethrough,
        align,
        textColor,
        backgroundColor,
        format,
        decimals,
        currencySymbol,
        borders,
      );
}

/// Optional per-cell rules, kept as a bitmask so the payload stays small.
class CellBorders {
  const CellBorders({
    this.top = false,
    this.right = false,
    this.bottom = false,
    this.left = false,
  });

  static const none = CellBorders();
  static const all =
      CellBorders(top: true, right: true, bottom: true, left: true);

  final bool top;
  final bool right;
  final bool bottom;
  final bool left;

  int get mask =>
      (top ? 1 : 0) | (right ? 2 : 0) | (bottom ? 4 : 0) | (left ? 8 : 0);

  static CellBorders fromMask(int mask) => CellBorders(
        top: mask & 1 != 0,
        right: mask & 2 != 0,
        bottom: mask & 4 != 0,
        left: mask & 8 != 0,
      );

  @override
  bool operator ==(Object other) => other is CellBorders && other.mask == mask;

  @override
  int get hashCode => mask;
}

/// One stored cell: the text the user typed plus how it should look.
class SheetCell {
  const SheetCell({this.raw = '', this.style = CellStyle.empty});

  final String raw;
  final CellStyle style;

  bool get isEmpty => raw.isEmpty && style.isEmpty;
  bool get isFormula => raw.length > 1 && raw.startsWith('=');

  SheetCell copyWith({String? raw, CellStyle? style}) =>
      SheetCell(raw: raw ?? this.raw, style: style ?? this.style);

  Map<String, dynamic> toJson() => {
        if (raw.isNotEmpty) 'v': raw,
        ...style.toJson(),
      };

  static SheetCell fromJson(Map<dynamic, dynamic> json) => SheetCell(
        raw: json['v']?.toString() ?? '',
        style: CellStyle.fromJson(json),
      );

  @override
  bool operator ==(Object other) =>
      other is SheetCell && other.raw == raw && other.style == style;

  @override
  int get hashCode => Object.hash(raw, style);
}

class SheetColumn {
  const SheetColumn({
    this.width = defaultWidth,
    this.hidden = false,
    this.title = '',
  });

  static const double defaultWidth = 132;
  static const double minWidth = 56;
  static const double maxWidth = 720;

  final double width;
  final bool hidden;

  /// The column's name. Headers are column metadata, not a row of data, so
  /// `A1` always addresses the first cell a person can see.
  final String title;

  SheetColumn copyWith({double? width, bool? hidden, String? title}) =>
      SheetColumn(
        width: (width ?? this.width).clamp(minWidth, maxWidth).toDouble(),
        hidden: hidden ?? this.hidden,
        title: title ?? this.title,
      );

  Map<String, dynamic> toJson() => {
        if (width != defaultWidth) 'w': width,
        if (hidden) 'h': true,
        if (title.isNotEmpty) 't': title,
      };

  static SheetColumn fromJson(Map<dynamic, dynamic> json) => SheetColumn(
        width: (json['w'] as num?)?.toDouble() ?? defaultWidth,
        hidden: json['h'] == true,
        title: json['t']?.toString() ?? '',
      );
}

class SheetRow {
  const SheetRow({this.height = defaultHeight, this.hidden = false});

  static const double defaultHeight = 34;
  static const double minHeight = 26;
  static const double maxHeight = 400;

  final double height;
  final bool hidden;

  SheetRow copyWith({double? height, bool? hidden}) => SheetRow(
        height: (height ?? this.height).clamp(minHeight, maxHeight).toDouble(),
        hidden: hidden ?? this.hidden,
      );

  Map<String, dynamic> toJson() => {
        if (height != defaultHeight) 'h': height,
        if (hidden) 'x': true,
      };

  static SheetRow fromJson(Map<dynamic, dynamic> json) => SheetRow(
        height: (json['h'] as num?)?.toDouble() ?? defaultHeight,
        hidden: json['x'] == true,
      );
}

enum SortDirection { ascending, descending }

/// A single-column sort applied to the body rows.
class SheetSort {
  const SheetSort({required this.column, required this.direction});

  final int column;
  final SortDirection direction;

  Map<String, dynamic> toJson() => {
        'c': column,
        'd': direction.name,
      };

  static SheetSort? fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) {
      return null;
    }
    final column = (json['c'] as num?)?.toInt();
    if (column == null) {
      return null;
    }
    return SheetSort(
      column: column,
      direction: json['d'] == SortDirection.descending.name
          ? SortDirection.descending
          : SortDirection.ascending,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is SheetSort &&
      other.column == column &&
      other.direction == direction;

  @override
  int get hashCode => Object.hash(column, direction);
}

/// A contains-text filter on one column.
class SheetFilter {
  const SheetFilter({required this.column, required this.query});

  final int column;
  final String query;

  Map<String, dynamic> toJson() => {'c': column, 'q': query};

  static SheetFilter? fromJson(Map<dynamic, dynamic> json) {
    final column = (json['c'] as num?)?.toInt();
    final query = json['q'] as String?;
    if (column == null || query == null || query.isEmpty) {
      return null;
    }
    return SheetFilter(column: column, query: query);
  }

  @override
  bool operator ==(Object other) =>
      other is SheetFilter && other.column == column && other.query == query;

  @override
  int get hashCode => Object.hash(column, query);
}

/// The whole grid. Mutable by design: a spreadsheet edit touches one cell and
/// rebuilding an immutable map of thousands of entries per keystroke is what
/// makes naive implementations feel slow. Undo takes an explicit [clone].
class SpreadsheetData {
  SpreadsheetData({
    required this.rowCount,
    required this.columnCount,
    Map<CellRef, SheetCell>? cells,
    List<SheetColumn>? columns,
    Map<int, SheetRow>? rows,
    this.showHeader = true,
    this.sort,
    List<SheetFilter>? filters,
  })  : _cells = cells ?? <CellRef, SheetCell>{},
        _columns = columns ?? <SheetColumn>[],
        _rows = rows ?? <int, SheetRow>{},
        filters = filters ?? <SheetFilter>[];

  factory SpreadsheetData.empty({int rows = 6, int columns = 4}) =>
      SpreadsheetData(rowCount: rows, columnCount: columns);

  /// Builds a grid from a rectangular list of raw strings.
  ///
  /// With [headerRow] set, the first list becomes the column names rather than
  /// the first row of data.
  factory SpreadsheetData.fromRows(
    List<List<String>> values, {
    bool headerRow = true,
    int minRows = 4,
    int minColumns = 3,
  }) {
    final titles = headerRow && values.isNotEmpty ? values.first : null;
    final body =
        headerRow && values.isNotEmpty ? values.skip(1).toList() : values;
    final columnCount = math.max(
      minColumns,
      math.max(
        titles?.length ?? 0,
        body.fold<int>(0, (best, row) => math.max(best, row.length)),
      ),
    );
    final rowCount = math.max(minRows, body.length);
    final cells = <CellRef, SheetCell>{};
    for (var row = 0; row < body.length; row++) {
      for (var column = 0; column < body[row].length; column++) {
        final raw = body[row][column];
        if (raw.isEmpty) {
          continue;
        }
        cells[CellRef(row, column)] = SheetCell(raw: raw);
      }
    }
    final columns = <SheetColumn>[];
    if (titles != null) {
      for (var index = 0; index < columnCount; index++) {
        columns.add(
          SheetColumn(title: index < titles.length ? titles[index] : ''),
        );
      }
    }
    return SpreadsheetData(
      rowCount: rowCount,
      columnCount: columnCount,
      cells: cells,
      columns: columns,
      showHeader: headerRow,
    );
  }

  static const int maxRows = 20000;
  static const int maxColumns = 256;

  /// Bumped when the stored shape changes. Version 1 kept the header in row 0.
  static const int schemaVersion = 2;

  int rowCount;
  int columnCount;

  /// Whether the column-name strip is shown. It is never a row of data.
  bool showHeader;
  SheetSort? sort;
  List<SheetFilter> filters;

  final Map<CellRef, SheetCell> _cells;
  final List<SheetColumn> _columns;
  final Map<int, SheetRow> _rows;

  Map<CellRef, SheetCell> get cells => _cells;

  /// True when nothing has been typed yet, whatever the grid's dimensions.
  bool get isEmpty => _cells.values.every((cell) => cell.raw.isEmpty);

  SheetCell cellAt(CellRef ref) => _cells[ref] ?? const SheetCell();

  String rawAt(CellRef ref) => _cells[ref]?.raw ?? '';

  CellStyle styleAt(CellRef ref) => _cells[ref]?.style ?? CellStyle.empty;

  void setCell(CellRef ref, SheetCell cell) {
    if (cell.isEmpty) {
      _cells.remove(ref);
    } else {
      _cells[ref] = cell;
    }
  }

  void setRaw(CellRef ref, String raw) =>
      setCell(ref, cellAt(ref).copyWith(raw: raw));

  void setStyle(CellRef ref, CellStyle style) =>
      setCell(ref, cellAt(ref).copyWith(style: style));

  SheetColumn column(int index) =>
      index >= 0 && index < _columns.length ? _columns[index] : _defaultColumn;

  String columnTitle(int index) => column(index).title;

  void setColumnTitle(int index, String title) =>
      setColumn(index, column(index).copyWith(title: title));

  /// What the header strip shows for a column: its name, or its letter when
  /// it has not been named or names are turned off.
  String headerLabel(int index) {
    if (!showHeader) {
      return CellRef.columnLabel(index);
    }
    final title = columnTitle(index);
    return title.isEmpty ? CellRef.columnLabel(index) : title;
  }

  List<String> get columnTitles =>
      [for (var index = 0; index < columnCount; index++) columnTitle(index)];

  SheetRow row(int index) => _rows[index] ?? _defaultRow;

  static const _defaultColumn = SheetColumn();
  static const _defaultRow = SheetRow();

  double columnWidth(int index) {
    final spec = column(index);
    return spec.hidden ? 0 : spec.width;
  }

  double rowHeight(int index) {
    final spec = row(index);
    return spec.hidden ? 0 : spec.height;
  }

  bool isColumnHidden(int index) => column(index).hidden;

  void setColumn(int index, SheetColumn spec) {
    while (_columns.length <= index) {
      _columns.add(const SheetColumn());
    }
    _columns[index] = spec;
  }

  void setRowSpec(int index, SheetRow spec) {
    if (spec.height == SheetRow.defaultHeight && !spec.hidden) {
      _rows.remove(index);
    } else {
      _rows[index] = spec;
    }
  }

  double get totalWidth {
    var total = 0.0;
    for (var index = 0; index < columnCount; index++) {
      total += columnWidth(index);
    }
    return total;
  }

  /// Offset of a column's left edge from the start of the grid.
  double columnOffset(int index) {
    var offset = 0.0;
    for (var i = 0; i < index && i < columnCount; i++) {
      offset += columnWidth(i);
    }
    return offset;
  }

  // ---------------------------------------------------------------------
  // Structure
  // ---------------------------------------------------------------------

  void insertRows(int at, int count) {
    if (count <= 0 || rowCount + count > maxRows) {
      return;
    }
    _shiftRows(at, count);
    rowCount += count;
  }

  void deleteRows(int at, int count) {
    final removable = math.min(count, rowCount - at);
    if (removable <= 0 || rowCount - removable < 1) {
      return;
    }
    for (final ref in _cells.keys.toList(growable: false)) {
      if (ref.row >= at && ref.row < at + removable) {
        _cells.remove(ref);
      }
    }
    _shiftRows(at + removable, -removable);
    rowCount -= removable;
  }

  void _shiftRows(int from, int delta) {
    final moved = <CellRef, SheetCell>{};
    for (final entry in _cells.entries.toList(growable: false)) {
      if (entry.key.row >= from) {
        _cells.remove(entry.key);
        moved[entry.key.translate(delta, 0)] = entry.value;
      }
    }
    _cells.addAll(moved);

    final movedRows = <int, SheetRow>{};
    for (final entry in _rows.entries.toList(growable: false)) {
      if (entry.key >= from) {
        _rows.remove(entry.key);
        movedRows[entry.key + delta] = entry.value;
      }
    }
    _rows.addAll(movedRows);
  }

  void insertColumns(int at, int count) {
    if (count <= 0 || columnCount + count > maxColumns) {
      return;
    }
    _shiftColumns(at, count);
    while (_columns.length < columnCount) {
      _columns.add(const SheetColumn());
    }
    for (var i = 0; i < count; i++) {
      if (at <= _columns.length) {
        _columns.insert(at, const SheetColumn());
      }
    }
    columnCount += count;
  }

  void deleteColumns(int at, int count) {
    final removable = math.min(count, columnCount - at);
    if (removable <= 0 || columnCount - removable < 1) {
      return;
    }
    for (final ref in _cells.keys.toList(growable: false)) {
      if (ref.column >= at && ref.column < at + removable) {
        _cells.remove(ref);
      }
    }
    _shiftColumns(at + removable, -removable);
    while (_columns.length < columnCount) {
      _columns.add(const SheetColumn());
    }
    for (var i = 0; i < removable; i++) {
      if (at < _columns.length) {
        _columns.removeAt(at);
      }
    }
    columnCount -= removable;
  }

  void _shiftColumns(int from, int delta) {
    final moved = <CellRef, SheetCell>{};
    for (final entry in _cells.entries.toList(growable: false)) {
      if (entry.key.column >= from) {
        _cells.remove(entry.key);
        moved[entry.key.translate(0, delta)] = entry.value;
      }
    }
    _cells.addAll(moved);
  }

  /// Moves a column and its stored cells to a new index.
  void moveColumn(int from, int to) {
    if (from == to ||
        from < 0 ||
        to < 0 ||
        from >= columnCount ||
        to >= columnCount) {
      return;
    }
    final order = List<int>.generate(columnCount, (index) => index);
    order.insert(to, order.removeAt(from));
    final remapped = <CellRef, SheetCell>{};
    for (final entry in _cells.entries) {
      final target = order.indexOf(entry.key.column);
      remapped[CellRef(entry.key.row, target)] = entry.value;
    }
    _cells
      ..clear()
      ..addAll(remapped);

    while (_columns.length < columnCount) {
      _columns.add(const SheetColumn());
    }
    _columns.insert(to, _columns.removeAt(from));
  }

  SpreadsheetData clone() => SpreadsheetData(
        rowCount: rowCount,
        columnCount: columnCount,
        cells: Map<CellRef, SheetCell>.of(_cells),
        columns: List<SheetColumn>.of(_columns),
        rows: Map<int, SheetRow>.of(_rows),
        showHeader: showHeader,
        sort: sort,
        filters: List<SheetFilter>.of(filters),
      );

  /// Raw values as a rectangular list, trimmed to the used range.
  List<List<String>> toRows({bool trim = true}) {
    var lastRow = rowCount - 1;
    var lastColumn = columnCount - 1;
    if (trim) {
      lastRow = -1;
      lastColumn = -1;
      for (final entry in _cells.entries) {
        if (entry.value.raw.isEmpty) {
          continue;
        }
        lastRow = math.max(lastRow, entry.key.row);
        lastColumn = math.max(lastColumn, entry.key.column);
      }
    }
    return [
      for (var row = 0; row <= lastRow; row++)
        [
          for (var column = 0; column <= lastColumn; column++)
            rawAt(CellRef(row, column)),
        ],
    ];
  }

  Map<String, dynamic> toJson() {
    final cellJson = <String, dynamic>{};
    for (final entry in _cells.entries) {
      if (entry.value.isEmpty) {
        continue;
      }
      cellJson['${entry.key.row}:${entry.key.column}'] = entry.value.toJson();
    }
    final columnJson = <String, dynamic>{};
    for (var index = 0; index < _columns.length; index++) {
      final json = _columns[index].toJson();
      if (json.isNotEmpty) {
        columnJson['$index'] = json;
      }
    }
    final rowJson = <String, dynamic>{};
    for (final entry in _rows.entries) {
      final json = entry.value.toJson();
      if (json.isNotEmpty) {
        rowJson['${entry.key}'] = json;
      }
    }
    return {
      'v': schemaVersion,
      'rows': rowCount,
      'columns': columnCount,
      'header': showHeader,
      if (cellJson.isNotEmpty) 'cells': cellJson,
      if (columnJson.isNotEmpty) 'cols': columnJson,
      if (rowJson.isNotEmpty) 'rowSpecs': rowJson,
      if (sort != null) 'sort': sort!.toJson(),
      if (filters.isNotEmpty)
        'filters': filters.map((filter) => filter.toJson()).toList(),
    };
  }

  static SpreadsheetData fromJson(Map<dynamic, dynamic>? json) {
    if (json == null) {
      return SpreadsheetData.empty();
    }
    final rowCount =
        ((json['rows'] as num?)?.toInt() ?? 6).clamp(1, maxRows).toInt();
    final columnCount =
        ((json['columns'] as num?)?.toInt() ?? 4).clamp(1, maxColumns).toInt();

    final cells = <CellRef, SheetCell>{};
    final cellJson = json['cells'];
    if (cellJson is Map) {
      for (final entry in cellJson.entries) {
        final parts = entry.key.toString().split(':');
        if (parts.length != 2) {
          continue;
        }
        final row = int.tryParse(parts[0]);
        final column = int.tryParse(parts[1]);
        if (row == null || column == null) {
          continue;
        }
        if (entry.value is Map) {
          final cell = SheetCell.fromJson(entry.value as Map);
          if (!cell.isEmpty) {
            cells[CellRef(row, column)] = cell;
          }
        }
      }
    }

    final columns = <SheetColumn>[];
    final columnJson = json['cols'];
    if (columnJson is Map) {
      for (final entry in columnJson.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index == null || entry.value is! Map) {
          continue;
        }
        while (columns.length <= index) {
          columns.add(const SheetColumn());
        }
        columns[index] = SheetColumn.fromJson(entry.value as Map);
      }
    }

    final rows = <int, SheetRow>{};
    final rowJson = json['rowSpecs'];
    if (rowJson is Map) {
      for (final entry in rowJson.entries) {
        final index = int.tryParse(entry.key.toString());
        if (index == null || entry.value is! Map) {
          continue;
        }
        rows[index] = SheetRow.fromJson(entry.value as Map);
      }
    }

    final filters = <SheetFilter>[];
    final filterJson = json['filters'];
    if (filterJson is List) {
      for (final entry in filterJson) {
        if (entry is Map) {
          final filter = SheetFilter.fromJson(entry);
          if (filter != null) {
            filters.add(filter);
          }
        }
      }
    }

    final data = SpreadsheetData(
      rowCount: rowCount,
      columnCount: columnCount,
      cells: cells,
      columns: columns,
      rows: rows,
      showHeader: json['header'] != false,
      sort: SheetSort.fromJson(json['sort'] as Map<dynamic, dynamic>?),
      filters: filters,
    );

    // Version 1 kept the header in row 0, which meant `A1` addressed a row
    // nobody could point at. Lift it into the column names and close the gap.
    final version = (json['v'] as num?)?.toInt() ?? 1;
    if (version < SpreadsheetData.schemaVersion && data.showHeader) {
      for (var column = 0; column < data.columnCount; column++) {
        final title = data.rawAt(CellRef(0, column));
        if (title.isNotEmpty) {
          data.setColumnTitle(column, title);
        }
      }
      data.deleteRows(0, 1);
    }
    return data;
  }
}

/// Utility for reading an ARGB int back into a [Color].
Color colorFromValue(int value) => Color(value);
