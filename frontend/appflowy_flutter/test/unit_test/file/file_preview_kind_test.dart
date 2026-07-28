import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/material.dart';

void main() {
  group('filePreviewKindFromName', () {
    test('detects supported rich previews case-insensitively', () {
      expect(filePreviewKindFromName('guide.PDF'), FilePreviewKind.pdf);
      expect(filePreviewKindFromName('page.html'), FilePreviewKind.html);
      expect(filePreviewKindFromName('readme.md'), FilePreviewKind.markdown);
      expect(filePreviewKindFromName('data.csv'), FilePreviewKind.csv);
      expect(filePreviewKindFromName('code.cpp'), FilePreviewKind.code);
      expect(
        filePreviewKindFromName('notebook.ipynb'),
        FilePreviewKind.notebook,
      );
      expect(filePreviewKindFromName('bundle.zip'), FilePreviewKind.archive);
    });

    test('routes Office documents to embedded Office previews', () {
      for (final name in [
        'file.docx',
        'file.xlsx',
        'file.pptx',
        'file.rtf',
      ]) {
        expect(filePreviewKindFromName(name), isNull);
        expect(isOfficeFile(name), isTrue);
        expect(supportsEmbeddedFilePreview(name), isTrue);
      }
    });

    test('does not preview unsupported binary files', () {
      expect(filePreviewKindFromName('binary.exe'), isNull);
      expect(supportsEmbeddedFilePreview('binary.exe'), isFalse);
    });

    test('recognises every archive container it can browse', () {
      for (final name in [
        'bundle.tar',
        'bundle.tar.gz',
        'bundle.tgz',
        'bundle.tar.bz2',
        'bundle.tar.xz',
        'notes.txt.gz',
      ]) {
        expect(filePreviewKindFromName(name), FilePreviewKind.archive);
      }
      // Nothing bundled can unpack these, so they stay plain attachments.
      expect(filePreviewKindFromName('bundle.7z'), isNull);
      expect(filePreviewKindFromName('bundle.rar'), isNull);
      expect(fileIconForName('bundle.7z'), Icons.folder_zip_rounded);
    });

    test('uses extension-specific icons for generic file blocks', () {
      expect(fileIconForName('paper.pdf'), Icons.picture_as_pdf_rounded);
      expect(fileIconForName('source.py'), Icons.code_rounded);
      expect(fileIconForName('data.csv'), Icons.table_chart_rounded);
      expect(fileIconForName('unknown.bin'), Icons.insert_drive_file_rounded);
    });

    test('keeps WebView trackpad ownership inside the preview', () {
      expect(FilePreviewKind.pdf.usesFrameScrollGuard, isTrue);
      expect(FilePreviewKind.html.usesFrameScrollGuard, isFalse);
      expect(FilePreviewKind.markdown.usesFrameScrollGuard, isFalse);
    });
  });
}
