import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_page_raster_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late ui.Image pixels;

  setUpAll(() async {
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawColor(Colors.white, BlendMode.src);
    final picture = recorder.endRecording();
    pixels = await picture.toImage(2, 2);
    picture.dispose();
  });
  tearDownAll(() => pixels.dispose());

  test('raster budget is bounded before a high-DPI scene requests it', () {
    expect(
      PdfPageRasterCache.rasterWidthFor(
        onScreenWidth: 1200,
        devicePixelRatio: 3,
      ),
      1600,
    );
    expect(
      PdfPageRasterCache.rasterWidthFor(
        onScreenWidth: 800,
        devicePixelRatio: 1.5,
      ),
      1200,
    );
    expect(
      PdfPageRasterCache.rasterWidthFor(
        onScreenWidth: 10,
        devicePixelRatio: 1,
      ),
      240,
    );
  });

  test('ready bounded raster satisfies its own high-DPI scene lookup',
      () async {
    final document = _Document(pixels);
    final cache = PdfPageRasterCache();
    try {
      final width = PdfPageRasterCache.rasterWidthFor(
        onScreenWidth: 1200,
        devicePixelRatio: 3,
      );
      final image = await cache.load(document.pages.first, targetWidth: width);
      expect(image, isNotNull);
      expect(document.pages.first.renderWidths, [1600]);
      expect(cache.peek(1, minWidth: width), same(image));
      // Defensively accept an older caller's unbounded pixel width as well.
      expect(cache.peek(1, minWidth: 3600), same(image));
      expect(
        await cache.load(document.pages.first, targetWidth: 3600),
        same(image),
      );
      expect(document.pages.first.renderWidths, hasLength(1));
    } finally {
      cache.dispose();
    }
  });

  test('small PDF pages reuse the raster permitted by the page-scale cap',
      () async {
    final document = _Document(pixels, pageWidth: 100);
    final cache = PdfPageRasterCache();
    try {
      final image = await cache.load(document.pages.first, targetWidth: 3600);
      expect(image, isNotNull);
      expect(document.pages.first.renderWidths, [400]);
      expect(cache.peek(1, minWidth: 3600), same(image));
      expect(
        await cache.load(document.pages.first, targetWidth: 1600),
        same(image),
      );
      expect(document.pages.first.renderWidths, hasLength(1));
    } finally {
      cache.dispose();
    }
  });

  test('a pending small raster is upgraded for the waiting high-DPI request',
      () async {
    final document = _Document(pixels);
    final gate = Completer<void>();
    document.pages.first.gate = gate.future;
    final cache = PdfPageRasterCache();
    try {
      final small = cache.load(document.pages.first, targetWidth: 240);
      final large = cache.load(document.pages.first, targetWidth: 3600);
      gate.complete();
      await small;
      final image = await large;
      expect(document.pages.first.renderWidths, [240, 1600]);
      expect(cache.peek(1, minWidth: 3600), same(image));
    } finally {
      if (!gate.isCompleted) gate.complete();
      cache.dispose();
    }
  });

  test('old document completion cannot populate or unlock replacement page',
      () async {
    final old = _Document(pixels);
    final replacement = _Document(pixels);
    final oldGate = Completer<void>();
    final newGate = Completer<void>();
    old.pages.first.gate = oldGate.future;
    replacement.pages.first.gate = newGate.future;
    final cache = PdfPageRasterCache();
    try {
      final obsolete = cache.load(old.pages.first, targetWidth: 1600);
      cache.clear();
      final pending = cache.load(replacement.pages.first, targetWidth: 1600);
      oldGate.complete();
      expect(await obsolete, isNull);
      expect(cache.peek(1), isNull);
      expect(
        cache.load(replacement.pages.first, targetWidth: 1600),
        same(pending),
        reason: 'Old whenComplete must not remove the new pending entry',
      );
      newGate.complete();
      final image = await pending;
      expect(image, isNotNull);
      expect(cache.peek(1, minWidth: 1600), same(image));
      expect(replacement.pages.first.renderWidths, [1600]);
    } finally {
      if (!oldGate.isCompleted) oldGate.complete();
      if (!newGate.isCompleted) newGate.complete();
      cache.dispose();
    }
  });

  test(
      'rebinding a cache cancels the old prefetch sequence, not just its image',
      () async {
    final old = _Document(pixels, count: 2);
    final replacement = _Document(pixels);
    final gate = Completer<void>();
    old.pages.first.gate = gate.future;
    final cache = PdfPageRasterCache();
    try {
      final obsolete = cache.prefetch(old, [1, 2], targetWidth: 800);
      final image = await cache.load(replacement.pages.first, targetWidth: 800);
      gate.complete();
      await obsolete;
      expect(old.pages.last.renderWidths, isEmpty);
      expect(cache.peek(1, minWidth: 800), same(image));
      expect(cache.peek(2), isNull);
    } finally {
      if (!gate.isCompleted) gate.complete();
      cache.dispose();
    }
  });

  test('dispose rejects a pending raster without leaving a cached image',
      () async {
    final document = _Document(pixels);
    final gate = Completer<void>();
    document.pages.first.gate = gate.future;
    final cache = PdfPageRasterCache();
    final pending = cache.load(document.pages.first, targetWidth: 800);
    cache.dispose();
    gate.complete();
    expect(await pending, isNull);
    expect(cache.peek(1), isNull);
  });
}

class _Document extends Fake implements PdfDocument {
  _Document(ui.Image image, {int count = 1, double pageWidth = 600}) {
    pages = [
      for (var index = 0; index < count; index++)
        _Page(this, index + 1, image, pageWidth),
    ];
  }

  @override
  late final List<_Page> pages;
}

class _Page extends Fake implements PdfPage {
  _Page(this.document, this.pageNumber, this.image, this.pageWidth);

  @override
  final PdfDocument document;
  @override
  final int pageNumber;
  final ui.Image image;
  final double pageWidth;
  final renderWidths = <double>[];
  Future<void>? gate;
  @override
  double get width => pageWidth;
  @override
  double get height => 800;

  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async {
    renderWidths.add(fullWidth!);
    if (gate != null) await gate;
    return _Bitmap(image);
  }
}

class _Bitmap extends Fake implements PdfImage {
  _Bitmap(this.image);
  final ui.Image image;
  @override
  Future<ui.Image> createImage() async => image.clone();
  @override
  void dispose() {}
}
