import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:flutter/material.dart';

import 'document_scroll.dart';
import 'document_scrollbar.dart';
import 'document_typography.dart';
import 'document_viewer_theme.dart';

/// A Cursor-style code surface: quiet gutter, generous leading, no chrome.
///
/// The text field is driven by the shared [DocumentScrollController] and the
/// shared [DocumentScrollPhysics], so scrolling a source file is
/// indistinguishable from scrolling a PDF or a Markdown document.
class DocumentCodeFileView extends StatefulWidget {
  const DocumentCodeFileView({
    super.key,
    required this.controller,
    required this.code,
    required this.language,
    this.showLineNumbers = true,
    this.editable = false,
    this.onChanged,
    this.scale = 1,
  });

  final DocumentScrollController controller;
  final String code;
  final String language;
  final bool showLineNumbers;
  final bool editable;
  final ValueChanged<String>? onChanged;
  final double scale;

  /// Left padding of the code column, measured from the gutter rule.
  static const double codeInset = 20;
  static const double verticalInset = 22;

  @override
  State<DocumentCodeFileView> createState() => _DocumentCodeFileViewState();
}

class _DocumentCodeFileViewState extends State<DocumentCodeFileView> {
  late final _SyntaxTextController text = _SyntaxTextController(
    text: widget.code,
    language: widget.language,
  );
  final ValueNotifier<double> gutterOffset = ValueNotifier<double>(0);
  final FocusNode focusNode = FocusNode();
  Timer? persistTimer;
  int lineCount = 1;

  @override
  void initState() {
    super.initState();
    lineCount = _countLines(widget.code);
    widget.controller.addListener(_syncGutter);
    text.addListener(_handleTextChanged);
  }

  @override
  void didUpdateWidget(covariant DocumentCodeFileView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.language != widget.language) {
      text.updateLanguage(widget.language);
    }
    if (oldWidget.code != widget.code && widget.code != text.text) {
      text.text = widget.code;
      lineCount = _countLines(widget.code);
    }
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_syncGutter);
      widget.controller.addListener(_syncGutter);
    }
  }

  @override
  void dispose() {
    persistTimer?.cancel();
    widget.controller.removeListener(_syncGutter);
    text.removeListener(_handleTextChanged);
    text.dispose();
    gutterOffset.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _syncGutter() {
    if (widget.controller.hasClients) {
      gutterOffset.value = widget.controller.offset;
    }
  }

  void _handleTextChanged() {
    final next = _countLines(text.text);
    if (next != lineCount) {
      setState(() => lineCount = next);
    }
  }

  static int _countLines(String value) => '\n'.allMatches(value).length + 1;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    final typography = DocumentTypography.resolve(theme, scale: widget.scale);
    final style = typography.code.copyWith(
      fontSize: (typography.code.fontSize ?? 13.5) + 0.5,
      height: 1.7,
      color: theme.textPrimary,
    );
    final gutterWidth =
        widget.showLineNumbers ? 26 + '$lineCount'.length * 8.0 : 0.0;

    return DocumentScrollScope(
      child: ColoredBox(
        color: theme.codeSurface,
        child: DocumentScrollbar(
          controller: widget.controller,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showLineNumbers)
                _Gutter(
                  width: gutterWidth,
                  lineCount: lineCount,
                  offset: gutterOffset,
                  style: style.copyWith(
                    color: theme.textMuted.withValues(alpha: 0.62),
                  ),
                ),
              Expanded(
                child: TextField(
                  controller: text,
                  focusNode: focusNode,
                  scrollController: widget.controller,
                  scrollPhysics: const DocumentScrollPhysics(),
                  readOnly: !widget.editable,
                  expands: true,
                  maxLines: null,
                  cursorColor: theme.accent,
                  cursorWidth: 1.6,
                  cursorRadius: const Radius.circular(1),
                  keyboardType: TextInputType.multiline,
                  style: style,
                  decoration: InputDecoration(
                    isDense: true,
                    contentPadding: EdgeInsets.fromLTRB(
                      widget.showLineNumbers
                          ? DocumentCodeFileView.codeInset
                          : 28,
                      DocumentCodeFileView.verticalInset,
                      28,
                      DocumentCodeFileView.verticalInset,
                    ),
                    border: InputBorder.none,
                    enabledBorder: InputBorder.none,
                    focusedBorder: InputBorder.none,
                    filled: false,
                    hoverColor: Colors.transparent,
                  ),
                  onChanged: (value) {
                    widget.onChanged?.call(value);
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.width,
    required this.lineCount,
    required this.offset,
    required this.style,
  });

  final double width;
  final int lineCount;
  final ValueNotifier<double> offset;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final theme = DocumentViewerTheme.of(context);
    return Container(
      width: width,
      decoration: BoxDecoration(
        border: Border(
          right: BorderSide(color: theme.hairline, width: 0.6),
        ),
      ),
      child: ClipRect(
        child: RepaintBoundary(
          child: ValueListenableBuilder<double>(
            valueListenable: offset,
            builder: (context, value, child) => Transform.translate(
              offset: Offset(0, -value),
              child: child,
            ),
            child: Padding(
              padding: const EdgeInsets.only(
                top: DocumentCodeFileView.verticalInset,
                right: 12,
              ),
              child: Align(
                alignment: Alignment.topRight,
                child: Text(
                  [for (var line = 1; line <= lineCount; line++) '$line']
                      .join('\n'),
                  textAlign: TextAlign.right,
                  style: style.copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A controller that paints syntax highlighting behind live editing.
class _SyntaxTextController extends TextEditingController {
  _SyntaxTextController({required super.text, required String language})
      : language = normalizeCodeLanguage(language);

  String language;

  void updateLanguage(String value) {
    language = normalizeCodeLanguage(value);
    notifyListeners();
  }

  @override
  TextSpan buildTextSpan({
    required BuildContext context,
    TextStyle? style,
    required bool withComposing,
  }) {
    final theme = DocumentViewerTheme.of(context);
    return buildSyntaxHighlightedTextSpan(
      code: text,
      language: language,
      brightness: theme.brightness,
      isPaper: theme.isPaper,
      style: style,
    );
  }
}
