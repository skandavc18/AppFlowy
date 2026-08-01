import 'dart:typed_data';

import 'package:appflowy/workspace/application/collections/album/photo_exif.dart';
import 'package:flutter_test/flutter_test.dart';

/// One EXIF value, already encoded in the target byte order.
class _Entry {
  _Entry(this.tag, this.type, this.count, this.payload);

  final int tag;
  final int type;
  final int count;
  final Uint8List payload;

  bool get isInline => payload.length <= 4;
}

class _Ifd {
  final List<_Entry> entries = [];

  int get byteLength => 2 + entries.length * 12 + 4;

  void ascii(int tag, String value) {
    final bytes = Uint8List.fromList([...value.codeUnits, 0]);
    entries.add(_Entry(tag, 2, bytes.length, bytes));
  }

  void short(int tag, int value, Endian endian) {
    final bytes = ByteData(2)..setUint16(0, value, endian);
    entries.add(_Entry(tag, 3, 1, bytes.buffer.asUint8List()));
  }

  void long(int tag, int value, Endian endian) {
    final bytes = ByteData(4)..setUint32(0, value, endian);
    entries.add(_Entry(tag, 4, 1, bytes.buffer.asUint8List()));
  }

  void rationals(int tag, List<List<int>> values, Endian endian) {
    final bytes = ByteData(values.length * 8);
    for (var index = 0; index < values.length; index++) {
      bytes.setUint32(index * 8, values[index][0], endian);
      bytes.setUint32(index * 8 + 4, values[index][1], endian);
    }
    entries.add(_Entry(tag, 5, values.length, bytes.buffer.asUint8List()));
  }
}

/// Lays out a real TIFF/EXIF block so the reader is tested against the format
/// rather than against a fixture nobody can check.
Uint8List _buildTiff({required Endian endian, required bool withGps}) {
  const exifPointerTag = 0x8769;
  const gpsPointerTag = 0x8825;

  final root = _Ifd()
    ..ascii(0x010F, 'Canon')
    ..ascii(0x0110, 'Canon EOS R6')
    ..short(0x0112, 6, endian);
  final exif = _Ifd()
    ..rationals(
      0x829A,
      [
        [1, 250],
      ],
      endian,
    )
    ..rationals(
      0x829D,
      [
        [28, 10],
      ],
      endian,
    )
    ..short(0x8827, 400, endian)
    ..ascii(0x9003, '2026:07:31 21:04:11')
    ..rationals(
      0x920A,
      [
        [50, 1],
      ],
      endian,
    )
    ..long(0xA002, 6000, endian)
    ..long(0xA003, 4000, endian)
    ..ascii(0xA434, 'RF24-70mm F2.8 L IS USM');
  final gps = _Ifd();
  if (withGps) {
    gps
      ..ascii(0x0001, 'N')
      ..rationals(
        0x0002,
        [
          [51, 1],
          [30, 1],
          [0, 1],
        ],
        endian,
      )
      ..ascii(0x0003, 'W')
      ..rationals(
        0x0004,
        [
          [0, 1],
          [7, 1],
          [3900, 100],
        ],
        endian,
      );
  }

  // The pointers must exist before offsets are known, so they are reserved
  // now and filled in once the layout is decided.
  root
    ..long(exifPointerTag, 0, endian)
    ..long(gpsPointerTag, 0, endian);

  const headerLength = 8;
  final rootOffset = headerLength;
  final exifOffset = rootOffset + root.byteLength;
  final gpsOffset = exifOffset + exif.byteLength;
  var dataCursor = gpsOffset + (withGps ? gps.byteLength : 0);

  final overflow = <_Entry, int>{};
  for (final ifd in [root, exif, if (withGps) gps]) {
    for (final entry in ifd.entries) {
      if (!entry.isInline) {
        overflow[entry] = dataCursor;
        dataCursor +=
            entry.payload.length + (entry.payload.length.isOdd ? 1 : 0);
      }
    }
  }

  final buffer = Uint8List(dataCursor);
  final data = ByteData.sublistView(buffer);
  // The byte order mark itself is always read big endian.
  data.setUint16(0, endian == Endian.little ? 0x4949 : 0x4D4D);
  data.setUint16(2, 42, endian);
  data.setUint32(4, rootOffset, endian);

  void writeIfd(_Ifd ifd, int offset) {
    data.setUint16(offset, ifd.entries.length, endian);
    for (var index = 0; index < ifd.entries.length; index++) {
      final entry = ifd.entries[index];
      final at = offset + 2 + index * 12;
      data.setUint16(at, entry.tag, endian);
      data.setUint16(at + 2, entry.type, endian);
      data.setUint32(at + 4, entry.count, endian);
      if (entry.tag == exifPointerTag) {
        data.setUint32(at + 8, exifOffset, endian);
      } else if (entry.tag == gpsPointerTag) {
        data.setUint32(at + 8, gpsOffset, endian);
      } else if (entry.isInline) {
        buffer.setRange(at + 8, at + 8 + entry.payload.length, entry.payload);
      } else {
        final target = overflow[entry]!;
        data.setUint32(at + 8, target, endian);
        buffer.setRange(
          target,
          target + entry.payload.length,
          entry.payload,
        );
      }
    }
    data.setUint32(offset + 2 + ifd.entries.length * 12, 0, endian);
  }

  writeIfd(root, rootOffset);
  writeIfd(exif, exifOffset);
  if (withGps) {
    writeIfd(gps, gpsOffset);
  }
  return buffer;
}

Uint8List _wrapInJpeg(Uint8List tiff) {
  final payload = <int>[0x45, 0x78, 0x69, 0x66, 0x00, 0x00, ...tiff];
  final length = payload.length + 2;
  return Uint8List.fromList([
    0xFF, 0xD8, // SOI
    0xFF, 0xE1, // APP1
    (length >> 8) & 0xFF, length & 0xFF,
    ...payload,
    0xFF, 0xDA, // SOS
  ]);
}

Uint8List _wrapInPng(Uint8List tiff) {
  final chunk = <int>[
    (tiff.length >> 24) & 0xFF,
    (tiff.length >> 16) & 0xFF,
    (tiff.length >> 8) & 0xFF,
    tiff.length & 0xFF,
    ...'eXIf'.codeUnits,
    ...tiff,
    0, 0, 0, 0, // CRC, unchecked by the reader
  ];
  return Uint8List.fromList([
    0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,
    ...chunk,
    0, 0, 0, 0, ...'IEND'.codeUnits, 0, 0, 0, 0,
  ]);
}

void main() {
  group('exif reader', () {
    test('reads camera, exposure and dimensions out of a JPEG', () {
      final exif = readPhotoExif(
        _wrapInJpeg(_buildTiff(endian: Endian.little, withGps: false)),
      );

      expect(exif.make, 'Canon');
      expect(exif.model, 'Canon EOS R6');
      expect(exif.lens, 'RF24-70mm F2.8 L IS USM');
      expect(exif.iso, 400);
      expect(exif.fNumber, closeTo(2.8, 0.001));
      expect(exif.exposureSeconds, closeTo(1 / 250, 0.00001));
      expect(exif.focalLength, closeTo(50, 0.001));
      expect(exif.pixelWidth, 6000);
      expect(exif.pixelHeight, 4000);
      expect(exif.orientation, 6);
      expect(exif.isQuarterTurned, isTrue);
      expect(exif.takenAt, DateTime(2026, 7, 31, 21, 4, 11));
      expect(exif.hasLocation, isFalse);
      expect(exif.isEmpty, isFalse);
    });

    test('reads the same values from a big endian block', () {
      final exif = readPhotoExif(
        _wrapInJpeg(_buildTiff(endian: Endian.big, withGps: false)),
      );

      expect(exif.model, 'Canon EOS R6');
      expect(exif.iso, 400);
      expect(exif.pixelWidth, 6000);
    });

    test('reads an EXIF chunk out of a PNG', () {
      final exif = readPhotoExif(
        _wrapInPng(_buildTiff(endian: Endian.little, withGps: false)),
      );

      expect(exif.model, 'Canon EOS R6');
      expect(exif.focalLength, closeTo(50, 0.001));
    });

    test('turns GPS degrees, minutes and seconds into a signed coordinate',
        () {
      final exif = readPhotoExif(
        _wrapInJpeg(_buildTiff(endian: Endian.little, withGps: true)),
      );

      expect(exif.hasLocation, isTrue);
      expect(exif.latitude, closeTo(51.5, 0.0001));
      // 0° 7' 39" west of Greenwich, so negative.
      expect(exif.longitude, closeTo(-0.1275, 0.0001));
    });

    test('returns nothing rather than guessing at unknown bytes', () {
      expect(readPhotoExif(Uint8List(0)).isEmpty, isTrue);
      expect(readPhotoExif(Uint8List.fromList([1, 2, 3, 4])).isEmpty, isTrue);
      expect(
        readPhotoExif(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDA])).isEmpty,
        isTrue,
      );
      expect(readPhotoExif(Uint8List(64)).isEmpty, isTrue);
    });

    test('reads a bare TIFF with no container around it', () {
      final exif =
          readPhotoExif(_buildTiff(endian: Endian.little, withGps: false));

      expect(exif.make, 'Canon');
    });
  });

  group('exif labels', () {
    test('name the settings the way a photographer would', () {
      const exif = PhotoExif(
        make: 'Canon',
        model: 'Canon EOS R6',
        exposureSeconds: 1 / 250,
        fNumber: 2.8,
        iso: 400,
        focalLength: 50,
      );

      expect(exif.cameraName, 'Canon EOS R6');
      expect(exif.exposureLabel, '1/250 s');
      expect(exif.apertureLabel, 'f/2.8');
      expect(exif.focalLengthLabel, '50 mm');
      expect(exif.isoLabel, 'ISO 400');
      expect(exif.exposureSummary, '50 mm  ·  f/2.8  ·  1/250 s  ·  ISO 400');
    });

    test('long exposures are spelled out in seconds', () {
      expect(const PhotoExif(exposureSeconds: 2.5).exposureLabel, '2.5 s');
      expect(const PhotoExif(exposureSeconds: 30).exposureLabel, '30 s');
      expect(const PhotoExif(exposureSeconds: 0).exposureLabel, isNull);
    });

    test('a maker that is not already in the model is prefixed', () {
      expect(
        const PhotoExif(make: 'NIKON', model: 'Z 6').cameraName,
        'NIKON Z 6',
      );
      expect(const PhotoExif(make: 'Apple').cameraName, 'Apple');
      expect(const PhotoExif().cameraName, isNull);
      expect(const PhotoExif().exposureSummary, isNull);
    });
  });
}
