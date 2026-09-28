import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import 'database_find_navigation.dart';

/// Seek a variable-height, lazy grid WITHOUT replacing its scroll controller
/// or row delegate. Estimates are only materialization hints: the caller must
/// subsequently reveal and verify the actual cell's native range boxes.
Future<String?> materializeDatabaseFindGridRow({
  required DatabaseFindRequest request,
  required ScrollController vertical,
  required List<String> Function() rowIds,
  Future<void> Function(int index)? loadThrough,
}) async {
  final rowId = request.target.rowId;
  if (rowId == null) return null; // Column headings are already materialized.
  final target = DatabaseFindTarget.row(request.target.viewId, rowId);
  final index = rowIds().indexOf(rowId);
  if (index < 0) return 'The row is no longer in this filtered view.';
  if (!request.isCurrent) return null;
  await loadThrough?.call(index);
  if (!request.isCurrent) return null;

  double? lower;
  double? upper;
  double? lastPixels;
  int? lastFirst;
  int? lastLast;
  var stalled = 0;
  for (var attempt = 0; attempt < 64 && request.isCurrent; attempt++) {
    if (request.controller.materializedAnchors(target).isNotEmpty) return null;
    if (!vertical.hasClients || vertical.positions.length != 1) {
      if (!await request.nextFrame()) return null;
      continue;
    }
    final position = vertical.position;
    if (!position.hasContentDimensions) {
      if (!await request.nextFrame()) return null;
      continue;
    }
    final ids = rowIds();
    final liveIndex = ids.indexOf(rowId);
    if (liveIndex < 0) return 'The row is no longer in this filtered view.';
    final indices = {for (var i = 0; i < ids.length; i++) ids[i]: i};
    final materialized = <(int, RenderDatabaseFindAnchor, double)>[];
    // A variable-height SliverList can overshoot its measured end while new
    // row blocs still display their short placeholders. Flutter retains the
    // last laid-out child with zero sliver paintExtent in that case. It is a
    // valid seek sample, not a visible match; discarding it would leave this
    // loop waiting for paint that only another scroll can produce.
    for (final anchor in request.controller.materializedRows) {
      final at = indices[anchor.target.rowId];
      final viewport = RenderAbstractViewport.maybeOf(anchor);
      if (at == null ||
          viewport is! RenderViewportBase ||
          viewport.axis != Axis.vertical ||
          !identical(viewport.offset, position)) {
        continue;
      }
      final offset = viewport.getOffsetToReveal(anchor, 0).offset;
      if (offset.isFinite && anchor.size.height > 0) {
        materialized.add((at, anchor, offset));
      }
    }
    if (materialized.isEmpty) {
      if (!await request.nextFrame()) return null;
      continue;
    }
    materialized.sort((a, b) => a.$1.compareTo(b.$1));
    final first = materialized.first.$1;
    final last = materialized.last.$1;
    final pixels = position.pixels;
    if (pixels == lastPixels && first == lastFirst && last == lastLast) {
      if (++stalled >= 3) break;
    } else {
      stalled = 0;
    }
    lastPixels = pixels;
    lastFirst = first;
    lastLast = last;
    if (last < liveIndex) lower = pixels;
    if (first > liveIndex) upper = pixels;
    final nearest = materialized.reduce(
      (a, b) => (a.$1 - liveIndex).abs() < (b.$1 - liveIndex).abs() ? a : b,
    );
    final mean =
        materialized.fold<double>(0, (sum, row) => sum + row.$2.size.height) /
            materialized.length;
    var next = nearest.$3 + (liveIndex - nearest.$1) * mean;
    if (lower != null && upper != null && lower < upper) {
      // Highly unequal wrapped rows can overshoot both ways. Bisect measured
      // brackets instead of repeating an inaccurate average indefinitely.
      next = (lower + upper) / 2;
    }
    if ((next - pixels).abs() < 1) {
      next = pixels +
          (liveIndex > last ? 1 : -1) *
              math.max(mean, position.viewportDimension * 0.8);
    }
    next = next
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
    if (!request.isCurrent) return null;
    position.jumpTo(next);
    if (!await request.nextFrame()) return null;
  }
  return request.isCurrent
      ? 'The lazy row could not be materialized within the navigation limit. No approximate location is reported as a match.'
      : null;
}
