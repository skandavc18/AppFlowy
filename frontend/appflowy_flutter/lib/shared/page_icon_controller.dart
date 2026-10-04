import 'dart:async';

import 'package:appflowy/shared/page_icon_size.dart';
import 'package:appflowy/workspace/application/view/view_listener.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

/// The normal ViewBackendService boundary, injectable without changing FFI.
class PageIconBackendService {
  const PageIconBackendService();

  // Shared by all mounted/reopened headers. Disposing a controller must not
  // unlock an already-dispatched write (including A -> B -> A rebinding).
  static final _tails = <String, Future<void>>{};
  static final _writes = <String, List<_PageIconWrite>>{};

  /// Shared serialization for metadata-only page identity edits. The operation
  /// must re-read the view inside this queue and merge only its owned fields.
  /// Installing the tail synchronously also orders re-entrant UI listeners.
  static Future<T> serializeMetadata<T>(
    String viewId,
    Future<T> Function() operation,
  ) {
    final previous = _tails[viewId] ?? Future<void>.value();
    final release = Completer<void>();
    final tail = release.future;
    _tails[viewId] = tail;
    return () async {
      try {
        await previous;
        return await operation();
      } finally {
        if (identical(_tails[viewId], tail)) {
          unawaited(_tails.remove(viewId));
        }
        release.complete();
      }
    }();
  }

  bool isPendingSize(String viewId, double? size) =>
      _writes[viewId]?.any((write) => write.size == size) ?? false;

  Future<FlowyResult<ViewPB, FlowyError>> readView(String viewId) =>
      ViewBackendService.getView(viewId);

  Future<FlowyResult<ViewPB, FlowyError>> updateView({
    required String viewId,
    required String extra,
  }) =>
      ViewBackendService.updateView(viewId: viewId, extra: extra);

  VoidCallback listen({
    required String viewId,
    required ValueChanged<ViewPB> onView,
    required VoidCallback onUnavailable,
  }) {
    final listener = ViewListener(viewId: viewId)
      ..start(
        onViewUpdated: onView,
        onViewDeleted: (_) => onUnavailable(),
        onViewMoveToTrash: (_) => onUnavailable(),
      );
    return () => unawaited(listener.stop());
  }

  Future<FlowyResult<void, FlowyError>> save({
    required ViewPB view,
    required double? size,
    required bool Function() isCurrent,
    required bool Function(ViewPB) isSameTarget,
  }) {
    // Install the tail BEFORE any caller can notify synchronous listeners.
    final write = _PageIconWrite(size);
    (_writes[view.id] ??= []).add(write);
    return serializeMetadata(view.id, () async {
      try {
        if (view.id.isEmpty || !isCurrent()) return _unavailable();
        final result = await readView(view.id);
        if (!isCurrent()) return _unavailable();
        final fresh = result.fold<ViewPB?>((view) => view, (_) => null);
        if (fresh == null ||
            fresh.id != view.id ||
            fresh.isLocked ||
            fresh.layout != view.layout ||
            !isSameTarget(fresh)) {
          return _unavailable();
        }
        final extra = IconSize.merge(fresh.extra, size);
        if (!isCurrent()) return _unavailable();
        final saved = await updateView(viewId: view.id, extra: extra);
        return saved.fold(
          // FolderEventUpdateView may return an EMPTY success ACK. Its fields
          // are not authority to roll back the current title/icon/cover.
          (ack) => ack.id.isEmpty || ack.id == view.id
              ? FlowyResult<void, FlowyError>.success(null)
              : _unavailable(),
          (error) => FlowyResult<void, FlowyError>.failure(error),
        );
      } catch (_) {
        // A thrown write has an unknown outcome. Do not retry automatically or
        // attempt an inverse write which could overwrite someone else's edit.
        return FlowyResult<void, FlowyError>.failure(
          FlowyError(msg: 'Unable to save this page icon size. Try again.'),
        );
      } finally {
        final writes = _writes[view.id];
        writes?.remove(write);
        if (writes?.isEmpty ?? false) _writes.remove(view.id);
      }
    });
  }

  static FlowyResult<void, FlowyError> _unavailable() => FlowyResult.failure(
        FlowyError(msg: 'This page is no longer available for resizing.'),
      );
}

/// Transient resizing lives here, never in a document/database controller.
/// Each release/key action queues one metadata write; pointer moves queue none.
class PageIconController extends ChangeNotifier {
  PageIconController({
    required ViewPB view,
    required Object binding,
    required bool editable,
    required this.canEdit,
    required this.onSaved,
    required this.isSameTarget,
    required double defaultSize,
    this.backend = const PageIconBackendService(),
  })  : _view = ViewPB.fromBuffer(view.writeToBuffer()),
        _hostExtra = view.extra,
        _hostLocked = view.isLocked,
        _binding = binding,
        _editable = editable,
        _defaultSize = defaultSize,
        _observedSize = IconSize.decode(view.extra),
        _savedSize = IconSize.decode(view.extra) {
    _listen();
  }

  final PageIconBackendService backend;
  final bool Function() canEdit;
  final ValueChanged<double?> onSaved;
  final bool Function(ViewPB) isSameTarget;
  ViewPB _view;
  String _hostExtra;
  bool _hostLocked;
  Object _binding;
  bool _editable;
  double _defaultSize;
  double? _observedSize;
  double? _savedSize;
  double? _draft;
  double? _dragStart;
  bool _unavailable = false;
  bool _disposed = false;
  bool _failed = false;
  int _generation = 0;
  int _subscriptionGeneration = 0;
  VoidCallback? _stopListening;
  final _pending = <_PageIconSave>[];

  bool get canResize =>
      !_disposed &&
      !_unavailable &&
      _view.id.isNotEmpty &&
      _editable &&
      !_view.isLocked &&
      canEdit();
  bool get isResizing => _draft != null;
  bool get isSaving => _pending.isNotEmpty;
  bool get hasFailure => _failed;
  double? get savedSize => _savedSize;
  double? get _requestedSize =>
      _pending.isEmpty ? _savedSize : _pending.last.size;
  double get size => _draft ?? _requestedSize ?? _defaultSize;

  /// Called without notification from widget lifecycle methods. A metadata-
  /// only rebuild retains the draft; changing the binding/access does not.
  void rebind({
    required ViewPB view,
    required Object binding,
    required bool editable,
    required double defaultSize,
    bool notify = true,
  }) {
    if (_disposed) return;
    _defaultSize = defaultSize;
    if (_view.id != view.id || _binding != binding) {
      _stopListening?.call();
      _invalidate();
      _binding = binding;
      _view = ViewPB.fromBuffer(view.writeToBuffer());
      _hostExtra = view.extra;
      _hostLocked = view.isLocked;
      _observedSize = _savedSize = IconSize.decode(view.extra);
      _unavailable = false;
      _editable = editable;
      _listen();
    } else {
      if (_editable && !editable) _invalidate();
      _editable = editable;
      // An unchanged host snapshot can lag a notification or an empty ACK.
      // Rebuilding for a theme/width change must not undo the acknowledged size.
      if (_hostExtra != view.extra ||
          _hostLocked != view.isLocked ||
          _view.layout != view.layout) {
        _hostExtra = view.extra;
        _hostLocked = view.isLocked;
        _adopt(view);
      }
    }
    if (notify) notifyListeners();
  }

  /// Also used for access-stream notifications: revocation invalidates work
  /// even if access is restored again before the next frame is built.
  void setEditable(bool editable, {bool notify = true}) {
    if (_disposed || _editable == editable) return;
    if (!editable) _invalidate();
    _editable = editable;
    if (notify) notifyListeners();
  }

  void _listen() {
    final subscription = ++_subscriptionGeneration;
    _stopListening = null;
    if (_view.id.isEmpty) return;
    _stopListening = backend.listen(
      viewId: _view.id,
      onView: (view) {
        if (_disposed || subscription != _subscriptionGeneration) return;
        _adopt(view);
        notifyListeners();
      },
      onUnavailable: () {
        if (_disposed || subscription != _subscriptionGeneration) return;
        _unavailable = true;
        _invalidate();
        notifyListeners();
      },
    );
  }

  void _adopt(ViewPB view) {
    if (view.id != _view.id) return;
    if (view.layout != _view.layout || !isSameTarget(view)) {
      _unavailable = true;
      _invalidate();
    } else if (view.isLocked) {
      _invalidate();
    }
    final value = IconSize.decode(view.extra);
    if (value != _observedSize) {
      // A matching echo may precede its ACK, including an older queued resize.
      // A different external resize wins and cancels this transient gesture.
      if (value != _savedSize &&
          !_pending.any((request) => request.size == value) &&
          !backend.isPendingSize(view.id, value)) {
        _invalidate();
      }
      _savedSize = _observedSize = value;
    }
    _view = ViewPB.fromBuffer(view.writeToBuffer());
  }

  bool _guard() {
    if (canResize) return true;
    if (!_disposed && (_draft != null || _pending.isNotEmpty)) {
      _invalidate();
      notifyListeners();
    }
    return false;
  }

  bool beginResize(double displayedSize) {
    if (!_guard() ||
        !displayedSize.isFinite ||
        displayedSize < IconSize.minimum) {
      return false;
    }
    _draft = _dragStart = IconSize.clamp(displayedSize);
    _failed = false;
    notifyListeners();
    return true;
  }

  void preview(double size) {
    if (!_guard() || _draft == null || !size.isFinite) return;
    final value = IconSize.clamp(size);
    if (_draft == value) return;
    _draft = value;
    notifyListeners();
  }

  void cancelResize() {
    if (_disposed || _draft == null) return;
    _draft = _dragStart = null;
    notifyListeners();
  }

  Future<bool> commitResize() {
    if (!_guard() || _draft == null) return Future.value(false);
    final value = _draft!;
    final changed = value != _dragStart;
    _draft = _dragStart = null;
    if (!changed) {
      notifyListeners();
      return Future.value(true);
    }
    return saveSize(value);
  }

  Future<bool> saveSize(double? size) {
    if (!_guard()) return Future.value(false);
    final value = size == null ? null : IconSize.clamp(size);
    if (_requestedSize == value) return Future.value(true);
    final request = _PageIconSave(_generation, value);
    _pending.add(request);
    _failed = false;
    final operation = backend.save(
      view: ViewPB.fromBuffer(_view.writeToBuffer()),
      size: value,
      isCurrent: () => _current(request),
      isSameTarget: isSameTarget,
    );
    // The backend tail is already installed if a listener queues another edit.
    notifyListeners();
    return _complete(request, operation);
  }

  bool _current(_PageIconSave request) =>
      _guard() && request.generation == _generation;

  Future<bool> _complete(
    _PageIconSave request,
    Future<FlowyResult<void, FlowyError>> operation,
  ) async {
    final result = await operation;
    if (!_current(request)) return false;
    _pending.remove(request);
    final saved = result.fold((_) => true, (_) => false);
    _failed = !saved;
    if (saved) {
      _savedSize = _observedSize = request.size;
      onSaved(request.size);
    }
    if (!_disposed) notifyListeners();
    return saved;
  }

  void _invalidate() {
    _generation++;
    _pending.clear();
    _draft = _dragStart = null;
    _failed = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscriptionGeneration++;
    _invalidate();
    _stopListening?.call();
    super.dispose();
  }
}

class _PageIconSave {
  const _PageIconSave(this.generation, this.size);

  final int generation;
  final double? size;
}

class _PageIconWrite {
  const _PageIconWrite(this.size);

  final double? size;
}
