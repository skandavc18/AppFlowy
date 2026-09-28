import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/shared/document_viewer/native_file_page_scroll.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('forward consumes header first; reverse waits for actual body ACK',
      () async {
    var header = 0.0;
    final events = <String>[];
    final replies = <Completer<double>>[];
    final dispatcher = NativeFilePageScrollDispatcher(
      isCurrent: () => true,
      moveHeader: (delta) {
        events.add('header:$delta');
        final next = (header + delta).clamp(0.0, 100.0);
        final used = next - header;
        header = next;
        return used;
      },
      consumeBody: (delta, _) {
        events.add('body:$delta');
        final reply = Completer<double>();
        replies.add(reply);
        return reply.future.then(_atStart);
      },
    );
    try {
      final down = dispatcher.consumeVertical(140);
      expect(header, 100);
      expect(events, ['header:140.0', 'body:40.0']);
      replies.removeAt(0).complete(40);
      expect(await down, 140);
      events.clear();
      final up = dispatcher.consumeVertical(-70);
      expect(header, 100, reason: 'No speculative reverse header movement');
      expect(events, ['body:-70.0']);
      replies.removeAt(0).complete(-40);
      expect(await up, -70);
      expect(header, 70);
      expect(events, ['body:-70.0', 'header:-30.0']);
    } finally {
      dispatcher.dispose();
      for (final reply in replies) {
        if (!reply.isCompleted) reply.complete(0);
      }
    }
  });

  testWidgets('deadline quarantines true in-flight slot; late ACK cannot apply',
      (tester) async {
    var headers = 0;
    final calls = <Completer<double>>[];
    final dispatcher = NativeFilePageScrollDispatcher(
      deadline: const Duration(milliseconds: 20),
      capacity: 2,
      isCurrent: () => true,
      moveHeader: (_) {
        headers++;
        return 0;
      },
      consumeBody: (_, __) {
        final call = Completer<double>();
        calls.add(call);
        return call.future.then(_atStart);
      },
    );
    try {
      final old = dispatcher.consumeVertical(-20);
      final queued = dispatcher.consumeVertical(-10);
      await tester.pump(const Duration(milliseconds: 21));
      expect(await old, isNull);
      expect(await queued, isNull);
      expect(dispatcher.inFlight, isTrue);
      expect(dispatcher.pendingCount, 0);
      final next = dispatcher.consumeVertical(-5);
      await tester.pump();
      expect(calls, hasLength(1));
      calls.first.complete(0);
      await tester.pump();
      expect(headers, 0);
      expect(calls, hasLength(2));
      calls.last.complete(-5);
      await tester.pump();
      expect(await next, -5);
      expect(headers, 1); // verified zero residual, not the old -20
    } finally {
      dispatcher.dispose();
      for (final call in calls) {
        if (!call.isCompleted) call.complete(0);
      }
      await tester.pump();
    }
  });

  testWidgets('cancel/navigation/dispose discard pending and delayed replies',
      (tester) async {
    for (final action in ['cancel', 'navigation', 'dispose']) {
      var current = true;
      var header = 100.0;
      final ack = Completer<double>();
      final dispatcher = NativeFilePageScrollDispatcher(
        isCurrent: () => current,
        moveHeader: (delta) {
          header += delta;
          return delta;
        },
        consumeBody: (_, __) => ack.future.then(_atStart),
      );
      try {
        final result = dispatcher.consumeVertical(-40);
        if (action == 'cancel') dispatcher.cancel();
        if (action == 'navigation') {
          current = false;
          dispatcher.cancel();
        }
        if (action == 'dispose') dispatcher.dispose();
        ack.complete(0);
        await tester.pump();
        expect(await result, isNull, reason: action);
        expect(header, 100, reason: action);
      } finally {
        dispatcher.dispose();
        if (!ack.isCompleted) ack.complete(0);
        await tester.pump();
      }
    }
  });

  testWidgets('bounded queue rejects overflow without releasing native work',
      (tester) async {
    final ack = Completer<double>();
    var calls = 0;
    final dispatcher = NativeFilePageScrollDispatcher(
      capacity: 2,
      isCurrent: () => true,
      moveHeader: (_) => 0,
      consumeBody: (_, __) {
        calls++;
        return ack.future.then(_atStart);
      },
    );
    try {
      final running = dispatcher.consumeVertical(-1);
      final one = dispatcher.consumeVertical(-1);
      final two = dispatcher.consumeVertical(-1);
      expect(await dispatcher.consumeVertical(-1), isNull);
      expect(dispatcher.pendingCount, 2);
      expect(calls, 1);
      dispatcher.cancel();
      ack.complete(-1);
      await tester.pump();
      expect(await running, isNull);
      expect(await one, isNull);
      expect(await two, isNull);
      expect(calls, 1);
    } finally {
      dispatcher.dispose();
      if (!ack.isCompleted) ack.complete(0);
      await tester.pump();
    }
  });

  for (final bad in [double.nan, double.infinity, 1.0, -100.0]) {
    test('invalid ACK $bad never reveals header', () async {
      var headerCalls = 0;
      final dispatcher = NativeFilePageScrollDispatcher(
        isCurrent: () => true,
        moveHeader: (_) {
          headerCalls++;
          return 0;
        },
        consumeBody: (_, __) async => _atStart(bad),
      );
      try {
        expect(await dispatcher.consumeVertical(-10), isNull);
        expect(headerCalls, 0);
      } finally {
        dispatcher.dispose();
      }
    });
  }

  test('rounded reverse ACK is actual travel, not a top boundary', () async {
    final headerMoves = <double>[];
    var travel = const NativeFilePageBodyTravel(-0.8, atStart: false);
    final dispatcher = NativeFilePageScrollDispatcher(
      devicePixelRatio: 1.25,
      isCurrent: () => true,
      moveHeader: (delta) {
        headerMoves.add(delta);
        return delta;
      },
      consumeBody: (_, __) async => travel,
    );
    try {
      expect(await dispatcher.consumeVertical(-1), -0.8);
      expect(headerMoves, isEmpty);
      expect(dispatcher.epoch, 0);
      travel = const NativeFilePageBodyTravel(0, atStart: false);
      expect(await dispatcher.consumeVertical(-0.01), 0);
      expect(headerMoves, isEmpty);
      travel = const NativeFilePageBodyTravel(-0.8, atStart: true);
      expect(await dispatcher.consumeVertical(-1), -1);
      expect(headerMoves.single, closeTo(-0.2, 1e-9));
    } finally {
      dispatcher.dispose();
    }
  });

  test('one physical pixel rounding allowance never invents requested travel',
      () async {
    for (final dpr in [1.0, 1.25, 2.0]) {
      final headers = <double>[];
      var actual = -1 / dpr;
      final dispatcher = NativeFilePageScrollDispatcher(
        devicePixelRatio: dpr,
        isCurrent: () => true,
        moveHeader: (delta) {
          headers.add(delta);
          return delta;
        },
        consumeBody: (_, __) async =>
            NativeFilePageBodyTravel(actual, atStart: true),
      );
      try {
        expect(await dispatcher.consumeVertical(-0.01), actual);
        expect(headers, [0.0], reason: 'Never correct the header forwards');
        expect(dispatcher.epoch, 0);
        actual = -(1 / dpr + 0.02);
        expect(await dispatcher.consumeVertical(-0.01), isNull);
        expect(headers, [0.0], reason: 'Over-budget ACK is still invalid');
      } finally {
        dispatcher.dispose();
      }
    }
  });

  testWidgets(
      'default 250ms deadline keeps a fractional native slot quarantined',
      (tester) async {
    final calls = <Completer<NativeFilePageBodyTravel>>[];
    final dispatcher = NativeFilePageScrollDispatcher(
      devicePixelRatio: 1.25,
      isCurrent: () => true,
      moveHeader: (_) => 0,
      consumeBody: (_, __) {
        final call = Completer<NativeFilePageBodyTravel>();
        calls.add(call);
        return call.future;
      },
    );
    try {
      final old = dispatcher.consumeVertical(-0.01);
      var finished = false;
      unawaited(old.then((_) {
        finished = true;
      }));
      await tester.pump(const Duration(milliseconds: 249));
      expect(finished, isFalse);
      await tester.pump(const Duration(milliseconds: 1));
      expect(await old, isNull);
      expect(dispatcher.inFlight, isTrue);
      final next = dispatcher.consumeVertical(-0.02);
      expect(calls, hasLength(1));
      calls.first
          .complete(const NativeFilePageBodyTravel(-0.8, atStart: false));
      await tester.pump();
      expect(calls, hasLength(2));
      calls.last.complete(const NativeFilePageBodyTravel(0, atStart: false));
      await tester.pump();
      expect(await next, 0);
      expect(dispatcher.inFlight, isFalse);
    } finally {
      dispatcher.dispose();
      for (final call in calls) {
        if (!call.isCompleted)
          call.complete(const NativeFilePageBodyTravel(0, atStart: false));
      }
      await tester.pump();
    }
  });

  test('production nativeScript DOM fractional DPR and nested boundary cases',
      () async {
    // Uses the existing fixture-local jsdom installation. No downloads and no
    // native fixture changes. The short bootstrap avoids Windows argv limits.
    final process = await Process.start('node', [
      '-e',
      r'''
require('node:stream/consumers').text(process.stdin).then(text => {
  const payload = JSON.parse(text);
  return new Function('require', 'payload', payload.fixture)(require, payload);
}).catch(error => { console.error(error); process.exitCode = 1; });
'''
    ]);
    final output = process.stdout.transform(utf8.decoder).join();
    final errors = process.stderr.transform(utf8.decoder).join();
    Future<(int, String, String)> execute() async {
      process.stdin.write(jsonEncode({
        'script': buildNativeFilePageScrollScript('fractional',
            devicePixelRatio: 1.25),
        'friction': const PremiumScrollPhysicsConfig().friction,
        'fixture': _nativeScriptDomFixture,
      }));
      await process.stdin.close();
      return (await process.exitCode, await output, await errors);
    }

    try {
      final (exit, stdout, stderr) =
          await execute().timeout(const Duration(seconds: 20));
      expect(exit, 0, reason: '$stdout\n$stderr');
    } finally {
      process.kill();
    }
  }, timeout: const Timeout(Duration(seconds: 30)));
}

// Existing dispatcher cases model a body whose partial ACK is a real boundary.
NativeFilePageBodyTravel _atStart(double actual) =>
    NativeFilePageBodyTravel(actual, atStart: true);

// Real DOM/event dispatch plus a deterministic scroll/layout seam (jsdom does
// not lay out or scroll). No copy of the production movement/gesture engine.
const _nativeScriptDomFixture = r'''
return (async () => {
  const assert = require('node:assert/strict');
  const localRequire = require('node:module').createRequire(
    require('node:path').resolve('test/unit_test/shared/fixtures/webview_find_dom.cjs'));
  const { JSDOM } = localRequire('jsdom');
  const near = (actual, expected) => assert.ok(Math.abs(actual - expected) < 1e-8,
    `${actual} != ${expected}`);
  const settle = async () => { for (let i = 0; i < 8; i++) await Promise.resolve(); };

  function fixture({ nested = false, dpr = 1.25, rootTop = 8,
      paneTop = 8, header = 100 } = {}) {
    const dom = new JSDOM('<!doctype html><html><body><div id="pane" ' +
      'style="overflow-y:auto"><p id="text">retained <b>document</b></p></div></body></html>',
      { runScripts: 'outside-only', pretendToBeVisual: true });
    const w = dom.window, doc = w.document;
    const root = doc.documentElement, pane = doc.getElementById('pane');
    const leaf = doc.getElementById('text');
    if (!nested) pane.style.overflowY = 'visible';
    Object.defineProperty(w, 'devicePixelRatio', { value: dpr });
    Object.defineProperty(w, 'innerHeight', { value: 200 });
    Object.defineProperty(doc, 'scrollingElement', { value: root });
    let hit = leaf, picks = 0, styles = 0;
    doc.elementFromPoint = () => { picks++; return hit; };
    const originalStyle = w.getComputedStyle.bind(w);
    w.getComputedStyle = node => { styles++; return originalStyle(node); };
    const moves = [], requests = [], cancellations = [], replies = [];
    const frames = new Map();
    let nextFrame = 1, held = null, holdNext = false;
    w.requestAnimationFrame = callback => {
      const id = nextFrame++; frames.set(id, callback); return id;
    };
    w.cancelAnimationFrame = id => frames.delete(id);
    function scroller(node, initial) {
      let top = initial;
      Object.defineProperties(node, {
        scrollHeight: { value: 1200 }, clientHeight: { value: 200 },
        scrollWidth: { value: 100 }, clientWidth: { value: 100 },
        scrollTop: { get: () => top },
      });
      node.scrollBy = options => {
        assert.equal(options.behavior, 'instant');
        assert.equal(options.left, 0);
        const before = top;
        top = Math.max(0, Math.min(1000, Math.round((top + options.top) * dpr) / dpr));
        moves.push({ node, requested: options.top, actual: top - before });
      };
    }
    scroller(root, rootTop);
    scroller(pane, paneTop);
    let runtime;
    // Header transport seam only. Actual DOM consumption and atStart come
    // from production; Dart's dispatcher and protocol validation have their
    // own tests above and in the widget suite.
    function answer(id, generation, delta) {
      const before = header;
      if (delta > 0) header = Math.min(100, header + delta);
      const remaining = delta - (header - before);
      const body = runtime.consumeVertical(id, generation, remaining, Date.now() + 250);
      if (!body) return null;
      assert.equal(typeof body.actual, 'number');
      assert.equal(typeof body.atStart, 'boolean');
      if (delta < 0 && body.atStart) {
        header = Math.max(0, header + Math.min(0, remaining - body.actual));
      }
      const reply = { actual: body.actual + header - before, headerHidden: header === 100 };
      replies.push({ ...reply, body });
      return reply;
    }
    w.flutter_inappwebview = { callHandler(name, id, generation, delta, action) {
      assert.equal(name, 'appflowyFilePageScroll');
      if (action === 'cancel') { cancellations.push(generation); return Promise.resolve(null); }
      requests.push({ id, generation, delta });
      if (holdNext) {
        holdNext = false;
        return new Promise(resolve => { held = () => resolve(answer(id, generation, delta)); });
      }
      return Promise.resolve(answer(id, generation, delta));
    } };
    assert.equal(w.eval(payload.script), true);
    runtime = w.__appflowyFilePageScroll;
    return {
      w, root, pane, moves, requests, replies, cancellations, runtime, frames,
      get header() { return header; }, get picks() { return picks; },
      get styles() { return styles; },
      wheel(deltaY, options = {}) {
        const event = new w.WheelEvent('wheel', { deltaY, clientX: 20, clientY: 40,
          bubbles: true, cancelable: true, ...options });
        leaf.dispatchEvent(event); return event;
      },
      touch(type, x, y, at, count = 1) {
        const event = new w.Event(type, { bubbles: true, cancelable: true });
        Object.defineProperties(event, {
          touches: { value: Array.from({length: count}, () => ({ clientX: x, clientY: y })) },
          timeStamp: { value: at },
        });
        leaf.dispatchEvent(event); return event;
      },
      frame(time) {
        const callbacks = [...frames.values()]; frames.clear();
        for (const callback of callbacks) callback(time);
      },
      hold() { holdNext = true; },
      finish() { const complete = held; held = null; complete?.(); },
      choose(node) { hit = node; },
      close() { runtime.dispose(); held?.(); w.close(); },
    };
  }

  let f = fixture();
  try {
    const generation = f.runtime.snapshot().gesture + 1;
    for (let i = 0; i < 16; i++) {
      assert.equal(f.wheel(-0.1).defaultPrevented, true);
      await settle();
      assert.equal(f.runtime.snapshot().gesture, generation, 'rounding must not cancel');
      assert.equal(f.runtime.snapshot().busy, false);
      assert.equal(f.runtime.snapshot().pending, 0, 'no self-retrying fractional queue');
      assert.equal(f.header, 100, 'interior rounding must never expose chrome');
    }
    near(f.root.scrollTop, 6.4);
    near(f.replies.reduce((sum, reply) => sum + reply.body.actual, 0), -1.6);
    assert.ok(f.replies.some(reply => reply.actual === 0));
    assert.ok(f.replies.some(reply => reply.actual < -0.1));
    assert.ok(f.requests.length < 16, 'credit must not be replayed in reverse');
    assert.equal(f.cancellations.length, 1);
    assert.equal(f.picks, 1, 'same gesture never rescans DOM');
    assert.ok(f.moves.every(move => move.requested < 0));
  } finally { f.close(); }

  f = fixture();
  try {
    f.root.scrollBy = () => {}; // no ACK of a boundary: an interior cannot move
    f.wheel(-10); await settle();
    assert.equal(f.header, 100);
    assert.equal(f.requests.length, 1, 'no self-retrying transport');
    assert.equal(f.runtime.snapshot().pending, 0);
    assert.equal(f.runtime.snapshot().busy, false);
    assert.equal(f.runtime.snapshot().gesture, 2, 'large interior shortfall is not rounding');
    assert.equal(f.frames.size, 0);
  } finally { f.close(); }

  f = fixture({ nested: true });
  try {
    f.wheel(-1); await settle();
    near(f.pane.scrollTop, 7.2);
    near(f.root.scrollTop, 8);
    assert.equal(f.moves.filter(move => move.node === f.root).length, 0,
      'interior fractional residual belongs to the pane, not its ancestor');
    f.wheel(-7.3); await settle();
    near(f.pane.scrollTop, 0); near(f.root.scrollTop, 8);
    assert.equal(f.replies.at(-1).body.atStart, false);
    assert.equal(f.header, 100);
    f.wheel(-8.7); await settle();
    near(f.root.scrollTop, 0); near(f.header, 99);
    assert.equal(f.replies.at(-1).body.atStart, true);
    near(f.replies.reduce((sum, reply) => sum + reply.actual, 0), -17);
  } finally { f.close(); }

  f = fixture({ nested: true });
  try {
    f.wheel(-0.5); await settle();
    near(f.pane.scrollTop, 7.2); near(f.root.scrollTop, 8);
    assert.equal(f.moves.length, 1, 'over-rounding must not move any ancestor forward');
    near(f.replies[0].actual, -0.8);
    f.wheel(-0.1); await settle();
    assert.equal(f.moves.length, 1, 'small next input pays back rounded-up credit');
  } finally { f.close(); }

  for (const dpr of [1.25, 2.5]) {
    const scale = dpr / 1.25;
    f = fixture({ dpr, rootTop: 0 });
    try {
      f.wheel(1, { deltaMode: 1 }); await settle();
      near(f.requests.at(-1).delta, 16 * scale);
      near(f.root.scrollTop, 16);
      f.wheel(1, { deltaMode: 2 }); await settle();
      near(f.requests.at(-1).delta, 200 * scale);
      near(f.root.scrollTop, 216);
      const count = f.requests.length;
      for (const options of [{ ctrlKey: true }, { metaKey: true }, { shiftKey: true },
        { deltaX: 5 }, { cancelable: false }]) {
        assert.equal(f.wheel(1, options).defaultPrevented, false);
        await settle();
        assert.equal(f.requests.length, count);
      }
    } finally { f.close(); }

    f = fixture({ dpr, rootTop: 2.56 });
    try {
      f.touch('touchstart', 20, 100, 0);
      f.touch('touchmove', 20, 102, 10); await settle();
      const styles = f.styles;
      f.touch('touchend', 20, 102, 11, 0);
      f.frame(10); f.frame(26); await settle();
      const delta = -200 / payload.friction * (1 - Math.exp(-payload.friction * 0.016));
      assert.equal(f.requests.length, 2, 'one body-to-header coast transfer');
      near(f.requests[1].delta, (delta + 0.56) * scale);
      near(f.header, 100 + (delta + 0.56) * scale);
      near(f.root.scrollTop, 0);
      assert.equal(f.frames.size, 0);
      assert.equal(f.styles, styles, 'coast never repeats target/style selection');
    } finally { f.close(); }
  }

  f = fixture();
  try {
    f.hold(); f.wheel(-1);
    const old = f.runtime.snapshot().gesture;
    for (let i = 0; i < 100; i++) f.wheel(-40);
    assert.equal(f.requests.length, 1);
    assert.equal(f.runtime.snapshot().pending, -1600);
    f.touch('touchstart', 20, 100, 0);
    const current = f.runtime.snapshot().gesture;
    assert.ok(current > old);
    f.runtime.cancel('fractional', old); // delayed app-side stop for the old pan
    assert.equal(f.runtime.snapshot().gesture, current);
    f.touch('touchmove', 20, 102, 10);
    assert.equal(f.requests.length, 1, 'cancel does not release actual transport slot');
    assert.equal(f.runtime.snapshot().busy, true);
    f.finish(); await settle();
    assert.equal(f.requests.length, 2);
    assert.equal(f.requests[1].generation, current);
    assert.equal(f.runtime.snapshot().busy, false);
    const before = f.root.scrollTop;
    assert.equal(f.runtime.consumeVertical('fractional', old, -10, Date.now() + 250), null);
    assert.equal(f.runtime.consumeVertical('fractional', current, -10, Date.now() - 1), null);
    near(f.root.scrollTop, before);
    f.touch('touchmove', 20, 105, 20, 2); await settle();
    assert.ok(f.runtime.snapshot().gesture > current, 'pinch stays native');
  } finally { f.close(); }
})();
''';
