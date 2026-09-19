/// This pattern matches a file extension that is an image.
///
/// JFIF contains JPEG data; recognising its name does not add a new codec.
/// These patterns classify names, not the platform's decoding capabilities.
const _imgExtensionPattern = r'\.(gif|jpe?g|jfif|tiff?|png|webp|bmp)$';
final imgExtensionRegex = RegExp(_imgExtensionPattern, caseSensitive: false);

/// This pattern matches a file extension that is a video.
///
const _videoExtensionPattern = r'\.(mp4|mov|avi|webm|flv|m4v|mpeg|h264)$';
final videoExtensionRegex =
    RegExp(_videoExtensionPattern, caseSensitive: false);

/// This pattern matches a file extension that is an audio.
///
const _audioExtensionPattern = r'\.(mp3|wav|ogg|flac|aac|wma|alac|aiff)$';
final audioExtensionRegex =
    RegExp(_audioExtensionPattern, caseSensitive: false);

/// This pattern matches a file extension that is a document.
///
const _documentExtensionPattern = r'\.(pdf|doc|docx)$';
final documentExtensionRegex =
    RegExp(_documentExtensionPattern, caseSensitive: false);

/// This pattern matches a file extension that is an archive.
///
const _archiveExtensionPattern = r'\.(zip|tar|gz|7z|rar)$';
final archiveExtensionRegex =
    RegExp(_archiveExtensionPattern, caseSensitive: false);

/// This pattern matches a file extension that is a text.
///
const _textExtensionPattern = r'\.(txt|md|html|css|js|json|xml|csv)$';
final textExtensionRegex = RegExp(_textExtensionPattern, caseSensitive: false);

final _windowsDrivePrefix = RegExp('^[a-zA-Z]:');

/// The part of a filename, local path or URI whose extension describes a file.
///
/// A URL's query/fragment is not a filename. Conversely, a raw local path's
/// literal `#` and `%` must not be interpreted as URI syntax, and a Windows
/// drive letter must not be mistaken for a URI scheme.
String fileTypePath(String source) {
  if (_windowsDrivePrefix.hasMatch(source) || source.startsWith(r'\\')) {
    return source;
  }

  final uri = Uri.tryParse(source);
  if (uri == null) {
    return '';
  }
  if (!uri.hasScheme && !uri.hasAuthority) {
    return source;
  }
  // Opaque URIs (data:, blob:, mailto:, ...) do not identify a file by suffix.
  if (!uri.hasAuthority && !uri.isScheme('file')) {
    return '';
  }

  try {
    return Uri.decodeComponent(uri.path);
  } on FormatException {
    return uri.path;
  }
}
