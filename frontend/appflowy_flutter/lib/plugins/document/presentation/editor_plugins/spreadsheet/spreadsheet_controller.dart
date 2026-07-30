import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'spreadsheet_codec.dart';
import 'spreadsheet_format.dart';
import 'spreadsheet_formula.dart';
import 'spreadsheet_model.dart';

/// Owns every piece of live spreadsheet state: what is selected, what is being
/// typed, the undo stack and the derived view after filtering.
///
/// The widget layer is a pure function of this controller.
class SpreadsheetController extends ChangeNotifier {
  SpreadsheetController({
    required SpreadsheetData data,
    this.onChanged,
    this.editable = true,
  })  : _data = data,
        _evaluator = SpreadsheetEvaluator(data) {
    _rebuildView();
  }

  static const int _maxHistory = 80;
  static const Duration persistDebounce = Duration(milliseconds: 350);

  final bool editable;

  /// Called after an edit settles, with the data that should be persisted.
  final ValueChanged<SpreadsheetData>? onChanged;

  SpreadsheetData _data;
  SpreadsheetEvaluator _evaluator;
  Timer? _persistTimer;

  final List<SpreadsheetData> _undoStack = [];
  final List<SpreadsheetData> _redoStack = [];

  CellRef _active = const CellRef(0, 0);
  CellRef _anchor = const CellRef(0, 0);
  CellRef? _editing;
  int? _editingHeader;
  String _editingText = '';
  bool _editingFromKeystroke = false;

  int? _hoveredRow;
  int? _selectedColumnHeader;
  List<int> _view = const [];
  String _search = '';
  List<CellRef> _matches = const [];
  int _matchIndex = -1;

  /// Cells copied inside the app, kept so styles survive a copy/paste.
  static List<List<SheetCell>>? _internalClipboard;

  SpreadsheetData get data => _data;
  SpreadsheetEvaluator get evaluator => _evaluator;

  /// Bumped whenever the grid's contents or geometry change.
  ///
  /// Pointer hover also notifies listeners, and recomputing row offsets for
  /// thousands of rows on every mouse move is exactly the kind of work that
  /// makes a sheet feel heavy — the view layer compares this instead.
  int get revision => _revision;
  int _revision = 0;

  CellRef get active => _active;
  CellRef get anchor => _anchor;
  CellRange get selection => CellRange(_anchor, _active);
  CellRef? get editing => _editing;

  /// The column whose name is being renamed, if any.
  int? get editingHeader => _editingHeader;

  bool get isEditing => _editing != null || _editingHeader != null;

  String get editingText => _editingText;
  bool get editingFromKeystroke => _editingFromKeystroke;
  int? get hoveredRow => _hoveredRow;
  int? get selectedColumnHeader => _selectedColumnHeader;

  bool get canUndo => _undoStack.isNotEmpty;
  bool get canRedo => _redoStack.isNotEmpty;

  String get searchQuery => _search;
  List<CellRef> get searchMatches => _matches;
  int get searchMatchIndex => _matchIndex;
  CellRef? get currentSearchMatch =>
      _matchIndex >= 0 && _matchIndex < _matches.length
          ? _matches[_matchIndex]
          : null;

  /// Source row indices in display order, after filtering.
  List<int> get visibleRows => _view;

  @override
  void dispose() {
    _persistTimer?.cancel();
    super.dispose();
  }

  // -------------------------------------------------------------------
  // View
  // -------------------------------------------------------------------

  void _rebuildView() {
    final rows = <int>[];
    for (var row = 0; row < _data.rowCount; row++) {
      if (_data.row(row).hidden) {
        continue;
      }
      if (_passesFilters(row)) {
        rows.add(row);
      }
    }
    _view = rows;
  }

  bool _passesFilters(int row) {
    if (_data.filters.isEmpty) {
      return true;
    }
    for (final filter in _data.filters) {
      final text = displayTextAt(CellRef(row, filter.column));
      if (!text.toLowerCase().contains(filter.query.toLowerCase())) {
        return false;
      }
    }
    return true;
  }

  /// Position of a source row in the filtered view, or -1.
  int viewIndexOf(int sourceRow) => _view.indexOf(sourceRow);

  /// The text a cell shows when it is not being edited.
  String displayTextAt(CellRef ref) {
    final cell = _data.cellAt(ref);
    if (cell.raw.isEmpty) {
      return '';
    }
    return formatCellValue(
      _evaluator.valueAt(ref),
      cell.style,
      raw: cell.raw,
    );
  }

  SheetValue valueAt(CellRef ref) => _evaluator.valueAt(ref);

  // -------------------------------------------------------------------
  // Mutation plumbing
  // -------------------------------------------------------------------

  /// Runs [action] against the data as one undoable step.
  void mutate(
    void Function(SpreadsheetData data) action, {
    bool persist = true,
  }) {
    if (!editable) {
      return;
    }
    _pushUndo();
    action(_data);
    _afterMutation(persist: persist);
  }

  void _afterMutation({bool persist = true}) {
    _revision++;
    _evaluator = SpreadsheetEvaluator(_data);
    _rebuildView();
    _clampSelection();
    if (_search.isNotEmpty) {
      _recomputeMatches(keepIndex: true);
    }
    notifyListeners();
    if (persist) {
      _schedulePersist();
    }
  }

  void _pushUndo() {
    _undoStack.add(_data.clone());
    if (_undoStack.length > _maxHistory) {
      _undoStack.removeAt(0);
    }
    _redoStack.clear();
  }

  void _schedulePersist() {
    if (onChanged == null) {
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, flushPersist);
  }

  /// Writes pending changes out immediately.
  void flushPersist() {
    _persistTimer?.cancel();
    _persistTimer = null;
    onChanged?.call(_data);
  }

  void undo() {
    if (_undoStack.isEmpty) {
      return;
    }
    _redoStack.add(_data.clone());
    _data = _undoStack.removeLast();
    cancelEditing();
    _afterMutation();
  }

  void redo() {
    if (_redoStack.isEmpty) {
      return;
    }
    _undoStack.add(_data.clone());
    _data = _redoStack.removeLast();
    cancelEditing();
    _afterMutation();
  }

  /// Replaces the whole grid, e.g. after an import.
  void replaceData(SpreadsheetData next) {
    if (!editable) {
      return;
    }
    _pushUndo();
    _data = next;
    cancelEditing();
    _active = const CellRef(0, 0);
    _anchor = _active;
    _afterMutation();
  }

  // -------------------------------------------------------------------
  // Selection
  // -------------------------------------------------------------------

  void selectCell(CellRef ref, {bool extend = false}) {
    final clamped = _clamp(ref);
    if (_editing != null && _editing != clamped) {
      commitEditing();
    }
    _active = clamped;
    if (!extend) {
      _anchor = clamped;
    }
    _selectedColumnHeader = null;
    notifyListeners();
  }

  void selectRange(CellRef anchor, CellRef focus) {
    _anchor = _clamp(anchor);
    _active = _clamp(focus);
    _selectedColumnHeader = null;
    notifyListeners();
  }

  void selectColumn(int column) {
    final index = column.clamp(0, _data.columnCount - 1);
    _anchor = CellRef(0, index);
    _active = CellRef(_data.rowCount - 1, index);
    _selectedColumnHeader = index;
    notifyListeners();
  }

  void selectRow(int row) {
    final index = row.clamp(0, _data.rowCount - 1);
    _anchor = CellRef(index, 0);
    _active = CellRef(index, _data.columnCount - 1);
    _selectedColumnHeader = null;
    notifyListeners();
  }

  void selectAll() {
    _anchor = const CellRef(0, 0);
    _active = CellRef(_data.rowCount - 1, _data.columnCount - 1);
    notifyListeners();
  }

  void setHoveredRow(int? row) {
    if (_hoveredRow == row) {
      return;
    }
    _hoveredRow = row;
    notifyListeners();
  }

  CellRef _clamp(CellRef ref) => CellRef(
        ref.row.clamp(0, math.max(0, _data.rowCount - 1)),
        ref.column.clamp(0, math.max(0, _data.columnCount - 1)),
      );

  void _clampSelection() {
    _active = _clamp(_active);
    _anchor = _clamp(_anchor);
  }

  /// Moves the cursor, skipping rows hidden by a filter.
  void move(int rowDelta, int columnDelta, {bool extend = false}) {
    var target = _active;
    if (rowDelta != 0) {
      final viewIndex = viewIndexOf(_active.row);
      if (viewIndex >= 0) {
        final nextIndex = (viewIndex + rowDelta)
            .clamp(0, math.max(0, _view.length - 1))
            .toInt();
        target = CellRef(_view[nextIndex], target.column);
      } else {
        target = target.translate(rowDelta, 0);
      }
    }
    if (columnDelta != 0) {
      var column = target.column;
      var remaining = columnDelta.abs();
      final step = columnDelta.sign;
      while (remaining > 0) {
        final next = column + step;
        if (next < 0 || next >= _data.columnCount) {
          break;
        }
        column = next;
        if (!_data.isColumnHidden(column)) {
          remaining--;
        }
      }
      target = CellRef(target.row, column);
    }
    selectCell(target, extend: extend);
  }

  void moveToEdge(int rowDelta, int columnDelta, {bool extend = false}) {
    if (rowDelta != 0) {
      final index = rowDelta < 0 ? 0 : _view.length - 1;
      if (index >= 0 && index < _view.length) {
        selectCell(CellRef(_view[index], _active.column), extend: extend);
      }
      return;
    }
    if (columnDelta != 0) {
      selectCell(
        CellRef(_active.row, columnDelta < 0 ? 0 : _data.columnCount - 1),
        extend: extend,
      );
    }
  }

  /// Advances after Enter or Tab, adding a row when the cursor runs off the
  /// bottom so typing never stops at the edge.
  void advance({required bool horizontal, required bool backwards}) {
    if (horizontal) {
      if (backwards) {
        move(0, -1);
        return;
      }
      if (_active.column >= _data.columnCount - 1) {
        final viewIndex = viewIndexOf(_active.row);
        if (viewIndex >= 0 && viewIndex < _view.length - 1) {
          selectCell(CellRef(_view[viewIndex + 1], 0));
          return;
        }
      }
      move(0, 1);
      return;
    }
    if (backwards) {
      move(-1, 0);
      return;
    }
    final viewIndex = viewIndexOf(_active.row);
    if (viewIndex >= 0 && viewIndex == _view.length - 1) {
      if (_data.rowCount < SpreadsheetData.maxRows) {
        mutate((data) => data.insertRows(data.rowCount, 1));
        final rows = _view;
        selectCell(CellRef(rows.last, _active.column));
        return;
      }
    }
    move(1, 0);
  }

  // -------------------------------------------------------------------
  // Editing
  // -------------------------------------------------------------------

  void startEditing({String? initialText, bool fromKeystroke = false}) {
    if (!editable) {
      return;
    }
    _editingHeader = null;
    _editing = _active;
    _editingText = initialText ?? _data.rawAt(_active);
    _editingFromKeystroke = fromKeystroke;
    notifyListeners();
  }

  /// Renames a column. Headers are names, not cells, so this never touches the
  /// grid's addressing.
  void startEditingHeader(int column) {
    if (!editable || column < 0 || column >= _data.columnCount) {
      return;
    }
    _editing = null;
    _editingHeader = column;
    _editingText = _data.columnTitle(column);
    _editingFromKeystroke = false;
    notifyListeners();
  }

  void updateEditingText(String text) {
    _editingText = text;
  }

  void commitEditing({bool notify = true}) {
    final column = _editingHeader;
    if (column != null) {
      final text = _editingText;
      _editingHeader = null;
      _editingText = '';
      if (_data.columnTitle(column) == text) {
        if (notify) {
          notifyListeners();
        }
        return;
      }
      mutate((data) => data.setColumnTitle(column, text));
      return;
    }

    final ref = _editing;
    if (ref == null) {
      return;
    }
    final text = _editingText;
    _editing = null;
    _editingText = '';
    _editingFromKeystroke = false;
    if (_data.rawAt(ref) == text) {
      if (notify) {
        notifyListeners();
      }
      return;
    }
    mutate((data) => data.setRaw(ref, text));
  }

  void cancelEditing() {
    if (_editing == null && _editingHeader == null) {
      return;
    }
    _editing = null;
    _editingHeader = null;
    _editingText = '';
    _editingFromKeystroke = false;
    notifyListeners();
  }

  // -------------------------------------------------------------------
  // Content operations
  // -------------------------------------------------------------------

  void clearSelection() {
    final range = selection;
    mutate((data) {
      for (final ref in range.cells) {
        data.setRaw(ref, '');
      }
    });
  }

  void applyStyle(CellStyle Function(CellStyle current) transform) {
    final range = selection;
    mutate((data) {
      for (final ref in range.cells) {
        data.setStyle(ref, transform(data.styleAt(ref)));
      }
    });
  }

  /// True when every cell in the selection already satisfies [test]; used to
  /// make the format buttons toggle rather than only turn on.
  bool selectionHas(bool Function(CellStyle style) test) {
    final range = selection;
    for (final ref in range.cells) {
      if (!test(_data.styleAt(ref))) {
        return false;
      }
    }
    return true;
  }

  /// Flips one boolean attribute across the selection.
  ///
  /// The target value is decided up front: reading the selection again from
  /// inside the transform would see cells this very call has already changed,
  /// and the toggle would alternate cell by cell instead of moving as one.
  void _toggleFlag(
    bool Function(CellStyle style) read,
    CellStyle Function(CellStyle style, bool value) write,
  ) {
    final target = !selectionHas(read);
    applyStyle((style) => write(style, target));
  }

  void toggleBold() => _toggleFlag(
        (style) => style.bold,
        (style, value) => style.copyWith(bold: value),
      );

  void toggleItalic() => _toggleFlag(
        (style) => style.italic,
        (style, value) => style.copyWith(italic: value),
      );

  void toggleUnderline() => _toggleFlag(
        (style) => style.underline,
        (style, value) => style.copyWith(underline: value),
      );

  void toggleStrikethrough() => _toggleFlag(
        (style) => style.strikethrough,
        (style, value) => style.copyWith(strikethrough: value),
      );

  void setAlign(CellAlign? align) => applyStyle(
        (style) => align == null
            ? style.copyWith(clearAlign: true)
            : style.copyWith(align: align),
      );

  void setNumberFormat(CellNumberFormat format, {int? decimals}) => applyStyle(
        (style) => style.copyWith(
          format: format,
          decimals: decimals,
          clearDecimals: decimals == null && format != style.format,
        ),
      );

  void setTextColor(int? color) => applyStyle(
        (style) => color == null
            ? style.copyWith(clearTextColor: true)
            : style.copyWith(textColor: color),
      );

  void setBackgroundColor(int? color) => applyStyle(
        (style) => color == null
            ? style.copyWith(clearBackgroundColor: true)
            : style.copyWith(backgroundColor: color),
      );

  void setBorders(CellBorders borders) =>
      applyStyle((style) => style.copyWith(borders: borders));

  // -------------------------------------------------------------------
  // Structure
  // -------------------------------------------------------------------

  void insertRowsAt(int at, int count) =>
      mutate((data) => data.insertRows(at, count));

  void deleteRowsAt(int at, int count) =>
      mutate((data) => data.deleteRows(at, count));

  void insertColumnsAt(int at, int count) =>
      mutate((data) => data.insertColumns(at, count));

  void deleteColumnsAt(int at, int count) =>
      mutate((data) => data.deleteColumns(at, count));

  void moveColumn(int from, int to) =>
      mutate((data) => data.moveColumn(from, to));

  void setColumnWidth(int column, double width) => mutate(
        (data) =>
            data.setColumn(column, data.column(column).copyWith(width: width)),
      );

  void setRowHeight(int row, double height) => mutate(
        (data) => data.setRowSpec(row, data.row(row).copyWith(height: height)),
      );

  void setColumnHidden(int column, bool hidden) => mutate(
        (data) => data.setColumn(
          column,
          data.column(column).copyWith(hidden: hidden),
        ),
      );

  void showAllColumns() => mutate((data) {
        for (var column = 0; column < data.columnCount; column++) {
          if (data.column(column).hidden) {
            data.setColumn(column, data.column(column).copyWith(hidden: false));
          }
        }
      });

  void setShowHeader(bool enabled) =>
      mutate((data) => data.showHeader = enabled);

  // -------------------------------------------------------------------
  // Sort & filter
  // -------------------------------------------------------------------

  /// Reorders the body rows in place — an explicit action rather than a live
  /// view, so what is on screen is what gets saved and undo means something.
  void sortByColumn(int column, SortDirection direction) {
    mutate((data) {
      final order = <int>[for (var row = 0; row < data.rowCount; row++) row];
      final keys = <int, SheetValue>{
        for (final row in order) row: _evaluator.valueAt(CellRef(row, column)),
      };
      order.sort((a, b) {
        final comparison = _compareValues(keys[a]!, keys[b]!);
        return direction == SortDirection.ascending ? comparison : -comparison;
      });

      final moved = <CellRef, SheetCell>{};
      for (var index = 0; index < order.length; index++) {
        final source = order[index];
        for (var column = 0; column < data.columnCount; column++) {
          final cell = data.cellAt(CellRef(source, column));
          if (!cell.isEmpty) {
            moved[CellRef(index, column)] = cell;
          }
        }
      }
      for (var row = 0; row < data.rowCount; row++) {
        for (var column = 0; column < data.columnCount; column++) {
          data.setCell(CellRef(row, column), const SheetCell());
        }
      }
      for (final entry in moved.entries) {
        data.setCell(entry.key, entry.value);
      }
      data.sort = SheetSort(column: column, direction: direction);
    });
  }

  static int _compareValues(SheetValue a, SheetValue b) {
    if (a.isBlank && b.isBlank) {
      return 0;
    }
    // Blanks always sink to the bottom, whichever direction is chosen.
    if (a.isBlank) {
      return 1;
    }
    if (b.isBlank) {
      return -1;
    }
    if (a is NumberValue && b is NumberValue) {
      return a.value.compareTo(b.value);
    }
    return a.asText.toLowerCase().compareTo(b.asText.toLowerCase());
  }

  void setFilter(int column, String query) {
    mutate((data) {
      data.filters = [
        ...data.filters.where((filter) => filter.column != column),
        if (query.trim().isNotEmpty)
          SheetFilter(column: column, query: query.trim()),
      ];
    });
  }

  void clearFilters() => mutate((data) => data.filters = const []);

  String filterFor(int column) =>
      _data.filters
          .where((filter) => filter.column == column)
          .map((filter) => filter.query)
          .firstOrNull ??
      '';

  // -------------------------------------------------------------------
  // Search
  // -------------------------------------------------------------------

  void setSearch(String query) {
    _search = query;
    _recomputeMatches();
    notifyListeners();
  }

  void _recomputeMatches({bool keepIndex = false}) {
    if (_search.trim().isEmpty) {
      _matches = const [];
      _matchIndex = -1;
      return;
    }
    final needle = _search.toLowerCase();
    final matches = <CellRef>[];
    for (final row in _view) {
      for (var column = 0; column < _data.columnCount; column++) {
        if (_data.isColumnHidden(column)) {
          continue;
        }
        final ref = CellRef(row, column);
        final raw = _data.rawAt(ref);
        if (raw.toLowerCase().contains(needle) ||
            displayTextAt(ref).toLowerCase().contains(needle)) {
          matches.add(ref);
        }
      }
    }
    _matches = matches;
    if (matches.isEmpty) {
      _matchIndex = -1;
    } else if (!keepIndex || _matchIndex < 0) {
      _matchIndex = 0;
    } else {
      _matchIndex = _matchIndex.clamp(0, matches.length - 1);
    }
  }

  void stepSearch(int delta) {
    if (_matches.isEmpty) {
      return;
    }
    _matchIndex = (_matchIndex + delta) % _matches.length;
    if (_matchIndex < 0) {
      _matchIndex += _matches.length;
    }
    final ref = _matches[_matchIndex];
    _active = ref;
    _anchor = ref;
    notifyListeners();
  }

  void replaceCurrent(String replacement) {
    final ref = currentSearchMatch;
    if (ref == null || _search.isEmpty) {
      return;
    }
    final raw = _data.rawAt(ref);
    final next = raw.replaceAll(
      RegExp(RegExp.escape(_search), caseSensitive: false),
      replacement,
    );
    mutate((data) => data.setRaw(ref, next));
    stepSearch(1);
  }

  int replaceAll(String replacement) {
    if (_search.isEmpty) {
      return 0;
    }
    final pattern = RegExp(RegExp.escape(_search), caseSensitive: false);
    var count = 0;
    final targets = List<CellRef>.of(_matches);
    mutate((data) {
      for (final ref in targets) {
        final raw = data.rawAt(ref);
        if (!raw.toLowerCase().contains(_search.toLowerCase())) {
          continue;
        }
        data.setRaw(ref, raw.replaceAll(pattern, replacement));
        count++;
      }
    });
    _recomputeMatches();
    notifyListeners();
    return count;
  }

  // -------------------------------------------------------------------
  // Clipboard
  // -------------------------------------------------------------------

  /// Puts the selection on the system clipboard as TSV and keeps a styled
  /// copy for pasting back into a sheet.
  Future<void> copySelection() async {
    final range = selection;
    final cells = <List<SheetCell>>[];
    final text = <List<String>>[];
    for (var row = range.top; row <= range.bottom; row++) {
      final cellRow = <SheetCell>[];
      final textRow = <String>[];
      for (var column = range.left; column <= range.right; column++) {
        final ref = CellRef(row, column);
        cellRow.add(_data.cellAt(ref));
        textRow.add(displayTextAt(ref));
      }
      cells.add(cellRow);
      text.add(textRow);
    }
    _internalClipboard = cells;
    await Clipboard.setData(
      ClipboardData(text: encodeDelimitedText(text, delimiter: '\t')),
    );
  }

  Future<void> cutSelection() async {
    await copySelection();
    clearSelection();
  }

  Future<void> pasteFromClipboard() async {
    if (!editable) {
      return;
    }
    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    final text = clipboard?.text ?? '';
    final internal = _internalClipboard;

    if (internal != null && internal.isNotEmpty) {
      final rendered = [
        for (final row in internal)
          [
            for (final cell in row) cell.raw,
          ],
      ];
      // Only reuse the styled payload when the clipboard still holds what we
      // put there; otherwise another app owns it now.
      final expected = encodeDelimitedText(
        [
          for (var row = 0; row < internal.length; row++)
            [
              for (var column = 0; column < internal[row].length; column++)
                internal[row][column].raw,
            ],
        ],
        delimiter: '\t',
      );
      if (text.isEmpty || _looksLike(text, expected, rendered)) {
        _pasteCells(internal);
        return;
      }
    }

    if (text.isEmpty) {
      return;
    }
    final markdown = parseMarkdownTable(text);
    final rows = markdown ?? parseDelimitedText(text);
    if (rows.isEmpty) {
      return;
    }
    _pasteCells([
      for (final row in rows) [for (final value in row) SheetCell(raw: value)],
    ]);
  }

  static bool _looksLike(
    String clipboardText,
    String rawEncoding,
    List<List<String>> rendered,
  ) {
    if (clipboardText == rawEncoding) {
      return true;
    }
    final rows = parseDelimitedText(clipboardText, delimiter: '\t');
    return rows.length == rendered.length;
  }

  void _pasteCells(List<List<SheetCell>> cells) {
    if (cells.isEmpty) {
      return;
    }
    final origin = selection.anchor;
    final neededRows = origin.row + cells.length;
    final neededColumns = origin.column +
        cells.fold<int>(0, (best, row) => math.max(best, row.length));
    mutate((data) {
      if (neededRows > data.rowCount) {
        data.insertRows(data.rowCount, neededRows - data.rowCount);
      }
      if (neededColumns > data.columnCount) {
        data.insertColumns(
          data.columnCount,
          math.min(
            neededColumns - data.columnCount,
            SpreadsheetData.maxColumns - data.columnCount,
          ),
        );
      }
      for (var row = 0; row < cells.length; row++) {
        for (var column = 0; column < cells[row].length; column++) {
          final target = CellRef(origin.row + row, origin.column + column);
          if (target.row >= data.rowCount ||
              target.column >= data.columnCount) {
            continue;
          }
          data.setCell(target, cells[row][column]);
        }
      }
    });
    selectRange(
      origin,
      CellRef(
        math.min(origin.row + cells.length - 1, _data.rowCount - 1),
        math.min(neededColumns - 1, _data.columnCount - 1),
      ),
    );
  }

  /// Puts the whole sheet on the clipboard as a markdown table.
  Future<void> copyAsMarkdown() =>
      Clipboard.setData(ClipboardData(text: encodeMarkdownTable(_data)));

  // -------------------------------------------------------------------
  // Fill handle
  // -------------------------------------------------------------------

  /// Extends [source] into [target], continuing numeric and date series the
  /// way a drag-fill is expected to.
  void fill(CellRange source, CellRange target) {
    if (!editable || target == source) {
      return;
    }
    final downward = target.bottom > source.bottom;
    final upward = target.top < source.top;
    final rightward = target.right > source.right;
    final leftward = target.left < source.left;

    mutate((data) {
      if (downward || upward) {
        for (var column = source.left; column <= source.right; column++) {
          final pattern = [
            for (var row = source.top; row <= source.bottom; row++)
              data.cellAt(CellRef(row, column)),
          ];
          if (downward) {
            var step = 1;
            for (var row = source.bottom + 1; row <= target.bottom; row++) {
              data.setCell(
                CellRef(row, column),
                _projected(pattern, step, forwards: true, vertical: true),
              );
              step++;
            }
          }
          if (upward) {
            var step = 1;
            for (var row = source.top - 1; row >= target.top; row--) {
              data.setCell(
                CellRef(row, column),
                _projected(pattern, step, forwards: false, vertical: true),
              );
              step++;
            }
          }
        }
      }
      if (rightward || leftward) {
        for (var row = source.top; row <= source.bottom; row++) {
          final pattern = [
            for (var column = source.left; column <= source.right; column++)
              data.cellAt(CellRef(row, column)),
          ];
          if (rightward) {
            var step = 1;
            for (var column = source.right + 1;
                column <= target.right;
                column++) {
              data.setCell(
                CellRef(row, column),
                _projected(pattern, step, forwards: true, vertical: false),
              );
              step++;
            }
          }
          if (leftward) {
            var step = 1;
            for (var column = source.left - 1;
                column >= target.left;
                column--) {
              data.setCell(
                CellRef(row, column),
                _projected(pattern, step, forwards: false, vertical: false),
              );
              step++;
            }
          }
        }
      }
    });
    selectRange(target.anchor, CellRef(target.bottom, target.right));
  }

  /// The value [step] places past the end (or before the start) of [pattern].
  static SheetCell _projected(
    List<SheetCell> pattern,
    int step, {
    required bool forwards,
    required bool vertical,
  }) {
    if (pattern.isEmpty) {
      return const SheetCell();
    }
    // Where this cell lands relative to the start of the pattern, and which
    // pattern cell it repeats.
    final destination = forwards ? pattern.length - 1 + step : -step;
    final index = forwards
        ? (pattern.length - 1 + step) % pattern.length
        : (pattern.length - (step % pattern.length)) % pattern.length;
    final delta = destination - index;

    // A formula travels with its references, so the copy reads the row or
    // column it landed on rather than the one it came from.
    if (pattern[index].isFormula) {
      final template = pattern[index];
      return template.copyWith(
        raw: '=${translateFormula(
          template.raw.substring(1),
          rowDelta: vertical ? delta : 0,
          columnDelta: vertical ? 0 : delta,
        )}',
      );
    }

    final numbers = <double>[];
    for (final cell in pattern) {
      if (cell.isFormula) {
        numbers.clear();
        break;
      }
      final number = parseCellNumber(cell.raw);
      if (number == null) {
        numbers.clear();
        break;
      }
      numbers.add(number);
    }

    if (numbers.isNotEmpty) {
      final increment = numbers.length == 1
          ? 1.0
          : _commonDifference(numbers) ?? _trendSlope(numbers);
      final base = forwards ? numbers.last : numbers.first;
      final next = forwards ? base + increment * step : base - increment * step;
      final template = forwards ? pattern.last : pattern.first;
      return template.copyWith(raw: _matchNumberShape(template.raw, next));
    }

    return _projectedDate(pattern, step, forwards: forwards) ??
        _projectedText(pattern, step, forwards: forwards) ??
        // Otherwise repeat the pattern.
        pattern[index];
  }

  /// A run of dates continued by the gap the selection established.
  static SheetCell? _projectedDate(
    List<SheetCell> pattern,
    int step, {
    required bool forwards,
  }) {
    final days = <double>[];
    DateTime? first;
    for (final cell in pattern) {
      if (cell.isFormula) {
        return null;
      }
      final date = parseCellDate(cell.raw);
      if (date == null) {
        return null;
      }
      first ??= date;
      days.add(date.difference(first).inDays.toDouble());
    }
    final increment =
        days.length == 1 ? 1.0 : _commonDifference(days) ?? _trendSlope(days);
    final template = forwards ? pattern.last : pattern.first;
    final base = parseCellDate(template.raw)!;
    final offset = (increment * step * (forwards ? 1 : -1)).round();
    return template.copyWith(
      raw: formatCellDateLike(template.raw, base.add(Duration(days: offset))),
    );
  }

  /// A run of labels sharing a prefix ("Week 1", "Week 3") continued by the
  /// step between them.
  static SheetCell? _projectedText(
    List<SheetCell> pattern,
    int step, {
    required bool forwards,
  }) {
    final expression = RegExp(r'^(.*?)(\d+)$');
    String? prefix;
    final numbers = <double>[];
    for (final cell in pattern) {
      if (cell.isFormula) {
        return null;
      }
      final match = expression.firstMatch(cell.raw);
      if (match == null) {
        return null;
      }
      final head = match.group(1)!;
      if (prefix == null) {
        prefix = head;
      } else if (prefix != head) {
        return null;
      }
      numbers.add(double.parse(match.group(2)!));
    }
    final increment =
        numbers.length == 1 ? 1.0 : _commonDifference(numbers) ?? 0;
    if (increment == 0 && numbers.length > 1) {
      return null;
    }
    final template = forwards ? pattern.last : pattern.first;
    final match = expression.firstMatch(template.raw)!;
    final base = double.parse(match.group(2)!);
    final next =
        (forwards ? base + increment * step : base - increment * step).round();
    if (next < 0) {
      return null;
    }
    final digits = match.group(2)!.length;
    return template.copyWith(
      raw: '$prefix${next.toString().padLeft(digits, '0')}',
    );
  }

  static double? _commonDifference(List<double> numbers) {
    if (numbers.length < 2) {
      return null;
    }
    final first = numbers[1] - numbers[0];
    for (var index = 2; index < numbers.length; index++) {
      if ((numbers[index] - numbers[index - 1] - first).abs() > 1e-9) {
        return null;
      }
    }
    return first;
  }

  /// The least-squares slope through the pattern, so an uneven run still
  /// extends along its trend instead of repeating its last value.
  static double _trendSlope(List<double> numbers) {
    final count = numbers.length;
    final meanX = (count - 1) / 2;
    final meanY = numbers.reduce((a, b) => a + b) / count;
    var covariance = 0.0;
    var variance = 0.0;
    for (var index = 0; index < count; index++) {
      final dx = index - meanX;
      covariance += dx * (numbers[index] - meanY);
      variance += dx * dx;
    }
    return variance == 0 ? 0 : covariance / variance;
  }

  /// Keeps the currency symbol or percent sign that the source cell used.
  static String _matchNumberShape(String template, double value) {
    final text = formatPlainNumber(value);
    final trimmed = template.trim();
    if (trimmed.endsWith('%')) {
      return '$text%';
    }
    final prefix = RegExp(r'^[\$€£¥₹]').firstMatch(trimmed)?.group(0);
    if (prefix != null) {
      return '$prefix$text';
    }
    return text;
  }

  // -------------------------------------------------------------------
  // Column types
  // -------------------------------------------------------------------

  /// Applies detected number formats to every column that does not already
  /// have one set by hand.
  int applyAutomaticColumnTypes() {
    var applied = 0;
    mutate((data) {
      for (var column = 0; column < data.columnCount; column++) {
        final kind = detectColumnKind(data, column);
        if (kind == null) {
          continue;
        }
        final format = formatForColumnKind(kind);
        if (format == CellNumberFormat.automatic) {
          continue;
        }
        var changed = false;
        for (var row = 0; row < data.rowCount; row++) {
          final ref = CellRef(row, column);
          final style = data.styleAt(ref);
          if (style.format != CellNumberFormat.automatic) {
            continue;
          }
          if (data.rawAt(ref).isEmpty) {
            continue;
          }
          data.setStyle(ref, style.copyWith(format: format));
          changed = true;
        }
        if (changed) {
          applied++;
        }
      }
    });
    return applied;
  }

  /// A compact summary of the current selection, shown in the status strip.
  SelectionSummary get selectionSummary {
    final range = selection;
    var count = 0;
    var numeric = 0;
    var total = 0.0;
    double? min;
    double? max;
    for (final ref in range.cells) {
      final value = _evaluator.valueAt(ref);
      if (value.isBlank) {
        continue;
      }
      count++;
      if (value is NumberValue) {
        numeric++;
        total += value.value;
        min = min == null ? value.value : math.min(min, value.value);
        max = max == null ? value.value : math.max(max, value.value);
      }
    }
    return SelectionSummary(
      cellCount: range.cellCount,
      filledCount: count,
      numericCount: numeric,
      sum: total,
      average: numeric == 0 ? null : total / numeric,
      minimum: min,
      maximum: max,
    );
  }

  /// The sheet as JSON for persistence.
  Map<String, dynamic> toJson() => _data.toJson();

  /// Raw values as TSV, used by the export menu.
  String toDelimitedText({String delimiter = ','}) =>
      encodeDelimitedText(spreadsheetDisplayRows(_data), delimiter: delimiter);

  @visibleForTesting
  static void debugClearInternalClipboard() => _internalClipboard = null;
}

/// Aggregates for the selected cells.
class SelectionSummary {
  const SelectionSummary({
    required this.cellCount,
    required this.filledCount,
    required this.numericCount,
    required this.sum,
    required this.average,
    required this.minimum,
    required this.maximum,
  });

  final int cellCount;
  final int filledCount;
  final int numericCount;
  final double sum;
  final double? average;
  final double? minimum;
  final double? maximum;

  bool get hasNumbers => numericCount > 0;
}

/// Convenience for encoding a sheet as pretty JSON in debug output.
String debugEncodeSpreadsheet(SpreadsheetData data) =>
    const JsonEncoder.withIndent('  ').convert(data.toJson());
