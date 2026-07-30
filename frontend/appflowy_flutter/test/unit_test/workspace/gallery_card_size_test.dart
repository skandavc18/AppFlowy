import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('GalleryCardMetrics', () {
    test('divides the row into whole cards of about the chosen size', () {
      final metrics = GalleryCardMetrics.resolve(
        available: 1200,
        size: GalleryCardSize.medium,
        spacing: 30,
      );

      expect(metrics.columns, 4);
      expect(metrics.width, closeTo((1200 - 30 * 3) / 4, 0.01));
    });

    test('gives more, smaller cards as the size steps down', () {
      int columnsFor(GalleryCardSize size) => GalleryCardMetrics.resolve(
            available: 1200,
            size: size,
            spacing: 30,
          ).columns;

      expect(
        columnsFor(GalleryCardSize.small),
        greaterThan(columnsFor(GalleryCardSize.medium)),
      );
      expect(
        columnsFor(GalleryCardSize.large),
        lessThan(columnsFor(GalleryCardSize.medium)),
      );
    });

    test('keeps the card shape as the space changes', () {
      final wide = GalleryCardMetrics.resolve(
        available: 1400,
        size: GalleryCardSize.medium,
        spacing: 30,
      );
      final narrow = GalleryCardMetrics.resolve(
        available: 700,
        size: GalleryCardSize.medium,
        spacing: 16,
        scale: 0.74,
      );

      for (final metrics in [wide, narrow]) {
        expect(metrics.height / metrics.width, closeTo(1.18, 0.02));
      }
      // An embed asks for a smaller target, so its cards stay moderate.
      expect(narrow.width, lessThan(wide.width));
    });

    test('keeps a title-sized floor under very narrow cards', () {
      final metrics = GalleryCardMetrics.resolve(
        available: 520,
        size: GalleryCardSize.medium,
        spacing: 16,
        scale: 0.74,
      );

      expect(metrics.width, lessThan(176));
      expect(metrics.height, 208);
    });

    test('never draws a card taller than the clamp allows', () {
      final metrics = GalleryCardMetrics.resolve(
        available: 380,
        size: GalleryCardSize.large,
        spacing: 30,
        maximumHeight: 300,
      );

      expect(metrics.columns, 1);
      expect(metrics.height, 300);
    });

    test('adds a column rather than letting cards swallow the slack', () {
      // The width of a zip embed: the row fits 2.97 cards, and rounding down
      // used to hand each of the two survivors half the leftover space.
      final metrics = GalleryCardMetrics.resolve(
        available: 608,
        size: GalleryCardSize.medium,
        spacing: 16,
        scale: 0.74,
        maximumColumns: 4,
      );

      expect(metrics.columns, 3);
      expect(metrics.width, lessThan(GalleryCardSize.medium.targetWidth));
    });

    test('holds every card within reach of the size that was asked for', () {
      for (var available = 240.0; available <= 1680; available += 7) {
        for (final size in GalleryCardSize.values) {
          for (final scale in [1.0, 0.74]) {
            final metrics = GalleryCardMetrics.resolve(
              available: available,
              size: size,
              spacing: 16,
              scale: scale,
            );
            final target = size.targetWidth * scale;
            final stretched = metrics.width > target * 1.25;
            expect(
              stretched && metrics.columns < 5,
              isFalse,
              reason: 'width ${metrics.width} over target $target '
                  'in $available across ${metrics.columns}',
            );
          }
        }
      }
    });

    test('falls back to one card when the width is unknown', () {
      final metrics = GalleryCardMetrics.resolve(
        available: double.infinity,
        size: GalleryCardSize.medium,
        spacing: 30,
      );

      expect(metrics.columns, 1);
      expect(metrics.width, GalleryCardSize.medium.targetWidth);
    });
  });

  group('GalleryCardSize', () {
    test('reads back the stored name and defaults to medium', () {
      for (final size in GalleryCardSize.values) {
        expect(GalleryCardSize.fromName(size.name), size);
      }
      expect(GalleryCardSize.fromName(null), GalleryCardSize.medium);
      expect(GalleryCardSize.fromName('enormous'), GalleryCardSize.medium);
    });
  });

  group('GalleryCardDensity', () {
    test('captions a full size card exactly as it was designed', () {
      final density = GalleryCardDensity.forWidth(
        GalleryCardDensity.referenceWidth,
      );

      expect(density.titleSize, 17);
      expect(density.footerPadding, const EdgeInsets.fromLTRB(21, 19, 21, 20));
    });

    test('shrinks the file name to suit a narrow card', () {
      final embed = GalleryCardDensity.forWidth(192);
      final full = GalleryCardDensity.forWidth(312);

      expect(embed.titleSize, lessThan(full.titleSize));
      expect(embed.footerPadding.left, lessThan(full.footerPadding.left));
    });

    test('never sets the file name below a legible floor', () {
      for (final width in [0.0, 60.0, 120.0, 150.0]) {
        expect(GalleryCardDensity.forWidth(width).titleSize, 13);
      }
    });

    test('never grows the type past its design size', () {
      for (final width in [300.0, 480.0, 900.0, double.infinity]) {
        final density = GalleryCardDensity.forWidth(width);
        expect(density.titleSize, 17);
        expect(density.metadataSize, 10);
      }
    });

    test('keeps the file name larger than the line beneath it', () {
      for (var width = 120.0; width <= 420; width += 6) {
        final density = GalleryCardDensity.forWidth(width);
        expect(density.titleSize, greaterThan(density.metadataSize));
      }
    });
  });
}
