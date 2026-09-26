import 'package:flutter_test/flutter_test.dart';

const homeProfileTestTimeout = Timeout(Duration(seconds: 45));

/// Drain in-memory bloc/stream closes in the fake zone that owns them.
/// Awaiting close directly (or moving it to runAsync) can block the very pump
/// needed to deliver onDone, including for a previously closed stream.
Future<void> pumpHomeProfileClose(
  WidgetTester tester,
  Future<void> close, {
  String description = 'Home/profile fixture close',
}) async {
  var completed = false;
  Object? closeError;
  StackTrace? closeStack;
  final closed = close.then<void>(
    (_) {
      completed = true;
    },
    onError: (Object error, StackTrace stack) {
      closeError = error;
      closeStack = stack;
      completed = true;
    },
  );
  for (var turn = 0; turn < 8 && !completed; turn++) {
    // StreamSubscription.cancel may return a cached completed Future from
    // outside FakeAsync. Drain that zone without awaiting the close there;
    // its next continuation can still need the owning fake microtask queue.
    await tester.runAsync(() async {});
    await tester.pump();
  }
  expect(
    completed,
    isTrue,
    reason: '$description did not complete within eight fake-clock pumps.',
  );
  await closed;
  if (closeError != null) {
    Error.throwWithStackTrace(closeError!, closeStack!);
  }
}
