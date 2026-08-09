import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';

/// One place a scanned word was found.
@immutable
class PdfOcrMatch {
  const PdfOcrMatch({required this.pageNumber, required this.rects});

  final int pageNumber;

  /// Normalized to the page: 0..1 on both axes.
  final List<Rect> rects;
}

/// What one page's scan produced: its text, and where each word sits.
@immutable
class _ScannedPage {
  const _ScannedPage({required this.text, required this.words});

  final String text;

  /// Word bounds paired with the character range they occupy in [text].
  final List<({int start, int end, Rect bounds})> words;
}

/// Reads a scanned document so it can be searched.
///
/// A PDF made from photographs or a scanner carries no text layer, so pdfrx
/// finds nothing in it however the query is written. This renders each page
/// and hands it to the same text recogniser the image blocks use, then
/// searches what came back.
class PdfOcrSearchIndex extends ChangeNotifier {
  PdfOcrSearchIndex({OcrService? service}) : _service = service ?? OcrService();

  final OcrService _service;
  final Map<int, _ScannedPage> _pages = {};

  int _scanned = 0;
  int _total = 0;
  bool _scanning = false;
  bool _cancelled = false;
  String? _failure;

  int get scannedPages => _scanned;
  int get totalPages => _total;
  bool get isScanning => _scanning;
  bool get hasPages => _pages.isNotEmpty;

  /// Why the scan could not run, if it could not.
  String? get failure => _failure;

  /// Reads every page that has not been read yet, one at a time, reporting
  /// after each so results appear while the rest is still being scanned.
  Future<void> scan(PdfDocument document) async {
    if (_scanning) {
      return;
    }
    _scanning = true;
    _cancelled = false;
    _failure = null;
    _total = document.pages.length;
    _scanned = _pages.length;
    notifyListeners();

    Directory? workspace;
    try {
      workspace = Directory(
        p.join(
          (await getTemporaryDirectory()).path,
          'appflowy-pdf-ocr-${DateTime.now().microsecondsSinceEpoch}',
        ),
      );
      await workspace.create(recursive: true);
      for (final page in document.pages) {
        if (_cancelled) {
          break;
        }
        if (_pages.containsKey(page.pageNumber)) {
          continue;
        }
        final scanned = await _scanPage(page, workspace);
        if (_cancelled) {
          break;
        }
        _pages[page.pageNumber] = scanned;
        _scanned = _pages.length;
        notifyListeners();
      }
    } on OcrUnavailableException catch (error) {
      _failure = error.message;
    } on Object catch (error, stackTrace) {
      Log.error('Failed to scan a PDF for text', error, stackTrace);
      _failure = 'This document could not be scanned.';
    } finally {
      _scanning = false;
      final directory = workspace;
      if (directory != null) {
        unawaited(
          directory.delete(recursive: true).catchError((_) => directory),
        );
      }
      notifyListeners();
    }
  }

  void cancel() => _cancelled = true;

  /// Everything [query] matches in what has been scanned so far.
  List<PdfOcrMatch> search(String query, FindOptions options) {
    if (query.isEmpty || _pages.isEmpty) {
      return const [];
    }
    final results = <PdfOcrMatch>[];
    final numbers = _pages.keys.toList()..sort();
    for (final number in numbers) {
      final page = _pages[number]!;
      for (final match in findMatches(page.text, query, options)) {
        final rects = <Rect>[];
        for (final word in page.words) {
          if (word.end <= match.start || word.start >= match.end) {
            continue;
          }
          rects.add(word.bounds);
        }
        if (rects.isNotEmpty) {
          results.add(PdfOcrMatch(pageNumber: number, rects: rects));
        }
      }
    }
    return results;
  }

  Future<_ScannedPage> _scanPage(PdfPage page, Directory workspace) async {
    final file = File(p.join(workspace.path, 'page-${page.pageNumber}.png'));
    await file.writeAsBytes(await renderPdfPagePng(page), flush: true);
    final result = await _service.recognize(
      file,
      imageSize: Size(page.width, page.height),
    );
    unawaited(file.delete().catchError((_) => file));
    return _buildScannedPage(result);
  }

  /// Lays the recognised words out as one searchable string, remembering
  /// which characters belong to which word so a match can be pointed at.
  static _ScannedPage _buildScannedPage(OcrResult result) {
    final buffer = StringBuffer();
    final words = <({int start, int end, Rect bounds})>[];
    for (var lineIndex = 0; lineIndex < result.lines.length; lineIndex++) {
      if (lineIndex > 0) {
        buffer.write('\n');
      }
      final line = result.lines[lineIndex];
      for (var index = 0; index < line.words.length; index++) {
        if (index > 0) {
          buffer.write(' ');
        }
        final word = line.words[index];
        final start = buffer.length;
        buffer.write(word.text);
        words.add((start: start, end: buffer.length, bounds: word.bounds));
      }
    }
    return _ScannedPage(text: buffer.toString(), words: words);
  }
}

/// Renders a page as a bitmap a text recogniser can read.
///
/// Small print is read far better at roughly 200 DPI, but the bitmap still
/// has to stay inside what the engines accept.
Future<Uint8List> renderPdfPagePng(PdfPage page) async {
  final scale =
      _minOf(3200 / page.width, 3200 / page.height).clamp(1.0, 3.0).toDouble();
  final rendered = await page.render(
    fullWidth: page.width * scale,
    fullHeight: page.height * scale,
    backgroundColor: const Color(0xFFFFFFFF),
  );
  if (rendered == null) {
    throw StateError('the page could not be rendered');
  }

  Image image;
  try {
    image = await rendered.createImage();
  } finally {
    rendered.dispose();
  }

  try {
    final data = await image.toByteData(format: ImageByteFormat.png);
    if (data == null) {
      throw StateError('the page image could not be encoded');
    }
    return data.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

double _minOf(double a, double b) => a < b ? a : b;
