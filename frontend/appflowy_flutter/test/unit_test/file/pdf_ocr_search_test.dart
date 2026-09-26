import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_ocr_search.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('OCR indexes current page first, caches empty pages, and honors options',
      () async {
    final document = _Document(3);
    final calls = <int>[];
    final index = PdfOcrSearchIndex(
      scanPage: (page) async {
        calls.add(page.pageNumber);
        return page.pageNumber == 1
            ? OcrResult.empty
            : _result('Report report a.b axb catalog cat');
      },
    );
    addTearDown(index.dispose);

    expect(index.search('', const FindOptions()), isEmpty);
    expect(calls, isEmpty);
    await index.scan(document, startPage: 2);
    expect(calls, [2, 3, 1]);
    expect(index.scannedPages, 3);
    expect(index.isComplete, isTrue);
    expect(index.isScanning, isFalse);
    expect(index.failure, isNull);
    expect(index.search('report', const FindOptions()), hasLength(4));
    expect(
      index.search('report', const FindOptions(caseSensitive: true)),
      hasLength(2),
    );
    expect(index.search('a.b', const FindOptions()), hasLength(2));
    expect(
      index.search('a.b', const FindOptions(useRegex: true)),
      hasLength(4),
    );
    expect(
      index.search('cat', const FindOptions(wholeWord: true)),
      hasLength(2),
    );
    expect(index.search('[', const FindOptions(useRegex: true)), isEmpty);
    expect(index.search('^', const FindOptions(useRegex: true)), isEmpty);
    final match = index.search('report', const FindOptions()).first;
    expect(match.pageNumber, 2);
    expect(match.text, 'Report');
    expect(match.start, 0);
    expect(match.rects, [const ui.Rect.fromLTWH(0.1, 0.2, 0.8, 0.1)]);

    await index.scan(document);
    expect(calls, [2, 3, 1], reason: 'Even a genuine empty page is cached');
  });

  test('automatic target subset can be extended by an explicit scan', () async {
    final document = _Document(3);
    final calls = <int>[];
    final index = PdfOcrSearchIndex(
      scanPage: (page) async {
        calls.add(page.pageNumber);
        return OcrResult.empty;
      },
    );
    addTearDown(index.dispose);
    await index.scan(document, startPage: 3, pageNumbers: [2, 3]);
    expect(calls, [3, 2]);
    expect(index.totalPages, 2);
    expect(index.isComplete, isTrue);
    await index.scan(document);
    expect(calls, [3, 2, 1]);
    expect(index.scannedPages, 3);
  });

  test('page failures retain matches and retry only unfinished pages',
      () async {
    final document = _Document(3);
    final calls = <int>[];
    var fail = true;
    final index = PdfOcrSearchIndex(
      scanPage: (page) async {
        calls.add(page.pageNumber);
        if (page.pageNumber == 2 && fail) {
          throw StateError('Synthetic page error');
        }
        return page.pageNumber == 3 ? OcrResult.empty : _result('retained');
      },
    );
    addTearDown(index.dispose);
    await index.scan(document);
    expect(index.failure, isNotNull);
    expect(index.isScanning, isFalse);
    expect(index.isComplete, isFalse);
    expect(index.scannedPages, 2);
    expect(index.search('retained', const FindOptions()), hasLength(1));
    index.search('another query', const FindOptions());
    expect(calls, [1, 2, 3]);

    fail = false;
    await index.scan(document);
    expect(calls, [1, 2, 3, 2]);
    expect(index.failure, isNull);
    expect(index.isComplete, isTrue);
    expect(index.search('retained', const FindOptions()), hasLength(2));
  });

  test('unavailable engines surface actionable errors without losing pages',
      () async {
    final document = _Document(3);
    final calls = <int>[];
    var unavailable = true;
    final index = PdfOcrSearchIndex(
      scanPage: (page) async {
        calls.add(page.pageNumber);
        if (page.pageNumber == 2 && unavailable) {
          throw const OcrUnavailableException(
            'No local OCR',
            hint: 'Install a pack',
          );
        }
        return _result('cached');
      },
    );
    addTearDown(index.dispose);
    await index.scan(document);
    expect(calls, [1, 2]);
    expect(index.failure, contains('Install a pack'));
    expect(index.search('cached', const FindOptions()), hasLength(1));
    unavailable = false;
    await index.scan(document);
    expect(calls, [1, 2, 2, 3]);
    expect(index.failure, isNull);
    expect(index.isComplete, isTrue);
  });

  test(
      'cancel and immediate retry ignore the old task and resume completed pages',
      () async {
    final document = _Document(3);
    final firstStarted = Completer<void>();
    final secondStarted = Completer<void>();
    final oldPage = Completer<OcrResult>();
    final newPage = Completer<OcrResult>();
    final calls = <int>[];
    var secondPageAttempts = 0;
    final index = PdfOcrSearchIndex(
      scanPage: (page) async {
        calls.add(page.pageNumber);
        if (page.pageNumber != 2) return _result('retained');
        if (++secondPageAttempts == 1) {
          firstStarted.complete();
          return oldPage.future;
        }
        secondStarted.complete();
        return newPage.future;
      },
    );
    addTearDown(index.dispose);
    final oldScan = index.scan(document);
    await firstStarted.future;
    expect(index.scannedPages, 1);
    index.cancel();
    expect(index.isScanning, isFalse);
    final retry = index.scan(document);
    await secondStarted.future;
    oldPage.complete(_result('obsolete'));
    await oldScan;
    expect(
      index.isScanning,
      isTrue,
      reason: 'Old finally must not stop the retry',
    );
    expect(index.search('obsolete', const FindOptions()), isEmpty);
    expect(index.scannedPages, 1);
    newPage.complete(_result('current'));
    await retry;
    expect(calls, [1, 2, 2, 3]);
    expect(index.isComplete, isTrue);
    expect(index.search('current', const FindOptions()), hasLength(1));
    expect(index.search('retained', const FindOptions()), hasLength(2));
  });

  test(
      'dispose prevents all late notifications, writes to the index, and pages',
      () async {
    final started = Completer<void>();
    final page = Completer<OcrResult>();
    var calls = 0;
    var notifications = 0;
    final index = PdfOcrSearchIndex(
      scanPage: (_) {
        calls++;
        started.complete();
        return page.future;
      },
    )..addListener(() => notifications++);
    final scan = index.scan(_Document(3));
    await started.future;
    index.dispose();
    final before = notifications;
    page.complete(_result('late'));
    await scan;
    index.cancel();
    await index.scan(_Document(1));
    expect(notifications, before);
    expect(calls, 1);
    expect(index.search('late', const FindOptions()), isEmpty);
  });

  test('a new document never inherits cached or in-flight page numbers',
      () async {
    final oldDocument = _Document(1);
    final newDocument = _Document(1);
    final started = Completer<void>();
    final oldPage = Completer<OcrResult>();
    final index = PdfOcrSearchIndex(
      scanPage: (page) {
        if (identical(page.document, oldDocument)) {
          started.complete();
          return oldPage.future;
        }
        return Future.value(_result('new document'));
      },
    );
    addTearDown(index.dispose);
    final oldScan = index.scan(oldDocument);
    await started.future;
    await index.scan(newDocument);
    oldPage.complete(_result('old document'));
    await oldScan;
    expect(index.search('old', const FindOptions()), isEmpty);
    expect(index.search('new', const FindOptions()), hasLength(1));
    expect(index.scannedPages, 1);
    expect(index.isComplete, isTrue);
  });

  test('invalid/out-of-image OCR boxes are clipped, not painted off the page',
      () async {
    final index = PdfOcrSearchIndex(
      scanPage: (_) async => OcrResult(
        engine: 'fixture',
        lines: [
          OcrLine.fromWords(const [
            OcrWord(
              text: 'edge',
              bounds: ui.Rect.fromLTWH(-0.1, 0.9, 0.5, 0.2),
            ),
            OcrWord(
              text: 'outside',
              bounds: ui.Rect.fromLTWH(2, 2, 1, 1),
            ),
          ]),
        ],
      ),
    );
    addTearDown(index.dispose);
    await index.scan(_Document(1));
    final match = index.search('edge', const FindOptions()).single;
    expect(match.rects.single, const ui.Rect.fromLTRB(0, 0.9, 0.4, 1));
    expect(index.search('outside', const FindOptions()), isEmpty);
  });

  for (final windows in [false, true]) {
    test(
        'raster dimensions are correct for ${windows ? 'Windows' : 'Tesseract'} bounds',
        () async {
      // Only a synthetic raster and a disposable test directory are used.
      // The real index renders/encodes/cleans up; no OCR process is started.
      final directory = await Directory.systemTemp.createTemp('pdf-ocr-test-');
      final recorder = ui.PictureRecorder();
      ui.Canvas(recorder)
          .drawColor(const ui.Color(0xFFFFFFFF), ui.BlendMode.src);
      final picture = recorder.endRecording();
      final image = await picture.toImage(80, 100);
      picture.dispose();
      final service = _RasterService(windows: windows);
      final document = _Document(1, raster: image);
      final index = PdfOcrSearchIndex(
        service: service,
        temporaryDirectory: () async => directory,
      );
      try {
        await index.scan(document);
        expect(index.failure, isNull);
        expect(service.sizes, [const ui.Size(80, 100)]);
        expect(document.pages.single.size, const ui.Size(600, 800));
        final bounds =
            index.search('word', const FindOptions()).single.rects.single;
        expect(bounds.left, closeTo(0.1, 0.000001));
        expect(bounds.top, closeTo(0.2, 0.000001));
        expect(bounds.width, closeTo(0.3, 0.000001));
        expect(bounds.height, closeTo(0.1, 0.000001));
        expect(await directory.list().toList(), isEmpty);
        // Existing single-page OCR/export callers still receive PNG bytes.
        final png = await renderPdfPagePng(document.pages.single);
        expect(png.take(8), [137, 80, 78, 71, 13, 10, 26, 10]);
      } finally {
        index.dispose();
        image.dispose();
        await directory.delete(recursive: true);
      }
    });
  }
}

OcrResult _result(String text) => OcrResult(
      engine: 'fixture',
      lines: [
        OcrLine.fromWords([
          OcrWord(
            text: text,
            bounds: const ui.Rect.fromLTWH(0.1, 0.2, 0.8, 0.1),
          ),
        ]),
      ],
    );

class _Document extends PdfDocument {
  _Document(int count, {ui.Image? raster})
      : super(sourceName: 'synthetic.pdf') {
    pages = [for (var i = 1; i <= count; i++) _Page(this, i, raster)];
  }
  @override
  late final List<PdfPage> pages;
  @override
  PdfPermissions? get permissions => null;
  @override
  bool get isEncrypted => false;
  @override
  Future<void> dispose() async {}
  @override
  Future<List<PdfOutlineNode>> loadOutline() async => [];
  @override
  bool isIdenticalDocumentHandle(Object? other) => identical(this, other);
}

class _Page extends Fake implements PdfPage {
  _Page(this.document, this.pageNumber, this.raster);
  @override
  final PdfDocument document;
  @override
  final int pageNumber;
  final ui.Image? raster;
  @override
  double get width => 600;
  @override
  double get height => 800;
  @override
  ui.Size get size => ui.Size(width, height);
  @override
  Future<PdfImage?> render({
    int x = 0,
    int y = 0,
    int? width,
    int? height,
    double? fullWidth,
    double? fullHeight,
    ui.Color? backgroundColor,
    PdfAnnotationRenderingMode annotationRenderingMode =
        PdfAnnotationRenderingMode.annotationAndForms,
    PdfPageRenderCancellationToken? cancellationToken,
  }) async =>
      _Bitmap(raster!);
}

class _Bitmap extends PdfImage {
  _Bitmap(this.image);
  final ui.Image image;
  @override
  int get width => image.width;
  @override
  int get height => image.height;
  @override
  ui.PixelFormat get format => ui.PixelFormat.rgba8888;
  @override
  Uint8List get pixels => Uint8List(width * height * 4);
  @override
  Future<ui.Image> createImage() async => image.clone();
  @override
  void dispose() {}
}

class _RasterService extends OcrService {
  _RasterService({required this.windows}) : super(engines: []);
  final bool windows;
  final sizes = <ui.Size>[];
  @override
  Future<OcrResult> recognize(File image, {required ui.Size imageSize}) async {
    sizes.add(imageSize);
    if (windows) {
      // Windows reports its own scaled frame, independently of imageSize.
      return WindowsOcrEngine().parseWindowsOutput(
        '{"width":160,"height":200,"lines":[{"text":"word","words":'
        '[{"text":"word","x":16,"y":40,"w":48,"h":20}]}]}',
      );
    }
    return TesseractOcrEngine().parseTsv(
      'block_num\tpar_num\tline_num\tleft\ttop\twidth\theight\tconf\ttext\n'
      '1\t1\t1\t8\t20\t24\t10\t99\tword\n',
      imageSize,
    );
  }
}
