import 'dart:io';

import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/image_header.dart';
import 'package:appflowy/workspace/application/collections/album/photo_exif.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:flutter/foundation.dart';

/// What could be learned about one piece of media without decoding it.
@immutable
class AlbumMediaMetadata {
  const AlbumMediaMetadata({
    this.exif = PhotoExif.empty,
    this.pixelSize,
    this.capturedAt,
    this.byteSize,
    this.failed = false,
  });

  static const pending = AlbumMediaMetadata();

  /// The shape a picture is assumed to have until its header has been read.
  static const defaultAspectRatio = 3 / 2;

  final PhotoExif exif;
  final ImageHeaderSize? pixelSize;
  final DateTime? capturedAt;
  final int? byteSize;
  final bool failed;

  bool get isResolved => pixelSize != null || failed || !exif.isEmpty;

  /// Width over height, with the camera's own rotation applied.
  double get aspectRatio {
    final size = pixelSize;
    if (size == null || size.width <= 0 || size.height <= 0) {
      return defaultAspectRatio;
    }
    final ratio = size.aspectRatio;
    return exif.isQuarterTurned ? 1 / ratio : ratio;
  }

  String? get dimensionsLabel {
    final size = pixelSize;
    if (size == null) {
      return null;
    }
    return exif.isQuarterTurned
        ? '${size.height} × ${size.width}'
        : '${size.width} × ${size.height}';
  }
}

/// Reads media metadata once and remembers it.
///
/// Only the head of each file is read: every format states its size and its
/// EXIF block within the first few hundred kilobytes, and a wall of forty
/// megapixel photographs must never be decoded just to be laid out.
class AlbumMetadataCache {
  AlbumMetadataCache({this.headerBytes = 512 * 1024});

  final int headerBytes;
  final Map<String, AlbumMediaMetadata> _resolved = {};
  final Map<String, Future<AlbumMediaMetadata>> _inFlight = {};

  AlbumMediaMetadata? peek(String id) => _resolved[id];

  /// Records what a service has already said about a picture.
  ///
  /// A hosted album's shapes, capture dates and coordinates arrive with the
  /// listing, so nothing has to be downloaded for the wall to lay out or for
  /// the timeline and the places plot to have anything to show. Seeding also
  /// stops [load] reading the cached thumbnail and reporting ITS size as the
  /// picture's own.
  void seed(String id, AlbumMediaMetadata metadata) {
    _resolved[id] = metadata;
    _inFlight.removeWhere((key, _) => key == id);
  }

  Future<AlbumMediaMetadata> load(AlbumMediaItem item) {
    final cached = _resolved[item.id];
    if (cached != null) {
      return Future.value(cached);
    }
    return _inFlight.putIfAbsent(item.id, () async {
      final metadata = await _read(item);
      _resolved[item.id] = metadata;
      _inFlight.removeWhere((key, _) => key == item.id);
      return metadata;
    });
  }

  Future<AlbumMediaMetadata> _read(AlbumMediaItem item) async {
    if (!item.isLocal || item.kind != AlbumMediaKind.image) {
      return AlbumMediaMetadata(
        capturedAt: item.modifiedAt,
        byteSize: item.byteSize,
        failed: !item.isLocal,
      );
    }
    try {
      final file = File(item.path);
      final length = await file.length();
      final head = await _readHead(file, length);
      final exif = readPhotoExif(head);
      final header = readImageHeaderSize(head);
      return AlbumMediaMetadata(
        exif: exif,
        pixelSize: header ??
            (exif.pixelWidth != null && exif.pixelHeight != null
                ? ImageHeaderSize(exif.pixelWidth!, exif.pixelHeight!)
                : null),
        capturedAt: exif.takenAt ?? item.modifiedAt,
        byteSize: length,
      );
    } on Object {
      return AlbumMediaMetadata(
        capturedAt: item.modifiedAt,
        byteSize: item.byteSize,
        failed: true,
      );
    }
  }

  Future<Uint8List> _readHead(File file, int length) async {
    if (length <= headerBytes) {
      return file.readAsBytes();
    }
    final handle = await file.open();
    try {
      return await handle.read(headerBytes);
    } finally {
      await handle.close();
    }
  }

  void invalidate(String id) {
    _resolved.remove(id);
    _inFlight.remove(id);
  }

  void clear() {
    _resolved.clear();
    _inFlight.clear();
  }
}

/// What a service has already told us about one piece of media.
///
/// A hosted photo is never opened to be laid out: the listing carries its
/// shape, when it was taken and where, which is everything the wall, the
/// timeline and the places plot ask for.
AlbumMediaMetadata albumMetadataOfProviderNode(ProviderNode node) {
  final width = node.width;
  final height = node.height;
  return AlbumMediaMetadata(
    exif: PhotoExif(
      takenAt: node.createdAt,
      pixelWidth: width,
      pixelHeight: height,
      latitude: node.latitude,
      longitude: node.longitude,
    ),
    pixelSize: width != null && height != null && width > 0 && height > 0
        ? ImageHeaderSize(width, height)
        : null,
    capturedAt: node.createdAt ?? node.modifiedAt,
    byteSize: node.byteSize,
  );
}
