import 'dart:async';
import 'dart:convert';

import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:flutter_test/flutter_test.dart';

/// A ready, existing page handle for tests substituting the website leaf.
/// Uses the real session/parser/current-generation checks, but no JS/native IO.
class BookmarkReaderCaptureFixture {
  BookmarkReaderCaptureFixture(String url) {
    session.attach(this, (script) {
      expectSync(script, bookmarkVisibleArticleScript);
      captureUrls.add(session.url!);
      return captureGate?.future ?? Future.value(payload(session.url!));
    });
    session.navigationStarted(url);
    session.navigationFinished(url);
  }

  final session = BookmarkReadingSession();
  final captureUrls = <String>[];
  Completer<String?>? captureGate;

  static String payload(String url) => jsonEncode({
        'url': url,
        'html': '<article><h1>Visible saved article</h1>'
            '<p>This public paragraph belongs to the already visible page, '
            'not a new HTTP fetch or a hidden browser.</p></article>',
      });

  void dispose() {
    session.dispose();
    final gate = captureGate;
    if (gate != null && !gate.isCompleted) gate.complete(null);
  }
}

/// Reader UI boundary stub, NOT a replacement for production store-guard tests.
/// Records work start, publishes busy changes and rechecks the supplied live
/// guard after the save gate before returning a receipt. No metadata/disk IO.
class ReaderCaptureTestController extends BookmarkController {
  ReaderCaptureTestController({required super.service});

  final refreshes = <String>[];
  final captureSaves = <String>[];
  final savedCaptures = <BookmarkReaderCapture>[];
  final saveStores = <BookmarkSnapshotStore?>[];
  final saveReceipts = <bool>[];
  final _saving = <String>{};
  Completer<void>? saveGate;
  bool saveSucceeds = true;
  bool _fixtureDisposed = false;

  @override
  bool get isWorking => _saving.isNotEmpty || super.isWorking;

  @override
  int get workingCount => _saving.length + super.workingCount;

  @override
  bool isWorkingOn(String id) => _saving.contains(id) || super.isWorkingOn(id);

  @override
  Future<bool> saveReaderCapture(
    BookmarkEntry entry,
    BookmarkReaderCapture capture, {
    required bool Function() isCurrent,
    BookmarkSnapshotStore? store,
  }) async {
    bool allowed() =>
        !_fixtureDisposed &&
        capture.url == entry.url &&
        entryFor(entry.id)?.url == entry.url &&
        isCurrent();
    if (!allowed() || isWorkingOn(entry.id)) return false;
    captureSaves.add(entry.id);
    savedCaptures.add(capture);
    saveStores.add(store);
    _saving.add(entry.id);
    notifyListeners();
    try {
      await saveGate?.future;
      final saved = allowed() && saveSucceeds;
      saveReceipts.add(saved);
      return saved;
    } finally {
      _saving.remove(entry.id);
      if (!_fixtureDisposed) notifyListeners();
    }
  }

  @override
  Future<void> refresh(
    BookmarkEntry entry, {
    bool snapshot = false,
    bool force = true,
  }) async {
    // Keep the old API observable: Reader saving must never fall back to it.
    refreshes.add(entry.id);
  }

  @override
  void dispose() {
    _fixtureDisposed = true;
    final gate = saveGate;
    if (gate != null && !gate.isCompleted) gate.complete();
    super.dispose();
  }
}
