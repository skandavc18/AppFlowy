import 'dart:math' as math;

import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'spreadsheet_controller.dart';
import 'spreadsheet_floating_toolbar.dart';
import 'spreadsheet_grid_render.dart';
import 'spreadsheet_menus.dart';
import 'spreadsheet_model.dart';
import 'spreadsheet_theme.dart';

/// The interactive grid: a single painted surface with an editor overlaid on
/// the active cell, so thousands of rows cost a few hundred draw calls rather
/// than a widget per cell.
class SpreadsheetGrid extends StatefulWidget {
  const SpreadsheetGrid({
    super.key,
    required this.controller,
    this.editable = true,
    this.onRequestFind,
    this.autofocus = false,
    this.baseTextStyle,
    this.placeholder,
    this.addRowLabel,
  });

  final SpreadsheetController controller;
  final bool editable;
  final VoidCallback? onRequestFind;
  final bool autofocus;

  /// The document's body text style, so a sheet is set in the same face as the
  /// paragraph above it.
  final TextStyle? baseTextStyle;

  /// Hint shown in the first cell while the sheet is untouched.
  final String? placeholder;

  /// Label on the band under the last row that appends one.
  final String? addRowLabel;

  @override
  State<SpreadsheetGrid> createState() => SpreadsheetGridState();
}

enum _DragMode { none, select, fill, resizeColumn, resizeRow, reorderColumn }

class SpreadsheetGridState extends State<SpreadsheetGrid>
    with SingleTickerProviderStateMixin {
  final ScrollController _horizontal = ScrollController();
  final ScrollController _vertical = ScrollController();
  final FocusNode _gridFocus = FocusNode(debugLabel: 'spreadsheet-grid');
  final FocusNode _editorFocus = FocusNode(debugLabel: 'spreadsheet-editor');
  final TextEditingController _editorController = TextEditingController();
  final SheetTextCache _textCache = SheetTextCache();
  final GlobalKey _bodyKey = GlobalKey(debugLabel: 'spreadsheet-body');

  /// Settles the focus ring onto a newly selected cell.
  late final AnimationController _selectionSettle = AnimationController(
    vsync: this,
    duration: AppFlowyMotion.fast,
    value: 1,
  );

  late SheetGeometry _geometry;
  late Listenable _repaint;
  int _lastRevision = -1;
  CellRef? _lastActive;

  _DragMode _dragMode = _DragMode.none;
  int? _resizingColumn;
  int? _resizingRow;
  double _resizeStart = 0;
  double _resizeOrigin = 0;
  int? _reorderColumn;
  int? _dropIndicator;
  int? _hoveredColumn;
  CellRange? _fillPreview;
  CellRange? _fillSource;
  Offset _pressOrigin = Offset.zero;
  DateTime? _lastTapTime;
  CellRef? _lastTapCell;
  DateTime? _lastHeaderTapTime;
  int? _lastHeaderTapColumn;
  bool _lastHeaderTapWasEdge = false;
  CellRef? _hoveredCell;
  bool _pointerInside = false;
  bool _gridFocused = false;
  bool _formatMenuOpen = false;
  bool _addRowHovered = false;
  bool _addColumnHovered = false;

  SpreadsheetController get controller => widget.controller;

  SheetGeometry _buildGeometry() =>
      SheetGeometry.from(controller, showAddAffordances: widget.editable);

  @override
  void initState() {
    super.initState();
    _geometry = _buildGeometry();
    _lastRevision = controller.revision;
    _repaint = Listenable.merge(
      [controller, _horizontal, _vertical, _selectionSettle],
    );
    controller.addListener(_onControllerChanged);
    if (widget.autofocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _gridFocus.requestFocus();
        }
      });
    }
  }

  @override
  void didUpdateWidget(covariant SpreadsheetGrid oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      controller.addListener(_onControllerChanged);
      _repaint = Listenable.merge(
        [controller, _horizontal, _vertical, _selectionSettle],
      );
      _lastRevision = -1;
      _onControllerChanged();
    }
  }

  @override
  void dispose() {
    controller.removeListener(_onControllerChanged);
    _selectionSettle.dispose();
    _horizontal.dispose();
    _vertical.dispose();
    _gridFocus.dispose();
    _editorFocus.dispose();
    _editorController.dispose();
    super.dispose();
  }

  void _onControllerChanged() {
    final editing = controller.editing;
    if (editing != null && _editorController.text != controller.editingText) {
      _editorController.value = TextEditingValue(
        text: controller.editingText,
        selection:
            TextSelection.collapsed(offset: controller.editingText.length),
      );
    }
    if (controller.revision != _lastRevision) {
      _lastRevision = controller.revision;
      _textCache.invalidate();
      setState(() => _geometry = _buildGeometry());
    } else {
      setState(() {});
    }
    if (editing != null && !_editorFocus.hasFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && controller.editing != null) {
          _editorFocus.requestFocus();
        }
      });
    } else if (editing == null && _editorFocus.hasFocus) {
      _gridFocus.requestFocus();
    }
    if (_lastActive != controller.active) {
      _lastActive = controller.active;
      _selectionSettle.forward(from: 0);
      _scheduleReveal();
    }
  }

  // -------------------------------------------------------------------
  // Scrolling helpers
  // -------------------------------------------------------------------

  bool _revealScheduled = false;

  void _scheduleReveal() {
    if (_revealScheduled) {
      return;
    }
    _revealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _revealScheduled = false;
      if (mounted) {
        _revealActiveCell();
      }
    });
  }

  void _revealActiveCell() {
    final size = _bodySize;
    if (size == null) {
      return;
    }
    final active = controller.active;
    if (_horizontal.hasClients) {
      final left = _geometry.columnLeft(active.column);
      final right = left + _geometry.columnWidth(active.column);
      final offset = _horizontal.offset;
      if (left < offset) {
        _horizontal.jumpTo(
          left.clamp(0, _horizontal.position.maxScrollExtent).toDouble(),
        );
      } else if (right > offset + size.width) {
        _horizontal.jumpTo(
          (right - size.width)
              .clamp(0, _horizontal.position.maxScrollExtent)
              .toDouble(),
        );
      }
    }
    final index = _geometry.bodyIndexOf(active.row);
    if (index >= 0 && _vertical.hasClients) {
      final top = _geometry.rowTop(index);
      final bottom = top + _geometry.rowHeight(index);
      final offset = _vertical.offset;
      if (top < offset) {
        _vertical.jumpTo(
          top.clamp(0, _vertical.position.maxScrollExtent).toDouble(),
        );
      } else if (bottom > offset + size.height) {
        _vertical.jumpTo(
          (bottom - size.height)
              .clamp(0, _vertical.position.maxScrollExtent)
              .toDouble(),
        );
      }
    }
  }

  Size? get _bodySize {
    final box = _bodyKey.currentContext?.findRenderObject() as RenderBox?;
    return box?.hasSize ?? false ? box!.size : null;
  }

  /// Converts a pointer position inside the body to sheet coordinates.
  Offset _toSheet(Offset local) => Offset(
        local.dx + (_horizontal.hasClients ? _horizontal.offset : 0),
        local.dy + (_vertical.hasClients ? _vertical.offset : 0),
      );

  CellRef? _cellAt(Offset local) {
    final sheet = _toSheet(local);
    final column = _geometry.columnAt(sheet.dx);
    final index = _geometry.bodyIndexAt(sheet.dy);
    if (column == null || index == null) {
      return null;
    }
    return CellRef(_geometry.bodyRows[index], column);
  }

  /// Nearest cell even when the pointer is past the last row or column, so a
  /// drag that leaves the grid still extends the selection sensibly.
  CellRef _nearestCell(Offset local) {
    final sheet = _toSheet(local);
    final column = _geometry.columnAt(sheet.dx) ??
        (sheet.dx <= 0 ? 0 : _geometry.columnCount - 1);
    final index = _geometry.bodyIndexAt(sheet.dy) ??
        (sheet.dy <= 0 ? 0 : _geometry.bodyRows.length - 1);
    final row = _geometry.bodyRows.isEmpty
        ? 0
        : _geometry.bodyRows[index.clamp(0, _geometry.bodyRows.length - 1)];
    return CellRef(row, column.clamp(0, _geometry.columnCount - 1));
  }

  Rect? _selectionRect() {
    final range = controller.selection;
    var top = double.infinity;
    var bottom = -double.infinity;
    for (var row = range.top; row <= range.bottom; row++) {
      final index = _geometry.bodyIndexOf(row);
      if (index < 0) {
        continue;
      }
      top = math.min(top, _geometry.rowTop(index));
      bottom = math.max(
        bottom,
        _geometry.rowTop(index) + _geometry.rowHeight(index),
      );
    }
    if (!top.isFinite || !bottom.isFinite) {
      return null;
    }
    return Rect.fromLTRB(
      _geometry.columnLeft(range.left),
      top,
      _geometry.columnLeft(math.min(range.right + 1, _geometry.columnCount)),
      bottom,
    );
  }

  bool _isOnFillHandle(Offset local) {
    final rect = _selectionRect();
    if (rect == null) {
      return false;
    }
    const target = SpreadsheetMetrics.fillHandleTargetSize;
    return Rect.fromCenter(
      center: rect.bottomRight,
      width: target,
      height: target,
    ).contains(_toSheet(local));
  }

  // -------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    final typography = SpreadsheetTypography.of(
      context,
      palette,
      base: widget.baseTextStyle,
    );

    return Shortcuts(
      // Shortcuts and Actions must sit above the focus node: key events are
      // dispatched to the focused node and then up its ancestors, so a
      // Shortcuts placed inside the Focus would never be consulted.
      shortcuts: _activeShortcuts(),
      child: Actions(
        actions: _buildActions(),
        child: Focus(
          focusNode: _gridFocus,
          onKeyEvent: _onGridKey,
          onFocusChange: (value) {
            if (mounted && value != _gridFocused) {
              setState(() => _gridFocused = value);
            }
          },
          child: MouseRegion(
            opaque: false,
            onEnter: (_) => _setPointerInside(true),
            onExit: (_) {
              _setPointerInside(false);
              controller.setHoveredRow(null);
            },
            child: ColoredBox(
              color: palette.surface,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SizedBox(
                    height: SpreadsheetMetrics.headerHeight,
                    child: Row(
                      children: [
                        _buildCorner(palette),
                        Expanded(child: _buildHeader(palette, typography)),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildGutter(palette, typography),
                        Expanded(child: _buildBody(palette, typography)),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _setPointerInside(bool value) {
    if (_pointerInside != value && mounted) {
      setState(() => _pointerInside = value);
    }
  }

  Widget _buildCorner(SpreadsheetPalette palette) {
    return GestureDetector(
      onTap: controller.selectAll,
      child: Container(
        width: SpreadsheetMetrics.gutterWidth,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.headerSurface,
          border: Border(
            right: BorderSide(color: palette.gridLine),
            bottom: BorderSide(color: palette.divider),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Header strip
  // -------------------------------------------------------------------

  Widget _buildHeader(
    SpreadsheetPalette palette,
    SpreadsheetTypography typography,
  ) {
    return MouseRegion(
      opaque: false,
      onHover: _onHeaderHover,
      onExit: (_) => setState(() {
        _hoveredColumn = null;
        _addColumnHovered = false;
      }),
      cursor: _headerCursor(),
      child: Listener(
        onPointerDown: _onHeaderPointerDown,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: _onHeaderTap,
          onSecondaryTapUp: _onHeaderSecondaryTap,
          onHorizontalDragStart: _onHeaderDragStart,
          onHorizontalDragUpdate: _onHeaderDragUpdate,
          onHorizontalDragEnd: _onHeaderDragEnd,
          child: Stack(
            children: [
              Positioned.fill(
                child: CustomPaint(
                  painter: SheetHeaderPainter(
                    controller: controller,
                    geometry: _geometry,
                    palette: palette,
                    typography: typography,
                    horizontal: _horizontal,
                    hoveredColumn: _hoveredColumn,
                    dropIndicator: _dropIndicator,
                    resizingEdge: _resizingColumn ?? _hoveredColumnEdge,
                    addColumnHovered: _addColumnHovered,
                    repaint: _repaint,
                  ),
                ),
              ),
              if (controller.editingHeader != null)
                _buildHeaderEditor(palette, typography),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderEditor(
    SpreadsheetPalette palette,
    SpreadsheetTypography typography,
  ) {
    final column = controller.editingHeader!;
    final dx = _geometry.columnLeft(column) -
        (_horizontal.hasClients ? _horizontal.offset : 0);
    return Positioned(
      left: dx,
      top: 0,
      width: _geometry.columnWidth(column),
      height: SpreadsheetMetrics.headerHeight,
      child: _buildEditorField(palette, typography.header),
    );
  }

  MouseCursor _headerCursor() {
    if (_addColumnHovered) {
      return SystemMouseCursors.click;
    }
    if (_hoveredColumnEdge != null) {
      return SystemMouseCursors.resizeColumn;
    }
    return SystemMouseCursors.basic;
  }

  int? _hoveredColumnEdge;

  void _onHeaderHover(PointerHoverEvent event) {
    final sheet = event.localPosition.dx +
        (_horizontal.hasClients ? _horizontal.offset : 0);
    final onAdd = widget.editable && _geometry.isInAddColumn(sheet);
    if (onAdd != _addColumnHovered) {
      setState(() => _addColumnHovered = onAdd);
    }
    final edge = onAdd ? null : _columnEdgeAt(sheet);
    final column = _geometry.columnAt(sheet);
    if (edge != _hoveredColumnEdge || column != _hoveredColumn) {
      setState(() {
        _hoveredColumnEdge = edge;
        _hoveredColumn = column;
      });
    }
  }

  int? _columnEdgeAt(double x) {
    const tolerance = SpreadsheetMetrics.resizeHandleWidth / 2;
    for (var column = 0; column < _geometry.columnCount; column++) {
      final right =
          _geometry.columnLeft(column) + _geometry.columnWidth(column);
      if ((x - right).abs() <= tolerance) {
        return column;
      }
    }
    return null;
  }

  void _onHeaderPointerDown(PointerDownEvent event) {
    if (!widget.editable) {
      return;
    }
    final sheet = event.localPosition.dx +
        (_horizontal.hasClients ? _horizontal.offset : 0);
    _resizingColumn = _columnEdgeAt(sheet);
    _pressOrigin = event.localPosition;
  }

  void _onHeaderDragStart(DragStartDetails details) {
    if (!widget.editable) {
      return;
    }
    final sheet = details.localPosition.dx +
        (_horizontal.hasClients ? _horizontal.offset : 0);
    final edge = _columnEdgeAt(sheet);
    if (edge != null) {
      _dragMode = _DragMode.resizeColumn;
      _resizingColumn = edge;
      _resizeStart = details.localPosition.dx;
      _resizeOrigin = controller.data.column(edge).width;
      return;
    }
    final column = _geometry.columnAt(sheet);
    if (column != null) {
      _dragMode = _DragMode.reorderColumn;
      _reorderColumn = column;
      _dropIndicator = column;
    }
  }

  void _onHeaderDragUpdate(DragUpdateDetails details) {
    if (_dragMode == _DragMode.resizeColumn && _resizingColumn != null) {
      final width = _resizeOrigin + (details.localPosition.dx - _resizeStart);
      setState(() {
        controller.data.setColumn(
          _resizingColumn!,
          controller.data.column(_resizingColumn!).copyWith(width: width),
        );
        _geometry = SheetGeometry.from(controller);
      });
      return;
    }
    if (_dragMode == _DragMode.reorderColumn) {
      final sheet = details.localPosition.dx +
          (_horizontal.hasClients ? _horizontal.offset : 0);
      final target = _dropTargetFor(sheet);
      if (target != _dropIndicator) {
        setState(() => _dropIndicator = target);
      }
    }
  }

  int _dropTargetFor(double x) {
    for (var column = 0; column < _geometry.columnCount; column++) {
      final left = _geometry.columnLeft(column);
      final width = _geometry.columnWidth(column);
      if (x < left + width / 2) {
        return column;
      }
    }
    return _geometry.columnCount;
  }

  void _onHeaderDragEnd(DragEndDetails details) {
    if (_dragMode == _DragMode.resizeColumn && _resizingColumn != null) {
      final column = _resizingColumn!;
      final width = controller.data.column(column).width;
      // The drag mutated the model directly for live feedback, so put the
      // starting width back before committing: otherwise the undo snapshot
      // would already contain the new size and undo would do nothing.
      controller.data.setColumn(
        column,
        controller.data.column(column).copyWith(width: _resizeOrigin),
      );
      controller.setColumnWidth(column, width);
    } else if (_dragMode == _DragMode.reorderColumn &&
        _reorderColumn != null &&
        _dropIndicator != null) {
      var target = _dropIndicator!;
      if (target > _reorderColumn!) {
        target -= 1;
      }
      if (target != _reorderColumn) {
        controller.moveColumn(_reorderColumn!, target);
      }
    }
    setState(() {
      _dragMode = _DragMode.none;
      _resizingColumn = null;
      _reorderColumn = null;
      _dropIndicator = null;
    });
  }

  void _onHeaderTap(TapUpDetails details) {
    final offset = _horizontal.hasClients ? _horizontal.offset : 0.0;
    final sheet = details.localPosition.dx + offset;
    if (widget.editable && _geometry.isInAddColumn(sheet)) {
      addColumn();
      return;
    }
    final edge = _columnEdgeAt(sheet);
    final column = _geometry.columnAt(sheet);

    final now = DateTime.now();
    final last = _lastHeaderTapTime;
    final isDoubleTap = last != null &&
        _lastHeaderTapColumn == (edge ?? column) &&
        _lastHeaderTapWasEdge == (edge != null) &&
        now.difference(last) < kDoubleTapTimeout;
    _lastHeaderTapTime = now;
    _lastHeaderTapColumn = edge ?? column;
    _lastHeaderTapWasEdge = edge != null;

    if (edge != null) {
      // Double clicking the divider is the standard "fit to content" gesture.
      if (isDoubleTap) {
        _lastHeaderTapTime = null;
        autoFitColumn(edge);
      }
      return;
    }
    if (column == null) {
      return;
    }
    _gridFocus.requestFocus();

    if (isDoubleTap && _geometry.showHeader && widget.editable) {
      _lastHeaderTapTime = null;
      controller.startEditingHeader(column);
      return;
    }

    // The right edge of a header cell is the menu affordance; the rest of it
    // selects the column, and a second click renames it.
    final columnRight =
        _geometry.columnLeft(column) + _geometry.columnWidth(column);
    if (sheet <= columnRight - 24) {
      controller.selectColumn(column);
      return;
    }
    _openColumnMenu(column, details.globalPosition);
  }

  void _onHeaderSecondaryTap(TapUpDetails details) {
    final sheet = details.localPosition.dx +
        (_horizontal.hasClients ? _horizontal.offset : 0);
    final column = _geometry.columnAt(sheet);
    if (column != null) {
      _openColumnMenu(column, details.globalPosition);
    }
  }

  Future<void> _openColumnMenu(int column, Offset position) async {
    controller.selectColumn(column);
    await showSpreadsheetColumnMenu(
      context: context,
      controller: controller,
      column: column,
      position: position,
      onAutoFit: () => autoFitColumn(column),
      editable: widget.editable,
    );
  }

  /// Widens a column to fit its widest visible value.
  void autoFitColumn(int column) {
    final palette = SpreadsheetPalette.of(context);
    final typography = SpreadsheetTypography.of(
      context,
      palette,
      base: widget.baseTextStyle,
    );
    var widest = _textCache.intrinsicWidth(
      controller.data.headerLabel(column),
      typography.header,
    );
    for (final row in controller.visibleRows) {
      final ref = CellRef(row, column);
      final text = controller.displayTextAt(ref);
      if (text.isEmpty) {
        continue;
      }
      final style = cellTextStyle(
        base: typography.cell,
        style: controller.data.styleAt(ref),
        palette: palette,
        isError: false,
      );
      widest = math.max(widest, _textCache.intrinsicWidth(text, style));
    }
    controller.setColumnWidth(
      column,
      (widest + SpreadsheetMetrics.cellPaddingHorizontal * 2 + 18)
          .clamp(SheetColumn.minWidth, SheetColumn.maxWidth)
          .toDouble(),
    );
  }

  // -------------------------------------------------------------------
  // Gutter
  // -------------------------------------------------------------------

  Widget _buildGutter(
    SpreadsheetPalette palette,
    SpreadsheetTypography typography,
  ) {
    return MouseRegion(
      opaque: false,
      onHover: _onGutterHover,
      onExit: (_) => controller.setHoveredRow(null),
      cursor: _hoveredRowEdge != null
          ? SystemMouseCursors.resizeRow
          : SystemMouseCursors.basic,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: _onGutterTap,
        onSecondaryTapUp: _onGutterSecondaryTap,
        onVerticalDragStart: _onGutterDragStart,
        onVerticalDragUpdate: _onGutterDragUpdate,
        onVerticalDragEnd: _onGutterDragEnd,
        child: SizedBox(
          width: SpreadsheetMetrics.gutterWidth,
          child: CustomPaint(
            painter: SheetGutterPainter(
              controller: controller,
              geometry: _geometry,
              palette: palette,
              typography: typography,
              vertical: _vertical,
              pointerInside: _pointerInside,
              repaint: _repaint,
            ),
          ),
        ),
      ),
    );
  }

  int? _hoveredRowEdge;

  void _onGutterHover(PointerHoverEvent event) {
    final y =
        event.localPosition.dy + (_vertical.hasClients ? _vertical.offset : 0);
    final edge = _rowEdgeAt(y);
    if (edge != _hoveredRowEdge) {
      setState(() => _hoveredRowEdge = edge);
    }
    final index = _geometry.bodyIndexAt(y);
    controller.setHoveredRow(
      index == null ? null : _geometry.bodyRows[index],
    );
  }

  int? _rowEdgeAt(double y) {
    const tolerance = SpreadsheetMetrics.resizeHandleWidth / 2;
    for (var index = 0; index < _geometry.bodyRows.length; index++) {
      final bottom = _geometry.rowTop(index) + _geometry.rowHeight(index);
      if ((y - bottom).abs() <= tolerance) {
        return index;
      }
    }
    return null;
  }

  void _onGutterDragStart(DragStartDetails details) {
    if (!widget.editable) {
      return;
    }
    final y = details.localPosition.dy +
        (_vertical.hasClients ? _vertical.offset : 0);
    final edge = _rowEdgeAt(y);
    if (edge == null) {
      return;
    }
    _dragMode = _DragMode.resizeRow;
    _resizingRow = _geometry.bodyRows[edge];
    _resizeStart = details.localPosition.dy;
    _resizeOrigin = controller.data.row(_resizingRow!).height;
  }

  void _onGutterDragUpdate(DragUpdateDetails details) {
    if (_dragMode != _DragMode.resizeRow || _resizingRow == null) {
      return;
    }
    final height = _resizeOrigin + (details.localPosition.dy - _resizeStart);
    setState(() {
      controller.data.setRowSpec(
        _resizingRow!,
        controller.data.row(_resizingRow!).copyWith(height: height),
      );
      _geometry = SheetGeometry.from(controller);
    });
  }

  void _onGutterDragEnd(DragEndDetails details) {
    if (_dragMode == _DragMode.resizeRow && _resizingRow != null) {
      final row = _resizingRow!;
      final height = controller.data.row(row).height;
      controller.data.setRowSpec(
        row,
        controller.data.row(row).copyWith(height: _resizeOrigin),
      );
      controller.setRowHeight(row, height);
    }
    setState(() {
      _dragMode = _DragMode.none;
      _resizingRow = null;
    });
  }

  void _onGutterTap(TapUpDetails details) {
    final y = details.localPosition.dy +
        (_vertical.hasClients ? _vertical.offset : 0);
    final index = _geometry.bodyIndexAt(y);
    if (index == null) {
      return;
    }
    _gridFocus.requestFocus();
    controller.selectRow(_geometry.bodyRows[index]);
  }

  void _onGutterSecondaryTap(TapUpDetails details) {
    final y = details.localPosition.dy +
        (_vertical.hasClients ? _vertical.offset : 0);
    final index = _geometry.bodyIndexAt(y);
    if (index == null) {
      return;
    }
    final row = _geometry.bodyRows[index];
    controller.selectRow(row);
    showSpreadsheetRowMenu(
      context: context,
      controller: controller,
      row: row,
      position: details.globalPosition,
      editable: widget.editable,
    );
  }

  // -------------------------------------------------------------------
  // Body
  // -------------------------------------------------------------------

  Widget _buildBody(
    SpreadsheetPalette palette,
    SpreadsheetTypography typography,
  ) {
    return Stack(
      key: _bodyKey,
      children: [
        // The scroll views hold no children — they exist to provide physics,
        // scrollbars and wheel handling for the painted surface above them.
        Positioned.fill(
          child: SingleChildScrollView(
            controller: _vertical,
            child: SingleChildScrollView(
              controller: _horizontal,
              scrollDirection: Axis.horizontal,
              child: SizedBox(
                width: _geometry.contentWidth,
                height: math.max(_geometry.contentHeight, 1),
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: SheetBodyPainter(
                controller: controller,
                geometry: _geometry,
                palette: palette,
                typography: typography,
                textCache: _textCache,
                horizontal: _horizontal,
                vertical: _vertical,
                fillPreview: _fillPreview,
                hoveredCell: _hoveredCell,
                selectionSettle: _selectionSettle,
                placeholder:
                    controller.data.isEmpty ? widget.placeholder : null,
                addRowLabel: widget.editable ? widget.addRowLabel : null,
                addRowHovered: _addRowHovered,
                repaint: _repaint,
              ),
            ),
          ),
        ),
        if (controller.editing != null) _buildBodyEditor(palette, typography),
        Positioned.fill(
          child: MouseRegion(
            opaque: false,
            onHover: _onBodyHover,
            onExit: (_) {
              controller.setHoveredRow(null);
              if (_hoveredCell != null || _addRowHovered) {
                setState(() {
                  _hoveredCell = null;
                  _addRowHovered = false;
                });
              }
            },
            cursor: _bodyCursor,
            child: RawGestureDetector(
              behavior: HitTestBehavior.translucent,
              gestures: {
                TapGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<TapGestureRecognizer>(
                  () => TapGestureRecognizer(debugOwner: this),
                  (instance) => instance
                    ..onTapDown = _onBodyTapDown
                    ..onSecondaryTapUp = _onBodySecondaryTap,
                ),
                MouseDragGestureRecognizer:
                    GestureRecognizerFactoryWithHandlers<
                        MouseDragGestureRecognizer>(
                  () => MouseDragGestureRecognizer(debugOwner: this),
                  (instance) => instance
                    ..onStart = _onBodyDragStart
                    ..onUpdate = _onBodyDragUpdate
                    ..onEnd = _onBodyDragEnd
                    ..onCancel = _onBodyDragCancel,
                ),
              },
            ),
          ),
        ),
        ..._buildFloatingToolbar(),
      ],
    );
  }

  MouseCursor get _bodyCursor => _addRowHovered
      ? SystemMouseCursors.click
      : _hoveringFillHandle
          ? SystemMouseCursors.precise
          : SystemMouseCursors.basic;

  bool _hoveringFillHandle = false;

  /// The formatting bar hovers over a range selection, the same way the editor
  /// raises one for selected text.
  ///
  /// Only for a range: a bar that appeared on every single-cell selection
  /// would sit over the sheet permanently and swallow clicks. Formatting one
  /// cell is on the shortcuts and the right-click menu.
  List<Widget> _buildFloatingToolbar() {
    if (!widget.editable ||
        controller.editing != null ||
        controller.selection.isSingle ||
        !(_gridFocused || _formatMenuOpen)) {
      return const [];
    }
    final size = _bodySize;
    final rect = _selectionRect();
    if (size == null || rect == null) {
      return const [];
    }
    const height = SpreadsheetMetrics.floatingToolbarHeight;
    const gap = 8.0;
    final local = rect.translate(
      _horizontal.hasClients ? -_horizontal.offset : 0.0,
      _vertical.hasClients ? -_vertical.offset : 0.0,
    );
    if (local.bottom < 0 || local.top > size.height) {
      return const [];
    }
    var top = local.top - height - gap;
    if (top < 0) {
      // Below the selection the bar would otherwise sit on the fill handle.
      top = local.bottom + SpreadsheetMetrics.fillHandleTargetSize;
    }
    if (top + height > size.height) {
      top = math.max(0, size.height - height - 2);
    }
    // Aligning rather than positioning keeps the bar inside the sheet however
    // wide it turns out to be.
    final centre = local.center.dx.clamp(0.0, math.max(1.0, size.width));
    final alignment = size.width <= 0
        ? 0.0
        : (centre / size.width * 2 - 1).clamp(-1.0, 1.0).toDouble();
    return [
      Positioned(
        left: 0,
        right: 0,
        top: top,
        height: height,
        child: Align(
          alignment: Alignment(alignment, 0),
          child: SpreadsheetFloatingToolbar(
            controller: controller,
            onMenuVisibilityChanged: (open) {
              if (mounted) {
                setState(() => _formatMenuOpen = open);
              }
            },
          ),
        ),
      ),
    ];
  }

  void _onBodyHover(PointerHoverEvent event) {
    final sheet = _toSheet(event.localPosition);
    final onAddRow =
        widget.editable && _geometry.isInAddRow(sheet.dx, sheet.dy);
    if (onAddRow != _addRowHovered) {
      setState(() => _addRowHovered = onAddRow);
    }
    final onHandle =
        widget.editable && !onAddRow && _isOnFillHandle(event.localPosition);
    if (onHandle != _hoveringFillHandle) {
      setState(() => _hoveringFillHandle = onHandle);
    }
    final index = _geometry.bodyIndexAt(sheet.dy);
    controller.setHoveredRow(
      index == null ? null : _geometry.bodyRows[index],
    );
    final cell = _cellAt(event.localPosition);
    if (cell != _hoveredCell) {
      setState(() => _hoveredCell = cell);
    }
  }

  /// Appends a row and puts the cursor in it, the way "New row" behaves in a
  /// database grid.
  void addRow() {
    if (!widget.editable) {
      return;
    }
    final target = controller.data.rowCount;
    controller.insertRowsAt(target, 1);
    controller.selectCell(CellRef(target, 0));
    _gridFocus.requestFocus();
  }

  void addColumn() {
    if (!widget.editable) {
      return;
    }
    final target = controller.data.columnCount;
    controller.insertColumnsAt(target, 1);
    controller.selectColumn(target);
    _gridFocus.requestFocus();
  }

  Widget _buildBodyEditor(
    SpreadsheetPalette palette,
    SpreadsheetTypography typography,
  ) {
    final ref = controller.editing!;
    final index = _geometry.bodyIndexOf(ref.row);
    if (index < 0) {
      return const SizedBox.shrink();
    }
    final left = _geometry.columnLeft(ref.column) -
        (_horizontal.hasClients ? _horizontal.offset : 0);
    final top =
        _geometry.rowTop(index) - (_vertical.hasClients ? _vertical.offset : 0);
    return Positioned(
      left: left,
      top: top,
      width: math.max(
        _geometry.columnWidth(ref.column),
        SheetColumn.minWidth,
      ),
      height: _geometry.rowHeight(index),
      child: _buildEditorField(palette, typography.cell),
    );
  }

  /// The in-place editor. It shows the formula while typing and the value the
  /// moment it is committed, which is the whole point of "no formula bar".
  Widget _buildEditorField(SpreadsheetPalette palette, TextStyle style) {
    return Material(
      color: Colors.transparent,
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: palette.focusRing, width: 1.8),
          boxShadow: [
            BoxShadow(
              color: palette.focusHalo,
              spreadRadius: 2.5,
            ),
            BoxShadow(
              color: palette.shadow,
              blurRadius: 12,
              spreadRadius: -2,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        padding: const EdgeInsets.symmetric(
          horizontal: SpreadsheetMetrics.cellPaddingHorizontal - 2,
        ),
        alignment: Alignment.centerLeft,
        child: TextField(
          controller: _editorController,
          focusNode: _editorFocus,
          style: style.copyWith(color: palette.textPrimary),
          cursorColor: palette.accent,
          cursorWidth: 1.6,
          cursorRadius: const Radius.circular(1),
          decoration: const InputDecoration(
            isCollapsed: true,
            border: InputBorder.none,
            filled: false,
            hoverColor: Colors.transparent,
            contentPadding: EdgeInsets.zero,
          ),
          onChanged: controller.updateEditingText,
          onTapOutside: (_) => controller.commitEditing(),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // Body gestures
  // -------------------------------------------------------------------

  void _onBodyTapDown(TapDownDetails details) {
    _gridFocus.requestFocus();
    // The tap recognizer fires on pointer down, before the pan is recognised.
    // Selecting here would collapse a multi-cell range to one cell and rob the
    // fill of the series it was dragged from.
    if (widget.editable && _isOnFillHandle(details.localPosition)) {
      return;
    }
    final sheet = _toSheet(details.localPosition);
    if (widget.editable && _geometry.isInAddRow(sheet.dx, sheet.dy)) {
      addRow();
      return;
    }
    final ref = _cellAt(details.localPosition);
    if (ref == null) {
      return;
    }
    // Double clicks are detected by hand rather than with a
    // DoubleTapGestureRecognizer: sharing an arena with one would hold the
    // single tap back for kDoubleTapTimeout, and a spreadsheet has to select
    // the instant it is clicked.
    final now = DateTime.now();
    final last = _lastTapTime;
    final isDoubleTap = last != null &&
        _lastTapCell == ref &&
        now.difference(last) < kDoubleTapTimeout;
    _lastTapTime = now;
    _lastTapCell = ref;

    if (isDoubleTap) {
      _lastTapTime = null;
      if (widget.editable) {
        controller
          ..selectCell(ref)
          ..startEditing();
      }
      return;
    }

    final extend = HardwareKeyboard.instance.isShiftPressed;
    controller.selectCell(ref, extend: extend);
  }

  void _onBodySecondaryTap(TapUpDetails details) {
    final ref = _cellAt(details.localPosition);
    if (ref == null) {
      return;
    }
    _gridFocus.requestFocus();
    if (!controller.selection.contains(ref)) {
      controller.selectCell(ref);
    }
    showSpreadsheetCellMenu(
      context: context,
      controller: controller,
      position: details.globalPosition,
      editable: widget.editable,
    );
  }

  void _onBodyDragStart(DragStartDetails details) {
    _pressOrigin = details.localPosition;
    if (widget.editable && _isOnFillHandle(details.localPosition)) {
      _dragMode = _DragMode.fill;
      _fillSource = controller.selection;
      _fillPreview = _fillSource;
      setState(() {});
      return;
    }
    _dragMode = _DragMode.select;
    final ref = _nearestCell(details.localPosition);
    controller.selectCell(ref);
  }

  void _onBodyDragUpdate(DragUpdateDetails details) {
    if (_dragMode == _DragMode.select) {
      final ref = _nearestCell(details.localPosition);
      controller.selectRange(controller.anchor, ref);
      _autoScroll(details.localPosition);
      return;
    }
    if (_dragMode == _DragMode.fill && _fillSource != null) {
      final ref = _nearestCell(details.localPosition);
      final preview = _fillTarget(_fillSource!, ref, details.localPosition);
      if (preview != _fillPreview) {
        setState(() => _fillPreview = preview);
      }
      _autoScroll(details.localPosition);
    }
  }

  /// Fill extends along whichever axis the pointer travelled furthest.
  CellRange _fillTarget(CellRange source, CellRef ref, Offset local) {
    final horizontal = (local.dx - _pressOrigin.dx).abs();
    final vertical = (local.dy - _pressOrigin.dy).abs();
    if (vertical >= horizontal) {
      final bottom = math.max(ref.row, source.bottom);
      final top = math.min(ref.row, source.top);
      return CellRange.raw(
        top: top,
        left: source.left,
        bottom: bottom,
        right: source.right,
      );
    }
    final right = math.max(ref.column, source.right);
    final left = math.min(ref.column, source.left);
    return CellRange.raw(
      top: source.top,
      left: left,
      bottom: source.bottom,
      right: right,
    );
  }

  void _onBodyDragEnd(DragEndDetails details) {
    if (_dragMode == _DragMode.fill &&
        _fillSource != null &&
        _fillPreview != null) {
      controller.fill(_fillSource!, _fillPreview!);
    }
    _endDrag();
  }

  void _onBodyDragCancel() => _endDrag();

  void _endDrag() {
    setState(() {
      _dragMode = _DragMode.none;
      _fillPreview = null;
      _fillSource = null;
    });
  }

  void _autoScroll(Offset local) {
    final size = _bodySize;
    if (size == null) {
      return;
    }
    const edge = 28.0;
    const step = 16.0;
    if (_vertical.hasClients) {
      if (local.dy > size.height - edge) {
        _vertical.jumpTo(
          math.min(_vertical.offset + step, _vertical.position.maxScrollExtent),
        );
      } else if (local.dy < edge) {
        _vertical.jumpTo(math.max(_vertical.offset - step, 0));
      }
    }
    if (_horizontal.hasClients) {
      if (local.dx > size.width - edge) {
        _horizontal.jumpTo(
          math.min(
            _horizontal.offset + step,
            _horizontal.position.maxScrollExtent,
          ),
        );
      } else if (local.dx < edge) {
        _horizontal.jumpTo(math.max(_horizontal.offset - step, 0));
      }
    }
  }

  // -------------------------------------------------------------------
  // Keyboard
  // -------------------------------------------------------------------

  KeyEventResult _onGridKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent || !widget.editable) {
      return KeyEventResult.ignored;
    }
    if (controller.editing != null) {
      return KeyEventResult.ignored;
    }
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final character = event.character;
    if (character == null || character.isEmpty) {
      return KeyEventResult.ignored;
    }
    // Control characters (Enter, Tab, Escape) carry a character on some
    // platforms; only printable input should start an edit.
    if (character.codeUnitAt(0) < 32 || character == '\u007f') {
      return KeyEventResult.ignored;
    }
    controller.startEditing(initialText: character, fromKeystroke: true);
    return KeyEventResult.handled;
  }

  Map<ShortcutActivator, Intent> _activeShortcuts() {
    if (controller.editing == null) {
      return buildSheetShortcuts();
    }
    final editing = <ShortcutActivator, Intent>{
      const SingleActivator(LogicalKeyboardKey.tab):
          const SheetTabIntent(backwards: false),
      const SingleActivator(LogicalKeyboardKey.tab, shift: true):
          const SheetTabIntent(backwards: true),
      const SingleActivator(LogicalKeyboardKey.enter):
          const SheetEnterIntent(backwards: false),
      const SingleActivator(LogicalKeyboardKey.numpadEnter):
          const SheetEnterIntent(backwards: false),
      const SingleActivator(LogicalKeyboardKey.enter, shift: true):
          const SheetEnterIntent(backwards: true),
      const SingleActivator(LogicalKeyboardKey.escape):
          const SheetEscapeIntent(),
    };
    if (controller.editingFromKeystroke) {
      // Typing straight into a cell keeps arrow keys as navigation, the way a
      // spreadsheet behaves; F2 or a double click gives caret editing instead.
      editing.addAll({
        const SingleActivator(LogicalKeyboardKey.arrowUp):
            const SheetMoveIntent(-1, 0),
        const SingleActivator(LogicalKeyboardKey.arrowDown):
            const SheetMoveIntent(1, 0),
      });
    }
    return editing;
  }

  Map<Type, Action<Intent>> _buildActions() {
    return <Type, Action<Intent>>{
      SheetMoveIntent: CallbackAction<SheetMoveIntent>(
        onInvoke: (intent) {
          controller.commitEditing();
          controller.move(
            intent.rowDelta,
            intent.columnDelta,
            extend: intent.extend,
          );
          return null;
        },
      ),
      SheetEdgeIntent: CallbackAction<SheetEdgeIntent>(
        onInvoke: (intent) {
          controller.moveToEdge(
            intent.rowDelta,
            intent.columnDelta,
            extend: intent.extend,
          );
          return null;
        },
      ),
      SheetEditIntent: CallbackAction<SheetEditIntent>(
        onInvoke: (_) {
          if (widget.editable) {
            controller.startEditing();
          }
          return null;
        },
      ),
      SheetClearIntent: CallbackAction<SheetClearIntent>(
        onInvoke: (_) {
          if (widget.editable) {
            controller.clearSelection();
          }
          return null;
        },
      ),
      SheetTabIntent: CallbackAction<SheetTabIntent>(
        onInvoke: (intent) {
          controller.commitEditing();
          controller.advance(horizontal: true, backwards: intent.backwards);
          return null;
        },
      ),
      SheetEnterIntent: CallbackAction<SheetEnterIntent>(
        onInvoke: (intent) {
          if (controller.editing != null) {
            controller.commitEditing();
            controller.advance(horizontal: false, backwards: intent.backwards);
          } else if (widget.editable) {
            controller.startEditing();
          }
          return null;
        },
      ),
      SheetEscapeIntent: CallbackAction<SheetEscapeIntent>(
        onInvoke: (_) {
          if (controller.editing != null) {
            controller.cancelEditing();
          } else if (controller.searchQuery.isNotEmpty) {
            controller.setSearch('');
          }
          return null;
        },
      ),
      SheetCopyIntent: CallbackAction<SheetCopyIntent>(
        onInvoke: (intent) {
          if (intent.cut && widget.editable) {
            controller.cutSelection();
          } else {
            controller.copySelection();
          }
          return null;
        },
      ),
      SheetPasteIntent: CallbackAction<SheetPasteIntent>(
        onInvoke: (_) {
          controller.pasteFromClipboard();
          return null;
        },
      ),
      SheetUndoIntent: CallbackAction<SheetUndoIntent>(
        onInvoke: (intent) {
          if (intent.redo) {
            controller.redo();
          } else {
            controller.undo();
          }
          return null;
        },
      ),
      SheetSelectAllIntent: CallbackAction<SheetSelectAllIntent>(
        onInvoke: (_) {
          controller.selectAll();
          return null;
        },
      ),
      SheetFindIntent: CallbackAction<SheetFindIntent>(
        onInvoke: (_) {
          widget.onRequestFind?.call();
          return null;
        },
      ),
      SheetBoldIntent: CallbackAction<SheetBoldIntent>(
        onInvoke: (_) {
          controller.toggleBold();
          return null;
        },
      ),
      SheetItalicIntent: CallbackAction<SheetItalicIntent>(
        onInvoke: (_) {
          controller.toggleItalic();
          return null;
        },
      ),
      SheetUnderlineIntent: CallbackAction<SheetUnderlineIntent>(
        onInvoke: (_) {
          controller.toggleUnderline();
          return null;
        },
      ),
    };
  }

  /// Gives keyboard focus to the grid, used by the block when it is tapped.
  void focusGrid() => _gridFocus.requestFocus();
}
