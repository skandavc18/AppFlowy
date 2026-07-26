import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/custom_image_cache_manager.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:string_validator/string_validator.dart';

/// Where an editable picture comes from and how to reach its bytes.
class ImageEditorSource {
  const ImageEditorSource({
    required this.url,
    required this.type,
    this.userProfile,
  });

  final String url;
  final CustomImageType type;
  final UserProfilePB? userProfile;

  bool get isRemote => isURL(url);

  Future<Uint8List> readBytes() async {
    if (!isRemote) {
      return File(url).readAsBytes();
    }
    // The cache manager already knows how to authenticate against the
    // workspace host and reuses whatever the block just displayed.
    final file = await CustomImageCacheManager().getSingleFile(
      url,
      headers: _authHeaders(),
    );
    return file.readAsBytes();
  }

  Map<String, String> _authHeaders() {
    final token = userProfile?.token;
    if (token == null || token.isEmpty) {
      return const {};
    }
    try {
      final decoded = jsonDecode(token);
      return {'Authorization': 'Bearer ${decoded['access_token']}'};
    } catch (e) {
      Log.error('Unable to decode token for the image editor: $e');
      return const {};
    }
  }
}

/// Decodes [bytes] into a GPU-backed image the editor can paint repeatedly.
Future<ui.Image> decodeEditableImage(Uint8List bytes) async {
  final codec = await ui.instantiateImageCodec(bytes);
  try {
    final frame = await codec.getNextFrame();
    return frame.image;
  } finally {
    codec.dispose();
  }
}

/// Reads the encoded format straight from the payload's magic number, which is
/// the only reliable signal: workspace URLs are often extension-less.
String? sniffImageFormat(Uint8List bytes) {
  if (bytes.length >= 4 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return 'png';
  }
  if (bytes.length >= 3 &&
      bytes[0] == 0xFF &&
      bytes[1] == 0xD8 &&
      bytes[2] == 0xFF) {
    return 'jpeg';
  }
  if (bytes.length >= 4 &&
      bytes[0] == 0x47 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x38) {
    return 'gif';
  }
  return null;
}

/// The file extension that matches a [sniffImageFormat] result.
String imageExtensionFor(String? format) => switch (format) {
      'jpeg' => 'jpg',
      'gif' => 'gif',
      _ => 'png',
    };

/// Bytes the system clipboard accepts. PNG, JPEG and GIF are handed over
/// untouched; anything else (WebP, BMP, HEIC…) is decoded and re-encoded.
Future<(String format, Uint8List bytes)> encodeForClipboard(
  Uint8List bytes,
) async {
  final format = sniffImageFormat(bytes);
  if (format != null) {
    return (format, bytes);
  }

  final image = await decodeEditableImage(bytes);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) {
      throw StateError('Unable to encode the image for the clipboard');
    }
    return ('png', data.buffer.asUint8List());
  } finally {
    image.dispose();
  }
}
