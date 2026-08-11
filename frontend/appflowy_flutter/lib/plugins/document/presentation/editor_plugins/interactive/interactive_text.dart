import 'dart:async';

import 'package:flutter/material.dart';

import 'interactive_style.dart';

/// A text field that belongs to a block rather than to a form.
///
/// It writes back on a timer instead of on every keystroke, because a
/// transaction per character rebuilds the whole page; it flushes when it loses
/// focus and when it is taken down, so nothing typed is ever lost.
class InteractiveEditableText extends StatefulWidget {
  const InteractiveEditableText({
    super.key,
    required this.value,
    required this.onChanged,
    this.hint = '',
    this.style,
    this.hintStyle,
    this.maxLines = 1,
    this.minLines,
    this.enabled = true,
    this.autofocus = false,
    this.textAlign = TextAlign.start,
    this.debounce = const Duration(milliseconds: 400),
    this.onSubmitted,
    this.onFocusChanged,
    this.onLiveChanged,
    this.keyboardType,
    this.palette,
    this.controller,
    this.focusNode,
  });

  final String value;

  /// Called once typing has settled, and again on blur and teardown.
  final ValueChanged<String> onChanged;

  /// Called on every keystroke, for anything that must follow the text live.
  final ValueChanged<String>? onLiveChanged;

  final String hint;
  final TextStyle? style;
  final TextStyle? hintStyle;
  final int? maxLines;
  final int? minLines;
  final bool enabled;
  final bool autofocus;
  final TextAlign textAlign;
  final Duration debounce;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<bool>? onFocusChanged;
  final TextInputType? keyboardType;
  final InteractivePalette? palette;
  final TextEditingController? controller;
  final FocusNode? focusNode;

  @override
  State<InteractiveEditableText> createState() =>
      _InteractiveEditableTextState();
}

class _InteractiveEditableTextState extends State<InteractiveEditableText> {
  late final TextEditingController _controller =
      widget.controller ?? TextEditingController(text: widget.value);
  late final FocusNode _focus = widget.focusNode ?? FocusNode();
  Timer? _commit;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(InteractiveEditableText oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Never adopt an attribute while an edit is still on its way to the
    // document, or a rebuild lands mid-write and puts the old text back.
    if (!_dirty && !_focus.hasFocus && widget.value != _controller.text) {
      _controller.text = widget.value;
    }
  }

  @override
  void dispose() {
    _focus.removeListener(_onFocusChanged);
    _flush();
    if (widget.controller == null) {
      _controller.dispose();
    }
    if (widget.focusNode == null) {
      _focus.dispose();
    }
    super.dispose();
  }

  void _onFocusChanged() {
    widget.onFocusChanged?.call(_focus.hasFocus);
    if (!_focus.hasFocus) {
      _flush();
    }
  }

  void _flush() {
    _commit?.cancel();
    _commit = null;
    if (_dirty) {
      _dirty = false;
      widget.onChanged(_controller.text);
    }
  }

  void _onTyped(String value) {
    _dirty = true;
    widget.onLiveChanged?.call(value);
    _commit?.cancel();
    _commit = Timer(widget.debounce, () {
      _commit = null;
      if (_dirty) {
        _dirty = false;
        widget.onChanged(_controller.text);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette ?? interactivePaletteOf(context);
    final style = widget.style ?? InteractiveType.body(palette);
    return TextField(
      controller: _controller,
      focusNode: _focus,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      maxLines: widget.maxLines,
      minLines: widget.minLines,
      textAlign: widget.textAlign,
      keyboardType: widget.keyboardType ??
          (widget.maxLines == 1 ? null : TextInputType.multiline),
      style: style,
      cursorColor: palette.accent,
      cursorWidth: 1.6,
      cursorRadius: const Radius.circular(1),
      onChanged: _onTyped,
      onSubmitted: (value) {
        _flush();
        widget.onSubmitted?.call(value);
      },
      decoration: InputDecoration(
        isCollapsed: true,
        border: InputBorder.none,
        enabledBorder: InputBorder.none,
        focusedBorder: InputBorder.none,
        // A filled field blends Material's hover colour over the fill, which
        // greys the whole control under the pointer.
        filled: false,
        hoverColor: Colors.transparent,
        contentPadding: EdgeInsets.zero,
        hintText: widget.hint,
        hintStyle: widget.hintStyle ??
            style.copyWith(color: palette.textMuted.withValues(alpha: 0.8)),
      ),
    );
  }
}
