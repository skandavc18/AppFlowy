import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pbenum.dart';
import 'package:cross_file/cross_file.dart';

enum FileType {
  other,
  image,
  link,
  document,
  archive,
  video,
  audio,
  text;
}

extension TypeRecognizer on XFile {
  FileType get fileType => inferFileType(path, mimeType: mimeType);
}

/// Shared inference for picked files and legacy attachment metadata.
///
/// A recognised MIME type wins over a misleading extension. Missing, generic
/// (such as application/octet-stream) and unrecognised MIME types fall back to
/// the filename/URI path. This classifies the file, not codec availability.
FileType inferFileType(String source, {String? mimeType}) {
  final mime = mimeType?.split(';').first.trim().toLowerCase() ?? '';
  if (mime.startsWith('image/')) return FileType.image;
  if (mime.startsWith('video/')) return FileType.video;
  if (mime.startsWith('audio/')) return FileType.audio;
  if (mime.startsWith('text/')) return FileType.text;

  if (mime == 'application/pdf' ||
      mime == 'application/msword' ||
      mime.startsWith('application/vnd.openxmlformats-officedocument.') ||
      mime.startsWith('application/vnd.oasis.opendocument.')) {
    return FileType.document;
  }
  if (const {
    'application/zip',
    'application/x-zip-compressed',
    'application/x-tar',
    'application/gzip',
    'application/x-gzip',
    'application/x-7z-compressed',
    'application/vnd.rar',
    'application/x-rar-compressed',
    'application/java-archive',
  }.contains(mime)) {
    return FileType.archive;
  }
  if (const {
    'application/rtf',
    'application/json',
    'application/ld+json',
    'application/xml',
    'application/javascript',
  }.contains(mime)) {
    return FileType.text;
  }

  final path = fileTypePath(source);
  if (imgExtensionRegex.hasMatch(path)) return FileType.image;
  if (videoExtensionRegex.hasMatch(path)) return FileType.video;
  if (audioExtensionRegex.hasMatch(path)) return FileType.audio;
  if (documentExtensionRegex.hasMatch(path)) return FileType.document;
  if (archiveExtensionRegex.hasMatch(path)) return FileType.archive;
  if (textExtensionRegex.hasMatch(path)) return FileType.text;
  return FileType.other;
}

extension ToMediaFileTypePB on FileType {
  MediaFileTypePB toMediaFileTypePB() {
    switch (this) {
      case FileType.image:
        return MediaFileTypePB.Image;
      case FileType.video:
        return MediaFileTypePB.Video;
      case FileType.audio:
        return MediaFileTypePB.Audio;
      case FileType.document:
        return MediaFileTypePB.Document;
      case FileType.archive:
        return MediaFileTypePB.Archive;
      case FileType.text:
        return MediaFileTypePB.Text;
      default:
        return MediaFileTypePB.Other;
    }
  }
}
