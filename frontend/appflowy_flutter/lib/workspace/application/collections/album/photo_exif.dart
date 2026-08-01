import 'dart:convert';

import 'package:flutter/foundation.dart';

/// What a camera recorded alongside the picture.
///
/// Only the fields a person actually reads are kept — the rest of the EXIF
/// tree is skipped rather than modelled.
@immutable
class PhotoExif {
  const PhotoExif({
    this.make,
    this.model,
    this.lens,
    this.takenAt,
    this.exposureSeconds,
    this.fNumber,
    this.iso,
    this.focalLength,
    this.orientation,
    this.pixelWidth,
    this.pixelHeight,
    this.latitude,
    this.longitude,
    this.altitude,
  });

  static const empty = PhotoExif();

  final String? make;
  final String? model;
  final String? lens;
  final DateTime? takenAt;
  final double? exposureSeconds;
  final double? fNumber;
  final int? iso;
  final double? focalLength;

  /// The TIFF orientation tag, 1 to 8.
  final int? orientation;
  final int? pixelWidth;
  final int? pixelHeight;
  final double? latitude;
  final double? longitude;
  final double? altitude;

  bool get isEmpty =>
      make == null &&
      model == null &&
      lens == null &&
      takenAt == null &&
      exposureSeconds == null &&
      fNumber == null &&
      iso == null &&
      focalLength == null &&
      latitude == null;

  bool get hasLocation => latitude != null && longitude != null;

  bool get hasCamera => make != null || model != null;

  /// "Canon EOS R6" rather than "Canon" and "Canon EOS R6".
  String? get cameraName {
    final maker = make?.trim();
    final body = model?.trim();
    if (body == null || body.isEmpty) {
      return maker == null || maker.isEmpty ? null : maker;
    }
    if (maker == null || maker.isEmpty) {
      return body;
    }
    return body.toLowerCase().startsWith(maker.toLowerCase())
        ? body
        : '$maker $body';
  }

  /// "1/250 s" for short exposures, "2.5 s" for long ones.
  String? get exposureLabel {
    final seconds = exposureSeconds;
    if (seconds == null || seconds <= 0) {
      return null;
    }
    if (seconds >= 1) {
      final rounded = seconds.toStringAsFixed(seconds % 1 == 0 ? 0 : 1);
      return '$rounded s';
    }
    return '1/${(1 / seconds).round()} s';
  }

  String? get apertureLabel =>
      fNumber == null ? null : 'f/${_trimZeros(fNumber!)}';

  String? get focalLengthLabel =>
      focalLength == null ? null : '${_trimZeros(focalLength!)} mm';

  String? get isoLabel => iso == null ? null : 'ISO $iso';

  /// The camera settings as one line, skipping whatever was not recorded.
  String? get exposureSummary {
    final parts = [
      focalLengthLabel,
      apertureLabel,
      exposureLabel,
      isoLabel,
    ].whereType<String>().toList();
    return parts.isEmpty ? null : parts.join('  ·  ');
  }

  /// Whether the orientation tag swaps width and height.
  bool get isQuarterTurned =>
      orientation != null && orientation! >= 5 && orientation! <= 8;
}

String _trimZeros(double value) {
  final text = value.toStringAsFixed(1);
  return text.endsWith('.0') ? text.substring(0, text.length - 2) : text;
}

/// Reads the EXIF block out of an encoded picture.
///
/// Understands JPEG `APP1` and PNG `eXIf`, plus a bare TIFF header. Anything
/// else — including HEIC, whose metadata lives in an ISO container — returns
/// [PhotoExif.empty] rather than guessing.
PhotoExif readPhotoExif(Uint8List bytes) {
  try {
    final tiff = _locateTiff(bytes);
    if (tiff == null) {
      return PhotoExif.empty;
    }
    return _readTiff(bytes, tiff);
  } on Object {
    // Metadata is never worth failing a picture over.
    return PhotoExif.empty;
  }
}

/// The offset of the TIFF header inside [bytes], if there is one.
int? _locateTiff(Uint8List bytes) {
  if (bytes.length < 8) {
    return null;
  }
  if (bytes[0] == 0xFF && bytes[1] == 0xD8) {
    return _locateJpegExif(bytes);
  }
  if (bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47) {
    return _locatePngExif(bytes);
  }
  final byteOrder = bytes[0] << 8 | bytes[1];
  if (byteOrder == 0x4949 || byteOrder == 0x4D4D) {
    return 0;
  }
  return null;
}

int? _locateJpegExif(Uint8List bytes) {
  var offset = 2;
  while (offset + 4 <= bytes.length) {
    if (bytes[offset] != 0xFF) {
      return null;
    }
    final marker = bytes[offset + 1];
    // Start of scan: the entropy coded image begins, no more metadata.
    if (marker == 0xDA || marker == 0xD9) {
      return null;
    }
    final length = bytes[offset + 2] << 8 | bytes[offset + 3];
    if (length < 2) {
      return null;
    }
    if (marker == 0xE1 && offset + 4 + 6 <= bytes.length) {
      final header = bytes.sublist(offset + 4, offset + 10);
      if (header[0] == 0x45 &&
          header[1] == 0x78 &&
          header[2] == 0x69 &&
          header[3] == 0x66 &&
          header[4] == 0x00) {
        return offset + 10;
      }
    }
    offset += 2 + length;
  }
  return null;
}

int? _locatePngExif(Uint8List bytes) {
  var offset = 8;
  final data = ByteData.sublistView(bytes);
  while (offset + 8 <= bytes.length) {
    final length = data.getUint32(offset);
    final type = String.fromCharCodes(bytes, offset + 4, offset + 8);
    if (type == 'eXIf') {
      return offset + 8;
    }
    if (type == 'IDAT' || type == 'IEND') {
      return null;
    }
    offset += 12 + length;
  }
  return null;
}

PhotoExif _readTiff(Uint8List bytes, int start) {
  final data = ByteData.sublistView(bytes);
  final order = data.getUint16(start);
  if (order != 0x4949 && order != 0x4D4D) {
    return PhotoExif.empty;
  }
  final little = order == 0x4949;
  final endian = little ? Endian.little : Endian.big;
  if (data.getUint16(start + 2, endian) != 42) {
    return PhotoExif.empty;
  }

  final reader = _TiffReader(bytes, data, start, endian);
  final root = reader.readIfd(reader.uint32(start + 4));
  final exif = root[_Tags.exifPointer] != null
      ? reader.readIfd(reader.asInt(root[_Tags.exifPointer]!)!)
      : const <int, _TiffEntry>{};
  final gps = root[_Tags.gpsPointer] != null
      ? reader.readIfd(reader.asInt(root[_Tags.gpsPointer]!)!)
      : const <int, _TiffEntry>{};

  final latitude = reader.coordinate(
    gps[_Tags.gpsLatitude],
    reader.asString(gps[_Tags.gpsLatitudeRef]),
    negativeRef: 'S',
  );
  final longitude = reader.coordinate(
    gps[_Tags.gpsLongitude],
    reader.asString(gps[_Tags.gpsLongitudeRef]),
    negativeRef: 'W',
  );
  final altitude = reader.asDouble(gps[_Tags.gpsAltitude]);
  final belowSeaLevel = reader.asInt(gps[_Tags.gpsAltitudeRef]) == 1;

  return PhotoExif(
    make: reader.asString(root[_Tags.make]),
    model: reader.asString(root[_Tags.model]),
    lens: reader.asString(exif[_Tags.lensModel]),
    takenAt: _parseExifDate(
      reader.asString(exif[_Tags.dateTimeOriginal]) ??
          reader.asString(exif[_Tags.dateTimeDigitized]) ??
          reader.asString(root[_Tags.dateTime]),
    ),
    exposureSeconds: reader.asDouble(exif[_Tags.exposureTime]),
    fNumber: reader.asDouble(exif[_Tags.fNumber]),
    iso: reader.asInt(exif[_Tags.isoSpeed]),
    focalLength: reader.asDouble(exif[_Tags.focalLength]),
    orientation: reader.asInt(root[_Tags.orientation]),
    pixelWidth: reader.asInt(exif[_Tags.pixelXDimension]),
    pixelHeight: reader.asInt(exif[_Tags.pixelYDimension]),
    latitude: latitude,
    longitude: longitude,
    altitude: altitude == null
        ? null
        : belowSeaLevel
            ? -altitude
            : altitude,
  );
}

/// EXIF writes dates as `2026:07:31 21:04:11`, which is not ISO 8601.
DateTime? _parseExifDate(String? value) {
  if (value == null || value.length < 19) {
    return null;
  }
  final year = int.tryParse(value.substring(0, 4));
  final month = int.tryParse(value.substring(5, 7));
  final day = int.tryParse(value.substring(8, 10));
  final hour = int.tryParse(value.substring(11, 13));
  final minute = int.tryParse(value.substring(14, 16));
  final second = int.tryParse(value.substring(17, 19));
  if (year == null ||
      month == null ||
      day == null ||
      month < 1 ||
      month > 12 ||
      day < 1 ||
      day > 31) {
    return null;
  }
  return DateTime(year, month, day, hour ?? 0, minute ?? 0, second ?? 0);
}

@immutable
class _TiffEntry {
  const _TiffEntry({
    required this.type,
    required this.count,
    required this.valueOffset,
  });

  final int type;
  final int count;
  final int valueOffset;
}

class _TiffReader {
  _TiffReader(this.bytes, this.data, this.start, this.endian);

  final Uint8List bytes;
  final ByteData data;
  final int start;
  final Endian endian;

  static const _typeSizes = <int, int>{
    1: 1, // BYTE
    2: 1, // ASCII
    3: 2, // SHORT
    4: 4, // LONG
    5: 8, // RATIONAL
    7: 1, // UNDEFINED
    9: 4, // SLONG
    10: 8, // SRATIONAL
  };

  int uint16(int offset) => data.getUint16(offset, endian);
  int uint32(int offset) => data.getUint32(offset, endian);

  Map<int, _TiffEntry> readIfd(int ifdOffset) {
    final base = start + ifdOffset;
    if (base < 0 || base + 2 > bytes.length) {
      return const {};
    }
    final count = uint16(base);
    final entries = <int, _TiffEntry>{};
    for (var index = 0; index < count; index++) {
      final entry = base + 2 + index * 12;
      if (entry + 12 > bytes.length) {
        break;
      }
      entries[uint16(entry)] = _TiffEntry(
        type: uint16(entry + 2),
        count: uint32(entry + 4),
        valueOffset: entry + 8,
      );
    }
    return entries;
  }

  /// Values of four bytes or fewer are stored inline; anything larger is a
  /// pointer relative to the TIFF header.
  int? _dataOffset(_TiffEntry entry) {
    final size = _typeSizes[entry.type];
    if (size == null) {
      return null;
    }
    final total = size * entry.count;
    if (total <= 4) {
      return entry.valueOffset;
    }
    final offset = start + uint32(entry.valueOffset);
    return offset + total > bytes.length ? null : offset;
  }

  String? asString(_TiffEntry? entry) {
    if (entry == null || entry.type != 2 || entry.count == 0) {
      return null;
    }
    final offset = _dataOffset(entry);
    if (offset == null) {
      return null;
    }
    final end = (offset + entry.count).clamp(0, bytes.length);
    final raw = bytes.sublist(offset, end);
    final terminator = raw.indexOf(0);
    final text = const AsciiDecoder(allowInvalid: true)
        .convert(terminator < 0 ? raw : raw.sublist(0, terminator))
        .trim();
    return text.isEmpty ? null : text;
  }

  int? asInt(_TiffEntry? entry) {
    if (entry == null) {
      return null;
    }
    final offset = _dataOffset(entry);
    if (offset == null) {
      return null;
    }
    return switch (entry.type) {
      1 || 7 => bytes[offset],
      3 => uint16(offset),
      4 => uint32(offset),
      9 => data.getInt32(offset, endian),
      5 || 10 => asDouble(entry)?.round(),
      _ => null,
    };
  }

  double? asDouble(_TiffEntry? entry) {
    if (entry == null) {
      return null;
    }
    final offset = _dataOffset(entry);
    if (offset == null) {
      return null;
    }
    if (entry.type == 5 || entry.type == 10) {
      return _rationalAt(offset, signed: entry.type == 10);
    }
    return asInt(entry)?.toDouble();
  }

  double? _rationalAt(int offset, {required bool signed}) {
    if (offset + 8 > bytes.length) {
      return null;
    }
    final numerator = signed
        ? data.getInt32(offset, endian)
        : data.getUint32(offset, endian);
    final denominator = signed
        ? data.getInt32(offset + 4, endian)
        : data.getUint32(offset + 4, endian);
    if (denominator == 0) {
      return null;
    }
    return numerator / denominator;
  }

  /// GPS coordinates are stored as three rationals — degrees, minutes and
  /// seconds — with the hemisphere in a separate reference tag.
  double? coordinate(
    _TiffEntry? entry,
    String? reference, {
    required String negativeRef,
  }) {
    if (entry == null || entry.count < 3 || entry.type != 5) {
      return null;
    }
    final offset = _dataOffset(entry);
    if (offset == null) {
      return null;
    }
    final degrees = _rationalAt(offset, signed: false);
    final minutes = _rationalAt(offset + 8, signed: false);
    final seconds = _rationalAt(offset + 16, signed: false);
    if (degrees == null || minutes == null || seconds == null) {
      return null;
    }
    final value = degrees + minutes / 60 + seconds / 3600;
    if (value.isNaN || value.abs() > 180) {
      return null;
    }
    return reference?.toUpperCase() == negativeRef ? -value : value;
  }
}

abstract final class _Tags {
  static const make = 0x010F;
  static const model = 0x0110;
  static const orientation = 0x0112;
  static const dateTime = 0x0132;
  static const exifPointer = 0x8769;
  static const gpsPointer = 0x8825;

  static const exposureTime = 0x829A;
  static const fNumber = 0x829D;
  static const isoSpeed = 0x8827;
  static const dateTimeOriginal = 0x9003;
  static const dateTimeDigitized = 0x9004;
  static const focalLength = 0x920A;
  static const pixelXDimension = 0xA002;
  static const pixelYDimension = 0xA003;
  static const lensModel = 0xA434;

  static const gpsLatitudeRef = 0x0001;
  static const gpsLatitude = 0x0002;
  static const gpsLongitudeRef = 0x0003;
  static const gpsLongitude = 0x0004;
  static const gpsAltitudeRef = 0x0005;
  static const gpsAltitude = 0x0006;
}
