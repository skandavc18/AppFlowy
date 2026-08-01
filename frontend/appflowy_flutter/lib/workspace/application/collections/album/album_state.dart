import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:flutter/foundation.dart';

/// How big the tiles in a wall of media are.
enum AlbumTileSize {
  small,
  medium,
  large;

  static AlbumTileSize fromValue(Object? value) {
    for (final size in AlbumTileSize.values) {
      if (size.name == value) {
        return size;
      }
    }
    return AlbumTileSize.medium;
  }

  double get targetWidth => switch (this) {
        AlbumTileSize.small => 148,
        AlbumTileSize.medium => 214,
        AlbumTileSize.large => 302,
      };
}

enum AlbumSort {
  newestFirst,
  oldestFirst,
  name,
  albumOrder;

  static AlbumSort fromValue(Object? value) {
    for (final sort in AlbumSort.values) {
      if (sort.name == value) {
        return sort;
      }
    }
    return AlbumSort.newestFirst;
  }
}

enum AlbumGrouping {
  none,
  day,
  month,
  year;

  static AlbumGrouping fromValue(Object? value) {
    for (final grouping in AlbumGrouping.values) {
      if (grouping.name == value) {
        return grouping;
      }
    }
    return AlbumGrouping.month;
  }
}

enum AlbumSlideshowTransition {
  none,
  fade,
  slide,
  zoom;

  static AlbumSlideshowTransition fromValue(Object? value) {
    for (final transition in AlbumSlideshowTransition.values) {
      if (transition.name == value) {
        return transition;
      }
    }
    return AlbumSlideshowTransition.fade;
  }
}

@immutable
class AlbumSlideshowSettings {
  const AlbumSlideshowSettings({
    this.seconds = 5,
    this.transition = AlbumSlideshowTransition.fade,
    this.shuffle = false,
    this.loop = true,
  });

  static const minimumSeconds = 2;
  static const maximumSeconds = 30;

  final int seconds;
  final AlbumSlideshowTransition transition;
  final bool shuffle;
  final bool loop;

  Duration get interval => Duration(seconds: seconds);

  AlbumSlideshowSettings copyWith({
    int? seconds,
    AlbumSlideshowTransition? transition,
    bool? shuffle,
    bool? loop,
  }) =>
      AlbumSlideshowSettings(
        seconds: (seconds ?? this.seconds)
            .clamp(minimumSeconds, maximumSeconds)
            .toInt(),
        transition: transition ?? this.transition,
        shuffle: shuffle ?? this.shuffle,
        loop: loop ?? this.loop,
      );

  Map<String, Object?> toJson() => {
        'seconds': seconds,
        'transition': transition.name,
        'shuffle': shuffle,
        'loop': loop,
      };

  static AlbumSlideshowSettings fromJson(Object? value) {
    if (value is! Map) {
      return const AlbumSlideshowSettings();
    }
    final values = Map<String, dynamic>.from(value);
    return const AlbumSlideshowSettings().copyWith(
      seconds: values['seconds'] is num ? (values['seconds'] as num).toInt() : 5,
      transition: AlbumSlideshowTransition.fromValue(values['transition']),
      shuffle: values['shuffle'] == true,
      loop: values['loop'] != false,
    );
  }
}

@immutable
class AlbumSettings {
  const AlbumSettings({
    this.tileSize = AlbumTileSize.medium,
    this.sort = AlbumSort.newestFirst,
    this.grouping = AlbumGrouping.month,
    this.showNames = false,
    this.slideshow = const AlbumSlideshowSettings(),
  });

  final AlbumTileSize tileSize;
  final AlbumSort sort;

  /// Only the timeline groups; the other views read this for their headings.
  final AlbumGrouping grouping;
  final bool showNames;
  final AlbumSlideshowSettings slideshow;

  AlbumSettings copyWith({
    AlbumTileSize? tileSize,
    AlbumSort? sort,
    AlbumGrouping? grouping,
    bool? showNames,
    AlbumSlideshowSettings? slideshow,
  }) =>
      AlbumSettings(
        tileSize: tileSize ?? this.tileSize,
        sort: sort ?? this.sort,
        grouping: grouping ?? this.grouping,
        showNames: showNames ?? this.showNames,
        slideshow: slideshow ?? this.slideshow,
      );

  Map<String, Object?> toJson() => {
        'tile_size': tileSize.name,
        'sort': sort.name,
        'grouping': grouping.name,
        'show_names': showNames,
        'slideshow': slideshow.toJson(),
      };

  static AlbumSettings fromJson(Object? value) {
    if (value is! Map) {
      return const AlbumSettings();
    }
    final values = Map<String, dynamic>.from(value);
    return AlbumSettings(
      tileSize: AlbumTileSize.fromValue(values['tile_size']),
      sort: AlbumSort.fromValue(values['sort']),
      grouping: AlbumGrouping.fromValue(values['grouping']),
      showNames: values['show_names'] == true,
      slideshow: AlbumSlideshowSettings.fromJson(values['slideshow']),
    );
  }
}

/// Everything an album remembers between visits.
@immutable
class AlbumState {
  const AlbumState({
    this.settings = const AlbumSettings(),
    this.favourites = const <String>{},
    this.selectedId,
  });

  final AlbumSettings settings;

  /// The pictures that were starred, by view id.
  final Set<String> favourites;

  /// The last picture that was looked at, so a view reopens where it was.
  final String? selectedId;

  bool isFavourite(String id) => favourites.contains(id);

  AlbumState copyWith({
    AlbumSettings? settings,
    Set<String>? favourites,
    String? selectedId,
  }) =>
      AlbumState(
        settings: settings ?? this.settings,
        favourites: favourites ?? this.favourites,
        selectedId: selectedId ?? this.selectedId,
      );

  AlbumState toggleFavourite(String id) {
    final next = Set<String>.from(favourites);
    if (!next.remove(id)) {
      next.add(id);
    }
    return copyWith(favourites: next);
  }

  /// Forgets stars and selections for media that is no longer in the album.
  AlbumState prunedTo(Iterable<String> ids) {
    final live = ids.toSet();
    final nextFavourites = favourites.intersection(live);
    final selectionSurvives = selectedId == null || live.contains(selectedId);
    if (nextFavourites.length == favourites.length && selectionSurvives) {
      return this;
    }
    return AlbumState(
      settings: settings,
      favourites: nextFavourites,
      selectedId: selectionSurvives ? selectedId : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'settings': settings.toJson(),
        if (favourites.isNotEmpty) 'favourites': favourites.toList(),
        if (selectedId != null) 'selected': selectedId,
      };

  static AlbumState fromJson(Map<String, dynamic> values) {
    final favourites = values['favourites'];
    return AlbumState(
      settings: AlbumSettings.fromJson(values['settings']),
      favourites: favourites is List
          ? {
              for (final value in favourites)
                if (value is String) value,
            }
          : const <String>{},
      selectedId:
          values['selected'] is String ? values['selected'] as String : null,
    );
  }
}

/// A run of media that shares a heading — a day, a month or a year.
@immutable
class AlbumGroup {
  const AlbumGroup({required this.key, required this.date, required this.items});

  final String key;

  /// `null` when nothing in the run carries a date.
  final DateTime? date;
  final List<AlbumMediaItem> items;
}

/// Splits [items] into headed runs. The order of [items] is respected, so the
/// caller sorts first and groups second.
List<AlbumGroup> groupAlbumMedia(
  List<AlbumMediaItem> items,
  AlbumGrouping grouping,
  DateTime? Function(AlbumMediaItem item) dateOf,
) {
  if (grouping == AlbumGrouping.none || items.isEmpty) {
    return [
      if (items.isNotEmpty)
        AlbumGroup(key: '', date: null, items: List.unmodifiable(items)),
    ];
  }

  final groups = <AlbumGroup>[];
  var currentKey = '';
  var currentDate = DateTime(0);
  var current = <AlbumMediaItem>[];

  void flush() {
    if (current.isNotEmpty) {
      groups.add(
        AlbumGroup(
          key: currentKey,
          date: currentKey == '' ? null : currentDate,
          items: List.unmodifiable(current),
        ),
      );
    }
  }

  for (final item in items) {
    final date = dateOf(item);
    final bucket = date == null ? DateTime(0) : _bucket(date, grouping);
    final key = date == null ? '' : bucket.toIso8601String();
    if (key != currentKey || groups.isEmpty && current.isEmpty) {
      if (current.isNotEmpty) {
        flush();
        current = <AlbumMediaItem>[];
      }
      currentKey = key;
      currentDate = bucket;
    }
    current.add(item);
  }
  flush();
  return groups;
}

DateTime _bucket(DateTime date, AlbumGrouping grouping) => switch (grouping) {
      AlbumGrouping.day => DateTime(date.year, date.month, date.day),
      AlbumGrouping.month => DateTime(date.year, date.month),
      AlbumGrouping.year => DateTime(date.year),
      AlbumGrouping.none => DateTime(0),
    };
