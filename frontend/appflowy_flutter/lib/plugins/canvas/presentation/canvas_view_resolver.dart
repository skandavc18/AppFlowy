import 'dart:async';

import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flutter/foundation.dart';

/// Reads the workspace objects a canvas points at, once each.
///
/// A canvas of forty page cards would otherwise ask the backend for the same
/// forty views on every rebuild — and a rebuild happens on every pointer move
/// while something is being dragged.
class CanvasViewResolver extends ChangeNotifier {
  CanvasViewResolver();

  final Map<String, ViewPB> _views = <String, ViewPB>{};
  final Set<String> _missing = <String>{};

  /// The reads already in flight, so a second card asking for the same object
  /// joins that request rather than starting another.
  final Set<String> _reading = <String>{};
  bool _disposed = false;

  /// The view, if it has already been read. Null means "not yet" — ask with
  /// [request] and rebuild when this object notifies.
  ViewPB? peek(String viewId) => _views[viewId];

  /// Whether the object a card points at is known to be gone, as opposed to
  /// merely not read yet. A card must not say "this is no longer here" while
  /// it is still looking.
  bool isMissing(String viewId) => _missing.contains(viewId);

  void request(String viewId) {
    if (viewId.isEmpty ||
        _views.containsKey(viewId) ||
        _missing.contains(viewId) ||
        !_reading.add(viewId)) {
      return;
    }
    unawaited(_read(viewId));
  }

  Future<void> _read(String viewId) async {
    final result = await ViewBackendService.getView(viewId);
    _reading.remove(viewId);
    if (_disposed) {
      return;
    }
    result.fold(
      (view) => _views[viewId] = view,
      (_) => _missing.add(viewId),
    );
    notifyListeners();
  }

  /// Read again — after a rename, or after the card was pointed somewhere else.
  void forget(String viewId) {
    if (_views.remove(viewId) != null || _missing.remove(viewId)) {
      notifyListeners();
    }
  }

  void adopt(ViewPB view) {
    _views[view.id] = view;
    _missing.remove(view.id);
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
