import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'document_content.dart';
import 'document_content_view.dart';
import 'document_normalizer.dart';
import 'document_scroll.dart';
import 'document_typography.dart';
import 'document_viewport.dart';
import 'document_viewer_theme.dart';

/// Plain text and log files, rendered on the shared page surface.
///
/// The body is chunked so a hundred-megabyte log still virtualizes cleanly
/// while remaining fully selectable through the ambient [SelectionArea].
class DocumentPlainTextView extends StatelessWidget {
  const DocumentPlainTextView({
    super.key,
    required this.controller,
    required this.text,
    this.monospace = true,
    this.scale = 1,
  });

  final DocumentScrollController controller;
  final String text;
  final bool monospace;
  final double scale;

  /// Lines per virtualized chunk. Small enough to keep layout cheap, large
  /// enough that scrolling never builds hundreds of widgets per frame.
  static const int linesPerChunk = 120;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme, scale: scale);
    final chunks = chunkDocumentText(text, linesPerChunk);

    if (chunks.isEmpty) {
      return DocumentViewport.child(
        controller: controller,
        fillViewport: true,
        child: Center(
          child: Text('This file is empty.', style: typography.caption),
        ),
      );
    }

    return SelectionArea(
      child: DocumentViewport.list(
        controller: controller,
        itemCount: chunks.length,
        maxContentWidth: monospace
            ? DocumentViewerTheme.wideReadingWidth
            : DocumentViewerTheme.readingWidth,
        itemBuilder: (context, index) => Text(
          chunks[index],
          style: monospace
              ? typography.code.copyWith(height: 1.7)
              : typography.body,
        ),
      ),
    );
  }
}

/// Splits text into chunks of at most [linesPerChunk] lines.
List<String> chunkDocumentText(String text, int linesPerChunk) {
  if (text.isEmpty) {
    return const [];
  }
  final lines = const LineSplitter().convert(text);
  if (lines.isEmpty) {
    return const [];
  }
  return [
    for (var start = 0; start < lines.length; start += linesPerChunk)
      lines
          .sublist(start, math.min(start + linesPerChunk, lines.length))
          .join('\n'),
  ];
}

/// A delimited data file presented as an elegant, virtualized table.
class DocumentDataTableView extends StatelessWidget {
  const DocumentDataTableView({
    super.key,
    required this.controller,
    required this.rows,
    this.hasHeader = true,
    this.scale = 1,
  });

  final DocumentScrollController controller;
  final List<List<String>> rows;
  final bool hasHeader;
  final double scale;

  /// Column widths are derived once so virtualized rows never reflow.
  static const double minColumnWidth = 96;
  static const double maxColumnWidth = 320;
  static const double approximateGlyphWidth = 7.6;
  static const double cellHorizontalPadding = 14;

  static List<double> resolveColumnWidths(List<List<String>> rows) {
    final columns = rows.fold<int>(
      0,
      (widest, row) => row.length > widest ? row.length : widest,
    );
    final widths = List<double>.filled(columns, minColumnWidth);
    // Sampling the head of the file keeps opening a huge CSV instant.
    final sampled = rows.take(200);
    for (final row in sampled) {
      for (var index = 0; index < row.length; index++) {
        final measured = row[index].length * approximateGlyphWidth +
            cellHorizontalPadding * 2;
        widths[index] = measured.clamp(minColumnWidth, maxColumnWidth);
      }
    }
    return widths;
  }

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme, scale: scale);
    if (rows.isEmpty) {
      return DocumentViewport.child(
        controller: controller,
        fillViewport: true,
        child: Center(
          child: Text('This table is empty.', style: typography.caption),
        ),
      );
    }

    final widths = resolveColumnWidths(rows);
    final totalWidth = widths.fold<double>(0, (sum, width) => sum + width);

    return SelectionArea(
      child: DocumentViewport.list(
        controller: controller,
        maxContentWidth: math.max(
          DocumentViewerTheme.readingWidth,
          math.min(totalWidth, DocumentViewerTheme.wideReadingWidth),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        itemCount: rows.length,
        itemBuilder: (context, index) => _DataRow(
          cells: rows[index],
          widths: widths,
          typography: typography,
          isHeader: hasHeader && index == 0,
          striped: index.isOdd,
        ),
      ),
    );
  }
}

class _DataRow extends StatelessWidget {
  const _DataRow({
    required this.cells,
    required this.widths,
    required this.typography,
    required this.isHeader,
    required this.striped,
  });

  final List<String> cells;
  final List<double> widths;
  final DocumentTypography typography;
  final bool isHeader;
  final bool striped;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isHeader
            ? theme.control
            : striped
                ? theme.control.withValues(alpha: 0.35)
                : null,
        border: Border(
          bottom: BorderSide(color: theme.hairline, width: 0.6),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < widths.length; index++)
            SizedBox(
              width: widths[index],
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: DocumentDataTableView.cellHorizontalPadding,
                  vertical: 9,
                ),
                child: Text(
                  index < cells.length ? cells[index] : '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style:
                      isHeader ? typography.tableHeader : typography.tableCell,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A parsed notebook cell.
@immutable
class DocumentNotebookCell {
  const DocumentNotebookCell({
    required this.markdown,
    required this.source,
    this.output,
    this.executionCount,
  });

  final bool markdown;
  final String source;
  final String? output;
  final int? executionCount;
}

/// Reads Jupyter notebook JSON into renderable cells.
List<DocumentNotebookCell> parseNotebookCells(Map<String, dynamic> document) {
  final cells = document['cells'];
  if (cells is! List) {
    return const [];
  }
  final parsed = <DocumentNotebookCell>[];
  for (final cell in cells) {
    if (cell is! Map) {
      continue;
    }
    final source = cell['source'];
    final text = source is List ? source.join() : source?.toString() ?? '';
    final isMarkdown = cell['cell_type'] == 'markdown';
    String? output;
    if (!isMarkdown) {
      final outputs = cell['outputs'];
      if (outputs is List) {
        final buffer = StringBuffer();
        for (final entry in outputs.whereType<Map>()) {
          final text = entry['text'];
          if (text is List) {
            buffer.write(text.join());
          } else if (text is String) {
            buffer.write(text);
          }
          final data = entry['data'];
          if (data is Map && data['text/plain'] != null) {
            final plain = data['text/plain'];
            buffer.write(plain is List ? plain.join() : plain.toString());
          }
        }
        output = buffer.isEmpty ? null : buffer.toString().trimRight();
      }
    }
    parsed.add(
      DocumentNotebookCell(
        markdown: isMarkdown,
        source: text.trimRight(),
        output: output,
        executionCount: cell['execution_count'] is int
            ? cell['execution_count'] as int
            : null,
      ),
    );
  }
  return parsed;
}

/// Notebooks: prose cells read as prose, code cells read as code.
class DocumentNotebookView extends StatelessWidget {
  const DocumentNotebookView({
    super.key,
    required this.controller,
    required this.cells,
    this.language,
    this.onOpenLink,
    this.scale = 1,
  });

  final DocumentScrollController controller;
  final List<DocumentNotebookCell> cells;
  final String? language;
  final ValueChanged<String>? onOpenLink;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme, scale: scale);

    if (cells.isEmpty) {
      return DocumentViewport.child(
        controller: controller,
        fillViewport: true,
        child: Center(
          child: Text('This notebook is empty.', style: typography.caption),
        ),
      );
    }

    return SelectionArea(
      child: DocumentViewport.list(
        controller: controller,
        itemCount: cells.length,
        itemBuilder: (context, index) => Padding(
          padding: EdgeInsets.only(top: index == 0 ? 0 : 22),
          child: _NotebookCell(
            cell: cells[index],
            typography: typography,
            language: language,
            onOpenLink: onOpenLink,
          ),
        ),
      ),
    );
  }
}

class _NotebookCell extends StatelessWidget {
  const _NotebookCell({
    required this.cell,
    required this.typography,
    this.language,
    this.onOpenLink,
  });

  final DocumentNotebookCell cell;
  final DocumentTypography typography;
  final String? language;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);

    if (cell.markdown) {
      final blocks = DocumentNormalizer.fromMarkdown(cell.source);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var index = 0; index < blocks.length; index++)
            Padding(
              padding: EdgeInsets.only(
                top: documentBlockSpacing(
                  blocks[index],
                  index == 0 ? null : blocks[index - 1],
                  typography,
                ),
              ),
              child: DocumentBlockView(
                block: blocks[index],
                typography: typography,
                onOpenLink: onOpenLink,
              ),
            ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (cell.executionCount != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Text(
              'In [${cell.executionCount}]',
              style: typography.overline.copyWith(fontSize: 10.5),
            ),
          ),
        DocumentCodeSurface(
          code: cell.source,
          language: language,
          typography: typography,
        ),
        if (cell.output != null) ...[
          const SizedBox(height: 10),
          DocumentPanel(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
            color: theme.control,
            borderColor: theme.hairline,
            child: Text(
              cell.output!,
              style: typography.code.copyWith(color: theme.textSecondary),
            ),
          ),
        ],
      ],
    );
  }
}

/// One row of an archive listing.
@immutable
class DocumentArchiveEntry {
  const DocumentArchiveEntry({
    required this.name,
    required this.size,
    required this.isDirectory,
  });

  final String name;
  final int size;
  final bool isDirectory;
}

/// Archive contents: a calm, readable listing rather than a file manager.
class DocumentArchiveView extends StatelessWidget {
  const DocumentArchiveView({
    super.key,
    required this.controller,
    required this.entries,
    this.scale = 1,
  });

  final DocumentScrollController controller;
  final List<DocumentArchiveEntry> entries;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme, scale: scale);

    if (entries.isEmpty) {
      return DocumentViewport.child(
        controller: controller,
        fillViewport: true,
        child: Center(
          child: Text('This archive is empty.', style: typography.caption),
        ),
      );
    }

    return DocumentViewport.list(
      controller: controller,
      itemCount: entries.length,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 20),
      itemBuilder: (context, index) => _ArchiveRow(
        entry: entries[index],
        typography: typography,
      ),
    );
  }
}

class _ArchiveRow extends StatelessWidget {
  const _ArchiveRow({required this.entry, required this.typography});

  final DocumentArchiveEntry entry;
  final DocumentTypography typography;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.hairline, width: 0.6)),
      ),
      child: Row(
        children: [
          Icon(
            entry.isDirectory
                ? Icons.folder_outlined
                : Icons.description_outlined,
            size: 15,
            color: theme.iconMuted,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              entry.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typography.tableCell,
            ),
          ),
          if (!entry.isDirectory)
            Text(
              _formatSize(entry.size),
              style: typography.caption.copyWith(
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
        ],
      ),
    );
  }

  static String _formatSize(int bytes) {
    if (bytes < 1024) {
      return '$bytes B';
    }
    const units = ['KB', 'MB', 'GB'];
    var value = bytes / 1024;
    var unit = 0;
    while (value >= 1024 && unit < units.length - 1) {
      value /= 1024;
      unit++;
    }
    return '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ${units[unit]}';
  }
}

/// Splits a delimited line, honouring quoted fields.
List<String> parseDelimitedLine(String line, String separator) {
  final cells = <String>[];
  final buffer = StringBuffer();
  var quoted = false;
  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (character == '"') {
      if (quoted && index + 1 < line.length && line[index + 1] == '"') {
        buffer.write('"');
        index++;
        continue;
      }
      quoted = !quoted;
      continue;
    }
    if (!quoted && character == separator) {
      cells.add(buffer.toString());
      buffer.clear();
      continue;
    }
    buffer.write(character);
  }
  cells.add(buffer.toString());
  return cells;
}

/// Parses a delimited document into rows, capped at [maxRows].
List<List<String>> parseDelimitedDocument(
  String text,
  String separator, {
  int maxRows = 5000,
}) {
  return [
    for (final line in const LineSplitter().convert(text).take(maxRows))
      if (line.trim().isNotEmpty) parseDelimitedLine(line, separator),
  ];
}

/// Blocks describing an unsupported or unreadable document.
List<DocumentBlock> documentPlaceholderBlocks(String message) => [
      DocumentParagraphBlock(DocumentInline.text(message), lead: true),
    ];
