import 'dart:collection';

import 'package:flutter/foundation.dart';

class WorkspaceExplorerSelection extends ChangeNotifier {
  final LinkedHashSet<String> _ids = LinkedHashSet();
  String? _anchorId;

  Set<String> get ids => Set.unmodifiable(_ids);
  String? get anchorId => _anchorId;
  bool get isEmpty => _ids.isEmpty;
  bool get isNotEmpty => _ids.isNotEmpty;
  int get length => _ids.length;

  bool contains(String id) => _ids.contains(id);

  void selectOnly(String id) {
    if (_ids.length == 1 && _ids.contains(id)) {
      _anchorId = id;
      return;
    }
    _ids
      ..clear()
      ..add(id);
    _anchorId = id;
    notifyListeners();
  }

  void toggle(String id) {
    if (!_ids.remove(id)) {
      _ids.add(id);
    }
    _anchorId = id;
    notifyListeners();
  }

  void selectRange({
    required String id,
    required List<String> visibleIds,
  }) {
    final anchorIndex = _anchorId == null ? -1 : visibleIds.indexOf(_anchorId!);
    final targetIndex = visibleIds.indexOf(id);
    if (anchorIndex == -1 || targetIndex == -1) {
      selectOnly(id);
      return;
    }
    final start = anchorIndex < targetIndex ? anchorIndex : targetIndex;
    final end = anchorIndex > targetIndex ? anchorIndex : targetIndex;
    _ids
      ..clear()
      ..addAll(visibleIds.sublist(start, end + 1));
    notifyListeners();
  }

  void selectAll(Iterable<String> ids) {
    _ids
      ..clear()
      ..addAll(ids);
    _anchorId = _ids.firstOrNull;
    notifyListeners();
  }

  void retain(Iterable<String> ids) {
    final allowed = ids.toSet();
    final previousLength = _ids.length;
    _ids.removeWhere((id) => !allowed.contains(id));
    if (_anchorId != null && !_ids.contains(_anchorId)) {
      _anchorId = _ids.firstOrNull;
    }
    if (_ids.length != previousLength) {
      notifyListeners();
    }
  }

  void clear() {
    if (_ids.isEmpty) {
      return;
    }
    _ids.clear();
    _anchorId = null;
    notifyListeners();
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
