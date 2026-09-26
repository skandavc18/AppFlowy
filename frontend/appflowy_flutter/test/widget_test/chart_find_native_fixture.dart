import 'dart:ffi' as native;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:ffi/ffi.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// Already resolved through printing (pdf 3.11.3); no dependency-file changes.
// ignore: depend_on_referenced_packages
import 'package:pdf/widgets.dart' as pw;
import 'package:pdfrx/pdfrx.dart';

const nativeFindCapture = ValueKey('chart-find-native-capture');

/// Only temporary-directory placement is overridden: file IO, OCR processes,
/// PDFium and WebView2 remain real. This helper never initializes a binding.
class NativeFindFixture extends IOOverrides {
  late final Directory output;
  Directory? _scratch;
  late final File image;
  late final File pdf;
  late final File html;
  IOOverrides? _previousIo;
  String? _previousProfile;
  bool _redirected = false;

  Future<void> initialize(String projectRoot) async {
    final parent = await Directory(
      p.join(
        projectRoot,
        'build',
        'performance',
        'chart-find-native',
      ),
    ).create(recursive: true);
    output = await parent.createTemp('run-');
    final scratch = _scratch = await Directory(
      p.join(output.path, 'scratch'),
    ).create();
    _previousIo = IOOverrides.current;
    _previousProfile = Platform.environment['WEBVIEW2_USER_DATA_FOLDER'];
    // Process-local Win32 environment, not the user's environment/preferences.
    // FilePreview creates the real default WebView2 environment without a seam.
    _setProfile(p.join(scratch.path, 'webview2'));
    _redirected = true;
    IOOverrides.global = this;

    await (FontLoader('DM Sans')
          ..addFont(
            rootBundle.load(
              'assets/google_fonts/DM_Sans/DMSans-Variable.ttf',
            ),
          ))
        .load();
    final bytes = await _textPng();
    image = await File(p.join(scratch.path, 'synthetic.png'))
        .writeAsBytes(bytes, flush: true);
    final document = pw.Document()
      ..addPage(
        pw.Page(
          build: (_) => pw.Text(
            'Alpha alpha',
            style: pw.TextStyle(fontSize: 32),
          ),
        ),
      )
      ..addPage(
        pw.Page(
          build: (_) => pw.Center(
            child: pw.Image(pw.MemoryImage(bytes), width: 500),
          ),
        ),
      );
    pdf = await File(p.join(scratch.path, 'synthetic.pdf'))
        .writeAsBytes(await document.save(), flush: true);
    html = await File(p.join(scratch.path, 'synthetic.html')).writeAsString(
      '<!doctype html><html><body>'
      '<p>Hello <b>World</b> hello world</p>'
      '</body></html>',
      flush: true,
    );
  }

  @override
  Directory getSystemTempDirectory() => _scratch!;

  bool get scansClosed => !_scratch!.listSync().any(
        (entry) =>
            p.basename(entry.path).startsWith('appflowy-image-ocr-') ||
            p.basename(entry.path).startsWith('appflowy-ocr-engine-'),
      );

  bool get isolatedProfileCreated =>
      Directory(p.join(_scratch!.path, 'webview2')).existsSync();

  Future<void> dispose() async {
    try {
      final scratch = _scratch;
      if (scratch == null) return;
      final deadline = Stopwatch()..start();
      while (await scratch.exists()) {
        try {
          await scratch.delete(recursive: true);
        } on FileSystemException {
          if (deadline.elapsed > const Duration(seconds: 15)) {
            throw StateError('Native handles still hold fixture scratch; '
                'close this fixture process before removing its run directory.');
          }
          await Future<void>.delayed(const Duration(milliseconds: 100));
        }
      }
    } finally {
      if (_redirected) {
        IOOverrides.global = _previousIo;
        _setProfile(_previousProfile);
        _redirected = false;
      }
    }
  }
}

void _setProfile(String? value) {
  final set = native.DynamicLibrary.open('kernel32.dll').lookupFunction<
      native.Int32 Function(native.Pointer<Utf16>, native.Pointer<Utf16>),
      int Function(native.Pointer<Utf16>, native.Pointer<Utf16>)>(
    'SetEnvironmentVariableW',
  );
  final name = 'WEBVIEW2_USER_DATA_FOLDER'.toNativeUtf16();
  final folder = value?.toNativeUtf16() ?? native.nullptr.cast<Utf16>();
  try {
    if (set(name, folder) == 0) {
      throw StateError('Could not isolate the fixture WebView2 profile.');
    }
  } finally {
    calloc.free(name);
    if (folder != native.nullptr) calloc.free(folder);
  }
}

Future<Uint8List> _textPng() async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder)..drawColor(Colors.white, BlendMode.src);
  final text = TextPainter(
    text: const TextSpan(
      text: 'AppFlowy Native\nSearch 123',
      style:
          TextStyle(fontFamily: 'DM Sans', fontSize: 48, color: Colors.black),
    ),
    textDirection: TextDirection.ltr,
  )..layout(maxWidth: 820);
  text.paint(canvas, const Offset(40, 40));
  text.dispose();
  final picture = recorder.endRecording();
  ui.Image? image;
  try {
    image = await picture.toImage(900, 250);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw StateError('Synthetic OCR PNG encoding failed.');
    return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
  } finally {
    image?.dispose();
    picture.dispose();
  }
}

/// Captures the actual opened handle, including an open that finishes late.
/// Unmount/release useDocument leases before calling close; never fake PDFium.
class NativeFindDocumentRef extends PdfDocumentRefFile {
  NativeFindDocumentRef(File file) : super(file.path, autoDispose: false);
  Future<PdfDocument>? _opening;

  @override
  Future<PdfDocument> loadDocument(
    PdfDocumentLoaderProgressCallback progressCallback,
    PdfDocumentLoaderReportCallback reportCallback,
  ) =>
      _opening ??= super.loadDocument(progressCallback, reportCallback);

  Future<void> close() async {
    await _opening
        ?.then<void>(
          (document) => document.dispose(),
          onError: (Object _, StackTrace __) {}, // Failed open owns no handle.
        )
        .timeout(const Duration(seconds: 15));
  }
}

/// Flutter pixels only, never an OS screenshot or proof of WebView2 texture
/// contents. Optional ink checking is restricted to the visible native PDF page.
Future<bool> nativeFindSnapshot(
  WidgetTester tester, {
  File? output,
  Rect? globalRegion,
  Color? ink,
}) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byKey(nativeFindCapture),
  );
  final image = await boundary.toImage().timeout(const Duration(seconds: 10));
  try {
    if (output != null) {
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      if (png == null) throw StateError('Native capture PNG encoding failed.');
      final bytes =
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes);
      expect(bytes.take(8), orderedEquals([137, 80, 78, 71, 13, 10, 26, 10]));
      await output.writeAsBytes(bytes, flush: true);
    }
    if (globalRegion == null || ink == null) return true;
    final region = Rect.fromPoints(
      boundary.globalToLocal(globalRegion.topLeft),
      boundary.globalToLocal(globalRegion.bottomRight),
    ).intersect(Offset.zero & boundary.size);
    if (region.isEmpty) return false;
    final rgba = await image.toByteData();
    if (rgba == null) throw StateError('Native capture RGBA encoding failed.');
    final channels =
        [ink.r, ink.g, ink.b].map((v) => (v * 255).round()).toList();
    var matches = 0;
    for (var y = region.top.ceil(); y < region.bottom.floor(); y += 2) {
      for (var x = region.left.ceil(); x < region.right.floor(); x += 2) {
        final offset = (y * image.width + x) * 4;
        if ((rgba.getUint8(offset) - channels[0]).abs() <= 3 &&
            (rgba.getUint8(offset + 1) - channels[1]).abs() <= 3 &&
            (rgba.getUint8(offset + 2) - channels[2]).abs() <= 3 &&
            ++matches >= 12) {
          return true;
        }
      }
    }
    return false;
  } finally {
    image.dispose();
  }
}
