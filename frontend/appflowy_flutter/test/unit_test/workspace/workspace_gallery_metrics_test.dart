import 'package:appflowy/plugins/database/board/presentation/board_style.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('board and table cards use the shared grounded card geometry', () {
    expect(WorkspaceTokens.cardRadius, 20);
    expect(BoardMetrics.cardRadius, WorkspaceTokens.cardRadius);
    expect(TableViewMetrics.cardRadius, WorkspaceTokens.cardRadius);
    expect(BoardMetrics.cardLift, 0);
    expect(BoardMetrics.cardGrowth, 1);
    expect(TableViewMetrics.hoverLift, 0);
    expect(BoardMetrics.hover, WorkspaceTokens.hoverDuration);
    expect(TableViewMetrics.hover, WorkspaceTokens.hoverDuration);
  });

  test('all saved folder and table sizes still determine the column count', () {
    final folderColumns = [
      for (final size in GalleryCardSize.values)
        GalleryCardMetrics.resolve(
          available: 1200,
          size: size,
          spacing: 30,
        ).columns,
    ];
    final tableColumns = [
      for (final scale in GalleryCardScale.values)
        galleryLayoutFor(available: 1200, target: scale.target).columns,
    ];
    expect(folderColumns[0], greaterThan(folderColumns[1]));
    expect(folderColumns[1], greaterThan(folderColumns[2]));
    expect(tableColumns[0], greaterThan(tableColumns[1]));
    expect(tableColumns[1], greaterThan(tableColumns[2]));
    expect(folderColumns.first, greaterThan(2));
    expect(tableColumns.first, greaterThan(2));
    for (final size in GalleryCardSize.values) {
      expect(GalleryCardSize.fromName(size.name), size);
    }
    for (final scale in GalleryCardScale.values) {
      for (final face in GalleryCardFace.values) {
        final spec = GallerySpec(scale: scale, face: face);
        expect(GallerySpec.fromJson(spec.toJson()), spec);
      }
    }
  });

  test('large text grows the caption without changing the chosen card width',
      () {
    for (final available in [168.0, 520.0, 960.0, 1440.0]) {
      for (final size in GalleryCardSize.values) {
        final normal = GalleryCardMetrics.resolve(
          available: available,
          size: size,
          spacing: 18,
        );
        for (final textScale in [1.0, 1.5, 2.0, 3.0]) {
          final scaled = GalleryCardMetrics.resolve(
            available: available,
            size: size,
            spacing: 18,
            textScale: textScale,
          );
          expect(scaled.columns, normal.columns);
          expect(scaled.width, normal.width);
          expect(scaled.spacing, normal.spacing);
          expect(
            scaled.height,
            closeTo(
              normal.height +
                  (textScale - 1) * TableViewMetrics.cardCaptionAllowance,
              0.001,
            ),
          );
          expect(scaled.width, greaterThan(0));
          expect(
            scaled.width * scaled.columns +
                scaled.spacing * (scaled.columns - 1),
            closeTo(available, 0.001),
          );
        }
      }
    }
  });

  test('captions stay readable and subordinate at every card size', () {
    for (final width in [0.0, 120.0, 168.0, 196.0, 300.0, 900.0]) {
      final density = GalleryCardDensity.forWidth(width);
      expect(density.titleSize, inInclusiveRange(14, 15));
      expect(density.metadataSize, inInclusiveRange(11, 12));
      expect(density.titleSize, greaterThan(density.metadataSize));
      expect(density.typeLabelSize, density.metadataSize);
      expect(density.tagSize, density.metadataSize);
      expect(density.footerPadding.left, inInclusiveRange(12, 16));
      expect(density.footerPadding.right, density.footerPadding.left);
      expect(density.titleGap, lessThanOrEqualTo(WorkspaceTokens.space2));
    }
  });

  test('unknown constraints and invalid scale cannot create a NaN card', () {
    for (final width in [0.0, double.infinity, double.nan]) {
      for (final textScale in [1.0, 2.0, double.infinity, double.nan]) {
        final metrics = GalleryCardMetrics.resolve(
          available: width,
          size: GalleryCardSize.medium,
          spacing: 18,
          textScale: textScale,
        );
        expect(metrics.columns, 1);
        expect(metrics.width, GalleryCardSize.medium.targetWidth);
        expect(metrics.height.isFinite, isTrue);
        expect(metrics.height, greaterThan(0));
      }
    }
  });
}
