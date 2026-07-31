import 'dart:async';

import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:flutter/foundation.dart';

/// Owns everything the reader remembers, and writes it back to the collection
/// envelope without the views having to think about persistence.
class BookReadingController extends ChangeNotifier {
  BookReadingController({
    required Map<String, dynamic> initialState,
    required this.onPersist,
    this.persistDebounce = const Duration(milliseconds: 1200),
    this.sessionTick = const Duration(seconds: 20),
  }) : _state = BookReadingState.fromJson(initialState);

  /// Called with the serialised state whenever it settles.
  final ValueChanged<Map<String, dynamic>> onPersist;
  final Duration persistDebounce;

  /// How often reading time is banked. Long enough not to churn the envelope,
  /// short enough that closing the window loses only a few seconds.
  final Duration sessionTick;

  BookReadingState _state;
  List<BookChapter> _chapters = const [];
  Timer? _persistTimer;
  Timer? _sessionTimer;
  DateTime? _tickStartedAt;
  bool _active = false;
  bool _disposed = false;

  BookReadingState get state => _state;
  BookReaderSettings get settings => _state.settings;
  List<BookChapter> get chapters => _chapters;

  List<BookChapter> get readableChapters => [
        for (final chapter in _chapters)
          if (!chapter.isPart) chapter
      ];

  BookChapter? get currentChapter {
    final readable = readableChapters;
    if (readable.isEmpty) {
      return null;
    }
    final id = _state.chapterId;
    for (final chapter in readable) {
      if (chapter.id == id) {
        return chapter;
      }
    }
    return readable.first;
  }

  BookChapter? get nextChapter => _neighbour(1);
  BookChapter? get previousChapter => _neighbour(-1);

  BookChapter? _neighbour(int delta) {
    final readable = readableChapters;
    final current = currentChapter;
    if (current == null) {
      return null;
    }
    final index = readable.indexWhere((chapter) => chapter.id == current.id);
    final target = index + delta;
    if (index < 0 || target < 0 || target >= readable.length) {
      return null;
    }
    return readable[target];
  }

  /// Adopts the book's contents. Positions, bookmarks and notes belonging to
  /// chapters that were removed are dropped.
  void setChapters(List<BookChapter> chapters) {
    final sameOrder = _chapters.length == chapters.length &&
        !_chapters.indexed.any((entry) => entry.$2.id != chapters[entry.$1].id);
    _chapters = chapters;
    final pruned = _state.prunedTo([for (final c in chapters) c.id]);
    final resolved = _withValidChapter(pruned);
    final changed = !identical(resolved, _state);
    _state = resolved;
    if (changed) {
      _schedulePersist();
    }
    if (!sameOrder || changed) {
      _notify();
    }
  }

  BookReadingState _withValidChapter(BookReadingState state) {
    final readable = readableChapters;
    if (readable.isEmpty) {
      return state;
    }
    final id = state.chapterId;
    if (id != null && readable.any((chapter) => chapter.id == id)) {
      return state;
    }
    return state.copyWith(chapterId: readable.first.id);
  }

  void openChapter(String chapterId) {
    if (_state.chapterId == chapterId) {
      return;
    }
    _state = _state.copyWith(chapterId: chapterId);
    _schedulePersist();
    _notify();
  }

  bool goToNextChapter() {
    final next = nextChapter;
    if (next == null) {
      return false;
    }
    openChapter(next.id);
    return true;
  }

  bool goToPreviousChapter() {
    final previous = previousChapter;
    if (previous == null) {
      return false;
    }
    openChapter(previous.id);
    return true;
  }

  /// Reports how far through [chapterId] the reader has scrolled.
  void reportProgress(String chapterId, double value) {
    final next = _state.withProgress(chapterId, value);
    if (identical(next, _state)) {
      return;
    }
    _state = next;
    _schedulePersist();
    _notify();
  }

  void updateSettings(BookReaderSettings settings) {
    _state = _state.copyWith(settings: settings);
    _schedulePersist();
    _notify();
  }

  void toggleContentsRail() => updateSettings(
        settings.copyWith(showContentsRail: !settings.showContentsRail),
      );

  BookBookmark addBookmark({
    required String chapterId,
    required double offset,
    String label = '',
  }) {
    final bookmark = BookBookmark(
      id: uuid(),
      chapterId: chapterId,
      offset: offset.clamp(0, 1).toDouble(),
      label: label,
      createdAt: DateTime.now(),
    );
    _state = _state.copyWith(bookmarks: [..._state.bookmarks, bookmark]);
    _schedulePersist();
    _notify();
    return bookmark;
  }

  void removeBookmark(String id) {
    final next = [
      for (final bookmark in _state.bookmarks)
        if (bookmark.id != id) bookmark,
    ];
    if (next.length == _state.bookmarks.length) {
      return;
    }
    _state = _state.copyWith(bookmarks: next);
    _schedulePersist();
    _notify();
  }

  void renameBookmark(String id, String label) {
    _state = _state.copyWith(
      bookmarks: [
        for (final bookmark in _state.bookmarks)
          bookmark.id == id ? bookmark.copyWith(label: label) : bookmark,
      ],
    );
    _schedulePersist();
    _notify();
  }

  BookNote addNote({
    required String chapterId,
    required double offset,
    String quote = '',
    String body = '',
    BookNoteColor color = BookNoteColor.yellow,
  }) {
    final note = BookNote(
      id: uuid(),
      chapterId: chapterId,
      offset: offset.clamp(0, 1).toDouble(),
      quote: quote,
      body: body,
      color: color,
      createdAt: DateTime.now(),
    );
    _state = _state.copyWith(notes: [..._state.notes, note]);
    _schedulePersist();
    _notify();
    return note;
  }

  void updateNote(
    String id, {
    String? quote,
    String? body,
    BookNoteColor? color,
  }) {
    _state = _state.copyWith(
      notes: [
        for (final note in _state.notes)
          note.id == id
              ? note.copyWith(quote: quote, body: body, color: color)
              : note,
      ],
    );
    _schedulePersist();
    _notify();
  }

  void removeNote(String id) {
    final next = [
      for (final note in _state.notes)
        if (note.id != id) note,
    ];
    if (next.length == _state.notes.length) {
      return;
    }
    _state = _state.copyWith(notes: next);
    _schedulePersist();
    _notify();
  }

  /// Starts and stops the reading clock. Time only accrues while the reader is
  /// on screen and the window is in the foreground.
  void setActive(bool active) {
    if (_active == active || _disposed) {
      return;
    }
    _active = active;
    if (active) {
      _tickStartedAt = DateTime.now();
      _state = _state.copyWith(
        stats: _state.stats.startSession(at: _tickStartedAt!),
      );
      _sessionTimer = Timer.periodic(sessionTick, (_) => _bankReadingTime());
      _schedulePersist();
    } else {
      _sessionTimer?.cancel();
      _sessionTimer = null;
      _bankReadingTime();
    }
  }

  void _bankReadingTime() {
    final startedAt = _tickStartedAt;
    if (startedAt == null) {
      return;
    }
    final now = DateTime.now();
    final seconds = now.difference(startedAt).inSeconds;
    _tickStartedAt = now;
    if (seconds <= 0) {
      return;
    }
    _state = _state.copyWith(
      stats: _state.stats.recordSeconds(seconds, at: now),
    );
    _schedulePersist();
    _notify();
  }

  void _schedulePersist() {
    if (_disposed) {
      return;
    }
    _persistTimer?.cancel();
    _persistTimer = Timer(persistDebounce, flush);
  }

  /// Writes the state out now rather than waiting for the debounce.
  void flush() {
    _persistTimer?.cancel();
    _persistTimer = null;
    onPersist(_state.toJson());
  }

  void _notify() {
    if (!_disposed) {
      notifyListeners();
    }
  }

  @override
  void dispose() {
    _sessionTimer?.cancel();
    _bankReadingTime();
    _persistTimer?.cancel();
    _persistTimer = null;
    onPersist(_state.toJson());
    _disposed = true;
    super.dispose();
  }
}
