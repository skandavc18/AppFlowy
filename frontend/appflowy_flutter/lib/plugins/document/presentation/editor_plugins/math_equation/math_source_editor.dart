import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/visual_block/visual_block.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_math_fork/flutter_math.dart';

import 'math_symbols.dart';

/// The LaTeX editor shared by the block, the fullscreen workspace and the
/// inline equation popover.
///
/// It is one quiet field with a strip of symbols under it — the equation it
/// produces is what is being looked at, so the tool that writes it stays out
/// of the way.
class MathSourceEditor extends StatefulWidget {
  const MathSourceEditor({
    super.key,
    required this.latex,
    required this.onChanged,
    this.editorState,
    this.onSubmit,
    this.onClose,
    this.undoController,
    this.autofocus = true,
    this.showSymbols = true,
    this.showLabel = true,
    this.expanded = false,
    this.hint,
  });

  final String latex;
  final ValueChanged<String> onChanged;

  /// The document this field sits inside, when it sits inside one.
  ///
  /// It has to be handed in: `context.read<EditorState?>()` is a different
  /// lookup from `Provider<EditorState>` and never finds it, which left the
  /// editor holding its selection and swallowing Backspace.
  final EditorState? editorState;

  /// Run when Enter is pressed without Shift.
  final ValueChanged<String>? onSubmit;

  /// Run on Escape.
  final VoidCallback? onClose;

  /// Lets a host drive the field's own undo stack from its own buttons.
  final UndoHistoryController? undoController;

  final bool autofocus;
  final bool showSymbols;
  final bool showLabel;

  /// Lets the field grow with its content instead of scrolling at five lines.
  final bool expanded;

  final String? hint;

  @override
  State<MathSourceEditor> createState() => _MathSourceEditorState();
}

class _MathSourceEditorState extends State<MathSourceEditor> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.latex);
  final FocusNode _focusNode = FocusNode(debugLabel: 'math_source');
  final ScrollController _symbolScroll = ScrollController();
  Timer? _debounce;
  int _group = 0;
  bool _focused = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void didUpdateWidget(covariant MathSourceEditor oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.latex != oldWidget.latex &&
        widget.latex != _controller.text &&
        _debounce == null) {
      _controller.text = widget.latex;
    }
  }

  @override
  void dispose() {
    _flush();
    _debounce?.cancel();
    _focusNode.removeListener(_onFocusChanged);
    _controller.dispose();
    _focusNode.dispose();
    _symbolScroll.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (mounted && _focused != _focusNode.hasFocus) {
      setState(() => _focused = _focusNode.hasFocus);
    }
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
    // Typesetting on every keystroke is what makes a maths editor feel heavy;
    // a pause this short is imperceptible and keeps typing fluid.
    _debounce = Timer(const Duration(milliseconds: 140), () {
      _debounce = null;
      widget.onChanged(value);
    });
  }

  void _insert(MathSymbol symbol) {
    final result = insertMathSymbol(
      _controller.text,
      _controller.selection,
      symbol.latex,
    );
    _controller.value = TextEditingValue(
      text: result.text,
      selection: TextSelection.collapsed(offset: result.caret),
    );
    _debounce?.cancel();
    _debounce = null;
    widget.onChanged(result.text);
    _focusNode.requestFocus();
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    final close = widget.onClose;
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        close == null) {
      return KeyEventResult.ignored;
    }
    _flush();
    close();
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final palette = VisualBlockPalette.of(context);
    final editorState = widget.editorState;

    final mono = TextStyle(
      fontFamily: 'RobotoMono',
      fontFamilyFallback: const ['JetBrains Mono', 'Consolas', 'monospace'],
      fontSize: 13,
      height: 1.55,
      color: palette.text,
    );

    final field = TextField(
      controller: _controller,
      focusNode: _focusNode,
      undoController: widget.undoController,
      autofocus: widget.autofocus,
      onChanged: _onChanged,
      maxLines: widget.expanded ? null : 5,
      minLines: 1,
      textInputAction: TextInputAction.newline,
      cursorColor: palette.accent,
      cursorWidth: 1.5,
      cursorRadius: const Radius.circular(1),
      style: mono,
      onSubmitted: widget.onSubmit,
      decoration: InputDecoration(
        isDense: true,
        filled: false,
        border: InputBorder.none,
        focusedBorder: InputBorder.none,
        enabledBorder: InputBorder.none,
        hoverColor: Colors.transparent,
        contentPadding: const EdgeInsets.fromLTRB(14, 11, 14, 11),
        hintText: widget.hint ?? 'E = mc^2',
        hintStyle: mono.copyWith(
          color: palette.textMuted.withValues(alpha: 0.55),
        ),
      ),
    );

    Widget body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (widget.showLabel) _label(palette),
        // One soft well rather than a bordered box: focus is a whisper of the
        // accent, not an outline around a form control.
        AnimatedContainer(
          duration: VisualBlockMetrics.hover,
          curve: VisualBlockMetrics.curve,
          decoration: BoxDecoration(
            color: _fieldFill(palette),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _focused
                  ? palette.accent.withValues(alpha: 0.30)
                  : palette.border.withValues(alpha: 0.16),
            ),
          ),
          child: field,
        ),
        if (widget.showSymbols) _symbols(palette),
      ],
    );

    body = Focus(
      onKeyEvent: _onKey,
      canRequestFocus: false,
      skipTraversal: true,
      child: body,
    );

    if (editorState == null) {
      return body;
    }
    // The field sits under the editor's own key handling, so it must clear the
    // selection while focused or Backspace deletes the block.
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          editorState.selection = null;
        }
      },
      child: body,
    );
  }

  Color _fieldFill(VisualBlockPalette palette) => palette.isDark
      ? palette.canvas.withValues(alpha: _focused ? 0.62 : 0.45)
      : palette.hover.withValues(alpha: _focused ? 0.62 : 0.40);

  Widget _label(VisualBlockPalette palette) => Padding(
        padding: const EdgeInsets.only(left: 3, bottom: 6),
        child: Text(
          LocaleKeys.diagrams_math_source.tr(),
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w500,
            letterSpacing: 0.5,
            color: palette.textMuted,
          ),
        ),
      );

  Widget _symbols(VisualBlockPalette palette) {
    final group = kMathSymbolGroups[_group];
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 26,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.zero,
              itemCount: kMathSymbolGroups.length,
              separatorBuilder: (_, __) => const SizedBox(width: 2),
              itemBuilder: (context, index) => _CategoryPill(
                label: kMathSymbolGroups[index].name,
                selected: index == _group,
                palette: palette,
                onTap: () {
                  setState(() => _group = index);
                  if (_symbolScroll.hasClients) {
                    _symbolScroll.jumpTo(0);
                  }
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 148),
              child: Scrollbar(
                controller: _symbolScroll,
                // Shown at all times: a palette that silently scrolls is a
                // palette whose later symbols nobody finds.
                thumbVisibility: true,
                thickness: 3,
                radius: const Radius.circular(3),
                child: SingleChildScrollView(
                  controller: _symbolScroll,
                  padding: const EdgeInsets.only(right: 8),
                  // No cross-fade between categories: two grids stacked during
                  // the switch would size to the taller of them and bounce the
                  // block. The height simply eases to the new one.
                  child: Wrap(
                    spacing: 2,
                    runSpacing: 2,
                    children: [
                      for (final symbol in group.symbols)
                        _SymbolChip(
                          symbol: symbol,
                          palette: palette,
                          onTap: () => _insert(symbol),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A category in the symbol strip: a word that takes a soft pill when chosen.
class _CategoryPill extends StatefulWidget {
  const _CategoryPill({
    required this.label,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VisualBlockPalette palette;
  final VoidCallback onTap;

  @override
  State<_CategoryPill> createState() => _CategoryPillState();
}

class _CategoryPillState extends State<_CategoryPill> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final Color fill;
    if (widget.selected) {
      fill = palette.accent.withValues(alpha: palette.isDark ? 0.18 : 0.10);
    } else if (_hovered) {
      fill = palette.hover.withValues(alpha: 0.7);
    } else {
      fill = palette.hoverBase;
    }
    return Semantics(
      button: true,
      selected: widget.selected,
      label: widget.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: VisualBlockMetrics.hover,
            curve: VisualBlockMetrics.curve,
            // No `alignment` here: an aligning Container expands to fill its
            // constraints, so inside a horizontal list each pill would claim
            // the whole width and none of them could be hit.
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Center(
              child: AnimatedDefaultTextStyle(
                duration: VisualBlockMetrics.hover,
                curve: VisualBlockMetrics.curve,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight:
                      widget.selected ? FontWeight.w600 : FontWeight.w500,
                  letterSpacing: 0.1,
                  color: widget.selected
                      ? palette.accent
                      : (_hovered ? palette.text : palette.textMuted),
                ),
                child: Text(widget.label),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One symbol: no border, no box — the glyph, and a wash under the pointer.
class _SymbolChip extends StatefulWidget {
  const _SymbolChip({
    required this.symbol,
    required this.palette,
    required this.onTap,
  });

  final MathSymbol symbol;
  final VisualBlockPalette palette;
  final VoidCallback onTap;

  @override
  State<_SymbolChip> createState() => _SymbolChipState();
}

class _SymbolChipState extends State<_SymbolChip> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final ink = _hovered ? palette.text : palette.textSecondary;
    return Tooltip(
      message: widget.symbol.latex.replaceAll(r'$0', '').trim(),
      waitDuration: const Duration(milliseconds: 550),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          behavior: HitTestBehavior.opaque,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 120),
            curve: Curves.easeOut,
            height: 30,
            constraints: const BoxConstraints(minWidth: 34),
            padding: const EdgeInsets.symmetric(horizontal: 7),
            decoration: BoxDecoration(
              color: _hovered
                  ? palette.hover.withValues(alpha: 0.85)
                  : palette.hoverBase,
              borderRadius: BorderRadius.circular(8),
            ),
            // Centred with a shrink-wrapping Center, never with the
            // container's own `alignment`: an aligning container fills its
            // constraints, which inside a Wrap gives every symbol its own row.
            child: Center(
              widthFactor: 1,
              child: widget.symbol.label != null
                  ? Text(
                      widget.symbol.label!,
                      style: TextStyle(fontSize: 15, color: ink),
                    )
                  : Math.tex(
                      widget.symbol.preview,
                      mathStyle: MathStyle.text,
                      textStyle: TextStyle(fontSize: 13.5, color: ink),
                      onErrorFallback: (_) => Text(
                        widget.symbol.preview,
                        style:
                            TextStyle(fontSize: 11, color: palette.textMuted),
                      ),
                    ),
            ),
          ),
        ),
      ),
    );
  }
}
