import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'mermaid_samples.dart';

/// The source pane of a Mermaid block.
///
/// It is deliberately secondary: a small monospaced sheet under the drawing
/// that only appears when somebody asks for it, so viewing a page shows the
/// diagram rather than the text that made it.
class MermaidSourceEditor extends StatefulWidget {
  const MermaidSourceEditor({
    super.key,
    required this.source,
    required this.onChanged,
    required this.onClose,
    this.onInsertSample,
    this.error,
    this.expanded = false,
  });

  final String source;
  final ValueChanged<String> onChanged;
  final VoidCallback onClose;
  final ValueChanged<String>? onInsertSample;

  /// A sentence naming what could not be read, shown under the field.
  final String? error;

  /// Fills its box rather than sitting at a fixed height — used in fullscreen.
  final bool expanded;

  @override
  State<MermaidSourceEditor> createState() => _MermaidSourceEditorState();
}

class _MermaidSourceEditorState extends State<MermaidSourceEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.source);
  final FocusNode _focusNode = FocusNode(debugLabel: 'mermaid_source');
  Timer? _debounce;

  @override
  void didUpdateWidget(covariant MermaidSourceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Adopt a source changed elsewhere — a sample, an undo — but never while
    // the person is mid-keystroke, or the caret jumps.
    if (widget.source != oldWidget.source &&
        widget.source != _controller.text &&
        _debounce == null) {
      _controller.text = widget.source;
    }
  }

  @override
  void dispose() {
    _flush();
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _flush() {
    if (_debounce?.isActive ?? false) {
      _debounce!.cancel();
      _debounce = null;
      widget.onChanged(_controller.text);
    }
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    // Rendering while somebody types is cheap but not free; a short pause
    // keeps a long diagram from being laid out on every keystroke.
    _debounce = Timer(const Duration(milliseconds: 320), () {
      _debounce = null;
      widget.onChanged(value);
    });
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    final editorState = context.read<EditorState>();

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      onChanged: _onChanged,
      maxLines: null,
      expands: widget.expanded,
      cursorColor: palette.accent,
      cursorWidth: 1.6,
      style: TextStyle(
        fontFamily: 'RobotoMono',
        fontFamilyFallback: const ['JetBrains Mono', 'Consolas', 'monospace'],
        fontSize: 12.5,
        height: 1.55,
        color: palette.text,
      ),
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        hoverColor: Colors.transparent,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        hintText: LocaleKeys.diagrams_mermaid_sourcePlaceholder.tr(),
        hintStyle: TextStyle(
          fontFamily: 'RobotoMono',
          fontFamilyFallback: const ['JetBrains Mono', 'Consolas', 'monospace'],
          fontSize: 12.5,
          height: 1.55,
          color: palette.textMuted.withValues(alpha: 0.7),
        ),
      ),
    );

    return
        // An embedded field lives under the editor's own key handling, so it
        // must clear the selection while it holds focus or Backspace deletes
        // the whole block instead of a character.
        FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          editorState.selection = null;
        }
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(10, 0, 10, 10),
        decoration: BoxDecoration(
          color: palette.isDark
              ? palette.canvas.withValues(alpha: 0.55)
              : palette.hover.withValues(alpha: 0.55),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: widget.expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            _header(palette),
            if (widget.expanded)
              Expanded(child: field)
            else
              ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 190),
                child: SingleChildScrollView(child: field),
              ),
            if (widget.error != null) _error(palette),
            if (widget.source.trim().isEmpty && widget.onInsertSample != null)
              _samples(palette),
          ],
        ),
      ),
    );
  }

  Widget _header(VisualBlockPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 6, 2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                LocaleKeys.diagrams_mermaid_editSource.tr(),
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.3,
                  color: palette.textMuted,
                ),
              ),
            ),
            VisualBlockButton(
              icon: Icons.close_rounded,
              tooltip: LocaleKeys.button_close.tr(),
              palette: palette,
              size: 22,
              onTap: () {
                _flush();
                widget.onClose();
              },
            ),
          ],
        ),
      );

  Widget _error(VisualBlockPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 13,
              color: palette.textMuted,
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                widget.error!,
                style: TextStyle(
                  fontSize: 11.5,
                  height: 1.35,
                  color: palette.textMuted,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _samples(VisualBlockPalette palette) {
    final chips = Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final sample in kMermaidSamples)
          _SampleChip(
            sample: sample,
            palette: palette,
            onTap: () {
              _controller.text = sample.source;
              _debounce?.cancel();
              _debounce = null;
              widget.onInsertSample!(sample.source);
            },
          ),
      ],
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 10),
      // In the block the pane has a fixed height, so the starters scroll
      // rather than push the writing area out of the card.
      child: widget.expanded
          ? ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 92),
              child: SingleChildScrollView(child: chips),
            )
          : chips,
    );
  }
}

class _SampleChip extends StatefulWidget {
  const _SampleChip({
    required this.sample,
    required this.palette,
    required this.onTap,
  });

  final MermaidSample sample;
  final VisualBlockPalette palette;
  final VoidCallback onTap;

  @override
  State<_SampleChip> createState() => _SampleChipState();
}

class _SampleChipState extends State<_SampleChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: VisualBlockMetrics.hover,
          curve: VisualBlockMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          decoration: BoxDecoration(
            color: _hovered ? palette.accentSoft : palette.raised,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.sample.icon,
                size: 13,
                color: _hovered ? palette.accent : palette.textSecondary,
              ),
              const SizedBox(width: 6),
              Text(
                widget.sample.label,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w500,
                  color: _hovered ? palette.text : palette.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
