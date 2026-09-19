import 'dart:async';
import 'dart:ui' as ui;

import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/field/property_style.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/header/column_heading_menu.dart';
import 'package:appflowy/plugins/database/grid/presentation/widgets/row/cell_menu.dart';
import 'package:appflowy/plugins/database/widgets/cell/property_style_cell.dart';
import 'package:appflowy/plugins/database/widgets/field/type_option_editor/property_style_editor.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/interactive/interactive_style.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/progress_bar.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/test_asset_bundle.dart';

const _progress = PropertyStyle(kind: PropertyStyleKind.progress);
const _valueKey = ValueKey('property-progress-value');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  for (final mode in ['light', 'dark', 'paper']) {
    testWidgets('$mode: default buttons, readout and hover use the palette',
        (tester) async {
      final changes = <String>[];
      await _pumpProgress(tester, mode: mode, onChanged: changes.add);
      final palette = interactivePaletteOf(
        tester.element(find.byType(PropertyValueControl)),
      );
      final colors = ProgressBarColors.of(
        tester.element(find.byType(PropertyValueControl)),
      );
      final track = tester.widget<PropertyProgressTrack>(_track);
      final shell = tester.widget<AnimatedContainer>(
        find.descendant(
          of: find.byType(PropertyValueControl),
          matching: find.byType(AnimatedContainer),
        ),
      );
      expect((shell.decoration! as BoxDecoration).color, isNull);
      expect(track.fill, colors.fill);
      expect(track.highlight, colors.highlight);
      expect(track.track, colors.track);
      expect(track.fill.g, greaterThan(track.fill.r));
      expect(track.fill.g, greaterThan(track.fill.b));
      expect(find.text('40%'), findsOneWidget);
      expect(_button(true), findsOneWidget);
      expect(_button(false), findsOneWidget);
      expect(tester.getSize(_track).height, greaterThanOrEqualTo(32));
      final button = tester.widget<TextButton>(_button(true));
      expect(button.style!.backgroundColor!.resolve({})!.a, 0);
      expect(button.style!.shape!.resolve({}), isA<CircleBorder>());
      expect(
        button.style!.overlayColor!.resolve({WidgetState.hovered}),
        colors.fill.withValues(alpha: 0.2),
      );
      expect(button.style!.foregroundColor!.resolve({}), palette.textSecondary);
      expect(
        button.style!.foregroundColor!.resolve({WidgetState.hovered}),
        colors.ink,
      );
      if (mode == 'paper') {
        expect(palette.isPaper, isTrue);
        expect(track.fill, const Color(0xFF588C42));
        expect(
          track.track,
          Color.alphaBlend(
            colors.fill.withValues(alpha: 0.07),
            PaperTheme.editorPreviewBackground,
          ),
        );
      }
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: tester.getCenter(_button(true)));
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      await mouse.removePointer();
      await tester.tap(_button(true));
      await tester.pumpAndSettle();
      expect(changes, ['41']);
      expect(find.text('41%'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    for (final buttons in [true, false]) {
      testWidgets('$mode: $buttons buttons fit a narrow scaled intrinsic row',
          (tester) async {
        final semantics = tester.ensureSemantics();
        final changes = <String>[];
        await _pumpProgress(
          tester,
          mode: mode,
          width: 110,
          scale: 2,
          style: _progress.withSetting('show_buttons', buttons),
          onChanged: changes.add,
        );
        expect(tester.takeException(), isNull);
        expect(tester.getSize(_track).width, greaterThan(0));
        expect(
          find.descendant(of: _track, matching: find.byType(LayoutBuilder)),
          findsNothing,
        );
        expect(tester.getSemantics(find.byKey(_valueKey)).value, '40%');
        expect(changes, isEmpty);
        if (buttons) {
          await tester.tap(_button(true));
        } else {
          await tester.tap(_track);
        }
        await tester.pumpAndSettle();
        expect(changes, [buttons ? '41' : '50']);
        expect(tester.takeException(), isNull);
        semantics.dispose();
      });
    }

    testWidgets('$mode: readonly has no pointer, keyboard or semantic writes',
        (tester) async {
      final semantics = tester.ensureSemantics();
      final changes = <String>[];
      await _pumpProgress(
        tester,
        mode: mode,
        enabled: false,
        onChanged: changes.add,
      );
      expect(tester.widget<TextButton>(_button(true)).onPressed, isNull);
      expect(tester.widget<TextButton>(_button(false)).onPressed, isNull);
      final track = tester.widget<PropertyProgressTrack>(_track);
      expect(track.onScrub, isNull);
      expect(track.onScrubEnd, isNull);
      final node = tester.getSemantics(find.byKey(_valueKey));
      final data = node.getSemanticsData();
      expect(data.hasFlag(ui.SemanticsFlag.isEnabled), isFalse);
      expect(data.hasAction(ui.SemanticsAction.increase), isFalse);
      expect(data.hasAction(ui.SemanticsAction.decrease), isFalse);
      node.owner!.performAction(node.id, ui.SemanticsAction.increase);
      node.owner!.performAction(node.id, ui.SemanticsAction.decrease);
      await tester.tap(_button(true), warnIfMissed: false);
      await tester.tap(_track, warnIfMissed: false);
      _progressFocus(tester).requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyEvent(LogicalKeyboardKey.end);
      await tester.pumpAndSettle();
      expect(changes, isEmpty);
      expect(find.text('40%'), findsOneWidget);
      expect(tester.takeException(), isNull);
      semantics.dispose();
    });
  }

  testWidgets('rapid clicks survive stale rebuilds and intermediate echoes',
      (tester) async {
    final changes = <String>[];
    await _pumpProgress(tester, onChanged: changes.add);
    // No pump or value propagation between presses.
    await tester.tap(_button(true));
    await tester.tap(_button(true));
    await tester.tap(_button(true));
    await tester.pumpAndSettle();
    expect(changes, ['41', '42', '43']);
    await _pumpProgress(tester, onChanged: changes.add);
    expect(find.text('43%'), findsOneWidget);
    await _pumpProgress(tester, value: '41', onChanged: changes.add);
    expect(find.text('43%'), findsOneWidget);
    await tester.tap(_button(true));
    await tester.pumpAndSettle();
    expect(changes.last, '44');
    await _pumpProgress(tester, value: '44', onChanged: changes.add);
    expect(find.text('44%'), findsOneWidget);
    // An independent edit is adopted once the echoes have caught up.
    await _pumpProgress(tester, value: '10', onChanged: changes.add);
    await tester.tap(_button(true));
    await tester.pumpAndSettle();
    expect(changes.last, '11');
  });

  testWidgets('reversing before an echo reports the original value again',
      (tester) async {
    final changes = <String>[];
    await _pumpProgress(tester, value: '0', onChanged: changes.add);
    await tester.tap(_button(true));
    await tester.pump();
    await tester.tap(_button(false));
    await tester.pumpAndSettle();
    expect(changes, ['1', '0']);
    expect(find.text('0%'), findsOneWidget);
  });

  for (final sample in <(String, double, double, bool, String)>[
    ('0.9', 0.3, 1, true, '1'),
    ('0.1', 0.3, 1, false, '0'),
    ('0.25', 0.1, 1, true, '0.35'),
    ('0.1', 0.2, 1, true, '0.3'),
    ('0.995', 0.001, 1, true, '0.996'),
    ('0.0004', 0.0001, 0.001, true, '0.0005'),
    ('0.75', 0.5, 1.1, true, '1.1'),
    ('5', 100, 10, true, '10'),
    ('5', 100, 10, false, '0'),
  ]) {
    testWidgets('step ${sample.$2} from ${sample.$1} clamps to ${sample.$5}',
        (tester) async {
      final changes = <String>[];
      await _pumpProgress(
        tester,
        value: sample.$1,
        style: PropertyStyle(
          kind: PropertyStyleKind.progress,
          settings: {
            'maximum': sample.$3,
            'step': sample.$2,
            'show_percent': false,
          },
        ),
        onChanged: changes.add,
      );
      await tester.tap(_button(sample.$4));
      await tester.pumpAndSettle();
      expect(changes, [sample.$5]);
      expect(
        find.text('${sample.$5}/${formatProgressNumber(sample.$3)}'),
        findsOneWidget,
      );
      expect(double.parse(changes.single), inInclusiveRange(0, sample.$3));
    });
  }

  testWidgets('huge finite addition saturates without integer overflow',
      (tester) async {
    final changes = <String>[];
    await _pumpProgress(
      tester,
      value: '8e307',
      style: const PropertyStyle(
        kind: PropertyStyleKind.progress,
        settings: {'maximum': 1e308, 'step': 8e307, 'show_percent': false},
      ),
      onChanged: changes.add,
    );
    await tester.tap(_button(true));
    await tester.pumpAndSettle();
    expect(double.parse(changes.single), 1e308);
    expect(tester.widget<TextButton>(_button(true)).onPressed, isNull);
    expect(tester.takeException(), isNull);
  });

  for (final sample in {
    '': 0,
    'not a number': 0,
    'NaN': 0,
    'Infinity': 0,
    '-Infinity': 0,
    '1e999': 0,
    '-20': 0,
    '999': 10,
  }.entries) {
    testWidgets('invalid/out-of-range cell "${sample.key}" is safe to adjust',
        (tester) async {
      final changes = <String>[];
      await _pumpProgress(
        tester,
        value: sample.key,
        style: _progress.withSetting('maximum', 10),
        onChanged: changes.add,
      );
      expect(
        tester.widget<PropertyProgressTrack>(_track).fraction,
        sample.value / 10,
      );
      expect(changes, isEmpty);
      await tester.tap(_button(sample.value == 0));
      await tester.pumpAndSettle();
      expect(changes, [sample.value == 0 ? '1' : '9']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('legacy invalid bounds and steps render with safe defaults',
      (tester) async {
    final changes = <String>[];
    await _pumpProgress(
      tester,
      style: const PropertyStyle(
        kind: PropertyStyleKind.progress,
        settings: {'maximum': double.nan, 'step': double.infinity},
      ),
      onChanged: changes.add,
    );
    expect(find.text('40%'), findsOneWidget);
    await tester.tap(_button(true));
    await tester.pumpAndSettle();
    expect(changes, ['41']);
    expect(tester.takeException(), isNull);
  });

  testWidgets('buttons and semantic actions disable at their respective bounds',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final changes = <String>[];
    await _pumpProgress(
      tester,
      value: '0',
      style: _progress.withSetting('maximum', 1),
      onChanged: changes.add,
    );
    expect(tester.widget<TextButton>(_button(false)).onPressed, isNull);
    var node = tester.getSemantics(find.byKey(_valueKey));
    expect(
      node.getSemanticsData().hasAction(ui.SemanticsAction.decrease),
      isFalse,
    );
    expect(node.getSemanticsData().increasedValue, '100%');
    node.owner!.performAction(node.id, ui.SemanticsAction.increase);
    await tester.pumpAndSettle();
    expect(changes, ['1']);
    expect(tester.widget<TextButton>(_button(true)).onPressed, isNull);
    node = tester.getSemantics(find.byKey(_valueKey));
    expect(
      node.getSemanticsData().hasAction(ui.SemanticsAction.increase),
      isFalse,
    );
    expect(node.getSemanticsData().decreasedValue, '0%');
    node.owner!.performAction(node.id, ui.SemanticsAction.decrease);
    await tester.pumpAndSettle();
    expect(changes, ['1', '0']);
    semantics.dispose();
  });

  testWidgets('keyboard works with hidden buttons and never writes past bounds',
      (tester) async {
    final changes = <String>[];
    await _pumpProgress(
      tester,
      value: '0.5',
      style: const PropertyStyle(
        kind: PropertyStyleKind.progress,
        settings: {'maximum': 1, 'step': 0.25, 'show_buttons': false},
      ),
      onChanged: changes.add,
    );
    expect(_button(true), findsNothing);
    _progressFocus(tester).requestFocus();
    await tester.pump();
    for (final key in [
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.arrowRight,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.home,
      LogicalKeyboardKey.arrowLeft,
      LogicalKeyboardKey.end,
      LogicalKeyboardKey.end,
    ]) {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }
    expect(changes, ['0.75', '1', '0.75', '0.5', '0', '1']);
    expect(find.text('100%'), findsOneWidget);
  });

  testWidgets('end buttons support keyboard activation', (tester) async {
    final changes = <String>[];
    await _pumpProgress(tester, onChanged: changes.add);
    Focus.of(tester.element(find.byIcon(Icons.add_rounded))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(changes, ['41']);
    Focus.of(tester.element(find.byIcon(Icons.remove_rounded))).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(changes, ['41', '40']);
  });

  testWidgets('disabling cancels a drag and stale callbacks cannot write',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final changes = <String>[];
    await _pumpProgress(tester, onChanged: changes.add);
    final stalePress = tester.widget<TextButton>(_button(true)).onPressed!;
    final staleTrack = tester.widget<PropertyProgressTrack>(_track);
    final rect = tester.getRect(_track);
    final gesture = await tester.startGesture(rect.center);
    await gesture.moveTo(Offset(rect.right - 2, rect.center.dy));
    await tester.pump();
    expect(changes, isEmpty);
    await _pumpProgress(tester, enabled: false, onChanged: changes.add);
    stalePress();
    staleTrack.onScrub!(0.8);
    staleTrack.onScrubEnd!();
    await gesture.up();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('40%'), findsOneWidget);
    expect(tester.takeException(), isNull);
    semantics.dispose();
  });

  for (final kind in [PointerDeviceKind.touch, PointerDeviceKind.mouse]) {
    testWidgets('$kind: click and frame-by-frame scrub beat actual grid scroll',
        (tester) async {
      final scroll = ScrollController();
      addTearDown(scroll.dispose);
      final changes = <String>[];
      var parentTaps = 0;
      await tester.pumpWidget(
        _app(
          child: _scrollingProgress(
            scroll: scroll,
            onChanged: changes.add,
            onTap: () => parentTaps++,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      final rect = tester.getRect(_track);
      // Near the top, well outside the six-pixel painted bar.
      final click = await tester.startGesture(
        Offset(rect.left + rect.width * 0.25, rect.top + 2),
        kind: kind,
      );
      await tester.pump();
      expect(changes, isEmpty);
      await click.up();
      await tester.pumpAndSettle();
      expect(changes, ['25']);
      changes.clear();
      final gesture = await tester.startGesture(
        Offset(rect.left + rect.width * 0.8, rect.center.dy),
        kind: kind,
      );
      for (final fraction in [0.7, 0.5, 0.2]) {
        await gesture.moveTo(
          Offset(rect.left + rect.width * fraction, rect.center.dy),
        );
        await tester.pump(const Duration(milliseconds: 16));
        expect(changes, isEmpty);
        expect(
          tester.widget<PropertyProgressTrack>(_track).fraction,
          closeTo(fraction, 1e-10),
        );
        _expectPaintedFraction(tester, fraction);
      }
      await gesture.up();
      await tester.pumpAndSettle();
      expect(changes, ['20']);
      expect(scroll.offset, 0);
      expect(parentTaps, 0);
      // The ancestor really can scroll when the pointer starts beside the cell.
      final viewport = tester.getRect(find.byType(SingleChildScrollView));
      final navigation = await tester.startGesture(
        Offset(viewport.right - 4, viewport.center.dy),
        kind: kind,
      );
      await navigation.moveBy(const Offset(-30, 0));
      await tester.pump();
      await navigation.moveBy(const Offset(-60, 0));
      await tester.pump();
      await navigation.up();
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(changes, ['20']);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('scrub clamps both ends and cancellation discards the preview',
      (tester) async {
    final changes = <String>[];
    await _pumpProgress(tester, onChanged: changes.add);
    final rect = tester.getRect(_track);
    final cancelled = await tester.startGesture(rect.center);
    await cancelled.moveTo(Offset(rect.right + 80, rect.center.dy));
    await tester.pump();
    expect(find.text('100%'), findsOneWidget);
    await cancelled.cancel();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('40%'), findsOneWidget);
    final drag = await tester.startGesture(rect.center);
    await drag.moveTo(Offset(rect.left - 80, rect.center.dy));
    await tester.pump();
    expect(find.text('0%'), findsOneWidget);
    await drag.up();
    await tester.pumpAndSettle();
    expect(changes, ['0']);
  });

  testWidgets('right clicking never sets progress', (tester) async {
    final changes = <String>[];
    await _pumpProgress(tester, onChanged: changes.add);
    final gesture = await tester.startGesture(
      tester.getCenter(_track),
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await gesture.up();
    await tester.pumpAndSettle();
    expect(changes, isEmpty);
    expect(find.text('40%'), findsOneWidget);
  });

  testWidgets('trackpad navigation over the bar scrolls without editing',
      (tester) async {
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final changes = <String>[];
    await tester.pumpWidget(
      _app(
        child: _scrollingProgress(scroll: scroll, onChanged: changes.add),
      ),
    );
    await tester.pumpAndSettle();
    final position = tester.getCenter(_track);
    await tester.sendEventToBinding(
      PointerPanZoomStartEvent(
        pointer: 21,
        device: 21,
        position: position,
      ),
    );
    for (final dx in [-60.0, -120.0]) {
      await tester.sendEventToBinding(
        PointerPanZoomUpdateEvent(
          pointer: 21,
          device: 21,
          position: position,
          pan: Offset(dx, 0),
          panDelta: const Offset(-60, 0),
        ),
      );
      await tester.pump();
    }
    await tester.sendEventToBinding(
      PointerPanZoomEndEvent(
        pointer: 21,
        device: 21,
        position: position,
      ),
    );
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(0));
    expect(changes, isEmpty);
    expect(tester.takeException(), isNull);
  });

  for (final reduceMotion in [false, true]) {
    testWidgets('value animation respects reduced motion: $reduceMotion',
        (tester) async {
      final value = ValueNotifier('20');
      addTearDown(value.dispose);
      await tester.pumpWidget(
        _app(
          reduceMotion: reduceMotion,
          child: ValueListenableBuilder<String>(
            valueListenable: value,
            builder: (_, raw, __) => _intrinsicRow(
              PropertyValueControl(
                style: _progress,
                value: raw,
                onChanged: (_) {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      _expectPaintedFraction(tester, 0.2);
      value.value = '80';
      await tester.pump();
      _expectPaintedFraction(tester, reduceMotion ? 0.8 : 0.2);
      final animation = tester.widget<TweenAnimationBuilder<double>>(
        find.descendant(
          of: _track,
          matching: find.byType(TweenAnimationBuilder<double>),
        ),
      );
      expect(
        animation.duration,
        reduceMotion ? Duration.zero : InteractiveMetrics.settle,
      );
      expect(
        tester.widget<TextButton>(_button(true)).style!.animationDuration,
        reduceMotion ? Duration.zero : InteractiveMetrics.hover,
      );
      await tester.pumpAndSettle();
      _expectPaintedFraction(tester, 0.8);
    });
  }

  for (final scope in ['column', 'cell', 'editor']) {
    testWidgets('$scope settings toggle buttons and update the correct scope',
        (tester) async {
      final styles = _settings();
      addTearDown(styles.dispose);
      final writes = <Map<String, Object?>>[];
      await tester.pumpWidget(_settingsApp(scope, styles, writes));
      await tester.pumpAndSettle();
      await _openSettings(tester, scope);
      await tester.tap(find.text('Show − / + buttons'));
      await tester.pumpAndSettle();
      expect(writes, [
        {'show_buttons': false},
      ]);
      expect(styles.value.cellStyle('field', 'edited')!.showButtons, isFalse);
      expect(
        styles.value.cellStyle('field', 'other')!.showButtons,
        scope == 'cell',
      );
      expect(
        find.byIcon(Icons.add_rounded),
        scope == 'cell' ? findsOneWidget : findsNothing,
      );
      await _openSettings(tester, scope);
      await tester.tap(find.text('Show − / + buttons'));
      await tester.pumpAndSettle();
      expect(writes.last, {'show_buttons': true});
      expect(find.byIcon(Icons.add_rounded), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$scope settings save fractional steps and reject invalid input',
        (tester) async {
      final styles = _settings();
      addTearDown(styles.dispose);
      final writes = <Map<String, Object?>>[];
      await tester.pumpWidget(_settingsApp(scope, styles, writes));
      await tester.pumpAndSettle();
      for (final setting in ['Step', 'Maximum']) {
        for (final invalid in [
          'NaN',
          'Infinity',
          '-2',
          '0',
          'invalid',
          '1e999',
        ]) {
          await _openSettings(tester, scope);
          await tester.tap(find.text(setting).first);
          await tester.pumpAndSettle();
          expect(find.byType(AFTextFieldDialog), findsOneWidget);
          await tester.enterText(find.byType(TextField), invalid);
          await tester.tap(find.text('Confirm'));
          await tester.pumpAndSettle();
          expect(writes, isEmpty, reason: '$setting = $invalid');
          expect(tester.takeException(), isNull);
        }
      }
      await _openSettings(tester, scope);
      await tester.tap(find.text('Step').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AFTextFieldDialog>(find.byType(AFTextFieldDialog))
            .initialValue,
        '0.25',
      );
      await tester.enterText(find.byType(TextField), '0.001');
      await tester.tap(find.text('Confirm'));
      await tester.pumpAndSettle();
      expect(writes, [
        {'step': 0.001},
      ]);
      expect(styles.value.cellStyle('field', 'edited')!.progressStep, 0.001);
      expect(
        styles.value.cellStyle('field', 'other')!.progressStep,
        scope == 'cell' ? 0.25 : 0.001,
      );
      // Cancellation is not an update either.
      await _openSettings(tester, scope);
      await tester.tap(find.text('Step').first);
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<AFTextFieldDialog>(find.byType(AFTextFieldDialog))
            .initialValue,
        '0.001',
      );
      await tester.enterText(find.byType(TextField), '7');
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(writes, hasLength(1));
      expect(tester.takeException(), isNull);
    });
  }
}

Finder get _track => find.byType(PropertyProgressTrack);

Finder _button(bool increase) => find.descendant(
      of: find.byKey(
        ValueKey(
          increase
              ? 'property-progress-increase'
              : 'property-progress-decrease',
        ),
      ),
      matching: find.byType(TextButton),
    );

FocusNode _progressFocus(WidgetTester tester) => tester
    .widget<FocusableActionDetector>(
      find.descendant(
        of: find.byKey(_valueKey),
        matching: find.byType(FocusableActionDetector),
      ),
    )
    .focusNode!;

void _expectPaintedFraction(WidgetTester tester, double fraction) {
  final paint = find.descendant(of: _track, matching: find.byType(CustomPaint));
  final size = tester.getSize(paint);
  expect(
    paint,
    paints
      ..rrect()
      ..rrect(
        rrect: RRect.fromRectAndRadius(
          Rect.fromLTWH(0, 0, size.width * fraction, size.height),
          Radius.circular(size.height / 2),
        ),
      ),
  );
}

Future<void> _pumpProgress(
  WidgetTester tester, {
  required ValueChanged<String> onChanged,
  String value = '40',
  PropertyStyle style = _progress,
  bool enabled = true,
  String mode = 'light',
  double width = 260,
  double scale = 1,
}) async {
  await tester.pumpWidget(
    _app(
      mode: mode,
      scale: scale,
      child: _intrinsicRow(
        PropertyValueControl(
          style: style,
          value: value,
          enabled: enabled,
          onChanged: onChanged,
        ),
        width: width,
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Widget _intrinsicRow(Widget child, {double width = 260}) => Center(
      child: SizedBox(
        width: width,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(width: 0, height: 36),
              Expanded(child: child),
            ],
          ),
        ),
      ),
    );

Widget _scrollingProgress({
  required ScrollController scroll,
  required ValueChanged<String> onChanged,
  VoidCallback? onTap,
}) =>
    Center(
      child: SizedBox(
        width: 280,
        height: 100,
        child: ScrollConfiguration(
          behavior: const ScrollBehavior().copyWith(
            dragDevices: PointerDeviceKind.values.toSet(),
            scrollbars: false,
          ),
          child: SingleChildScrollView(
            controller: scroll,
            scrollDirection: Axis.horizontal,
            child: SizedBox(
              width: 900,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: onTap,
                    child: _intrinsicRow(
                      PropertyValueControl(
                        style: _progress,
                        value: '40',
                        onChanged: onChanged,
                      ),
                      width: 240,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

ValueNotifier<PropertyStyles> _settings() => ValueNotifier(
      const PropertyStyles(
        byField: {
          'field': PropertyStyle(
            kind: PropertyStyleKind.progress,
            settings: {'maximum': 1, 'step': 0.25},
          ),
        },
      ),
    );

Future<void> _openSettings(WidgetTester tester, String scope) async {
  if (scope != 'editor') {
    await tester.tap(find.text('Open settings'));
    await tester.pumpAndSettle();
  }
}

Widget _settingsApp(
  String scope,
  ValueNotifier<PropertyStyles> styles,
  List<Map<String, Object?>> writes,
) =>
    _app(
      mode: 'paper',
      child: Center(
        child: SizedBox(
          width: 320,
          child: ValueListenableBuilder<PropertyStyles>(
            valueListenable: styles,
            builder: (context, current, _) {
              final style = current.cellStyle('field', 'edited')!;
              Future<void> write(Map<String, Object?> values) async {
                writes.add(values);
                if (scope == 'cell') {
                  styles.value = current.withCell('field', 'edited', {
                    ...current.cellOverride('field', 'edited'),
                    ...values,
                  });
                } else {
                  var next = current['field']!;
                  for (final entry in values.entries) {
                    next = next.withSetting(entry.key, entry.value);
                  }
                  styles.value = current.withField('field', next);
                }
              }

              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (scope == 'editor')
                    PropertyStyleEditor(
                      viewId: '',
                      fieldId: 'field',
                      style: style,
                      onSettingsChanged: write,
                    )
                  else
                    TextButton(
                      onPressed: () => unawaited(
                        showAppMenu<void>(
                          context: context,
                          globalPosition: const Offset(100, 50),
                          entries: scope == 'cell'
                              ? cellStyleMenuEntries(
                                  context: context,
                                  viewId: '',
                                  fieldId: 'field',
                                  rowId: 'edited',
                                  style: style,
                                  override:
                                      current.cellOverride('field', 'edited'),
                                  onSettingsChanged: write,
                                )
                              : columnHeadingMenuEntries(
                                  context: context,
                                  viewId: '',
                                  fieldInfo: FieldInfo.initial(
                                    FieldPB(
                                      id: 'field',
                                      name: 'Progress',
                                      fieldType: FieldType.RichText,
                                    ),
                                  ),
                                  style: current['field'],
                                  isLocation: false,
                                  onEditProperty: () {},
                                  onStyleSettingsChanged: write,
                                ),
                        ),
                      ),
                      child: const Text('Open settings'),
                    ),
                  for (final row in ['edited', 'other'])
                    PropertyValueControl(
                      key: ValueKey(row),
                      style: current.cellStyle('field', row)!,
                      value: '0.5',
                      onChanged: (_) {},
                    ),
                ],
              );
            },
          ),
        ),
      ),
    );

Widget _app({
  required Widget child,
  String mode = 'light',
  double scale = 1,
  bool reduceMotion = false,
}) {
  final brightness = mode == 'dark' ? Brightness.dark : Brightness.light;
  final materialTheme = DesktopAppearance()
      .getThemeData(
        mode == 'paper'
            ? AppTheme.builtins.firstWhere(
                (theme) => theme.themeName == BuiltInTheme.paper,
              )
            : AppTheme.fallback,
        brightness,
        defaultFontFamily,
        builtInCodeFontFamily,
      )
      .copyWith(platform: TargetPlatform.windows);
  final defaultTheme = AppFlowyDefaultTheme();
  final appFlowyTheme = PremiumTheme.appFlowyTheme(
    base: brightness == Brightness.dark
        ? defaultTheme.dark()
        : defaultTheme.light(),
    palette: materialTheme.extension<PremiumThemeExtension>()!,
    brightness: brightness,
  );
  return EasyLocalization(
    supportedLocales: const [Locale('en', 'US')],
    path: 'assets/translations',
    fallbackLocale: const Locale('en', 'US'),
    saveLocale: false,
    assetLoader: const TestBundleAssetLoader(),
    child: Builder(
      builder: (context) => MaterialApp(
        locale: const Locale('en', 'US'),
        localizationsDelegates: context.localizationDelegates,
        theme: materialTheme,
        themeAnimationDuration: Duration.zero,
        builder: (context, body) => AppFlowyTheme(
          data: appFlowyTheme,
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
              disableAnimations: reduceMotion,
            ),
            child: body!,
          ),
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
}
