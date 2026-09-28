import 'dart:async';

import 'package:appflowy/shared/page_icon_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';

/// Retains the real save queue/guards, replacing only storage and notifications.
class PageIconMemoryBackend extends PageIconBackendService {
  PageIconMemoryBackend(Iterable<ViewPB> initial)
      : views = {
          for (final view in initial)
            view.id: ViewPB.fromBuffer(view.writeToBuffer()),
        };

  final Map<String, ViewPB> views;
  final reads = <String>[];
  final writes = <({String viewId, String extra})>[];
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  final listenedIds = <String>[];
  final _held = <Completer<void>>[];
  final _listeners = <_Subscription>[];
  Completer<void>? readBarrier;
  Completer<void>? writeBarrier;
  bool failWrites = false;
  bool throwWrites = false;
  bool emitUpdates = true;
  String ackId = '';
  int activeWrites = 0;
  int maxActiveWrites = 0;

  int get activeListeners => _listeners.length;

  @override
  Future<FlowyResult<ViewPB, FlowyError>> readView(String viewId) async {
    reads.add(viewId);
    final barrier = readBarrier;
    readBarrier = null;
    if (barrier != null) _held.add(barrier);
    if (!readStarted.isCompleted) readStarted.complete();
    if (barrier != null) await barrier.future;
    final view = views[viewId];
    return view == null
        ? FlowyResult.failure(FlowyError(msg: 'Missing view'))
        : FlowyResult.success(ViewPB.fromBuffer(view.writeToBuffer()));
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateView({
    required String viewId,
    required String extra,
  }) async {
    writes.add((viewId: viewId, extra: extra));
    activeWrites++;
    if (activeWrites > maxActiveWrites) maxActiveWrites = activeWrites;
    final barrier = writeBarrier;
    writeBarrier = null;
    if (barrier != null) _held.add(barrier);
    if (!writeStarted.isCompleted) writeStarted.complete();
    try {
      if (barrier != null) await barrier.future;
      if (throwWrites) throw StateError('Synthetic unknown write outcome');
      final current = views[viewId];
      if (failWrites || current == null) {
        return FlowyResult.failure(FlowyError(msg: 'Synthetic failed write'));
      }
      final saved = ViewPB.fromBuffer(current.writeToBuffer())..extra = extra;
      views[viewId] = saved;
      if (emitUpdates) publish(saved);
      return FlowyResult.success(ViewPB(id: ackId));
    } finally {
      activeWrites--;
    }
  }

  @override
  VoidCallback listen({
    required String viewId,
    required ValueChanged<ViewPB> onView,
    required VoidCallback onUnavailable,
  }) {
    listenedIds.add(viewId);
    final subscription = _Subscription(viewId, onView, onUnavailable);
    _listeners.add(subscription);
    return () => _listeners.remove(subscription);
  }

  void publish(ViewPB view) {
    views[view.id] = ViewPB.fromBuffer(view.writeToBuffer());
    for (final subscription in _listeners.toList()) {
      if (subscription.viewId == view.id) subscription.onView(view);
    }
  }

  void delete(String viewId) {
    views.remove(viewId);
    for (final subscription in _listeners.toList()) {
      if (subscription.viewId == viewId) subscription.onUnavailable();
    }
  }

  void releasePending() {
    for (final barrier in [..._held, readBarrier, writeBarrier]) {
      if (barrier != null && !barrier.isCompleted) barrier.complete();
    }
  }
}

class _Subscription {
  const _Subscription(this.viewId, this.onView, this.onUnavailable);

  final String viewId;
  final ValueChanged<ViewPB> onView;
  final VoidCallback onUnavailable;
}
