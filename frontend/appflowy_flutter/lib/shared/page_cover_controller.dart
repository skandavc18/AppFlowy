import 'dart:async';

import 'package:appflowy/shared/page_cover_height.dart';
import 'package:appflowy/shared/page_icon_controller.dart';
import 'package:appflowy/workspace/application/view/view_cover_codec.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';

/// Existing notification/FFI adapter, with a separate cover-only mutation.
/// Fresh merges are serialized across mounted and reopened cover owners.
/// Other metadata writers/devices are not an atomic compare-and-swap service.
class PageCoverBackendService {
  const PageCoverBackendService({this.views = const PageIconBackendService()});

  final PageIconBackendService views;

  Future<bool> save({
    required ViewPB view,
    required double? height,
    required bool Function() isCurrent,
    required bool Function(ViewPB) isSameTarget,
  }) {
    return PageIconBackendService.serializeMetadata(view.id, () async {
      try {
        if (view.id.isEmpty || !isCurrent()) return false;
        final result = await views.readView(view.id);
        final fresh = result.fold<ViewPB?>((value) => value, (_) => null);
        if (!isCurrent() ||
            fresh == null ||
            fresh.id != view.id ||
            fresh.isLocked ||
            fresh.layout != view.layout ||
            !samePageCoverSource(view, fresh) ||
            !isSameTarget(fresh)) {
          return false;
        }
        final extra = PageCoverHeight.merge(fresh.extra, height);
        if (!isCurrent()) return false;
        final saved = await views.updateView(viewId: view.id, extra: extra);
        return saved.fold(
          (ack) => ack.id.isEmpty || ack.id == view.id,
          (_) => false,
        );
      } catch (_) {
        // No inverse write/retry: an exception can have an unknown outcome.
        return false;
      }
    });
  }
}

/// Identity/source changes cancel work; unrelated title/icon/size metadata does
/// not. Include the complete source binding (including its read-only flag).
bool samePageCoverSource(ViewPB before, ViewPB after) {
  try {
    final a = ViewCoverCodec.decodeExtra(before.extra);
    final b = ViewCoverCodec.decodeExtra(after.extra);
    return before.id == after.id &&
        before.layout == after.layout &&
        const DeepCollectionEquality().equals(
          [
            a['cover'],
            a['appflowy_collection_source'],
            a['appflowy_workspace_item']
          ],
          [
            b['cover'],
            b['appflowy_collection_source'],
            b['appflowy_workspace_item']
          ],
        );
  } on FormatException {
    return false;
  }
}

/// No editor, image, title, or native-focus ownership lives in this controller.
class PageCoverController extends ChangeNotifier {
  PageCoverController({
    required ViewPB view,
    required Object binding,
    required bool editable,
    required this.canEdit,
    required this.isSameTarget,
    required this.onSaved,
    this.backend = const PageCoverBackendService(),
  })  : _view = ViewPB.fromBuffer(view.writeToBuffer()),
        _hostExtra = view.extra,
        _binding = binding,
        _editable = editable,
        _saved = PageCoverHeight.decode(view.extra) {
    _listen();
  }

  final PageCoverBackendService backend;
  final bool Function() canEdit;
  final bool Function(ViewPB) isSameTarget;
  final ValueChanged<double?> onSaved;
  ViewPB _view;
  String _hostExtra;
  Object _binding;
  bool _editable;
  bool _disposed = false;
  bool _unavailable = false;
  bool _failed = false;
  int _epoch = 0;
  int _subscription = 0;
  double? _saved;
  double? _draft;
  double? _start;
  final _pending = <_CoverSave>[];
  VoidCallback? _stop;

  bool get canResize =>
      !_disposed &&
      !_unavailable &&
      _editable &&
      !_view.isLocked &&
      _view.id.isNotEmpty &&
      canEdit();
  bool get isResizing => _draft != null;
  bool get isSaving => _pending.isNotEmpty;
  bool get hasFailure => _failed;
  double? get height =>
      _draft ?? (_pending.isEmpty ? _saved : _pending.last.height);

  void _listen() {
    final subscription = ++_subscription;
    if (_view.id.isEmpty) return;
    _stop = backend.views.listen(
      viewId: _view.id,
      onView: (view) {
        if (_disposed || subscription != _subscription) return;
        _adopt(view);
        notifyListeners();
      },
      onUnavailable: () {
        if (_disposed || subscription != _subscription) return;
        _unavailable = true;
        _invalidate();
        notifyListeners();
      },
    );
  }

  void rebind(
      {required ViewPB view, required Object binding, required bool editable}) {
    if (_disposed) return;
    if (_view.id != view.id || _binding != binding) {
      _stop?.call();
      _invalidate();
      _view = ViewPB.fromBuffer(view.writeToBuffer());
      _hostExtra = view.extra;
      _saved = PageCoverHeight.decode(view.extra);
      _binding = binding;
      _unavailable = false;
      _editable = editable;
      _listen();
    } else {
      setEditable(editable, notify: false);
      if (_hostExtra != view.extra || view.isLocked != _view.isLocked) {
        _hostExtra = view.extra;
        _adopt(view);
      }
    }
  }

  void _adopt(ViewPB view) {
    if (view.id != _view.id) return;
    if (!samePageCoverSource(_view, view) || !isSameTarget(view)) {
      _invalidate();
      _unavailable = view.layout != _view.layout || !isSameTarget(view);
    } else if (view.isLocked) {
      _invalidate();
    }
    final size = PageCoverHeight.decode(view.extra);
    if (size != _saved && !_pending.any((save) => save.height == size)) {
      _invalidate();
    }
    _saved = size;
    _view = ViewPB.fromBuffer(view.writeToBuffer());
  }

  void setEditable(bool editable, {bool notify = true}) {
    if (_disposed || _editable == editable) return;
    if (!editable) _invalidate();
    _editable = editable;
    if (notify) notifyListeners();
  }

  bool begin(double displayed) {
    if (!canResize || !displayed.isFinite) return false;
    _start = _draft = displayed
        .clamp(PageCoverHeight.minimum, PageCoverHeight.maximum)
        .toDouble();
    _failed = false;
    notifyListeners();
    return true;
  }

  void preview(double value) {
    if (!canResize) {
      cancel();
      return;
    }
    if (_draft == null || !value.isFinite) return;
    _draft = value
        .clamp(PageCoverHeight.minimum, PageCoverHeight.maximum)
        .toDouble();
    notifyListeners();
  }

  void cancel() {
    if (_disposed || _draft == null) return;
    _start = _draft = null;
    notifyListeners();
  }

  Future<bool> commit() {
    final value = _draft;
    final changed = value != _start;
    _start = _draft = null;
    if (value == null || !changed || !canResize) {
      if (!_disposed) notifyListeners();
      return Future.value(false);
    }
    return save(value);
  }

  Future<bool> save(double? height) {
    if (!canResize ||
        (height != null &&
            (!height.isFinite ||
                height < PageCoverHeight.minimum ||
                height > PageCoverHeight.maximum))) {
      return Future.value(false);
    }
    final request = _CoverSave(_epoch, height);
    _pending.add(request);
    _failed = false;
    final operation = backend.save(
      view: ViewPB.fromBuffer(_view.writeToBuffer()),
      height: height,
      isCurrent: () => canResize && request.epoch == _epoch,
      isSameTarget: isSameTarget,
    );
    notifyListeners();
    return _complete(request, operation);
  }

  Future<bool> _complete(_CoverSave request, Future<bool> operation) async {
    final saved = await operation;
    if (!canResize || request.epoch != _epoch) return false;
    _pending.remove(request);
    _failed = !saved;
    if (saved) {
      _saved = request.height;
      onSaved(request.height);
    }
    if (!_disposed) notifyListeners();
    return saved;
  }

  void _invalidate() {
    _epoch++;
    _pending.clear();
    _start = _draft = null;
    _failed = false;
  }

  @override
  void dispose() {
    _disposed = true;
    _subscription++;
    _invalidate();
    _stop?.call();
    super.dispose();
  }
}

class _CoverSave {
  const _CoverSave(this.epoch, this.height);
  final int epoch;
  final double? height;
}
