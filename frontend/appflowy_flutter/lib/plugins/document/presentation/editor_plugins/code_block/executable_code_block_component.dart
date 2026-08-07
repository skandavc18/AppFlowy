import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/code_block/syntax_highlighter.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:universal_platform/universal_platform.dart';

const codeBlockShowLineNumbers = 'show_line_numbers';
const codeBlockWidth = 'width';
const codeBlockHeight = 'height';
const codeBlockTestCases = 'test_cases';
const codeBlockMinHeight = 140.0;

class ExecutableCodeBlockComponentBuilder extends CodeBlockComponentBuilder {
  ExecutableCodeBlockComponentBuilder({
    required this.baseStyleBuilder,
    required super.configuration,
    required super.padding,
  });

  final CodeBlockStyle Function() baseStyleBuilder;

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    final baseStyle = baseStyleBuilder();

    return _ExecutableCodeBlockComponentWidget(
      key: node.key,
      node: node,
      configuration: configuration,
      padding: padding,
      showActions: showActions(node),
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
      style: baseStyle,
    );
  }
}

class _ExecutableCodeBlockComponentWidget extends BlockComponentStatefulWidget {
  const _ExecutableCodeBlockComponentWidget({
    super.key,
    required super.node,
    required super.configuration,
    required super.showActions,
    required super.actionBuilder,
    required this.padding,
    required this.style,
  });

  final EdgeInsets padding;
  final CodeBlockStyle style;

  @override
  State<_ExecutableCodeBlockComponentWidget> createState() =>
      _ExecutableCodeBlockComponentWidgetState();
}

class _ExecutableCodeBlockComponentWidgetState
    extends State<_ExecutableCodeBlockComponentWidget>
    with
        SelectableMixin,
        DefaultSelectableMixin,
        BlockComponentConfigurable,
        BlockComponentTextDirectionMixin {
  @override
  final forwardKey = GlobalKey(debugLabel: 'premium_code_flowy_rich_text');

  @override
  final blockComponentKey = GlobalKey(debugLabel: CodeBlockKeys.type);

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  GlobalKey<State<StatefulWidget>> get containerKey => node.key;

  @override
  Node get node => widget.node;

  @override
  late EditorState editorState;
  StreamSubscription<EditorTransactionValue>? transactionSubscription;
  final horizontalScrollController = ScrollController();
  final verticalScrollController = ScrollController();
  final codeViewportKey = GlobalKey();
  final verticalViewportKey = GlobalKey();
  bool attached = false;
  bool canPanStart = true;

  late final selectionInterceptor = SelectionGestureInterceptor(
    key: 'premium-code-block-${node.id}',
    canTap: (_) => canPanStart,
    canPanStart: (_) => canPanStart,
  );

  String get language => normalizeCodeLanguage(
        node.attributes[CodeBlockKeys.language] as String? ?? 'auto',
      );

  bool get showLineNumbers =>
      node.attributes[codeBlockShowLineNumbers] as bool? ?? true;

  List<CodeTestCase> get testCases =>
      decodeCodeTestCases(node.attributes[codeBlockTestCases]);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final nextEditorState = context.read<EditorState>();
    if (attached && identical(editorState, nextEditorState)) {
      return;
    }

    _detachEditorState();
    editorState = nextEditorState;
    attached = true;
    if (editorState.editable) {
      editorState.selectionService.registerGestureInterceptor(
        selectionInterceptor,
      );
      editorState.selectionNotifier.addListener(_ensureCursorVisible);
    }
    transactionSubscription = editorState.transactionStream.listen((event) {
      if (event.$2.operations
          .any((operation) => operation.path.equals(node.path))) {
        _ensureCursorVisible();
      }
    });
  }

  @override
  void dispose() {
    _detachEditorState();
    horizontalScrollController.dispose();
    verticalScrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final textDirection = calculateTextDirection(
      layoutDirection: Directionality.maybeOf(context),
    );
    final code = node.delta?.toPlainText() ?? '';

    Widget child = Padding(
      key: blockComponentKey,
      padding: widget.padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final availableWidth = constraints.maxWidth.isFinite
              ? constraints.maxWidth
              : defaultVisualMediaWidth;
          final width =
              node.attributes[codeBlockWidth]?.toDouble() ?? availableWidth;
          final height = node.attributes[codeBlockHeight]?.toDouble();
          return ResizableMedia(
            width: width,
            minWidth: 320,
            height: height,
            minHeight: codeBlockMinHeight,
            alignment: blockEmbedAlignment(node),
            editable: editorState.editable && UniversalPlatform.isDesktopOrWeb,
            onResize: _updateWidth,
            onResizeHeight: _updateHeight,
            child: SandboxedCodeRunner(
              code: code,
              fileName: fileNameForCodeLanguage(language),
              language: language,
              showLineNumbers: showLineNumbers,
              contentPadding: const EdgeInsets.fromLTRB(14, 14, 16, 18),
              onHeaderInteractionChanged: (interacting) {
                canPanStart = !interacting;
              },
              // While the prompt has focus the document must not: the editor
              // reads Backspace before the field does and would edit the code
              // instead of the answer being typed.
              onTerminalFocusChanged: (hasFocus) {
                if (hasFocus && keepEditorFocusNotifier.value == 0) {
                  editorState.selection = null;
                }
              },
              onLanguageChanged: _updateLanguage,
              onToggleLineNumbers: _toggleLineNumbers,
              editable: editorState.editable,
              testCases: testCases,
              onTestCasesChanged: _updateTestCases,
              child: _buildCodeEditor(
                context,
                code: code,
                textDirection: textDirection,
              ),
            ),
          );
        },
      ),
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (UniversalPlatform.isDesktopOrWeb &&
        widget.showActions &&
        widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }

    return child;
  }

  Widget _buildCodeEditor(
    BuildContext context, {
    required String code,
    required TextDirection textDirection,
  }) {
    final baseTextStyle =
        (widget.style.textStyle ?? textStyleWithTextSpan()).copyWith(
      height: 1.55,
      fontFamilyFallback: const [
        'JetBrains Mono',
        'Geist Mono',
        'RobotoMono',
        'monospace',
      ],
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final highlightedSpan = buildSyntaxHighlightedTextSpan(
      code: code,
      language: language,
      brightness: Theme.of(context).brightness,
      isPaper: PaperTheme.isEnabled(context),
      style: baseTextStyle,
    );
    final editor = AppFlowyRichText(
      key: forwardKey,
      delegate: this,
      node: node,
      editorState: editorState,
      placeholderText: placeholderText,
      lineHeight: 1.55,
      textSpanDecorator: (_) => highlightedSpan,
      placeholderTextSpanDecorator: (textSpan) => textSpan,
      textDirection: textDirection,
      cursorColor: editorState.editorStyle.cursorColor,
      selectionColor: editorState.editorStyle.selectionColor,
    );
    final wrapLines = widget.style.wrapLines && !showLineNumbers;
    final codeEditor = wrapLines
        ? editor
        : Scrollbar(
            controller: horizontalScrollController,
            thumbVisibility: false,
            trackVisibility: false,
            interactive: true,
            thickness: 3,
            radius: const Radius.circular(999),
            child: SingleChildScrollView(
              key: codeViewportKey,
              controller: horizontalScrollController,
              padding: const EdgeInsets.only(bottom: 4),
              scrollDirection: Axis.horizontal,
              child: editor,
            ),
          );
    final lineNumberColor = AppFlowyTheme.of(context).textColorScheme.tertiary;

    return Scrollbar(
      controller: verticalScrollController,
      thumbVisibility: false,
      trackVisibility: false,
      interactive: true,
      thickness: 3,
      radius: const Radius.circular(999),
      child: SingleChildScrollView(
        key: verticalViewportKey,
        controller: verticalScrollController,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showLineNumbers)
              _CodeLineNumbers(
                count: '\n'.allMatches(code).length + 1,
                style: baseTextStyle.copyWith(color: lineNumberColor),
              ),
            Flexible(child: codeEditor),
          ],
        ),
      ),
    );
  }

  void _updateLanguage(String value) {
    final normalized = normalizeCodeLanguage(value);
    final transaction = editorState.transaction
      ..updateNode(node, {
        CodeBlockKeys.language: normalized == 'auto' ? null : normalized,
      });
    unawaited(editorState.apply(transaction));
  }

  void _toggleLineNumbers() {
    final transaction = editorState.transaction
      ..updateNode(node, {
        codeBlockShowLineNumbers: !showLineNumbers,
      });
    unawaited(editorState.apply(transaction));
  }

  void _updateTestCases(List<CodeTestCase> cases) {
    final transaction = editorState.transaction
      ..updateNode(node, {
        // A null attribute is dropped, so an emptied tray leaves no trace.
        codeBlockTestCases: cases.isEmpty ? null : encodeCodeTestCases(cases),
      });
    unawaited(editorState.apply(transaction));
  }

  void _updateWidth(double width) {
    final transaction = editorState.transaction
      ..updateNode(node, {codeBlockWidth: width});
    unawaited(editorState.apply(transaction));
  }

  void _updateHeight(double height) {
    final transaction = editorState.transaction
      ..updateNode(node, {codeBlockHeight: height});
    unawaited(editorState.apply(transaction));
  }

  void _ensureCursorVisible() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final selection = editorState.selection;
      if (!mounted || selection == null || !selection.isCollapsed) {
        return;
      }

      final selectedNodes = editorState.getNodesInSelection(selection);
      if (selectedNodes.length != 1 ||
          !selectedNodes.first.path.equals(node.path)) {
        return;
      }

      final selectionRects = editorState.selectionRects();
      if (selectionRects.isEmpty) {
        return;
      }
      final cursorRect = selectionRects.first;
      _revealCursorInViewport(
        controller: horizontalScrollController,
        viewportKey: codeViewportKey,
        cursorRect: cursorRect,
        axis: Axis.horizontal,
      );
      _revealCursorInViewport(
        controller: verticalScrollController,
        viewportKey: verticalViewportKey,
        cursorRect: cursorRect,
        axis: Axis.vertical,
      );
    });
  }

  void _revealCursorInViewport({
    required ScrollController controller,
    required GlobalKey viewportKey,
    required Rect cursorRect,
    required Axis axis,
  }) {
    if (!controller.hasClients) {
      return;
    }
    final renderBox =
        viewportKey.currentContext?.findRenderObject() as RenderBox?;
    if (renderBox == null) {
      return;
    }

    final viewportOffset = renderBox.localToGlobal(Offset.zero);
    final cursorOffset = cursorRect.center - viewportOffset;
    final cursorPosition =
        axis == Axis.horizontal ? cursorOffset.dx : cursorOffset.dy;
    final viewportExtent =
        axis == Axis.horizontal ? renderBox.size.width : renderBox.size.height;
    final currentOffset = controller.offset;
    double? targetOffset;
    if (cursorPosition < 1 && currentOffset > 0) {
      targetOffset = currentOffset + cursorPosition - 1;
    } else if (cursorPosition > viewportExtent - 1) {
      targetOffset = currentOffset + cursorPosition - viewportExtent + 1;
    }

    if (targetOffset != null) {
      controller.jumpTo(
        targetOffset.clamp(
          0.0,
          controller.position.maxScrollExtent,
        ),
      );
    }
  }

  void _detachEditorState() {
    if (!attached) {
      return;
    }

    if (editorState.editable) {
      editorState.selectionNotifier.removeListener(_ensureCursorVisible);
      editorState.selectionService.unregisterGestureInterceptor(
        selectionInterceptor.key,
      );
    }
    unawaited(transactionSubscription?.cancel());
    transactionSubscription = null;
    attached = false;
  }
}

class _CodeLineNumbers extends StatelessWidget {
  const _CodeLineNumbers({required this.count, required this.style});

  final int count;
  final TextStyle style;

  @override
  Widget build(BuildContext context) {
    final width = 18.0 + count.toString().length * 8.0;
    return ExcludeSemantics(
      child: SizedBox(
        width: width,
        child: Padding(
          padding: const EdgeInsets.only(top: 1, right: 12),
          child: Text(
            List.generate(count, (index) => '${index + 1}').join('\n'),
            textAlign: TextAlign.right,
            style: style,
          ),
        ),
      ),
    );
  }
}
