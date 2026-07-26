import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('source editing', () {
    test('rendered previews expose editing, transformed ones do not', () {
      // These render their source, so showing it raw is a faithful round trip.
      expect(FilePreviewKind.markdown.supportsSourceEditing, isTrue);
      expect(FilePreviewKind.html.supportsSourceEditing, isTrue);
      expect(FilePreviewKind.text.supportsSourceEditing, isTrue);

      // Code is already editable the moment it opens.
      expect(FilePreviewKind.code.supportsSourceEditing, isFalse);

      // These reinterpret the file — pretty printing, decoding, rendering —
      // so writing the displayed text back would corrupt the original.
      expect(FilePreviewKind.json.supportsSourceEditing, isFalse);
      expect(FilePreviewKind.csv.supportsSourceEditing, isFalse);
      expect(FilePreviewKind.notebook.supportsSourceEditing, isFalse);
      expect(FilePreviewKind.archive.supportsSourceEditing, isFalse);
      expect(FilePreviewKind.pdf.supportsSourceEditing, isFalse);
    });

    test('editing highlights the source with its own grammar', () {
      expect(FilePreviewKind.markdown.sourceLanguage, 'markdown');
      expect(FilePreviewKind.html.sourceLanguage, 'html');
      expect(FilePreviewKind.text.sourceLanguage, 'text');
    });

    test('the edit flag is stored under a stable metadata key', () {
      expect(filePreviewEditModeKey, 'edit_mode');
    });
  });
}
