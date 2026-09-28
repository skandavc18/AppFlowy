import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

// Observe immediately, including errors, without replacing the original future.
// Assertions below still await that future (or its throwsA expectation).
class _ObservedFuture {
  _ObservedFuture(this.future) {
    unawaited(future.then<void>((_) {
      settled = true;
    }, onError: (Object error, StackTrace stack) {
      settled = true;
    }));
  }

  final Future<void> future;
  bool settled = false;
}

Future<void> _drainUntil(
  WidgetTester tester,
  bool Function() reached,
  String phase,
) async {
  // Dart's broadcast subscription.cancel returns the root-zone nullFuture,
  // not EventChannel's async onCancel result. A pump alone cannot drain that
  // future's late-listener microtask. Yield to real microtasks, then pump the
  // fake-zone continuations (including stream close), without awaiting a
  // fake-zone lifecycle future inside runAsync or advancing arbitrary time.
  for (var turn = 0; turn < 20 && !reached(); turn++) {
    await tester.runAsync(() async {});
    await tester.pump();
  }
  expect(reached(), isTrue,
      reason: '$phase did not finish within 20 drain turns');
}

Future<void> _awaitObserved(
  WidgetTester tester,
  _ObservedFuture observed,
  String phase,
) async {
  await _drainUntil(tester, () => observed.settled, phase);
  await observed.future;
}

void main() {
  const timeout = Timeout(Duration(seconds: 30));
  const manager =
      MethodChannel('com.pichillilorenzo/flutter_inappwebview_manager');
  const events =
      MethodChannel('com.pichillilorenzo/custom_platform_view_81_events');
  const view = MethodChannel('com.pichillilorenzo/custom_platform_view_81');

  testWidgets('unmount disposal waits for native unregister final ack',
      (tester) async {
    final nativeAck = Completer<Map<String, dynamic>>();
    var disposals = 0;
    final eventCalls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method == 'createInAppWebView') return 81;
      if (call.method == 'dispose') {
        expectSync(call.arguments, {'id': 81});
        expectSync(eventCalls, ['listen', 'cancel']);
        disposals++;
        return nativeAck.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      eventCalls.add(call.method);
      return null;
    });
    messenger.setMockMethodCallHandler(view, (_) async => null);
    addTearDown(() {
      messenger.setMockMethodCallHandler(manager, null);
      messenger.setMockMethodCallHandler(events, null);
      messenger.setMockMethodCallHandler(view, null);
    });
    CustomPlatformViewController? controller;
    try {
      await tester.pumpWidget(const MaterialApp(
        home: SizedBox(width: 300, height: 300, child: CustomPlatformView()),
      ));
      final mountedController = tester
          .state<CustomPlatformViewState>(find.byType(CustomPlatformView))
          .controller;
      controller = mountedController;
      await _awaitObserved(
        tester,
        _ObservedFuture(mountedController.ready),
        'widget initialization',
      );
      await tester.pump();
      expect(mountedController.value.isInitialized, isTrue);
      expect(eventCalls, ['listen']);
      await tester.pumpWidget(const SizedBox.shrink());
      final disposal = _ObservedFuture(mountedController.dispose());
      expect(identical(disposal.future, mountedController.dispose()), isTrue);
      await _drainUntil(tester, () => disposals == 1, 'native dispose request');
      expect(disposals, 1);
      expect(disposal.settled, isFalse);
      expect(mountedController.disposalDiagnostics, isNull);
      nativeAck.complete({
        'schema': 1,
        'stages': [0, 1, 2, 3, 4, 5]
      });
      await _awaitObserved(tester, disposal, 'native ACK and stream closure');
      expect(disposal.settled, isTrue);
      expect(mountedController.disposalDiagnostics?['schema'], 1);
      expect(
          mountedController.disposalDiagnostics?['stages'], [0, 1, 2, 3, 4, 5]);
      expect(identical(disposal.future, mountedController.dispose()), isTrue);
      expect(disposals, 1);
      expect(eventCalls, ['listen', 'cancel']);
      expect(tester.takeException(), isNull);
    } finally {
      if (!nativeAck.isCompleted) nativeAck.complete({});
      await tester.pumpWidget(const SizedBox.shrink());
      if (controller != null) {
        await _awaitObserved(
          tester,
          _ObservedFuture(controller.dispose()),
          'unmount cleanup',
        );
      }
    }
  }, timeout: timeout);

  testWidgets('disposal waits for pending creation and then unregister',
      (tester) async {
    final creation = Completer<int>();
    final nativeAck = Completer<void>();
    var disposals = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method == 'createInAppWebView') return creation.future;
      if (call.method == 'dispose') {
        expectSync(call.arguments, {'id': 81});
        disposals++;
        await nativeAck.future;
      }
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(manager, null));
    final controller = CustomPlatformViewController();
    final initialized = _ObservedFuture(controller.initialize());
    final disposal = _ObservedFuture(controller.dispose());
    try {
      expect(identical(disposal.future, controller.dispose()), isTrue);
      await tester.pump();
      expect(disposals, 0);
      expect(initialized.settled, isFalse);
      expect(disposal.settled, isFalse);
      creation.complete(81);
      await _awaitObserved(tester, initialized, 'pending creation');
      await tester.pump();
      await _drainUntil(tester, () => disposals == 1, 'dispose after creation');
      expect(disposals, 1);
      expect(disposal.settled, isFalse);
      nativeAck.complete();
      await _awaitObserved(tester, disposal, 'pending creation disposal ACK');
      expect(disposal.settled, isTrue);
      expect(controller.disposalDiagnostics, isNull);
      expect(identical(disposal.future, controller.dispose()), isTrue);
      expect(disposals, 1);
    } finally {
      if (!creation.isCompleted) creation.complete(81);
      if (!nativeAck.isCompleted) nativeAck.complete();
      await _awaitObserved(tester, initialized, 'creation cleanup');
      await _awaitObserved(tester, disposal, 'pending disposal cleanup');
    }
  }, timeout: timeout);

  testWidgets('failed unregister reply remains a failed shared disposal',
      (tester) async {
    final nativeAck = Completer<void>();
    var disposals = 0;
    final eventCalls = <String>[];
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method == 'createInAppWebView') return 81;
      if (call.method == 'dispose') {
        expectSync(call.arguments, {'id': 81});
        expectSync(eventCalls, ['listen', 'cancel']);
        disposals++;
        await nativeAck.future;
      }
      return null;
    });
    messenger.setMockMethodCallHandler(events, (call) async {
      eventCalls.add(call.method);
      return null;
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(manager, null);
      messenger.setMockMethodCallHandler(events, null);
    });
    final controller = CustomPlatformViewController();
    final initialized = _ObservedFuture(controller.initialize());
    _ObservedFuture? disposal;
    _ObservedFuture? failure;
    try {
      await _awaitObserved(
          tester, initialized, 'initialization before failure');
      await tester.pump();
      final observedDisposal = _ObservedFuture(controller.dispose());
      disposal = observedDisposal;
      final observedFailure = _ObservedFuture(expectLater(
        observedDisposal.future,
        throwsA(isA<PlatformException>()
            .having((error) => error.code, 'code', 'controllerCloseFailed')),
      ));
      failure = observedFailure;
      expect(identical(observedDisposal.future, controller.dispose()), isTrue);
      await _drainUntil(
          tester, () => disposals == 1, 'failing dispose request');
      expect(disposals, 1);
      expect(observedDisposal.settled, isFalse);
      expect(controller.disposalDiagnostics, isNull);
      nativeAck.completeError(PlatformException(code: 'controllerCloseFailed'));
      await _awaitObserved(tester, observedFailure, 'failed ACK propagation');
      expect(observedDisposal.settled, isTrue);
      expect(identical(observedDisposal.future, controller.dispose()), isTrue);
      // A late caller must see the same failure, not a successful retry.
      await _awaitObserved(
        tester,
        _ObservedFuture(expectLater(
          controller.dispose(),
          throwsA(isA<PlatformException>()
              .having((error) => error.code, 'code', 'controllerCloseFailed')),
        )),
        'late shared disposal failure',
      );
      expect(controller.disposalDiagnostics, isNull);
      expect(disposals, 1);
      expect(eventCalls, ['listen', 'cancel']);
    } finally {
      if (!nativeAck.isCompleted) nativeAck.complete();
      final cleanup = disposal ?? _ObservedFuture(controller.dispose());
      await _drainUntil(
          tester, () => cleanup.settled, 'failed disposal cleanup');
      if (failure != null) {
        await _awaitObserved(tester, failure, 'failure assertion cleanup');
      } else {
        await _awaitObserved(tester, initialized, 'initialization cleanup');
        await cleanup.future;
      }
    }
  }, timeout: timeout);

  testWidgets('creation error does not strand a disposal waiter',
      (tester) async {
    var disposals = 0;
    final messenger = tester.binding.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(manager, (call) async {
      if (call.method == 'createInAppWebView') {
        throw PlatformException(code: 'createFailed');
      }
      if (call.method == 'dispose') disposals++;
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(manager, null));
    final controller = CustomPlatformViewController();
    final initialized = _ObservedFuture(controller.initialize());
    final failure = _ObservedFuture(expectLater(
      initialized.future,
      throwsA(isA<PlatformException>()
          .having((error) => error.code, 'code', 'createFailed')),
    ));
    final ready = _ObservedFuture(controller.ready);
    final disposal = _ObservedFuture(controller.dispose());
    try {
      expect(identical(disposal.future, controller.dispose()), isTrue);
      await _awaitObserved(tester, failure, 'creation error propagation');
      await tester.pump();
      await _awaitObserved(tester, ready, 'failed creation waiter release');
      await _awaitObserved(tester, disposal, 'failed creation stream closure');
      expect(disposal.settled, isTrue);
      expect(identical(disposal.future, controller.dispose()), isTrue);
      expect(disposals, 0);
      expect(controller.disposalDiagnostics, isNull);
    } finally {
      await _awaitObserved(tester, failure, 'creation error assertion cleanup');
      await _awaitObserved(tester, disposal, 'creation error disposal cleanup');
    }
  }, timeout: timeout);
}
