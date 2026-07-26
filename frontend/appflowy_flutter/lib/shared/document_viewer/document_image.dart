import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;

/// A resolved document image, ready to paint.
@immutable
sealed class DocumentImageData {
  const DocumentImageData();

  /// Intrinsic size in logical pixels, when it could be determined.
  Size? get intrinsicSize;
}

/// A decodable bitmap, already measured and ready to paint.
class DocumentRasterImage extends DocumentImageData {
  const DocumentRasterImage(this.provider, this.intrinsicSize);

  final ImageProvider provider;

  @override
  final Size intrinsicSize;
}

/// A vector image. Badges and shields are almost always SVG.
class DocumentVectorImage extends DocumentImageData {
  const DocumentVectorImage(this.bytes, this.intrinsicSize);

  final Uint8List bytes;

  @override
  final Size? intrinsicSize;
}

/// Loads document images, deciding between raster and vector by content.
///
/// Sniffing matters because badge services such as `img.shields.io` serve SVG
/// from extension-less URLs; guessing from the path alone leaves every badge
/// in a document broken.
abstract final class DocumentImageLoader {
  /// Refuses documents that would blow up memory before they are decoded.
  static const int maxImageBytes = 24 * 1024 * 1024;

  /// Widest bitmap kept in memory, in device pixels.
  ///
  /// README-scale artwork is routinely 4000px wide while the reading column is
  /// 720. Decoding at full resolution costs tens of megabytes per image and
  /// stalls the raster thread, which is felt immediately as scroll stutter.
  static const int maxDecodeWidth = 1600;

  /// Enough of the head to find the SVG root element.
  static const int _sniffLength = 1024;

  static final Map<String, Future<DocumentImageData>> _cache = {};

  /// Bounded so a long document with many images cannot grow without limit.
  static const int _maxCacheEntries = 128;

  @visibleForTesting
  static http.Client Function() clientFactory = http.Client.new;

  /// Resolves [source], reusing an in-flight or completed load.
  static Future<DocumentImageData> load(String source) {
    final cached = _cache[source];
    if (cached != null) {
      return cached;
    }
    if (_cache.length >= _maxCacheEntries) {
      _cache.remove(_cache.keys.first);
    }
    final pending = _load(source);
    _cache[source] = pending;
    // Failures are evicted so a dropped connection does not leave the image
    // broken for the rest of the session. The original future still carries
    // the error to whoever is waiting on it.
    unawaited(
      pending.then(
        (_) {},
        onError: (Object _, StackTrace __) {
          if (identical(_cache[source], pending)) {
            _cache.remove(source);
          }
        },
      ),
    );
    return pending;
  }

  @visibleForTesting
  static void clearCache() => _cache.clear();

  static Future<DocumentImageData> _load(String source) async {
    final uri = Uri.tryParse(source);
    if (uri == null) {
      throw const FormatException('Unsupported image source.');
    }

    return switch (uri.scheme) {
      'file' => await _fromBytes(await _readFile(uri), null),
      'data' => await _fromBytes(_decodeData(source), _dataMimeType(source)),
      'http' || 'https' => await _fromNetwork(uri),
      _ => throw const FormatException('Unsupported image source.'),
    };
  }

  static Future<Uint8List> _readFile(Uri uri) async {
    final file = File.fromUri(uri);
    final length = await file.length();
    if (length > maxImageBytes) {
      throw const FileSystemException('This image is too large to display.');
    }
    return file.readAsBytes();
  }

  static Uint8List _decodeData(String source) {
    final separator = source.indexOf(',');
    if (separator < 0) {
      throw const FormatException('Malformed data image.');
    }
    return base64Decode(source.substring(separator + 1));
  }

  static String? _dataMimeType(String source) {
    final separator = source.indexOf(',');
    if (separator < 0) {
      return null;
    }
    return source.substring('data:'.length, separator).split(';').first;
  }

  static Future<DocumentImageData> _fromNetwork(Uri uri) async {
    final client = clientFactory();
    try {
      final response = await client.get(
        uri,
        headers: const {'Accept': 'image/*,*/*;q=0.8'},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'The image responded with ${response.statusCode}.',
          uri: uri,
        );
      }
      if (response.bodyBytes.length > maxImageBytes) {
        throw HttpException('This image is too large to display.', uri: uri);
      }
      return _fromBytes(
        response.bodyBytes,
        response.headers['content-type'],
      );
    } finally {
      client.close();
    }
  }

  static Future<DocumentImageData> _fromBytes(
    Uint8List bytes,
    String? contentType,
  ) async {
    if (bytes.isEmpty) {
      throw const FormatException('The image is empty.');
    }
    if (looksLikeHtml(bytes, contentType)) {
      throw const FormatException('The response is a web page, not an image.');
    }
    if (looksLikeSvg(bytes, contentType)) {
      return DocumentVectorImage(bytes, readSvgSize(bytes));
    }

    // Measuring here keeps the widget tree pure: the renderer always knows the
    // exact size before its first layout, so nothing shifts once a bitmap
    // arrives and no decode failure can escape into the widget tree.
    final size = await readRasterSize(bytes);
    final scale = size.width > maxDecodeWidth ? maxDecodeWidth / size.width : 1;
    final provider = scale == 1
        ? MemoryImage(bytes)
        : ResizeImage(
            MemoryImage(bytes),
            width: maxDecodeWidth,
            policy: ResizeImagePolicy.fit,
          ) as ImageProvider;
    return DocumentRasterImage(provider, size);
  }

  /// Reads a bitmap's dimensions from its header without decoding pixels.
  ///
  /// Doubles as validation: undecodable payloads throw here rather than
  /// failing later inside a paint.
  @visibleForTesting
  static Future<Size> readRasterSize(Uint8List bytes) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    final descriptor = await ui.ImageDescriptor.encoded(buffer);
    buffer.dispose();
    final size = Size(
      descriptor.width.toDouble(),
      descriptor.height.toDouble(),
    );
    descriptor.dispose();
    if (size.isEmpty) {
      throw const FormatException('The image has no dimensions.');
    }
    return size;
  }

  /// Detects a web page masquerading as an image.
  ///
  /// Sign-in walls and error pages answer image requests with HTML, and those
  /// pages frequently contain an inline `<svg>` logo — so this check runs
  /// before SVG sniffing.
  @visibleForTesting
  static bool looksLikeHtml(Uint8List bytes, String? contentType) {
    if (contentType != null &&
        contentType.toLowerCase().contains('text/html')) {
      return true;
    }
    final head = _head(bytes, 256).trimLeft().toLowerCase();
    return head.startsWith('<!doctype html') || head.startsWith('<html');
  }

  /// Detects SVG from the declared type, falling back to the document root.
  @visibleForTesting
  static bool looksLikeSvg(Uint8List bytes, String? contentType) {
    if (contentType != null &&
        contentType.toLowerCase().contains('image/svg')) {
      return true;
    }
    if (contentType != null &&
        RegExp('^image/(png|jpeg|gif|webp|bmp|avif)', caseSensitive: false)
            .hasMatch(contentType)) {
      return false;
    }
    // Only a document that *starts* as SVG counts. Merely containing an `<svg>`
    // element somewhere is what a web page looks like.
    final head = _head(bytes, _sniffLength).trimLeft().toLowerCase();
    if (head.startsWith('<svg')) {
      return true;
    }
    if (!head.startsWith('<?xml') && !head.startsWith('<!doctype svg')) {
      return false;
    }
    return head.contains('<svg');
  }

  static String _head(Uint8List bytes, int length) => latin1.decode(
        bytes.sublist(0, bytes.length.clamp(0, length)),
        allowInvalid: true,
      );

  /// Reads the intrinsic size from the SVG root, preferring the view box.
  ///
  /// Vector images have no pixel dimensions, so without this a badge would
  /// stretch to whatever space the layout happens to offer.
  @visibleForTesting
  static Size? readSvgSize(Uint8List bytes) {
    final head = latin1.decode(
      bytes.sublist(0, bytes.length.clamp(0, _sniffLength * 4)),
      allowInvalid: true,
    );
    final width = _readSvgLength(head, 'width');
    final height = _readSvgLength(head, 'height');
    if (width != null && height != null && width > 0 && height > 0) {
      return Size(width, height);
    }

    final viewBox = RegExp(
      r'viewBox\s*=\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(head);
    final numbers = viewBox?.group(1)?.trim().split(RegExp(r'[\s,]+'));
    if (numbers == null || numbers.length < 4) {
      return null;
    }
    final boxWidth = double.tryParse(numbers[2]);
    final boxHeight = double.tryParse(numbers[3]);
    if (boxWidth == null || boxHeight == null || boxHeight <= 0) {
      return null;
    }
    return Size(boxWidth, boxHeight);
  }

  static double? _readSvgLength(String head, String attribute) {
    final match = RegExp(
      '$attribute\\s*=\\s*"([^"]+)"',
      caseSensitive: false,
    ).firstMatch(head);
    return parseCssLength(match?.group(1));
  }
}

/// Parses `120`, `120px`, `120.5pt` and similar authored lengths.
///
/// Percentages are intentionally rejected: they describe a relationship to a
/// container the document viewer does not reproduce.
double? parseCssLength(String? value) {
  if (value == null) {
    return null;
  }
  final trimmed = value.trim();
  if (trimmed.isEmpty || trimmed.endsWith('%')) {
    return null;
  }
  final match = RegExp(r'^([0-9]*\.?[0-9]+)').firstMatch(trimmed);
  return match == null ? null : double.tryParse(match.group(1)!);
}
