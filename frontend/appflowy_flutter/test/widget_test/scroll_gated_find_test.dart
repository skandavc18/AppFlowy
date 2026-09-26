import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/scrolling/scroll_gesture_gate.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _pageKey = ValueKey('gated-find-page');
const _viewerKey = ValueKey('gated-find-viewer');
const _hitKey = ValueKey('gated-find-content');
const _outerListenerKey = ValueKey('gated-find-outer-listener');
const _editableKey = ValueKey('gated-find-editable');
const _overlayKey = ValueKey('gated-find-overlay');
const _nativeKey = ValueKey('gated-find-native-surface');
const _queryGroupKey = ValueKey('gated-find-query-group');
const _queryActionKey = ValueKey('gated-find-query-action');
const _outsideKey = ValueKey('gated-find-outside-group');

// Pure Flutter contracts for the real gate/router; no renderer or OCR fakes.
// Theme coverage belongs to the actual spreadsheet integration fixtures.
void main() {
  _test(
      'nested blocked gates route transparent hovered content before the page',
      (tester, focus, mouse) async {
    final calls = <String>[];
    var builds = 0;
    await tester.pumpWidget(
      _app(
        _page(
          focus,
          calls,
          Center(
            child: ScrollGestureGate(
              blocked: true,
              child: ContextualFindRegion(
                onFind: () => calls.add('middle'),
                child: ContextualFindSelection(
                  isSelected: () => false,
                  child: ScrollGestureGate(
                    blocked: true,
                    child: ContextualFindRegion(
                      key: _viewerKey,
                      onFind: () => calls.add('viewer'),
                      child: Builder(
                        builder: (_) {
                          builds++;
                          // No opaque decoration or gesture target is needed
                          // for the real translucent find surfaces to route.
                          return const SizedBox(
                            key: _hitKey,
                            width: 240,
                            height: 120,
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _focus(tester, focus);
    expect(find.byType(EditableText), findsNothing);
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['page']);
    calls.clear();

    final viewer = tester.state(find.byKey(_viewerKey));
    final content = tester.element(find.byKey(_hitKey));
    final beforeBuilds = builds;
    await mouse.moveTo(tester.getCenter(find.byKey(_hitKey)));
    await tester.pump();
    expect(calls, isEmpty);
    expect(builds, beforeBuilds);
    expect(FocusManager.instance.primaryFocus, same(focus));
    expect(tester.state(find.byKey(_viewerKey)), same(viewer));
    expect(tester.element(find.byKey(_hitKey)), same(content));

    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['viewer']); // Neither parent nor its local shortcut ran.
    expect(builds, beforeBuilds);
    expect(focus.hasPrimaryFocus, isTrue);
  });

  _test('Find inspection leaves blocked taps working and scroll delivery gated',
      (tester, focus, mouse) async {
    final calls = <String>[];
    final blocked = ValueNotifier(true);
    final innerScrolls = <Offset>[];
    final outerScrolls = <Offset>[];
    var taps = 0;
    var hovers = 0;
    addTearDown(blocked.dispose);
    await tester.pumpWidget(
      _app(
        _page(
          focus,
          calls,
          Center(
            child: Listener(
              key: _outerListenerKey,
              // Find's non-opaque MouseRegion returns false from hitTest even
              // with child hits. A deferToChild observer would not be added.
              behavior: HitTestBehavior.translucent,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent) {
                  outerScrolls.add(event.scrollDelta);
                }
              },
              child: ValueListenableBuilder<bool>(
                valueListenable: blocked,
                builder: (_, value, child) => _gates(child!, blocked: value),
                child: ContextualFindRegion(
                  key: _viewerKey,
                  onFind: () => calls.add('viewer'),
                  child: Listener(
                    key: _hitKey,
                    onPointerHover: (_) => hovers++,
                    onPointerSignal: (event) {
                      if (event is PointerScrollEvent) {
                        innerScrolls.add(event.scrollDelta);
                      }
                    },
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => taps++,
                      child: const SizedBox(width: 240, height: 120),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _focus(tester, focus);
    final content = tester.element(find.byKey(_hitKey));
    final innerTarget =
        tester.renderObject<RenderPointerListener>(find.byKey(_hitKey));
    final outerTarget = tester.renderObject<RenderPointerListener>(
      find.byKey(_outerListenerKey),
    );
    final point = tester.getCenter(find.byKey(_hitKey));
    await mouse.moveTo(point);
    await tester.pump();
    final beforeHovers = hovers;
    expect(beforeHovers, greaterThan(0));
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['viewer']);
    expect(
      hovers,
      beforeHovers,
      reason: 'A Find lookup must not redispatch hover.',
    );
    expect(taps, 0);
    expect(innerScrolls, isEmpty);
    expect(outerScrolls, isEmpty);
    _wrappedHit(tester, point, innerTarget);
    expect(
      tester.hitTestOnBinding(point).path.where(
            (entry) => identical(entry.target, outerTarget),
          ),
      hasLength(1),
      reason: 'The outer observer must be on the real, unfiltered event path.',
    );

    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        viewId: tester.view.viewId,
        scrollDelta: const Offset(0, 40),
      ),
    );
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(innerScrolls, isEmpty);
    expect(outerScrolls, [const Offset(0, 40)]);
    expect(taps, 1);
    expect(focus.hasPrimaryFocus, isTrue);

    blocked.value = false;
    await tester.pump();
    expect(tester.element(find.byKey(_hitKey)), same(content));
    expect(tester.renderObject(find.byKey(_hitKey)), same(innerTarget));
    expect(
      tester.hitTestOnBinding(point).path.map((entry) => entry.target),
      contains(same(innerTarget)),
    );
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: point,
        viewId: tester.view.viewId,
        scrollDelta: const Offset(0, 24),
      ),
    );
    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(innerScrolls, [const Offset(0, 24)]);
    expect(outerScrolls, [const Offset(0, 40), const Offset(0, 24)]);
    expect(taps, 2);
  });

  _test('unblocked targets are identical and nested filters unwrap read-only',
      (tester, focus, mouse) async {
    final blocked = ValueNotifier(false);
    final calls = <String>[];
    var downs = 0;
    addTearDown(blocked.dispose);
    await tester.pumpWidget(
      _app(
        _page(
          focus,
          calls,
          Center(
            child: ValueListenableBuilder<bool>(
              valueListenable: blocked,
              builder: (_, value, child) => _gates(child!, blocked: value),
              child: ContextualFindRegion(
                onFind: () => calls.add('viewer'),
                child: Listener(
                  key: _hitKey,
                  behavior: HitTestBehavior.opaque,
                  onPointerDown: (_) => downs++,
                  child: const SizedBox(width: 240, height: 120),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _focus(tester, focus);
    final point = tester.getCenter(find.byKey(_hitKey));
    final target =
        tester.renderObject<RenderPointerListener>(find.byKey(_hitKey));
    final raw = tester.hitTestOnBinding(point);
    final targets = raw.path.map((entry) => entry.target).toList();
    expect(targets, contains(same(target)));
    expect(
      raw.path.singleWhere((entry) => identical(entry.target, target)),
      isA<BoxHitTestEntry>(),
    );
    for (final entry in raw.path) {
      expect(
        ScrollGestureGate.originalTarget(entry.target),
        same(entry.target),
      );
    }

    blocked.value = true;
    await tester.pump();
    expect(tester.renderObject(find.byKey(_hitKey)), same(target));
    final wrapped = _wrappedHit(tester, point, target);
    final filter = wrapped.target;
    expect(wrapped, isNot(isA<BoxHitTestEntry>()));
    expect(ScrollGestureGate.originalTarget(filter), same(target));
    expect(
      ScrollGestureGate.originalTarget(
        ScrollGestureGate.originalTarget(filter),
      ),
      same(target),
    );
    expect(
      wrapped.target,
      same(filter),
      reason: 'Keep the dispatch filter intact.',
    );
    expect(downs, 0);
    expect(calls, isEmpty);

    blocked.value = false;
    await tester.pump();
    final restored = tester.hitTestOnBinding(point).path.toList();
    expect(restored, hasLength(targets.length));
    for (var index = 0; index < restored.length; index++) {
      expect(restored[index].target, same(targets[index]));
      expect(
        ScrollGestureGate.originalTarget(restored[index].target),
        same(restored[index].target),
      );
    }
  });

  _test(
      'an opaque overlay inside the gates blocks selected and last-owner fallback',
      (tester, focus, mouse) async {
    final calls = <String>[];
    final covered = ValueNotifier(false);
    addTearDown(covered.dispose);
    await tester.pumpWidget(
      _app(
        _localFind(
          calls,
          Focus(
            focusNode: focus,
            child: _gates(
              ValueListenableBuilder<bool>(
                valueListenable: covered,
                builder: (_, value, child) => Stack(
                  fit: StackFit.expand,
                  children: [
                    child!,
                    if (value)
                      const Positioned.fill(
                        child: Listener(
                          key: _overlayKey,
                          behavior: HitTestBehavior.opaque,
                          child: SizedBox.expand(),
                        ),
                      ),
                  ],
                ),
                child: ContextualFindRegion(
                  key: _pageKey,
                  onFind: () => calls.add('page'),
                  child: Center(
                    child: ContextualFindSelection(
                      isSelected: () => true,
                      child: ContextualFindRegion(
                        key: _viewerKey,
                        onFind: () => calls.add('viewer'),
                        child: const Listener(
                          key: _hitKey,
                          behavior: HitTestBehavior.translucent,
                          child: SizedBox(width: 240, height: 120),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await _focus(tester, focus);
    final viewer = tester.state(find.byKey(_viewerKey));
    final target =
        tester.renderObject<RenderPointerListener>(find.byKey(_hitKey));
    final point = tester.getCenter(find.byKey(_hitKey));
    await mouse.moveTo(point);
    await tester.pump();
    _wrappedHit(tester, point, target);
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['viewer']);

    covered.value = true;
    await tester.pump(); // Keep the pointer stationary over the covered viewer.
    expect(tester.state(find.byKey(_viewerKey)), same(viewer));
    expect(tester.getRect(find.byKey(_hitKey)).contains(point), isTrue);
    _wrappedHit(
      tester,
      point,
      tester.renderObject<RenderPointerListener>(find.byKey(_overlayKey)),
    );
    expect(
      tester.hitTestOnBinding(point).path.map(
            (entry) => ScrollGestureGate.originalTarget(entry.target),
          ),
      isNot(contains(same(target))),
    );
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['viewer', 'local']);
    expect(focus.hasPrimaryFocus, isTrue);

    covered.value = false;
    await tester.pump();
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['viewer', 'local', 'viewer']);
    expect(tester.state(find.byKey(_viewerKey)), same(viewer));
  });

  _test(
      'gated EditableText retains local Find until its nearest region opts in',
      (tester, focus, mouse) async {
    final calls = <String>[];
    final owned = ValueNotifier(false);
    final text = TextEditingController(text: 'unsaved editable content');
    addTearDown(owned.dispose);
    addTearDown(text.dispose);
    await tester.pumpWidget(
      _app(
        _localFind(
          calls,
          ContextualFindRegion(
            key: _pageKey,
            onFind: () => calls.add('page'),
            findInEditable: true, // An ancestor opt-in cannot be borrowed.
            child: Center(
              child: _gates(
                ValueListenableBuilder<bool>(
                  valueListenable: owned,
                  builder: (_, value, child) => ContextualFindRegion(
                    key: _viewerKey,
                    onFind: () => calls.add('viewer'),
                    findInEditable: value,
                    child: child!,
                  ),
                  child: SizedBox(width: 300, child: _editable(focus, text)),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<EditableTextState>(find.byKey(_editableKey));
    final point = state.renderEditable.localToGlobal(
      state.renderEditable.size.center(Offset.zero),
    );
    await mouse.moveTo(point);
    await tester.pump();
    _wrappedHit(tester, point, state.renderEditable);
    expect(focus.hasFocus, isFalse);
    expect(calls, isEmpty);
    final page = tester.element(find.byKey(_pageKey));
    // Check RenderEditable hover before native editable focus can short-circuit
    // the router. This would otherwise pass even with the old wrapped lookup.
    expect(ContextualFindRegion.dispatch(page), isFalse);
    owned.value = true;
    await tester.pump();
    expect(ContextualFindRegion.dispatch(page), isTrue);
    expect(calls, ['viewer']);

    calls.clear();
    owned.value = false;
    await tester.pump();
    await _focus(tester, focus);
    final draft = text.value;
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['local']);
    owned.value = true;
    await tester.pump();
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['local', 'viewer']);
    owned.value = false;
    await tester.pump();
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['local', 'viewer', 'local']);
    expect(
      tester.state<EditableTextState>(find.byKey(_editableKey)),
      same(state),
    );
    expect(text.value, draft);
    expect(focus.hasPrimaryFocus, isTrue);
  });

  _test(
      'gated platform surfaces and explicit native opt-outs retain local Find',
      (tester, focus, mouse) async {
    final calls = <String>[];
    final mode = ValueNotifier(_NativeMode.platform);
    final controller = _NativeController();
    addTearDown(mode.dispose);
    await tester.pumpWidget(
      _app(
        _page(
          focus,
          calls,
          Center(
            child: _gates(
              ValueListenableBuilder<_NativeMode>(
                valueListenable: mode,
                builder: (_, value, __) => ContextualFindRegion(
                  key: _viewerKey,
                  onFind: () => calls.add('viewer'),
                  useNativeFind: value == _NativeMode.optedOut,
                  child: SizedBox(
                    width: 240,
                    height: 120,
                    child: value == _NativeMode.platform
                        ? PlatformViewSurface(
                            key: _nativeKey,
                            controller: controller,
                            hitTestBehavior: PlatformViewHitTestBehavior.opaque,
                            gestureRecognizers: const <Factory<
                                OneSequenceGestureRecognizer>>{},
                          )
                        : const Listener(
                            key: _hitKey,
                            behavior: HitTestBehavior.opaque,
                            child: SizedBox.expand(),
                          ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // Focus belongs to Flutter page content, not to a native leaf. Native
    // exclusion must therefore come from the real hover hit itself.
    await _focus(tester, focus);
    final viewer = tester.state(find.byKey(_viewerKey));
    final point = tester.getCenter(find.byKey(_nativeKey));
    final surface = tester.renderObject<PlatformViewRenderBox>(
      find.byKey(_nativeKey),
    );
    await mouse.moveTo(point);
    await tester.pump();
    // PlatformViewRenderBox implements MouseTrackerAnnotation in this SDK.
    // The gate must keep its identity, not put an event filter in its place.
    expect(surface, isA<MouseTrackerAnnotation>());
    final nativeHits = tester.hitTestOnBinding(point).path.where(
          (entry) => identical(
            ScrollGestureGate.originalTarget(entry.target),
            surface,
          ),
        );
    expect(nativeHits, hasLength(1));
    final nativeHit = nativeHits.single;
    expect(nativeHit.target, same(surface));
    expect(nativeHit, isA<BoxHitTestEntry>());
    expect(
      (nativeHit as BoxHitTestEntry).localPosition,
      surface.globalToLocal(point),
    );
    expect(
      tester.widget<ContextualFindRegion>(find.byKey(_viewerKey)).useNativeFind,
      isFalse,
    );
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['local']);

    mode.value = _NativeMode.optedOut;
    await tester.pump();
    expect(find.byType(PlatformViewSurface), findsNothing);
    expect(surface.attached, isFalse);
    expect(tester.state(find.byKey(_viewerKey)), same(viewer));
    final flutterTarget =
        tester.renderObject<RenderPointerListener>(find.byKey(_hitKey));
    _wrappedHit(tester, point, flutterTarget);
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['local', 'local']);

    mode.value = _NativeMode.flutter;
    await tester.pump();
    expect(tester.state(find.byKey(_viewerKey)), same(viewer));
    expect(tester.renderObject(find.byKey(_hitKey)), same(flutterTarget));
    _wrappedHit(tester, point, flutterTarget);
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['local', 'local', 'viewer']);
    expect(focus.hasPrimaryFocus, isTrue);
  });

  _test(
      'external gated query keeps Find ownership and inside/outside tap identity',
      (tester, focus, mouse) async {
    final calls = <String>[];
    final query = TextEditingController(text: 'retained query');
    var outsideCalls = 0;
    var actionTaps = 0;
    var outsideTaps = 0;
    addTearDown(query.dispose);
    await tester.pumpWidget(
      _app(
        _localFind(
          calls,
          ContextualFindRegion(
            key: _pageKey,
            onFind: () => calls.add('page'),
            child: _gates(
              Column(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ContextualFindRegion(
                    key: _viewerKey,
                    onFind: () => calls.add('viewer'),
                    findOpen: true,
                    findFocusNode: focus,
                    child: const SizedBox(width: 300, height: 100),
                  ),
                  // The query and its right-hand action are siblings of the
                  // viewer, not searchable content inside that region.
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TapRegion(
                        key: _queryGroupKey,
                        groupId: query,
                        onTapOutside: (_) => outsideCalls++,
                        child: SizedBox(
                          width: 260,
                          child: _editable(focus, query),
                        ),
                      ),
                      const SizedBox(width: 16),
                      TapRegion(
                        key: _queryActionKey,
                        groupId: query,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => actionTaps++,
                          child: const SizedBox(width: 64, height: 48),
                        ),
                      ),
                    ],
                  ),
                  GestureDetector(
                    key: _outsideKey,
                    behavior: HitTestBehavior.opaque,
                    onTap: () => outsideTaps++,
                    child: const SizedBox(width: 100, height: 48),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    await _focus(tester, focus);
    final state = tester.state<EditableTextState>(find.byKey(_editableKey));
    final draft = query.value;
    final point = state.renderEditable.localToGlobal(
      state.renderEditable.size.center(Offset.zero),
    );
    expect(
      find.descendant(
        of: find.byKey(_viewerKey),
        matching: find.byKey(_editableKey),
      ),
      findsNothing,
    );
    expect(tester.getRect(find.byKey(_viewerKey)).contains(point), isFalse);
    _wrappedHit(tester, point, state.renderEditable);
    final group =
        tester.renderObject<RenderTapRegion>(find.byKey(_queryGroupKey));
    expect(group.groupId, same(query));
    expect(
      tester.hitTestOnBinding(point).path.map((entry) => entry.target),
      contains(same(group)),
    );
    expect(ScrollGestureGate.originalTarget(group), same(group));
    await mouse.moveTo(point);
    await tester.pump();
    expect(calls, isEmpty);
    expect(query.value, draft);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['viewer']);
    expect(query.value, draft);

    await tester.tapAt(point, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(outsideCalls, 0);
    expect(focus.hasPrimaryFocus, isTrue);
    final afterQueryTap = query.value;
    final actionPoint = tester.getCenter(find.byKey(_queryActionKey));
    final action =
        tester.renderObject<RenderTapRegion>(find.byKey(_queryActionKey));
    expect(action.groupId, same(query));
    final actionTargets = tester.hitTestOnBinding(actionPoint).path.map(
          (entry) => entry.target,
        );
    expect(actionTargets, contains(same(action)));
    expect(actionTargets, isNot(contains(same(group))));
    await tester.tapAt(actionPoint, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(actionTaps, 1);
    expect(outsideCalls, 0);
    expect(query.value, afterQueryTap);
    expect(focus.hasPrimaryFocus, isTrue);
    expect(await _ctrlF(tester), isTrue);
    expect(calls, ['viewer', 'viewer']);
    expect(
      tester.state<EditableTextState>(find.byKey(_editableKey)),
      same(state),
    );

    // tap(finder) checks raw target identity and warns on this valid filter.
    // Verify the actual wrapped hit, then dispatch the ordinary pointer event.
    final outsidePoint = tester.getCenter(find.byKey(_outsideKey));
    _wrappedHit(
      tester,
      outsidePoint,
      tester
          .renderObject<RenderSemanticsGestureHandler>(find.byKey(_outsideKey)),
    );
    await tester.tapAt(outsidePoint, kind: PointerDeviceKind.mouse);
    await tester.pump();
    expect(outsideCalls, 1);
    expect(
      outsideTaps,
      1,
      reason: 'Outside dismissal must not consume the click.',
    );
    expect(actionTaps, 1);
    expect(focus.hasFocus, isFalse); // Real EditableText outside-tap default.
    expect(query.text, draft.text);
    expect(calls, ['viewer', 'viewer']);
  });
}

Widget _app(Widget child) => MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 560, height: 360, child: child),
        ),
      ),
    );

Widget _localFind(List<String> calls, Widget child) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            calls.add('local'),
      },
      child: child,
    );

Widget _page(FocusNode focus, List<String> calls, Widget child) => _localFind(
      calls,
      ContextualFindRegion(
        key: _pageKey,
        onFind: () => calls.add('page'),
        child: Focus(focusNode: focus, child: child),
      ),
    );

Widget _gates(Widget child, {bool blocked = true}) => ScrollGestureGate(
      blocked: blocked,
      child: ScrollGestureGate(blocked: blocked, child: child),
    );

Widget _editable(FocusNode focus, TextEditingController controller) => Builder(
      builder: (context) => EditableText(
        key: _editableKey,
        focusNode: focus,
        controller: controller,
        groupId: controller,
        style: Theme.of(context).textTheme.bodyMedium!,
        cursorColor: Theme.of(context).colorScheme.primary,
        backgroundCursorColor: Theme.of(context).colorScheme.onSurface,
      ),
    );

HitTestEntry _wrappedHit(
  WidgetTester tester,
  Offset point,
  HitTestTarget target,
) {
  // Inspect only. Passing an identity-only path to dispatchEvent would bypass
  // scroll filtering and lose the original entry subtypes and transforms.
  final hits = tester.hitTestOnBinding(point).path.where(
        (entry) =>
            identical(ScrollGestureGate.originalTarget(entry.target), target),
      );
  expect(hits, hasLength(1));
  final hit = hits.single;
  expect(hit.target, isNot(same(target)));
  return hit;
}

Future<void> _focus(WidgetTester tester, FocusNode focus) async {
  focus.requestFocus();
  await tester.pump();
  await tester.pump();
  expect(focus.hasPrimaryFocus, isTrue);
}

Future<bool> _ctrlF(WidgetTester tester) async {
  var handled = false;
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
  try {
    handled = await tester.sendKeyDownEvent(LogicalKeyboardKey.keyF);
  } finally {
    try {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.keyF);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    }
  }
  await tester.pump();
  await tester.pump();
  return handled;
}

void _test(
  String name,
  Future<void> Function(WidgetTester, FocusNode, TestGesture) body,
) {
  testWidgets(
    name,
    (tester) async {
      expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
      expect(ContextualFindRegion.debugHasEarlyKeyHandler, isFalse);
      // Attach this node once: either to page Focus or to the real EditableText.
      final focus = FocusNode(debugLabel: 'Gated Find keyboard owner');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: const Offset(4, 4));
        await body(tester, focus, mouse);
        expect(tester.takeException(), isNull);
      } finally {
        try {
          await mouse.removePointer();
        } finally {
          try {
            await tester.pumpWidget(const SizedBox.shrink());
            await tester.pump();
          } finally {
            focus.dispose();
          }
        }
      }
      expect(ContextualFindRegion.debugRegisteredRegionCount, 0);
      expect(ContextualFindRegion.debugHasEarlyKeyHandler, isFalse);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 20)),
  );
}

enum _NativeMode { platform, optedOut, flutter }

class _NativeController extends Fake implements PlatformViewController {
  @override
  int get viewId => 42;

  @override
  Future<void> dispatchPointerEvent(PointerEvent event) async {}
}
