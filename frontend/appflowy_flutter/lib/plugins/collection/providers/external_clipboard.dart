// What was copied or cut out of a service's folder.
//
// Held in one place rather than on a widget, because copying in one folder and
// pasting in another means the two never exist at the same time.

import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:flutter/foundation.dart';

@immutable
class ExternalClipboardEntry {
  const ExternalClipboardEntry({
    required this.node,
    required this.connectionId,
    required this.cut,
  });

  final ProviderNode node;

  /// The account it came out of; pasting into another one has to copy the
  /// bytes rather than ask the service to move something it cannot see.
  final String connectionId;

  final bool cut;
}

/// The one thing waiting to be pasted.
class ExternalClipboard extends ChangeNotifier {
  ExternalClipboard._();

  static final ExternalClipboard instance = ExternalClipboard._();

  ExternalClipboardEntry? _entry;

  ExternalClipboardEntry? get entry => _entry;
  bool get isEmpty => _entry == null;

  void copy(ProviderNode node, {required String connectionId}) =>
      _hold(node, connectionId: connectionId, cut: false);

  void cut(ProviderNode node, {required String connectionId}) =>
      _hold(node, connectionId: connectionId, cut: true);

  void clear() {
    _entry = null;
    notifyListeners();
  }

  void _hold(
    ProviderNode node, {
    required String connectionId,
    required bool cut,
  }) {
    _entry = ExternalClipboardEntry(
      node: node,
      connectionId: connectionId,
      cut: cut,
    );
    notifyListeners();
  }
}
