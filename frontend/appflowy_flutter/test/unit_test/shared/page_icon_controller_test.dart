import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/page_icon_controller.dart';
import 'package:appflowy/shared/page_icon_size.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

import 'page_icon_test_support.dart';

void main() {
  test('empty IDs neither listen nor write and rebinding releases listeners',
      () async {
    final h = _Harness(view: ViewPB());
    expect(h.backend.listenedIds, isEmpty);
    expect(h.controller.canResize, isFalse);
    expect(h.controller.beginResize(66), isFalse);
    expect(await h.controller.saveSize(100), isFalse);
    expect(h.backend.reads, isEmpty);
    expect(h.backend.writes, isEmpty);
    h.rebind(ViewPB(id: 'nonempty'));
    expect(h.backend.listenedIds, ['nonempty']);
    expect(h.backend.activeListeners, 1);
    h.rebind(ViewPB());
    expect(h.backend.listenedIds, ['nonempty']);
    expect(h.backend.activeListeners, 0);
    h.close();
    expect(h.backend.activeListeners, 0);
  });

  test('preview/cancel is local and never changes the shared view', () async {
    final h = _Harness();
    final original = h.view.writeToBuffer();
    expect(h.controller.size, 66);
    expect(h.controller.beginResize(66), isTrue);
    h.controller.preview(103.375);
    expect(h.controller.size, 103.375);
    expect(h.backend.reads, isEmpty);
    expect(h.backend.writes, isEmpty);
    expect(h.saved, isEmpty);
    expect(h.view.writeToBuffer(), original);
    h.controller.cancelResize();
    expect(h.controller.size, 66);
    expect(await h.controller.commitResize(), isFalse);
    expect(h.controller.beginResize(66), isTrue);
    expect(await h.controller.commitResize(), isTrue);
    expect(h.backend.writes, isEmpty);
  });

  test('fresh extra and an empty ACK preserve newer unrelated metadata',
      () async {
    final h = _Harness(extra: '{"old":true}');
    final live = ViewPB.fromBuffer(h.view.writeToBuffer())
      ..name = 'Concurrent title'
      ..extra = '{"cover":{"value":"new-cover"},"unknown":[1,2]}';
    h.backend.views[live.id] = live;
    h.view = ViewPB.fromBuffer(live.writeToBuffer());
    expect(await h.controller.saveSize(121.375), isTrue);
    expect(h.saved, [121.375]);
    expect(h.view.name, 'Concurrent title');
    expect(jsonDecode(h.backend.writes.single.extra), {
      'cover': {'value': 'new-cover'},
      'unknown': [1, 2],
      IconSize.key: 121.375,
    });
    expect(IconSize.decode(h.view.extra), 121.375);
  });

  test('repeated resize, save, reopen and reset retain per-view preferences',
      () async {
    final h = _Harness();
    for (final size in [101.25, 187.75, 62.125]) {
      expect(await h.resize(size), isTrue);
      expect(h.controller.savedSize, size);
    }
    final stored = h.backend.views[h.view.id]!;
    h.close();
    final reopened = _Harness(view: stored, backend: h.backend);
    expect(reopened.controller.size, 62.125);
    expect(await reopened.controller.saveSize(null), isTrue);
    expect(reopened.controller.size, 66);
    expect(jsonDecode(reopened.backend.views[stored.id]!.extra), isEmpty);
    final other = _Harness();
    expect(other.controller.size, 66);
    expect(other.backend.writes, isEmpty);
  });

  test('same-view writes serialize, including reentrant busy listeners',
      () async {
    final h = _Harness();
    final barrier = Completer<void>();
    h.backend.writeBarrier = barrier;
    var enqueued = false;
    late Future<bool> second;
    h.controller.addListener(() {
      if (h.controller.isSaving && !enqueued) {
        enqueued = true;
        second = h.controller.saveSize(178.25);
      }
    });
    final first = h.controller.saveSize(97.5);
    await h.backend.writeStarted.future;
    expect(h.backend.writes, hasLength(1));
    expect(h.controller.size, 178.25);
    barrier.complete();
    expect(await first, isTrue);
    expect(await second, isTrue);
    expect(h.backend.maxActiveWrites, 1);
    expect(h.backend.reads, [h.view.id, h.view.id]);
    expect(h.backend.writes.map((write) => IconSize.decode(write.extra)),
        [97.5, 178.25]);
    expect(h.controller.savedSize, 178.25);
  });

  test('late host snapshot does not undo an empty ACK without notifications',
      () async {
    final h = _Harness();
    final oldView = ViewPB.fromBuffer(h.view.writeToBuffer());
    h.backend.emitUpdates = false;
    expect(await h.controller.saveSize(104), isTrue);
    h.controller.rebind(
      view: oldView,
      binding: h.binding,
      editable: true,
      defaultSize: 66,
    );
    expect(h.controller.size, 104);
    expect(h.controller.savedSize, 104);
  });

  for (final invalidation in ['readonly', 'locked', 'deleted', 'rebound']) {
    test('$invalidation while reading cancels the write and queued requests',
        () async {
      final h = _Harness();
      final barrier = Completer<void>();
      h.backend.readBarrier = barrier;
      final first = h.controller.saveSize(98);
      final second = h.controller.saveSize(135);
      await h.backend.readStarted.future;
      switch (invalidation) {
        case 'readonly':
          h.controller.setEditable(false);
          h.controller.setEditable(true);
        case 'locked':
          h.backend.publish(
            ViewPB.fromBuffer(h.view.writeToBuffer())..isLocked = true,
          );
        case 'deleted':
          h.backend.delete(h.view.id);
        case 'rebound':
          h.rebind(ViewPB(id: '${h.view.id}-replacement'));
      }
      barrier.complete();
      expect(await first, isFalse);
      expect(await second, isFalse);
      expect(h.backend.writes, isEmpty);
      expect(h.saved, isEmpty);
      expect(h.controller.isSaving, isFalse);
      expect(h.controller.isResizing, isFalse);
    });
  }

  test('live permission callback is rechecked after fresh read', () async {
    final h = _Harness();
    final barrier = Completer<void>();
    h.backend.readBarrier = barrier;
    final save = h.controller.saveSize(110);
    await h.backend.readStarted.future;
    // Deliberately no widget/controller rebuild in between.
    h.editable = false;
    barrier.complete();
    expect(await save, isFalse);
    expect(h.backend.writes, isEmpty);
    expect(h.saved, isEmpty);
  });

  test('revocation after dispatch ignores ACK and drops queued writes',
      () async {
    final h = _Harness();
    final barrier = Completer<void>();
    h.backend.writeBarrier = barrier;
    final first = h.controller.saveSize(110);
    await h.backend.writeStarted.future;
    final second = h.controller.saveSize(190);
    h.controller.setEditable(false);
    barrier.complete();
    expect(await first, isFalse);
    expect(await second, isFalse);
    expect(h.saved, isEmpty);
    expect(h.backend.writes, hasLength(1));
    // Already-dispatched writes cannot be cancelled, and are never inverted.
    expect(IconSize.decode(h.backend.views[h.view.id]!.extra), 110);
  });

  test('A -> B -> A keeps the old write lock and ignores stale ACK callbacks',
      () async {
    final h = _Harness();
    final a = h.view;
    final b = ViewPB(id: '${a.id}-B');
    h.backend.views[b.id] = b;
    final barrier = Completer<void>();
    h.backend.writeBarrier = barrier;
    final old = h.controller.saveSize(90);
    await h.backend.writeStarted.future;
    h.rebind(b);
    h.rebind(a);
    final fresh = h.controller.saveSize(155);
    expect(h.backend.writes, hasLength(1));
    barrier.complete();
    expect(await old, isFalse);
    expect(await fresh, isTrue);
    expect(h.saved, [155]);
    expect(h.backend.maxActiveWrites, 1);
    expect(h.backend.writes.map((write) => write.viewId), [a.id, a.id]);
    expect(IconSize.decode(h.backend.views[a.id]!.extra), 155);
    expect(IconSize.decode(h.backend.views[b.id]!.extra), isNull);
  });

  test('dispose/reopen shares the backend queue without updating old hosts',
      () async {
    final h = _Harness();
    final view = h.view;
    final barrier = Completer<void>();
    h.backend.writeBarrier = barrier;
    final old = h.controller.saveSize(88);
    await h.backend.writeStarted.future;
    h.close();
    final reopened = _Harness(view: view, backend: h.backend);
    final fresh = reopened.controller.saveSize(148);
    expect(h.backend.writes, hasLength(1));
    barrier.complete();
    expect(await old, isFalse);
    expect(await fresh, isTrue);
    expect(h.saved, isEmpty);
    expect(reopened.saved, [148]);
    expect(h.backend.maxActiveWrites, 1);
  });

  test('external size changes cancel a drag; ordinary metadata does not', () {
    final h = _Harness();
    expect(h.controller.beginResize(66), isTrue);
    h.controller.preview(94);
    h.backend.publish(
      ViewPB.fromBuffer(h.view.writeToBuffer())..extra = '{"other":"new"}',
    );
    expect(h.controller.size, 94);
    expect(h.controller.isResizing, isTrue);
    h.backend.publish(IconSize.applyTo(h.view, 140));
    expect(h.controller.isResizing, isFalse);
    expect(h.controller.size, 140);
    expect(h.backend.writes, isEmpty);
  });

  for (final failure in ['missing', 'locked', 'replacement', 'bad metadata']) {
    test('fresh $failure refuses the metadata update', () async {
      final h = _Harness();
      switch (failure) {
        case 'missing':
          h.backend.views.remove(h.view.id);
        case 'locked':
          h.backend.views[h.view.id]!.isLocked = true;
        case 'replacement':
          h.acceptTarget = false;
        case 'bad metadata':
          h.backend.views[h.view.id]!.extra = 'not a JSON object';
      }
      expect(await h.controller.saveSize(180), isFalse);
      expect(h.backend.writes, isEmpty);
      expect(h.saved, isEmpty);
      expect(h.controller.size, 66);
      expect(h.controller.hasFailure, isTrue);
    });
  }

  for (final failure in ['failure', 'throw', 'wrong ACK']) {
    test('$failure rolls back presentation and permits an explicit retry',
        () async {
      final h = _Harness();
      h.backend.emitUpdates = false;
      h.backend.failWrites = failure == 'failure';
      h.backend.throwWrites = failure == 'throw';
      h.backend.ackId = failure == 'wrong ACK' ? 'wrong-view' : '';
      expect(await h.controller.saveSize(180), isFalse);
      expect(h.saved, isEmpty);
      expect(h.controller.size, 66);
      expect(h.controller.hasFailure, isTrue);
      h.backend.failWrites = h.backend.throwWrites = false;
      h.backend.ackId = '';
      expect(await h.controller.saveSize(181), isTrue);
      expect(h.saved, [181]);
      expect(h.controller.hasFailure, isFalse);
    });
  }
}

int _nextId = 0;

class _Harness {
  _Harness({ViewPB? view, PageIconMemoryBackend? backend, String extra = ''}) {
    this.view = view ?? ViewPB(id: 'page-icon-${_nextId++}', extra: extra);
    this.backend = backend ?? PageIconMemoryBackend([this.view]);
    controller = PageIconController(
      view: this.view,
      binding: binding,
      editable: true,
      defaultSize: 66,
      backend: this.backend,
      canEdit: () => editable,
      isSameTarget: (_) => acceptTarget,
      onSaved: (size) {
        saved.add(size);
        this.view = IconSize.applyTo(this.view, size);
      },
    );
    addTearDown(() {
      close();
      this.backend.releasePending();
    });
  }

  late ViewPB view;
  late PageIconMemoryBackend backend;
  late PageIconController controller;
  Object binding = Object();
  bool editable = true;
  bool acceptTarget = true;
  bool closed = false;
  final saved = <double?>[];

  Future<bool> resize(double size) {
    controller.beginResize(controller.size);
    controller.preview(size);
    return controller.commitResize();
  }

  void rebind(ViewPB view) {
    this.view = view;
    binding = Object();
    controller.rebind(
      view: view,
      binding: binding,
      editable: editable,
      defaultSize: 66,
    );
  }

  void close() {
    if (closed) return;
    closed = true;
    controller.dispose();
  }
}
