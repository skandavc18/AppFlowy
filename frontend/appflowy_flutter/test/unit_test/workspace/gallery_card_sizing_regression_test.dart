import 'dart:math' as math;

import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  for (final compact in [false, true]) {
    for (final paneWidth in [360.0, 680.0, 1280.0, 1697.0]) {
      test('target-sized gallery: compact=$compact, pane=$paneWidth', () {
        final padding = compact
            ? 18.0
            : KnowledgeGalleryLayout.horizontalPadding(paneWidth);
        final available = paneWidth - padding * 2;
        final scale = compact ? 0.74 : 1.0;
        final spacing = compact ? 16.0 : KnowledgeGalleryLayout.cardSpacing;
        final widths = <double>[];

        for (final size in GalleryCardSize.values) {
          final target = size.targetWidth * scale;
          final metrics = GalleryCardMetrics.resolve(
            available: available,
            size: size,
            spacing: spacing,
            scale: scale,
            maximumColumns: null,
            fillRow: false,
          );
          widths.add(metrics.width);
          expect(metrics.width, closeTo(math.min(target, available), 0.001));
          expect(
            metrics.columns,
            math.max(1, ((available + spacing) / (target + spacing)).floor()),
          );
          expect(metrics.height, (metrics.width * 1.18).clamp(208, 404));
          expect(metrics.spacing, spacing);
          expect(metrics.gridWidth, lessThanOrEqualTo(available + 0.001));
          expect(available - metrics.gridWidth, greaterThanOrEqualTo(-0.001));
          expect(available - metrics.gridWidth, lessThan(target + spacing));
        }

        // Pin physical widths, not just counts: two choices can legitimately
        // have the same count but must not become the same sized cards.
        expect(widths[1] - widths[0], greaterThan(24));
        expect(widths[2] - widths[1], greaterThan(24));
      });
    }
  }

  test('a column limit never stretches target-sized cards into one bucket', () {
    for (final limit in [1, 4, 5]) {
      for (final size in GalleryCardSize.values) {
        final metrics = GalleryCardMetrics.resolve(
          available: 1625,
          size: size,
          spacing: 30,
          maximumColumns: limit,
          fillRow: false,
        );
        expect(metrics.columns, lessThanOrEqualTo(limit));
        expect(metrics.width, size.targetWidth);
        expect(metrics.gridWidth, lessThanOrEqualTo(1625));
      }
    }
  });

  test('narrow panes constrain geometry, not the requested size or captions',
      () {
    for (final available in [120.0, 168.0, 240.0, 288.0, 644.0]) {
      for (final size in GalleryCardSize.values) {
        final normal = GalleryCardMetrics.resolve(
          available: available,
          size: size,
          spacing: 16,
          maximumColumns: null,
          fillRow: false,
        );
        final scaled = GalleryCardMetrics.resolve(
          available: available,
          size: size,
          spacing: 16,
          maximumColumns: null,
          fillRow: false,
          textScale: 2,
        );
        expect(normal.width, inInclusiveRange(0.0, available));
        expect(normal.height, greaterThanOrEqualTo(208));
        expect(scaled.columns, normal.columns);
        expect(scaled.width, normal.width);
        expect(scaled.gridWidth, normal.gridWidth);
        expect(scaled.height, greaterThan(normal.height));
        expect(GalleryCardSize.fromName(size.name), size);
      }
    }
  });
}
