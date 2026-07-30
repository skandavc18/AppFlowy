import 'package:flutter/material.dart';

/// How large the cards of a gallery are drawn.
enum GalleryCardSize {
  small,
  medium,
  large;

  static GalleryCardSize fromName(String? value) => values.firstWhere(
        (size) => size.name == value,
        orElse: () => GalleryCardSize.medium,
      );

  String get label => switch (this) {
        GalleryCardSize.small => 'Small cards',
        GalleryCardSize.medium => 'Medium cards',
        GalleryCardSize.large => 'Large cards',
      };

  IconData get icon => switch (this) {
        GalleryCardSize.small => Icons.grid_on_rounded,
        GalleryCardSize.medium => Icons.grid_view_rounded,
        GalleryCardSize.large => Icons.crop_square_rounded,
      };

  /// The width a card aims for before the row is shared out between columns.
  double get targetWidth => switch (this) {
        GalleryCardSize.small => 196,
        GalleryCardSize.medium => 262,
        GalleryCardSize.large => 336,
      };
}

/// The measurements one row of gallery cards is laid out with.
@immutable
class GalleryCardMetrics {
  const GalleryCardMetrics({
    required this.columns,
    required this.width,
    required this.height,
    required this.spacing,
  });

  /// Divides [available] into whole cards of roughly the requested size.
  ///
  /// The height follows the width rather than being fixed, so a card keeps
  /// its shape whether it sits in a page embed or fills the window.
  factory GalleryCardMetrics.resolve({
    required double available,
    required GalleryCardSize size,
    required double spacing,
    double scale = 1,
    double aspectRatio = 1.18,
    double minimumHeight = 208,
    double maximumHeight = 404,
    double maximumStretch = 1.25,
    int maximumColumns = 5,
  }) {
    final target = size.targetWidth * scale;
    if (!available.isFinite || available <= 0) {
      return GalleryCardMetrics(
        columns: 1,
        width: target,
        height: target * aspectRatio,
        spacing: spacing,
      );
    }
    double widthFor(int columns) =>
        (available - spacing * (columns - 1)) / columns;

    // Round rather than floor: a row that fits 2.9 cards should hold 3 slightly
    // narrow ones, not 2 that each swallow half the leftover space.
    var columns = ((available + spacing) / (target + spacing)).round().clamp(
          1,
          maximumColumns,
        );
    // Cards share out whatever the last column leaves behind, but only so far.
    // Past this they no longer read as the size that was asked for.
    while (widthFor(columns) > target * maximumStretch &&
        columns < maximumColumns) {
      columns += 1;
    }
    final width = widthFor(columns);
    return GalleryCardMetrics(
      columns: columns,
      width: width,
      height: (width * aspectRatio).clamp(minimumHeight, maximumHeight),
      spacing: spacing,
    );
  }

  final int columns;
  final double width;
  final double height;
  final double spacing;
}

/// The type and spacing a card of a given width is captioned with.
///
/// The footer was drawn for a full-window card, so reusing those sizes on a
/// narrow embed card leaves the file name shouting over its own artwork. Every
/// value slides between a legible floor and the original design instead.
@immutable
class GalleryCardDensity {
  const GalleryCardDensity(this.t);

  factory GalleryCardDensity.forWidth(double width) => GalleryCardDensity(
        width.isFinite
            ? ((width - _floorWidth) / (referenceWidth - _floorWidth))
                .clamp(0.0, 1.0)
            : 1.0,
      );

  /// The card width the footer's type was designed against.
  static const double referenceWidth = 300;
  static const double _floorWidth = 150;

  /// 0 at the narrowest card, 1 once the card is full size.
  final double t;

  double _lerp(double min, double max) => min + (max - min) * t;

  double get titleSize => _lerp(13, 17);
  double get titleSpacing => _lerp(-0.2, -0.38);
  double get emojiSize => _lerp(14, 18);
  double get typeLabelSize => _lerp(8.6, 9.5);
  double get metadataSize => _lerp(9, 10);
  double get tagSize => _lerp(9.4, 10.5);
  double get titleGap => _lerp(9, 15);

  EdgeInsets get footerPadding => EdgeInsets.fromLTRB(
        _lerp(14, 21),
        _lerp(12, 19),
        _lerp(14, 21),
        _lerp(13, 20),
      );
}
