import 'package:flutter/foundation.dart';

@immutable
class ImageHeaderSize {
  const ImageHeaderSize(this.width, this.height);

  final int width;
  final int height;

  double get aspectRatio => height == 0 ? 1 : width / height;
}

/// The pixel size of an encoded picture, read from its header alone.
///
/// A masonry wall needs every picture's shape before any of them is decoded,
/// and decoding a wall of 40 megapixel photographs to find out costs hundreds
/// of megabytes. Every format here states its size within the first few
/// hundred bytes, so a small prefix of the file is enough.
ImageHeaderSize? readImageHeaderSize(Uint8List bytes) {
  if (bytes.length < 16) {
    return null;
  }
  try {
    return _png(bytes) ?? _gif(bytes) ?? _webp(bytes) ?? _bmp(bytes) ??
        _jpeg(bytes);
  } on Object {
    return null;
  }
}

ImageHeaderSize? _png(Uint8List bytes) {
  if (bytes[0] != 0x89 ||
      bytes[1] != 0x50 ||
      bytes[2] != 0x4E ||
      bytes[3] != 0x47) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  return ImageHeaderSize(data.getUint32(16), data.getUint32(20));
}

ImageHeaderSize? _gif(Uint8List bytes) {
  if (bytes[0] != 0x47 || bytes[1] != 0x49 || bytes[2] != 0x46) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  return ImageHeaderSize(
    data.getUint16(6, Endian.little),
    data.getUint16(8, Endian.little),
  );
}

ImageHeaderSize? _webp(Uint8List bytes) {
  if (bytes.length < 30 ||
      String.fromCharCodes(bytes, 0, 4) != 'RIFF' ||
      String.fromCharCodes(bytes, 8, 12) != 'WEBP') {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  final chunk = String.fromCharCodes(bytes, 12, 16);
  switch (chunk) {
    case 'VP8 ':
      return ImageHeaderSize(
        data.getUint16(26, Endian.little) & 0x3FFF,
        data.getUint16(28, Endian.little) & 0x3FFF,
      );
    case 'VP8L':
      final bits = data.getUint32(21, Endian.little);
      return ImageHeaderSize((bits & 0x3FFF) + 1, ((bits >> 14) & 0x3FFF) + 1);
    case 'VP8X':
      final width = bytes[24] | bytes[25] << 8 | bytes[26] << 16;
      final height = bytes[27] | bytes[28] << 8 | bytes[29] << 16;
      return ImageHeaderSize(width + 1, height + 1);
    default:
      return null;
  }
}

ImageHeaderSize? _bmp(Uint8List bytes) {
  if (bytes.length < 26 || bytes[0] != 0x42 || bytes[1] != 0x4D) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  return ImageHeaderSize(
    data.getInt32(18, Endian.little).abs(),
    data.getInt32(22, Endian.little).abs(),
  );
}

ImageHeaderSize? _jpeg(Uint8List bytes) {
  if (bytes[0] != 0xFF || bytes[1] != 0xD8) {
    return null;
  }
  final data = ByteData.sublistView(bytes);
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) {
      return null;
    }
    final marker = bytes[offset + 1];
    // Start of scan, or end of image: no frame header was found.
    if (marker == 0xDA || marker == 0xD9) {
      return null;
    }
    final length = data.getUint16(offset + 2);
    if (length < 2) {
      return null;
    }
    // SOF0..SOF15, minus the tables that share the range.
    final isFrameHeader = marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC;
    if (isFrameHeader) {
      if (offset + 9 > bytes.length) {
        return null;
      }
      return ImageHeaderSize(
        data.getUint16(offset + 7),
        data.getUint16(offset + 5),
      );
    }
    offset += 2 + length;
  }
  return null;
}
