import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _modes = [
  (name: 'native/light', enabled: false, reduced: false),
  (name: 'kinetic/dark', enabled: true, reduced: false),
  (name: 'reduced motion/paper', enabled: true, reduced: true),
];

void main() {
  for (final (appearance, mode) in _modes.indexed) {
    for (final axis in Axis.values) {
      _case(
        '${mode.name}: ${axis.name} wheel and pan activation cycle',
        (tester, h) async {
          final inner = axis == Axis.vertical ? h.v[0] : h.h[0];
          final outer = axis == Axis.vertical ? h.outerV : h.outerH;
          final otherOuter = axis == Axis.vertical ? h.outerH : h.outerV;
          final otherInner = axis == Axis.vertical ? h.h[0] : h.v[0];
          final target = _key(axis == Axis.vertical ? 'v0' : 'h0');
          final delta =
              axis == Axis.vertical ? const Offset(0, 80) : const Offset(80, 0);
          expect(inner.position.maxScrollExtent, greaterThan(240));
          expect(outer.position.maxScrollExtent, greaterThan(240));
          final context = tester.element(target);
          expect(PaperTheme.isEnabled(context), appearance == 2);
          expect(
            Theme.of(context).brightness,
            appearance == 1 ? Brightness.dark : Brightness.light,
          );
          expect(
            find.descendant(
              of: _key('region0'),
              matching: find.byWidgetPredicate(
                (widget) => widget is Scrollbar || widget is RawScrollbar,
              ),
            ),
            findsNothing,
          );

          await _wheel(tester, target, delta);
          expect(outer.offset, greaterThan(0));
          expect(inner.offset, 0);
          final afterWheel = outer.offset;
          await _pan(tester, target, -delta);
          expect(outer.offset, greaterThan(afterWheel));
          expect(inner.offset, 0);
          final pageOffset = outer.offset;
          await _click(tester, _key('header0'));
          expect(inner.offset, 0,
              reason: 'Activation must not reposition content.');
          await _wheel(tester, target, delta);
          final firstInnerOffset = inner.offset;
          expect(firstInnerOffset, greaterThan(0));
          if (axis == Axis.horizontal) {
            await _wheel(tester, target, const Offset(0, 40), shift: true);
            expect(inner.offset, greaterThan(firstInnerOffset));
          }
          final beforePan = inner.offset;
          await _pan(tester, target, -delta);
          expect(inner.offset, greaterThan(beforePan));
          expect(outer.offset, pageOffset);
          expect(otherOuter.offset, 0);
          expect(otherInner.offset, 0);

          final retained = inner.offset;
          await _click(tester, _key('outside'));
          expect(inner.offset, retained);
          await _wheel(tester, target, delta);
          expect(outer.offset, greaterThan(pageOffset));
          expect(inner.offset, retained);
          expect(otherOuter.offset, 0);
          expect(otherInner.offset, 0);
        },
        enabled: mode.enabled,
        reduced: mode.reduced,
        appearance: appearance,
      );
    }
  }

  _case('a touch drag scrolls the page without activating the wrapper',
      (tester, h) async {
    await tester.drag(_key('v0'), const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(h.outerV.offset, greaterThan(0));
    expect(h.v[0].offset, 0);
    final before = h.outerV.offset;
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.outerV.offset, greaterThan(before));
    expect(h.v[0].offset, 0);
  });

  _case('hover and an actual tooltip do not activate', (tester, h) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    try {
      await mouse.moveTo(tester.getCenter(_key('header0')));
      await tester.pump(const Duration(seconds: 1));
      await tester.pumpAndSettle();
      expect(find.text('Card help 0'), findsOneWidget);
      await _wheel(tester, _key('v0'), const Offset(0, 40));
      expect(h.outerV.offset, greaterThan(0));
      expect(h.v[0].offset, 0);
    } finally {
      await mouse.removePointer();
    }
  });

  for (final press in ['drag', 'cancel', 'secondary', 'small wobble']) {
    _case('$press distinguishes a completed primary click', (tester, h) async {
      final gesture = await tester.startGesture(
        tester.getCenter(_key('header0')),
        kind: PointerDeviceKind.mouse,
        buttons: press == 'secondary' ? kSecondaryButton : kPrimaryButton,
      );
      if (press == 'cancel') {
        await gesture.cancel();
      } else {
        if (press == 'drag' || press == 'small wobble') {
          final movement = Offset(press == 'drag' ? 4 : 3, 0);
          await gesture.moveBy(movement);
          if (press == 'drag') await gesture.moveBy(-movement);
        }
        await gesture.up();
      }
      await tester.pumpAndSettle();
      await _wheel(tester, _key('v0'), const Offset(0, 40));
      expect(h.v[0].offset, press == 'small wobble' ? greaterThan(0) : 0);
      expect(h.outerV.offset, press == 'small wobble' ? 0 : greaterThan(0));
    });
  }

  _case('the first child button click fires once and enables scrolling',
      (tester, h) async {
    await _click(tester, _key('button0'));
    expect(h.taps, 1);
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.v[0].offset, greaterThan(0));
    expect(h.outerV.offset, 0);
    expect(h.taps, 1);
  });

  _case('field focus survives activation, typing and physical Backspace',
      (tester, h) async {
    await _click(tester, _key('field0'));
    expect(FocusManager.instance.primaryFocus, same(h.fields[0]));
    await tester.enterText(_key('field0'), 'ab');
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace,
        platform: 'windows');
    await tester.pump();
    expect(h.text[0].text, 'a');
    tester.testTextInput.enterText('a typed');
    await tester.pump();
    expect(h.text[0].text, 'a typed');
    expect(FocusManager.instance.primaryFocus, same(h.fields[0]));
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.v[0].offset, greaterThan(0));
    expect(h.outerV.offset, 0);
    expect(h.text[1].text, isEmpty);
  });

  _case('Tab transfers activation between regions and back to the page',
      (tester, h) async {
    h.fields[0].requestFocus();
    await tester.pumpAndSettle();
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    final retained = h.v[0].offset;
    expect(retained, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(h.buttons[1].hasPrimaryFocus, isTrue);
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.v[0].offset, retained);
    final page = h.outerV.offset;
    expect(page, greaterThan(0));
    await _wheel(tester, _key('v1'), const Offset(0, 40));
    expect(h.v[1].offset, greaterThan(0));
    expect(h.outerV.offset, page);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(h.fields[1].hasPrimaryFocus, isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pumpAndSettle();
    expect(h.outside.hasPrimaryFocus, isTrue);
    final second = h.v[1].offset;
    await _wheel(tester, _key('v1'), const Offset(0, 40));
    expect(h.outerV.offset, greaterThan(page));
    expect(h.v[1].offset, second);
  });

  _case('jumpTo and region switches retain offsets, controllers and state',
      (tester, h) async {
    final state = tester.state<ScrollableState>(
      find.descendant(of: _key('v0'), matching: find.byType(Scrollable)),
    );
    h.v[0].jumpTo(72);
    h.h[0].jumpTo(64);
    await tester.pump();
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.v[0].offset, 72);
    await _click(tester, _key('header0'));
    await _click(tester, _key('header1'));
    final before = h.outerV.offset;
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.outerV.offset, greaterThan(before));
    expect(h.v[0].offset, 72);
    expect(h.h[0].offset, 64);
    await _wheel(tester, _key('v1'), const Offset(0, 40));
    expect(h.v[1].offset, greaterThan(0));
    expect(tester.widget<ListView>(_key('v0')).controller, same(h.v[0]));
    expect(tester.widget<SingleChildScrollView>(_key('h0')).controller,
        same(h.h[0]));
    expect(
      tester.state<ScrollableState>(
        find.descendant(of: _key('v0'), matching: find.byType(Scrollable)),
      ),
      same(state),
    );
  });

  _case('only plain Escape deactivates and the outer handler still receives it',
      (tester, h) async {
    await _click(tester, _key('header0'));
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
    try {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    } finally {
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
    }
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.v[0].offset, greaterThan(0));
    expect(h.outerV.offset, 0);
    final retained = h.v[0].offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.escapes, 2);
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.outerV.offset, greaterThan(0));
    expect(h.v[0].offset, retained);
  });

  _case('deactivation cancels both inner wheel queues, not the outer activity',
      (tester, h) async {
    await _click(tester, _key('header0'));
    await _wheel(tester, _key('v0'), const Offset(0, 120), settle: false);
    await _wheel(tester, _key('h0'), const Offset(120, 0), settle: false);
    await _wheel(tester, _key('v1'), const Offset(0, 120), settle: false);
    await tester.pump(const Duration(milliseconds: 16));
    for (final controller in [h.v[0], h.h[0], h.outerV]) {
      expect(controller.position.isScrollingNotifier.value, isTrue);
    }
    final vertical = h.v[0].offset;
    final horizontal = h.h[0].offset;
    final page = h.outerV.offset;
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.v[0].offset, vertical);
    expect(h.h[0].offset, horizontal);
    expect(h.outerV.offset, greaterThan(page));
    expect(h.v[0].position.isScrollingNotifier.value, isFalse);
    expect(h.h[0].position.isScrollingNotifier.value, isFalse);
  });

  _case('deactivation cancels an actual trackpad release without resetting it',
      (tester, h) async {
    await _click(tester, _key('header0'));
    await _pan(tester, _key('v0'), const Offset(0, -80), coast: true);
    await tester.pump(const Duration(milliseconds: 16));
    expect(h.v[0].position.isScrollingNotifier.value, isTrue);
    final retained = h.v[0].offset;
    expect(retained, greaterThan(0));
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(h.v[0].offset, retained);
    await _wheel(tester, _key('v0'), const Offset(0, 40));
    expect(h.outerV.offset, greaterThan(0));
    expect(h.v[0].offset, retained);
  });

  for (final queuedWheel in [false, true]) {
    _case('unmount with queued ${queuedWheel ? 'wheel' : 'focus'} work is safe',
        (tester, h) async {
      await tester.tap(_key('header0'), kind: PointerDeviceKind.mouse);
      if (queuedWheel) {
        await tester.pumpAndSettle();
        await _wheel(tester, _key('v0'), const Offset(0, 120), settle: false);
        expect(h.v[0].position.isScrollingNotifier.value, isTrue);
      }
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump(const Duration(seconds: 2));
      expect(h.v[0].hasClients, isFalse);
      expect(h.h[0].hasClients, isFalse);
      expect(tester.binding.hasScheduledFrame, isFalse);
    });
  }

  _case('a child can remove its own region on the first tap',
      (tester, h) async {
    h.onTap = (_) => h.showFirst.value = false;
    await _click(tester, _key('button0'));
    expect(h.taps, 1);
    expect(_key('region0'), findsNothing);
    expect(_key('region1'), findsOneWidget);
    await _wheel(tester, _key('v1'), const Offset(0, 40));
    expect(h.outerV.offset, greaterThan(0));
    expect(h.v[1].offset, 0);
  });

  _case('a first-click popup can scroll with captured inactive behavior',
      (tester, h) async {
    final popupScroll = ScrollController();
    final popupFocus = FocusNode();
    addTearDown(popupScroll.dispose);
    addTearDown(popupFocus.dispose);
    var capturedInactive = false;
    h.onTap = (context) {
      final captured = ScrollConfiguration.of(context);
      capturedInactive = !captured
          .getScrollPhysics(context)
          .shouldAcceptUserOffset(h.v[0].position);
      unawaited(
        showDialog<void>(
          context: context,
          builder: (_) => ScrollConfiguration(
            behavior: captured,
            child: Dialog(
              child: SizedBox(
                width: 400,
                height: 320,
                child: Column(
                  children: [
                    TextField(autofocus: true, focusNode: popupFocus),
                    Expanded(
                      child: ListView.builder(
                        key: const ValueKey('popup-list'),
                        controller: popupScroll,
                        primary: false,
                        itemCount: 80,
                        itemExtent: 32,
                        itemBuilder: (_, index) => Text('Popup row $index'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    };
    await _click(tester, _key('button0'));
    expect(h.taps, 1);
    expect(capturedInactive, isTrue);
    expect(popupFocus.hasPrimaryFocus, isTrue);
    await _wheel(tester, _key('popup-list'), const Offset(0, 80));
    expect(popupScroll.offset, greaterThan(0));
    expect(h.v[0].offset, 0);
    expect(h.outerV.offset, 0);
    expect(popupFocus.hasPrimaryFocus, isTrue);
    Navigator.of(tester.element(_key('popup-list'))).pop();
    await tester.pumpAndSettle();
  });

  for (final (appearance, mode) in _modes.indexed) {
    _case(
      '${mode.name}: controlled focus and rejected clicks never bypass the host',
      (tester, h) async {
        h.fields[0].requestFocus();
        await tester.pumpAndSettle();
        expect(h.fields[0].hasPrimaryFocus, isTrue);
        expect(h.requests, [<bool>[], <bool>[]]);
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        await _wheel(tester, _key('h0'), const Offset(40, 0));
        expect(h.outerV.offset, greaterThan(0));
        expect(h.outerH.offset, greaterThan(0));
        expect(h.v[0].offset, 0);
        expect(h.h[0].offset, 0);

        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pumpAndSettle();
        expect(h.buttons[1].hasPrimaryFocus, isTrue);
        expect(h.requests, [<bool>[], <bool>[]]);
        final beforeTabWheel = h.outerV.offset;
        await _wheel(tester, _key('v1'), const Offset(0, 40));
        expect(h.outerV.offset, greaterThan(beforeTabWheel));
        expect(h.v[1].offset, 0);

        final press = await tester.startGesture(
          tester.getCenter(_key('button0')),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pump();
        expect(h.requests[0], isEmpty,
            reason: 'Pointer down is not selection.');
        expect(h.taps, 0);
        await press.up();
        await tester.pumpAndSettle();
        expect(h.taps, 1);
        expect(h.requests[0], [true]);
        expect(h.requests[1], isEmpty);
        expect(
          tester.widget<ScrollActivationRegion>(_key('region0')).active,
          isFalse,
        );
        final rejectedPage = Offset(h.outerH.offset, h.outerV.offset);
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        await _wheel(tester, _key('h0'), const Offset(40, 0));
        expect(h.outerV.offset, greaterThan(rejectedPage.dy));
        expect(h.outerH.offset, greaterThan(rejectedPage.dx));
        expect(h.v[0].offset, 0);
        expect(h.h[0].offset, 0);

        // The callback records requests only. A later host update, not the
        // completed click or retained child focus, is what opens the gate.
        h.active[0].value = true;
        h.fields[0].requestFocus();
        await tester.pumpAndSettle();
        final selectedPage = Offset(h.outerH.offset, h.outerV.offset);
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        await _wheel(tester, _key('h0'), const Offset(40, 0));
        expect(h.v[0].offset, greaterThan(0));
        expect(h.h[0].offset, greaterThan(0));
        expect(Offset(h.outerH.offset, h.outerV.offset), selectedPage);
        final retained = Offset(h.h[0].offset, h.v[0].offset);

        h.active[0].value = false;
        await tester.pumpAndSettle();
        expect(h.fields[0].hasPrimaryFocus, isTrue);
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        await _pan(tester, _key('h0'), const Offset(-60, 0));
        expect(h.outerV.offset, greaterThan(selectedPage.dy));
        expect(h.outerH.offset, greaterThan(selectedPage.dx));
        expect(Offset(h.h[0].offset, h.v[0].offset), retained);
        expect(h.requests[0], [true]);
        expect(h.requests[1], isEmpty);
        expect(h.taps, 1);
      },
      enabled: mode.enabled,
      reduced: mode.reduced,
      appearance: appearance,
      controlled: true,
    );
  }

  _case(
    'controlled semantics tap requests selection but waits for the host',
    (tester, h) async {
      final semantics = tester.ensureSemantics();
      try {
        await tester.pump();
        final regionSemantics = find.descendant(
          of: _key('region0'),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is Semantics &&
                widget.properties.selected != null &&
                widget.properties.onTap != null,
          ),
        );
        expect(regionSemantics, findsOneWidget);
        final node = tester.getSemantics(regionSemantics);
        expect(
            node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
        expect(
          node.getSemanticsData().hasFlag(ui.SemanticsFlag.isSelected),
          isFalse,
        );

        // Dispatch through the real semantics owner rather than calling the
        // widget's onTap closure or synthesizing a pointer click.
        node.owner!.performAction(node.id, ui.SemanticsAction.tap);
        await tester.pumpAndSettle();
        expect(h.requests[0], [true]);
        expect(h.taps, 0);
        expect(
          tester.widget<ScrollActivationRegion>(_key('region0')).active,
          isFalse,
        );
        expect(
          tester.getSemantics(regionSemantics).getSemanticsData().hasFlag(
                ui.SemanticsFlag.isSelected,
              ),
          isFalse,
        );
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        expect(h.outerV.offset, greaterThan(0));
        expect(h.v[0].offset, 0);

        h.active[0].value = true;
        await tester.pumpAndSettle();
        expect(
          tester.getSemantics(regionSemantics).getSemanticsData().hasFlag(
                ui.SemanticsFlag.isSelected,
              ),
          isTrue,
        );
        final page = h.outerV.offset;
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        expect(h.v[0].offset, greaterThan(0));
        expect(h.outerV.offset, page);
        expect(h.requests[0], [true]);
        expect(h.requests[1], isEmpty);
        expect(h.taps, 0);
      } finally {
        semantics.dispose();
      }
    },
    controlled: true,
  );

  for (final leave in ['outside click', 'plain Escape', 'focus leave']) {
    _case(
      'controlled $leave requests deselection and returns both axes to the page',
      (tester, h) async {
        h.onActiveChanged = (index, active) => h.active[index].value = active;
        h.active[0].value = true;
        h.fields[0].requestFocus();
        await tester.pumpAndSettle();
        expect(h.requests[0], isEmpty);
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        await _wheel(tester, _key('h0'), const Offset(40, 0));
        final retained = Offset(h.h[0].offset, h.v[0].offset);
        expect(retained.dx, greaterThan(0));
        expect(retained.dy, greaterThan(0));

        switch (leave) {
          case 'outside click':
            await _click(tester, _key('outside'));
          case 'plain Escape':
            await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
            try {
              await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            } finally {
              await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
            }
            await tester.pumpAndSettle();
            expect(h.requests[0], isEmpty);
            expect(h.active[0].value, isTrue);
            await tester.sendKeyEvent(LogicalKeyboardKey.escape);
            await tester.pumpAndSettle();
            expect(h.escapes, 2,
                reason: 'The outer handler still sees Escape.');
            expect(h.fields[0].hasPrimaryFocus, isTrue);
          case 'focus leave':
            h.outside.requestFocus();
            await tester.pumpAndSettle();
        }

        expect(h.requests[0], isNotEmpty);
        expect(h.requests[0], everyElement(isFalse));
        expect(h.requests[1], isEmpty);
        expect(
          tester.widget<ScrollActivationRegion>(_key('region0')).active,
          isFalse,
        );
        await _wheel(tester, _key('v0'), const Offset(0, 40));
        await _wheel(tester, _key('h0'), const Offset(40, 0));
        expect(h.outerV.offset, greaterThan(0));
        expect(h.outerH.offset, greaterThan(0));
        expect(Offset(h.h[0].offset, h.v[0].offset), retained);
        expect(h.requests[0], everyElement(isFalse));
      },
      controlled: true,
    );
  }

  _case(
    'external controlled deselection stops both inner queues without losing focus',
    (tester, h) async {
      h.active[0].value = true;
      h.fields[0].requestFocus();
      await tester.pumpAndSettle();
      await _wheel(tester, _key('v0'), const Offset(0, 120), settle: false);
      await _wheel(tester, _key('h0'), const Offset(120, 0), settle: false);
      await _wheel(tester, _key('v1'), const Offset(0, 120), settle: false);
      await _wheel(tester, _key('h1'), const Offset(120, 0), settle: false);
      await tester.pump(const Duration(milliseconds: 16));
      for (final controller in [h.v[0], h.h[0], h.outerV, h.outerH]) {
        expect(controller.position.isScrollingNotifier.value, isTrue);
      }
      final retained = Offset(h.h[0].offset, h.v[0].offset);
      final page = Offset(h.outerH.offset, h.outerV.offset);

      h.active[0].value = false;
      // Rebuild and run the post-frame stop without advancing kinetic time.
      await tester.pump();
      expect(h.fields[0].hasPrimaryFocus, isTrue);
      expect(Offset(h.h[0].offset, h.v[0].offset), retained);
      expect(h.v[0].position.isScrollingNotifier.value, isFalse);
      expect(h.h[0].position.isScrollingNotifier.value, isFalse);
      await tester.pumpAndSettle();
      expect(Offset(h.h[0].offset, h.v[0].offset), retained);
      expect(h.outerV.offset, greaterThan(page.dy));
      expect(h.outerH.offset, greaterThan(page.dx));
      expect(h.requests, [<bool>[], <bool>[]]);

      final drainedPage = Offset(h.outerH.offset, h.outerV.offset);
      await _wheel(tester, _key('v0'), const Offset(0, 40));
      await _wheel(tester, _key('h0'), const Offset(40, 0));
      expect(h.outerV.offset, greaterThan(drainedPage.dy));
      expect(h.outerH.offset, greaterThan(drainedPage.dx));
      expect(Offset(h.h[0].offset, h.v[0].offset), retained);
      expect(h.fields[0].hasPrimaryFocus, isTrue);
      expect(h.requests, [<bool>[], <bool>[]]);
    },
    controlled: true,
  );

  _case(
    'a controlled rejected first click still opens a scrollable captured popup',
    (tester, h) async {
      final popupScroll = ScrollController();
      final popupFocus = FocusNode();
      addTearDown(popupScroll.dispose);
      addTearDown(popupFocus.dispose);
      var capturedInactive = false;
      h.onTap = (context) {
        final captured = ScrollConfiguration.of(context);
        capturedInactive = !captured
            .getScrollPhysics(context)
            .shouldAcceptUserOffset(h.v[0].position);
        unawaited(
          showDialog<void>(
            context: context,
            builder: (_) => ScrollConfiguration(
              behavior: captured,
              child: Dialog(
                child: SizedBox(
                  width: 400,
                  height: 320,
                  child: Column(
                    children: [
                      TextField(autofocus: true, focusNode: popupFocus),
                      Expanded(
                        child: ListView.builder(
                          key: const ValueKey('controlled-popup-list'),
                          controller: popupScroll,
                          primary: false,
                          itemCount: 80,
                          itemExtent: 32,
                          itemBuilder: (_, index) => Text('Popup row $index'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      };
      await _click(tester, _key('button0'));
      expect(h.taps, 1);
      expect(h.requests[0], [true]);
      expect(capturedInactive, isTrue);
      expect(
        tester
            .widget<ScrollActivationRegion>(
              find.byKey(const ValueKey('region0'), skipOffstage: false),
            )
            .active,
        isFalse,
      );
      expect(popupFocus.hasPrimaryFocus, isTrue);
      await _wheel(tester, _key('controlled-popup-list'), const Offset(0, 80));
      expect(popupScroll.offset, greaterThan(0));
      expect(h.v[0].offset, 0);
      expect(h.outerV.offset, 0);
      expect(popupFocus.hasPrimaryFocus, isTrue);
      Navigator.of(tester.element(_key('controlled-popup-list'))).pop();
      await tester.pumpAndSettle();
      await _wheel(tester, _key('v0'), const Offset(0, 40));
      expect(h.outerV.offset, greaterThan(0));
      expect(h.v[0].offset, 0);
      expect(h.requests[0], [true]);
      expect(h.taps, 1);
    },
    controlled: true,
  );
}

void _case(
  String name,
  Future<void> Function(WidgetTester, _Harness) body, {
  bool enabled = true,
  bool reduced = false,
  int appearance = 0,
  bool controlled = false,
}) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 1000);
      final h = _Harness();
      try {
        if (controlled) {
          for (final active in h.active) {
            active.value = false;
          }
        }
        await tester.pumpWidget(h.app(enabled, reduced, appearance));
        await tester.pumpAndSettle();
        await body(tester, h);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        h.dispose();
        tester.view.reset();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _Harness {
  final outerV = ScrollController();
  final outerH = ScrollController();
  final v = [ScrollController(), ScrollController()];
  final h = [ScrollController(), ScrollController()];
  final fields = [FocusNode(), FocusNode()];
  final buttons = [FocusNode(), FocusNode()];
  final text = [TextEditingController(), TextEditingController()];
  final outside = FocusNode();
  final showFirst = ValueNotifier(true);
  final active = [ValueNotifier<bool?>(null), ValueNotifier<bool?>(null)];
  final requests = [<bool>[], <bool>[]];
  void Function(BuildContext)? onTap;
  void Function(int, bool)? onActiveChanged;
  var taps = 0;
  var escapes = 0;

  Widget app(bool enabled, bool reduced, int appearance) => MaterialApp(
        theme: DesktopAppearance().getThemeData(
          appearance == 2
              ? AppTheme.builtins
                  .firstWhere((t) => t.themeName == BuiltInTheme.paper)
              : AppTheme.fallback,
          appearance == 1 ? Brightness.dark : Brightness.light,
          defaultFontFamily,
          builtInCodeFontFamily,
        ),
        themeAnimationDuration: Duration.zero,
        builder: (context, navigator) => MediaQuery(
          data: MediaQuery.of(context).copyWith(disableAnimations: reduced),
          child: PremiumScrollScope(enabled: enabled, child: navigator!),
        ),
        home: Scaffold(
          body: FocusTraversalGroup(
            // Pin traversal for this activation test, rather than testing the
            // geometric reading order of two side-by-side form rows.
            policy: WidgetOrderTraversalPolicy(),
            child: Focus(
              // This test observer is not a user-facing Tab destination.
              skipTraversal: true,
              onKeyEvent: (_, event) {
                if (event is KeyDownEvent &&
                    event.logicalKey == LogicalKeyboardKey.escape) {
                  escapes++;
                }
                return KeyEventResult.ignored;
              },
              child: Column(
                children: [
                  SizedBox(
                    height: 48,
                    child: TextButton(
                      key: const ValueKey('outside'),
                      focusNode: outside,
                      onPressed: outside.requestFocus,
                      child: const Text('Outside the cards'),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      controller: outerV,
                      primary: false,
                      child: SizedBox(
                        height: 1800,
                        child: SingleChildScrollView(
                          controller: outerH,
                          primary: false,
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: 2300,
                            child: Align(
                              alignment: Alignment.topLeft,
                              child: Padding(
                                // Room for a complete 240px wheel queue on either axis.
                                padding:
                                    const EdgeInsets.only(left: 300, top: 300),
                                child: ValueListenableBuilder<bool>(
                                  valueListenable: showFirst,
                                  builder: (_, visible, __) => Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      if (visible) region(0),
                                      const SizedBox(width: 32),
                                      region(1),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );

  Widget region(int index) => SizedBox(
        width: 340,
        height: 360,
        child: ValueListenableBuilder<bool?>(
          valueListenable: active[index],
          builder: (_, selected, child) => ScrollActivationRegion(
            key: ValueKey('region$index'),
            active: selected,
            onActiveChanged: selected == null
                ? null
                : (value) {
                    requests[index].add(value);
                    onActiveChanged?.call(index, value);
                  },
            child: child!,
          ),
          child: Builder(
            builder: (context) => ScrollConfiguration(
              behavior: NoScrollbarBehavior(ScrollConfiguration.of(context))
                  .copyWith(scrollbars: true),
              child: Material(
                child: Column(
                  children: [
                    Tooltip(
                      message: 'Card help $index',
                      child: SizedBox(
                        key: ValueKey('header$index'),
                        height: 40,
                        width: double.infinity,
                        child: Center(child: Text('Card $index')),
                      ),
                    ),
                    SizedBox(
                      height: 56,
                      child: Row(
                        children: [
                          TextButton(
                            key: ValueKey('button$index'),
                            focusNode: buttons[index],
                            onPressed: () {
                              taps++;
                              onTap?.call(context);
                            },
                            child: const Text('Action'),
                          ),
                          Expanded(
                            child: TextField(
                              key: ValueKey('field$index'),
                              controller: text[index],
                              focusNode: fields[index],
                            ),
                          ),
                        ],
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        key: ValueKey('v$index'),
                        controller: v[index],
                        primary: false,
                        padding: EdgeInsets.zero,
                        itemCount: 60,
                        itemExtent: 32,
                        itemBuilder: (_, row) => Text('Reading $row'),
                      ),
                    ),
                    SizedBox(
                      height: 60,
                      child: SingleChildScrollView(
                        key: ValueKey('h$index'),
                        controller: h[index],
                        primary: false,
                        scrollDirection: Axis.horizontal,
                        child: const SizedBox(
                            width: 1800, child: Text('Wide reading')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  void dispose() {
    for (final controller in [outerV, outerH, ...v, ...h]) {
      controller.dispose();
    }
    for (final node in [outside, ...fields, ...buttons]) {
      node.dispose();
    }
    for (final controller in text) {
      controller.dispose();
    }
    for (final value in active) {
      value.dispose();
    }
    showFirst.dispose();
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));

Future<void> _click(WidgetTester tester, Finder target) async {
  await tester.tap(target, kind: PointerDeviceKind.mouse);
  await tester.pumpAndSettle();
}

Future<void> _wheel(
  WidgetTester tester,
  Finder target,
  Offset delta, {
  bool shift = false,
  bool settle = true,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: tester.getCenter(target),
        scrollDelta: delta,
      ),
    );
  } finally {
    if (shift) await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  if (settle) await tester.pumpAndSettle(const Duration(milliseconds: 16));
}

Future<void> _pan(
  WidgetTester tester,
  Finder target,
  Offset delta, {
  bool coast = false,
}) async {
  final position = tester.getCenter(target);
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(pointer: 71, device: 71, position: position),
  );
  for (var step = 1; step <= 3; step++) {
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 71,
        device: 71,
        position: position,
        pan: delta * (step / 3),
        panDelta: delta / 3,
        timeStamp: Duration(milliseconds: step * 10),
      ),
    );
  }
  if (!coast) {
    // A stationary sample prevents an unrelated release fling moving the cards away.
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 71,
        device: 71,
        position: position,
        pan: delta,
        timeStamp: const Duration(milliseconds: 200),
      ),
    );
  }
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: 71,
      device: 71,
      position: position,
      timeStamp: Duration(milliseconds: coast ? 31 : 201),
    ),
  );
  if (!coast) await tester.pumpAndSettle();
}
