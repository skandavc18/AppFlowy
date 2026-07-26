import 'dart:math' as math;

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'document_content.dart';
import 'document_image.dart';
import 'document_scroll.dart';
import 'document_typography.dart';
import 'document_viewport.dart';
import 'document_viewer_theme.dart';

/// Renders normalized document blocks inside the shared reading viewport.
///
/// The list is virtualized and every block is isolated behind a repaint
/// boundary, so a thousand-block Markdown or HTML document scrolls without
/// rebuilding or repainting anything outside the viewport.
class DocumentContentView extends StatelessWidget {
  const DocumentContentView({
    super.key,
    required this.controller,
    required this.blocks,
    this.onOpenLink,
    this.maxContentWidth = DocumentViewerTheme.readingWidth,
    this.padding,
    this.scale = 1,
    this.semanticLabel,
  });

  final DocumentScrollController controller;
  final List<DocumentBlock> blocks;
  final ValueChanged<String>? onOpenLink;
  final double maxContentWidth;
  final EdgeInsets? padding;

  /// Reader zoom, applied to the whole typographic scale.
  final double scale;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme, scale: scale);

    if (blocks.isEmpty) {
      return DocumentViewport.child(
        controller: controller,
        maxContentWidth: maxContentWidth,
        padding: padding,
        fillViewport: true,
        child: Center(
          child: Text('This document is empty.', style: typography.caption),
        ),
      );
    }

    return SelectionArea(
      child: DocumentViewport.list(
        controller: controller,
        itemCount: blocks.length,
        maxContentWidth: maxContentWidth,
        padding: padding,
        semanticLabel: semanticLabel,
        itemBuilder: (context, index) {
          final block = blocks[index];
          final previous = index == 0 ? null : blocks[index - 1];
          return Padding(
            padding: EdgeInsets.only(
              top: documentBlockSpacing(block, previous, typography),
            ),
            child: DocumentBlockView(
              block: block,
              typography: typography,
              onOpenLink: onOpenLink,
            ),
          );
        },
      ),
    );
  }
}

/// Vertical rhythm between two consecutive blocks.
///
/// Headings claim space above themselves, related list items sit close
/// together, and the very first block never gets a leading gap.
double documentBlockSpacing(
  DocumentBlock block,
  DocumentBlock? previous,
  DocumentTypography typography,
) {
  if (previous == null) {
    return 0;
  }
  if (block is DocumentHeadingBlock) {
    return typography.spaceAboveHeading(block.level);
  }
  if (previous is DocumentHeadingBlock) {
    return typography.spaceBelowHeading(previous.level);
  }
  return switch (block) {
    DocumentDividerBlock() => 30,
    DocumentImageBlock() => 24,
    DocumentImageRowBlock() =>
      previous is DocumentImageRowBlock || previous is DocumentImageBlock
          ? 10
          : 20,
    DocumentTableBlock() => 22,
    DocumentCodeBlock() => 20,
    DocumentCalloutBlock() => 20,
    DocumentQuoteBlock() => 20,
    DocumentListBlock() => previous is DocumentListBlock ? 8 : 16,
    _ => 16,
  };
}

/// Renders one block. Recursive for quotes, callouts and list items.
class DocumentBlockView extends StatelessWidget {
  const DocumentBlockView({
    super.key,
    required this.block,
    required this.typography,
    this.onOpenLink,
  });

  final DocumentBlock block;
  final DocumentTypography typography;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    return switch (block) {
      final DocumentHeadingBlock heading => DocumentInlineText(
          inline: heading.text,
          style: typography.headingFor(heading.level),
          typography: typography,
          onOpenLink: onOpenLink,
        ),
      final DocumentParagraphBlock paragraph => DocumentInlineText(
          inline: paragraph.text,
          style: paragraph.lead ? typography.lead : typography.body,
          typography: typography,
          onOpenLink: onOpenLink,
        ),
      final DocumentQuoteBlock quote => _Quote(
          block: quote,
          typography: typography,
          onOpenLink: onOpenLink,
        ),
      final DocumentCalloutBlock callout => _Callout(
          block: callout,
          typography: typography,
          onOpenLink: onOpenLink,
        ),
      final DocumentCodeBlock code => DocumentCodeSurface(
          code: code.code,
          language: code.language,
          typography: typography,
        ),
      final DocumentListBlock list => _List(
          block: list,
          typography: typography,
          onOpenLink: onOpenLink,
        ),
      final DocumentTableBlock table => _Table(
          block: table,
          typography: typography,
          onOpenLink: onOpenLink,
        ),
      DocumentDividerBlock() => const _Divider(),
      final DocumentImageBlock image => DocumentImageView(
          block: image,
          typography: typography,
        ),
      final DocumentImageRowBlock row => DocumentImageRowView(
          block: row,
          typography: typography,
        ),
    };
  }
}

/// Renders an inline run, owning its link gesture recognizers.
class DocumentInlineText extends StatefulWidget {
  const DocumentInlineText({
    super.key,
    required this.inline,
    required this.style,
    required this.typography,
    this.onOpenLink,
    this.textAlign,
    this.maxLines,
  });

  final DocumentInline inline;
  final TextStyle style;
  final DocumentTypography typography;
  final ValueChanged<String>? onOpenLink;
  final TextAlign? textAlign;
  final int? maxLines;

  @override
  State<DocumentInlineText> createState() => _DocumentInlineTextState();
}

class _DocumentInlineTextState extends State<DocumentInlineText> {
  final List<TapGestureRecognizer> recognizers = [];

  @override
  void dispose() {
    _releaseRecognizers();
    super.dispose();
  }

  void _releaseRecognizers() {
    for (final recognizer in recognizers) {
      recognizer.dispose();
    }
    recognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    _releaseRecognizers();

    return Text.rich(
      TextSpan(
        style: widget.style,
        children: [
          for (final span in widget.inline.spans)
            _buildSpan(context, theme, span),
        ],
      ),
      textAlign: widget.textAlign ?? TextAlign.start,
      maxLines: widget.maxLines,
      overflow:
          widget.maxLines == null ? TextOverflow.clip : TextOverflow.ellipsis,
    );
  }

  InlineSpan _buildSpan(
    BuildContext context,
    DocumentViewerTheme theme,
    DocumentInlineSpan span,
  ) {
    if (span.code) {
      return WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        baseline: TextBaseline.alphabetic,
        child: _InlineCode(
          text: span.text,
          style: widget.typography.inlineCode,
        ),
      );
    }

    final style = widget.style.copyWith(
      fontWeight: span.bold ? FontWeight.w700 : null,
      fontStyle: span.italic ? FontStyle.italic : null,
      decoration: span.strikethrough
          ? TextDecoration.lineThrough
          : span.link != null
              ? TextDecoration.underline
              : null,
      decorationColor: span.link != null
          ? theme.accent.withValues(alpha: 0.4)
          : theme.textMuted,
      decorationThickness: 1,
      color: span.strikethrough
          ? theme.textMuted
          : span.link != null
              ? theme.accent
              : widget.style.color,
    );

    final link = span.link;
    if (link == null || widget.onOpenLink == null) {
      return TextSpan(text: span.text, style: style);
    }

    final recognizer = TapGestureRecognizer()
      ..onTap = () => widget.onOpenLink!(link);
    recognizers.add(recognizer);
    return TextSpan(
      text: span.text,
      style: style,
      recognizer: recognizer,
      mouseCursor: SystemMouseCursors.click,
      semanticsLabel: span.text,
    );
  }
}

class _InlineCode extends StatelessWidget {
  const _InlineCode({required this.text, required this.style});

  final String text;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: theme.codeSurface,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: theme.codeBorder, width: 0.6),
      ),
      child: Text(text, style: style.copyWith(color: theme.textPrimary)),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Container(height: 0.6, color: theme.divider),
    );
  }
}

class _Quote extends StatelessWidget {
  const _Quote({
    required this.block,
    required this.typography,
    this.onOpenLink,
  });

  final DocumentQuoteBlock block;
  final DocumentTypography typography;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Container(
      padding: const EdgeInsets.only(left: 18),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: theme.quoteBar, width: 2.5)),
      ),
      child: _Stack(
        blocks: block.children,
        typography: typography,
        onOpenLink: onOpenLink,
        style: typography.quote,
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.block,
    required this.typography,
    this.onOpenLink,
  });

  final DocumentCalloutBlock block;
  final DocumentTypography typography;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final tone = documentCalloutStyle(block.tone, theme);

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      decoration: BoxDecoration(
        color: tone.background,
        borderRadius: BorderRadius.circular(DocumentViewerTheme.surfaceRadius),
        border: Border.all(color: tone.border, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Icon(tone.icon, size: 17, color: tone.accent),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  block.title ?? tone.label,
                  style: typography.minorHeading.copyWith(
                    fontSize: 14,
                    color: tone.accent,
                  ),
                ),
                const SizedBox(height: 6),
                _Stack(
                  blocks: block.children,
                  typography: typography,
                  onOpenLink: onOpenLink,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Resolved appearance for a callout tone.
@immutable
class DocumentCalloutStyle {
  const DocumentCalloutStyle({
    required this.label,
    required this.icon,
    required this.accent,
    required this.background,
    required this.border,
  });

  final String label;
  final IconData icon;
  final Color accent;
  final Color background;
  final Color border;
}

DocumentCalloutStyle documentCalloutStyle(
  DocumentCalloutTone tone,
  DocumentViewerTheme theme,
) {
  final (label, icon, accent) = switch (tone) {
    DocumentCalloutTone.note => (
        'Note',
        Icons.info_outline_rounded,
        theme.isDark ? const Color(0xFF6EA8FF) : const Color(0xFF2C6BD6),
      ),
    DocumentCalloutTone.tip => (
        'Tip',
        Icons.lightbulb_outline_rounded,
        theme.isDark ? const Color(0xFF5FD0A0) : const Color(0xFF1E8A63),
      ),
    DocumentCalloutTone.important => (
        'Important',
        Icons.auto_awesome_outlined,
        theme.isDark ? const Color(0xFFB79BFF) : const Color(0xFF6D4BC7),
      ),
    DocumentCalloutTone.warning => (
        'Warning',
        Icons.warning_amber_rounded,
        theme.isDark ? const Color(0xFFE3B457) : const Color(0xFF9A6A12),
      ),
    DocumentCalloutTone.caution => (
        'Caution',
        Icons.report_gmailerrorred_rounded,
        theme.isDark ? const Color(0xFFF08A8A) : const Color(0xFFB3443F),
      ),
  };
  return DocumentCalloutStyle(
    label: label,
    icon: icon,
    accent: accent,
    background: accent.withValues(alpha: theme.isDark ? 0.10 : 0.07),
    border: accent.withValues(alpha: theme.isDark ? 0.24 : 0.20),
  );
}

class _List extends StatelessWidget {
  const _List({
    required this.block,
    required this.typography,
    this.onOpenLink,
  });

  final DocumentListBlock block;
  final DocumentTypography typography;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = 0; index < block.items.length; index++)
          Padding(
            padding: EdgeInsets.only(top: index == 0 ? 0 : 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _marker(theme, block.items[index], index),
                const SizedBox(width: 10),
                Expanded(
                  child: _Stack(
                    blocks: block.items[index].children,
                    typography: typography,
                    onOpenLink: onOpenLink,
                    style: block.items[index].checked == true
                        ? typography.body.copyWith(
                            color: theme.textMuted,
                            decoration: TextDecoration.lineThrough,
                            decorationColor: theme.textMuted,
                          )
                        : null,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _marker(
    DocumentViewerTheme theme,
    DocumentListItem item,
    int index,
  ) {
    // Align every marker to the first text line's optical centre.
    final leading =
        (typography.body.fontSize ?? 16) * (typography.body.height ?? 1.7) / 2;

    if (item.checked != null) {
      return Padding(
        padding: EdgeInsets.only(top: leading - 8),
        child: _Checkbox(checked: item.checked!),
      );
    }
    if (block.ordered) {
      return SizedBox(
        width: 22,
        child: Text(
          '${block.start + index}.',
          textAlign: TextAlign.right,
          style: typography.body.copyWith(
            color: theme.textMuted,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: leading - 2.5, left: 7),
      child: Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          color: theme.textMuted,
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

class _Checkbox extends StatelessWidget {
  const _Checkbox({required this.checked});

  final bool checked;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return AnimatedContainer(
      duration: AppFlowyMotion.fast,
      curve: AppFlowyMotion.standardCurve,
      width: 16,
      height: 16,
      decoration: BoxDecoration(
        color: checked ? theme.accent : Colors.transparent,
        borderRadius: BorderRadius.circular(5),
        border: Border.all(
          color: checked ? theme.accent : theme.divider,
          width: checked ? 0 : 1.2,
        ),
      ),
      alignment: Alignment.center,
      child: checked
          ? Icon(Icons.check_rounded, size: 12, color: theme.onAccent)
          : null,
    );
  }
}

/// Lays out nested blocks with the shared vertical rhythm.
class _Stack extends StatelessWidget {
  const _Stack({
    required this.blocks,
    required this.typography,
    this.onOpenLink,
    this.style,
  });

  final List<DocumentBlock> blocks;
  final DocumentTypography typography;
  final ValueChanged<String>? onOpenLink;

  /// Overrides body text styling for quotes and completed checklist items.
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final resolved = style == null
        ? typography
        : DocumentTypography(
            display: typography.display,
            title: typography.title,
            heading: typography.heading,
            subheading: typography.subheading,
            minorHeading: typography.minorHeading,
            overline: typography.overline,
            body: style!,
            lead: typography.lead,
            caption: typography.caption,
            quote: typography.quote,
            code: typography.code,
            inlineCode: typography.inlineCode,
            tableHeader: typography.tableHeader,
            tableCell: typography.tableCell,
          );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var index = 0; index < blocks.length; index++)
          Padding(
            padding: EdgeInsets.only(
              top: documentBlockSpacing(
                blocks[index],
                index == 0 ? null : blocks[index - 1],
                resolved,
              ),
            ),
            child: DocumentBlockView(
              block: blocks[index],
              typography: resolved,
              onOpenLink: onOpenLink,
            ),
          ),
      ],
    );
  }
}

class _Table extends StatelessWidget {
  const _Table({
    required this.block,
    required this.typography,
    this.onOpenLink,
  });

  final DocumentTableBlock block;
  final DocumentTypography typography;
  final ValueChanged<String>? onOpenLink;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final columns = block.columnCount;
    if (columns == 0) {
      return const SizedBox.shrink();
    }

    return DocumentPanel(
      padding: EdgeInsets.zero,
      color: theme.page,
      borderColor: theme.divider,
      child: Scrollbar(
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          physics: const DocumentScrollPhysics(),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 320),
            child: Table(
              defaultColumnWidth: const IntrinsicColumnWidth(flex: 1),
              border: TableBorder(
                horizontalInside: BorderSide(color: theme.hairline, width: 0.6),
                verticalInside: BorderSide(color: theme.hairline, width: 0.6),
              ),
              children: [
                for (var row = 0; row < block.rows.length; row++)
                  TableRow(
                    decoration: BoxDecoration(
                      color: row == 0 && block.hasHeader ? theme.control : null,
                    ),
                    children: [
                      for (var column = 0; column < columns; column++)
                        Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          child: DocumentInlineText(
                            inline: column < block.rows[row].length
                                ? block.rows[row][column]
                                : const DocumentInline.empty(),
                            typography: typography,
                            onOpenLink: onOpenLink,
                            textAlign: column < block.alignments.length
                                ? block.alignments[column]
                                : null,
                            style: row == 0 && block.hasHeader
                                ? typography.tableHeader
                                : typography.tableCell,
                          ),
                        ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The premium code surface used by fenced code, code files and notebooks.
class DocumentCodeSurface extends StatefulWidget {
  const DocumentCodeSurface({
    super.key,
    required this.code,
    required this.typography,
    this.language,
    this.showHeader = true,
    this.maxHeight,
  });

  final String code;
  final String? language;
  final DocumentTypography typography;
  final bool showHeader;
  final double? maxHeight;

  @override
  State<DocumentCodeSurface> createState() => _DocumentCodeSurfaceState();
}

class _DocumentCodeSurfaceState extends State<DocumentCodeSurface> {
  final ScrollController horizontal = ScrollController();
  bool copied = false;

  @override
  void dispose() {
    horizontal.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final lineCount = '\n'.allMatches(widget.code).length + 1;
    final gutterWidth = 20.0 + '$lineCount'.length * 8.0;

    final body = Scrollbar(
      controller: horizontal,
      child: SingleChildScrollView(
        controller: horizontal,
        scrollDirection: Axis.horizontal,
        physics: const DocumentScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(0, 14, 20, 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: gutterWidth,
                child: Text(
                  [for (var line = 1; line <= lineCount; line++) '$line']
                      .join('\n'),
                  textAlign: TextAlign.right,
                  style: widget.typography.code.copyWith(
                    color: theme.textMuted.withValues(alpha: 0.7),
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Text.rich(
                buildSyntaxHighlightedTextSpan(
                  code: widget.code,
                  language: widget.language ?? 'auto',
                  brightness: theme.brightness,
                  isPaper: theme.isPaper,
                  style: widget.typography.code,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    return DocumentPanel(
      padding: EdgeInsets.zero,
      color: theme.codeSurface,
      borderColor: theme.codeBorder,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (widget.showHeader) _header(theme),
          if (widget.maxHeight != null)
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: widget.maxHeight!),
              child: body,
            )
          else
            body,
        ],
      ),
    );
  }

  Widget _header(DocumentViewerTheme theme) {
    return Container(
      height: 34,
      padding: const EdgeInsets.only(left: 14, right: 6),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: theme.codeBorder, width: 0.6)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              documentCodeLanguageLabel(widget.language),
              style: widget.typography.overline.copyWith(
                fontSize: 10.5,
                letterSpacing: 0.8,
              ),
            ),
          ),
          _CopyButton(
            copied: copied,
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: widget.code));
              if (!mounted) {
                return;
              }
              setState(() => copied = true);
              await Future<void>.delayed(const Duration(milliseconds: 1400));
              if (mounted) {
                setState(() => copied = false);
              }
            },
          ),
        ],
      ),
    );
  }
}

/// Human label for a highlight language key.
String documentCodeLanguageLabel(String? language) {
  final normalized = language == null || language.trim().isEmpty
      ? 'auto'
      : normalizeCodeLanguage(language);
  return switch (normalized) {
    'auto' => 'CODE',
    'cpp' => 'C++',
    'cs' => 'C#',
    'javascript' => 'JAVASCRIPT',
    'typescript' => 'TYPESCRIPT',
    'objectivec' => 'OBJECTIVE-C',
    _ => normalized.toUpperCase(),
  };
}

class _CopyButton extends StatelessWidget {
  const _CopyButton({required this.copied, required this.onPressed});

  final bool copied;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Tooltip(
      message: copied ? 'Copied' : 'Copy',
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(7),
        hoverColor: theme.controlHover,
        splashFactory: NoSplash.splashFactory,
        highlightColor: Colors.transparent,
        child: SizedBox(
          width: 26,
          height: 26,
          child: AnimatedSwitcher(
            duration: AppFlowyMotion.fast,
            child: Icon(
              copied ? Icons.check_rounded : Icons.copy_rounded,
              key: ValueKey(copied),
              size: 13,
              color: copied ? theme.accent : theme.iconMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// A row of images that belong together, such as a badge strip.
class DocumentImageRowView extends StatelessWidget {
  const DocumentImageRowView({
    super.key,
    required this.block,
    required this.typography,
  });

  final DocumentImageRowBlock block;
  final DocumentTypography typography;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: documentImageAlignment(block.alignment),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: switch (block.alignment) {
          TextAlign.center => WrapAlignment.center,
          TextAlign.right || TextAlign.end => WrapAlignment.end,
          _ => WrapAlignment.start,
        },
        children: [
          for (final image in block.images)
            DocumentImageView(
              key: ValueKey(image.source),
              block: image,
              typography: typography,
              inline: true,
            ),
        ],
      ),
    );
  }
}

/// Resolves authored text alignment to a box alignment.
Alignment documentImageAlignment(TextAlign alignment) => switch (alignment) {
      TextAlign.center => Alignment.center,
      TextAlign.right || TextAlign.end => Alignment.centerRight,
      _ => Alignment.centerLeft,
    };

/// An image inside a document.
///
/// Images are painted at their own size and only ever scaled *down* to fit the
/// reading measure, so a 20-pixel badge stays a badge instead of becoming a
/// full-width panel. Space is reserved from the authored or measured
/// dimensions, which keeps the reading position stable while a long document
/// loads.
class DocumentImageView extends StatefulWidget {
  const DocumentImageView({
    super.key,
    required this.block,
    required this.typography,
    this.inline = false,
  });

  final DocumentImageBlock block;
  final DocumentTypography typography;

  /// Inline images sit in a run with siblings and never claim a caption.
  final bool inline;

  /// Height reserved for an image whose dimensions are not yet known.
  static const double placeholderHeight = 180;

  /// Images at or below this height read as badges and stay on one line.
  static const double inlineHeightLimit = 44;

  /// Tallest an image may render. Beyond this a single picture would fill the
  /// viewport several times over and the document stops feeling scrollable.
  static const double maxRenderedHeight = 1100;

  @override
  State<DocumentImageView> createState() => _DocumentImageViewState();
}

class _DocumentImageViewState extends State<DocumentImageView> {
  late Future<DocumentImageData> pending;

  @override
  void initState() {
    super.initState();
    pending = DocumentImageLoader.load(widget.block.source);
  }

  @override
  void didUpdateWidget(covariant DocumentImageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.block.source != widget.block.source) {
      pending = DocumentImageLoader.load(widget.block.source);
    }
  }

  /// The space the author asked for, in whatever detail they gave.
  ///
  /// A lone `width` is common and perfectly usable — the height follows from
  /// the image's own proportions.
  double? get declaredWidth {
    final width = widget.block.width;
    return width == null || width <= 0 ? null : width;
  }

  Size? get declaredSize {
    final width = declaredWidth;
    final height = widget.block.height;
    if (width == null || height == null || height <= 0) {
      return null;
    }
    return Size(width, height);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<DocumentImageData>(
      future: pending,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _DocumentImageNotice(
            alt: widget.block.alt,
            typography: widget.typography,
            compact: widget.inline || declaredSize == null,
          );
        }
        final data = snapshot.data;
        if (data == null) {
          return _DocumentImageSkeleton(
            size: declaredSize,
            alignment: widget.block.alignment,
          );
        }
        return _content(context, data);
      },
    );
  }

  Widget _content(BuildContext context, DocumentImageData data) {
    final theme = DocumentViewerTheme.of(context);
    // The loader measures every image before it is handed over, so a size is
    // always available and the layout never shifts underneath the reader.
    final intrinsic = data.intrinsicSize ?? declaredSize;
    if (intrinsic == null || intrinsic.isEmpty) {
      return _DocumentImageNotice(
        alt: widget.block.alt,
        typography: widget.typography,
        compact: true,
      );
    }

    final rounded = intrinsic.height > DocumentImageView.inlineHeightLimit;

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : DocumentViewerTheme.readingWidth;
        // Scale down to the measure, never up past the source resolution.
        var width = math.min(declaredWidth ?? intrinsic.width, available);
        var height = width * intrinsic.height / intrinsic.width;
        // A very tall image would otherwise fill the viewport several times
        // over and make the document feel unscrollable.
        if (height > DocumentImageView.maxRenderedHeight) {
          height = DocumentImageView.maxRenderedHeight;
          width = height * intrinsic.width / intrinsic.height;
        }

        // Vector images have no pixel size of their own, so the resolved
        // layout size is handed to them explicitly.
        final picture = switch (data) {
          DocumentRasterImage(:final provider) => Image(
              image: provider,
              fit: BoxFit.contain,
              gaplessPlayback: true,
              errorBuilder: (context, _, __) => _DocumentImageNotice(
                alt: widget.block.alt,
                typography: widget.typography,
                compact: true,
              ),
            ),
          DocumentVectorImage(:final bytes) => SvgPicture.memory(
              bytes,
              width: width,
              height: height,
            ),
        };

        final sized = RepaintBoundary(
          child: SizedBox(
            width: width,
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(
                rounded ? DocumentViewerTheme.surfaceRadius : 4,
              ),
              child: picture,
            ),
          ),
        );

        if (widget.inline) {
          return sized;
        }

        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Align(
              alignment: documentImageAlignment(widget.block.alignment),
              child: sized,
            ),
            if (rounded && widget.block.alt?.isNotEmpty == true) ...[
              const SizedBox(height: 8),
              Text(
                widget.block.alt!,
                textAlign: widget.block.alignment,
                style: widget.typography.caption.copyWith(
                  color: theme.textMuted,
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// Reserved space while an image is on its way.
class _DocumentImageSkeleton extends StatelessWidget {
  const _DocumentImageSkeleton({
    required this.size,
    required this.alignment,
  });

  final Size? size;
  final TextAlign alignment;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final height = size == null
        ? DocumentImageView.placeholderHeight
        : math.min(size!.height, 520.0);

    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : DocumentViewerTheme.readingWidth;
        final width =
            size == null ? available : math.min(size!.width, available);
        return Align(
          alignment: documentImageAlignment(alignment),
          child: Container(
            width: width,
            height: size == null
                ? height
                : height * (width / math.max(size!.width, 1)),
            decoration: BoxDecoration(
              color: theme.control,
              borderRadius:
                  BorderRadius.circular(DocumentViewerTheme.surfaceRadius),
            ),
          ),
        );
      },
    );
  }
}

/// A quiet marker for an image that could not be shown.
///
/// Deliberately small: a failed decoration should never dominate the page.
class _DocumentImageNotice extends StatelessWidget {
  const _DocumentImageNotice({
    required this.alt,
    required this.typography,
    required this.compact,
  });

  final String? alt;
  final DocumentTypography typography;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final label = alt?.isNotEmpty == true ? alt! : 'Image unavailable';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: theme.control,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: theme.hairline, width: 0.6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.image_not_supported_outlined,
            size: 13,
            color: theme.iconMuted,
          ),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: compact ? 220 : 460),
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: typography.caption.copyWith(
                fontSize: 11.5,
                color: theme.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
