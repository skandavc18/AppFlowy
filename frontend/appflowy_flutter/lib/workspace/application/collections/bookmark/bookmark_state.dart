import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:flutter/foundation.dart';

/// The order a library is read in.
enum BookmarkSort {
  recentlyAdded,
  oldestFirst,
  published,
  title,
  site,
  unreadFirst;

  static BookmarkSort fromValue(Object? value) {
    for (final sort in BookmarkSort.values) {
      if (sort.name == value) {
        return sort;
      }
    }
    return BookmarkSort.recentlyAdded;
  }
}

/// How a shelf or a feed divides its rows.
enum BookmarkGrouping {
  none,
  site,
  tag,
  month,
  readState;

  static BookmarkGrouping fromValue(Object? value) {
    for (final grouping in BookmarkGrouping.values) {
      if (grouping.name == value) {
        return grouping;
      }
    }
    return BookmarkGrouping.site;
  }
}

/// Which saved links are shown at all.
enum BookmarkFilter {
  all,
  unread,
  starred,
  offline,
  untagged;

  static BookmarkFilter fromValue(Object? value) {
    for (final filter in BookmarkFilter.values) {
      if (filter.name == value) {
        return filter;
      }
    }
    return BookmarkFilter.all;
  }
}

/// How big the cards are drawn.
enum BookmarkDensity {
  compact,
  cosy,
  roomy;

  static BookmarkDensity fromValue(Object? value) {
    for (final density in BookmarkDensity.values) {
      if (density.name == value) {
        return density;
      }
    }
    return BookmarkDensity.cosy;
  }

  double get cardWidth => switch (this) {
        BookmarkDensity.compact => 232,
        BookmarkDensity.cosy => 292,
        BookmarkDensity.roomy => 360,
      };
}

/// The choices a library remembers.
@immutable
class BookmarkSettings {
  const BookmarkSettings({
    this.sort = BookmarkSort.recentlyAdded,
    this.grouping = BookmarkGrouping.site,
    this.filter = BookmarkFilter.all,
    this.density = BookmarkDensity.cosy,
    this.showDescriptions = true,
    this.autoSnapshot = false,
  });

  final BookmarkSort sort;
  final BookmarkGrouping grouping;
  final BookmarkFilter filter;
  final BookmarkDensity density;
  final bool showDescriptions;

  /// Whether saving a link also keeps an offline copy of it.
  final bool autoSnapshot;

  BookmarkSettings copyWith({
    BookmarkSort? sort,
    BookmarkGrouping? grouping,
    BookmarkFilter? filter,
    BookmarkDensity? density,
    bool? showDescriptions,
    bool? autoSnapshot,
  }) =>
      BookmarkSettings(
        sort: sort ?? this.sort,
        grouping: grouping ?? this.grouping,
        filter: filter ?? this.filter,
        density: density ?? this.density,
        showDescriptions: showDescriptions ?? this.showDescriptions,
        autoSnapshot: autoSnapshot ?? this.autoSnapshot,
      );

  Map<String, Object?> toJson() => {
        'sort': sort.name,
        'grouping': grouping.name,
        'filter': filter.name,
        'density': density.name,
        'show_descriptions': showDescriptions,
        'auto_snapshot': autoSnapshot,
      };

  static BookmarkSettings fromJson(Map<String, dynamic> json) =>
      BookmarkSettings(
        sort: BookmarkSort.fromValue(json['sort']),
        grouping: BookmarkGrouping.fromValue(json['grouping']),
        filter: BookmarkFilter.fromValue(json['filter']),
        density: BookmarkDensity.fromValue(json['density']),
        showDescriptions: json['show_descriptions'] != false,
        autoSnapshot: json['auto_snapshot'] == true,
      );
}

/// Everything a bookmark library remembers between visits.
@immutable
class BookmarkState {
  const BookmarkState({
    this.settings = const BookmarkSettings(),
    this.activeTags = const <String>{},
    this.activeSite,
    this.activeId,
  });

  final BookmarkSettings settings;

  /// The tags currently narrowing the library. Empty means everything.
  final Set<String> activeTags;

  final String? activeSite;

  /// The bookmark the reader was last on.
  final String? activeId;

  BookmarkState copyWith({
    BookmarkSettings? settings,
    Set<String>? activeTags,
    String? activeSite,
    String? activeId,
    bool clearSite = false,
    bool clearActive = false,
  }) =>
      BookmarkState(
        settings: settings ?? this.settings,
        activeTags: activeTags ?? this.activeTags,
        activeSite: clearSite ? null : activeSite ?? this.activeSite,
        activeId: clearActive ? null : activeId ?? this.activeId,
      );

  BookmarkState toggleTag(String tag) {
    final next = Set<String>.from(activeTags);
    if (!next.remove(tag)) {
      next.add(tag);
    }
    return copyWith(activeTags: next);
  }

  Map<String, Object?> toJson() => {
        'settings': settings.toJson(),
        if (activeTags.isNotEmpty) 'tags': activeTags.toList()..sort(),
        if (activeSite != null) 'site': activeSite,
        if (activeId != null) 'active': activeId,
      };

  static BookmarkState fromJson(Map<String, dynamic> json) {
    final settings = json['settings'];
    final tags = json['tags'];
    return BookmarkState(
      settings: settings is Map
          ? BookmarkSettings.fromJson(Map<String, dynamic>.from(settings))
          : const BookmarkSettings(),
      activeTags: tags is List
          ? {
              for (final tag in tags)
                if (normalizeBookmarkTag(tag is String ? tag : '')
                    case final String value)
                  value,
            }
          : const <String>{},
      activeSite: json['site'] is String ? json['site'] as String : null,
      activeId: json['active'] is String ? json['active'] as String : null,
    );
  }
}

/// How many bookmarks a site or a tag accounts for.
@immutable
class BookmarkFacet {
  const BookmarkFacet({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;
}

/// The counts a library shows about itself.
@immutable
class BookmarkStats {
  const BookmarkStats({
    required this.total,
    required this.unread,
    required this.starred,
    required this.offline,
    required this.sites,
    required this.tags,
  });

  static const empty = BookmarkStats(
    total: 0,
    unread: 0,
    starred: 0,
    offline: 0,
    sites: [],
    tags: [],
  );

  final int total;
  final int unread;
  final int starred;
  final int offline;

  /// Sites and tags, most used first.
  final List<BookmarkFacet> sites;
  final List<BookmarkFacet> tags;
}

/// A run of bookmarks under one heading.
@immutable
class BookmarkGroup {
  const BookmarkGroup({required this.label, required this.entries});

  final String label;
  final List<BookmarkEntry> entries;
}
