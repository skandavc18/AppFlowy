import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:flutter/foundation.dart';

/// How large the cards on the wall are set.
enum GalleryCardScale {
  small('small', 208),
  medium('medium', 272),
  large('large', 348);

  const GalleryCardScale(this.id, this.target);

  final String id;

  /// The width a card aims for. It is a target, never a floor: the wall shares
  /// out whatever is left so the columns come out even.
  final double target;

  static GalleryCardScale fromId(String? id) {
    for (final scale in GalleryCardScale.values) {
      if (scale.id == id) {
        return scale;
      }
    }
    return GalleryCardScale.medium;
  }
}

/// How much of a row a card shows.
enum GalleryCardFace {
  /// The row's cover leads, with its properties beneath.
  cover('picture'),

  /// A few lines of the row's own page stand in for a cover.
  content('content'),

  /// No cover at all: the title and the properties, and nothing else.
  none('writing'),

  /// The cover fills the card with the title laid over it.
  portrait('portrait');

  const GalleryCardFace(this.id);

  final String id;

  /// Whether the card carries any cover at all.
  bool get showsCover =>
      this == GalleryCardFace.cover || this == GalleryCardFace.portrait;

  static GalleryCardFace fromId(String? id) {
    for (final face in GalleryCardFace.values) {
      if (face.id == id) {
        return face;
      }
    }
    return GalleryCardFace.cover;
  }
}

/// How a table is hung on a wall.
@immutable
class GallerySpec {
  const GallerySpec({
    this.titleColumn = '',
    this.coverColumn = '',
    this.propertyColumns = const [],
    this.hiddenColumns = const [],
    this.scale = GalleryCardScale.medium,
    this.face = GalleryCardFace.cover,
    this.showCoverPlaceholder = true,
  });

  final String titleColumn;
  final String coverColumn;
  final List<String> propertyColumns;
  final List<String> hiddenColumns;
  final GalleryCardScale scale;
  final GalleryCardFace face;

  /// Whether a row with no picture still gets a band of colour, so the wall
  /// stays a wall rather than becoming a ragged list.
  final bool showCoverPlaceholder;

  GallerySpec copyWith({
    String? titleColumn,
    String? coverColumn,
    List<String>? propertyColumns,
    List<String>? hiddenColumns,
    GalleryCardScale? scale,
    GalleryCardFace? face,
    bool? showCoverPlaceholder,
  }) =>
      GallerySpec(
        titleColumn: titleColumn ?? this.titleColumn,
        coverColumn: coverColumn ?? this.coverColumn,
        propertyColumns: propertyColumns ?? this.propertyColumns,
        hiddenColumns: hiddenColumns ?? this.hiddenColumns,
        scale: scale ?? this.scale,
        face: face ?? this.face,
        showCoverPlaceholder: showCoverPlaceholder ?? this.showCoverPlaceholder,
      );

  TableReadSpec get readSpec => TableReadSpec(
        titleColumn: titleColumn,
        coverColumn: coverColumn,
        propertyColumns: propertyColumns,
        hiddenColumns: hiddenColumns,
      );

  Map<String, dynamic> toJson() => {
        if (titleColumn.isNotEmpty) 'title': titleColumn,
        if (coverColumn.isNotEmpty) 'cover': coverColumn,
        if (propertyColumns.isNotEmpty) 'properties': propertyColumns,
        if (hiddenColumns.isNotEmpty) 'hidden': hiddenColumns,
        if (scale != GalleryCardScale.medium) 'scale': scale.id,
        if (face != GalleryCardFace.cover) 'face': face.id,
        if (!showCoverPlaceholder) 'placeholder': false,
      };

  static GallerySpec fromJson(Map<String, dynamic> values) => GallerySpec(
        titleColumn: values['title'] as String? ?? '',
        coverColumn: values['cover'] as String? ?? '',
        propertyColumns: _strings(values['properties']),
        hiddenColumns: _strings(values['hidden']),
        scale: GalleryCardScale.fromId(values['scale'] as String?),
        face: GalleryCardFace.fromId(values['face'] as String?),
        showCoverPlaceholder: values['placeholder'] != false,
      );

  static List<String> _strings(Object? value) => value is List
      ? List.unmodifiable(value.whereType<String>())
      : const <String>[];

  @override
  bool operator ==(Object other) =>
      other is GallerySpec &&
      other.titleColumn == titleColumn &&
      other.coverColumn == coverColumn &&
      listEquals(other.propertyColumns, propertyColumns) &&
      listEquals(other.hiddenColumns, hiddenColumns) &&
      other.scale == scale &&
      other.face == face &&
      other.showCoverPlaceholder == showCoverPlaceholder;

  @override
  int get hashCode => Object.hash(
        titleColumn,
        coverColumn,
        Object.hashAll(propertyColumns),
        Object.hashAll(hiddenColumns),
        scale,
        face,
        showCoverPlaceholder,
      );
}

/// How a wall of cards is shared out across the width it has.
@immutable
class GalleryLayout {
  const GalleryLayout({required this.columns, required this.cardWidth});

  final int columns;
  final double cardWidth;

  /// A card is a little taller than it is wide, which is the shape a cover and
  /// a couple of lines of writing want.
  double get cardHeight => (cardWidth * 1.16).clamp(210.0, 420.0).toDouble();

  /// How much of the card the cover takes. It has to shrink with the card, or
  /// a small card is all picture and its writing is cut off.
  double get coverHeight => (cardHeight * 0.44).clamp(84.0, 190.0).toDouble();
}

/// Works out how many cards fit, and how wide each is.
///
/// ⚠️ Rounding rather than flooring matters: a row that fits 2.97 cards would
/// otherwise become two cards sharing all the slack, which is a 50% overshoot
/// and reads as "the cards are enormous".
GalleryLayout galleryLayoutFor({
  required double available,
  required double target,
  double spacing = 18,
  int maximumColumns = 6,
  double maximumStretch = 1.25,
}) {
  if (available <= 0) {
    return GalleryLayout(columns: 1, cardWidth: target);
  }
  var columns = ((available + spacing) / (target + spacing)).round();
  columns = columns.clamp(1, maximumColumns);

  double widthFor(int count) => (available - spacing * (count - 1)) / count;

  // A card that would still outgrow its target after rounding gets another
  // column rather than being blown up.
  while (
      columns < maximumColumns && widthFor(columns) > target * maximumStretch) {
    columns++;
  }
  return GalleryLayout(
    columns: columns,
    cardWidth: widthFor(columns).clamp(120.0, 640.0).toDouble(),
  );
}
