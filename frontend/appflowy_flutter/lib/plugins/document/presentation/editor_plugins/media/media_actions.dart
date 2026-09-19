import 'dart:convert';
import 'dart:io';
import 'dart:ui' show Rect;

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flowy_infra/file_picker/file_picker_impl.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:mime/mime.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';
import 'package:universal_platform/universal_platform.dart';

/// An immutable action target, including a snapshot of its credentials.
///
/// Equality includes headers so a refreshed credential or changed target resets
/// UI action status. Constructing a cloud target never throws for missing auth;
/// [MediaActionService] checks it when an operation is requested.
@immutable
class MediaActionSource {
  MediaActionSource({
    required this.source,
    required this.name,
    this.isImage = false,
    this.shareAsLink = false,
    Map<String, String> httpHeaders = const {},
    this.requireAuthentication = false,
  }) : httpHeaders = Map.unmodifiable(httpHeaders);

  factory MediaActionSource.image(
    ImageBlockData image, {
    UserProfilePB? userProfile,
    String? name,
  }) {
    final internal = image.type == CustomImageType.internal;
    return MediaActionSource(
      source: image.url,
      name: name ?? _sourceFileName(image.url),
      isImage: true,
      httpHeaders: internal ? _cloudHeaders(userProfile) : const {},
      requireAuthentication: internal,
    );
  }

  factory MediaActionSource.file({
    required String source,
    required String name,
    FileUploadTypePB? uploadType,
    UserProfilePB? userProfile,
    bool isImage = false,
    bool shareAsLink = false,
  }) {
    final internal = uploadType == FileUploadTypePB.CloudFile;
    return MediaActionSource(
      source: source,
      name: name,
      isImage: isImage,
      shareAsLink: shareAsLink,
      httpHeaders: internal ? _cloudHeaders(userProfile) : const {},
      requireAuthentication: internal,
    );
  }

  final String source;
  final String name;
  final bool isImage;
  final bool shareAsLink;
  final Map<String, String> httpHeaders;
  final bool requireAuthentication;

  @override
  bool operator ==(Object other) =>
      other is MediaActionSource &&
      source == other.source &&
      name == other.name &&
      isImage == other.isImage &&
      shareAsLink == other.shareAsLink &&
      requireAuthentication == other.requireAuthentication &&
      mapEquals(httpHeaders, other.httpHeaders);

  @override
  int get hashCode => Object.hash(
        source,
        name,
        isImage,
        shareAsLink,
        requireAuthentication,
        Object.hashAllUnordered(
          httpHeaders.entries
              .map((entry) => Object.hash(entry.key, entry.value)),
        ),
      );
}

typedef MediaFileSharer = Future<ShareResult> Function(
  List<XFile> files, {
  Rect? sharePositionOrigin,
  List<String>? fileNameOverrides,
});

typedef MediaLinkSharer = Future<ShareResult> Function(
  String text, {
  Rect? sharePositionOrigin,
});

/// Copies original media, not the scaled viewer or its hover controls.
///
/// Injection is at the IO boundaries; the real preparation and format selection
/// still run in tests. A supplied [httpClient] remains owned by the caller.
class MediaActionService {
  const MediaActionService({
    this.clipboard = _systemClipboard,
    this.shareFiles = Share.shareXFiles,
    this.shareText = Share.share,
    this.httpClient,
    this.temporaryDirectory = getTemporaryDirectory,
  });

  static const instance = MediaActionService();

  final ClipboardWriter? Function() clipboard;
  final MediaFileSharer shareFiles;
  final MediaLinkSharer shareText;
  final http.Client? httpClient;
  final Future<Directory> Function() temporaryDirectory;

  Future<void> copy(MediaActionSource target) async {
    _checkTarget(target);
    final writer = clipboard();
    if (writer == null) {
      throw UnsupportedError('The system clipboard is unavailable.');
    }
    if (target.shareAsLink) {
      await writer.write([
        DataWriterItem()..add(await Formats.plainText(target.source)),
      ]);
      return;
    }

    final media = await _prepare(target, forClipboard: true);
    final item = DataWriterItem(suggestedName: p.basename(media.file.path));
    try {
      final image = media.image;
      if (image != null) {
        // Highest fidelity first; super_clipboard also supplies native Windows
        // DIB/DIBV5 renditions for these formats when a receiving app asks.
        item.add(
          await switch (image.$1) {
            'jpeg' => Formats.jpeg(image.$2),
            'gif' => Formats.gif(image.$2),
            _ => Formats.png(image.$2),
          },
        );
      }
      item
        ..add(await Formats.fileUri(media.file.uri))
        ..add(await Formats.plainText(media.file.path));
    } catch (_) {
      await _discardExport(media.directory);
      rethrow;
    }
    // Do not delete after handoff, even if a native call subsequently throws:
    // the OS may already hold the file URI and read it later.
    await writer.write([item]);
  }

  /// Completes after handoff, not confirmed delivery to another application.
  Future<void> share(
    MediaActionSource target, {
    Rect? sharePositionOrigin,
  }) async {
    _checkTarget(target);
    if (target.shareAsLink) {
      await shareText(target.source, sharePositionOrigin: sharePositionOrigin);
      return;
    }

    final media = await _prepare(target, forClipboard: false);
    // Windows ignores fileNameOverrides: the physical file has the right name.
    // Its WinRT sheet returns unavailable while still consuming the file. This
    // is neither a failure nor proof of delivery, and must not trigger cleanup.
    await shareFiles(
      [XFile(media.file.path, mimeType: media.mimeType)],
      fileNameOverrides: [p.basename(media.file.path)],
      sharePositionOrigin: sharePositionOrigin,
    );
  }

  Future<_MediaExport> _prepare(
    MediaActionSource target, {
    required bool forClipboard,
  }) async {
    final media = await _materialize(
      source: target.source,
      name: target.name,
      httpHeaders: target.httpHeaders,
      httpClient: httpClient,
      temporaryDirectory: temporaryDirectory,
      copyLocal: true,
    );
    try {
      if (!target.isImage) {
        return media;
      }
      final bytes = await media.file.readAsBytes();
      var format = sniffImageFormat(bytes) ??
          switch (lookupMimeType('', headerBytes: bytes)) {
            'image/webp' => 'webp',
            'image/bmp' || 'image/x-ms-bmp' => 'bmp',
            'image/tiff' => 'tiff',
            'image/heic' => 'heic',
            'image/heif' => 'heif',
            'image/avif' => 'avif',
            _ => null,
          };
      // mime 2.x does not recognize BMP magic numbers without a filename.
      if (format == null &&
          bytes.length >= 14 &&
          bytes[0] == 0x42 &&
          bytes[1] == 0x4d) {
        format = 'bmp';
      }
      (String, Uint8List)? encoded;
      if (forClipboard || format == null) {
        encoded = await encodeForClipboard(bytes);
        if (sniffImageFormat(bytes) != null) {
          // The encoder passes these formats through. Validate the image too,
          // so a truncated response never replaces the clipboard with junk.
          final image = await decodeEditableImage(bytes);
          image.dispose();
        }
      }
      final fileBytes = format == null ? encoded!.$2 : bytes;
      format ??= encoded!.$1;
      final name = _imageFileName(p.basename(media.file.path), format);
      var file = media.file;
      if (!identical(fileBytes, bytes)) {
        file = await File(p.join(media.directory!.path, name))
            .writeAsBytes(fileBytes, flush: true);
        if (file.path != media.file.path) {
          await media.file.delete();
        }
      } else if (name != p.basename(file.path)) {
        file = await file.rename(p.join(media.directory!.path, name));
      }
      return _MediaExport(
        file,
        directory: media.directory,
        mimeType: 'image/$format',
        image: forClipboard ? encoded : null,
      );
    } catch (_) {
      await _discardExport(media.directory);
      rethrow;
    }
  }
}

ClipboardWriter? _systemClipboard() => SystemClipboard.instance;

Map<String, String> _cloudHeaders(UserProfilePB? profile) {
  // Do not use the logging auth helper here: a JSON FormatException can include
  // the malformed token itself. Building an action is deliberately fail-closed
  // and silent; the operation reports missing credentials without their value.
  try {
    final decoded = jsonDecode(profile?.token ?? '');
    final token = decoded is Map ? decoded['access_token'] : null;
    if (token is String && _isBearerToken(token)) {
      return {'Authorization': 'Bearer $token'};
    }
  } on FormatException {
    // Missing or malformed credentials are checked at operation time.
  }
  return const {};
}

bool _isBearerToken(String value) =>
    RegExp(r'^[a-zA-Z0-9._~+/-]+=*$').hasMatch(value);

void _checkTarget(MediaActionSource target) {
  if (target.source.trim().isEmpty) {
    throw ArgumentError('No media source was provided.');
  }
  if (target.requireAuthentication &&
      !target.httpHeaders.entries.any(
        (entry) =>
            entry.key.toLowerCase() == 'authorization' &&
            entry.value.toLowerCase().startsWith('bearer ') &&
            _isBearerToken(entry.value.substring(7)),
      )) {
    throw StateError('Sign in to access this cloud media.');
  }
  if (target.shareAsLink &&
      (target.requireAuthentication || target.httpHeaders.isNotEmpty)) {
    throw StateError(
      'Authenticated media must be shared as a file, not a link.',
    );
  }
}

/// Resolves stored local paths without copying (editors rely on that), or
/// downloads HTTP(S) media into a unique export directory. No successful export
/// is deleted here: a caller or an OS consumer may still need it.
Future<File> materializeMediaFile({
  required String source,
  required String name,
  Map<String, String> httpHeaders = const {},
  http.Client? httpClient,
  Future<Directory> Function() temporaryDirectory = getTemporaryDirectory,
}) async {
  final media = await _materialize(
    source: source,
    name: name,
    httpHeaders: httpHeaders,
    httpClient: httpClient,
    temporaryDirectory: temporaryDirectory,
  );
  return media.file;
}

Future<_MediaExport> _materialize({
  required String source,
  required String name,
  required Map<String, String> httpHeaders,
  required http.Client? httpClient,
  required Future<Directory> Function() temporaryDirectory,
  bool copyLocal = false,
}) async {
  // Snapshot before the resolver's first await, including for legacy callers
  // that still pass mutable header maps directly.
  final headers = Map<String, String>.unmodifiable(httpHeaders);
  final resolved = await resolveLocalStorageFilePath(source);
  if (resolved != null && !copyLocal) {
    return _MediaExport(File(resolved));
  }

  Uint8List? bytes;
  if (resolved == null) {
    final uri = Uri.tryParse(source);
    if (uri == null || !(uri.isScheme('http') || uri.isScheme('https'))) {
      throw FileSystemException(
        'AppFlowy could not find this file where it was stored.',
        source,
      );
    }
    if (!uri.hasAuthority ||
        uri.host.isEmpty ||
        RegExp(r'[\s%\\]').hasMatch(uri.host) ||
        uri.userInfo.isNotEmpty) {
      throw const HttpException('The media URL must have a valid host.');
    }
    final client = httpClient ?? http.Client();
    try {
      final response = await client.get(uri, headers: headers);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'Unable to download media (${response.statusCode}).',
        );
      }
      bytes = response.bodyBytes;
    } finally {
      if (httpClient == null) {
        client.close();
      }
    }
  }

  final root = Directory(
    p.join((await temporaryDirectory()).path, 'appflowy_media'),
  );
  await root.create(recursive: true);
  final directory = await root.createTemp('export_');
  try {
    final safeName = _safeFileName(
      name.trim().isEmpty ? _sourceFileName(source) : name,
    );
    final path = p.join(directory.path, safeName);
    final file = resolved != null
        ? await File(resolved).copy(path)
        : await File(path).writeAsBytes(bytes!, flush: true);
    return _MediaExport(
      file,
      directory: directory,
      mimeType: lookupMimeType(safeName),
    );
  } catch (_) {
    await _discardExport(directory);
    rethrow;
  }
}

class _MediaExport {
  const _MediaExport(
    this.file, {
    this.directory,
    this.mimeType,
    this.image,
  });

  final File file;
  final Directory? directory;
  final String? mimeType;
  final (String, Uint8List)? image;
}

Future<void> _discardExport(Directory? directory) async {
  try {
    await directory?.delete(recursive: true);
  } on FileSystemException {
    // Cleanup must never mask the preparation failure. Never delete a source
    // file or a parent directory shared with another export.
  }
}

String _sourceFileName(String source) {
  final uri = Uri.tryParse(source);
  if (uri != null &&
      (uri.isScheme('http') || uri.isScheme('https') || uri.isScheme('file'))) {
    try {
      return uri.pathSegments.isEmpty ? '' : uri.pathSegments.last;
    } on FormatException {
      return '';
    }
  }
  // Do not URI-decode raw paths: #, %, spaces and Unicode are literal names.
  return source.split(RegExp(r'[/\\]')).last;
}

String _safeFileName(String name) {
  var safe = name
      .split(RegExp(r'[/\\]'))
      .last
      .replaceAll(RegExp(r'[<>:"|?*\x00-\x1f\x7f-\x9f]'), '_')
      .trim()
      .replaceAll(RegExp(r'[. ]+$'), '')
      .replaceAll(RegExp(r'\.{2,}'), '_');
  if (safe.isEmpty) {
    safe = 'media';
  }
  final stem = safe.split('.').first.trimRight();
  if (RegExp(
    r'^(con|prn|aux|nul|clock\$|conin\$|conout\$|com[0-9¹²³]|lpt[0-9¹²³])$',
    caseSensitive: false,
  ).hasMatch(stem)) {
    safe = '_$safe';
  }
  return safe;
}

String _imageFileName(String name, String format) {
  final extension = p.extension(name).toLowerCase();
  if (extension == '.$format' ||
      (format == 'jpeg' && {'.jpg', '.jpe', '.jfif'}.contains(extension)) ||
      (format == 'tiff' && extension == '.tif')) {
    return name;
  }
  final actualExtension = format == 'jpeg' ? '.jpg' : '.$format';
  const imageExtensions = {
    '.png',
    '.jpg',
    '.jpeg',
    '.jpe',
    '.jfif',
    '.gif',
    '.webp',
    '.bmp',
    '.tif',
    '.tiff',
    '.heic',
    '.heif',
    '.avif',
  };
  return imageExtensions.contains(extension)
      ? p.setExtension(name, actualExtension)
      : '$name$actualExtension';
}

Future<void> copyMedia({
  required String source,
  required String name,
  bool shareAsLink = false,
  bool asImage = false,
  Map<String, String> httpHeaders = const {},
}) =>
    MediaActionService.instance.copy(
      MediaActionSource(
        source: source,
        name: name,
        isImage: asImage,
        shareAsLink: shareAsLink,
        httpHeaders: httpHeaders,
      ),
    );

Future<void> shareMedia({
  required String source,
  required String name,
  bool shareAsLink = false,
  bool asImage = false,
  Map<String, String> httpHeaders = const {},
  Rect? sharePositionOrigin,
}) =>
    MediaActionService.instance.share(
      MediaActionSource(
        source: source,
        name: name,
        isImage: asImage,
        shareAsLink: shareAsLink,
        httpHeaders: httpHeaders,
      ),
      sharePositionOrigin: sharePositionOrigin,
    );

Future<bool> downloadMedia({
  required String source,
  required String name,
  Map<String, String> httpHeaders = const {},
}) async {
  final file = await materializeMediaFile(
    source: source,
    name: name,
    httpHeaders: httpHeaders,
  );
  return saveMediaBytes(bytes: await file.readAsBytes(), name: name);
}

Future<bool> saveMediaBytes({
  required Uint8List bytes,
  required String name,
}) async {
  final path = await FilePicker().saveFile(
    fileName: name,
    bytes: UniversalPlatform.isMobile ? bytes : null,
  );
  if (path != null && !UniversalPlatform.isMobile) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path != null;
}
