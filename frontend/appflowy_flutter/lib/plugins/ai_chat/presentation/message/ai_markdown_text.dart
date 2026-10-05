import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/page_style/document_page_style_bloc.dart';
import 'package:appflowy/plugins/ai_chat/application/chat_text_selection.dart';
import 'package:appflowy/plugins/ai_chat/presentation/chat_find.dart';
import 'package:appflowy/plugins/document/presentation/editor_configuration.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/plugins.dart';
import 'package:appflowy/shared/editor_focus_node.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import '../chat_editor_style.dart';

// Wrap the appflowy_editor as a chat text message widget
class AIMarkdownText extends StatelessWidget {
  const AIMarkdownText({
    super.key,
    required this.markdown,
    this.withAnimation = false,
    this.findMessageId,
  });

  final String markdown;
  final bool withAnimation;
  final String? findMessageId;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => DocumentPageStyleBloc(view: ViewPB())
        ..add(const DocumentPageStyleEvent.initial()),
      child: _AppFlowyEditorMarkdown(
        markdown: markdown,
        withAnimation: withAnimation,
        findMessageId: findMessageId,
      ),
    );
  }
}

class _AppFlowyEditorMarkdown extends StatefulWidget {
  const _AppFlowyEditorMarkdown({
    required this.markdown,
    this.withAnimation = false,
    this.findMessageId,
  });

  // the text should be the markdown format
  final String markdown;

  /// Whether to animate the text.
  final bool withAnimation;
  final String? findMessageId;

  @override
  State<_AppFlowyEditorMarkdown> createState() =>
      _AppFlowyEditorMarkdownState();
}

class _AppFlowyEditorMarkdownState extends State<_AppFlowyEditorMarkdown>
    with TickerProviderStateMixin {
  /// How the answer is uncovered as it arrives. Short steps read as writing;
  /// long ones read as text being pasted in a lump.
  static const _revealInterval = Duration(milliseconds: 24);
  static const _revealChunk = 10;

  late EditorState editorState;
  late EditorScrollController scrollController;
  final EditorFocusNode _focusNode = EditorFocusNode(debugLabel: 'chat answer');
  Timer? markdownOutputTimer;
  int offset = 0;
  String _renderedMarkdown = '';
  SurfaceFindController? _find;
  bool _reduceMotion = false;
  bool _animate = false;

  final Map<String, (AnimationController, Animation<double>)> _animations = {};

  @override
  void initState() {
    super.initState();

    _renderedMarkdown = widget.markdown.trim();
    editorState = _parseMarkdown(_renderedMarkdown);
    offset = widget.markdown.length;
    scrollController = EditorScrollController(
      editorState: editorState,
      shrinkWrap: true,
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _find = SurfaceFindScope.maybeOf(context);
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    _syncReveal();
  }

  @override
  void didUpdateWidget(covariant _AppFlowyEditorMarkdown oldWidget) {
    super.didUpdateWidget(oldWidget);

    _syncReveal();
  }

  void _syncReveal() {
    _animate = widget.withAnimation && !_reduceMotion && _find?.isOpen != true;
    if (!_animate || offset > widget.markdown.length) {
      markdownOutputTimer?.cancel();
      markdownOutputTimer = null;
      offset = widget.markdown.length;
      _adoptMarkdown(widget.markdown);
      for (final entry in _animations.values) {
        entry.$1
          ..stop()
          ..value = 1;
      }
      return;
    }
    if (offset >= widget.markdown.length || markdownOutputTimer != null) return;
    markdownOutputTimer = Timer.periodic(_revealInterval, (_) {
      if (!mounted || !_animate) return;
      final behind = widget.markdown.length - offset;
      offset = math.min(
        widget.markdown.length,
        offset + math.max(_revealChunk, behind ~/ 16),
      );
      setState(() => _adoptMarkdown(widget.markdown.substring(0, offset)));
      if (offset >= widget.markdown.length) {
        markdownOutputTimer?.cancel();
        markdownOutputTimer = null;
      }
    });
  }

  void _adoptMarkdown(String markdown) {
    final text = markdown.trim();
    if (text == _renderedMarkdown) return;
    final next = _parseMarkdown(text, previousDocument: editorState.document);
    _renderedMarkdown = text;
    scrollController.dispose();
    editorState.dispose();
    editorState = next;
    scrollController =
        EditorScrollController(editorState: next, shrinkWrap: true);
  }

  @override
  void dispose() {
    scrollController.dispose();
    editorState.dispose();
    _focusNode.dispose();

    markdownOutputTimer?.cancel();
    for (final controller in _animations.values.map((e) => e.$1)) {
      controller.dispose();
    }

    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // don't lazy load the styleCustomizer and blockBuilders,
    // it needs the context to get the theme.
    final styleCustomizer = ChatEditorStyleCustomizer(
      context: context,
      padding: EdgeInsets.zero,
    );
    final editorStyle = styleCustomizer.style().copyWith(
          // hide the cursor
          cursorColor: Colors.transparent,
          cursorWidth: 0,
        );
    final blockBuilders = buildBlockComponentBuilders(
      context: context,
      editorState: editorState,
      styleCustomizer: styleCustomizer,
      // the editor is not editable in the chat
      editable: false,
      alwaysDistributeSimpleTableColumnWidths: UniversalPlatform.isDesktop,
      customPadding: (node) => EdgeInsets.zero,
    );
    return IntrinsicHeight(
      child: Listener(
        // The editor runs its own selection service, so text selected inside an
        // answer is invisible to the SelectionArea around the chat. Reporting
        // it here is what lets one Ctrl+C serve both.
        onPointerUp: (_) => ChatTextSelection.instance.report(_selectedText()),
        child: AppFlowyEditor(
          shrinkWrap: true,
          focusNode: _focusNode,
          // the editor is not editable in the chat
          editable: false,
          disableKeyboardService: UniversalPlatform.isMobile,
          disableSelectionService: UniversalPlatform.isMobile,
          editorStyle: editorStyle,
          editorScrollController: scrollController,
          blockComponentBuilders: blockBuilders,
          commandShortcutEvents: [customCopyCommand],
          disableAutoScroll: true,
          editorState: editorState,
          blockWrapper: (
            context, {
            required Node node,
            required Widget child,
          }) {
            final messageId = widget.findMessageId;
            final content = messageId != null && node.delta != null
                ? SurfaceFindTarget(
                    id: chatFindTextId(messageId, node.path),
                    includeEditable: true,
                    child: child,
                  )
                : child;

            if (_animate && !_animations.containsKey(node.id)) {
              final duration = UniversalPlatform.isMobile
                  ? const Duration(milliseconds: 260)
                  : const Duration(milliseconds: 420);
              final controller = AnimationController(
                vsync: this,
                duration: duration,
              );
              final fade = CurvedAnimation(
                parent: controller,
                curve: Curves.easeOut,
              );
              _animations[node.id] = (controller, fade);
              controller.forward();
            }
            // Always retain this wrapper: toggling Find/reduced motion must
            // not reparent a native editor block or dispose its selection.
            final fade = _animate
                ? _animations[node.id]!.$2
                : const AlwaysStoppedAnimation<double>(1);
            return _AnimatedWrapper(
              fade: fade,
              child: content,
            );
          },
          contextMenuItems: [
            [
              ContextMenuItem(
                getName: LocaleKeys.document_plugins_contextMenu_copy.tr,
                onPressed: (editorState) =>
                    customCopyCommand.execute(editorState),
              ),
            ]
          ],
        ),
      ),
    );
  }

  EditorState _parseMarkdown(
    String markdown, {
    Document? previousDocument,
  }) {
    final document = customMarkdownToDocument(markdown);
    final documentIterator = NodeIterator(
      document: document,
      startNode: document.root,
    );
    if (previousDocument != null) {
      final previousDocumentIterator = NodeIterator(
        document: previousDocument,
        startNode: previousDocument.root,
      );
      while (
          documentIterator.moveNext() && previousDocumentIterator.moveNext()) {
        final currentNode = documentIterator.current;
        final previousNode = previousDocumentIterator.current;
        if (currentNode.path.equals(previousNode.path)) {
          currentNode.id = previousNode.id;
        }
      }
    }
    final editorState = EditorState(document: document);
    return editorState;
  }

  String _selectedText() {
    final selection = editorState.selection;
    if (selection == null || selection.isCollapsed) {
      return '';
    }
    return editorState.getTextInSelection(selection).join('\n');
  }
}

class _AnimatedWrapper extends StatelessWidget {
  const _AnimatedWrapper({
    required this.fade,
    required this.child,
  });

  final Animation<double> fade;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: fade,
      builder: (context, childWidget) {
        final value = fade.value.clamp(0.0, 1.0);
        // The reveal runs a soft edge left to right. ⚠️ Both stops must reach 1
        // when the animation ends, or the tail of every block stays masked out
        // for good and the answer reads as half missing.
        const softness = 0.25;
        final end = value * (1 + softness);
        final start = (end - softness).clamp(0.0, 1.0);
        return ShaderMask(
          shaderCallback: (Rect bounds) {
            return LinearGradient(
              stops: [start, end.clamp(0.0, 1.0)],
              colors: const [
                Colors.white,
                Colors.transparent,
              ],
            ).createShader(bounds);
          },
          blendMode: BlendMode.dstIn,
          child: Opacity(
            opacity: value,
            child: childWidget,
          ),
        );
      },
      child: child,
    );
  }
}
