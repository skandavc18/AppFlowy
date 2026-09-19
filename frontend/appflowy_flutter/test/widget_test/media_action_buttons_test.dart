import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _modes = ['light', 'dark', 'paper'];
const _barKey = ValueKey('test-media-actions');
const _surfaceKey = ValueKey('media-action-surface');
const _copyKey = ValueKey('media-copy');
const _shareKey = ValueKey('media-share');
const _copiedKey = ValueKey('media-copied');
const _revealKey = ValueKey('media-action-reveal');
const _hostKey = ValueKey('test-media-host');
const _filenameKey = ValueKey('test-media-filename');
const _fade = Duration(milliseconds: 140);
const _cleanupTick = Duration(microseconds: 1);
const _sensitivePayload = 'private-path?token=synthetic-secret-do-not-display';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    final families = _modes
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  test('public defaults do not require service dependencies', () {
    final buttons = MediaActionButtons(source: _source());
    expect(buttons.actions, same(const MediaActionService()));
    expect(buttons.decorated, isTrue);
    expect(buttons.buttonSize, 28);
  });

  testWidgets(
      'hover exit removes action nodes from the attached semantics tree',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = _FakeMediaActionService();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _pump(tester, _hoverHost(actions));
      final state = tester.state(find.byType(MediaActionButtons));
      await mouse.moveTo(
        tester.getBottomLeft(find.byKey(_hostKey)) + const Offset(12, -12),
      );
      await tester.pump();
      await tester.pump(_fade);
      final copy = find.semantics.byLabel('Copy').evaluate().single;
      final share = find.semantics.byLabel('Share').evaluate().single;
      expect(copy.attached, isTrue);
      expect(share.attached, isTrue);
      _expectButtonSemantics(tester, _copyKey, label: 'Copy');
      _expectButtonSemantics(tester, _shareKey, label: 'Share');

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      _expectReveal(tester, visible: false);
      expect(_paintedOpacity(tester), 1);
      // Flutter 3.27 retains debugSemantics on mounted render objects even
      // after ExcludeSemantics detaches their nodes. Inspect the real tree.
      expect(copy.attached, isFalse);
      expect(share.attached, isFalse);
      expect(find.semantics.byLabel('Copy'), findsNothing);
      expect(find.semantics.byLabel('Share'), findsNothing);
      expect(find.semantics.byFlag(ui.SemanticsFlag.isButton), findsNothing);
      expect(find.semantics.byAction(ui.SemanticsAction.tap), findsNothing);
      expect(find.byKey(_copyKey).hitTestable(), findsNothing);
      expect(find.byKey(_shareKey).hitTestable(), findsNothing);
      await tester.pump(_fade);
      expect(_paintedOpacity(tester), 0);
      expect(find.semantics.byAction(ui.SemanticsAction.tap), findsNothing);

      await mouse.moveTo(
        tester.getBottomLeft(find.byKey(_hostKey)) + const Offset(12, -12),
      );
      await tester.pump();
      await tester.pump(_fade);
      _expectButtonSemantics(tester, _copyKey, label: 'Copy');
      _expectButtonSemantics(tester, _shareKey, label: 'Share');
      expect(
        find.semantics.byFlag(ui.SemanticsFlag.isButton),
        findsNWidgets(2),
      );
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      semantics.dispose();
      await _dispose(tester);
    }
  });

  for (final mode in _modes) {
    testWidgets('$mode: compact native controls use the floating palette',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _FakeMediaActionService();
      try {
        await _pump(tester, _buttons(actions), mode: mode);
        final context = tester.element(find.byKey(_barKey));
        final palette = PremiumThemeExtension.of(context);
        final decoration = _surface(tester);

        expect(find.byType(IconButton), findsNWidgets(2));
        expect(_button(tester, _copyKey).tooltip, 'Copy');
        expect(_button(tester, _shareKey).tooltip, 'Share');
        expect(find.byTooltip(LocaleKeys.editor_copy.tr()), findsOneWidget);
        expect(find.byTooltip(LocaleKeys.button_share.tr()), findsOneWidget);
        expect(_buttonIcon(_copyKey, Icons.copy_rounded), findsOneWidget);
        expect(_buttonIcon(_shareKey, Icons.ios_share_rounded), findsOneWidget);
        expect(tester.getSize(find.byKey(_barKey)), const Size(68, 36));
        expect(decoration.color, palette.floatingSurface);
        expect(decoration.border, isNull);
        expect(decoration.borderRadius, BorderRadius.circular(10));
        expect(decoration.boxShadow, EditorSurfaceStyle.embedShadow(context));
        if (mode == 'paper') {
          expect(PaperTheme.isEnabled(context), isTrue);
          expect(decoration.color, PaperTheme.popupBackground);
          expect(decoration.color!.r, greaterThan(decoration.color!.b));
        }
        for (final key in [_copyKey, _shareKey]) {
          final button = _button(tester, key);
          expect(tester.getSize(find.byKey(key)), const Size.square(28));
          _expectButtonSemantics(tester, key, label: button.tooltip!);
          expect(find.bySemanticsLabel(button.tooltip!), findsOneWidget);
          expect(button.style!.minimumSize!.resolve({}), const Size.square(28));
          expect(button.style!.maximumSize!.resolve({}), const Size.square(28));
          expect(button.style!.padding!.resolve({}), EdgeInsets.zero);
          expect(button.style!.tapTargetSize, MaterialTapTargetSize.shrinkWrap);
          expect(button.style!.splashFactory, NoSplash.splashFactory);
          expect(
            button.style!.foregroundColor!.resolve({}),
            palette.textSecondary,
          );
          expect(button.style!.backgroundColor!.resolve({})!.a, 0);
          expect(button.style!.side!.resolve({})!.color.a, 0);
          expect(
            button.style!.side!.resolve({WidgetState.focused})!.color,
            palette.focusRing,
          );
          expect(
            button.style!.backgroundColor!.resolve({WidgetState.hovered}),
            palette.accent.withValues(alpha: 0.07),
          );
          expect(
            button.style!.backgroundColor!.resolve({WidgetState.pressed}),
            palette.accent.withValues(alpha: 0.12),
          );
          expect(
            button.style!.overlayColor!.resolve({WidgetState.hovered}),
            Colors.transparent,
          );
          expect(
            button.style!.shape!.resolve({}),
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
          );
        }
        expect(find.byType(Card), findsNothing);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _dispose(tester);
      }
    });

    testWidgets('$mode: inline controls leave their parent background alone',
        (tester) async {
      final actions = _FakeMediaActionService();
      final parentColor = _theme(mode).scaffoldBackgroundColor;
      try {
        await _pump(
          tester,
          ColoredBox(
            key: const ValueKey('parent-toolbar'),
            color: parentColor,
            child: _buttons(actions, decorated: false),
          ),
          mode: mode,
        );
        expect(tester.getSize(find.byKey(_barKey)), const Size(60, 28));
        expect(_surface(tester).color, isNull);
        expect(_surface(tester).border, isNull);
        expect(_surface(tester).boxShadow, isNull);
        final material = tester.widget<Material>(
          find
              .descendant(
                of: find.byKey(_surfaceKey),
                matching: find.byType(Material),
              )
              .first,
        );
        expect(material.type, MaterialType.transparency);
        expect(material.elevation, 0);
        expect(
          tester
              .widget<ColoredBox>(find.byKey(const ValueKey('parent-toolbar')))
              .color,
          parentColor,
        );
        for (final key in [_copyKey, _shareKey]) {
          expect(tester.getSize(find.byKey(key)), const Size.square(28));
          expect(
            _button(tester, key).style!.backgroundColor!.resolve({})!.a,
            0,
          );
        }
        expect(actions.calls, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester);
      }
    });

    testWidgets(
        '$mode: awaited copy feedback never reflows an intrinsic scaled row',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _FakeMediaActionService();
      final source = _source(name: 'A very long photograph filename.png');
      try {
        await _pump(
          tester,
          SizedBox(
            width: 172,
            child: IntrinsicHeight(
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      source.name,
                      key: _filenameKey,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _buttons(actions, source: source),
                ],
              ),
            ),
          ),
          mode: mode,
          textScale: 2,
        );
        final bounds = _bounds(tester, filename: true);
        final copyAgain = _button(tester, _copyKey).onPressed!;
        final shareDuringCopy = _button(tester, _shareKey).onPressed!;

        await tester.tap(find.byKey(_copyKey));
        copyAgain();
        shareDuringCopy();
        await tester.pump();
        expect(actions.calls, hasLength(1));
        expect(actions.calls.single.kind, 'copy');
        expect(actions.calls.single.source, same(source));
        expect(actions.calls.single.finished, isFalse);
        _expectBusy(tester);
        expect(find.byType(CircularProgressIndicator), findsOneWidget);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(_bounds(tester, filename: true), bounds);
        _expectButtonSemantics(
          tester,
          _copyKey,
          label: 'Copy',
          enabled: false,
        );
        _expectButtonSemantics(
          tester,
          _shareKey,
          label: 'Share',
          enabled: false,
        );
        // Both actual taps and callbacks captured before the busy rebuild are guarded.
        await tester.tap(find.byKey(_copyKey));
        await tester.tap(find.byKey(_shareKey));
        await tester.pump(const Duration(milliseconds: 300));
        expect(actions.calls, hasLength(1));
        expect(find.byKey(_copiedKey), findsNothing);

        final feedbackDeadline = tester.binding.clock.now().add(
              const Duration(milliseconds: 1600),
            );
        actions.calls.single.succeed();
        await tester.pump();
        expect(_badgeOpacity(tester), 0);
        await tester.pump(const Duration(milliseconds: 70));
        expect(_badgeOpacity(tester), greaterThan(0));
        expect(_badgeOpacity(tester), lessThan(1));
        expect(_bounds(tester, filename: true), bounds);
        await tester.pump(const Duration(milliseconds: 70));
        expect(_badgeOpacity(tester), 1);
        // Flutter 3.27's interpolation completes only for elapsed > duration.
        // At exactly 140ms outgoing content must already be invisible; the
        // following 1us tick verifies disposal without stretching the feedback.
        _expectFadedOut(tester, find.byType(CircularProgressIndicator));
        await tester.pump(_cleanupTick);
        expect(actions.calls.single.finished, isTrue);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(_button(tester, _copyKey).tooltip, 'Copied');
        expect(_button(tester, _shareKey).tooltip, 'Share');
        _expectButtonSemantics(
          tester,
          _copyKey,
          label: 'Copied',
          liveRegion: true,
        );
        final copied = tester.widget<Text>(find.byKey(_copiedKey));
        expect(copied.data, 'Copied');
        expect(copied.style!.fontSize, 10);
        expect(
          tester.getRect(find.byKey(_copiedKey)).bottom,
          lessThan(tester.getRect(find.byKey(_barKey)).top),
        );
        expect(_badgeOpacity(tester), 1);
        expect(_bounds(tester, filename: true), bounds);
        expect(find.byType(SnackBar), findsNothing);

        // The 1600ms clock starts when the write succeeds, not when clicked.
        await tester.pump(
          feedbackDeadline.difference(tester.binding.clock.now()) -
              const Duration(milliseconds: 1),
        );
        expect(find.byKey(_copiedKey), findsOneWidget);
        expect(_button(tester, _copyKey).tooltip, 'Copied');
        await tester.pump(const Duration(milliseconds: 1));
        expect(tester.binding.clock.now(), feedbackDeadline);
        expect(_button(tester, _copyKey).tooltip, 'Copy');
        _expectButtonSemantics(tester, _copyKey, label: 'Copy');
        await tester.pump(_fade);
        _expectFadedOut(tester, find.byKey(_copiedKey));
        _expectFadedOut(tester, find.byIcon(Icons.check_rounded));
        await tester.pump(_cleanupTick);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(_bounds(tester, filename: true), bounds);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _dispose(tester);
      }
    });

    testWidgets(
        '$mode: failures expose only friendly localized inline feedback',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _FakeMediaActionService();
      final error = _SensitiveFailure();
      try {
        await _pump(
          tester,
          _buttons(
            actions,
            source: _source(
              source: _sensitivePayload,
              name: _sensitivePayload,
              headers: const {'Authorization': _sensitivePayload},
            ),
          ),
          mode: mode,
        );
        final bounds = _bounds(tester);
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        actions.calls.single.fail(error);
        await tester.pump();
        await tester.pump(_fade);

        expect(actions.calls.single.finished, isTrue);
        expect(error.stringified, isFalse);
        expect(
          _button(tester, _copyKey).tooltip,
          LocaleKeys.message_copy_fail.tr(),
        );
        _expectButtonSemantics(
          tester,
          _copyKey,
          label: LocaleKeys.message_copy_fail.tr(),
          liveRegion: true,
        );
        expect(
          _buttonIcon(_copyKey, Icons.error_outline_rounded),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(_button(tester, _copyKey).onPressed, isNotNull);
        expect(_button(tester, _shareKey).onPressed, isNotNull);
        expect(_bounds(tester), bounds);

        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        _expectBusy(tester);
        actions.calls.last.fail(error);
        await tester.pump();
        await tester.pump(_fade);
        expect(_button(tester, _copyKey).tooltip, 'Copy');
        expect(
          _button(tester, _shareKey).tooltip,
          LocaleKeys.mediaActions_shareFailed.tr(),
        );
        _expectButtonSemantics(
          tester,
          _shareKey,
          label: LocaleKeys.mediaActions_shareFailed.tr(),
          liveRegion: true,
        );
        _expectButtonSemantics(tester, _copyKey, label: 'Copy');
        expect(
          _buttonIcon(_shareKey, Icons.error_outline_rounded),
          findsOneWidget,
        );
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.textContaining(_sensitivePayload), findsNothing);
        expect(
          find.bySemanticsLabel(RegExp(RegExp.escape(_sensitivePayload))),
          findsNothing,
        );
        expect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Tooltip &&
                (widget.message?.contains(_sensitivePayload) ?? false),
          ),
          findsNothing,
        );
        expect(error.stringified, isFalse);
        expect(_bounds(tester), bounds);

        // A subsequent successful copy is the only route back to a checkmark.
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        actions.calls.last.succeed();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsOneWidget);
        expect(find.byIcon(Icons.check_rounded), findsOneWidget);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _dispose(tester);
      }
    });
  }

  testWidgets(
      'semantic activation retains labels, native roles and the busy guard',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = _FakeMediaActionService();
    try {
      await _pump(
        tester,
        TooltipTheme(
          data: const TooltipThemeData(excludeFromSemantics: true),
          child: MediaActionReveal(visible: false, child: _buttons(actions)),
        ),
        accessibleNavigation: true,
      );
      _expectButtonSemantics(tester, _copyKey, label: 'Copy');
      _expectButtonSemantics(tester, _shareKey, label: 'Share');
      final copy = find.semantics.byLabel('Copy');
      final share = find.semantics.byLabel('Share');
      final bounds = _bounds(tester);
      tester.semantics.tap(copy);
      tester.semantics.tap(copy);
      tester.semantics.tap(share);
      await tester.pump();
      expect(actions.calls, hasLength(1));
      expect(actions.calls.single.kind, 'copy');
      _expectButtonSemantics(tester, _copyKey, label: 'Copy', enabled: false);
      _expectButtonSemantics(tester, _shareKey, label: 'Share', enabled: false);
      expect(find.byKey(_copiedKey), findsNothing);
      actions.calls.single.succeed();
      await tester.pump();
      _expectButtonSemantics(
        tester,
        _copyKey,
        label: 'Copied',
        liveRegion: true,
      );
      expect(find.semantics.byLabel('Copied'), findsOneWidget);
      expect(_bounds(tester), bounds);

      tester.semantics.tap(share);
      await tester.pump();
      expect(actions.calls, hasLength(2));
      expect(actions.calls.last.kind, 'share');
      expect(actions.calls.last.origin, tester.getRect(find.byKey(_shareKey)));
      actions.calls.last.succeed();
      await tester.pump();
      _expectButtonSemantics(tester, _copyKey, label: 'Copy');
      _expectButtonSemantics(tester, _shareKey, label: 'Share');
      expect(find.byKey(_copiedKey), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(_bounds(tester), bounds);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
      await _dispose(tester);
    }
  });

  testWidgets(
      'custom sizes and extremely narrow intrinsic hosts remain bounded',
      (tester) async {
    final actions = _FakeMediaActionService();
    try {
      await _pump(tester, _buttons(actions, buttonSize: 36));
      expect(tester.getSize(find.byKey(_barKey)), const Size(84, 44));
      expect(tester.getSize(find.byKey(_copyKey)), const Size.square(36));
      expect(tester.getSize(find.byKey(_shareKey)), const Size.square(36));
      await _pump(
        tester,
        SizedBox(
          width: 32,
          child: IntrinsicHeight(child: _buttons(actions)),
        ),
        textScale: 2,
      );
      expect(tester.getSize(find.byKey(_barKey)).width, 32);
      expect(actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets('a plain Material theme supplies its own floating color',
      (tester) async {
    const surface = Color(0xFFF4EEDC);
    final actions = _FakeMediaActionService();
    try {
      await _pump(
        tester,
        _buttons(actions),
        theme: ThemeData.light().copyWith(cardColor: surface),
      );
      expect(_surface(tester).color, surface);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets('hover fades both ways without invisible hits or idle semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final actions = _FakeMediaActionService();
    final mouse = await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
    try {
      await mouse.addPointer(location: Offset.zero);
      await _pump(tester, _hoverHost(actions));
      final state = tester.state(find.byType(MediaActionButtons));
      final restingSize = tester.getSize(find.byKey(_barKey));
      _expectReveal(tester, visible: false);
      expect(_paintedOpacity(tester), 0);
      expect(find.semantics.byLabel('Copy'), findsNothing);
      expect(find.semantics.byLabel('Share'), findsNothing);
      expect(find.byKey(_copyKey).hitTestable(), findsNothing);
      expect(find.byKey(_shareKey).hitTestable(), findsNothing);
      await tester.tapAt(tester.getCenter(find.byKey(_copyKey)));
      await tester.pump();
      expect(actions.calls, isEmpty);

      await mouse.moveTo(
        tester.getBottomLeft(find.byKey(_hostKey)) + const Offset(12, -12),
      );
      await tester.pump();
      _expectReveal(tester, visible: true);
      await tester.pump(const Duration(milliseconds: 70));
      expect(_paintedOpacity(tester), greaterThan(0));
      expect(_paintedOpacity(tester), lessThan(1));
      await tester.pump(const Duration(milliseconds: 70));
      expect(_paintedOpacity(tester), 1);
      expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
      expect(find.bySemanticsLabel('Copy'), findsOneWidget);
      expect(find.bySemanticsLabel('Share'), findsOneWidget);
      _expectButtonSemantics(tester, _copyKey, label: 'Copy');
      _expectButtonSemantics(tester, _shareKey, label: 'Share');
      expect(actions.calls, isEmpty);

      await mouse.moveTo(Offset.zero);
      await tester.pump();
      // The fade has only just started; hit testing and semantics are already off.
      _expectReveal(tester, visible: false);
      expect(_paintedOpacity(tester), 1);
      expect(find.semantics.byLabel('Copy'), findsNothing);
      expect(find.semantics.byLabel('Share'), findsNothing);
      expect(find.byKey(_copyKey).hitTestable(), findsNothing);
      expect(find.byKey(_shareKey).hitTestable(), findsNothing);
      await tester.tapAt(tester.getCenter(find.byKey(_shareKey)));
      await tester.pump();
      expect(actions.calls, isEmpty);
      await tester.pump(_fade);
      expect(_paintedOpacity(tester), 0);
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(tester.getSize(find.byKey(_barKey)), restingSize);

      await mouse.moveTo(tester.getCenter(find.byKey(_hostKey)));
      await tester.pump();
      await tester.pump(_fade);
      final position = tester.getCenter(find.byKey(_copyKey));
      await mouse.moveTo(position);
      await tester.pump();
      await mouse.down(position);
      await mouse.up();
      await tester.pump();
      expect(actions.calls, hasLength(1));
      actions.calls.single.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsOneWidget);
      expect(_badgeOpacity(tester), 1);
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(tester.takeException(), isNull);
    } finally {
      await mouse.removePointer();
      semantics.dispose();
      await _dispose(tester);
    }
  });

  testWidgets(
    'hidden reveal keeps Tab order, focus on pointer exit, and reverse traversal',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _FakeMediaActionService();
      final before = FocusNode();
      final after = FocusNode();
      final mouse =
          await tester.createGesture(kind: ui.PointerDeviceKind.mouse);
      try {
        await _pump(
          tester,
          _focusHost(
            before: before,
            after: after,
            child: MediaActionReveal(visible: false, child: _buttons(actions)),
          ),
        );
        expect(before.hasFocus, isTrue);
        _expectReveal(tester, visible: false);
        await _tab(tester);
        _expectReveal(tester, visible: true);
        expect(find.bySemanticsLabel('Copy'), findsOneWidget);
        expect(find.bySemanticsLabel('Share'), findsOneWidget);
        _expectButtonSemantics(tester, _copyKey, label: 'Copy');
        _expectButtonSemantics(tester, _shareKey, label: 'Share');
        expect(
          tester
              .getSemantics(find.byKey(_copyKey))
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );
        await mouse.addPointer(location: Offset.zero);
        await mouse.moveTo(tester.getCenter(find.byKey(_copyKey)));
        await tester.pump();
        await mouse.moveTo(Offset.zero);
        await tester.pump(_fade);
        _expectReveal(tester, visible: true);
        expect(
          tester
              .getSemantics(find.byKey(_copyKey))
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );

        await _tab(tester);
        expect(
          tester
              .getSemantics(find.byKey(_shareKey))
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );
        await _tab(tester);
        expect(after.hasFocus, isTrue);
        _expectReveal(tester, visible: false);
        expect(find.semantics.byLabel('Copy'), findsNothing);
        expect(find.semantics.byLabel('Share'), findsNothing);
        await _tab(tester, reverse: true);
        _expectReveal(tester, visible: true);
        expect(
          tester
              .getSemantics(find.byKey(_shareKey))
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );
        expect(actions.calls, isEmpty);
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pump();
        expect(actions.calls.single.kind, 'share');
        actions.calls.single.succeed();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(_button(tester, _shareKey).tooltip, 'Share');
        expect(tester.takeException(), isNull);
      } finally {
        await mouse.removePointer();
        semantics.dispose();
        await _dispose(tester);
        before.dispose();
        after.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'hover-region descendant focus reveals controls and Enter copies',
    (tester) async {
      final semantics = tester.ensureSemantics();
      final actions = _FakeMediaActionService();
      final before = FocusNode();
      final after = FocusNode();
      var visible = false;
      try {
        await _pump(
          tester,
          _focusHost(
            before: before,
            after: after,
            child: MediaHoverRegion(
              builder: (context, shown) {
                visible = shown;
                return MediaActionReveal(
                  visible: shown,
                  child: _buttons(actions),
                );
              },
            ),
          ),
        );
        expect(visible, isFalse);
        await _tab(tester);
        expect(visible, isTrue);
        _expectReveal(tester, visible: true);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        expect(actions.calls.single.kind, 'copy');
        expect(actions.calls.single.finished, isFalse);
        expect(find.byKey(_copiedKey), findsNothing);
        _expectReveal(tester, visible: true);
        actions.calls.single.succeed();
        await tester.pump();
        await tester.pump();
        await tester.pump(_fade);
        expect(_button(tester, _copyKey).tooltip, 'Copied');
        expect(_paintedOpacity(tester), 1);
        expect(_badgeOpacity(tester), 1);
        _expectButtonSemantics(
          tester,
          _copyKey,
          label: 'Copied',
          liveRegion: true,
        );
        expect(
          tester
              .getSemantics(find.byKey(_copyKey))
              .hasFlag(ui.SemanticsFlag.isFocused),
          isTrue,
        );
        await _tab(tester);
        expect(_button(tester, _shareKey).focusNode!.hasFocus, isTrue);
        await _tab(tester);
        expect(after.hasFocus, isTrue);
        _expectReveal(tester, visible: false);
        expect(tester.takeException(), isNull);
      } finally {
        semantics.dispose();
        await _dispose(tester);
        before.dispose();
        after.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  testWidgets(
    'a pending keyboard action does not reclaim focus after the user leaves',
    (tester) async {
      final actions = _FakeMediaActionService();
      final before = FocusNode();
      final after = FocusNode();
      try {
        await _pump(
          tester,
          _focusHost(
            before: before,
            after: after,
            child: MediaActionReveal(visible: false, child: _buttons(actions)),
          ),
        );
        await _tab(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pump();
        _expectBusy(tester);
        _expectReveal(tester, visible: true);
        after.requestFocus();
        await tester.pump();
        await tester.pump();
        expect(after.hasFocus, isTrue);
        _expectReveal(tester, visible: false);
        actions.calls.single.succeed();
        await tester.pump();
        await tester.pump();
        await tester.pump(_fade);
        expect(after.hasFocus, isTrue);
        expect(_button(tester, _copyKey).focusNode!.hasFocus, isFalse);
        _expectReveal(tester, visible: false);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester);
        before.dispose();
        after.dispose();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );

  for (final platform in [TargetPlatform.android, TargetPlatform.iOS]) {
    testWidgets('$platform: touch can activate controls without hovering',
        (tester) async {
      final actions = _FakeMediaActionService();
      try {
        await _pump(tester, _hoverHost(actions), platform: platform);
        _expectReveal(tester, visible: true);
        expect(actions.calls, isEmpty);
        expect(find.byKey(_shareKey).hitTestable(), findsOneWidget);
        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        expect(actions.calls.single.kind, 'share');
        expect(actions.calls.single.origin, isNotNull);
        actions.calls.single.succeed();
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester);
      }
    });
  }

  testWidgets(
      'accessible navigation reveals both wrappers without hover or focus',
      (tester) async {
    final actions = _FakeMediaActionService();
    try {
      await _pump(tester, _hoverHost(actions), accessibleNavigation: true);
      _expectReveal(tester, visible: true, duration: Duration.zero);
      expect(_paintedOpacity(tester), 1);
      expect(find.byKey(_copyKey).hitTestable(), findsOneWidget);
      await _pump(
        tester,
        MediaActionReveal(visible: false, child: _buttons(actions)),
        accessibleNavigation: true,
      );
      _expectReveal(tester, visible: true, duration: Duration.zero);
      expect(find.byKey(_shareKey).hitTestable(), findsOneWidget);
      await _pump(
        tester,
        MediaActionReveal(visible: false, child: _buttons(actions)),
      );
      _expectReveal(tester, visible: false);
      expect(actions.calls, isEmpty);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  for (final fail in [false, true]) {
    testWidgets(
        'source rebinding gates late ${fail ? 'failure' : 'success'} and holds the lock',
        (tester) async {
      final actions = _FakeMediaActionService();
      final first = _source();
      final second = _source(
        source: 'https://media.example.test/second.png',
        name: 'second.png',
      );
      var source = first;
      late StateSetter update;
      try {
        await _pump(
          tester,
          StatefulBuilder(
            builder: (context, setState) {
              update = setState;
              return _buttons(actions, source: source);
            },
          ),
        );
        final state = tester.state(find.byType(MediaActionButtons));
        final staleCopy = _button(tester, _copyKey).onPressed!;
        await tester.tap(find.byKey(_copyKey));
        await tester.pump();
        update(() => source = second);
        await tester.pump();
        _expectBusy(tester);
        staleCopy();
        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        expect(actions.calls, hasLength(1));
        expect(actions.calls.single.source, same(first));
        if (fail) {
          actions.calls.single.fail(_SensitiveFailure());
        } else {
          actions.calls.single.succeed();
        }
        await tester.pump();
        await tester.pump(_fade);
        expect(find.byKey(_copiedKey), findsNothing);
        expect(find.byIcon(Icons.check_rounded), findsNothing);
        expect(find.byIcon(Icons.error_outline_rounded), findsNothing);
        expect(_button(tester, _copyKey).tooltip, 'Copy');
        expect(_button(tester, _copyKey).onPressed, isNotNull);
        staleCopy();
        expect(actions.calls, hasLength(1));
        await tester.tap(find.byKey(_shareKey));
        await tester.pump();
        expect(actions.calls, hasLength(2));
        expect(actions.calls.last.source, same(second));
        actions.calls.last.succeed();
        await tester.pump();
        expect(tester.state(find.byType(MediaActionButtons)), same(state));
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester);
      }
    });
  }

  testWidgets(
      'equal snapshots preserve feedback; credential changes clear it immediately',
      (tester) async {
    final actions = _FakeMediaActionService();
    final headers = {'Authorization': 'test-one', 'X-Test': 'snapshot'};
    var source = _source(headers: headers);
    late StateSetter update;
    try {
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _buttons(actions, source: source);
          },
        ),
      );
      // The service's value object snapshots credentials, not the mutable map.
      headers['Authorization'] = 'mutated-after-construction';
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      expect(
        actions.calls.single.source.httpHeaders['Authorization'],
        'test-one',
      );
      actions.calls.single.succeed();
      await tester.pump();
      await tester.pump(_fade);
      final staleShare = _button(tester, _shareKey).onPressed!;

      update(() {
        source = _source(
          headers: const {'X-Test': 'snapshot', 'Authorization': 'test-one'},
        );
      });
      await tester.pump();
      expect(find.byKey(_copiedKey), findsOneWidget);
      expect(_button(tester, _copyKey).tooltip, 'Copied');
      update(() {
        source = _source(
          headers: const {'X-Test': 'snapshot', 'Authorization': 'test-two'},
        );
      });
      await tester.pump();
      // Not even an outgoing AnimatedSwitcher child may carry the old check.
      expect(find.byKey(_copiedKey), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(_button(tester, _copyKey).tooltip, 'Copy');
      staleShare();
      expect(actions.calls, hasLength(1));
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      expect(
        actions.calls.last.source.httpHeaders['Authorization'],
        'test-two',
      );
      actions.calls.last.succeed();
      await tester.pump();
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets('A to B to A does not revive an obsolete completion',
      (tester) async {
    final actions = _FakeMediaActionService();
    final first = _source();
    var source = first;
    late StateSetter update;
    try {
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _buttons(actions, source: source);
          },
        ),
      );
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      update(() => source = _source(name: 'another-name.png'));
      await tester.pump();
      update(() => source = first);
      await tester.pump();
      actions.calls.single.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsNothing);
      expect(_button(tester, _copyKey).tooltip, 'Copy');
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets(
      'replacing the service does not retarget an operation or its completion',
      (tester) async {
    final first = _FakeMediaActionService();
    final second = _FakeMediaActionService();
    var actions = first;
    late StateSetter update;
    try {
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return _buttons(actions);
          },
        ),
      );
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      update(() => actions = second);
      await tester.pump();
      _expectBusy(tester);
      expect(second.calls, isEmpty);
      first.calls.single.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsNothing);
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      expect(first.calls, hasLength(1));
      expect(second.calls, hasLength(1));
      second.calls.single.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets(
      'repeated copies restart the feedback timer rather than racing it',
      (tester) async {
    final actions = _FakeMediaActionService();
    try {
      await _pump(tester, _buttons(actions));
      await tester.tap(find.byKey(_copyKey));
      actions.calls.single.succeed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byKey(_copiedKey), findsOneWidget);
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      expect(find.byKey(_copiedKey), findsNothing);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      actions.calls.last.succeed();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1000));
      expect(find.byKey(_copiedKey), findsOneWidget);
      expect(_button(tester, _copyKey).tooltip, 'Copied');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsNothing);
      expect(_button(tester, _copyKey).tooltip, 'Copy');
      expect(actions.calls, hasLength(2));
      expect(actions.calls.every((call) => call.finished), isTrue);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets(
      'share captures its transformed global anchor before the pending future',
      (tester) async {
    final actions = _FakeMediaActionService();
    final source = _source(shareAsLink: true);
    var offset = const Offset(38, 24);
    late StateSetter update;
    try {
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return Transform.translate(
              offset: offset,
              child: Transform.scale(
                scale: 1.25,
                child: _buttons(actions, source: source),
              ),
            );
          },
        ),
        platform: TargetPlatform.iOS,
      );
      final box = tester.renderObject<RenderBox>(find.byKey(_shareKey));
      final expectedOrigin = Rect.fromPoints(
        box.localToGlobal(Offset.zero),
        box.localToGlobal(box.size.bottomRight(Offset.zero)),
      );
      final bounds = _bounds(tester);
      final copyDuringShare = _button(tester, _copyKey).onPressed!;
      final shareAgain = _button(tester, _shareKey).onPressed!;
      await tester.tapAt(expectedOrigin.center);
      expect(actions.calls, hasLength(1));
      final call = actions.calls.single;
      expect(call.kind, 'share');
      expect(call.source, same(source));
      expect(call.origin, expectedOrigin);
      expect(call.origin!.isFinite, isTrue);
      expect(call.origin!.isEmpty, isFalse);
      expect(call.finished, isFalse);
      copyDuringShare();
      shareAgain();
      await tester.pump();
      _expectBusy(tester);
      expect(actions.calls, hasLength(1));
      expect(_bounds(tester), bounds);
      update(() => offset = const Offset(-44, 60));
      await tester.pump();
      expect(call.origin, expectedOrigin);
      expect(box.localToGlobal(Offset.zero), isNot(expectedOrigin.topLeft));
      call.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(call.finished, isTrue);
      expect(find.byIcon(Icons.check_rounded), findsNothing);
      expect(find.byKey(_copiedKey), findsNothing);
      expect(_button(tester, _shareKey).tooltip, 'Share');
      expect(find.textContaining('Shared'), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets('the visible Copied badge never intercepts the media below it',
      (tester) async {
    final actions = _FakeMediaActionService();
    var backgroundTaps = 0;
    try {
      await _pump(
        tester,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => backgroundTaps++,
          child: SizedBox(
            width: 240,
            height: 140,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned(top: 60, right: 10, child: _buttons(actions)),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byKey(_copyKey));
      actions.calls.single.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(backgroundTaps, 0);
      expect(_badgeOpacity(tester), 1);
      await tester.tapAt(tester.getCenter(find.byKey(_copiedKey)));
      await tester.pump();
      expect(backgroundTaps, 1);
      expect(actions.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  for (final key in [_copyKey, _shareKey]) {
    for (final fail in [false, true]) {
      testWidgets(
          '$key: dispose ignores a pending ${fail ? 'failure' : 'success'}',
          (tester) async {
        final actions = _FakeMediaActionService();
        try {
          await _pump(tester, _buttons(actions));
          final stalePress = _button(tester, key).onPressed!;
          await tester.tap(find.byKey(key));
          await tester.pump();
          expect(actions.calls.single.finished, isFalse);
          await _dispose(tester);
          stalePress();
          expect(actions.calls, hasLength(1));
          if (fail) {
            actions.calls.single.fail(_SensitiveFailure());
          } else {
            actions.calls.single.succeed();
          }
          await tester.pump();
          expect(actions.calls.single.finished, isTrue);
          expect(find.byKey(_copiedKey), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester);
        }
      });
    }
  }

  testWidgets(
      'dispose cancels a live feedback timer without advancing its deadline',
      (tester) async {
    final actions = _FakeMediaActionService();
    try {
      await _pump(tester, _buttons(actions));
      await tester.tap(find.byKey(_copyKey));
      actions.calls.single.succeed();
      await tester.pump();
      await tester.pump(_fade);
      expect(find.byKey(_copiedKey), findsOneWidget);
      await _dispose(tester);
      // Do not pump 1600ms here: Flutter's pending-timer invariant must catch a
      // leaked timer, rather than letting the test drain it accidentally.
      expect(tester.binding.transientCallbackCount, 0);
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });

  testWidgets(
      'reduced motion skips fades and slide and keeps pending progress still',
      (tester) async {
    final actions = _FakeMediaActionService();
    var visible = false;
    late StateSetter update;
    try {
      await _pump(
        tester,
        StatefulBuilder(
          builder: (context, setState) {
            update = setState;
            return MediaActionReveal(
              visible: visible,
              child: _buttons(actions),
            );
          },
        ),
        disableAnimations: true,
      );
      final state = tester.state(find.byType(MediaActionButtons));
      _expectReveal(tester, visible: false, duration: Duration.zero);
      update(() => visible = true);
      await tester.pump();
      await tester.pump();
      _expectReveal(tester, visible: true, duration: Duration.zero);
      expect(_paintedOpacity(tester), 1);
      final slide = tester.widget<AnimatedSlide>(find.byType(AnimatedSlide));
      expect(slide.duration, Duration.zero);
      expect(slide.offset, Offset.zero);
      expect(find.byType(AnimatedSize), findsNothing);
      for (final switcher in tester
          .widgetList<AnimatedSwitcher>(find.byType(AnimatedSwitcher))) {
        expect(switcher.duration, Duration.zero);
      }
      for (final key in [_copyKey, _shareKey]) {
        expect(_button(tester, key).style!.animationDuration, Duration.zero);
      }
      await tester.tap(find.byKey(_copyKey));
      await tester.pump();
      final progress = tester.widget<CircularProgressIndicator>(
        find.byType(CircularProgressIndicator),
      );
      expect(progress.value, isNotNull);
      expect(find.byKey(_copiedKey), findsNothing);
      actions.calls.single.succeed();
      await tester.pump();
      await tester.pump();
      expect(find.byKey(_copiedKey), findsOneWidget);
      expect(_badgeOpacity(tester), 1);
      update(() => visible = false);
      await tester.pump();
      await tester.pump();
      _expectReveal(tester, visible: false, duration: Duration.zero);
      expect(_paintedOpacity(tester), 0);
      expect(tester.state(find.byType(MediaActionButtons)), same(state));
      expect(actions.calls, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await _dispose(tester);
    }
  });
}

MediaActionSource _source({
  String source = 'https://media.example.test/photo.png',
  String name = 'photo.png',
  bool shareAsLink = false,
  Map<String, String> headers = const {},
}) =>
    MediaActionSource(
      source: source,
      name: name,
      isImage: true,
      shareAsLink: shareAsLink,
      httpHeaders: headers,
    );

Widget _buttons(
  _FakeMediaActionService actions, {
  MediaActionSource? source,
  bool decorated = true,
  double buttonSize = 28,
}) =>
    MediaActionButtons(
      key: _barKey,
      source: source ?? _source(),
      actions: actions,
      decorated: decorated,
      buttonSize: buttonSize,
    );

Widget _hoverHost(_FakeMediaActionService actions) => MediaHoverRegion(
      builder: (context, visible) => SizedBox(
        key: _hostKey,
        width: 180,
        height: 100,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            Positioned.fill(
              child:
                  ColoredBox(color: Theme.of(context).scaffoldBackgroundColor),
            ),
            Positioned(
              top: 28,
              right: 8,
              child:
                  MediaActionReveal(visible: visible, child: _buttons(actions)),
            ),
          ],
        ),
      ),
    );

Widget _focusHost({
  required FocusNode before,
  required FocusNode after,
  required Widget child,
}) =>
    Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextButton(
          autofocus: true,
          focusNode: before,
          onPressed: () {},
          child: const Text('Before media'),
        ),
        child,
        TextButton(
          focusNode: after,
          onPressed: () {},
          child: const Text('After media'),
        ),
      ],
    );

IconButton _button(WidgetTester tester, Key key) =>
    tester.widget<IconButton>(find.byKey(key));

BoxDecoration _surface(WidgetTester tester) =>
    tester.widget<DecoratedBox>(find.byKey(_surfaceKey)).decoration
        as BoxDecoration;

void _expectButtonSemantics(
  WidgetTester tester,
  Key key, {
  required String label,
  bool enabled = true,
  bool liveRegion = false,
}) {
  final node = tester.getSemantics(find.byKey(key));
  // Check the native actionable node, not a separately labelled ancestor.
  expect(node.attached, isTrue);
  expect(find.semantics.byLabel(label).evaluate(), contains(same(node)));
  expect(node.label, label);
  expect(node.tooltip, isEmpty);
  expect(node.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(node.hasFlag(ui.SemanticsFlag.hasEnabledState), isTrue);
  expect(node.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
  expect(node.hasFlag(ui.SemanticsFlag.isLiveRegion), liveRegion);
  expect(node.getSemanticsData().hasAction(ui.SemanticsAction.tap), enabled);
}

Finder _buttonIcon(Key key, IconData icon) =>
    find.descendant(of: find.byKey(key), matching: find.byIcon(icon));

List<Rect> _bounds(WidgetTester tester, {bool filename = false}) => [
      for (final key in [
        _barKey,
        _copyKey,
        _shareKey,
        if (filename) _filenameKey,
      ])
        tester.getRect(find.byKey(key)),
    ];

void _expectBusy(WidgetTester tester) {
  expect(_button(tester, _copyKey).onPressed, isNull);
  expect(_button(tester, _shareKey).onPressed, isNull);
}

void _expectReveal(
  WidgetTester tester, {
  required bool visible,
  Duration duration = _fade,
}) {
  final reveal = find.byKey(_revealKey);
  final opacity = tester.widget<AnimatedOpacity>(reveal);
  expect(opacity.opacity, visible ? 1 : 0);
  expect(opacity.duration, duration);
  expect(
    tester
        .widget<IgnorePointer>(
          find.ancestor(of: reveal, matching: find.byType(IgnorePointer)).first,
        )
        .ignoring,
    !visible,
  );
  expect(
    tester
        .widget<ExcludeSemantics>(
          find
              .ancestor(of: reveal, matching: find.byType(ExcludeSemantics))
              .first,
        )
        .excluding,
    !visible,
  );
}

double _paintedOpacity(WidgetTester tester) => tester
    .widget<FadeTransition>(
      find
          .descendant(
            of: find.byKey(_revealKey),
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

double _badgeOpacity(WidgetTester tester) =>
    _fadeOpacity(tester, find.byKey(_copiedKey));

double _fadeOpacity(WidgetTester tester, Finder child) => tester
    .widget<FadeTransition>(
      find
          .ancestor(
            of: child,
            matching: find.byType(FadeTransition),
          )
          .first,
    )
    .opacity
    .value;

void _expectFadedOut(WidgetTester tester, Finder outgoing) {
  // A newer SDK may already have removed the child at the exact endpoint.
  for (final element in outgoing.evaluate()) {
    expect(_fadeOpacity(tester, find.byWidget(element.widget)), 0);
  }
}

Future<void> _tab(WidgetTester tester, {bool reverse = false}) async {
  if (reverse) {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  }
  await tester.sendKeyEvent(LogicalKeyboardKey.tab);
  if (reverse) {
    await tester.sendKeyUpEvent(LogicalKeyboardKey.shiftLeft);
  }
  // Focus notifications may schedule their rebuild after the first pump.
  await tester.pump();
  await tester.pump();
  await tester.pump(_fade);
}

ThemeData _theme(String mode) => DesktopAppearance().getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    );

Future<void> _pump(
  WidgetTester tester,
  Widget child, {
  String mode = 'light',
  TargetPlatform platform = TargetPlatform.windows,
  double textScale = 1,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: (theme ?? _theme(mode)).copyWith(platform: platform),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: disableAnimations,
              accessibleNavigation: accessibleNavigation,
            ),
            child: child!,
          ),
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    ),
  );
  // Only used before an action is pending. Pending futures are advanced by the
  // tests themselves, never by pumpAndSettle or a real platform implementation.
  await tester.pumpAndSettle();
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// No clipboard/share/network implementation is reachable through this fake.
class _FakeMediaActionService implements MediaActionService {
  final calls = <_MediaCall>[];

  @override
  Future<void> copy(MediaActionSource source) => _begin('copy', source, null);

  @override
  Future<void> share(MediaActionSource source, {Rect? sharePositionOrigin}) =>
      _begin('share', source, sharePositionOrigin);

  Future<void> _begin(
    String kind,
    MediaActionSource source,
    Rect? origin,
  ) async {
    final call = _MediaCall(kind, source, origin);
    calls.add(call);
    try {
      await call.completion.future;
    } finally {
      call.finished = true;
    }
  }

  // Unexpected service API calls fail instead of delegating to the platform.
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _MediaCall {
  _MediaCall(this.kind, this.source, this.origin);

  final String kind;
  final MediaActionSource source;
  final Rect? origin;
  final completion = Completer<void>();
  bool finished = false;

  void succeed() => completion.complete();

  void fail(Object error) =>
      completion.completeError(error, StackTrace.current);
}

class _SensitiveFailure implements Exception {
  bool stringified = false;

  @override
  String toString() {
    stringified = true;
    return _sensitivePayload;
  }
}
