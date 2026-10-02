import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// Whether a pointer at [at] within [finder] would actually reach it.
///
/// flutter_test's `hitTestable()` and `tap()` compare RAW hit-test targets.
/// An inactive `ScrollActivationRegion` deliberately wraps its content's
/// targets so that scrolling passes through to the page while clicks are still
/// delivered — which makes those checks report a control as obscured when it
/// is not. This unwraps the gate before comparing, so it still fails for a
/// control that is genuinely covered, clipped away or ignoring pointers.
bool receivesPointer(
  WidgetTester tester,
  Finder finder, {
  Alignment at = Alignment.center,
}) {
  final element = finder.evaluate().single;
  final box = element.renderObject! as RenderBox;
  final position = box.localToGlobal(at.alongSize(box.size));
  final result = HitTestResult();
  tester.binding.hitTestInView(result, position, tester.view.viewId);
  return result.path.any(
    (entry) => ScrollGestureGate.originalTarget(entry.target) == box,
  );
}

/// Taps [finder] after proving the pointer reaches it through any scroll gate.
///
/// Use it where `tester.tap` would warn (or, with fatal hit-test warnings,
/// throw) only because the target sits in a card that has not been activated
/// for scrolling yet.
Future<void> tapReceiving(
  WidgetTester tester,
  Finder finder, {
  PointerDeviceKind kind = PointerDeviceKind.touch,
}) async {
  expect(
    receivesPointer(tester, finder),
    isTrue,
    reason: 'The control must receive the pointer at its centre.',
  );
  await tester.tapAt(tester.getCenter(finder), kind: kind);
}
