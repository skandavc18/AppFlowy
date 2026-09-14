import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:flutter/material.dart';

/// Shows all code immediately, then colors it off the scrolling critical path.
/// The editor and its text/selection stay mounted; only the span decoration
/// changes. A code block that is scrolled past never starts a parser job.
class DeferredCodeHighlight extends StatefulWidget {
  const DeferredCodeHighlight({
    super.key,
    required this.code,
    required this.language,
    required this.brightness,
    required this.style,
    required this.builder,
    this.isPaper = false,
    this.scrolling,
    this.highlighter = loadSyntaxHighlightedTextSpan,
  });

  final String code;
  final String language;
  final Brightness brightness;
  final TextStyle style;
  final bool isPaper;
  final ValueNotifier<bool>? scrolling;
  final Widget Function(BuildContext, TextSpan) builder;
  final AsyncSyntaxHighlighter highlighter;

  @override
  State<DeferredCodeHighlight> createState() => _DeferredCodeHighlightState();
}

class _DeferredCodeHighlightState extends State<DeferredCodeHighlight> {
  TextSpan? _span;
  Timer? _idle;
  int _generation = 0;

  bool get _scrolling => widget.scrolling?.value ?? false;

  @override
  void initState() {
    super.initState();
    widget.scrolling?.addListener(_onScroll);
    _refresh();
  }

  @override
  void didUpdateWidget(covariant DeferredCodeHighlight oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrolling != widget.scrolling) {
      oldWidget.scrolling?.removeListener(_onScroll);
      widget.scrolling?.addListener(_onScroll);
    }
    if (oldWidget.code != widget.code ||
        oldWidget.language != widget.language ||
        oldWidget.brightness != widget.brightness ||
        oldWidget.isPaper != widget.isPaper ||
        oldWidget.style != widget.style ||
        oldWidget.highlighter != widget.highlighter ||
        oldWidget.scrolling != widget.scrolling) {
      _refresh();
    }
  }

  void _refresh() {
    _span = cachedSyntaxHighlightedTextSpan(
      code: widget.code,
      language: widget.language,
      brightness: widget.brightness,
      style: widget.style,
      isPaper: widget.isPaper,
    );
    _onScroll();
  }

  void _onScroll() {
    _generation++;
    _idle?.cancel();
    _idle = null;
    if (!_scrolling && _span == null) {
      _idle = Timer(const Duration(milliseconds: 80), () {
        _idle = null;
        unawaited(_highlight(_generation));
      });
    }
  }

  Future<void> _highlight(int generation) async {
    bool cancelled() => !mounted || generation != _generation || _scrolling;
    try {
      final span = await widget.highlighter(
        code: widget.code,
        language: widget.language,
        brightness: widget.brightness,
        style: widget.style,
        isPaper: widget.isPaper,
        isCancelled: cancelled,
      );
      if (!cancelled() && span != null) setState(() => _span = span);
    } on Object {
      // Syntax coloring must never prevent reading or editing the source.
      // A later edit/theme change can retry; keep the complete plain text.
    }
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        _span ?? TextSpan(text: widget.code, style: widget.style),
      );

  @override
  void dispose() {
    _generation++;
    _idle?.cancel();
    widget.scrolling?.removeListener(_onScroll);
    super.dispose();
  }
}
