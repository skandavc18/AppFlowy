import 'dart:async';

import 'package:flutter_inappwebview_windows/src/in_app_webview/custom_platform_view.dart';
import 'package:flutter_test/flutter_test.dart';

const platformViewTestTimeout = Timeout(Duration(seconds: 30));

Future<void> drainPlatformViewUntil(
  WidgetTester tester,
  bool Function() reached,
  String phase,
) async {
  // Broadcast cancellation can return a cached root-zone future. Drain that
  // zone, then the fake-zone continuations; never await fake disposal in runAsync.
  for (var turn = 0; turn < 20 && !reached(); turn++) {
    await tester.runAsync(() async {});
    await tester.pump();
  }
  expect(reached(), isTrue,
      reason: '$phase did not finish within 20 drain turns');
}

Future<void> awaitPlatformViewDisposal(
  WidgetTester tester,
  CustomPlatformViewController controller, {
  Zone? ownerZone,
}) =>
    _awaitPlatformViewFuture(
      tester,
      controller.dispose(),
      'platform view disposal',
      ownerZone ?? Zone.current,
    );

Future<void> awaitPlatformViewReady(
  WidgetTester tester,
  CustomPlatformViewController controller,
) async {
  if (!controller.value.isInitialized) {
    await _awaitPlatformViewFuture(
      tester,
      controller.ready,
      'platform view initialization',
      Zone.current,
    );
  }
  expect(controller.value.isInitialized, isTrue);
}

Future<void> _awaitPlatformViewFuture(
  WidgetTester tester,
  Future<void> future,
  String phase,
  Zone ownerZone,
) async {
  var settled = false;
  AsyncError? failure;
  // A teardown runs outside the body's error zone. Register in the owner's
  // zone so Dart does not reject delivery of a failed lifecycle future.
  ownerZone.run<void>(() {
    unawaited(future.then<void>((_) {
      settled = true;
    }, onError: (Object error, StackTrace stack) {
      failure = AsyncError(error, stack);
      settled = true;
    }));
  });
  await drainPlatformViewUntil(tester, () => settled, phase);
  // Do not await `future` again: _Future._addListener schedules late listeners
  // in its original (fake) zone. After runTest returns, no automatic drain is
  // left to release that await in addTearDown. Forward the observed ACK result,
  // including its original error/stack, rather than treating settled as success.
  final error = failure;
  if (error != null) Error.throwWithStackTrace(error.error, error.stackTrace);
}
