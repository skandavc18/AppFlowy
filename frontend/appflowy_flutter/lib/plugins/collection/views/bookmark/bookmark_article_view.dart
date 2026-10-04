import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Text-only local reading, not a native document editor or another WebView.
/// Selectable paragraphs, bounded reading width and local Find work offline.
class BookmarkArticleView extends StatefulWidget {
  const BookmarkArticleView({super.key, required this.text});
  final String text;

  @override
  State<BookmarkArticleView> createState() => _BookmarkArticleViewState();
}

class _BookmarkArticleViewState extends State<BookmarkArticleView> {
  final _find = TextFindSession();
  final _focus = FocusNode();
  final _scroll = ScrollController();
  List<String> _paragraphs = [];
  List<int> _starts = [];
  List<GlobalKey> _keys = [];
  bool _open = false;
  int _reveal = 0;

  @override
  void initState() {
    super.initState();
    _setText();
    _find.addListener(_changed);
  }

  void _setText() {
    _paragraphs = widget.text.split('\n\n');
    var offset = 0;
    _starts = [
      for (final paragraph in _paragraphs)
        (offset += paragraph.length + 2) - paragraph.length - 2,
    ];
    _keys = List.generate(_paragraphs.length, (_) => GlobalKey());
    _find.setText(widget.text);
  }

  @override
  void didUpdateWidget(BookmarkArticleView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.text != widget.text) _setText();
  }

  void _changed() {
    if (!mounted) return;
    setState(() {});
    final ticket = ++_reveal;
    final match = _find.currentMatch;
    if (!_open || match == null) return;
    final index = _starts.lastIndexWhere((start) => start <= match.start);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open || ticket != _reveal || !TickerMode.of(context)) {
        return;
      }
      final target = index < 0 ? null : _keys[index].currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          alignment: 0.15,
        );
      }
    });
  }

  void _openFind() {
    if (!mounted || !TickerMode.of(context)) return;
    setState(() => _open = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _open && TickerMode.of(context)) {
        _find.findFocusNode.requestFocus();
      }
    });
  }

  void _closeFind() {
    if (!mounted) return;
    _reveal++;
    _find.findFocusNode.unfocus();
    setState(() => _open = false);
  }

  @override
  void dispose() {
    _find.removeListener(_changed);
    _find.dispose();
    _focus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  TextSpan _paragraph(int index) {
    final text = _paragraphs[index];
    final start = _starts[index];
    final end = start + text.length;
    final spans = <InlineSpan>[];
    var cursor = 0;
    if (_open) {
      for (final match in _find.matches) {
        if (match.end <= start || match.start >= end) continue;
        final from = (match.start - start).clamp(0, text.length);
        final to = (match.end - start).clamp(0, text.length);
        if (from > cursor) {
          spans.add(TextSpan(text: text.substring(cursor, from)));
        }
        spans.add(
          TextSpan(
            text: text.substring(from, to),
            style: TextStyle(
              backgroundColor: match == _find.currentMatch
                  ? FindHighlightColors.current(Theme.of(context).brightness)
                  : FindHighlightColors.match(Theme.of(context).brightness),
            ),
          ),
        );
        cursor = to;
      }
    }
    spans.add(TextSpan(text: text.substring(cursor)));
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) => ContextualFindRegion(
        debugLabel: 'Bookmark local article',
        findOpen: _open,
        findFocusNode: _find.findFocusNode,
        onFind: _openFind,
        onDismiss: _closeFind,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.keyF, control: true):
                _openFind,
            const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
                _openFind,
          },
          child: Focus(
            focusNode: _focus,
            child: ColoredBox(
              color: EditorSurfaceStyle.canvasBackground(context),
              child: Column(
                children: [
                  if (_open)
                    Padding(
                      padding: const EdgeInsets.all(8),
                      child: Align(
                        alignment: Alignment.centerRight,
                        child: FindReplaceBar(
                          findController: _find.findController,
                          findFocusNode: _find.findFocusNode,
                          options: _find.options,
                          onOptionsChanged: (options) =>
                              _find.options = options,
                          matchCount: _find.matches.length,
                          currentMatch: _find.displayIndex,
                          queryInvalid: _find.invalid,
                          onPrevious:
                              _find.matches.isEmpty ? null : _find.previous,
                          onNext: _find.matches.isEmpty ? null : _find.next,
                          onClose: _closeFind,
                        ),
                      ),
                    ),
                  Expanded(
                    child: SelectionArea(
                      child: SingleChildScrollView(
                        key: const ValueKey('bookmark-local-article-scroll'),
                        controller: _scroll,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 24,
                        ),
                        child: Center(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 720),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                for (var i = 0; i < _paragraphs.length; i++)
                                  Padding(
                                    key: _keys[i],
                                    padding: const EdgeInsets.only(bottom: 16),
                                    child: Text.rich(
                                      _paragraph(i),
                                      style: Theme.of(context)
                                          .textTheme
                                          .bodyLarge
                                          ?.copyWith(height: 1.65),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
}
