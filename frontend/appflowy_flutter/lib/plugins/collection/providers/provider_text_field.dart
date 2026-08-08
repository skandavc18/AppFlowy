import 'dart:async';
import 'dart:io';

import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A text field that keeps its editing keys.
///
/// AppFlowy has several ancestors that claim keys before a field sees them —
/// the editor's keyboard service most of all. Typing still arrives, because
/// that comes through the input connection rather than the shortcut tree, which
/// is what makes the failure look selective: letters appear, but Backspace,
/// Ctrl+V and the arrows do nothing.
///
/// `Shortcuts` resolves from the focused node upwards and the FIRST match wins,
/// so restating the editing keys immediately around the field beats anything
/// above it. Nothing is handled twice: only one `Shortcuts` ever handles a
/// given event.
class ProviderTextField extends StatefulWidget {
  const ProviderTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.palette,
    this.hint = '',
    this.obscure = false,
    this.autofocus = false,
    this.showPasteButton = false,
    this.onSubmitted,
  });

  final String label;
  final TextEditingController controller;
  final FolderExplorerPalette palette;
  final String hint;
  final bool obscure;
  final bool autofocus;

  /// Offers a one-click paste. A client secret or an access token is long,
  /// always arrives from the clipboard, and is worth not depending on a key
  /// binding for at all.
  final bool showPasteButton;

  final ValueChanged<String>? onSubmitted;

  @override
  State<ProviderTextField> createState() => _ProviderTextFieldState();
}

class _ProviderTextFieldState extends State<ProviderTextField> {
  final FocusNode focusNode = FocusNode();
  bool revealed = false;

  @override
  void dispose() {
    focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final obscured = widget.obscure && !revealed;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          widget.label,
          style: TextStyle(
            color: palette.textSecondary,
            fontSize: 11.5,
            fontVariations: const [FontVariation.weight(580)],
          ),
        ),
        const SizedBox(height: 5),
        Row(
          children: [
            Expanded(
              child: Shortcuts(
                shortcuts: textEntryShortcuts,
                child: TextField(
                  controller: widget.controller,
                  focusNode: focusNode,
                  autofocus: widget.autofocus,
                  obscureText: obscured,
                  autocorrect: false,
                  enableSuggestions: false,
                  enableInteractiveSelection: true,
                  onSubmitted: widget.onSubmitted,
                  style: TextStyle(color: palette.textPrimary, fontSize: 13),
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: widget.hint,
                    hintStyle:
                        TextStyle(color: palette.textMuted, fontSize: 13),
                    filled: true,
                    fillColor: palette.background,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 11,
                    ),
                    suffixIcon: widget.obscure
                        ? _IconButton(
                            icon: revealed
                                ? Icons.visibility_off_rounded
                                : Icons.visibility_rounded,
                            palette: palette,
                            onPressed: () =>
                                setState(() => revealed = !revealed),
                          )
                        : null,
                    suffixIconConstraints:
                        const BoxConstraints(minWidth: 34, minHeight: 30),
                    border: _border(palette),
                    enabledBorder: _border(palette),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(9),
                      borderSide: BorderSide(color: palette.border, width: 1.2),
                    ),
                  ),
                ),
              ),
            ),
            if (widget.showPasteButton) ...[
              const SizedBox(width: 6),
              _IconButton(
                icon: Icons.content_paste_rounded,
                palette: palette,
                onPressed: _paste,
              ),
            ],
          ],
        ),
      ],
    );
  }

  static OutlineInputBorder _border(FolderExplorerPalette palette) =>
      OutlineInputBorder(
        borderRadius: BorderRadius.circular(9),
        borderSide: BorderSide.none,
      );

  /// Replaces the selection with the clipboard, or appends when the field has
  /// never been focused and so has no caret of its own.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) {
      return;
    }

    final controller = widget.controller;
    final selection = controller.selection;
    final value = controller.text;
    // A token pasted from a console often carries a trailing newline; a single
    // line field must not silently keep it.
    final cleaned = text.trim();

    if (selection.start < 0 || selection.end < 0) {
      controller.text = value + cleaned;
    } else {
      controller.value = controller.value.replaced(selection, cleaned);
    }
    focusNode.requestFocus();
  }
}

/// The editing keys a field must keep, whatever claims them further up.
///
/// Both Control and Meta are registered rather than branching on the platform:
/// a binding for a modifier the platform never sends simply never fires.
final Map<ShortcutActivator, Intent> textEntryShortcuts = {
  const SingleActivator(LogicalKeyboardKey.backspace):
      const DeleteCharacterIntent(forward: false),
  const SingleActivator(LogicalKeyboardKey.delete):
      const DeleteCharacterIntent(forward: true),
  const SingleActivator(LogicalKeyboardKey.backspace, control: true):
      const DeleteToNextWordBoundaryIntent(forward: false),
  const SingleActivator(LogicalKeyboardKey.backspace, alt: true):
      const DeleteToNextWordBoundaryIntent(forward: false),
  const SingleActivator(LogicalKeyboardKey.delete, control: true):
      const DeleteToNextWordBoundaryIntent(forward: true),
  const SingleActivator(LogicalKeyboardKey.arrowLeft):
      const ExtendSelectionByCharacterIntent(
    forward: false,
    collapseSelection: true,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowRight):
      const ExtendSelectionByCharacterIntent(
    forward: true,
    collapseSelection: true,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowLeft, shift: true):
      const ExtendSelectionByCharacterIntent(
    forward: false,
    collapseSelection: false,
  ),
  const SingleActivator(LogicalKeyboardKey.arrowRight, shift: true):
      const ExtendSelectionByCharacterIntent(
    forward: true,
    collapseSelection: false,
  ),
  const SingleActivator(LogicalKeyboardKey.home):
      const ExtendSelectionToLineBreakIntent(
    forward: false,
    collapseSelection: true,
  ),
  const SingleActivator(LogicalKeyboardKey.end):
      const ExtendSelectionToLineBreakIntent(
    forward: true,
    collapseSelection: true,
  ),
  const SingleActivator(LogicalKeyboardKey.home, shift: true):
      const ExtendSelectionToLineBreakIntent(
    forward: false,
    collapseSelection: false,
  ),
  const SingleActivator(LogicalKeyboardKey.end, shift: true):
      const ExtendSelectionToLineBreakIntent(
    forward: true,
    collapseSelection: false,
  ),
  const SingleActivator(LogicalKeyboardKey.keyA, control: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyA, meta: true):
      const SelectAllTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyC, control: true):
      CopySelectionTextIntent.copy,
  const SingleActivator(LogicalKeyboardKey.keyC, meta: true):
      CopySelectionTextIntent.copy,
  const SingleActivator(LogicalKeyboardKey.keyX, control: true):
      const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyX, meta: true):
      const CopySelectionTextIntent.cut(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyV, control: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyV, meta: true):
      const PasteTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyZ, control: true):
      const UndoTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true):
      const UndoTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyZ, control: true, shift: true):
      const RedoTextIntent(SelectionChangedCause.keyboard),
  const SingleActivator(LogicalKeyboardKey.keyZ, meta: true, shift: true):
      const RedoTextIntent(SelectionChangedCause.keyboard),
};

/// Restores the editing keys for a field this widget does not own — a search
/// box, a filter, anything already written as a plain [TextField].
class TextEntryShortcuts extends StatelessWidget {
  const TextEntryShortcuts({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Shortcuts(shortcuts: textEntryShortcuts, child: child);
}

class _IconButton extends StatefulWidget {
  const _IconButton({
    required this.icon,
    required this.palette,
    required this.onPressed,
  });

  final IconData icon;
  final FolderExplorerPalette palette;
  final VoidCallback onPressed;

  @override
  State<_IconButton> createState() => _IconButtonState();
}

class _IconButtonState extends State<_IconButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            width: 30,
            height: 30,
            margin: const EdgeInsets.all(2),
            decoration: BoxDecoration(
              color: widget.palette.hover.withValues(alpha: hovered ? 1 : 0),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              widget.icon,
              size: 15,
              color: widget.palette.textSecondary,
            ),
          ),
        ),
      );
}

/// Whether this platform uses Command rather than Control. Kept here so the
/// dialogs can label a shortcut correctly without importing `dart:io`.
bool get usesCommandKey => Platform.isMacOS;
