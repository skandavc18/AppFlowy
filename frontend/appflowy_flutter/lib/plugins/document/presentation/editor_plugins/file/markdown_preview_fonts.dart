import 'dart:convert';

import 'package:flutter/services.dart';

/// The application's own faces, inlined so a WebView preview reads in the same
/// type as the pages around it.
///
/// A WebView cannot reach Flutter's asset bundle by path, so the only way to
/// give a preview the app's typography is to hand it the font itself. Both
/// files are variable, so one face covers every weight.
const _uiFontAsset = 'assets/google_fonts/DM_Sans/DMSans-Variable.ttf';
const _uiItalicFontAsset =
    'assets/google_fonts/DM_Sans/DMSans-VariableItalic.ttf';
const _codeFontAsset = 'assets/google_fonts/Roboto_Mono/RobotoMono-Regular.ttf';

/// The CSS family names the preview stylesheet asks for.
const previewUiFontFamily = 'AppFlowy Sans';
const previewCodeFontFamily = 'AppFlowy Mono';

String? _faces;
Future<String>? _loading;

/// The `@font-face` block, once it has been read. Null until then, so the
/// first paint falls back to the system stack rather than blocking on IO.
String? get markdownPreviewFontFaces => _faces;

/// Reads the faces once and remembers them for every later preview.
Future<String> loadMarkdownPreviewFontFaces() {
  final cached = _faces;
  if (cached != null) {
    return Future.value(cached);
  }
  return _loading ??= _read();
}

Future<String> _read() async {
  try {
    final faces = await Future.wait([
      _face(previewUiFontFamily, _uiFontAsset, italic: false, variable: true),
      _face(
        previewUiFontFamily,
        _uiItalicFontAsset,
        italic: true,
        variable: true,
      ),
      _face(previewCodeFontFamily, _codeFontAsset, italic: false),
    ]);
    return _faces = faces.join('\n');
  } on Object {
    // A preview without the bundled face still reads; it just falls back.
    return _faces = '';
  }
}

Future<String> _face(
  String family,
  String asset, {
  required bool italic,
  bool variable = false,
}) async {
  final bytes = await rootBundle.load(asset);
  final data = base64Encode(bytes.buffer.asUint8List());
  return '''
  @font-face {
    font-family: "$family";
    font-style: ${italic ? 'italic' : 'normal'};
    font-weight: ${variable ? '100 1000' : '400'};
    font-display: block;
    src: url(data:font/ttf;base64,$data) format("truetype");
  }''';
}
