import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:path/path.dart' as p;

/// Spellings the shared viewer does not know by name.
const _extraMarkdownExtensions = {'mdown', 'mkd', 'mkdn', 'mdwn', 'mdtxt'};
const _extraHtmlExtensions = {'xhtml', 'shtml'};
const _extraTextExtensions = {'text'};

/// How much of a file without a known extension is read to decide whether it
/// is text.
const _sniffBytes = 8 * 1024;

/// The viewer for a file opened from outside AppFlowy, or null when it has
/// none.
///
/// The name decides first. A file without a recognised extension, such as a
/// README, LICENSE or `notes.text`, is shown as plain text when its opening
/// bytes contain no NUL byte.
Future<FilePreviewKind?> externalFilePreviewKind(File file) async {
  final kind = externalFilePreviewKindFromName(p.basename(file.path));
  if (kind != null) return kind;
  return await _looksLikeText(file) ? FilePreviewKind.text : null;
}

/// The viewer [name]'s extension alone selects, without reading the file.
FilePreviewKind? externalFilePreviewKindFromName(String name) {
  final extension = p.extension(name).replaceFirst('.', '').toLowerCase();
  if (extension.isEmpty) return null;
  if (_extraMarkdownExtensions.contains(extension)) {
    return FilePreviewKind.markdown;
  }
  if (_extraHtmlExtensions.contains(extension)) return FilePreviewKind.html;
  if (_extraTextExtensions.contains(extension)) return FilePreviewKind.text;
  return filePreviewKindFromName(name);
}

Future<bool> _looksLikeText(File file) async {
  RandomAccessFile? handle;
  try {
    handle = await file.open();
    final bytes = await handle.read(_sniffBytes);
    return !bytes.contains(0);
  } on FileSystemException {
    return false;
  } finally {
    await handle?.close();
  }
}
