import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_search_highlight.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

class FindAndReplaceMenuWidget extends StatefulWidget {
  const FindAndReplaceMenuWidget({
    super.key,
    required this.onDismiss,
    required this.editorState,
    required this.showReplaceMenu,
  });

  final EditorState editorState;
  final VoidCallback onDismiss;

  /// Whether to show the replace menu initially
  final bool showReplaceMenu;

  @override
  State<FindAndReplaceMenuWidget> createState() =>
      _FindAndReplaceMenuWidgetState();
}

class _FindAndReplaceMenuWidgetState extends State<FindAndReplaceMenuWidget> {
  late final SearchServiceV3 searchService = SearchServiceV3(
    editorState: widget.editorState,
  );

  final findController = TextEditingController();
  final replaceController = TextEditingController();
  final findFocusNode = FocusNode();
  final replaceFocusNode = FocusNode();

  late bool showReplaceMenu = widget.showReplaceMenu;
  FindOptions options = const FindOptions();
  bool invalidPattern = false;

  @override
  void initState() {
    super.initState();
    findController.addListener(_search);
    searchService.matchWrappers.addListener(_onMatchesChanged);
    searchService.currentSelectedIndex.addListener(_onMatchesChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      (widget.showReplaceMenu ? replaceFocusNode : findFocusNode)
          .requestFocus();
    });
  }

  @override
  void dispose() {
    searchService.matchWrappers.removeListener(_onMatchesChanged);
    searchService.currentSelectedIndex.removeListener(_onMatchesChanged);
    final editorState = widget.editorState;
    // Dropping the marks repaints the blocks, which cannot happen while this
    // subtree is being taken down.
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => DocumentSearchHighlight.instance.clear(editorState),
    );
    searchService.dispose();
    findController.dispose();
    replaceController.dispose();
    findFocusNode.dispose();
    replaceFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final matches = searchService.matchWrappers.value;
    return FindReplaceBar(
      findController: findController,
      findFocusNode: findFocusNode,
      options: options,
      onOptionsChanged: (value) {
        options = value;
        _search();
      },
      matchCount: matches.length,
      currentMatch: matches.isEmpty ? 0 : searchService.selectedIndex + 1,
      queryInvalid: invalidPattern,
      onPrevious: matches.isEmpty ? null : () => _navigate(moveUp: true),
      onNext: matches.isEmpty ? null : _navigate,
      onSubmitted: matches.isEmpty ? null : _navigate,
      onClose: widget.onDismiss,
      replaceController: replaceController,
      replaceFocusNode: replaceFocusNode,
      showReplace: showReplaceMenu,
      onToggleReplace: () => setState(() => showReplaceMenu = !showReplaceMenu),
      onReplace: matches.isEmpty ? null : _replaceCurrent,
      onReplaceAll: matches.isEmpty ? null : _replaceAll,
    );
  }

  void _search() {
    // Whole word is expressed as an expression, so the service has to be told
    // to read the query as one. A plain search is left alone: the service
    // escapes it itself, and its replacement then stays literal.
    final asExpression = options.useRegex || options.wholeWord;
    final query = asExpression
        ? findPatternSource(findController.text, options)
        : findController.text;
    if (searchService.caseSensitive != options.caseSensitive) {
      searchService.caseSensitive = options.caseSensitive;
    }
    if (searchService.regex != asExpression) {
      searchService.regex = asExpression;
    }
    invalidPattern = searchService.findAndHighlight(query) == 'Regex';
    _onMatchesChanged();
  }

  void _navigate({bool moveUp = false}) {
    searchService.navigateToMatch(moveUp: moveUp);
    _keepTyping(findFocusNode);
  }

  /// Replaces the match being read, then moves on to the next one, so holding
  /// Enter walks through the page replacing as it goes.
  Future<void> _replaceCurrent() async {
    if (replaceController.text.isEmpty) {
      // The editor's own service refuses an empty replacement, so there is
      // nothing to step over either.
      _keepTyping(replaceFocusNode);
      return;
    }
    final before = searchService.matchWrappers.value.length;
    await searchService.replaceSelectedWord(replaceController.text);
    if (!mounted) {
      return;
    }
    final after = searchService.matchWrappers.value.length;
    // Replacing a word with one that still matches leaves the reader standing
    // on the text they have just written, so step off it.
    if (after > 0 && after >= before) {
      searchService.navigateToMatch();
    }
    _keepTyping(replaceFocusNode);
  }

  void _replaceAll() {
    searchService.replaceAllMatches(replaceController.text);
    _keepTyping(replaceFocusNode);
  }

  /// Writing to the page hands the focus back to the editor, and the person is
  /// still typing in the bar.
  void _keepTyping(FocusNode node) {
    Future.delayed(
      const Duration(milliseconds: 50),
      () {
        if (mounted) {
          node.requestFocus();
        }
      },
    );
  }

  void _onMatchesChanged() {
    if (!mounted) {
      return;
    }
    DocumentSearchHighlight.instance.update(
      widget.editorState,
      [
        for (final wrapper in searchService.matchWrappers.value)
          (
            path: wrapper.path,
            start: wrapper.match.start,
            end: wrapper.match.end,
          ),
      ],
      searchService.selectedIndex,
    );
    setState(() {});
  }
}
