import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/find_and_replace_menu.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// Opens the find bar over a page.
///
/// The editor package's own service returns early unless a selection rectangle
/// is already on screen, so Ctrl+F did nothing at all on a page nobody had
/// clicked into yet. Searching a page should never depend on where the caret
/// happens to be.
abstract final class DocumentFindMenu {
  static OverlayEntry? _entry;
  static EditorState? _editorState;

  static const double _topOffset = 52;
  static const double _rightOffset = 40;

  static bool get isOpen => _entry != null;

  static void show(
    BuildContext context,
    EditorState editorState, {
    bool replace = false,
  }) {
    dismiss();
    final overlay = Overlay.maybeOf(context, rootOverlay: true);
    if (overlay == null) {
      return;
    }
    final entry = OverlayEntry(
      builder: (_) => Positioned(
        top: _topOffset,
        right: _rightOffset,
        child: Material(
          color: Colors.transparent,
          child: FindAndReplaceMenuWidget(
            editorState: editorState,
            showReplaceMenu: replace,
            onDismiss: dismiss,
          ),
        ),
      ),
    );
    _entry = entry;
    _editorState = editorState;
    editorState.onDispose.addListener(dismiss);
    overlay.insert(entry);
  }

  static void dismiss() {
    final entry = _entry;
    _entry = null;
    _editorState?.onDispose.removeListener(dismiss);
    _editorState = null;
    if (entry != null && entry.mounted) {
      entry.remove();
    }
  }
}
