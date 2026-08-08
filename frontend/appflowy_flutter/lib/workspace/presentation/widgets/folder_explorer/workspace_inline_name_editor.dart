import 'dart:async';

import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const workspaceInlineRenameTransitionDuration = Duration(milliseconds: 120);

/// `RenderEditable` lays its text out in `width - (1.0 + cursorWidth)` and keeps
/// the rest for the caret. A box measured from the label alone is therefore too
/// narrow for the same string, and wraps its last glyph onto a clipped line.
const workspaceInlineRenameCaretRoom = 3.0;

const _caretRoom =
    EdgeInsetsDirectional.only(end: workspaceInlineRenameCaretRoom);

bool isWorkspaceRenameShortcut(
  TargetPlatform platform,
  LogicalKeyboardKey key,
) =>
    switch (platform) {
      TargetPlatform.macOS => key == LogicalKeyboardKey.enter,
      TargetPlatform.windows ||
      TargetPlatform.linux =>
        key == LogicalKeyboardKey.f2,
      _ => false,
    };

class WorkspaceInlineEditableText extends StatelessWidget {
  const WorkspaceInlineEditableText({
    super.key,
    required this.text,
    required this.editing,
    required this.onSubmitted,
    required this.onCancelled,
    required this.style,
    this.editingValue,
    this.onTap,
    this.onDoubleTap,
    this.display,
    this.maxLines = 1,
    this.overflow = TextOverflow.ellipsis,
    this.textAlign = TextAlign.start,
    this.strutStyle,
    this.selectFileStem = false,
    this.maxLength = 256,
  });

  final String text;
  final String? editingValue;
  final bool editing;
  final Future<bool> Function(String name) onSubmitted;
  final VoidCallback onCancelled;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final Widget? display;
  final TextStyle style;
  final int maxLines;
  final TextOverflow overflow;
  final TextAlign textAlign;
  final StrutStyle? strutStyle;
  final bool selectFileStem;
  final int maxLength;

  @override
  Widget build(BuildContext context) {
    final displayChild = Padding(
      padding: _caretRoom,
      child: MouseRegion(
        cursor: onTap == null && onDoubleTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.text,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          child: display ??
              Text(
                text,
                maxLines: maxLines,
                overflow: overflow,
                textAlign: textAlign,
                strutStyle: strutStyle,
                style: style,
              ),
        ),
      ),
    );

    return AnimatedSwitcher(
      duration: workspaceInlineRenameTransitionDuration,
      reverseDuration: workspaceInlineRenameTransitionDuration,
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      layoutBuilder: (currentChild, previousChildren) => Stack(
        alignment: _alignmentFor(textAlign),
        children: [
          ...previousChildren,
          if (currentChild != null) currentChild,
        ],
      ),
      child: editing
          ? WorkspaceInlineNameEditor(
              key: const ValueKey('workspace-inline-editing'),
              initialValue: editingValue ?? text,
              sizingText: text,
              onSubmitted: onSubmitted,
              onCancelled: onCancelled,
              textStyle: style,
              maxLines: maxLines,
              textAlign: textAlign,
              strutStyle: strutStyle,
              selectFileStem: selectFileStem,
              maxLength: maxLength,
            )
          : KeyedSubtree(
              key: const ValueKey('workspace-inline-display'),
              child: displayChild,
            ),
    );
  }
}

class WorkspaceInlineNameEditor extends StatefulWidget {
  const WorkspaceInlineNameEditor({
    super.key,
    required this.initialValue,
    required this.onSubmitted,
    required this.onCancelled,
    this.sizingText,
    this.textStyle,
    this.maxLines = 1,
    this.textAlign = TextAlign.start,
    this.strutStyle,
    this.maxLength = 256,
    this.selectFileStem = false,
    this.debugLabel = 'workspace-inline-name-editor',
  });

  final String initialValue;
  final String? sizingText;
  final Future<bool> Function(String name) onSubmitted;
  final VoidCallback onCancelled;
  final TextStyle? textStyle;
  final int maxLines;
  final TextAlign textAlign;
  final StrutStyle? strutStyle;
  final int maxLength;
  final bool selectFileStem;
  final String debugLabel;

  @override
  State<WorkspaceInlineNameEditor> createState() =>
      _WorkspaceInlineNameEditorState();
}

class _WorkspaceInlineNameEditorState extends State<WorkspaceInlineNameEditor> {
  late final TextEditingController controller =
      TextEditingController(text: widget.initialValue);
  late final FocusNode focusNode = FocusNode(debugLabel: widget.debugLabel)
    ..addListener(_handleFocusChanged);

  bool submitting = false;
  bool completed = false;
  bool cancelled = false;
  bool invalid = false;

  /// `RenderEditable` carries its own tap recognizer, and it collapses the
  /// selection onto a caret. A title that opens on a single click therefore
  /// loses its select-all to the second click of a double click, so the field
  /// stays deaf to the pointer until that click can no longer arrive.
  bool acceptsPointer = false;
  Timer? pointerGate;

  @override
  void initState() {
    super.initState();
    pointerGate = Timer(kDoubleTapTimeout, () {
      if (mounted) {
        setState(() => acceptsPointer = true);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      focusNode.requestFocus();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _selectionEnd(controller.text),
      );
    });
  }

  @override
  void dispose() {
    pointerGate?.cancel();
    focusNode
      ..removeListener(_handleFocusChanged)
      ..dispose();
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final style = widget.textStyle ??
        TextStyle(
          color: palette.textPrimary,
          fontSize: 13,
          height: 1.2,
        );
    final sizingText = widget.sizingText ?? widget.initialValue;

    return Stack(
      alignment: _alignmentFor(widget.textAlign),
      children: [
        IgnorePointer(
          child: Opacity(
            opacity: 0,
            child: Padding(
              padding: _caretRoom,
              child: Text(
                sizingText.isEmpty ? '\u200B' : sizingText,
                maxLines: widget.maxLines,
                overflow: TextOverflow.ellipsis,
                textAlign: widget.textAlign,
                strutStyle: widget.strutStyle,
                style: style,
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Focus(
            onKeyEvent: (_, event) {
              if (event is KeyDownEvent &&
                  event.logicalKey == LogicalKeyboardKey.escape) {
                _cancel();
                return KeyEventResult.handled;
              }
              return KeyEventResult.ignored;
            },
            child: EditableText(
              key: const ValueKey('workspace-inline-name-editor'),
              controller: controller,
              focusNode: focusNode,
              style: style,
              strutStyle: widget.strutStyle,
              cursorColor: invalid ? palette.danger : palette.accent,
              backgroundCursorColor: palette.textMuted,
              selectionColor: palette.accent.withValues(alpha: 0.18),
              cursorWidth: 1.15,
              cursorRadius: const Radius.circular(0.6),
              cursorOpacityAnimates: true,
              textAlign: widget.textAlign,
              maxLines: widget.maxLines,
              minLines: 1,
              keyboardType: TextInputType.text,
              textInputAction: TextInputAction.done,
              keyboardAppearance: Theme.of(context).brightness,
              inputFormatters: [
                LengthLimitingTextInputFormatter(widget.maxLength),
              ],
              mouseCursor: SystemMouseCursors.text,
              rendererIgnoresPointer: !acceptsPointer,
              onChanged: (_) {
                if (invalid) {
                  setState(() => invalid = false);
                }
              },
              onSubmitted: (_) => unawaited(_submit()),
              onTapOutside: _handleTapOutside,
            ),
          ),
        ),
      ],
    );
  }

  void _handleFocusChanged() {
    if (focusNode.hasFocus || cancelled || completed) {
      return;
    }
    // Focus bounces for a frame while the label swaps for the field. Only a
    // loss that is still true next frame means somebody moved on.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !focusNode.hasFocus && !cancelled && !completed) {
        unawaited(_submit());
      }
    });
  }

  /// A tap that landed on the editor's own box is not "outside" it.
  ///
  /// The second click of a double click arrives while the label is still
  /// swapping for the field, so it misses the `EditableText`'s tap region and
  /// would otherwise submit and close the editor the instant it opened.
  void _handleTapOutside(PointerDownEvent event) {
    final box = context.findRenderObject() as RenderBox?;
    if (box != null && box.hasSize) {
      final local = box.globalToLocal(event.position);
      if (local.dx >= 0 &&
          local.dy >= 0 &&
          local.dx <= box.size.width &&
          local.dy <= box.size.height) {
        focusNode.requestFocus();
        controller.selection = TextSelection(
          baseOffset: 0,
          extentOffset: _selectionEnd(controller.text),
        );
        return;
      }
    }
    unawaited(_submit());
  }

  void _cancel() {
    if (cancelled || completed) {
      return;
    }
    cancelled = true;
    widget.onCancelled();
  }

  Future<void> _submit() async {
    if (submitting || cancelled || completed) {
      return;
    }
    final name = controller.text.trim();
    if (name.isEmpty) {
      if (mounted) {
        setState(() => invalid = true);
        focusNode.requestFocus();
      }
      return;
    }

    setState(() => submitting = true);
    final success = await widget.onSubmitted(name);
    if (success) {
      completed = true;
      return;
    }
    if (mounted) {
      setState(() => submitting = false);
      focusNode.requestFocus();
      controller.selection = TextSelection(
        baseOffset: 0,
        extentOffset: _selectionEnd(controller.text),
      );
    }
  }

  int _selectionEnd(String value) {
    if (!widget.selectFileStem) {
      return value.length;
    }
    final dot = value.lastIndexOf('.');
    return dot <= 0 ? value.length : dot;
  }
}

AlignmentGeometry _alignmentFor(TextAlign textAlign) => switch (textAlign) {
      TextAlign.left ||
      TextAlign.start ||
      TextAlign.justify =>
        AlignmentDirectional.centerStart,
      TextAlign.right || TextAlign.end => AlignmentDirectional.centerEnd,
      TextAlign.center => Alignment.center,
    };
