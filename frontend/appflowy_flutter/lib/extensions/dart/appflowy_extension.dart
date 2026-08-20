import 'dart:async';

import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';

/// Everything one extension started, so turning it off really turns it off.
///
/// ⚠️ Teardown is the whole reason this exists. A registry entry, a timer or a
/// listener that outlives its extension is a leak that only shows up as
/// something mysteriously still happening after it was switched off.
class ExtensionScope {
  ExtensionScope(this.extensionId);

  final String extensionId;
  final List<void Function()> _undo = [];
  bool _closed = false;

  bool get isClosed => _closed;

  /// Remembers how to undo something this extension did.
  void onDispose(void Function() undo) {
    if (_closed) {
      undo();
      return;
    }
    _undo.add(undo);
  }

  void addTimer(Timer timer) => onDispose(timer.cancel);

  void addListenable(Listenable listenable, VoidCallback listener) {
    listenable.addListener(listener);
    onDispose(() => listenable.removeListener(listener));
  }

  void addSubscription(StreamSubscription<Object?> subscription) =>
      onDispose(() => unawaited(subscription.cancel()));

  /// Runs every undo, newest first, and keeps going past a failure — one bad
  /// teardown must not strand the rest.
  void close() {
    if (_closed) {
      return;
    }
    _closed = true;
    for (final undo in _undo.reversed) {
      try {
        undo();
      } on Object catch (error) {
        Log.warn('Extension $extensionId failed to clean up: $error');
      }
    }
    _undo.clear();
  }
}

/// What a Dart extension says about itself.
@immutable
class DartExtensionInfo {
  const DartExtensionInfo({
    required this.id,
    required this.name,
    this.description = '',
    this.version = '1.0.0',
  });

  final String id;
  final String name;
  final String description;
  final String version;
}

/// An extension written in Dart and compiled in.
///
/// This is the tier with no ceiling: it can draw any Flutter widget, reach any
/// service directly and register a whole theme. The cost is that adding one
/// means rebuilding — which is why actions and islands exist for everything
/// that should not need a rebuild.
abstract class AppFlowyExtension {
  DartExtensionInfo get info;

  /// Register everything this extension offers against [context]. Anything
  /// registered through the context is undone automatically on deactivate.
  Future<void> activate(ExtensionContext context);

  /// Only for work the scope cannot undo on its own.
  Future<void> deactivate() async {}
}

/// Forward declaration so the contract can name it; the real one lives in
/// `extension_context.dart`.
abstract class ExtensionContext {
  DartExtensionInfo get info;

  ExtensionScope get scope;
}
