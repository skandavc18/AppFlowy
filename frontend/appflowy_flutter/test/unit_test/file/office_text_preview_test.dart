import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/document/presentation/editor_plugins/file/archive/archive_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/office/office_text_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/blank_file_content.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

ArchiveDocument _package(Map<String, String> parts) {
  final archive = Archive();
  for (final entry in parts.entries) {
    final bytes = Uint8List.fromList(utf8.encode(entry.value));
    archive.addFile(ArchiveFile(entry.key, bytes.length, bytes));
  }
  return ArchiveDocument.fromBytes(
    Uint8List.fromList(ZipEncoder().encode(archive)!),
  );
}

void main() {
  group('extractOfficeDocumentText', () {
    test('reads the paragraphs of a Word document', () {
      final document = _package({
        'word/document.xml': '<w:document><w:body>'
            '<w:p><w:r><w:t>Quarterly </w:t></w:r>'
            '<w:r><w:t>report</w:t></w:r></w:p>'
            '<w:p><w:r><w:t>Revenue &amp; costs</w:t></w:r></w:p>'
            '<w:p/>'
            '</w:body></w:document>',
      });

      expect(
        extractOfficeDocumentText(document, 'report.docx'),
        'Quarterly report\nRevenue & costs',
      );
    });

    test('reads the shared strings of a spreadsheet', () {
      final document = _package({
        'xl/sharedStrings.xml': '<sst>'
            '<si><t>Product</t></si>'
            '<si><t>Units sold</t></si>'
            '</sst>',
      });

      expect(
        extractOfficeDocumentText(document, 'sales.xlsx'),
        'Product\nUnits sold',
      );
    });

    test('reads a worksheet grid, numbers and all', () {
      final document = _package({
        'xl/sharedStrings.xml': '<sst><si><t>Product</t></si>'
            '<si><t>Widget</t></si></sst>',
        'xl/worksheets/sheet1.xml': '<worksheet><sheetData>'
            '<row r="1"><c r="A1" t="s"><v>0</v></c>'
            '<c r="B1" t="inlineStr"><is><t>Units</t></is></c></row>'
            '<row r="2"><c r="A2" t="s"><v>1</v></c>'
            '<c r="B2"><v>1250</v></c></row>'
            '<row r="3"><c r="A3"/></row>'
            '</sheetData></worksheet>',
      });

      expect(
        extractOfficeDocumentText(document, 'sales.xlsx'),
        'Product   Units\nWidget   1250',
      );
    });

    test('falls back to the shared strings when there is no sheet', () {
      final document = _package({
        'xl/sharedStrings.xml': '<sst><si><t>Only strings</t></si></sst>',
      });

      expect(
        extractOfficeDocumentText(document, 'sales.xlsx'),
        'Only strings',
      );
    });

    test('reads slides in the order they are presented', () {
      final document = _package({
        'ppt/slides/slide10.xml':
            '<p:sld><a:p><a:r><a:t>Last</a:t></a:r></a:p></p:sld>',
        'ppt/slides/slide2.xml':
            '<p:sld><a:p><a:r><a:t>Middle</a:t></a:r></a:p></p:sld>',
        'ppt/slides/slide1.xml':
            '<p:sld><a:p><a:r><a:t>First</a:t></a:r></a:p></p:sld>',
      });

      expect(
        extractOfficeDocumentText(document, 'deck.pptx'),
        'Slide 1\nFirst\n\nSlide 2\nMiddle\n\nSlide 10\nLast',
      );
    });

    test('reads the body of an OpenDocument file', () {
      final document = _package({
        'content.xml': '<office:body><office:text>'
            '<text:h>Notes</text:h>'
            '<text:p>A <text:span>styled</text:span> line</text:p>'
            '</office:text></office:body>',
      });

      expect(
        extractOfficeDocumentText(document, 'notes.odt'),
        'Notes\nA styled line',
      );
    });

    test('stops once the preview has enough text', () {
      final paragraphs = List.generate(
        200,
        (index) =>
            '<w:p><w:r><w:t>line $index padded out with words</w:t></w:r></w:p>',
      ).join();
      final document = _package({
        'word/document.xml': '<w:body>$paragraphs</w:body>',
      });

      final text = extractOfficeDocumentText(
        document,
        'long.docx',
        maxCharacters: 120,
      );
      expect(text, isNotNull);
      expect(text!.length, lessThanOrEqualTo(120));
      expect(text, startsWith('line 0'));
    });

    test('reports nothing for a package with no readable part', () {
      final document = _package({'word/settings.xml': '<w:settings/>'});
      expect(extractOfficeDocumentText(document, 'empty.docx'), isNull);
      expect(extractOfficeDocumentText(document, 'photo.png'), isNull);
    });
  });

  group('opening an Office package from disk', () {
    late Directory directory;

    setUp(() async {
      directory = await Directory.systemTemp.createTemp('office_preview_test');
    });

    tearDown(() async {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    });

    /// The extension of an Office file never names its container, so reading
    /// one without saying "zip" is refused outright. Forgetting that is what
    /// made every Office preview fall back to a plain file card.
    test('needs the container spelled out', () async {
      final file = File('${directory.path}/report.docx');
      await file.writeAsBytes(
        blankFileContent(WorkspaceFileKind.word),
      );

      await expectLater(
        ArchiveDocument.read(file),
        throwsA(isA<ArchiveDocumentException>()),
      );

      final document = await ArchiveDocument.read(
        file,
        format: ArchiveFormat.zip,
      );
      expect(document.containsPath('word/document.xml'), isTrue);
    });

    test('reads the text of a document written to disk', () async {
      final archive = Archive();
      const xml = '<w:body><w:p><w:r><w:t>Hello from disk</w:t></w:r>'
          '</w:p></w:body>';
      final bytes = Uint8List.fromList(utf8.encode(xml));
      archive.addFile(
        ArchiveFile('word/document.xml', bytes.length, bytes),
      );
      final file = File('${directory.path}/note.docx');
      await file.writeAsBytes(
        Uint8List.fromList(ZipEncoder().encode(archive)!),
      );

      final document = await ArchiveDocument.read(
        file,
        format: ArchiveFormat.zip,
      );
      expect(
        extractOfficeDocumentText(document, 'note.docx'),
        'Hello from disk',
      );
    });
  });
}
