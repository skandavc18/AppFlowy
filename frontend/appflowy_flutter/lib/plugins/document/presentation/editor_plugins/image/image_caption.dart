import 'dart:async';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/custom_image_block_component/custom_image_block_component.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// The line of text under a picture.
///
/// It is invisible until there is something to show or the block is hovered,
/// so an uncaptioned image keeps its clean edge.
class ImageCaption extends StatefulWidget {
  const ImageCaption({
    super.key,
    required this.node,
    required this.editorState,
    required this.editable,
    required this.isHovering,
    required this.focusRequest,
    this.textAlign = TextAlign.center,
  });

  final Node node;
  final EditorState editorState;
  final bool editable;

  /// Drives the placeholder: an empty caption only offers itself on hover.
  final ValueListenable<bool> isHovering;

  /// Bumped by the block menu to put the caret in the field.
  final ValueListenable<int> focusRequest;

  final TextAlign textAlign;

  @override
  State<ImageCaption> createState() => _ImageCaptionState();
}

class _ImageCaptionState extends State<ImageCaption> {
  late final TextEditingController _controller =
      TextEditingController(text: _storedCaption);
  final FocusNode _focusNode = FocusNode(debugLabel: 'image_caption');

  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
    widget.focusRequest.addListener(_onFocusRequested);
  }

  @override
  void didUpdateWidget(covariant ImageCaption oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusRequest != widget.focusRequest) {
      oldWidget.focusRequest.removeListener(_onFocusRequested);
      widget.focusRequest.addListener(_onFocusRequested);
    }
    // Adopt changes made elsewhere (undo, collaboration) unless the caret is
    // sitting in the field.
    if (!_focusNode.hasFocus && _controller.text != _storedCaption) {
      _controller.text = _storedCaption;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    // Losing the last keystrokes because the block rebuilt would be worse than
    // one extra transaction.
    _save();
    widget.focusRequest.removeListener(_onFocusRequested);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  String get _storedCaption =>
      widget.node.attributes[CustomImageBlockKeys.caption] as String? ?? '';

  void _onFocusRequested() {
    if (!widget.editable) {
      return;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _focusNode.requestFocus();
      }
    });
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _debounce?.cancel();
      _save();
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _onChanged(String _) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 500), _save);
    setState(() {});
  }

  void _save() {
    final text = _controller.text.trim();
    if (text == _storedCaption) {
      return;
    }
    final transaction = widget.editorState.transaction
      ..updateNode(widget.node, {
        // A null value drops the attribute, so an emptied caption leaves no
        // trace in the document.
        CustomImageBlockKeys.caption: text.isEmpty ? null : text,
      });
    unawaited(widget.editorState.apply(transaction));
  }

  @override
  Widget build(BuildContext context) {
    final palette = PremiumThemeExtension.maybeOf(context);
    final style = TextStyle(
      color: palette?.textSecondary ?? Theme.of(context).hintColor,
      fontSize: 14,
      height: 1.45,
    );

    if (!widget.editable) {
      final caption = _storedCaption;
      if (caption.isEmpty) {
        return const SizedBox.shrink();
      }
      return Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Text(caption, style: style, textAlign: widget.textAlign),
      );
    }

    return ValueListenableBuilder<bool>(
      valueListenable: widget.isHovering,
      builder: (context, isHovering, __) {
        final visible = _controller.text.trim().isNotEmpty ||
            isHovering ||
            _focusNode.hasFocus;
        return AnimatedSize(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: visible
              ? Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: _buildField(style, palette),
                )
              : const SizedBox(width: double.infinity, height: 0),
        );
      },
    );
  }

  Widget _buildField(TextStyle style, PremiumThemeExtension? palette) {
    // The editor's own key handlers sit above this field, and a Backspace on a
    // deltaless block deletes the whole embed. Dropping the document selection
    // while the field owns focus makes every command shortcut stand down.
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          widget.editorState.selection = null;
        }
      },
      child: TextField(
        controller: _controller,
        focusNode: _focusNode,
        onChanged: _onChanged,
        onEditingComplete: _save,
        textAlign: widget.textAlign,
        style: style,
        cursorColor: palette?.accent,
        cursorWidth: 1.5,
        maxLines: null,
        decoration: InputDecoration(
          isCollapsed: true,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
          filled: false,
          contentPadding: const EdgeInsets.symmetric(vertical: 2),
          hintText: 'Add a caption',
          hintStyle: style.copyWith(
            color: (palette?.textMuted ?? Theme.of(context).hintColor)
                .withValues(alpha: 0.7),
          ),
        ),
      ),
    );
  }
}
