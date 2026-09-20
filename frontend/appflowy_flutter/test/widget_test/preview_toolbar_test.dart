import 'dart:ui' as ui;

import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _fade = Duration(milliseconds: 140);
const _away = Offset(8, 8);
const _outside = ValueKey('outside-preview');

// Shared contracts only. Renderer-specific coverage lives in
// file_embed_toolbar_test.dart and embed_family_toolbar_test.dart.
void main() {
  for (final appearance in ['light', 'dark', 'paper']) {
    _test('$appearance: 140ms reveal retains geometry and gates live semantics',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      try {
        await mouse.addPointer(location: _away);
        await _mount(
          tester,
          _preview(
            'main',
            body: const Center(child: Text('Preview identity')),
          ),
          appearance: appearance,
        );
        final action = _action('main');
        final bounds = tester.getRect(action);
        final frame = tester.getRect(_frame('main'));
        final control = tester.state(action);
        final context = tester.element(action);
        expect(PaperTheme.isEnabled(context), appearance == 'paper');
        expect(
          Theme.of(context).brightness,
          appearance == 'dark' ? Brightness.dark : Brightness.light,
        );
        _expectToolbar(tester, 'main', false);
        expect(action.hitTestable(), findsNothing);
        expect(find.semantics.byLabel('Action main'), findsNothing);
        expect(find.semantics.byLabel('Preview identity'), findsOne);
        expect(_opacity(tester, 'main').duration, _fade);
        expect(_opacity(tester, 'main').curve, Curves.easeOutCubic);

        await mouse.moveTo(frame.center);
        await tester.pump();
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 70));
        expect(
          _paintedOpacity(tester, 'main'),
          closeTo(Curves.easeOutCubic.transform(0.5), 0.00001),
        );
        expect(action.hitTestable(), findsOneWidget);
        _expectButtonSemantics(tester, 'main');
        await tester.pump(const Duration(milliseconds: 70));
        _expectToolbar(tester, 'main', true);

        await mouse.moveTo(_away);
        await tester.pump();
        // Hit testing and accessibility stop immediately, not after the fade.
        _expectToolbar(tester, 'main', false, checkPaint: false);
        expect(_paintedOpacity(tester, 'main'), 1);
        expect(action.hitTestable(), findsNothing);
        // This walks the attached tree, not a mounted element's cached node.
        expect(find.semantics.byLabel('Action main'), findsNothing);
        expect(find.semantics.byLabel('Preview identity'), findsOne);
        await tester.pump(const Duration(milliseconds: 70));
        expect(
          _paintedOpacity(tester, 'main'),
          closeTo(1 - Curves.easeOutCubic.transform(0.5), 0.00001),
        );
        await tester.pump(const Duration(milliseconds: 70));
        _expectToolbar(tester, 'main', false);
        expect(tester.getRect(action), bounds);
        expect(tester.getRect(_frame('main')), frame);
        expect(tester.state(action), same(control));
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }

  _test('Tab reveals only its toolbar; body focus never reveals either group',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final outside = FocusNode();
    final first = FocusNode();
    final second = FocusNode();
    final body = FocusNode();
    var firstCalls = 0;
    var secondCalls = 0;
    try {
      await _mount(
        tester,
        SizedBox(
          width: 420,
          height: 240,
          child: PreviewToolbarRegion(
            child: Column(
              children: [
                Row(
                  children: [
                    _tools(
                      'first',
                      focus: first,
                      onPressed: () => firstCalls++,
                    ),
                    _tools(
                      'second',
                      focus: second,
                      onPressed: () => secondCalls++,
                    ),
                  ],
                ),
                TextField(focusNode: body),
              ],
            ),
          ),
        ),
        outsideFocus: outside,
      );
      await tester.enterText(find.byType(TextField), 'A body draft');
      await _settle(tester);
      expect(body.hasPrimaryFocus, isTrue);
      _expectToolbar(tester, 'first', false);
      _expectToolbar(tester, 'second', false);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(firstCalls + secondCalls, 0);

      outside.requestFocus();
      await _settle(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
      expect(first.hasPrimaryFocus, isTrue);
      _expectToolbar(tester, 'first', true);
      _expectToolbar(tester, 'second', false);
      _expectButtonSemantics(tester, 'first');
      expect(find.semantics.byLabel('Action second'), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      expect(firstCalls, 1);

      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await _settle(tester);
      expect(second.hasPrimaryFocus, isTrue);
      _expectToolbar(tester, 'first', false);
      _expectToolbar(tester, 'second', true);
      await tester.sendKeyEvent(LogicalKeyboardKey.space);
      expect(secondCalls, 1);
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
      await _settle(tester);
      expect(first.hasPrimaryFocus, isTrue);
      _expectToolbar(tester, 'first', true);
      _expectToolbar(tester, 'second', false);

      body.requestFocus();
      await _settle(tester);
      _expectToolbar(tester, 'first', false);
      _expectToolbar(tester, 'second', false);
      expect(find.text('A body draft'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final node in [outside, first, second, body]) {
        node.dispose();
      }
      semantics.dispose();
    }
  });

  for (final kind in [
    PointerDeviceKind.touch,
    PointerDeviceKind.stylus,
    PointerDeviceKind.invertedStylus,
  ]) {
    _test(
        '$kind: a hidden action has no hitbox; first contact reaches the body',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      TestGesture? contact;
      var actions = 0;
      var bodyTaps = 0;
      try {
        await mouse.addPointer(location: _away);
        await _mount(
          tester,
          SizedBox(
            width: 360,
            height: 200,
            child: PreviewToolbarRegion(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () => bodyTaps++,
                    child: const SizedBox.expand(),
                  ),
                  Positioned(
                    top: 0,
                    right: 0,
                    child: _tools('main', onPressed: () => actions++),
                  ),
                ],
              ),
            ),
          ),
        );
        _expectToolbar(tester, 'main', false);
        expect(_action('main').hitTestable(), findsNothing);
        contact = await tester.startGesture(
          tester.getCenter(_action('main')),
          kind: kind,
        );
        await tester.pump();
        await contact.up();
        await _settle(tester);
        expect(actions, 0);
        expect(
          bodyTaps,
          1,
          reason: 'No invisible toolbar may eat the first tap.',
        );
        _expectToolbar(tester, 'main', true);
        _expectButtonSemantics(tester, 'main');

        await contact.down(tester.getCenter(_action('main')));
        await contact.up();
        await _settle(tester);
        expect(actions, 1);
        expect(bodyTaps, 1);
        _focusOutside(tester);
        await mouse.moveTo(tester.getCenter(_action('main')));
        await mouse.moveTo(_away);
        await _settle(tester);
        _expectToolbar(tester, 'main', false);
        expect(find.semantics.byLabel('Action main'), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await contact?.removePointer();
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }

  for (final settings in [
    (platform: TargetPlatform.android, accessible: false, reduced: false),
    (platform: TargetPlatform.iOS, accessible: false, reduced: false),
    (platform: TargetPlatform.windows, accessible: true, reduced: false),
    (platform: TargetPlatform.windows, accessible: false, reduced: true),
  ]) {
    _test('touch/assistive-navigation and reduced-motion policy: $settings',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      final alwaysVisible =
          settings.platform != TargetPlatform.windows || settings.accessible;
      var activations = 0;
      try {
        await mouse.addPointer(location: _away);
        await _mount(
          tester,
          _preview(
            'main',
            tools: _tools('main', onPressed: () => activations++),
          ),
          platform: settings.platform,
          accessible: settings.accessible,
          reduced: settings.reduced,
        );
        _expectToolbar(tester, 'main', alwaysVisible);
        expect(
          _opacity(tester, 'main').duration,
          settings.accessible || settings.reduced ? Duration.zero : _fade,
        );
        if (alwaysVisible) _expectButtonSemantics(tester, 'main');
        if (settings.accessible) {
          tester.binding.renderViews.single.owner!.semanticsOwner!
              .performAction(
            tester.getSemantics(_action('main')).id,
            ui.SemanticsAction.tap,
          );
          await tester.pump();
          expect(activations, 1);
        }
        await mouse.moveTo(tester.getCenter(_frame('main')));
        await tester.pump();
        await tester.pump();
        // No elapsed time: reduced motion must change actual paint immediately.
        _expectToolbar(tester, 'main', true);
        await mouse.moveTo(_away);
        await tester.pump();
        await tester.pump();
        _expectToolbar(tester, 'main', alwaysVisible);
        expect(activations, settings.accessible ? 1 : 0);
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox.shrink());
        semantics.dispose();
      }
    });
  }

  _test('standalone, disabled-region and keepVisible fallbacks stay local',
      (tester) async {
    final pinned = ValueNotifier(true);
    try {
      await _mount(
        tester,
        Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _tools('standalone'),
            ValueListenableBuilder<bool>(
              valueListenable: pinned,
              builder: (_, value, __) => PreviewToolbarRegion(
                child: Column(
                  children: [
                    _tools('idle'),
                    _tools('pinned', keepVisible: value),
                    PreviewToolbarRegion(
                      enabled: !value,
                      child: _tools('disabled'),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
      final states = {
        for (final id in ['standalone', 'idle', 'pinned', 'disabled'])
          id: tester.state(_toolbar(id)),
      };
      for (final value in [true, false, true]) {
        pinned.value = value;
        await _settle(tester);
        for (final entry in states.entries) {
          final visible =
              entry.key == 'standalone' || (entry.key != 'idle' && value);
          _expectToolbar(tester, entry.key, visible);
          expect(tester.state(_toolbar(entry.key)), same(entry.value));
          expect(
            _action(entry.key).hitTestable(),
            visible ? findsOneWidget : findsNothing,
          );
        }
      }
      final release =
          PreviewToolbarRegion.hold(tester.element(_action('standalone')));
      release();
      release();
      _expectToolbar(tester, 'idle', false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      pinned.dispose();
    }
  });

  _test('nested holds are counted, sibling-local, idempotent and disposal-safe',
      (tester) async {
    final releases = <VoidCallback>[];
    final leftPresent = ValueNotifier(true);
    try {
      await _mount(
        tester,
        _nestedPreviews(
          leftPreview: ValueListenableBuilder<bool>(
            valueListenable: leftPresent,
            builder: (_, present, __) =>
                present ? _preview('left') : const SizedBox.shrink(),
          ),
        ),
      );
      VoidCallback hold(String id) {
        final release = PreviewToolbarRegion.hold(tester.element(_action(id)));
        releases.add(release);
        return release;
      }

      final first = hold('left');
      final second = hold('left');
      await _settle(tester);
      _expectNested(tester, outer: true, left: true, right: false);
      final sibling = hold('right');
      await _settle(tester);
      _expectNested(tester, outer: true, left: true, right: true);
      first();
      first();
      await _settle(tester);
      _expectNested(tester, outer: true, left: true, right: true);
      sibling();
      await _settle(tester);
      _expectNested(tester, outer: true, left: true, right: false);
      second();
      await _settle(tester);
      _expectNested(tester, outer: false, left: false, right: false);

      final lateFirst = hold('left');
      final lateSecond = hold('left');
      final lateSibling = hold('right');
      await _settle(tester);
      // Only the inner scope dies. Its outstanding holds must still balance
      // the surviving parent, without reaching the replacement inner scope.
      leftPresent.value = false;
      await _settle(tester);
      expect(_toolbar('left'), findsNothing);
      _expectToolbar(tester, 'outer', true);
      _expectToolbar(tester, 'right', true);
      leftPresent.value = true;
      await _settle(tester);
      _expectNested(tester, outer: true, left: false, right: true);
      final fresh = hold('left');
      for (final release in [lateSecond, lateSibling, lateFirst, lateFirst]) {
        expect(release, returnsNormally);
      }
      await _settle(tester);
      _expectNested(tester, outer: true, left: true, right: false);
      fresh();
      await _settle(tester);
      _expectNested(tester, outer: false, left: false, right: false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      for (final release in releases.reversed) {
        release();
      }
      leftPresent.dispose();
    }
  });

  _test(
      'only the real frame hovers; sequential inner regions never rebuild bodies',
      (tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await _mount(
        tester,
        SizedBox(
          width: 780,
          height: 580,
          child: ResizableMedia(
            width: 640,
            height: 480,
            editable: false,
            onResize: (_) {},
            footer: const Text('Caption outside preview'),
            child: Column(
              children: [
                _tools('outer'),
                Expanded(
                  child: _body(
                    'outer',
                    child: SizedBox(
                      height: 210,
                      child: Row(
                        children: [
                          Expanded(
                            child: _preview(
                              'left',
                              height: 210,
                              body: _body('left'),
                            ),
                          ),
                          const SizedBox(width: 24),
                          Expanded(
                            child: _preview(
                              'right',
                              height: 210,
                              body: _body('right'),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      for (final id in ['outer', 'left', 'right']) {
        await tester.enterText(
          find.byKey(ValueKey('draft-$id')),
          'Unsaved $id',
        );
        final state =
            tester.state<_CountingBodyState>(find.byKey(ValueKey('body-$id')));
        state.text.selection =
            const TextSelection(baseOffset: 1, extentOffset: 6);
        state.scroll.jumpTo(84);
      }
      _focusOutside(tester);
      await _settle(tester);
      final snapshots = {
        for (final id in ['outer', 'left', 'right'])
          id: (
            state: tester
                .state<_CountingBodyState>(find.byKey(ValueKey('body-$id'))),
            rect: tester.getRect(find.byKey(ValueKey('body-$id'))),
            editable: tester.state(
              find.descendant(
                of: find.byKey(ValueKey('draft-$id')),
                matching: find.byType(EditableText),
              ),
            ),
          ),
      };
      final builds = {
        for (final entry in snapshots.entries)
          entry.key: entry.value.state.builds,
      };
      final values = {
        for (final entry in snapshots.entries)
          entry.key: entry.value.state.text.value,
      };
      final positions = {
        for (final entry in snapshots.entries)
          entry.key: entry.value.state.scroll.position,
      };

      void expectRetained() {
        for (final entry in snapshots.entries) {
          final id = entry.key;
          final snapshot = entry.value;
          final state = tester
              .state<_CountingBodyState>(find.byKey(ValueKey('body-$id')));
          expect(state, same(snapshot.state));
          expect(
            state.builds,
            builds[id],
            reason: '$id body rebuilt on reveal',
          );
          expect(
            tester.getRect(find.byKey(ValueKey('body-$id'))),
            snapshot.rect,
          );
          expect(state.text.value, values[id]);
          expect(state.scroll.position, same(positions[id]));
          expect(state.scroll.offset, 84);
          expect(
            tester.state(
              find.descendant(
                of: find.byKey(ValueKey('draft-$id')),
                matching: find.byType(EditableText),
              ),
            ),
            same(snapshot.editable),
          );
        }
      }

      final frame =
          tester.getRect(find.byKey(const ValueKey('resizable_media')));
      for (final margin in [
        Offset(frame.left - 8, frame.center.dy),
        Offset(frame.right + 8, frame.center.dy),
        Offset(frame.center.dx, frame.top - 8),
        Offset(frame.center.dx, frame.bottom + 4),
        tester.getCenter(find.text('Caption outside preview')),
      ]) {
        await mouse.moveTo(margin);
        await _settle(tester);
        _expectNested(tester, outer: false, left: false, right: false);
        expectRetained();
      }
      for (var pass = 0; pass < 2; pass++) {
        for (final id in ['outer', 'left', 'right', 'left', 'outer', 'right']) {
          await mouse
              .moveTo(tester.getCenter(find.byKey(ValueKey('draft-$id'))));
          await _settle(tester);
          _expectNested(
            tester,
            outer: true,
            left: id == 'left',
            right: id == 'right',
          );
          expectRetained();
        }
        await mouse.moveTo(_away);
        await _settle(tester);
        _expectNested(tester, outer: false, left: false, right: false);
        expectRetained();
      }
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });

  _test('real showAppMenu holds ancestors after pointer/focus enter the menu',
      (tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    final triggerFocus = FocusNode();
    Future<String?>? menu;
    try {
      await mouse.addPointer(location: _away);
      await _mount(
        tester,
        _nestedPreviews(
          leftTools: Builder(
            builder: (context) => _tools(
              'left',
              focus: triggerFocus,
              onPressed: () {
                menu = showAppMenu<String>(
                  context: context,
                  globalPosition: const Offset(650, 630),
                  entries: const [
                    AppMenuItem(
                        label: 'Apply preview option', value: 'applied',),
                  ],
                );
              },
            ),
          ),
        ),
      );
      // Exercise both normal completion and cancellation on the same scopes.
      for (final cancel in [false, true]) {
        await mouse.moveTo(tester.getCenter(_frame('left')));
        await _settle(tester);
        await mouse.down(tester.getCenter(_action('left')));
        await mouse.up();
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        final menuCenter = tester.getCenter(find.byType(AppMenuSurface));
        expect(tester.getRect(_frame('outer')).contains(menuCenter), isFalse);
        await mouse.moveTo(menuCenter);
        await _settle(tester);
        expect(
          triggerFocus.hasFocus,
          isFalse,
          reason: 'Only the hold can keep these controls visible.',
        );
        _expectNested(tester, outer: true, left: true, right: false);

        if (cancel) {
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        } else {
          await mouse.down(tester.getCenter(find.text('Apply preview option')));
          await mouse.up();
        }
        await tester.pumpAndSettle();
        expect(await menu!, cancel ? isNull : 'applied');
        expect(find.byType(AppMenuSurface), findsNothing);
        _focusOutside(tester);
        await _settle(tester);
        _expectNested(tester, outer: false, left: false, right: false);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
      triggerFocus.dispose();
    }
  });

  _test(
      'menu cancellation after origin disposal releases without touching new scopes',
      (tester) async {
    final present = ValueNotifier(true);
    try {
      await _mount(
        tester,
        ValueListenableBuilder<bool>(
          valueListenable: present,
          builder: (_, value, __) =>
              value ? _nestedPreviews() : const SizedBox.shrink(),
        ),
      );
      final menu = showAppMenu<void>(
        context: tester.element(_action('left')),
        globalPosition: const Offset(650, 630),
        entries: const [AppMenuItem(label: 'Still-open menu')],
      );
      await tester.pumpAndSettle();
      _expectNested(tester, outer: true, left: true, right: false);
      present.value = false;
      await tester.pump();
      expect(find.byType(PreviewToolbarRegion), findsNothing);
      expect(find.byType(AppMenuSurface), findsOneWidget);
      present.value = true;
      await tester.pump();
      _expectNested(tester, outer: false, left: false, right: false);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      await menu;
      _focusOutside(tester);
      await _settle(tester);
      _expectNested(tester, outer: false, left: false, right: false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      present.dispose();
    }
  });

  _test(
      'empty and synchronously failing real menus cannot leak or over-release holds',
      (tester) async {
    const failureContext = ValueKey('missing-material-localizations');
    VoidCallback? release;
    try {
      await _mount(
        tester,
        _preview(
          'outer',
          height: 320,
          body: _preview(
            'left',
            body: Localizations(
              locale: const Locale('en', 'US'),
              delegates: const [DefaultWidgetsLocalizations.delegate],
              child: const SizedBox(key: failureContext),
            ),
          ),
        ),
      );
      final context = tester.element(find.byKey(failureContext));
      expect(
        await showAppMenu<Object?>(
          context: context,
          globalPosition: const Offset(650, 630),
          entries: const [AppMenuSeparator()],
        ),
        isNull,
      );
      await _settle(tester);
      _expectToolbar(tester, 'outer', false);
      _expectToolbar(tester, 'left', false);
      release = PreviewToolbarRegion.hold(context);
      await _settle(tester);

      // Navigator and regions are real. MaterialLocalizations.of throws after
      // showAppMenu acquires its own hold, inside its synchronous try/catch.
      expect(
        () => showAppMenu<void>(
          context: context,
          globalPosition: const Offset(650, 630),
          entries: const [AppMenuItem(label: 'Cannot open')],
        ),
        throwsA(
          isA<FlutterError>().having(
            (error) => error.toString(),
            'missing dependency',
            contains('MaterialLocalizations'),
          ),
        ),
      );
      await _settle(tester);
      _expectToolbar(tester, 'outer', true);
      _expectToolbar(tester, 'left', true);
      expect(find.byType(AppMenuSurface), findsNothing);
      release();
      await _settle(tester);
      _expectToolbar(tester, 'outer', false);
      _expectToolbar(tester, 'left', false);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox.shrink());
      release?.call();
    }
  });

  _test(
      '2x text and DPR changes retain logical geometry, state and reveal policy',
      (tester) async {
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: _away);
      await _mount(
        tester,
        _preview('main', width: 400, height: 300, body: _body('density')),
        textScale: 2,
      );
      final actionBounds = tester.getRect(_action('main'));
      final bodyBounds =
          tester.getRect(find.byKey(const ValueKey('body-density')));
      final state = tester.state(find.byKey(const ValueKey('body-density')));
      for (final dpr in [1.0, 3.0]) {
        tester.view.devicePixelRatio = dpr;
        tester.view.physicalSize = const Size(900, 720) * dpr;
        await _settle(tester);
        final context = tester.element(_action('main'));
        expect(MediaQuery.devicePixelRatioOf(context), dpr);
        expect(MediaQuery.textScalerOf(context).scale(14), 28);
        _expectToolbar(tester, 'main', false);
        expect(_opacity(tester, 'main').duration, _fade);
        final frame = tester.getRect(_frame('main'));
        await mouse.moveTo(Offset(frame.right + 8, frame.center.dy));
        await _settle(tester);
        _expectToolbar(tester, 'main', false);
        await mouse.moveTo(frame.center);
        await _settle(tester);
        _expectToolbar(tester, 'main', true);
        expect(tester.getRect(_action('main')), actionBounds);
        expect(
          tester.getRect(find.byKey(const ValueKey('body-density'))),
          bodyBounds,
        );
        expect(
          tester.state(find.byKey(const ValueKey('body-density'))),
          same(state),
        );
        await mouse.moveTo(_away);
        await _settle(tester);
        _expectToolbar(tester, 'main', false);
        expect(tester.takeException(), isNull);
      }
    } finally {
      await mouse.removePointer();
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}

void _test(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(
      name,
      body,
      variant: TargetPlatformVariant.only(TargetPlatform.windows),
    );

Finder _toolbar(String id) => find.byKey(ValueKey('toolbar-$id'));
Finder _action(String id) => find.byKey(ValueKey('action-$id'));
Finder _frame(String id) => find.byKey(ValueKey('frame-$id'));

Widget _tools(
  String id, {
  FocusNode? focus,
  VoidCallback? onPressed,
  bool keepVisible = false,
}) =>
    PreviewToolbar(
      key: ValueKey('toolbar-$id'),
      keepVisible: keepVisible,
      child: TextButton(
        key: ValueKey('action-$id'),
        focusNode: focus,
        onPressed: onPressed ?? () {},
        child: Text('Action $id'),
      ),
    );

Widget _preview(
  String id, {
  double width = 360,
  double height = 200,
  Widget? tools,
  Widget? body,
}) =>
    SizedBox(
      key: ValueKey('frame-$id'),
      width: width,
      height: height,
      child: PreviewToolbarRegion(
        child: Column(
          children: [
            Align(alignment: Alignment.topRight, child: tools ?? _tools(id)),
            Expanded(child: body ?? const SizedBox.expand()),
          ],
        ),
      ),
    );

Widget _nestedPreviews({Widget? leftTools, Widget? leftPreview}) => _preview(
      'outer',
      width: 720,
      height: 300,
      body: Row(
        children: [
          Expanded(child: leftPreview ?? _preview('left', tools: leftTools)),
          const SizedBox(width: 24),
          Expanded(child: _preview('right')),
        ],
      ),
    );

Finder _fadeFinder(String id) => find
    .descendant(
      of: _toolbar(id),
      matching: find.byType(AnimatedOpacity),
    )
    .first;

AnimatedOpacity _opacity(WidgetTester tester, String id) =>
    tester.widget<AnimatedOpacity>(_fadeFinder(id));

double _paintedOpacity(WidgetTester tester, String id) =>
    tester.renderObject<RenderAnimatedOpacity>(_fadeFinder(id)).opacity.value;

void _expectToolbar(
  WidgetTester tester,
  String id,
  bool visible, {
  bool checkPaint = true,
}) {
  expect(_opacity(tester, id).opacity, visible ? 1 : 0);
  if (checkPaint) expect(_paintedOpacity(tester, id), visible ? 1 : 0);
  expect(
    tester
        .widget<IgnorePointer>(
          find
              .descendant(
                of: _toolbar(id),
                matching: find.byType(IgnorePointer),
              )
              .first,
        )
        .ignoring,
    !visible,
  );
  expect(
    tester
        .widget<ExcludeSemantics>(
          find
              .descendant(
                of: _toolbar(id),
                matching: find.byType(ExcludeSemantics),
              )
              .first,
        )
        .excluding,
    !visible,
  );
}

void _expectNested(
  WidgetTester tester, {
  required bool outer,
  required bool left,
  required bool right,
}) {
  _expectToolbar(tester, 'outer', outer);
  _expectToolbar(tester, 'left', left);
  _expectToolbar(tester, 'right', right);
}

void _expectButtonSemantics(WidgetTester tester, String id) {
  expect(find.semantics.byLabel('Action $id'), findsOne);
  final node = tester.getSemantics(_action(id));
  expect(node.label, 'Action $id');
  expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), isTrue);
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
  await tester.pump(_fade);
}

void _focusOutside(WidgetTester tester) =>
    Focus.of(tester.element(find.text('Outside preview'))).requestFocus();

Future<void> _mount(
  WidgetTester tester,
  Widget child, {
  String appearance = 'paper',
  TargetPlatform platform = TargetPlatform.windows,
  FocusNode? outsideFocus,
  bool accessible = false,
  bool reduced = false,
  double textScale = 1,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(900, 720);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
    preferredFontFamily,
    builtInCodeFontFamily,
  );
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.copyWith(platform: platform),
      themeAnimationDuration: Duration.zero,
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          accessibleNavigation: accessible,
          disableAnimations: reduced,
          textScaler: TextScaler.linear(textScale),
        ),
        child: navigator!,
      ),
      home: Scaffold(
        body: FocusTraversalGroup(
          policy: WidgetOrderTraversalPolicy(),
          child: Column(
            children: [
              TextButton(
                key: _outside,
                focusNode: outsideFocus,
                onPressed: () {},
                child: const Text('Outside preview'),
              ),
              Expanded(child: Center(child: child)),
            ],
          ),
        ),
      ),
    ),
  );
  await _settle(tester);
}

Widget _body(String id, {Widget? child}) => _CountingBody(
      key: ValueKey('body-$id'),
      id: id,
      child: child,
    );

// The sole instrumented widget: real input and scroll state, plus a build count.
class _CountingBody extends StatefulWidget {
  const _CountingBody({super.key, required this.id, this.child});
  final String id;
  final Widget? child;

  @override
  State<_CountingBody> createState() => _CountingBodyState();
}

class _CountingBodyState extends State<_CountingBody> {
  final text = TextEditingController();
  final scroll = ScrollController();
  int builds = 0;

  @override
  void dispose() {
    text.dispose();
    scroll.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    builds++;
    return Column(
      children: [
        TextField(
          key: ValueKey('draft-${widget.id}'),
          controller: text,
          decoration: const InputDecoration(isDense: true),
        ),
        Expanded(
          child: ListView.builder(
            controller: scroll,
            primary: false,
            padding: EdgeInsets.zero,
            itemCount: 40,
            itemExtent: 28,
            itemBuilder: (_, index) => Text('Row $index'),
          ),
        ),
        if (widget.child != null) widget.child!,
      ],
    );
  }
}
