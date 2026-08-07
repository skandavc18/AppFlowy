import 'package:flutter/foundation.dart';

/// How much room a collection widget takes on the page.
///
/// The size is a *shape*, not a pixel count — every preview reads it and
/// decides what it can show at that shape, exactly as an iOS widget does.
enum CollectionEmbedSize {
  compact,
  medium,
  large;

  static CollectionEmbedSize fromValue(Object? value) => switch (value) {
        'compact' => CollectionEmbedSize.compact,
        'large' => CollectionEmbedSize.large,
        _ => CollectionEmbedSize.medium,
      };

  bool get isCompact => this == CollectionEmbedSize.compact;
  bool get isLarge => this == CollectionEmbedSize.large;
}

/// The order objects are offered in inside a widget.
enum CollectionEmbedSort {
  manual,
  name,
  newest,
  oldest;

  static CollectionEmbedSort fromValue(Object? value) => switch (value) {
        'name' => CollectionEmbedSort.name,
        'newest' => CollectionEmbedSort.newest,
        'oldest' => CollectionEmbedSort.oldest,
        _ => CollectionEmbedSort.manual,
      };
}

/// How the widget meets the page behind it.
///
/// [surface] is the default soft card; [flush] paints nothing at all so the
/// content continues the page (what a database wants); [tinted] washes the
/// collection type's own hue under the content.
enum CollectionEmbedBackground {
  surface,
  flush,
  tinted;

  static CollectionEmbedBackground fromValue(Object? value) => switch (value) {
        'flush' => CollectionEmbedBackground.flush,
        'tinted' => CollectionEmbedBackground.tinted,
        _ => CollectionEmbedBackground.surface,
      };
}

/// Everything a single embedded collection remembers about how it is shown.
///
/// Stored as one map on the block node, so a page carries its own layout and
/// two embeds of the same collection can look completely different.
@immutable
class CollectionEmbedSettings {
  const CollectionEmbedSettings({
    this.size = CollectionEmbedSize.medium,
    this.style,
    this.itemLimit,
    this.sort = CollectionEmbedSort.manual,
    this.showMetadata = true,
    this.background = CollectionEmbedBackground.surface,
    this.coverId,
    this.columns,
  });

  factory CollectionEmbedSettings.fromJson(Object? value) {
    if (value is! Map) {
      return const CollectionEmbedSettings();
    }
    final map = Map<String, dynamic>.from(value);
    final limit = map['items'];
    final columns = map['columns'];
    return CollectionEmbedSettings(
      size: CollectionEmbedSize.fromValue(map['size']),
      style: map['style'] is String && (map['style'] as String).isNotEmpty
          ? map['style'] as String
          : null,
      itemLimit: limit is num ? limit.round().clamp(1, 60) : null,
      sort: CollectionEmbedSort.fromValue(map['sort']),
      showMetadata: map['meta'] is bool ? map['meta'] as bool : true,
      background: CollectionEmbedBackground.fromValue(map['background']),
      coverId: map['cover'] is String && (map['cover'] as String).isNotEmpty
          ? map['cover'] as String
          : null,
      columns: columns is num ? columns.round().clamp(1, 8) : null,
    );
  }

  final CollectionEmbedSize size;

  /// The preview style id, which is specific to the collection type. `null`
  /// means "whatever this type calls its default", so a type can change its
  /// default without rewriting stored pages.
  final String? style;

  /// How many objects the preview offers. `null` defers to the style.
  final int? itemLimit;
  final CollectionEmbedSort sort;
  final bool showMetadata;
  final CollectionEmbedBackground background;

  /// The object whose artwork represents the collection (a book cover, an
  /// album cover). `null` means the first one that has artwork.
  final String? coverId;

  /// Books per shelf row, photos per grid row… `null` defers to the width.
  final int? columns;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'size': size.name,
        if (style != null) 'style': style,
        if (itemLimit != null) 'items': itemLimit,
        if (sort != CollectionEmbedSort.manual) 'sort': sort.name,
        if (!showMetadata) 'meta': false,
        if (background != CollectionEmbedBackground.surface)
          'background': background.name,
        if (coverId != null) 'cover': coverId,
        if (columns != null) 'columns': columns,
      };

  CollectionEmbedSettings copyWith({
    CollectionEmbedSize? size,
    String? style,
    int? itemLimit,
    CollectionEmbedSort? sort,
    bool? showMetadata,
    CollectionEmbedBackground? background,
    String? coverId,
    int? columns,
    bool clearItemLimit = false,
    bool clearCover = false,
    bool clearColumns = false,
  }) =>
      CollectionEmbedSettings(
        size: size ?? this.size,
        style: style ?? this.style,
        itemLimit: clearItemLimit ? null : itemLimit ?? this.itemLimit,
        sort: sort ?? this.sort,
        showMetadata: showMetadata ?? this.showMetadata,
        background: background ?? this.background,
        coverId: clearCover ? null : coverId ?? this.coverId,
        columns: clearColumns ? null : columns ?? this.columns,
      );

  @override
  bool operator ==(Object other) =>
      other is CollectionEmbedSettings &&
      other.size == size &&
      other.style == style &&
      other.itemLimit == itemLimit &&
      other.sort == sort &&
      other.showMetadata == showMetadata &&
      other.background == background &&
      other.coverId == coverId &&
      other.columns == columns;

  @override
  int get hashCode => Object.hash(
        size,
        style,
        itemLimit,
        sort,
        showMetadata,
        background,
        coverId,
        columns,
      );
}
