import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'spreadsheet_controller.dart';
import 'spreadsheet_format.dart';
import 'spreadsheet_formula.dart';
import 'spreadsheet_model.dart';
import 'spreadsheet_theme.dart';

/// Where a pointer landed inside the grid.
enum SheetHitKind { cell, columnHeader, rowGutter, corner, none }

class SheetHit {
  const SheetHit(this.kind, {this.ref, this.column, this.row});

  static const none = SheetHit(SheetHitKind.none);

  final SheetHitKind kind;
  final CellRef? ref;
  final int? column;
  final int? row;
}

/// Precomputed offsets so a frame never sums thousands of row heights.
class SheetGeometry {
  SheetGeometry({
    required this.columnOffsets,
    required this.bodyRows,
    required this.rowOffsets,
    required this.showHeader,
    required this.showAddAffordances,
  });

  factory SheetGeometry.from(
    SpreadsheetController controller, {
    bool showAddAffordances = true,
  }) {
    final data = controller.data;
    final columnOffsets = List<double>.filled(data.columnCount + 1, 0);
    for (var column = 0; column < data.columnCount; column++) {
      columnOffsets[column + 1] =
          columnOffsets[column] + data.columnWidth(column);
    }

    final bodyRows = List<int>.of(controller.visibleRows);
    final rowOffsets = List<double>.filled(bodyRows.length + 1, 0);
    for (var index = 0; index < bodyRows.length; index++) {
      rowOffsets[index + 1] =
          rowOffsets[index] + data.rowHeight(bodyRows[index]);
    }

    return SheetGeometry(
      columnOffsets: columnOffsets,
      bodyRows: bodyRows,
      rowOffsets: rowOffsets,
      showHeader: data.showHeader,
      showAddAffordances: showAddAffordances,
    );
  }

  final List<double> columnOffsets;
  final List<int> bodyRows;
  final List<double> rowOffsets;
  final bool showHeader;

  /// Whether the trailing "add column" cell and "add row" band are drawn.
  final bool showAddAffordances;

  int get columnCount => columnOffsets.length - 1;
  double get totalWidth => columnOffsets.last;
  double get totalHeight => rowOffsets.last;

  double get addColumnWidth =>
      showAddAffordances ? SpreadsheetMetrics.addColumnWidth : 0;

  double get addRowHeight =>
      showAddAffordances ? SpreadsheetMetrics.addRowHeight : 0;

  /// The scrollable extent, which includes the two affordances.
  double get contentWidth => totalWidth + addColumnWidth;
  double get contentHeight => totalHeight + addRowHeight;

  /// The band under the last row that appends one, in sheet coordinates.
  Rect get addRowBand =>
      Rect.fromLTWH(0, totalHeight, totalWidth, addRowHeight);

  bool isInAddColumn(double x) =>
      showAddAffordances && x >= totalWidth && x < contentWidth;

  bool isInAddRow(double x, double y) =>
      showAddAffordances &&
      y >= totalHeight &&
      y < contentHeight &&
      x >= 0 &&
      x < totalWidth;

  double columnLeft(int column) =>
      column >= 0 && column < columnOffsets.length ? columnOffsets[column] : 0;

  double columnWidth(int column) =>
      column >= 0 && column + 1 < columnOffsets.length
          ? columnOffsets[column + 1] - columnOffsets[column]
          : 0;

  double rowTop(int index) =>
      index >= 0 && index < rowOffsets.length ? rowOffsets[index] : 0;

  double rowHeight(int index) => index >= 0 && index + 1 < rowOffsets.length
      ? rowOffsets[index + 1] - rowOffsets[index]
      : 0;

  /// Index into [bodyRows] for a source row, or -1.
  int bodyIndexOf(int sourceRow) => bodyRows.indexOf(sourceRow);

  int? columnAt(double x) {
    if (x < 0 || x >= totalWidth) {
      return null;
    }
    var low = 0;
    var high = columnCount - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (x < columnOffsets[middle]) {
        high = middle - 1;
      } else if (x >= columnOffsets[middle + 1]) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    return null;
  }

  int? bodyIndexAt(double y) {
    if (y < 0 || y >= totalHeight || bodyRows.isEmpty) {
      return null;
    }
    var low = 0;
    var high = bodyRows.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      if (y < rowOffsets[middle]) {
        high = middle - 1;
      } else if (y >= rowOffsets[middle + 1]) {
        low = middle + 1;
      } else {
        return middle;
      }
    }
    return null;
  }

  /// The half-open range of columns touching `[start, end)`.
  (int, int) visibleColumns(double start, double end) {
    if (columnCount == 0) {
      return (0, 0);
    }
    var first = columnAt(start) ?? 0;
    var last = columnAt(math.max(0, end - 0.001)) ?? columnCount - 1;
    first = math.max(0, first - SpreadsheetMetrics.overscanColumns);
    last = math.min(columnCount - 1, last + SpreadsheetMetrics.overscanColumns);
    return (first, last + 1);
  }

  (int, int) visibleBodyRows(double start, double end) {
    if (bodyRows.isEmpty) {
      return (0, 0);
    }
    var first = bodyIndexAt(start) ?? 0;
    var last = bodyIndexAt(math.max(0, end - 0.001)) ?? bodyRows.length - 1;
    first = math.max(0, first - SpreadsheetMetrics.overscanRows);
    last =
        math.min(bodyRows.length - 1, last + SpreadsheetMetrics.overscanRows);
    return (first, last + 1);
  }
}

/// Caches laid-out text so scrolling does not re-shape every cell each frame.
class SheetTextCache {
  SheetTextCache();

  final Map<CellRef, _CachedText> _entries = {};
  int _generation = 0;

  void invalidate() {
    _generation++;
    if (_entries.length > 4000) {
      _entries.clear();
    }
  }

  TextPainter painterFor({
    required CellRef ref,
    required String text,
    required TextStyle style,
    required double maxWidth,
    required TextAlign align,
  }) {
    final cached = _entries[ref];
    if (cached != null &&
        cached.generation == _generation &&
        cached.text == text &&
        cached.maxWidth == maxWidth &&
        cached.align == align &&
        cached.style == style) {
      return cached.painter;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textAlign: align,
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(maxWidth: math.max(0, maxWidth));
    _entries[ref] = _CachedText(
      generation: _generation,
      text: text,
      style: style,
      maxWidth: maxWidth,
      align: align,
      painter: painter,
    );
    return painter;
  }

  /// The natural width a cell's text wants, used for auto-fit.
  double intrinsicWidth(String text, TextStyle style) {
    if (text.isEmpty) {
      return 0;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: style),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return painter.width;
  }
}

class _CachedText {
  const _CachedText({
    required this.generation,
    required this.text,
    required this.style,
    required this.maxWidth,
    required this.align,
    required this.painter,
  });

  final int generation;
  final String text;
  final TextStyle style;
  final double maxWidth;
  final TextAlign align;
  final TextPainter painter;
}

/// Paints the scrolling body: banding, cell text, grid lines and selection.
class SheetBodyPainter extends CustomPainter {
  SheetBodyPainter({
    required this.controller,
    required this.geometry,
    required this.palette,
    required this.typography,
    required this.textCache,
    required this.horizontal,
    required this.vertical,
    required this.fillPreview,
    required this.hoveredCell,
    required this.selectionSettle,
    required this.placeholder,
    required this.addRowLabel,
    required this.addRowHovered,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SpreadsheetController controller;
  final SheetGeometry geometry;
  final SpreadsheetPalette palette;
  final SpreadsheetTypography typography;
  final SheetTextCache textCache;
  final ScrollController horizontal;
  final ScrollController vertical;
  final CellRange? fillPreview;
  final CellRef? hoveredCell;

  /// Runs 0 to 1 as the focus ring settles onto a newly selected cell. Held as
  /// the animation rather than its value: the painter repaints without
  /// rebuilding, so a captured double would never move.
  final Animation<double> selectionSettle;

  /// Shown in the first body cell while the whole sheet is empty.
  final String? placeholder;

  /// The label on the band under the last row.
  final String? addRowLabel;
  final bool addRowHovered;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = horizontal.hasClients ? horizontal.offset : 0.0;
    final dy = vertical.hasClients ? vertical.offset : 0.0;

    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.translate(-dx, -dy);

    final (firstColumn, endColumn) =
        geometry.visibleColumns(dx, dx + size.width);
    final (firstRow, endRow) = geometry.visibleBodyRows(dy, dy + size.height);

    final background = Paint()..style = PaintingStyle.fill;
    final selection = controller.selection;
    final search = controller.searchMatches.toSet();
    final currentMatch = controller.currentSearchMatch;
    final selectedColumns = controller.selectedColumnHeader;

    // Backgrounds.
    for (var index = firstRow; index < endRow; index++) {
      final sourceRow = geometry.bodyRows[index];
      final top = geometry.rowTop(index);
      final height = geometry.rowHeight(index);
      final rowHovered = controller.hoveredRow == sourceRow;
      for (var column = firstColumn; column < endColumn; column++) {
        if (controller.data.isColumnHidden(column)) {
          continue;
        }
        final ref = CellRef(sourceRow, column);
        final rect = Rect.fromLTWH(
          geometry.columnLeft(column),
          top,
          geometry.columnWidth(column),
          height,
        );
        final style = controller.data.styleAt(ref);
        var color = style.backgroundColor != null
            ? Color(style.backgroundColor!)
            : palette.surface;
        if (rowHovered || selectedColumns == column) {
          color = Color.alphaBlend(palette.hover, color);
        }
        if (hoveredCell == ref) {
          color = Color.alphaBlend(palette.hover, color);
        }
        if (selection.contains(ref) && ref != controller.active) {
          color = Color.alphaBlend(palette.selection, color);
        }
        if (search.contains(ref)) {
          color = Color.alphaBlend(
            palette.accent.withValues(alpha: ref == currentMatch ? 0.30 : 0.14),
            color,
          );
        }
        if (color == palette.surface) {
          continue;
        }
        background.color = color;
        canvas.drawRect(rect, background);
      }
    }

    _paintGridLines(
      canvas,
      firstColumn: firstColumn,
      endColumn: endColumn,
      firstRow: firstRow,
      endRow: endRow,
    );

    // Text.
    for (var index = firstRow; index < endRow; index++) {
      final sourceRow = geometry.bodyRows[index];
      final top = geometry.rowTop(index);
      final height = geometry.rowHeight(index);
      for (var column = firstColumn; column < endColumn; column++) {
        final width = geometry.columnWidth(column);
        if (width <= 0) {
          continue;
        }
        final ref = CellRef(sourceRow, column);
        if (controller.editing == ref) {
          continue;
        }
        _paintCellText(
          canvas,
          ref: ref,
          rect: Rect.fromLTWH(geometry.columnLeft(column), top, width, height),
        );
      }
    }

    _paintPlaceholder(canvas);
    _paintAddRow(canvas);
    _paintSelection(canvas, selection);
    if (fillPreview != null) {
      _paintFillPreview(canvas, fillPreview!);
    }

    canvas.restore();
  }

  /// A single hairline per boundary, light enough that the grid reads as
  /// alignment rather than as a drawn table.
  void _paintGridLines(
    Canvas canvas, {
    required int firstColumn,
    required int endColumn,
    required int firstRow,
    required int endRow,
  }) {
    final line = Paint()
      ..color = palette.gridLine
      ..strokeWidth = 1
      ..isAntiAlias = false;
    final top = geometry.rowTop(firstRow);
    final bottom = geometry.rowTop(endRow);

    // Column rules stop short of the used range so the sheet fades out at its
    // edges instead of ending in a hard box.
    for (var column = firstColumn + 1; column < endColumn; column++) {
      if (column >= geometry.columnCount) {
        break;
      }
      if (geometry.columnWidth(column) <= 0) {
        continue;
      }
      final x = geometry.columnLeft(column) - 0.5;
      canvas.drawLine(Offset(x, top), Offset(x, bottom), line);
    }

    final left = geometry.columnLeft(firstColumn);
    final right =
        geometry.columnLeft(math.min(endColumn, geometry.columnCount));
    for (var index = firstRow + 1; index <= endRow; index++) {
      if (index >= geometry.rowOffsets.length) {
        break;
      }
      final y = geometry.rowTop(index) - 0.5;
      canvas.drawLine(Offset(left, y), Offset(right, y), line);
    }
  }

  /// The hint shown in the first body cell of an untouched sheet.
  void _paintPlaceholder(Canvas canvas) {
    final text = placeholder;
    if (text == null || text.isEmpty || geometry.bodyRows.isEmpty) {
      return;
    }
    if (controller.editing != null) {
      return;
    }
    final painter = TextPainter(
      text: TextSpan(text: text, style: typography.placeholder),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '…',
    )..layout(
        maxWidth: math.max(
          0,
          geometry.columnWidth(0) -
              SpreadsheetMetrics.cellPaddingHorizontal * 2,
        ),
      );
    painter.paint(
      canvas,
      Offset(
        SpreadsheetMetrics.cellPaddingHorizontal,
        geometry.rowTop(0) + (geometry.rowHeight(0) - painter.height) / 2,
      ),
    );
  }

  /// The band under the last row that appends one, the way a database grid
  /// ends with "New row".
  void _paintAddRow(Canvas canvas) {
    final label = addRowLabel;
    if (label == null || !geometry.showAddAffordances) {
      return;
    }
    final dx = horizontal.hasClients ? horizontal.offset : 0.0;
    // The band stops with the columns, so its rule matches every other row
    // rule instead of running the full width of the viewport.
    final band = Rect.fromLTWH(
      0,
      geometry.totalHeight,
      geometry.totalWidth,
      geometry.addRowHeight,
    );
    if (addRowHovered) {
      canvas.drawRect(band, Paint()..color = palette.hover);
    }
    canvas.drawLine(
      Offset(band.left, band.top - 0.5),
      Offset(band.right, band.top - 0.5),
      Paint()
        ..color = palette.gridLine
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );

    final color = addRowHovered ? palette.textSecondary : palette.textMuted;
    final painter = TextPainter(
      text: TextSpan(
        text: label,
        style: typography.chrome.copyWith(color: color),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    final centreY = band.center.dy;
    const glyph = 5.0;
    final glyphX = dx + SpreadsheetMetrics.cellPaddingHorizontal + glyph;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(glyphX - glyph, centreY),
        Offset(glyphX + glyph, centreY),
        stroke,
      )
      ..drawLine(
        Offset(glyphX, centreY - glyph),
        Offset(glyphX, centreY + glyph),
        stroke,
      );
    painter.paint(
      canvas,
      Offset(glyphX + glyph + 9, centreY - painter.height / 2),
    );
  }

  void _paintCellText(
    Canvas canvas, {
    required CellRef ref,
    required Rect rect,
  }) {
    final cell = controller.data.cellAt(ref);
    if (cell.raw.isEmpty) {
      return;
    }
    final value = controller.valueAt(ref);
    final text = formatCellValue(value, cell.style, raw: cell.raw);
    if (text.isEmpty) {
      return;
    }
    final style = cellTextStyle(
      base: typography.cell,
      style: cell.style,
      palette: palette,
      isError: value.isError,
    );
    final align = resolveAlign(cell.style, value);
    final maxWidth = rect.width - SpreadsheetMetrics.cellPaddingHorizontal * 2;
    final painter = textCache.painterFor(
      ref: ref,
      text: text,
      style: style,
      maxWidth: maxWidth,
      align: align,
    );
    final dx = switch (align) {
      TextAlign.right =>
        rect.right - SpreadsheetMetrics.cellPaddingHorizontal - painter.width,
      TextAlign.center => rect.left + (rect.width - painter.width) / 2,
      _ => rect.left + SpreadsheetMetrics.cellPaddingHorizontal,
    };
    final dy = rect.top + (rect.height - painter.height) / 2;
    canvas.save();
    canvas.clipRect(rect);
    painter.paint(canvas, Offset(dx, dy));
    canvas.restore();
  }

  /// A soft halo, then a rounded ring — the cursor announces itself the way a
  /// focused field does, not with a hard square outline.
  void _paintSelection(Canvas canvas, CellRange range) {
    final rect = _rangeRect(range);
    if (rect == null) {
      return;
    }
    final settle = selectionSettle.value.clamp(0.0, 1.0);
    final radius = Radius.circular(range.isSingle ? 5 : 4);
    final ring = rect.deflate(1);

    if (settle > 0) {
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          ring.inflate(2.5 * settle),
          Radius.circular(radius.x + 2),
        ),
        Paint()
          ..color = palette.focusHalo.withValues(
            alpha: palette.focusHalo.a * settle,
          ),
      );
    }
    canvas.drawRRect(
      RRect.fromRectAndRadius(ring, radius),
      Paint()
        ..color = range.isSingle ? palette.focusRing : palette.selectionBorder
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.8,
    );

    // Fill handle at the bottom-right corner.
    const size = SpreadsheetMetrics.fillHandleSize;
    final handleBounds =
        Rect.fromCenter(center: rect.bottomRight, width: size, height: size);
    canvas.drawRRect(
      RRect.fromRectAndRadius(handleBounds, const Radius.circular(2)),
      Paint()..color = palette.surface,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        handleBounds.deflate(1),
        const Radius.circular(1.5),
      ),
      Paint()..color = palette.focusRing,
    );
  }

  void _paintFillPreview(Canvas canvas, CellRange range) {
    final rect = _rangeRect(range);
    if (rect == null) {
      return;
    }
    final paint = Paint()
      ..color = palette.focusRing.withValues(alpha: 0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    _drawDashedRect(canvas, rect.deflate(0.5), paint);
  }

  static void _drawDashedRect(Canvas canvas, Rect rect, Paint paint) {
    const dash = 4.0;
    const gap = 3.0;
    void line(Offset from, Offset to) {
      final total = (to - from).distance;
      if (total <= 0) {
        return;
      }
      final direction = (to - from) / total;
      var travelled = 0.0;
      while (travelled < total) {
        final end = math.min(travelled + dash, total);
        canvas.drawLine(
          from + direction * travelled,
          from + direction * end,
          paint,
        );
        travelled = end + gap;
      }
    }

    line(rect.topLeft, rect.topRight);
    line(rect.topRight, rect.bottomRight);
    line(rect.bottomRight, rect.bottomLeft);
    line(rect.bottomLeft, rect.topLeft);
  }

  /// Body rect for a range, clipped to the rows that are actually shown.
  Rect? _rangeRect(CellRange range) {
    var top = double.infinity;
    var bottom = -double.infinity;
    for (var row = range.top; row <= range.bottom; row++) {
      final index = geometry.bodyIndexOf(row);
      if (index < 0) {
        continue;
      }
      top = math.min(top, geometry.rowTop(index));
      bottom =
          math.max(bottom, geometry.rowTop(index) + geometry.rowHeight(index));
    }
    if (!top.isFinite || !bottom.isFinite) {
      return null;
    }
    final left = geometry.columnLeft(range.left);
    final right = geometry.columnLeft(
      math.min(range.right + 1, geometry.columnCount),
    );
    return Rect.fromLTRB(left, top, right, bottom);
  }

  @override
  bool shouldRepaint(SheetBodyPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.palette != palette ||
      oldDelegate.hoveredCell != hoveredCell ||
      oldDelegate.selectionSettle != selectionSettle ||
      oldDelegate.placeholder != placeholder ||
      oldDelegate.addRowLabel != addRowLabel ||
      oldDelegate.addRowHovered != addRowHovered ||
      oldDelegate.fillPreview != fillPreview;
}

/// Paints the frozen column header strip.
class SheetHeaderPainter extends CustomPainter {
  SheetHeaderPainter({
    required this.controller,
    required this.geometry,
    required this.palette,
    required this.typography,
    required this.horizontal,
    required this.hoveredColumn,
    required this.dropIndicator,
    required this.resizingEdge,
    required this.addColumnHovered,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SpreadsheetController controller;
  final SheetGeometry geometry;
  final SpreadsheetPalette palette;
  final SpreadsheetTypography typography;
  final ScrollController horizontal;
  final int? hoveredColumn;
  final int? dropIndicator;

  /// The boundary the pointer is over or dragging, highlighted while resizing.
  final int? resizingEdge;

  final bool addColumnHovered;

  @override
  void paint(Canvas canvas, Size size) {
    final dx = horizontal.hasClients ? horizontal.offset : 0.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.headerSurface,
    );
    canvas.translate(-dx, 0);

    final (firstColumn, endColumn) =
        geometry.visibleColumns(dx, dx + size.width);
    final selection = controller.selection;
    final line = Paint()
      ..color = palette.gridLine
      ..strokeWidth = 1
      ..isAntiAlias = false;

    for (var column = firstColumn; column < endColumn; column++) {
      final width = geometry.columnWidth(column);
      if (width <= 0) {
        continue;
      }
      final rect = Rect.fromLTWH(
        geometry.columnLeft(column),
        0,
        width,
        size.height,
      );
      final isSelected = column >= selection.left && column <= selection.right;
      if (isSelected || hoveredColumn == column) {
        canvas.drawRect(
          rect,
          Paint()..color = isSelected ? palette.selection : palette.hover,
        );
      }
      if (isSelected) {
        // An accent underline instead of a box: the column reads as active
        // without boxing the header in.
        canvas.drawRect(
          Rect.fromLTWH(rect.left, rect.bottom - 2, rect.width, 2),
          Paint()..color = palette.focusRing,
        );
      }

      final title =
          geometry.showHeader ? controller.data.columnTitle(column) : '';
      final text = controller.data.headerLabel(column);
      final style = title.isNotEmpty
          ? typography.header.copyWith(color: palette.textSecondary)
          : typography.header.copyWith(color: palette.textMuted);
      if (controller.editingHeader != column) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          textDirection: TextDirection.ltr,
          maxLines: 1,
          ellipsis: '…',
        )..layout(
            maxWidth: math.max(
              0,
              width - SpreadsheetMetrics.cellPaddingHorizontal * 2 - 12,
            ),
          );
        canvas.save();
        canvas.clipRect(rect);
        painter.paint(
          canvas,
          Offset(
            rect.left + SpreadsheetMetrics.cellPaddingHorizontal,
            rect.top + (rect.height - painter.height) / 2,
          ),
        );
        canvas.restore();
      }

      // Sort and filter markers keep the header honest about the view.
      final sort = controller.data.sort;
      final hasFilter = controller.filterFor(column).isNotEmpty;
      if (sort?.column == column || hasFilter) {
        final marker = Paint()..color = palette.accent;
        final centre = Offset(rect.right - 12, rect.center.dy);
        if (hasFilter) {
          canvas.drawCircle(centre, 2.6, marker);
        } else {
          final ascending = sort!.direction == SortDirection.ascending;
          final path = Path();
          if (ascending) {
            path
              ..moveTo(centre.dx - 3.4, centre.dy + 1.8)
              ..lineTo(centre.dx + 3.4, centre.dy + 1.8)
              ..lineTo(centre.dx, centre.dy - 2.6);
          } else {
            path
              ..moveTo(centre.dx - 3.4, centre.dy - 1.8)
              ..lineTo(centre.dx + 3.4, centre.dy - 1.8)
              ..lineTo(centre.dx, centre.dy + 2.6);
          }
          canvas.drawPath(path..close(), marker);
        }
      }

      if (column < geometry.columnCount - 1) {
        final x = rect.right - 0.5;
        canvas.drawLine(Offset(x, 9), Offset(x, size.height - 9), line);
      }
    }

    // The resize affordance: a soft accent bar on the boundary under the
    // pointer, so the drag target is obvious before the drag begins.
    if (resizingEdge != null) {
      final x = geometry.columnLeft(resizingEdge!) +
          geometry.columnWidth(resizingEdge!);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 1, 6, 2, size.height - 12),
          const Radius.circular(1),
        ),
        Paint()..color = palette.focusRing,
      );
    }

    if (dropIndicator != null) {
      final x =
          geometry.columnLeft(dropIndicator!.clamp(0, geometry.columnCount));
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(x - 1, 4, 2, size.height - 8),
          const Radius.circular(1),
        ),
        Paint()..color = palette.accent,
      );
    }

    _paintAddColumn(canvas, size);

    canvas.restore();
    canvas.drawLine(
      Offset(0, size.height - 0.5),
      Offset(size.width, size.height - 0.5),
      Paint()
        ..color = palette.divider
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
  }

  /// The trailing cell that appends a column, mirroring the database grid's
  /// "New property".
  void _paintAddColumn(Canvas canvas, Size size) {
    if (!geometry.showAddAffordances) {
      return;
    }
    final rect = Rect.fromLTWH(
      geometry.totalWidth,
      0,
      geometry.addColumnWidth,
      size.height,
    );
    if (addColumnHovered) {
      canvas.drawRect(rect, Paint()..color = palette.hover);
    }
    final color = addColumnHovered ? palette.textSecondary : palette.textMuted;
    const glyph = 5.5;
    final centre = rect.center;
    final stroke = Paint()
      ..color = color
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;
    canvas
      ..drawLine(
        Offset(centre.dx - glyph, centre.dy),
        Offset(centre.dx + glyph, centre.dy),
        stroke,
      )
      ..drawLine(
        Offset(centre.dx, centre.dy - glyph),
        Offset(centre.dx, centre.dy + glyph),
        stroke,
      );
  }

  @override
  bool shouldRepaint(SheetHeaderPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.palette != palette ||
      oldDelegate.hoveredColumn != hoveredColumn ||
      oldDelegate.resizingEdge != resizingEdge ||
      oldDelegate.addColumnHovered != addColumnHovered ||
      oldDelegate.dropIndicator != dropIndicator;
}

/// Paints the frozen row-number gutter.
class SheetGutterPainter extends CustomPainter {
  SheetGutterPainter({
    required this.controller,
    required this.geometry,
    required this.palette,
    required this.typography,
    required this.vertical,
    required this.pointerInside,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final SpreadsheetController controller;
  final SheetGeometry geometry;
  final SpreadsheetPalette palette;
  final SpreadsheetTypography typography;
  final ScrollController vertical;

  /// Row numbers are almost invisible until the pointer is over the sheet.
  final bool pointerInside;

  @override
  void paint(Canvas canvas, Size size) {
    final dy = vertical.hasClients ? vertical.offset : 0.0;
    canvas.save();
    canvas.clipRect(Offset.zero & size);
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = palette.gutterSurface,
    );
    canvas.translate(0, -dy);

    final (firstRow, endRow) = geometry.visibleBodyRows(dy, dy + size.height);
    final selection = controller.selection;

    for (var index = firstRow; index < endRow; index++) {
      final sourceRow = geometry.bodyRows[index];
      final rect = Rect.fromLTWH(
        0,
        geometry.rowTop(index),
        size.width,
        geometry.rowHeight(index),
      );
      final isSelected =
          sourceRow >= selection.top && sourceRow <= selection.bottom;
      final isHovered = controller.hoveredRow == sourceRow;
      if (isSelected) {
        canvas.drawRect(rect, Paint()..color = palette.selection);
      } else if (isHovered) {
        canvas.drawRect(rect, Paint()..color = palette.hover);
      }

      final opacity = isSelected || isHovered
          ? 1.0
          : pointerInside
              ? 0.72
              : 0.42;
      final painter = TextPainter(
        text: TextSpan(
          // The true A1 row, not the position on screen: a header row makes
          // the first body row number 2, exactly as `=A2` addresses it.
          text: '${sourceRow + 1}',
          style: typography.gutter.copyWith(
            color: (isSelected ? palette.accent : palette.textMuted)
                .withValues(alpha: opacity),
            fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          ),
        ),
        textDirection: TextDirection.ltr,
        maxLines: 1,
      )..layout();
      painter.paint(
        canvas,
        Offset(
          rect.center.dx - painter.width / 2,
          rect.top + (rect.height - painter.height) / 2,
        ),
      );
    }

    canvas.restore();
    canvas.drawLine(
      Offset(size.width - 0.5, 0),
      Offset(size.width - 0.5, size.height),
      Paint()
        ..color = palette.gridLine
        ..strokeWidth = 1
        ..isAntiAlias = false,
    );
  }

  @override
  bool shouldRepaint(SheetGutterPainter oldDelegate) =>
      oldDelegate.geometry != geometry ||
      oldDelegate.palette != palette ||
      oldDelegate.pointerInside != pointerInside;
}

/// Builds the text style for one cell from its stored format.
TextStyle cellTextStyle({
  required TextStyle base,
  required CellStyle style,
  required SpreadsheetPalette palette,
  required bool isError,
}) {
  var decoration = TextDecoration.none;
  if (style.underline && style.strikethrough) {
    decoration = TextDecoration.combine(
      const [TextDecoration.underline, TextDecoration.lineThrough],
    );
  } else if (style.underline) {
    decoration = TextDecoration.underline;
  } else if (style.strikethrough) {
    decoration = TextDecoration.lineThrough;
  }
  // A filled cell keeps its own contrast: the swatches are light, so on a dark
  // theme the inherited light body colour would vanish into them.
  final Color? onFill = style.backgroundColor == null
      ? null
      : Color(style.backgroundColor!).computeLuminance() > 0.5
          ? const Color(0xFF1F2933)
          : const Color(0xFFF7F8F9);
  final color = isError
      ? palette.danger
      : style.textColor != null
          ? Color(style.textColor!)
          : (onFill ?? base.color);
  return base.copyWith(
    fontWeight: style.bold ? FontWeight.w600 : base.fontWeight,
    fontStyle: style.italic ? FontStyle.italic : FontStyle.normal,
    decoration: decoration,
    decorationColor: color,
    color: color,
  );
}

TextAlign resolveAlign(CellStyle style, SheetValue value) {
  switch (style.align) {
    case CellAlign.start:
      return TextAlign.left;
    case CellAlign.center:
      return TextAlign.center;
    case CellAlign.end:
      return TextAlign.right;
    case null:
      return isRightAlignedByDefault(value, style)
          ? TextAlign.right
          : TextAlign.left;
  }
}

/// A pan recognizer restricted to the mouse so trackpad panning still belongs
/// to the scroll view underneath.
///
/// It reports the press position rather than the position the drag was
/// recognised at, which is what lets a fast drag off the small fill handle
/// still count as a fill.
class MouseDragGestureRecognizer extends PanGestureRecognizer {
  MouseDragGestureRecognizer({super.debugOwner})
      : super(supportedDevices: const {PointerDeviceKind.mouse}) {
    dragStartBehavior = DragStartBehavior.down;
  }
}

/// Keyboard intents raised by the grid.
class SheetMoveIntent extends Intent {
  const SheetMoveIntent(this.rowDelta, this.columnDelta, {this.extend = false});
  final int rowDelta;
  final int columnDelta;
  final bool extend;
}

class SheetEdgeIntent extends Intent {
  const SheetEdgeIntent(this.rowDelta, this.columnDelta, {this.extend = false});
  final int rowDelta;
  final int columnDelta;
  final bool extend;
}

class SheetEditIntent extends Intent {
  const SheetEditIntent();
}

class SheetClearIntent extends Intent {
  const SheetClearIntent();
}

class SheetTabIntent extends Intent {
  const SheetTabIntent({required this.backwards});
  final bool backwards;
}

class SheetEnterIntent extends Intent {
  const SheetEnterIntent({required this.backwards});
  final bool backwards;
}

class SheetEscapeIntent extends Intent {
  const SheetEscapeIntent();
}

class SheetCopyIntent extends Intent {
  const SheetCopyIntent({required this.cut});
  final bool cut;
}

class SheetPasteIntent extends Intent {
  const SheetPasteIntent();
}

class SheetUndoIntent extends Intent {
  const SheetUndoIntent({required this.redo});
  final bool redo;
}

class SheetSelectAllIntent extends Intent {
  const SheetSelectAllIntent();
}

class SheetFindIntent extends Intent {
  const SheetFindIntent();
}

class SheetBoldIntent extends Intent {
  const SheetBoldIntent();
}

class SheetItalicIntent extends Intent {
  const SheetItalicIntent();
}

class SheetUnderlineIntent extends Intent {
  const SheetUnderlineIntent();
}

/// The shortcut table the grid installs while it has focus.
Map<ShortcutActivator, Intent> buildSheetShortcuts() {
  final meta = defaultTargetPlatform == TargetPlatform.macOS;
  SingleActivator control(
    LogicalKeyboardKey key, {
    bool shift = false,
  }) =>
      SingleActivator(
        key,
        control: !meta,
        meta: meta,
        shift: shift,
      );

  return <ShortcutActivator, Intent>{
    const SingleActivator(LogicalKeyboardKey.arrowUp):
        const SheetMoveIntent(-1, 0),
    const SingleActivator(LogicalKeyboardKey.arrowDown):
        const SheetMoveIntent(1, 0),
    const SingleActivator(LogicalKeyboardKey.arrowLeft):
        const SheetMoveIntent(0, -1),
    const SingleActivator(LogicalKeyboardKey.arrowRight):
        const SheetMoveIntent(0, 1),
    const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true):
        const SheetMoveIntent(-1, 0, extend: true),
    const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
        const SheetMoveIntent(1, 0, extend: true),
    const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
        const SheetMoveIntent(0, -1, extend: true),
    const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
        const SheetMoveIntent(0, 1, extend: true),
    const SingleActivator(LogicalKeyboardKey.pageUp):
        const SheetMoveIntent(-12, 0),
    const SingleActivator(LogicalKeyboardKey.pageDown):
        const SheetMoveIntent(12, 0),
    const SingleActivator(LogicalKeyboardKey.home):
        const SheetEdgeIntent(0, -1),
    const SingleActivator(LogicalKeyboardKey.end): const SheetEdgeIntent(0, 1),
    control(LogicalKeyboardKey.home): const SheetEdgeIntent(-1, 0),
    control(LogicalKeyboardKey.end): const SheetEdgeIntent(1, 0),
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
    const SingleActivator(LogicalKeyboardKey.escape): const SheetEscapeIntent(),
    const SingleActivator(LogicalKeyboardKey.f2): const SheetEditIntent(),
    const SingleActivator(LogicalKeyboardKey.delete): const SheetClearIntent(),
    const SingleActivator(LogicalKeyboardKey.backspace):
        const SheetClearIntent(),
    control(LogicalKeyboardKey.keyC): const SheetCopyIntent(cut: false),
    control(LogicalKeyboardKey.keyX): const SheetCopyIntent(cut: true),
    control(LogicalKeyboardKey.keyV): const SheetPasteIntent(),
    control(LogicalKeyboardKey.keyZ): const SheetUndoIntent(redo: false),
    control(LogicalKeyboardKey.keyZ, shift: true):
        const SheetUndoIntent(redo: true),
    control(LogicalKeyboardKey.keyY): const SheetUndoIntent(redo: true),
    control(LogicalKeyboardKey.keyA): const SheetSelectAllIntent(),
    control(LogicalKeyboardKey.keyF): const SheetFindIntent(),
    control(LogicalKeyboardKey.keyB): const SheetBoldIntent(),
    control(LogicalKeyboardKey.keyI): const SheetItalicIntent(),
    control(LogicalKeyboardKey.keyU): const SheetUnderlineIntent(),
  };
}
