import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_text_preview.dart';
import 'package:appflowy_backend/log.dart';
import 'package:pdfrx/pdfrx.dart';

/// Reads the words out of a workspace file.
///
/// A Word, Excel or PowerPoint document is a zip of XML, so its text can be
/// taken straight out of it — no document server is needed. A PDF carries its
/// own text. Everything else is read as it is written.
Future<String?> readWorkspaceFileText({
  required String source,
  required String name,
  int limit = 8000,
}) async {
  final path = await _localPath(source);
  if (path == null) {
    return null;
  }

  final extension = name.split('.').last.toLowerCase();
  try {
    if (extension == 'pdf') {
      return _clamp(await _readPdf(path), limit);
    }
    if (isOfficeFile(name)) {
      final document = await ArchiveDocument.read(
        File(path),
        name: name,
        format: ArchiveFormat.zip,
      );
      return _clamp(
        extractOfficeDocumentText(document, name, maxCharacters: limit) ?? '',
        limit,
      );
    }
    // Anything else is read as text; a binary file simply reads as noise, so
    // it is refused rather than shown.
    final bytes = await File(path).readAsBytes();
    if (_looksBinary(bytes)) {
      return null;
    }
    return _clamp(String.fromCharCodes(bytes), limit);
  } catch (error) {
    Log.warn('Could not read the text of $name: $error');
    return null;
  }
}

Future<String> _readPdf(String path) async {
  final document = await PdfDocument.openFile(path);
  try {
    final buffer = StringBuffer();
    for (final page in document.pages) {
      final text = await page.loadText();
      buffer
        ..writeln(text.fullText)
        ..writeln();
    }
    return buffer.toString();
  } finally {
    await document.dispose();
  }
}

Future<String?> _localPath(String source) async {
  final resolved = await resolveLocalStorageFilePath(source);
  if (resolved == null || !File(resolved).existsSync()) {
    return null;
  }
  return resolved;
}

String _clamp(String text, int limit) {
  final trimmed = text.trim();
  return trimmed.length <= limit
      ? trimmed
      : '${trimmed.substring(0, limit)}\n…(cut short)';
}

bool _looksBinary(List<int> bytes) {
  final sample = bytes.take(2048);
  var suspicious = 0;
  for (final byte in sample) {
    if (byte == 0) {
      return true;
    }
    if (byte < 9 || (byte > 13 && byte < 32)) {
      suspicious++;
    }
  }
  return suspicious > sample.length * 0.1;
}
