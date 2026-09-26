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
  const PdfOcrMatch({
    required this.pageNumber,
    required this.rects,
    this.text = '',
    this.start = 0,
  });

  final int pageNumber;
  final String text;

  /// Character offset, so two occurrences in the same word stay distinct.
  final int start;

  /// Normalized to the page: 0..1 on both axes.
  final List<Rect> rects;
}

typedef PdfOcrPageScanner = Future<OcrResult> Function(PdfPage page);

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
  PdfOcrSearchIndex({
    OcrService? service,
    @visibleForTesting PdfOcrPageScanner? scanPage,
    @visibleForTesting Future<Directory> Function()? temporaryDirectory,
  })  : _service = service ?? OcrService(),
        _scanPageOverride = scanPage,
        _temporaryDirectory = temporaryDirectory ?? getTemporaryDirectory;

  final OcrService _service;
  final PdfOcrPageScanner? _scanPageOverride;
  final Future<Directory> Function() _temporaryDirectory;
  final Map<int, _ScannedPage> _pages = {};
  PdfDocument? _document;
  Set<int> _targets = {};

  bool _scanning = false;
  bool _disposed = false;
  int _generation = 0;
  String? _failure;

  int get scannedPages => _targets.where(_pages.containsKey).length;
  int get totalPages => _targets.length;
  bool get isScanning => _scanning;
  bool get hasPages => _pages.isNotEmpty;
  bool get isComplete =>
      _document != null && _targets.every(_pages.containsKey);

  /// Why the scan could not run, if it could not.
  String? get failure => _failure;

  /// Reads every page that has not been read yet, one at a time, reporting
  /// after each so results appear while the rest is still being scanned.
  ///
  /// Automatic find supplies only pages without a text layer. An explicit
  /// scan may include all pages, including images on otherwise textual pages.
  /// Empty successful pages are cached too; failed pages remain retryable.
  Future<void> scan(
    PdfDocument document, {
    int startPage = 1,
    Iterable<int>? pageNumbers,
  }) async {
    if (_disposed || (_scanning && identical(_document, document))) {
      return;
    }
    if (!identical(_document, document)) {
      _document = document;
      _pages.clear();
    }
    final generation = ++_generation;
    bool current() => !_disposed && generation == _generation;
    _targets = (pageNumbers ?? document.pages.map((page) => page.pageNumber))
        .where((number) => number >= 1 && number <= document.pages.length)
        .toSet();
    _failure = null;
    if (isComplete) {
      _scanning = false;
      notifyListeners();
      return;
    }
    _scanning = true;
    notifyListeners();

    Directory? workspace;
    try {
      if (!current()) return;
      if (_scanPageOverride == null) {
        final parent = await _temporaryDirectory();
        if (!current()) return;
        workspace = await parent.createTemp('appflowy-pdf-ocr-');
      }
      final numbers = _targets.toList()..sort();
      final ordered = [
        ...numbers.where((number) => number >= startPage),
        ...numbers.where((number) => number < startPage),
      ];
      for (final number in ordered) {
        if (!current()) return;
        if (_pages.containsKey(number)) {
          continue;
        }
        try {
          final page = document.pages[number - 1];
          final result = _scanPageOverride != null
              ? await _scanPageOverride(page)
              : await _scanPage(page, workspace!, current);
          if (!current()) return;
          if (result != null) {
            _pages[number] = _buildScannedPage(result);
          }
        } on OcrUnavailableException catch (error) {
          if (!current()) return;
          _failure = error.toString();
          // An unavailable engine will not recover on the next page. Keep
          // completed pages and let the person explicitly retry later.
          break;
        } on Object catch (error, stackTrace) {
          if (!current()) return;
          Log.error('Failed to scan PDF page $number', error, stackTrace);
          _failure = 'Some pages could not be scanned. Retry the scan.';
        }
        notifyListeners();
      }
    } on Object catch (error, stackTrace) {
      if (!current()) return;
      Log.error('Failed to scan a PDF for text', error, stackTrace);
      _failure = 'This document could not be scanned.';
    } finally {
      final directory = workspace;
      if (directory != null) {
        try {
          await directory.delete(recursive: true);
        } on Object {
          // Temporary-file cleanup must not replace the scan result.
        }
      }
      // A cancelled task may finish after a retry or even after disposal.
      // It must neither publish results nor clear the newer task's busy flag.
      if (current()) {
        _scanning = false;
        notifyListeners();
      }
    }
  }

  void cancel() {
    if (_disposed) return;
    ++_generation;
    _scanning = false;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _scanning = false;
    _pages.clear();
    _document = null;
    _targets.clear();
    super.dispose();
  }

  /// Everything [query] matches in what has been scanned so far.
  List<PdfOcrMatch> search(String query, FindOptions options) {
    if (_disposed || query.isEmpty || _pages.isEmpty) {
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
          results.add(
            PdfOcrMatch(
              pageNumber: number,
              rects: List.unmodifiable(rects),
              text: page.text.substring(match.start, match.end),
              start: match.start,
            ),
          );
        }
      }
    }
    return results;
  }

  Future<OcrResult?> _scanPage(
    PdfPage page,
    Directory workspace,
    bool Function() current,
  ) async {
    final raster = await _renderPdfPageRaster(page);
    if (!current()) return null;
    final file = File(p.join(workspace.path, 'page-${page.pageNumber}.png'));
    try {
      await file.writeAsBytes(raster.bytes, flush: true);
      if (!current()) return null;
      // Tesseract's pixel boxes refer to this raster, NOT PDF points.
      // Windows OCR normalizes against its own internally scaled dimensions.
      return await _service.recognize(file, imageSize: raster.size);
    } finally {
      try {
        await file.delete();
      } on Object {
        // The scan workspace is also removed by its owner.
      }
    }
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
        if (!word.bounds.isFinite) continue;
        final bounds = word.bounds.intersect(const Rect.fromLTWH(0, 0, 1, 1));
        if (!bounds.isEmpty) {
          words.add((start: start, end: buffer.length, bounds: bounds));
        }
      }
    }
    return _ScannedPage(text: buffer.toString(), words: words);
  }
}

/// Renders a page as a bitmap a text recogniser can read.
///
/// Small print is read far better at roughly 200 DPI, but the bitmap still
/// has to stay inside what the engines accept.
Future<Uint8List> renderPdfPagePng(PdfPage page) async =>
    (await _renderPdfPageRaster(page)).bytes;

Future<({Uint8List bytes, Size size})> _renderPdfPageRaster(
  PdfPage page,
) async {
  if (!page.width.isFinite ||
      !page.height.isFinite ||
      page.width <= 0 ||
      page.height <= 0) {
    throw StateError('the page has invalid dimensions');
  }
  final scale = _minOf(3, _minOf(3200 / page.width, 3200 / page.height));
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
    return (
      bytes: data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      size: Size(image.width.toDouble(), image.height.toDouble()),
    );
  } finally {
    image.dispose();
  }
}

double _minOf(double a, double b) => a < b ? a : b;
