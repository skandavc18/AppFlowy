import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy_backend/log.dart';

/// Serializes this chart's settings edits. Each write merges into a fresh
/// extra payload, rather than the view snapshot from when the page opened.
class ChartSettingsWriter {
  ChartSettingsWriter({
    required this.viewId,
    Future<String> Function(String viewId)? readExtra,
    Future<void> Function(String viewId, String extra)? writeExtra,
    void Function(ChartMetadata metadata)? onAdopt,
  })  : _readExtra = readExtra ?? _readViewExtra,
        _writeExtra = writeExtra ?? _writeViewExtra,
        _onAdopt = onAdopt;

  final String viewId;
  final Future<String> Function(String viewId) _readExtra;
  final Future<void> Function(String viewId, String extra) _writeExtra;
  final void Function(ChartMetadata metadata)? _onAdopt;
  Future<void> _tail = Future.value();
  int _pending = 0;
  int _readGeneration = 0;
  bool _disposed = false;
  Object? _error;

  /// Notifications can arrive even after this becomes false. Hosts reconcile
  /// against storage instead of adopting a notification's potentially old extra.
  bool get isWriting => _pending > 0;
  Object? get error => _error;

  Future<void> write(ChartMetadata metadata) {
    if (_disposed || viewId.isEmpty) {
      return Future.value();
    }
    _readGeneration++;
    _pending++;
    _tail = _tail.then((_) async {
      try {
        final extra = await _readExtra(viewId);
        await _writeExtra(viewId, metadata.mergeIntoExtra(extra));
        _error = null;
      } on Object catch (error) {
        _error = error;
        // A failed save must not poison the queue for the next selection.
        Log.warn('Could not save chart settings for $viewId');
      } finally {
        _pending--;
      }
    });
    // Reconcile after the write queue, not inside it (which would await itself).
    return _tail.then((_) => reconcile());
  }

  /// Treat a host view update as an invalidation, not an ordered acknowledgement.
  /// A real remote change may equal an older local choice, so no echo blacklist
  /// is safe. A newer write/read or disposal invalidates this read's adoption.
  Future<void> reconcile() async {
    if (_disposed || viewId.isEmpty || _onAdopt == null) {
      return;
    }
    final generation = ++_readGeneration;
    await _tail;
    if (_disposed || generation != _readGeneration) {
      return;
    }
    try {
      final extra = await _readExtra(viewId);
      if (_disposed || isWriting || generation != _readGeneration) {
        return;
      }
      final metadata = ChartMetadata.fromExtra(extra);
      if (metadata != null) {
        _onAdopt(metadata);
      }
    } on Object catch (_) {
      // Do not replace a working selection with an unverified notification.
      Log.warn('Could not reconcile chart settings for $viewId');
    }
  }

  void dispose() {
    _disposed = true;
    _readGeneration++;
    // Already accepted edits still finish saving; only UI adoption is cancelled.
  }
}

Future<String> _readViewExtra(String viewId) async =>
    (await ViewBackendService.getView(viewId)).fold(
      (view) {
        if (view.id != viewId) {
          throw StateError('Chart settings returned a different view');
        }
        return view.extra;
      },
      (error) => throw StateError(error.msg),
    );

Future<void> _writeViewExtra(String viewId, String extra) async {
  (await ViewBackendService.updateView(viewId: viewId, extra: extra)).fold(
    (_) {},
    (error) => throw StateError(error.msg),
  );
}
