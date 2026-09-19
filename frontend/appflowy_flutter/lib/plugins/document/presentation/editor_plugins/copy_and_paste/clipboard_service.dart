import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:super_clipboard/super_clipboard.dart';

/// Used for in-app copy and paste without losing the format.
///
/// It's a Json string representing the copied editor nodes.
const inAppJsonFormat = CustomValueFormat<String>(
  applicationId: 'io.appflowy.InAppJsonType',
  onDecode: _defaultDecode,
  onEncode: _defaultEncode,
);

/// Used for table nodes when coping a row or a column.
const tableJsonFormat = CustomValueFormat<String>(
  applicationId: 'io.appflowy.TableJsonType',
  onDecode: _defaultDecode,
  onEncode: _defaultEncode,
);

class ClipboardServiceData {
  const ClipboardServiceData({
    this.plainText,
    this.html,
    this.image,
    this.inAppJson,
    this.tableJson,
    this.files = const [],
  });

  /// The [plainText] is the plain text string.
  ///
  /// It should be used for pasting the plain text from the clipboard.
  final String? plainText;

  /// The [html] is the html string.
  ///
  /// It should be used for pasting the html from the clipboard.
  /// For example, copy the content in the browser, and paste it in the editor.
  final String? html;

  /// The [image] is the image data.
  ///
  /// It should be used for pasting the image from the clipboard.
  /// For example, copy the image in the browser or other apps, and paste it in the editor.
  final (String, Uint8List?)? image;

  /// The [inAppJson] is the json string of the editor nodes.
  ///
  /// It should be used for pasting the content in-app.
  /// For example, pasting the content from document A to document B.
  final String? inAppJson;

  /// The [tableJson] is the json string of the table nodes.
  ///
  /// It only works for the table nodes when coping a row or a column.
  /// Don't use it for another scenario.
  final String? tableJson;

  /// Native file URIs in clipboard item order, never inferred from text or URLs.
  final List<Uri> files;
}

class ClipboardService {
  ClipboardService({
    Future<ClipboardReader?> Function() readClipboard = _readSystemClipboard,
  }) : _readClipboard = readClipboard;

  final Future<ClipboardReader?> Function() _readClipboard;

  static ClipboardServiceData? _mockData;

  @visibleForTesting
  static void mockSetData(ClipboardServiceData? data) {
    _mockData = data;
  }

  Future<void> setData(ClipboardServiceData data) async {
    final plainText = data.plainText;
    final html = data.html;
    final inAppJson = data.inAppJson;
    final image = data.image;
    final tableJson = data.tableJson;

    final item = DataWriterItem();
    if (plainText != null) {
      item.add(Formats.plainText(plainText));
    }
    if (html != null) {
      item.add(Formats.htmlText(html));
    }
    if (inAppJson != null) {
      item.add(inAppJsonFormat(inAppJson));
    }
    if (tableJson != null) {
      item.add(tableJsonFormat(tableJson));
    }
    if (image != null && image.$2?.isNotEmpty == true) {
      switch (image.$1) {
        case 'png':
          item.add(Formats.png(image.$2!));
          break;
        case 'jpeg':
          item.add(Formats.jpeg(image.$2!));
          break;
        case 'gif':
          item.add(Formats.gif(image.$2!));
          break;
        default:
          throw Exception('unsupported image format: ${image.$1}');
      }
    }
    await SystemClipboard.instance?.write([item]);
  }

  Future<void> setPlainText(String text) async {
    await SystemClipboard.instance?.write([
      DataWriterItem()..add(Formats.plainText(text)),
    ]);
  }

  Future<ClipboardServiceData> getData() async {
    if (_mockData != null) {
      return _mockData!;
    }

    ClipboardReader? reader;
    try {
      reader = await _readClipboard();
    } catch (_) {
      return const ClipboardServiceData();
    }

    if (reader == null) {
      return const ClipboardServiceData();
    }

    final files = <Uri>[];
    for (final item in reader.items) {
      final uri = await item.readValueSafely(Formats.fileUri);
      if (uri != null && _isUsableFileUri(uri)) {
        files.add(uri);
      }
    }

    final plainText = await _readFirstValue(reader, Formats.plainText);
    final html = await _readFirstValue(reader, Formats.htmlText);
    final inAppJson = await _readFirstValue(reader, inAppJsonFormat);
    final tableJson = await _readFirstValue(reader, tableJsonFormat);
    final uri = await _readFirstValue(reader, Formats.uri);
    // File URIs can advertise synthesized raster formats. Avoid reading the
    // original file a second time (or converting it) when its URI is usable.
    final image = files.isEmpty ? await _readImage(reader) : null;

    return ClipboardServiceData(
      plainText: plainText ?? uri?.uri.toString(),
      html: html,
      image: image,
      inAppJson: inAppJson,
      tableJson: tableJson,
      files: List<Uri>.unmodifiable(files),
    );
  }
}

Future<ClipboardReader?> _readSystemClipboard() async =>
    SystemClipboard.instance?.read();

bool _isUsableFileUri(Uri uri) {
  if (!uri.isScheme('file') || !uri.hasAbsolutePath) {
    return false;
  }
  try {
    final path = uri.toFilePath(
      windows: defaultTargetPlatform == TargetPlatform.windows,
    );
    return path.isNotEmpty && !path.contains('\u0000');
  } catch (_) {
    return false;
  }
}

Future<T?> _readFirstValue<T extends Object>(
  ClipboardReader reader,
  ValueFormat<T> format,
) async {
  for (final item in reader.items) {
    final value = await item.readValueSafely(format);
    if (value != null) {
      return value;
    }
  }
  return null;
}

Future<(String, Uint8List?)?> _readImage(ClipboardReader reader) async {
  for (final (extension, format) in [
    ('png', Formats.png),
    ('jpeg', Formats.jpeg),
    ('gif', Formats.gif),
    ('webp', Formats.webp),
  ]) {
    for (final item in reader.items) {
      try {
        if (item.canProvide(format)) {
          final bytes = await item.readFile(format);
          if (bytes != null && bytes.isNotEmpty) {
            return (extension, bytes);
          }
        }
      } catch (_) {
        // An advertised representation may be unavailable. Try the next one
        // without logging clipboard contents or platform exception details.
      }
    }
  }
  return null;
}

extension on ClipboardDataReader {
  Future<T?> readValueSafely<T extends Object>(ValueFormat<T> format) async {
    try {
      return canProvide(format) ? await readValue(format) : null;
    } catch (_) {
      // Optional or malformed representations must not block other formats.
      return null;
    }
  }

  Future<Uint8List?> readFile(FileFormat format) {
    final c = Completer<Uint8List?>();
    final progress = getFile(
      format,
      (file) async {
        try {
          final all = await file.readAll();
          c.complete(all);
        } catch (e) {
          c.completeError(e);
        }
      },
      onError: (e) {
        c.completeError(e);
      },
      // Still allow native bitmap conversion (e.g. Windows DIB to PNG), but
      // never retry a missing or malformed URI through filesystem synthesis.
      synthesizeFilesFromURIs: false,
    );
    if (progress == null) {
      c.complete(null);
    }
    return c.future;
  }
}

/// The default decode function for the clipboard service.
Future<String?> _defaultDecode(Object value, String platformType) async {
  if (value is PlatformDataProvider) {
    final data = await value.getData(platformType);
    if (data is List<int>) {
      return utf8.decode(data, allowMalformed: true);
    }
    if (data is String) {
      return Uri.decodeFull(data);
    }
  }
  return null;
}

/// The default encode function for the clipboard service.
Future<Object> _defaultEncode(String value, String platformType) async {
  return utf8.encode(value);
}
