import 'dart:math' as math;

import 'package:appflowy/shared/workspace_tokens.dart';
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
  /// A contact sheet, not a smaller rich card: square artwork followed by two
  /// name lines. It deliberately does not read or overwrite the Gallery size.
  factory GalleryCardMetrics.thumbnails({
    required double available,
    double textScale = 1,
    bool compact = false,
  }) {
    final target = compact ? 128.0 : 148.0;
    final spacing = compact ? 12.0 : 16.0;
    final bounded = available.isFinite && available > 0 ? available : target;
    final columns =
        math.max(1, ((bounded + spacing) / (target + spacing)).floor());
    final width = math.min(target, bounded);
    final scale = textScale.isFinite ? math.max(1.0, textScale) : 1.0;
    return GalleryCardMetrics(
      columns: columns,
      width: width,
      height: width + 12 + 2 * (13 * 1.4 * scale).ceilToDouble(),
      spacing: spacing,
    );
  }
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
  /// With [fillRow] false, cards keep their requested width (unless the pane
  /// is narrower). The grid must then be constrained to [gridWidth]; otherwise
  /// a fixed-column sliver stretches them back into identical size buckets.
  /// A null [maximumColumns] lets the available width determine the count.
  factory GalleryCardMetrics.resolve({
    required double available,
    required GalleryCardSize size,
    required double spacing,
    double scale = 1,
    double aspectRatio = 1.18,
    double minimumHeight = 208,
    double maximumHeight = 404,
    double maximumStretch = 1.25,
    int? maximumColumns = 5,
    double textScale = 1,
    bool fillRow = true,
  }) {
    final target = size.targetWidth * scale;
    // Grow the caption allowance, not the column width or the user's saved
    // size. Two title lines, metadata and a search path must still fit at 2x.
    final captionGrowth = textScale.isFinite && textScale > 1
        ? (textScale - 1) * (WorkspaceTokens.space16 + WorkspaceTokens.space3)
        : 0.0;
    if (!available.isFinite || available <= 0) {
      return GalleryCardMetrics(
        columns: 1,
        width: target,
        height: target * aspectRatio + captionGrowth,
        spacing: spacing,
      );
    }
    double widthFor(int columns) =>
        (available - spacing * (columns - 1)) / columns;

    final idealColumns = (available + spacing) / (target + spacing);
    final columnLimit = maximumColumns ?? math.max(1, idealColumns.ceil());
    // Filling rows rounds to avoid oversized cards. Target-width rows floor
    // instead: the leftover space stays outside the grid, not inside a card.
    var columns = (fillRow ? idealColumns.round() : idealColumns.floor())
        .clamp(1, columnLimit);
    // Cards share out whatever the last column leaves behind, but only so far.
    // Past this they no longer read as the size that was asked for.
    while (fillRow &&
        widthFor(columns) > target * maximumStretch &&
        columns < columnLimit) {
      columns += 1;
    }
    final width = fillRow ? widthFor(columns) : math.min(target, available);
    return GalleryCardMetrics(
      columns: columns,
      width: width,
      height: (width * aspectRatio).clamp(minimumHeight, maximumHeight) +
          captionGrowth,
      spacing: spacing,
    );
  }

  final int columns;
  final double width;
  final double height;
  final double spacing;

  double get gridWidth => width * columns + spacing * (columns - 1);
}

/// The type and spacing a card of a given width is captioned with.
///
/// Keep the caption subordinate to the preview without turning small cards
/// into tiny file-manager rows. Geometry adapts; the face is inherited from
/// the workspace's shared typography.
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

  double get titleSize => _lerp(14, 15);
  double get titleSpacing => -0.2;
  double get emojiSize => _lerp(16, 18);
  double get typeLabelSize => metadataSize;
  double get metadataSize => _lerp(11, 12);
  double get tagSize => metadataSize;
  double get titleGap => _lerp(6, WorkspaceTokens.space2);

  EdgeInsets get footerPadding => EdgeInsets.all(
        _lerp(WorkspaceTokens.space3, WorkspaceTokens.space4),
      );
}
