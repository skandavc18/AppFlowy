import 'package:flutter/foundation.dart';

/// What one object out of an external service is.
///
/// Deliberately coarse: the interface only needs to know which viewer to open
/// and which glyph to draw, and every service names its own types differently.
enum ProviderNodeKind {
  folder,
  album,
  image,
  video,
  audio,
  pdf,
  document,
  spreadsheet,
  presentation,
  markup,
  code,
  archive,
  other;

  bool get isContainer => this == folder || this == album;

  bool get isVisualMedia => this == image || this == video;

  bool get isMedia => isVisualMedia || this == audio;
}

/// One object as a provider reports it, before the workspace dresses it up.
///
/// Nothing here is service specific. A GitHub blob, a Drive file and an Immich
/// asset all arrive as this, which is what lets one set of views render them.
@immutable
class ProviderNode {
  const ProviderNode({
    required this.id,
    required this.name,
    required this.kind,
    this.parentId,
    this.path = '',
    this.mimeType,
    this.byteSize,
    this.modifiedAt,
    this.createdAt,
    this.thumbnailUrl,
    this.downloadUrl,
    this.webUrl,
    this.childCount,
    this.width,
    this.height,
    this.durationMs,
    this.favourite = false,
    this.readOnly = false,
    this.latitude,
    this.longitude,
    this.description,
    this.extra = const <String, Object?>{},
  });

  /// The service's own identifier. Opaque to everything above the provider.
  final String id;

  final String name;
  final ProviderNodeKind kind;

  /// The service's id of the container this sits in, when it has one.
  final String? parentId;

  /// A slash separated path relative to the collection's root, when the
  /// service is path shaped. Empty for a flat service such as a photo library.
  final String path;

  final String? mimeType;
  final int? byteSize;
  final DateTime? modifiedAt;
  final DateTime? createdAt;

  /// A small, cheap picture. Never the original.
  final String? thumbnailUrl;

  /// Where the bytes are. May need the connection's own credentials.
  final String? downloadUrl;

  /// The service's own page for this object, for "Open in …".
  final String? webUrl;

  final int? childCount;
  final int? width;
  final int? height;
  final int? durationMs;
  final bool favourite;

  /// Whether this particular object is read only, whatever the connection can
  /// do in general.
  final bool readOnly;

  final double? latitude;
  final double? longitude;
  final String? description;

  /// Anything a single provider needs to carry through and nothing else has to
  /// understand — a git blob sha, a Drive revision, an Immich device id.
  final Map<String, Object?> extra;

  bool get isFolder => kind.isContainer;

  bool get hasLocation => latitude != null && longitude != null;

  /// The file extension the name implies, lowercased and without the dot.
  String get extension {
    final dot = name.lastIndexOf('.');
    if (dot <= 0 || dot == name.length - 1) {
      return '';
    }
    return name.substring(dot + 1).toLowerCase();
  }

  ProviderNode copyWith({
    String? name,
    String? path,
    String? parentId,
    ProviderNodeKind? kind,
    String? thumbnailUrl,
    String? downloadUrl,
    bool? favourite,
    bool? readOnly,
    Map<String, Object?>? extra,
  }) =>
      ProviderNode(
        id: id,
        name: name ?? this.name,
        kind: kind ?? this.kind,
        parentId: parentId ?? this.parentId,
        path: path ?? this.path,
        mimeType: mimeType,
        byteSize: byteSize,
        modifiedAt: modifiedAt,
        createdAt: createdAt,
        thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
        downloadUrl: downloadUrl ?? this.downloadUrl,
        webUrl: webUrl,
        childCount: childCount,
        width: width,
        height: height,
        durationMs: durationMs,
        favourite: favourite ?? this.favourite,
        readOnly: readOnly ?? this.readOnly,
        latitude: latitude,
        longitude: longitude,
        description: description,
        extra: extra ?? this.extra,
      );

  Map<String, Object?> toJson() => {
        'id': id,
        'name': name,
        'kind': kind.name,
        if (parentId != null) 'parent': parentId,
        if (path.isNotEmpty) 'path': path,
        if (mimeType != null) 'mime': mimeType,
        if (byteSize != null) 'size': byteSize,
        if (modifiedAt != null) 'modified': modifiedAt!.millisecondsSinceEpoch,
        if (createdAt != null) 'created': createdAt!.millisecondsSinceEpoch,
        if (thumbnailUrl != null) 'thumb': thumbnailUrl,
        if (downloadUrl != null) 'download': downloadUrl,
        if (webUrl != null) 'web': webUrl,
        if (childCount != null) 'children': childCount,
        if (width != null) 'width': width,
        if (height != null) 'height': height,
        if (durationMs != null) 'duration': durationMs,
        if (favourite) 'favourite': true,
        if (readOnly) 'read_only': true,
        if (latitude != null) 'lat': latitude,
        if (longitude != null) 'lon': longitude,
        if (description != null) 'description': description,
        if (extra.isNotEmpty) 'extra': extra,
      };

  static ProviderNode? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final values = Map<String, dynamic>.from(value);
    final id = values['id'];
    final name = values['name'];
    if (id is! String || id.isEmpty || name is! String) {
      return null;
    }
    return ProviderNode(
      id: id,
      name: name,
      kind: ProviderNodeKind.values.firstWhere(
        (kind) => kind.name == values['kind'],
        orElse: () => ProviderNodeKind.other,
      ),
      parentId: values['parent'] is String ? values['parent'] as String : null,
      path: values['path'] is String ? values['path'] as String : '',
      mimeType: values['mime'] is String ? values['mime'] as String : null,
      byteSize: values['size'] is int ? values['size'] as int : null,
      modifiedAt: _date(values['modified']),
      createdAt: _date(values['created']),
      thumbnailUrl:
          values['thumb'] is String ? values['thumb'] as String : null,
      downloadUrl:
          values['download'] is String ? values['download'] as String : null,
      webUrl: values['web'] is String ? values['web'] as String : null,
      childCount: values['children'] is int ? values['children'] as int : null,
      width: values['width'] is int ? values['width'] as int : null,
      height: values['height'] is int ? values['height'] as int : null,
      durationMs: values['duration'] is int ? values['duration'] as int : null,
      favourite: values['favourite'] == true,
      readOnly: values['read_only'] == true,
      latitude: _number(values['lat']),
      longitude: _number(values['lon']),
      description: values['description'] is String
          ? values['description'] as String
          : null,
      extra: values['extra'] is Map
          ? Map<String, Object?>.from(values['extra'] as Map)
          : const <String, Object?>{},
    );
  }

  static DateTime? _date(Object? value) =>
      value is int ? DateTime.fromMillisecondsSinceEpoch(value) : null;

  static double? _number(Object? value) => switch (value) {
        final double value => value,
        final int value => value.toDouble(),
        _ => null,
      };
}

/// One page of results, so a provider never has to load a whole library to
/// show the first screen of it.
@immutable
class ProviderPage {
  const ProviderPage({
    required this.nodes,
    this.nextPageToken,
  });

  static const empty = ProviderPage(nodes: <ProviderNode>[]);

  final List<ProviderNode> nodes;
  final String? nextPageToken;

  bool get hasMore => nextPageToken != null && nextPageToken!.isNotEmpty;
}

/// Reads a node's kind out of whatever the service said about it.
///
/// Services disagree on how much they tell you: some give a MIME type, some
/// only a file name. Both are consulted, MIME first because it is the one that
/// cannot be faked by renaming.
ProviderNodeKind providerNodeKindFor({
  String? mimeType,
  String name = '',
  bool isFolder = false,
}) {
  if (isFolder) {
    return ProviderNodeKind.folder;
  }

  final mime = (mimeType ?? '').toLowerCase();
  if (mime.startsWith('image/')) {
    return ProviderNodeKind.image;
  }
  if (mime.startsWith('video/')) {
    return ProviderNodeKind.video;
  }
  if (mime.startsWith('audio/')) {
    return ProviderNodeKind.audio;
  }
  if (mime == 'application/pdf') {
    return ProviderNodeKind.pdf;
  }
  if (mime.contains('spreadsheet') || mime.contains('excel')) {
    return ProviderNodeKind.spreadsheet;
  }
  if (mime.contains('presentation') || mime.contains('powerpoint')) {
    return ProviderNodeKind.presentation;
  }
  if (mime.contains('wordprocessing') || mime == 'application/msword') {
    return ProviderNodeKind.document;
  }
  if (mime == 'application/vnd.google-apps.folder') {
    return ProviderNodeKind.folder;
  }

  final dot = name.lastIndexOf('.');
  final extension = dot > 0 ? name.substring(dot + 1).toLowerCase() : '';
  return _kindByExtension[extension] ?? ProviderNodeKind.other;
}

const _kindByExtension = <String, ProviderNodeKind>{
  'png': ProviderNodeKind.image,
  'jpg': ProviderNodeKind.image,
  'jpeg': ProviderNodeKind.image,
  'gif': ProviderNodeKind.image,
  'webp': ProviderNodeKind.image,
  'bmp': ProviderNodeKind.image,
  'heic': ProviderNodeKind.image,
  'heif': ProviderNodeKind.image,
  'svg': ProviderNodeKind.image,
  'avif': ProviderNodeKind.image,
  'mp4': ProviderNodeKind.video,
  'mov': ProviderNodeKind.video,
  'mkv': ProviderNodeKind.video,
  'webm': ProviderNodeKind.video,
  'avi': ProviderNodeKind.video,
  'm4v': ProviderNodeKind.video,
  'mp3': ProviderNodeKind.audio,
  'wav': ProviderNodeKind.audio,
  'flac': ProviderNodeKind.audio,
  'm4a': ProviderNodeKind.audio,
  'ogg': ProviderNodeKind.audio,
  'aac': ProviderNodeKind.audio,
  'pdf': ProviderNodeKind.pdf,
  'doc': ProviderNodeKind.document,
  'docx': ProviderNodeKind.document,
  'odt': ProviderNodeKind.document,
  'rtf': ProviderNodeKind.document,
  'txt': ProviderNodeKind.markup,
  'md': ProviderNodeKind.markup,
  'markdown': ProviderNodeKind.markup,
  'html': ProviderNodeKind.markup,
  'htm': ProviderNodeKind.markup,
  'xls': ProviderNodeKind.spreadsheet,
  'xlsx': ProviderNodeKind.spreadsheet,
  'ods': ProviderNodeKind.spreadsheet,
  'csv': ProviderNodeKind.spreadsheet,
  'tsv': ProviderNodeKind.spreadsheet,
  'ppt': ProviderNodeKind.presentation,
  'pptx': ProviderNodeKind.presentation,
  'odp': ProviderNodeKind.presentation,
  'zip': ProviderNodeKind.archive,
  'tar': ProviderNodeKind.archive,
  'gz': ProviderNodeKind.archive,
  'bz2': ProviderNodeKind.archive,
  'xz': ProviderNodeKind.archive,
  '7z': ProviderNodeKind.archive,
  'rar': ProviderNodeKind.archive,
  'dart': ProviderNodeKind.code,
  'rs': ProviderNodeKind.code,
  'py': ProviderNodeKind.code,
  'js': ProviderNodeKind.code,
  'ts': ProviderNodeKind.code,
  'tsx': ProviderNodeKind.code,
  'jsx': ProviderNodeKind.code,
  'go': ProviderNodeKind.code,
  'java': ProviderNodeKind.code,
  'kt': ProviderNodeKind.code,
  'swift': ProviderNodeKind.code,
  'c': ProviderNodeKind.code,
  'h': ProviderNodeKind.code,
  'cpp': ProviderNodeKind.code,
  'hpp': ProviderNodeKind.code,
  'cs': ProviderNodeKind.code,
  'rb': ProviderNodeKind.code,
  'php': ProviderNodeKind.code,
  'sh': ProviderNodeKind.code,
  'ps1': ProviderNodeKind.code,
  'json': ProviderNodeKind.code,
  'yaml': ProviderNodeKind.code,
  'yml': ProviderNodeKind.code,
  'toml': ProviderNodeKind.code,
  'xml': ProviderNodeKind.code,
  'sql': ProviderNodeKind.code,
};
