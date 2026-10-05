import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Whether a text field — a card's text, a block's search box, a form field —
/// owns the keyboard right now.
bool textFieldHasFocus() {
  final focus = FocusManager.instance.primaryFocus;
  final context = focus?.context;
  if (focus == null || context == null || !context.mounted) {
    return false;
  }
  final editable = context.findAncestorStateOfType<EditableTextState>();
  return editable != null && editable.widget.focusNode == focus;
}

/// [CallbackShortcuts] that leaves a focused text field its keys.
///
/// A board binds Backspace, Delete, the arrows and Ctrl+A/C/V/Z for itself,
/// and a text field anywhere on it — in a card, in an embedded block — needs
/// those very keys. While a text field has the keyboard only the bindings in
/// [whileTyping] still apply.
class CallbackShortcutsUnlessTyping extends StatelessWidget {
  const CallbackShortcutsUnlessTyping({
    super.key,
    required this.bindings,
    this.whileTyping = const {},
    required this.child,
  });

  final Map<ShortcutActivator, VoidCallback> bindings;
  final Set<ShortcutActivator> whileTyping;
  final Widget child;

  KeyEventResult _onKeyEvent(FocusNode node, KeyEvent event) {
    final typing = textFieldHasFocus();
    for (final binding in bindings.entries) {
      if (typing && !whileTyping.contains(binding.key)) {
        continue;
      }
      if (binding.key.accepts(event, HardwareKeyboard.instance)) {
        binding.value();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) => Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onKeyEvent,
        child: child,
      );
}
