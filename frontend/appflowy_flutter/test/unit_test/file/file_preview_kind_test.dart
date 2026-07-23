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

    test('keeps Office documents as regular file blocks', () {
      for (final name in ['file.docx', 'file.xlsx', 'file.pptx']) {
        expect(filePreviewKindFromName(name), isNull);
        expect(isOfficeFile(name), isTrue);
      }
    });

    test('does not preview unsupported binary files', () {
      expect(filePreviewKindFromName('binary.exe'), isNull);
    });

    test('uses extension-specific icons for generic file blocks', () {
      expect(fileIconForName('paper.pdf'), Icons.picture_as_pdf_outlined);
      expect(fileIconForName('source.py'), Icons.code);
      expect(fileIconForName('data.csv'), Icons.table_chart_outlined);
      expect(fileIconForName('unknown.bin'), Icons.insert_drive_file_outlined);
    });

    test('keeps WebView trackpad ownership inside the preview', () {
      expect(FilePreviewKind.pdf.usesFrameScrollGuard, isTrue);
      expect(FilePreviewKind.html.usesFrameScrollGuard, isFalse);
      expect(FilePreviewKind.markdown.usesFrameScrollGuard, isFalse);
    });
  });
}
