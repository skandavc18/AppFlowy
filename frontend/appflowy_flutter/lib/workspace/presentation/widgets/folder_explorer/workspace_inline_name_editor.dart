import 'dart:async';

import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

const workspaceInlineRenameTransitionDuration = Duration(milliseconds: 120);

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
    final displayChild = MouseRegion(
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

  @override
  void initState() {
    super.initState();
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
              onChanged: (_) {
                if (invalid) {
                  setState(() => invalid = false);
                }
              },
              onSubmitted: (_) => unawaited(_submit()),
              onTapOutside: (_) => unawaited(_submit()),
            ),
          ),
        ),
      ],
    );
  }

  void _handleFocusChanged() {
    if (!focusNode.hasFocus && !cancelled && !completed) {
      unawaited(_submit());
    }
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
