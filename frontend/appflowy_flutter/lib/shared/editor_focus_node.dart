import 'dart:async';

import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/widgets.dart';

/// The focus node an AppFlowy editor is built with.
///
/// When a menu that kept an editor focused closes, appflowy_editor has every
/// mounted editor ask for the focus back, and the last one to ask wins: an AI
/// chat answer, a block on a dashboard or canvas, or the page behind an open
/// dialog. Keys then go there while typing still reaches the page through its
/// open input connection, so Backspace, Delete, the arrows and Ctrl+V seem to
/// stop working, or a paste lands somewhere else entirely.
///
/// With this node only the editor that last had the focus takes it back, and
/// never from under a dialog.
class EditorFocusNode extends FocusNode {
  EditorFocusNode({super.debugLabel}) {
    _listenForRestoration();
    addListener(_onFocusChange);
  }

  static EditorFocusNode? _lastFocused;
  static bool _listening = false;
  static bool _restoring = false;

  /// Registered before the editors' own listeners, so that while they answer a
  /// menu closing, the answer is known to be a restoration.
  static void _listenForRestoration() {
    if (_listening) {
      return;
    }
    _listening = true;
    keepEditorFocusNotifier.addListener(() {
      if (keepEditorFocusNotifier.shouldKeepFocus || _restoring) {
        return;
      }
      _restoring = true;
      scheduleMicrotask(() => _restoring = false);
    });
  }

  void _onFocusChange() {
    if (hasFocus) {
      _lastFocused = this;
    }
  }

  @override
  void requestFocus([FocusNode? node]) {
    if (_restoring && node == null && !_mayTakeFocusBack()) {
      return;
    }
    super.requestFocus(node);
  }

  bool _mayTakeFocusBack() {
    if (!identical(_lastFocused, this)) {
      return false;
    }
    final context = this.context;
    return context != null && context.mounted && _isOnTopmostRoute(context);
  }

  static bool _isOnTopmostRoute(BuildContext context) {
    BuildContext? current = context;
    while (current != null) {
      final route = ModalRoute.of(current);
      if (route == null) {
        return true;
      }
      if (!route.isCurrent) {
        return false;
      }
      // A route inside a nested navigator is only on top if its navigator is.
      current = route.navigator?.context;
    }
    return true;
  }

  @override
  void dispose() {
    if (identical(_lastFocused, this)) {
      _lastFocused = null;
    }
    removeListener(_onFocusChange);
    super.dispose();
  }
}
