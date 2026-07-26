import 'package:flutter/material.dart';

/// A normalized document model shared by the Markdown and HTML renderers.
///
/// Both parsers lower their source into these blocks, so a heading authored in
/// Markdown and one authored in HTML render through exactly the same
/// typography, spacing and colours. Nothing here knows about CSS.
@immutable
sealed class DocumentBlock {
  const DocumentBlock();
}

class DocumentHeadingBlock extends DocumentBlock {
  const DocumentHeadingBlock({required this.level, required this.text});

  /// 1-6, matching Markdown and HTML heading levels.
  final int level;
  final DocumentInline text;
}

class DocumentParagraphBlock extends DocumentBlock {
  const DocumentParagraphBlock(this.text, {this.lead = false});

  final DocumentInline text;

  /// Renders as an introductory paragraph.
  final bool lead;
}

class DocumentQuoteBlock extends DocumentBlock {
  const DocumentQuoteBlock(this.children);

  final List<DocumentBlock> children;
}

/// Tone of a modern callout. Mirrors GitHub alert syntax.
enum DocumentCalloutTone { note, tip, important, warning, caution }

class DocumentCalloutBlock extends DocumentBlock {
  const DocumentCalloutBlock({
    required this.tone,
    required this.children,
    this.title,
  });

  final DocumentCalloutTone tone;
  final String? title;
  final List<DocumentBlock> children;
}

class DocumentCodeBlock extends DocumentBlock {
  const DocumentCodeBlock({required this.code, this.language});

  final String code;
  final String? language;
}

class DocumentListItem {
  const DocumentListItem({required this.children, this.checked});

  final List<DocumentBlock> children;

  /// Non-null for task list items; drives the native checklist rendering.
  final bool? checked;
}

class DocumentListBlock extends DocumentBlock {
  const DocumentListBlock({
    required this.items,
    this.ordered = false,
    this.start = 1,
  });

  final List<DocumentListItem> items;
  final bool ordered;
  final int start;
}

class DocumentTableBlock extends DocumentBlock {
  const DocumentTableBlock({
    required this.rows,
    this.hasHeader = true,
    this.alignments = const [],
  });

  /// Row-major cells. The first row is the header when [hasHeader].
  final List<List<DocumentInline>> rows;
  final bool hasHeader;
  final List<TextAlign?> alignments;

  int get columnCount =>
      rows.fold(0, (widest, row) => row.length > widest ? row.length : widest);
}

class DocumentDividerBlock extends DocumentBlock {
  const DocumentDividerBlock();
}

class DocumentImageBlock extends DocumentBlock {
  const DocumentImageBlock({
    required this.source,
    this.alt,
    this.width,
    this.height,
    this.alignment = TextAlign.start,
  });

  final String source;
  final String? alt;

  /// Intrinsic dimensions when the source declares them.
  ///
  /// Reserving this space up front is what prevents images from shifting the
  /// reading position while a long document is being scrolled.
  final double? width;
  final double? height;

  /// Horizontal placement inherited from the authoring markup.
  final TextAlign alignment;
}

/// Several images that belong on one line, such as a row of badges.
///
/// Stacking these as full-width blocks would turn a compact badge strip into a
/// screen of empty boxes, so they stay together and keep their own size.
class DocumentImageRowBlock extends DocumentBlock {
  const DocumentImageRowBlock({
    required this.images,
    this.alignment = TextAlign.start,
  });

  final List<DocumentImageBlock> images;
  final TextAlign alignment;
}

/// A short run of styled text.
@immutable
class DocumentInlineSpan {
  const DocumentInlineSpan({
    required this.text,
    this.bold = false,
    this.italic = false,
    this.strikethrough = false,
    this.code = false,
    this.link,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strikethrough;
  final bool code;
  final String? link;

  DocumentInlineSpan copyWith({
    String? text,
    bool? bold,
    bool? italic,
    bool? strikethrough,
    bool? code,
    String? link,
  }) =>
      DocumentInlineSpan(
        text: text ?? this.text,
        bold: bold ?? this.bold,
        italic: italic ?? this.italic,
        strikethrough: strikethrough ?? this.strikethrough,
        code: code ?? this.code,
        link: link ?? this.link,
      );
}

/// An immutable inline run used by paragraphs, headings and table cells.
@immutable
class DocumentInline {
  const DocumentInline(this.spans);

  const DocumentInline.empty() : spans = const [];

  factory DocumentInline.text(String value) =>
      DocumentInline([DocumentInlineSpan(text: value)]);

  final List<DocumentInlineSpan> spans;

  bool get isEmpty => spans.every((span) => span.text.trim().isEmpty);

  String get plainText => spans.map((span) => span.text).join();
}
