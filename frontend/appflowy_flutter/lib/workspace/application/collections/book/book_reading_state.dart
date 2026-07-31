import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:flutter/foundation.dart';

/// The reading surface a book is set on.
enum BookReaderTheme {
  /// Follows the workspace, so a book looks like the rest of AppFlowy — and
  /// in paper mode inherits the stationery it already has.
  workspace,
  paper,
  sepia,
  light,
  dark,
  night;

  static BookReaderTheme fromValue(Object? value) {
    for (final theme in BookReaderTheme.values) {
      if (theme.name == value) {
        return theme;
      }
    }
    return BookReaderTheme.workspace;
  }

  /// Whether the theme names its own dark surface. [workspace] takes its
  /// brightness from the application instead.
  bool get isDark =>
      this == BookReaderTheme.dark || this == BookReaderTheme.night;
}

/// How the pages of a book are laid out and moved through.
enum BookReaderFlow {
  /// One long column per chapter; reaching the end carries on into the next.
  continuous,

  /// One chapter fills the view and is turned like a leaf.
  paged,

  /// Chapters sit side by side and are swiped through.
  horizontal;

  static BookReaderFlow fromValue(Object? value) {
    for (final flow in BookReaderFlow.values) {
      if (flow.name == value) {
        return flow;
      }
    }
    return BookReaderFlow.continuous;
  }

  bool get turnsPages => this != BookReaderFlow.continuous;
}

/// How wide the text column is allowed to grow.
enum BookReaderMeasure {
  narrow,
  comfortable,
  wide,
  full;

  static BookReaderMeasure fromValue(Object? value) {
    for (final measure in BookReaderMeasure.values) {
      if (measure.name == value) {
        return measure;
      }
    }
    return BookReaderMeasure.comfortable;
  }

  /// `null` means the chapter fills whatever room it is given.
  double? get maxWidth => switch (this) {
        BookReaderMeasure.narrow => 604,
        BookReaderMeasure.comfortable => 748,
        BookReaderMeasure.wide => 940,
        BookReaderMeasure.full => null,
      };
}

/// How one chapter gives way to the next.
enum BookPageTransition {
  none,
  fade,
  slide,
  curl;

  static BookPageTransition fromValue(Object? value) {
    for (final transition in BookPageTransition.values) {
      if (transition.name == value) {
        return transition;
      }
    }
    return BookPageTransition.fade;
  }
}

enum BookNoteColor {
  yellow,
  green,
  blue,
  pink,
  purple;

  static BookNoteColor fromValue(Object? value) {
    for (final color in BookNoteColor.values) {
      if (color.name == value) {
        return color;
      }
    }
    return BookNoteColor.yellow;
  }
}

@immutable
class BookReaderSettings {
  const BookReaderSettings({
    this.theme = BookReaderTheme.workspace,
    this.fontScale = 1,
    this.measure = BookReaderMeasure.comfortable,
    this.flow = BookReaderFlow.continuous,
    this.transition = BookPageTransition.fade,
    this.showContentsRail = true,
    this.autoAdvance = true,
  });

  static const minimumFontScale = 0.8;
  static const maximumFontScale = 1.7;
  static const fontScaleStep = 0.1;

  final BookReaderTheme theme;

  /// Applied as a text scale over the whole chapter, so it reaches the hosted
  /// renderer without any of them having to know about the reader.
  final double fontScale;
  final BookReaderMeasure measure;
  final BookReaderFlow flow;
  final BookPageTransition transition;
  final bool showContentsRail;

  /// Whether reaching the end of a chapter carries on into the next one.
  final bool autoAdvance;

  BookReaderSettings copyWith({
    BookReaderTheme? theme,
    double? fontScale,
    BookReaderMeasure? measure,
    BookReaderFlow? flow,
    BookPageTransition? transition,
    bool? showContentsRail,
    bool? autoAdvance,
  }) =>
      BookReaderSettings(
        theme: theme ?? this.theme,
        fontScale: (fontScale ?? this.fontScale)
            .clamp(minimumFontScale, maximumFontScale),
        measure: measure ?? this.measure,
        flow: flow ?? this.flow,
        transition: transition ?? this.transition,
        showContentsRail: showContentsRail ?? this.showContentsRail,
        autoAdvance: autoAdvance ?? this.autoAdvance,
      );

  Map<String, Object?> toJson() => {
        'theme': theme.name,
        'font_scale': fontScale,
        'measure': measure.name,
        'flow': flow.name,
        'transition': transition.name,
        'contents_rail': showContentsRail,
        'auto_advance': autoAdvance,
      };

  static BookReaderSettings fromJson(Object? value) {
    if (value is! Map) {
      return const BookReaderSettings();
    }
    final values = Map<String, dynamic>.from(value);
    return const BookReaderSettings().copyWith(
      theme: BookReaderTheme.fromValue(values['theme']),
      fontScale: _readDouble(values['font_scale'], 1),
      measure: BookReaderMeasure.fromValue(values['measure']),
      flow: BookReaderFlow.fromValue(values['flow']),
      transition: BookPageTransition.fromValue(values['transition']),
      showContentsRail: values['contents_rail'] != false,
      autoAdvance: values['auto_advance'] != false,
    );
  }
}

@immutable
class BookBookmark {
  const BookBookmark({
    required this.id,
    required this.chapterId,
    required this.offset,
    required this.createdAt,
    this.label = '',
  });

  final String id;
  final String chapterId;

  /// Where in the chapter the mark sits, 0 at the top and 1 at the end.
  final double offset;
  final String label;
  final DateTime createdAt;

  BookBookmark copyWith({String? label}) => BookBookmark(
        id: id,
        chapterId: chapterId,
        offset: offset,
        createdAt: createdAt,
        label: label ?? this.label,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'chapter': chapterId,
        'offset': offset,
        'created_at': createdAt.millisecondsSinceEpoch,
        if (label.isNotEmpty) 'label': label,
      };

  static BookBookmark? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final values = Map<String, dynamic>.from(value);
    final id = values['id'];
    final chapterId = values['chapter'];
    if (id is! String || chapterId is! String) {
      return null;
    }
    return BookBookmark(
      id: id,
      chapterId: chapterId,
      offset: _readDouble(values['offset'], 0).clamp(0, 1).toDouble(),
      label: values['label'] is String ? values['label'] as String : '',
      createdAt: _readDate(values['created_at']),
    );
  }
}

/// A highlight with a note attached — the quote the reader kept, and what
/// they wanted to say about it.
@immutable
class BookNote {
  const BookNote({
    required this.id,
    required this.chapterId,
    required this.offset,
    required this.createdAt,
    this.quote = '',
    this.body = '',
    this.color = BookNoteColor.yellow,
  });

  final String id;
  final String chapterId;
  final double offset;
  final String quote;
  final String body;
  final BookNoteColor color;
  final DateTime createdAt;

  bool get isEmpty => quote.trim().isEmpty && body.trim().isEmpty;

  BookNote copyWith({
    String? quote,
    String? body,
    BookNoteColor? color,
  }) =>
      BookNote(
        id: id,
        chapterId: chapterId,
        offset: offset,
        createdAt: createdAt,
        quote: quote ?? this.quote,
        body: body ?? this.body,
        color: color ?? this.color,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'chapter': chapterId,
        'offset': offset,
        'created_at': createdAt.millisecondsSinceEpoch,
        'color': color.name,
        if (quote.isNotEmpty) 'quote': quote,
        if (body.isNotEmpty) 'body': body,
      };

  static BookNote? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final values = Map<String, dynamic>.from(value);
    final id = values['id'];
    final chapterId = values['chapter'];
    if (id is! String || chapterId is! String) {
      return null;
    }
    return BookNote(
      id: id,
      chapterId: chapterId,
      offset: _readDouble(values['offset'], 0).clamp(0, 1).toDouble(),
      quote: values['quote'] is String ? values['quote'] as String : '',
      body: values['body'] is String ? values['body'] as String : '',
      color: BookNoteColor.fromValue(values['color']),
      createdAt: _readDate(values['created_at']),
    );
  }
}

@immutable
class BookReadingStats {
  const BookReadingStats({
    this.totalSeconds = 0,
    this.sessions = 0,
    this.lastReadAt,
    this.dailySeconds = const <String, int>{},
  });

  /// Days of history kept, so the envelope cannot grow without bound.
  static const retainedDays = 120;

  final int totalSeconds;
  final int sessions;
  final DateTime? lastReadAt;

  /// Seconds read per calendar day, keyed `yyyy-mm-dd`.
  final Map<String, int> dailySeconds;

  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';

  int secondsOn(DateTime date) => dailySeconds[dayKey(date)] ?? 0;

  /// Consecutive days read up to [today], counting today only if it has time
  /// on it, so an unread morning does not wipe out a streak.
  int streakOn(DateTime today) {
    var cursor = DateTime(today.year, today.month, today.day);
    if (secondsOn(cursor) == 0) {
      cursor = cursor.subtract(const Duration(days: 1));
      if (secondsOn(cursor) == 0) {
        return 0;
      }
    }
    var streak = 0;
    while (secondsOn(cursor) > 0) {
      streak += 1;
      cursor = cursor.subtract(const Duration(days: 1));
    }
    return streak;
  }

  BookReadingStats recordSeconds(int seconds, {required DateTime at}) {
    if (seconds <= 0) {
      return this;
    }
    final key = dayKey(at);
    final next = Map<String, int>.from(dailySeconds)
      ..update(key, (value) => value + seconds, ifAbsent: () => seconds);
    final cutoff = at.subtract(const Duration(days: retainedDays));
    next.removeWhere((day, _) => day.compareTo(dayKey(cutoff)) < 0);
    return BookReadingStats(
      totalSeconds: totalSeconds + seconds,
      sessions: sessions,
      lastReadAt: at,
      dailySeconds: next,
    );
  }

  BookReadingStats startSession({required DateTime at}) => BookReadingStats(
        totalSeconds: totalSeconds,
        sessions: sessions + 1,
        lastReadAt: at,
        dailySeconds: dailySeconds,
      );

  Map<String, Object?> toJson() => {
        'total_seconds': totalSeconds,
        'sessions': sessions,
        if (lastReadAt != null)
          'last_read_at': lastReadAt!.millisecondsSinceEpoch,
        if (dailySeconds.isNotEmpty) 'daily_seconds': dailySeconds,
      };

  static BookReadingStats fromJson(Object? value) {
    if (value is! Map) {
      return const BookReadingStats();
    }
    final values = Map<String, dynamic>.from(value);
    final daily = values['daily_seconds'];
    return BookReadingStats(
      totalSeconds: _readInt(values['total_seconds']),
      sessions: _readInt(values['sessions']),
      lastReadAt: values['last_read_at'] is int
          ? DateTime.fromMillisecondsSinceEpoch(values['last_read_at'] as int)
          : null,
      dailySeconds: daily is Map
          ? {
              for (final entry in daily.entries)
                if (entry.key is String && entry.value is int)
                  entry.key as String: entry.value as int,
            }
          : const <String, int>{},
    );
  }
}

/// Everything the reader remembers about one book.
@immutable
class BookReadingState {
  const BookReadingState({
    this.chapterId,
    this.progress = const <String, double>{},
    this.bookmarks = const <BookBookmark>[],
    this.notes = const <BookNote>[],
    this.settings = const BookReaderSettings(),
    this.stats = const BookReadingStats(),
  });

  /// A chapter counts as read once this much of it has been passed.
  static const finishedThreshold = 0.985;

  final String? chapterId;

  /// How far through each chapter the reader has been, 0 to 1.
  final Map<String, double> progress;
  final List<BookBookmark> bookmarks;
  final List<BookNote> notes;
  final BookReaderSettings settings;
  final BookReadingStats stats;

  double progressFor(String chapterId) => progress[chapterId] ?? 0;

  bool isFinished(String chapterId) =>
      progressFor(chapterId) >= finishedThreshold;

  /// The share of the whole book that has been read, weighting every chapter
  /// equally because a chapter is the only unit both a page and a PDF share.
  double overallProgress(List<BookChapter> chapters) {
    final readable = chapters.where((chapter) => !chapter.isPart).toList();
    if (readable.isEmpty) {
      return 0;
    }
    final total = readable.fold<double>(
      0,
      (sum, chapter) => sum + progressFor(chapter.id),
    );
    return (total / readable.length).clamp(0, 1).toDouble();
  }

  int finishedCount(List<BookChapter> chapters) => chapters
      .where((chapter) => !chapter.isPart && isFinished(chapter.id))
      .length;

  List<BookBookmark> bookmarksIn(String chapterId) => [
        for (final bookmark in bookmarks)
          if (bookmark.chapterId == chapterId) bookmark,
      ];

  List<BookNote> notesIn(String chapterId) => [
        for (final note in notes)
          if (note.chapterId == chapterId) note,
      ];

  BookReadingState copyWith({
    String? chapterId,
    Map<String, double>? progress,
    List<BookBookmark>? bookmarks,
    List<BookNote>? notes,
    BookReaderSettings? settings,
    BookReadingStats? stats,
  }) =>
      BookReadingState(
        chapterId: chapterId ?? this.chapterId,
        progress: progress ?? this.progress,
        bookmarks: bookmarks ?? this.bookmarks,
        notes: notes ?? this.notes,
        settings: settings ?? this.settings,
        stats: stats ?? this.stats,
      );

  /// Progress only ever moves forward — scrolling back up a chapter must not
  /// undo the fact that it was read.
  BookReadingState withProgress(String chapterId, double value) {
    final clamped = value.clamp(0.0, 1.0);
    if (clamped <= progressFor(chapterId)) {
      return this;
    }
    return copyWith(
      progress: {...progress, chapterId: clamped},
    );
  }

  /// Drops positions, bookmarks and notes for chapters that no longer exist.
  BookReadingState prunedTo(Iterable<String> chapterIds) {
    final live = chapterIds.toSet();
    final nextProgress = {
      for (final entry in progress.entries)
        if (live.contains(entry.key)) entry.key: entry.value,
    };
    final nextBookmarks = [
      for (final bookmark in bookmarks)
        if (live.contains(bookmark.chapterId)) bookmark,
    ];
    final nextNotes = [
      for (final note in notes)
        if (live.contains(note.chapterId)) note,
    ];
    if (nextProgress.length == progress.length &&
        nextBookmarks.length == bookmarks.length &&
        nextNotes.length == notes.length) {
      return this;
    }
    return copyWith(
      progress: nextProgress,
      bookmarks: nextBookmarks,
      notes: nextNotes,
    );
  }

  Map<String, dynamic> toJson() => {
        if (chapterId != null) 'chapter': chapterId,
        if (progress.isNotEmpty) 'progress': progress,
        if (bookmarks.isNotEmpty)
          'bookmarks': [for (final mark in bookmarks) mark.toJson()],
        if (notes.isNotEmpty)
          'notes': [for (final note in notes) note.toJson()],
        'settings': settings.toJson(),
        'stats': stats.toJson(),
      };

  static BookReadingState fromJson(Map<String, dynamic> values) {
    final progress = values['progress'];
    final bookmarks = values['bookmarks'];
    final notes = values['notes'];
    return BookReadingState(
      chapterId:
          values['chapter'] is String ? values['chapter'] as String : null,
      progress: progress is Map
          ? {
              for (final entry in progress.entries)
                if (entry.key is String && entry.value is num)
                  entry.key as String:
                      (entry.value as num).toDouble().clamp(0, 1).toDouble(),
            }
          : const <String, double>{},
      bookmarks: bookmarks is List
          ? [
              for (final value in bookmarks)
                if (BookBookmark.fromJson(value) case final mark?) mark,
            ]
          : const <BookBookmark>[],
      notes: notes is List
          ? [
              for (final value in notes)
                if (BookNote.fromJson(value) case final note?) note,
            ]
          : const <BookNote>[],
      settings: BookReaderSettings.fromJson(values['settings']),
      stats: BookReadingStats.fromJson(values['stats']),
    );
  }
}

double _readDouble(Object? value, double fallback) =>
    value is num ? value.toDouble() : fallback;

int _readInt(Object? value) => value is num ? value.toInt() : 0;

DateTime _readDate(Object? value) => value is int
    ? DateTime.fromMillisecondsSinceEpoch(value)
    : DateTime.fromMillisecondsSinceEpoch(0);
