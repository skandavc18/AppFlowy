import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_session.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import 'document_find_content.dart';

class FindAndReplaceMenuWidget extends StatefulWidget {
  const FindAndReplaceMenuWidget({
    super.key,
    required this.onDismiss,
    required this.editorState,
    required this.showReplaceMenu,
    this.canReplace,
    this.isOwnerActive,
    this.findFocusNode,
    this.replaceFocusNode,
    this.currentView,
    this.viewChanges,
    this.referenceProvider,
    this.documentId,
    this.titleObstruction,
  });

  final EditorState editorState;
  final VoidCallback onDismiss;

  /// Whether to show the replace menu initially
  final bool showReplaceMenu;

  /// These remain live checks, including between query and explicit Replace.
  final bool Function()? canReplace;
  final bool Function()? isOwnerActive;
  final FocusNode? findFocusNode;
  final FocusNode? replaceFocusNode;
  final ViewPB? Function()? currentView;
  final Stream<ViewPB>? viewChanges;
  final DocumentFindReadProvider? referenceProvider;
  final String? documentId;
  final Rect? Function()? titleObstruction;

  @override
  State<FindAndReplaceMenuWidget> createState() =>
      _FindAndReplaceMenuWidgetState();
}

class _FindAndReplaceMenuWidgetState extends State<FindAndReplaceMenuWidget> {
  late DocumentFindSession _session;

  final findController = TextEditingController();
  final replaceController = TextEditingController();
  final _ownedFindFocusNode = FocusNode();
  final _ownedReplaceFocusNode = FocusNode();
  FocusNode get findFocusNode => widget.findFocusNode ?? _ownedFindFocusNode;
  FocusNode get replaceFocusNode =>
      widget.replaceFocusNode ?? _ownedReplaceFocusNode;

  late bool showReplaceMenu = widget.showReplaceMenu;
  FindOptions options = const FindOptions();
  int _focusRequest = 0;

  @override
  void initState() {
    super.initState();
    _bindSession();
    findController.addListener(_search);
    _keepTyping(showReplaceMenu ? replaceFocusNode : findFocusNode);
  }

  void _bindSession() {
    _session = DocumentFindSession(
      widget.editorState,
      documentId: widget.documentId,
      titleObstruction: widget.titleObstruction,
      currentView: () => widget.currentView?.call(),
      viewChanges: widget.viewChanges,
      referenceProvider: widget.referenceProvider,
      canReplace: () => widget.canReplace?.call() ?? true,
      isOwnerActive: () => mounted && (widget.isOwnerActive?.call() ?? true),
    )..addListener(_onMatchesChanged);
  }

  @override
  void didUpdateWidget(covariant FindAndReplaceMenuWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.editorState, widget.editorState)) {
      _focusRequest++;
      _session
        ..removeListener(_onMatchesChanged)
        ..dispose();
      _bindSession();
      final session = _session;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && identical(session, _session)) {
          _search();
        }
      });
    }
    if (oldWidget.showReplaceMenu != widget.showReplaceMenu) {
      showReplaceMenu = widget.showReplaceMenu && _session.replaceAllowed;
      _keepTyping(showReplaceMenu ? replaceFocusNode : findFocusNode);
    }
  }

  @override
  void dispose() {
    _focusRequest++;
    _session
      ..removeListener(_onMatchesChanged)
      ..dispose();
    findController.removeListener(_search);
    findController.dispose();
    replaceController.dispose();
    _ownedFindFocusNode.dispose();
    _ownedReplaceFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final session = _session;
    final matches = session.matches;
    final canNavigate = matches.isNotEmpty && !session.busy;
    final canReplace = session.replaceAllowed;
    final bar = FindReplaceBar(
      findController: findController,
      findFocusNode: findFocusNode,
      // This host chooses Find versus Replace and guards deferred focus by
      // session ownership, including a close before the overlay's first frame.
      autofocus: false,
      options: options,
      onOptionsChanged: (value) {
        if (!_isCurrentSession(session)) {
          return;
        }
        setState(() => options = value);
        _search();
      },
      matchCount: matches.length,
      currentMatch: matches.isEmpty ? 0 : session.selectedIndex + 1,
      queryInvalid: session.invalidPattern,
      busy: session.busy || session.loadingReferences,
      onPrevious: canNavigate ? () => _navigate(session, moveUp: true) : null,
      onNext: canNavigate ? () => _navigate(session) : null,
      onSubmitted: canNavigate ? () => _navigate(session) : null,
      onClose: () => _dismiss(session),
      onTapOutside: () => _dismiss(session),
      replaceController: canReplace ? replaceController : null,
      replaceFocusNode: canReplace ? replaceFocusNode : null,
      showReplace: canReplace && showReplaceMenu,
      onToggleReplace: canReplace
          ? () {
              if (_isCurrentSession(session) && session.replaceAllowed) {
                setState(() => showReplaceMenu = !showReplaceMenu);
              }
            }
          : null,
      onReplace: canReplace && canNavigate && session.currentIsWritable
          ? () => _replace(session, all: false)
          : null,
      onReplaceAll: canReplace && canNavigate && session.hasWritableMatches
          ? () => _replace(session, all: true)
          : null,
    );
    // Keep the native fields at a constant depth; result changes must not
    // remount their EditableText or hand query focus to an embedded renderer.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        bar,
        if (session.loadingReferences ||
            session.referencesTimedOut ||
            session.coverageUnknownCount > 0 ||
            session.unavailableCount > 0 ||
            session.truncated ||
            session.current?.isWritable == false)
          _DocumentFindDetails(session: session),
      ],
    );
  }

  bool _isCurrentSession(DocumentFindSession session) =>
      mounted && identical(session, _session) && session.isActive;

  void _dismiss(DocumentFindSession session) {
    if (!mounted || !identical(session, _session)) {
      return;
    }
    _focusRequest++;
    // No focus restoration: the outside click must reach its new target.
    widget.onDismiss();
  }

  void _search() {
    _focusRequest++;
    _session.search(findController.text, options);
  }

  void _navigate(DocumentFindSession session, {bool moveUp = false}) {
    if (!_isCurrentSession(session) || session.busy) {
      return;
    }
    session.navigate(previous: moveUp);
    _keepTyping(findFocusNode);
  }

  Future<void> _replace(
    DocumentFindSession session, {
    required bool all,
  }) async {
    if (!_isCurrentSession(session)) {
      return;
    }
    final revision = session.revision;
    final focusRequest = _focusRequest;
    if (all) {
      await session.replaceAll(replaceController.text);
    } else {
      await session.replaceCurrent(replaceController.text);
    }
    if (mounted &&
        identical(session, _session) &&
        revision == session.revision &&
        focusRequest == _focusRequest &&
        session.replaceAllowed) {
      _keepTyping(replaceFocusNode);
    }
  }

  /// Writing to the page hands the focus back to the editor, and the person is
  /// still typing in the bar.
  void _keepTyping(FocusNode node) {
    final request = ++_focusRequest;
    final session = _session;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          request == _focusRequest &&
          identical(session, _session) &&
          session.isActive &&
          (node == findFocusNode || node == replaceFocusNode)) {
        final target = node == replaceFocusNode && !session.replaceAllowed
            ? findFocusNode
            : node;
        if (target.parent != null && (target.context?.mounted ?? false)) {
          target.requestFocus();
        }
      }
    });
  }

  void _onMatchesChanged() {
    if (!mounted) {
      return;
    }
    final session = _session;
    void rebuild() {
      if (mounted && identical(session, _session)) {
        setState(() {
          if (!session.replaceAllowed) {
            showReplaceMenu = false;
          }
        });
      }
    }

    // AppFlowyEditor also updates editableNotifier from didUpdateWidget.
    // The bar is in a sibling overlay, not inside that editor's build scope.
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) => rebuild());
    } else {
      rebuild();
    }
  }
}

class _DocumentFindDetails extends StatelessWidget {
  const _DocumentFindDetails({required this.session});
  final DocumentFindSession session;

  @override
  Widget build(BuildContext context) {
    final palette = FindBarPalette.of(context);
    final current = session.current;
    final messages = <String>[
      if (session.loadingReferences) 'Searching linked content…',
      if (session.referencesTimedOut)
        'Partial search: linked content deadline reached. A native read may still be pending.',
      if (session.coverageUnknownCount > 0)
        'Partial search: full native row/cell or live file coverage could not be verified.',
      if (session.unavailableCount > 0)
        'Partial search: ${session.unavailableCount} source(s) unavailable, unsupported or not permitted.',
      if (session.truncated)
        'Partial search: linked content or spreadsheet limit reached.',
      if (current?.isWritable == false)
        'Read-only match · ${current!.location}',
    ];
    final match = current?.isWritable == false ? current!.match : null;
    // A selected range, not the start of a long row/page: the visible snippet
    // always contains the actual match, even when native content is virtualized.
    final start =
        match == null ? 0 : (match.start - 70).clamp(0, match.input.length);
    final end =
        match == null ? 0 : (match.end + 90).clamp(0, match.input.length);
    final matchedEnd =
        match == null ? 0 : (match.start + 160).clamp(match.start, match.end);
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 560),
      child: Container(
        key: const ValueKey('documentFindDetails'),
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Semantics(
          liveRegion: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                messages.join('\n'),
                style: TextStyle(fontSize: 11.5, color: palette.textSecondary),
              ),
              if (match != null) ...[
                const SizedBox(height: 6),
                Text.rich(
                  key: const ValueKey('documentFindSnippet'),
                  TextSpan(
                    children: [
                      TextSpan(
                        text:
                            '${start > 0 ? '…' : ''}${match.input.substring(start, match.start)}',
                      ),
                      TextSpan(
                        text:
                            '${match.input.substring(match.start, matchedEnd)}${matchedEnd < match.end ? '…' : ''}',
                        style: TextStyle(
                          backgroundColor: FindHighlightColors.current(
                            Theme.of(context).brightness,
                          ),
                        ),
                      ),
                      TextSpan(
                        text:
                            '${match.input.substring(match.end, end)}${end < match.input.length ? '…' : ''}',
                      ),
                    ],
                  ),
                  style: TextStyle(fontSize: 13, color: palette.textPrimary),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
