import 'dart:async';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/shared/page_icon_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

class CoverMemoryStorage extends Fake implements KeyValueStorage {
  final values = <String, String>{};
  final writes = <(String, String)>[];
  Completer<void>? readGate;
  Completer<void>? writeGate;
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  bool failRead = false;
  bool failWrite = false;

  @override
  Future<String?> get(String key) async {
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    if (failRead) throw StateError('private read details');
    return values[key];
  }

  @override
  Future<void> set(String key, String value) async {
    writes.add((key, value));
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (failWrite) throw StateError('private write details');
    values[key] = value;
  }
}

class CoverMemoryViews extends PageIconBackendService {
  CoverMemoryViews(this.view);
  ViewPB view;
  final writes = <String>[];
  int reads = 0;
  Completer<void>? readGate;
  Completer<void>? writeGate;
  final readStarted = Completer<void>();
  final writeStarted = Completer<void>();
  bool failWrite = false;
  bool wrongReadId = false;
  final listeners = <ValueChanged<ViewPB>>[];
  final unavailable = <VoidCallback>[];

  @override
  Future<FlowyResult<ViewPB, FlowyError>> readView(String viewId) async {
    reads++;
    if (!readStarted.isCompleted) readStarted.complete();
    await readGate?.future;
    return FlowyResult.success(wrongReadId ? ViewPB(id: 'wrong') : view);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> updateView({
    required String viewId,
    required String extra,
  }) async {
    writes.add(extra);
    if (!writeStarted.isCompleted) writeStarted.complete();
    await writeGate?.future;
    if (failWrite) {
      return FlowyResult.failure(FlowyError(msg: 'private write details'));
    }
    view = ViewPB.fromBuffer(view.writeToBuffer())..extra = extra;
    return FlowyResult.success(ViewPB()); // real empty-success ACK contract
  }

  @override
  VoidCallback listen({
    required String viewId,
    required ValueChanged<ViewPB> onView,
    required VoidCallback onUnavailable,
  }) {
    listeners.add(onView);
    unavailable.add(onUnavailable);
    return () {
      listeners.remove(onView);
      unavailable.remove(onUnavailable);
    };
  }

  void emit(ViewPB next) {
    view = next;
    for (final listener in List.of(listeners)) {
      listener(next);
    }
  }
}
