import 'dart:convert';

import '../archive/archive_document.dart';

/// The most text a preview reads out of an Office package.
const int maxOfficePreviewCharacters = 4000;

/// Pulls the readable text out of an Office document for a preview.
///
/// Every modern Office format is a zip of XML, so the words are already there
/// without a document server: a paragraph run in Word, a shared string in
/// Excel, a text run on a slide. Returns null when the package holds nothing
/// worth showing.
String? extractOfficeDocumentText(
  ArchiveDocument document,
  String name, {
  int maxCharacters = maxOfficePreviewCharacters,
}) {
  final extension = name.split('.').last.toLowerCase();
  final lines = switch (extension) {
    'docx' => _readRuns(document, 'word/document.xml', 'w:t', 'w:p'),
    'xlsx' => _readSpreadsheet(document),
    'pptx' => _readSlides(document),
    'odt' || 'ods' || 'odp' => _readOpenDocument(document),
    _ => const <String>[],
  };
  if (lines.isEmpty) {
    return null;
  }

  final buffer = StringBuffer();
  for (final line in lines) {
    if (buffer.length + line.length + 1 > maxCharacters) {
      break;
    }
    buffer
      ..write(line)
      ..write('\n');
  }
  final text = buffer.toString().trim();
  return text.isEmpty ? null : text;
}

/// Reads the text runs of one XML part, one line per [blockTag].
List<String> _readRuns(
  ArchiveDocument document,
  String part,
  String textTag,
  String blockTag,
) {
  final xml = _readPart(document, part);
  if (xml == null) {
    return const [];
  }
  final runs = RegExp('<$textTag\\b[^>]*>(.*?)</$textTag>', dotAll: true);
  final lines = <String>[];
  for (final block in xml.split('</$blockTag>')) {
    final line = runs
        .allMatches(block)
        .map((match) => _unescape(match.group(1) ?? ''))
        .join()
        .trim();
    if (line.isNotEmpty) {
      lines.add(line);
    }
  }
  return lines;
}

/// The first sheet of a workbook, read as rows of cells.
///
/// The shared string table alone would miss a sheet made of numbers, so the
/// worksheet itself is walked and its string references resolved.
List<String> _readSpreadsheet(ArchiveDocument document, {int maxRows = 40}) {
  final shared = _readRuns(document, 'xl/sharedStrings.xml', 't', 'si');
  final sheet = _firstWorksheet(document);
  final xml = sheet == null ? null : _readPart(document, sheet);
  if (xml == null) {
    return shared.take(maxRows).toList();
  }

  final rowPattern = RegExp(r'<row\b[^>]*>(.*?)</row>', dotAll: true);
  final lines = <String>[];
  for (final row in rowPattern.allMatches(xml)) {
    final cells = _readCells(row.group(1) ?? '', shared);
    final line = cells.join('   ').trimRight();
    if (line.isNotEmpty) {
      lines.add(line);
    }
    if (lines.length >= maxRows) {
      break;
    }
  }
  return lines.isEmpty ? shared.take(maxRows).toList() : lines;
}

final _cellPattern = RegExp(r'<c\b([^>]*?)(?:/>|>(.*?)</c>)', dotAll: true);
final _cellTypePattern = RegExp('t="([^"]*)"');
final _cellValuePattern = RegExp(r'<v\b[^>]*>(.*?)</v>', dotAll: true);
final _inlineTextPattern = RegExp(r'<t\b[^>]*>(.*?)</t>', dotAll: true);

List<String> _readCells(String row, List<String> shared) {
  final values = <String>[];
  for (final cell in _cellPattern.allMatches(row)) {
    final type = _cellTypePattern.firstMatch(cell.group(1) ?? '')?.group(1);
    final body = cell.group(2) ?? '';
    if (type == 'inlineStr') {
      values.add(
        _inlineTextPattern
            .allMatches(body)
            .map((match) => _unescape(match.group(1) ?? ''))
            .join(),
      );
      continue;
    }
    final raw = _unescape(_cellValuePattern.firstMatch(body)?.group(1) ?? '');
    if (type == 's') {
      final index = int.tryParse(raw);
      values.add(
        index != null && index >= 0 && index < shared.length
            ? shared[index]
            : '',
      );
      continue;
    }
    values.add(raw);
  }
  return values;
}

String? _firstWorksheet(ArchiveDocument document) {
  final sheets = document.paths
      .where(
        (path) => path.startsWith('xl/worksheets/') && path.endsWith('.xml'),
      )
      .toList()
    ..sort((a, b) => _trailingNumber(a).compareTo(_trailingNumber(b)));
  return sheets.isEmpty ? null : sheets.first;
}

int _trailingNumber(String path) {
  final digits = RegExp(r'(\d+)\.xml$').firstMatch(path)?.group(1);
  return int.tryParse(digits ?? '') ?? 0;
}

/// Slides in the order they are presented, each headed by its number.
List<String> _readSlides(ArchiveDocument document) {
  final slides = document.paths
      .where(
        (path) => path.startsWith('ppt/slides/slide') && path.endsWith('.xml'),
      )
      .toList()
    ..sort((a, b) => _slideNumber(a).compareTo(_slideNumber(b)));

  final lines = <String>[];
  for (final slide in slides) {
    final text = _readRuns(document, slide, 'a:t', 'a:p');
    if (text.isEmpty) {
      continue;
    }
    if (lines.isNotEmpty) {
      lines.add('');
    }
    lines
      ..add('Slide ${_slideNumber(slide)}')
      ..addAll(text);
  }
  return lines;
}

int _slideNumber(String path) {
  final digits = RegExp(r'slide(\d+)\.xml$').firstMatch(path)?.group(1);
  return int.tryParse(digits ?? '') ?? 0;
}

/// OpenDocument keeps its text in one part, marked up with `text:` tags.
List<String> _readOpenDocument(ArchiveDocument document) {
  final xml = _readPart(document, 'content.xml');
  if (xml == null) {
    return const [];
  }
  final paragraphs = RegExp(
    r'<text:(?:p|h)\b[^>]*>(.*?)</text:(?:p|h)>',
    dotAll: true,
  );
  final tags = RegExp('<[^>]*>');
  return paragraphs
      .allMatches(xml)
      .map((match) => _unescape((match.group(1) ?? '').replaceAll(tags, '')))
      .map((line) => line.trim())
      .where((line) => line.isNotEmpty)
      .toList();
}

String? _readPart(ArchiveDocument document, String path) {
  try {
    return const Utf8Decoder(allowMalformed: true)
        .convert(document.readBytes(path));
  } on ArchiveDocumentException {
    return null;
  }
}

/// Turns XML character references back into the characters they stand for.
String _unescape(String value) {
  if (!value.contains('&')) {
    return value;
  }
  return value
      .replaceAllMapped(
        RegExp('&#x([0-9a-fA-F]+);'),
        (match) => _codePoint(int.tryParse(match.group(1)!, radix: 16)),
      )
      .replaceAllMapped(
        RegExp(r'&#(\d+);'),
        (match) => _codePoint(int.tryParse(match.group(1)!)),
      )
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&quot;', '"')
      .replaceAll('&apos;', "'")
      .replaceAll('&amp;', '&');
}

String _codePoint(int? value) {
  if (value == null || value < 0 || value > 0x10FFFF) {
    return '';
  }
  return String.fromCharCode(value);
}
