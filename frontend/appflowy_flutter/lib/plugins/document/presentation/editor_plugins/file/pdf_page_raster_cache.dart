import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

/// The widest a cached page bitmap is ever rendered. Page turns only need to
/// look right at screen resolution, and an uncapped render on a large monitor
/// costs far more than the animation saves.
const _maxRasterWidth = 1600.0;
const _minRasterWidth = 240.0;

/// Anything within this factor of the requested width is reused rather than
/// re-rendered, so a small zoom change never invalidates the cache.
const _reuseFactor = 0.78;

class _CachedPage {
  _CachedPage(this.image, this.width);

  final ui.Image image;
  final double width;
}

/// Keeps rasterised PDF pages ready so a page turn never has to decode a page
/// while it is animating.
class PdfPageRasterCache {
  PdfPageRasterCache({this.maxEntries = 6});

  final int maxEntries;
  final Map<int, _CachedPage> _pages = {};
  final Map<int, Future<ui.Image?>> _pending = {};
  int _lastRequested = 1;
  bool _disposed = false;

  /// The already rendered bitmap for [pageNumber], or null when it still has
  /// to be produced. Never blocks, so gestures can decide instantly whether an
  /// interactive turn is possible.
  ui.Image? peek(int pageNumber, {double minWidth = 0}) {
    final cached = _pages[pageNumber];
    if (cached == null) {
      return null;
    }
    return cached.width >= minWidth * _reuseFactor ? cached.image : null;
  }

  /// Renders [page] unless a good enough bitmap is already cached.
  Future<ui.Image?> load(PdfPage page, {required double targetWidth}) {
    if (_disposed) {
      return Future.value();
    }
    final width = targetWidth.clamp(_minRasterWidth, _maxRasterWidth);
    _lastRequested = page.pageNumber;
    final existing = peek(page.pageNumber, minWidth: width);
    if (existing != null) {
      return Future.value(existing);
    }
    return _pending[page.pageNumber] ??= _render(page, width).whenComplete(
      () => _pending.remove(page.pageNumber),
    );
  }

  Future<ui.Image?> _render(PdfPage page, double width) async {
    try {
      final scale = (width / page.width).clamp(0.2, 4.0);
      final rendered = await page.render(
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        backgroundColor: const Color(0xFFFFFFFF),
      );
      if (rendered == null) {
        return null;
      }
      ui.Image image;
      try {
        image = await rendered.createImage();
      } finally {
        rendered.dispose();
      }
      if (_disposed) {
        image.dispose();
        return null;
      }
      _pages.remove(page.pageNumber)?.image.dispose();
      _pages[page.pageNumber] = _CachedPage(image, page.width * scale);
      _evict();
      return image;
    } on Object {
      return null;
    }
  }

  /// Drops whichever cached page is furthest from where the reader is.
  void _evict() {
    while (_pages.length > maxEntries) {
      var furthest = _pages.keys.first;
      var distance = -1;
      for (final pageNumber in _pages.keys) {
        final delta = (pageNumber - _lastRequested).abs();
        if (delta > distance) {
          distance = delta;
          furthest = pageNumber;
        }
      }
      _pages.remove(furthest)?.image.dispose();
    }
  }

  /// Warms [pageNumbers] in order, ignoring anything out of the document.
  Future<void> prefetch(
    PdfDocument document,
    Iterable<int> pageNumbers, {
    required double targetWidth,
  }) async {
    for (final pageNumber in pageNumbers) {
      if (_disposed) {
        return;
      }
      if (pageNumber < 1 || pageNumber > document.pages.length) {
        continue;
      }
      await load(document.pages[pageNumber - 1], targetWidth: targetWidth);
    }
  }

  /// The width a page should be rasterised at to look sharp on screen.
  static double rasterWidthFor({
    required double onScreenWidth,
    required double devicePixelRatio,
  }) =>
      math.max(onScreenWidth, 1) * devicePixelRatio;

  void dispose() {
    _disposed = true;
    for (final cached in _pages.values) {
      cached.image.dispose();
    }
    _pages.clear();
    _pending.clear();
  }
}
