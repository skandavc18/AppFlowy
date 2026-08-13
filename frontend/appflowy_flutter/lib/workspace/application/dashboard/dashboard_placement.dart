import 'dart:math' as math;

import 'package:flutter/foundation.dart';

/// Where one widget sits on the dashboard grid, and how big it is.
///
/// The grid is measured in COLUMNS across and ROW UNITS down. A row unit is a
/// fixed height, so a placement is resolution independent: the same dashboard
/// is laid out on a laptop, a tablet and a phone by changing only how many
/// columns the canvas offers.
@immutable
class DashboardPlacement {
  const DashboardPlacement({
    this.column = 0,
    this.row = 0,
    this.columnSpan = 4,
    this.rowSpan = 4,
  });

  factory DashboardPlacement.fromJson(Map<String, Object?> json) =>
      DashboardPlacement(
        column: _readInt(json['x'], 0),
        row: _readInt(json['y'], 0),
        columnSpan: _readInt(json['w'], 4),
        rowSpan: _readInt(json['h'], 4),
      );

  /// The column count every stored placement is expressed in.
  ///
  /// Twelve divides by 2, 3, 4 and 6, so one, two, three and four column
  /// arrangements are all exact — which is what keeps a re-flow from leaving
  /// a ragged edge.
  static const int referenceColumns = 12;

  final int column;
  final int row;
  final int columnSpan;
  final int rowSpan;

  int get endColumn => column + columnSpan;

  int get endRow => row + rowSpan;

  DashboardPlacement copyWith({
    int? column,
    int? row,
    int? columnSpan,
    int? rowSpan,
  }) =>
      DashboardPlacement(
        column: column ?? this.column,
        row: row ?? this.row,
        columnSpan: columnSpan ?? this.columnSpan,
        rowSpan: rowSpan ?? this.rowSpan,
      );

  Map<String, Object?> toJson() => {
        'x': column,
        'y': row,
        'w': columnSpan,
        'h': rowSpan,
      };

  bool overlaps(DashboardPlacement other) =>
      column < other.endColumn &&
      other.column < endColumn &&
      row < other.endRow &&
      other.row < endRow;

  @override
  bool operator ==(Object other) =>
      other is DashboardPlacement &&
      other.column == column &&
      other.row == row &&
      other.columnSpan == columnSpan &&
      other.rowSpan == rowSpan;

  @override
  int get hashCode => Object.hash(column, row, columnSpan, rowSpan);

  @override
  String toString() =>
      'DashboardPlacement($column,$row ${columnSpan}x$rowSpan)';
}

/// How many columns the canvas offers at [width].
///
/// The steps are deliberately coarse. A grid that changes column count every
/// few pixels reads as a layout that will not sit still, and a widget narrower
/// than about 150px cannot say anything useful.
int dashboardColumnsFor(double width) {
  if (width >= 1180) {
    return 12;
  }
  if (width >= 900) {
    return 8;
  }
  if (width >= 640) {
    return 6;
  }
  if (width >= 420) {
    return 4;
  }
  return 2;
}

/// Rewrite a placement stored against [from] columns for a canvas of [to].
///
/// Spans are scaled and rounded UP so a widget never loses so much width that
/// it stops working; a widget that filled the row still fills it.
DashboardPlacement scaleDashboardPlacement(
  DashboardPlacement placement, {
  required int from,
  required int to,
}) {
  if (from == to || from <= 0 || to <= 0) {
    return placement;
  }
  final ratio = to / from;
  var span = (placement.columnSpan * ratio).ceil();
  span = span.clamp(1, to);
  var column = (placement.column * ratio).floor();
  column = column.clamp(0, to - span);
  return placement.copyWith(column: column, columnSpan: span);
}

/// One widget's identity paired with where it wants to be.
///
/// The layout functions work on this rather than on the widget itself, so the
/// geometry stays free of everything a widget knows about.
@immutable
class DashboardSlot {
  const DashboardSlot({required this.id, required this.placement});

  final String id;
  final DashboardPlacement placement;

  DashboardSlot withPlacement(DashboardPlacement placement) =>
      DashboardSlot(id: id, placement: placement);
}

/// Settle [slots] onto a canvas of [columns], removing overlaps and the gaps
/// left above them.
///
/// The rules are the ones a person expects from a dashboard builder: reading
/// order is top to bottom then left to right, a widget never covers another,
/// and everything floats up until it rests on something. It is deliberately
/// pure — the canvas calls it during a drag to preview the result.
///
/// [compact] is the floating up. A free section turns it off: a widget dropped
/// into open space stays in the open space, which is the whole promise of a
/// freeform grid.
List<DashboardSlot> resolveDashboardLayout(
  List<DashboardSlot> slots, {
  required int columns,
  int storedColumns = DashboardPlacement.referenceColumns,
  String? floating,
  bool compact = true,
}) {
  if (slots.isEmpty) {
    return const [];
  }
  final scaled = <DashboardSlot>[
    for (final slot in slots)
      slot.withPlacement(
        _clampToCanvas(
          scaleDashboardPlacement(
            slot.placement,
            from: storedColumns,
            to: columns,
          ),
          columns: columns,
        ),
      ),
  ];

  // Reading order. A widget being dragged keeps its exact position, so it is
  // settled first and everything else flows around it.
  final ordered = [...scaled]..sort((a, b) {
      if (floating != null) {
        if (a.id == floating) {
          return -1;
        }
        if (b.id == floating) {
          return 1;
        }
      }
      final byRow = a.placement.row.compareTo(b.placement.row);
      return byRow != 0
          ? byRow
          : a.placement.column.compareTo(b.placement.column);
    });

  final settled = <DashboardSlot>[];
  for (final slot in ordered) {
    var placement = slot.placement;
    if (slot.id == floating) {
      settled.add(slot.withPlacement(placement));
      continue;
    }
    var row = compact ? 0 : placement.row;
    // Float up to the first row where nothing is already sitting, or, when the
    // section is free, push down from where it was put until it is clear.
    for (final other in settled) {
      final candidate = placement.copyWith(row: row);
      if (candidate.overlaps(other.placement)) {
        row = other.placement.endRow;
      }
    }
    // One more pass: raising the row can uncover a different neighbour.
    var moved = true;
    while (moved) {
      moved = false;
      for (final other in settled) {
        if (placement.copyWith(row: row).overlaps(other.placement)) {
          row = other.placement.endRow;
          moved = true;
        }
      }
    }
    placement = placement.copyWith(row: row);
    settled.add(slot.withPlacement(placement));
  }

  // Hand them back in the caller's order so widget identity is preserved.
  final byId = {for (final slot in settled) slot.id: slot};
  return [for (final slot in slots) byId[slot.id] ?? slot];
}

DashboardPlacement _clampToCanvas(
  DashboardPlacement placement, {
  required int columns,
}) {
  final span = placement.columnSpan.clamp(1, columns);
  final column = placement.column.clamp(0, columns - span);
  return placement.copyWith(
    column: column,
    columnSpan: span,
    rowSpan: math.max(1, placement.rowSpan),
    row: math.max(0, placement.row),
  );
}

/// How many row units the settled [slots] occupy.
int dashboardLayoutHeight(List<DashboardSlot> slots) {
  var height = 0;
  for (final slot in slots) {
    height = math.max(height, slot.placement.endRow);
  }
  return height;
}

/// The pixel geometry of one canvas.
@immutable
class DashboardGridMetrics {
  const DashboardGridMetrics({
    required this.columns,
    required this.columnWidth,
    required this.rowHeight,
    required this.gap,
  });

  final int columns;
  final double columnWidth;
  final double rowHeight;
  final double gap;

  double widthOf(int span) => span * columnWidth + math.max(0, span - 1) * gap;

  double heightOf(int span) => span * rowHeight + math.max(0, span - 1) * gap;

  double leftOf(int column) => column * (columnWidth + gap);

  double topOf(int row) => row * (rowHeight + gap);

  /// The column a pointer at [dx] is over.
  int columnAt(double dx) {
    final step = columnWidth + gap;
    if (step <= 0) {
      return 0;
    }
    return (dx / step).round().clamp(0, columns - 1);
  }

  /// The row a pointer at [dy] is over.
  int rowAt(double dy) {
    final step = rowHeight + gap;
    if (step <= 0) {
      return 0;
    }
    return math.max(0, (dy / step).round());
  }

  /// The span that best fits a box [width] wide.
  int spanForWidth(double width) {
    final step = columnWidth + gap;
    if (step <= 0) {
      return 1;
    }
    return ((width + gap) / step).round().clamp(1, columns);
  }

  /// The span that best fits a box [height] tall.
  int spanForHeight(double height) {
    final step = rowHeight + gap;
    if (step <= 0) {
      return 1;
    }
    return math.max(1, ((height + gap) / step).round());
  }
}

/// Work out the pixel geometry for a canvas [width] wide.
DashboardGridMetrics dashboardGridMetrics({
  required double width,
  required int columns,
  required double gap,
  required double rowHeight,
}) {
  final safeColumns = math.max(1, columns);
  final available = math.max(0.0, width - gap * (safeColumns - 1));
  return DashboardGridMetrics(
    columns: safeColumns,
    columnWidth: available / safeColumns,
    rowHeight: rowHeight,
    gap: gap,
  );
}

int _readInt(Object? value, int fallback) =>
    value is num ? value.round() : fallback;
