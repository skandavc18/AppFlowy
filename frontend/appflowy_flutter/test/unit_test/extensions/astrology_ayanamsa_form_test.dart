import 'dart:async';
import 'dart:ui' show PointerDeviceKind, SemanticsFlag;

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_birth_form.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_location.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/shared/maps/map_geocoder.dart';
import 'package:appflowy/shared/maps/map_location.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _preset = 'astrology-ayanamsa';
const _adjust = 'astrology-ayanamsa-adjust';
const _direction = 'astrology-ayanamsa-direction';
const _degrees = 'astrology-ayanamsa-degrees';
const _minutes = 'astrology-ayanamsa-minutes';
const _seconds = 'astrology-ayanamsa-seconds';
const _reset = 'astrology-ayanamsa-reset';
const _generate = 'astrology-generate';
const _save = 'astrology-save';
const _dms = [_degrees, _minutes, _seconds];

const _newYork = AstrologyPlace(
  name: 'New York, United States',
  latitude: 40.712812345678,
  longitude: -74.006012345678,
  timeZone: 'America/New_York',
);

// Pin the public choices independently of the enum-driven production menu.
const _presets = [
  (value: AstrologyAyanamsa.lahiri, label: 'Lahiri'),
  (value: AstrologyAyanamsa.raman, label: 'B.V. Raman'),
  (value: AstrologyAyanamsa.krishnamurti, label: 'KP (Krishnamurti)'),
  (value: AstrologyAyanamsa.pushyaPaksha, label: 'Pushya Paksha'),
  (value: AstrologyAyanamsa.yukteshwar, label: 'Yukteshwar'),
  (value: AstrologyAyanamsa.suryaSiddhanta, label: 'Surya Siddhanta'),
  (value: AstrologyAyanamsa.trueChitra, label: 'True Chitra'),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('visible ayanamsha presets', () {
    _formTest('defaults to Lahiri and zero without opening Advanced',
        (form) async {
      await form.pump();

      expect(const AstrologyInput().ayanamsaOffsetArcseconds, 0);
      expect(_byId(_preset).hitTestable(), findsOneWidget);
      expect(_byId('astrology-latitude'), findsNothing);
      expect(_byId(_degrees), findsNothing);
      expect(_byId(_direction), findsNothing);
      expect(_byId(_reset), findsNothing);
      final dropdown = form.choice<AstrologyAyanamsa>(_preset);
      expect(dropdown.value, AstrologyAyanamsa.lahiri);
      expect(
        dropdown.items!.map((item) => item.value),
        _presets.map((preset) => preset.value),
      );
      expect(
        dropdown.items!.map((item) => (item.child as Text).data),
        _presets.map((preset) => preset.label),
      );
      expect(AstrologyAyanamsa.values, _presets.map((preset) => preset.value));
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);

      await form.tap(_generate);
      _expectInput(form.generated.single, form.input);
      expect(form.saved, isEmpty);
    });

    for (final preset in _presets) {
      _formTest(
        '${preset.label} submits only on request and preserves both DST instants',
        (form) async {
          // Both instants display 01:30:45 in New York. Neither the occurrence
          // nor the invisible millisecond/microsecond precision may change.
          for (final hour in [5, 6]) {
            final input = _storedInput(
              utcHour: hour,
              ayanamsa: preset.value == AstrologyAyanamsa.lahiri
                  ? AstrologyAyanamsa.raman
                  : AstrologyAyanamsa.lahiri,
              offset: -12.3456789012345,
            );
            final generatedBefore = form.generated.length;
            final savedBefore = form.saved.length;
            await form.pump(input: input);
            expect(form.controller('astrology-date').text, '2024-11-03');
            expect(form.controller('astrology-time').text, '01:30:45');
            await form.changeChoice(_preset, preset.value);

            expect(form.choice<AstrologyAyanamsa>(_preset).value, preset.value);
            expect(_byId('astrology-latitude'), findsNothing);
            expect(form.generated, hasLength(generatedBefore));
            expect(form.saved, hasLength(savedBefore));
            expect(input.ayanamsa, isNot(preset.value));
            final expected = input.copyWith(ayanamsa: preset.value);

            await form.tap(_generate);
            expect(form.generated, hasLength(generatedBefore + 1));
            expect(form.saved, hasLength(savedBefore));
            _expectInput(form.generated.last, expected);
            await form.tap(_save);
            expect(form.generated, hasLength(generatedBefore + 1));
            expect(form.saved, hasLength(savedBefore + 1));
            _expectInput(form.saved.last, expected);
          }
        },
      );
    }

    _formTest('real dropdown click and keyboard editing stay inside the form',
        (form) async {
      final tester = form.tester;
      final semantics = tester.ensureSemantics();
      var intercepted = 0;
      try {
        await form.pump(
          wrap: (child) => _claimBackspace(
            child,
            onIntercept: () => intercepted++,
          ),
        );
        await form.tap(_preset);
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(
          form.choice<AstrologyAyanamsa>(_preset).value,
          AstrologyAyanamsa.raman,
        );

        await form.tap(_adjust);
        await form.enterDms('0', '0', '12.50');
        await form.tap(_seconds);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        await tester.sendKeyEvent(
          LogicalKeyboardKey.backspace,
          physicalKey: PhysicalKeyboardKey.backspace,
          platform: 'windows',
        );
        await tester.pump();
        expect(form.controller(_seconds).text, '12.5');
        expect(form.editable(_seconds).focusNode.hasPrimaryFocus, isTrue);
        expect(
          tester
              .getSemantics(_editableFinder(_seconds))
              .hasFlag(SemanticsFlag.isFocused),
          isTrue,
        );
        expect(intercepted, 0);
        expect(form.generated, isEmpty);
        expect(form.saved, isEmpty);

        await form.tap(_generate);
        _expectInput(
          form.generated.single,
          form.input.copyWith(
            ayanamsa: AstrologyAyanamsa.raman,
            ayanamsaOffsetArcseconds: 12.5,
          ),
        );
      } finally {
        semantics.dispose();
      }
    });
  });

  group('signed DMS validation', () {
    for (final subtract in [false, true]) {
      _formTest(
          '${subtract ? 'Subtract' : 'Add'} applies the fractional DMS sum',
          (form) async {
        await form.pump();
        await form.tap(_adjust);
        expect(
          form.choice<bool>(_direction).items!.map((item) => item.value),
          [false, true],
        );
        await form.enterDms(' 1 ', '02', ' 3.125 ');
        await form.changeChoice(_direction, subtract);
        expect(form.generated, isEmpty);
        expect(form.saved, isEmpty);
        expect(form.input.ayanamsaOffsetArcseconds, 0);

        final expected = form.input.copyWith(
          ayanamsaOffsetArcseconds: subtract ? -3723.125 : 3723.125,
        );
        await form.tap(_generate);
        _expectInput(form.generated.single, expected);
        expect(form.saved, isEmpty);
        form.expectDms([' 1 ', '02', ' 3.125 ']);
        await form.tap(_save);
        _expectInput(form.saved.single, expected);
        expect(form.generated, hasLength(1));
        expect(form.choice<bool>(_direction).value, subtract);
      });
    }

    _formTest(
        'empty and whitespace-only components mean zero in either direction',
        (form) async {
      await form.pump(input: _storedInput(offset: -3723.5));
      await form.enterDms('', '   ', '');
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);
      await form.tap(_generate);
      _expectInput(
        form.generated.single,
        form.input.copyWith(ayanamsaOffsetArcseconds: 0),
      );
      await form.changeChoice(_direction, false);
      await form.tap(_save);
      _expectInput(
        form.saved.single,
        form.input.copyWith(ayanamsaOffsetArcseconds: 0),
      );
      form.expectDms(['', '   ', '']);
    });

    _formTest('accepts valid components immediately below the upper bounds',
        (form) async {
      await form.pump();
      await form.tap(_adjust);
      await form.enterDms('359', '59', '59.999');
      await form.tap(_generate);

      expect(
        form.generated.single.ayanamsaOffsetArcseconds,
        closeTo(1295999.999, 1e-9),
      );
      expect(form.generated.single.ayanamsaOffsetArcseconds, lessThan(1296000));
      expect(_byId('astrology-error'), findsNothing);
      form.expectDms(['359', '59', '59.999']);
    });

    for (final part in const [
      (id: _degrees, label: 'degrees', invalidRange: ['-1', '360']),
      (id: _minutes, label: 'minutes', invalidRange: ['-1', '60']),
      (id: _seconds, label: 'seconds', invalidRange: ['-0.001', '60']),
    ]) {
      _formTest('${part.label} rejects NaN, infinities and nonnumeric drafts',
          (form) async {
        await _pumpValidationDraft(form);
        for (final value in ['NaN', 'Infinity', '-Infinity', 'not a number']) {
          await _expectRejectedDraft(form, part.id, value);
        }
      });

      _formTest('${part.label} rejects negative and out-of-range drafts',
          (form) async {
        await _pumpValidationDraft(form);
        for (final value in part.invalidRange) {
          await _expectRejectedDraft(form, part.id, value);
        }
      });
    }

    for (final part in const [
      (id: _degrees, label: 'degrees'),
      (id: _minutes, label: 'minutes'),
    ]) {
      _formTest('fractional ${part.label} is rejected rather than truncated',
          (form) async {
        await _pumpValidationDraft(form);
        for (final value in ['1.5', '0.25']) {
          await _expectRejectedDraft(form, part.id, value);
        }
      });
    }
  });

  group('adjustment draft lifecycle', () {
    for (final offset in [3661.123456789123, -3661.123456789123]) {
      _formTest('untouched stored offset $offset opens and submits exactly',
          (form) async {
        final input = _storedInput(
          ayanamsa: AstrologyAyanamsa.trueChitra,
          offset: offset,
        );
        await form.pump(input: input);
        expect(_byId(_degrees), findsOneWidget);
        expect(_byId('astrology-latitude'), findsNothing);
        expect(form.controller(_degrees).text, '1');
        expect(form.controller(_minutes).text, '1');
        expect(
          double.parse(form.controller(_seconds).text),
          closeTo(1.123456789123, 1e-10),
        );
        expect(form.choice<bool>(_direction).value, offset < 0);
        final displayed = [for (final id in _dms) form.controller(id).text];
        expect(form.generated, isEmpty);
        expect(form.saved, isEmpty);

        await form.tap(_generate);
        await form.tap(_save);
        // Exact equality, deliberately not closeTo: display precision must
        // never round an untouched stored value on a no-op submission.
        expect(form.generated.single.ayanamsaOffsetArcseconds, offset);
        expect(form.saved.single.ayanamsaOffsetArcseconds, offset);
        _expectInput(form.generated.single, input);
        _expectInput(form.saved.single, input);
        form.expectDms(displayed);
      });
    }

    _formTest(
        'hiding the panel retains and submits the dirty signed adjustment',
        (form) async {
      await form.pump(
        input: _storedInput(
          ayanamsa: AstrologyAyanamsa.krishnamurti,
          offset: -3723.5,
        ),
      );
      await form.enterDms('3', '04', '05.2500');
      await form.tap(_adjust);
      expect(_byId(_degrees), findsNothing);
      expect(_byId(_direction), findsNothing);
      expect(_byId(_reset), findsNothing);
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);
      final expected = form.input.copyWith(
        ayanamsaOffsetArcseconds: -11045.25,
      );
      await form.tap(_generate);
      _expectInput(form.generated.single, expected);

      await form.tap(_adjust);
      form.expectDms(['3', '04', '05.2500']);
      expect(form.choice<bool>(_direction).value, isTrue);
      await form.tap(_adjust);
      await form.tap(_save);
      _expectInput(form.saved.single, expected);
      expect(_byId(_degrees), findsNothing);
    });

    _formTest(
        'reset clears an invalid draft to zero without changing its preset',
        (form) async {
      await form.pump(
        input: _storedInput(
          ayanamsa: AstrologyAyanamsa.krishnamurti,
          offset: -3723.5,
        ),
      );
      await form.enter(_seconds, 'NaN');
      await form.tap(_save);
      expect(form.saved, isEmpty);
      expect(_byId('astrology-error'), findsOneWidget);
      await form.tap(_reset);

      form.expectDms(['0', '0', '0']);
      expect(form.choice<bool>(_direction).value, isFalse);
      expect(
        form.choice<AstrologyAyanamsa>(_preset).value,
        AstrologyAyanamsa.krishnamurti,
      );
      expect(_byId('astrology-error'), findsNothing);
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);
      expect(form.input.ayanamsaOffsetArcseconds, -3723.5);
      final expected = form.input.copyWith(ayanamsaOffsetArcseconds: 0);
      await form.tap(_generate);
      await form.tap(_save);
      _expectInput(form.generated.single, expected);
      _expectInput(form.saved.single, expected);
    });

    _formTest('equivalent parent echoes retain dirty DMS, selection and focus',
        (form) async {
      final input = _storedInput();
      await form.pump(input: input);
      await form.tap(_adjust);
      await form.changeChoice(_preset, AstrologyAyanamsa.yukteshwar);
      await form.changeChoice(_direction, true);
      await form.enterDms('07', '1.', '4.');
      form.tester.testTextInput.updateEditingValue(
        const TextEditingValue(
          text: '4.',
          selection: TextSelection.collapsed(offset: 1),
          composing: TextRange(start: 0, end: 2),
        ),
      );
      await form.tester.pump();
      final controllers = [for (final id in _dms) form.controller(id)];
      final values = [for (final controller in controllers) controller.value];
      final focus = form.editable(_seconds).focusNode;

      for (var echo = 0; echo < 3; echo++) {
        await form.pump(input: AstrologyInput.fromJson(input.toJson()));
        for (var index = 0; index < _dms.length; index++) {
          expect(form.controller(_dms[index]), same(controllers[index]));
          expect(controllers[index].value, values[index]);
        }
        expect(form.editable(_seconds).focusNode, same(focus));
        expect(focus.hasPrimaryFocus, isTrue);
        expect(form.choice<bool>(_direction).value, isTrue);
        expect(
          form.choice<AstrologyAyanamsa>(_preset).value,
          AstrologyAyanamsa.yukteshwar,
        );
        expect(form.generated, isEmpty);
        expect(form.saved, isEmpty);
      }

      await form.enter(_minutes, '2');
      await form.enter(_seconds, '4.25');
      await form.tap(_generate);
      _expectInput(
        form.generated.single,
        input.copyWith(
          ayanamsa: AstrologyAyanamsa.yukteshwar,
          ayanamsaOffsetArcseconds: -25324.25,
        ),
      );
    });

    _formTest(
        'changed settings replace a dirty draft and zero closes the panel',
        (form) async {
      final input = _storedInput(offset: 3723.5);
      await form.pump(input: input);
      await form.enterDms('9', '8', 'unfinished');
      await form.changeChoice(_preset, AstrologyAyanamsa.raman);
      final replacement = input.copyWith(
        ayanamsa: AstrologyAyanamsa.pushyaPaksha,
        ayanamsaOffsetArcseconds: -7323.5,
      );
      // Only the ayanamsha settings differ: they must be fingerprinted too.
      await form.pump(input: replacement);
      form.expectDms(['2', '2', '3.5']);
      expect(form.choice<bool>(_direction).value, isTrue);
      expect(
        form.choice<AstrologyAyanamsa>(_preset).value,
        AstrologyAyanamsa.pushyaPaksha,
      );
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);
      await form.tap(_save);
      _expectInput(form.saved.single, replacement);

      final zero = replacement.copyWith(ayanamsaOffsetArcseconds: 0);
      await form.pump(input: zero);
      expect(_byId(_degrees), findsNothing);
      expect(_byId('astrology-success'), findsNothing);
      await form.tap(_adjust);
      form.expectDms(['0', '0', '0']);
      expect(form.choice<bool>(_direction).value, isFalse);
      await form.tap(_generate);
      _expectInput(form.generated.single, zero);
    });
  });

  group('disabled and stale-callback safety', () {
    for (final menu in [
      (id: _preset, option: 'B.V. Raman'),
      (id: _direction, option: 'Add (+)'),
    ]) {
      _formTest('${menu.id} open route cannot apply to a replacement record',
          (form) async {
        await form.pump(input: _storedInput(offset: 3723.5));
        final state = form.tester.state(find.byType(AstrologyBirthForm));
        await form.tap(menu.id);
        await form.tester.pumpAndSettle();
        expect(find.text(menu.option).hitTestable(), findsOneWidget);
        final replacement = form.input.copyWith(
          name: 'Replacement while choosing',
          ayanamsa: AstrologyAyanamsa.suryaSiddhanta,
          ayanamsaOffsetArcseconds: -7323.5,
        );
        await form.pump(input: replacement);
        await form.tester.pumpAndSettle();
        expect(form.tester.state(find.byType(AstrologyBirthForm)), same(state));
        final staleOption = find.text(menu.option).hitTestable();
        if (staleOption.evaluate().isNotEmpty) {
          await form.tester.tap(staleOption);
          await form.tester.pumpAndSettle();
        }
        expect(
          form.choice<AstrologyAyanamsa>(_preset).value,
          AstrologyAyanamsa.suryaSiddhanta,
        );
        expect(form.choice<bool>(_direction).value, isTrue);
        form.expectDms(['2', '2', '3.5']);
        await form.tap(_save);
        _expectInput(form.saved.single, replacement);
      });
    }

    _formTest('a disabled preview disables every control and performs no IO',
        (form) async {
      await form.pump(
        input: const AstrologyInput(
          name: 'Preview',
          ayanamsa: AstrologyAyanamsa.raman,
          ayanamsaOffsetArcseconds: -3723.5,
        ),
        enabled: false,
        autoLocate: true,
      );
      _expectDisabled(form);
      for (final id in _dms) {
        final focus = form.editable(id).focusNode;
        focus.requestFocus();
        await form.tester.pump();
        expect(focus.hasPrimaryFocus, isFalse);
      }
      form.expectDms(['1', '2', '3.5']);
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);
    });

    _formTest('callbacks retained before disabling cannot edit or submit',
        (form) async {
      await form.pump(input: _storedInput(offset: -3723.5));
      await form.enter(_seconds, 'NaN');
      await form.tap(_generate);
      final error = form.message('astrology-error');
      final stale = _captureDraftCallbacks(form);
      final generate = form.button(_generate).onPressed!;
      final save = form.button(_save).onPressed!;
      await form.pump(enabled: false);
      _expectDisabled(form);

      stale.edit();
      generate();
      save();
      await form.tester.pump();
      form.expectDms(['1', '2', 'NaN']);
      expect(form.choice<bool>(_direction).value, isTrue);
      expect(
        form.choice<AstrologyAyanamsa>(_preset).value,
        AstrologyAyanamsa.lahiri,
      );
      expect(form.message('astrology-error'), error);
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);

      stale.toggle();
      await form.tester.pump();
      expect(
        _byId(_degrees),
        findsOneWidget,
        reason: 'An old enabled toggle must not close a disabled draft.',
      );
    });

    _formTest(
        'pending submission freezes controls and rejects retained callbacks',
        (form) async {
      final completion = Completer<void>();
      final input = _storedInput(offset: -3723.5);
      final expected = input.copyWith(ayanamsaOffsetArcseconds: -11045.25);
      try {
        await form.pump(input: input, pending: completion.future);
        await form.enterDms('3', '4', '5.25');
        final stale = _captureDraftCallbacks(form);
        final generate = form.button(_generate).onPressed!;
        final save = form.button(_save).onPressed!;
        await form.tap(_generate);
        _expectDisabled(form);
        _expectInput(form.generated.single, expected);
        expect(_byId('astrology-success'), findsNothing);

        stale.edit();
        generate();
        save();
        await form.tester.pump();
        form.expectDms(['3', '4', '5.25']);
        expect(form.choice<bool>(_direction).value, isTrue);
        expect(
          form.choice<AstrologyAyanamsa>(_preset).value,
          input.ayanamsa,
        );
        expect(form.generated, hasLength(1));
        expect(form.saved, isEmpty);
        stale.toggle();
        await form.tester.pump();
        expect(
          _byId(_degrees),
          findsOneWidget,
          reason: 'An old toggle must not change the in-flight form.',
        );
      } finally {
        completion.complete();
        await form.tester.pump();
        await form.tester.pump();
      }
      expect(form.button(_save).onPressed, isNotNull);
      await form.tap(_save);
      _expectInput(form.saved.single, expected);
      expect(form.generated, hasLength(1));
    });

    _formTest(
        'previous-record dropdown callbacks cannot overwrite new settings',
        (form) async {
      await form.pump(input: _storedInput(offset: 3723.5));
      final oldPreset = form.choice<AstrologyAyanamsa>(_preset).onChanged!;
      final oldDirection = form.choice<bool>(_direction).onChanged!;
      final replacement = form.input.copyWith(
        ayanamsa: AstrologyAyanamsa.suryaSiddhanta,
        ayanamsaOffsetArcseconds: -7323.5,
      );
      await form.pump(input: replacement);

      oldPreset(AstrologyAyanamsa.raman);
      oldDirection(false);
      await form.tester.pump();
      expect(
        form.choice<AstrologyAyanamsa>(_preset).value,
        replacement.ayanamsa,
      );
      expect(form.choice<bool>(_direction).value, isTrue);
      form.expectDms(['2', '2', '3.5']);
      expect(form.generated, isEmpty);
      expect(form.saved, isEmpty);
      await form.tap(_save);
      _expectInput(form.saved.single, replacement);
    });
  });

  group('themed responsive adjustment surfaces', () {
    for (final appearance in const [
      (name: 'light', brightness: Brightness.light, paper: false),
      (name: 'dark', brightness: Brightness.dark, paper: false),
      (name: 'paper', brightness: Brightness.light, paper: true),
    ]) {
      _formTest('${appearance.name} stays coherent at 760/280px and 2x text',
          (form) async {
        final theme = _desktopTheme(
          brightness: appearance.brightness,
          paper: appearance.paper,
        );
        for (final layout in const [
          (width: 760.0, scale: 1.0),
          (width: 280.0, scale: 1.0),
          (width: 280.0, scale: 2.0),
        ]) {
          final input = _storedInput(offset: 3723.5).copyWith(
            name: '${appearance.name} ${layout.width} ${layout.scale}',
          );
          await form.pump(
            input: input,
            theme: theme,
            width: layout.width,
            textScale: layout.scale,
          );
          final context = form.tester.element(_byId(_preset));
          expect(Theme.of(context).brightness, appearance.brightness);
          expect(PaperTheme.isEnabled(context), appearance.paper);
          expect(MediaQuery.textScalerOf(context).scale(10), layout.scale * 10);
          final ink = _expectColors(form, paper: appearance.paper);
          expect(form.tester.takeException(), isNull);

          // Open real routes too: the menu must inherit the scaled text and
          // themed ink, not merely look correct while the selector is closed.
          await form.pickMenu(_preset, 'B.V. Raman', ink: ink);
          await form.pickMenu(_direction, 'Subtract (−)', ink: ink);
          expect(
            form.choice<AstrologyAyanamsa>(_preset).value,
            AstrologyAyanamsa.raman,
          );
          expect(form.choice<bool>(_direction).value, isTrue);
          await form.enterDms('1', '2', '4.25');
          final generatedBefore = form.generated.length;
          await form.tap(_generate);
          expect(form.generated, hasLength(generatedBefore + 1));
          _expectInput(
            form.generated.last,
            input.copyWith(
              ayanamsa: AstrologyAyanamsa.raman,
              ayanamsaOffsetArcseconds: -3724.25,
            ),
          );
          _expectColors(form, paper: appearance.paper);
          expect(
            form.tester.takeException(),
            isNull,
            reason: '${layout.width}px at ${layout.scale}x must not overflow.',
          );
        }
        expect(form.saved, isEmpty);
      });
    }
  });
}

Finder _byId(String id) => find.byKey(ValueKey(id));

Finder _editableFinder(String id) => find.descendant(
      of: _byId(id),
      matching: find.byType(EditableText),
    );

AstrologyInput _storedInput({
  int utcHour = 6,
  AstrologyAyanamsa ayanamsa = AstrologyAyanamsa.lahiri,
  double offset = 0,
}) =>
    AstrologyInput(
      name: 'Stored horoscope',
      utc: DateTime.utc(2024, 11, 3, utcHour, 30, 45, 123, 456),
      place: _newYork,
      ayanamsa: ayanamsa,
      ayanamsaOffsetArcseconds: offset,
      trueNode: true,
      dashaYearDays: 360,
      style: IndianChartStyle.south,
    );

void _expectInput(AstrologyInput actual, AstrologyInput expected) {
  expect(actual.toJson(), expected.toJson());
  expect(actual.utc, expected.utc);
  expect(actual.utc!.isUtc, isTrue);
  expect(
      actual.utc!.microsecondsSinceEpoch, expected.utc!.microsecondsSinceEpoch);
  expect(actual.place, same(expected.place));
  expect(actual.ayanamsaOffsetArcseconds, expected.ayanamsaOffsetArcseconds);
}

/// Every case unmounts before returning, including assertion failures and open
/// dropdown routes. The widget owns its controllers and focus nodes.
void _formTest(
  String description,
  Future<void> Function(_FormHarness) body,
) {
  testWidgets(
    description,
    (tester) async {
      final form = _FormHarness(tester);
      try {
        await body(form);
        expect(tester.takeException(), isNull);
      } finally {
        FocusManager.instance.primaryFocus?.unfocus();
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        expect(form.service.calls, isEmpty,
            reason: 'These tests require no IO.');
        expect(tester.takeException(), isNull);
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<void> _pumpValidationDraft(_FormHarness form) async {
  await form.pump(
    input: _storedInput(
      ayanamsa: AstrologyAyanamsa.yukteshwar,
      offset: -3723.5,
    ),
  );
}

Future<void> _expectRejectedDraft(
  _FormHarness form,
  String id,
  String value,
) async {
  await form.enter(id, value);
  final draft = [for (final field in _dms) form.controller(field).text];
  for (final button in [_generate, _save]) {
    await form.tap(button);
    expect(form.generated, isEmpty);
    expect(form.saved, isEmpty);
    expect(form.message('astrology-error'), contains('Ayanamsha adjustment'));
    expect(_byId('astrology-success'), findsNothing);
    form.expectDms(draft);
    expect(form.controller(id).text, value);
    expect(form.choice<bool>(_direction).value, isTrue);
    expect(
      form.choice<AstrologyAyanamsa>(_preset).value,
      AstrologyAyanamsa.yukteshwar,
    );
    expect(form.controller('astrology-name').text, form.input.name);
    expect(form.controller('astrology-place').text, _newYork.name);
    expect(form.button(button).onPressed, isNotNull);
    expect(form.tester.takeException(), isNull);
  }
}

void _expectDisabled(_FormHarness form) {
  expect(form.choice<AstrologyAyanamsa>(_preset).onChanged, isNull);
  expect(form.choice<bool>(_direction).onChanged, isNull);
  for (final field
      in form.tester.widgetList<TextField>(find.byType(TextField))) {
    expect(field.enabled, isFalse, reason: '${field.key} must be disabled.');
  }
  for (final id in _dms) {
    expect(form.editable(id).focusNode.canRequestFocus, isFalse);
  }
  for (final id in [
    _adjust,
    _reset,
    _generate,
    _save,
    'astrology-advanced',
    'astrology-search',
    'astrology-current-location',
  ]) {
    expect(form.button(id).onPressed, isNull, reason: '$id must be disabled.');
  }
  expect(form.tester.widget<Switch>(_byId('astrology-now')).onChanged, isNull);
}

({VoidCallback edit, VoidCallback toggle}) _captureDraftCallbacks(
  _FormHarness form,
) {
  final preset = form.choice<AstrologyAyanamsa>(_preset);
  final direction = form.choice<bool>(_direction);
  final fields = [for (final id in _dms) form.field(id)];
  final reset = form.button(_reset).onPressed!;
  return (
    edit: () {
      // Invoke captured widgets, not freshly looked-up disabled controls.
      preset.onChanged!(AstrologyAyanamsa.trueChitra);
      direction.onChanged!(!direction.value!);
      for (final field in fields) {
        field.onChanged!('99');
      }
      reset();
    },
    toggle: form.button(_adjust).onPressed!,
  );
}

Color _expectColors(_FormHarness form, {required bool paper}) {
  final tester = form.tester;
  final palette = PremiumThemeExtension.of(tester.element(_byId(_preset)));
  final surface = paper ? PaperTheme.editorPreviewBackground : palette.surface;
  final fieldColor =
      paper ? PaperTheme.codeBlockBackground : palette.mutedSurface;
  final ink = paper ? PaperTheme.textPrimary : palette.textPrimary;
  final muted = paper ? PaperTheme.textSecondary : palette.textSecondary;
  final accent = paper ? PaperTheme.accent : palette.accent;
  final hover = paper ? PaperTheme.hoverOverlay : palette.hoverOverlay;
  expect(
    tester.widget<Material>(_byId('astrology-birth-surface')).color,
    surface,
  );
  for (final id in _dms) {
    final field = form.field(id);
    expect(field.decoration!.filled, isTrue);
    expect(field.decoration!.fillColor, fieldColor);
    expect(field.decoration!.hoverColor, hover);
    expect(field.decoration!.hintStyle!.color, muted);
    expect(field.decoration!.focusedBorder!.borderSide.color, accent);
    expect(field.style!.color, ink);
    expect(field.cursorColor, accent);
    expect(
      field.decoration!.fillColor,
      form.field('astrology-name').decoration!.fillColor,
    );
  }
  for (final dropdown in [
    form.choice<AstrologyAyanamsa>(_preset),
    form.choice<bool>(_direction),
  ]) {
    expect(dropdown.dropdownColor, surface);
    expect(dropdown.style!.color, ink);
    expect(dropdown.iconEnabledColor, muted);
    final decorator = tester.widget<InputDecorator>(
      find.ancestor(
        of: find.byKey(dropdown.key!),
        matching: find.byType(InputDecorator),
      ),
    );
    expect(decorator.decoration.fillColor, fieldColor);
    expect(decorator.decoration.hoverColor, hover);
    expect(decorator.decoration.focusedBorder!.borderSide.color, accent);
  }
  final generateStyle = form.button(_generate).style!;
  for (final id in [_adjust, _reset]) {
    final style = form.button(id).style!;
    expect(style.foregroundColor!.resolve({}), accent);
    expect(style.backgroundColor!.resolve({}), accent.withValues(alpha: 0.10));
    expect(
      style.overlayColor!.resolve({WidgetState.hovered}),
      generateStyle.overlayColor!.resolve({WidgetState.hovered}),
    );
    expect(style.backgroundColor!.resolve({WidgetState.disabled}), fieldColor);
    expect(style.foregroundColor!.resolve({WidgetState.disabled}), muted);
  }
  return ink;
}

Widget _claimBackspace(Widget child, {required VoidCallback onIntercept}) =>
    Focus(
      skipTraversal: true,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.backspace) {
          onIntercept();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Actions(
        actions: {
          DeleteCharacterIntent: CallbackAction<DeleteCharacterIntent>(
            onInvoke: (_) {
              onIntercept();
              return null;
            },
          ),
        },
        child: child,
      ),
    );

ThemeData _desktopTheme({
  Brightness brightness = Brightness.light,
  bool paper = false,
}) =>
    DesktopAppearance().getThemeData(
      paper
          ? AppTheme.builtins.firstWhere(
              (theme) => theme.themeName == BuiltInTheme.paper,
            )
          : AppTheme.fallback,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

class _FormHarness {
  _FormHarness(this.tester);

  final WidgetTester tester;
  final service = _NoIoLocationService();
  final generated = <AstrologyInput>[];
  final saved = <AstrologyInput>[];
  AstrologyInput input = _storedInput();

  Future<void> pump({
    AstrologyInput? input,
    bool enabled = true,
    bool autoLocate = false,
    double width = 760,
    double textScale = 1,
    ThemeData? theme,
    Widget Function(Widget)? wrap,
    Future<void>? pending,
  }) async {
    this.input = input ?? this.input;
    final form = AstrologyBirthForm(
      input: this.input,
      locationService: service,
      autoLocate: autoLocate,
      enabled: enabled,
      onGenerate: (value) async {
        generated.add(value);
        if (pending != null) await pending;
      },
      onSave: (value) async {
        saved.add(value);
        if (pending != null) await pending;
      },
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? _desktopTheme(),
        themeAnimationDuration: Duration.zero,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: width,
              height: 520,
              child: wrap == null ? form : wrap(form),
            ),
          ),
        ),
      ),
    );
    // Do not settle an unresolved submission's progress indicator.
    await tester.pump();
  }

  TextField field(String id) => tester.widget<TextField>(_byId(id));

  TextEditingController controller(String id) => field(id).controller!;

  EditableText editable(String id) =>
      tester.widget<EditableText>(_editableFinder(id));

  TextButton button(String id) => tester.widget<TextButton>(_byId(id));

  DropdownButton<T> choice<T>(String id) =>
      tester.widget<DropdownButton<T>>(_byId(id));

  String message(String id) => tester.widget<Text>(_byId(id)).data!;

  Future<void> reveal(String id) async {
    await tester.ensureVisible(_byId(id));
    await tester.pump();
    expect(_byId(id).hitTestable(), findsOneWidget);
  }

  Future<void> tap(String id) async {
    await reveal(id);
    await tester.tap(_byId(id), kind: PointerDeviceKind.mouse);
    await tester.pump();
    await tester.pump();
  }

  Future<void> enter(String id, String value) async {
    await reveal(id);
    await tester.enterText(_byId(id), value);
    await tester.pump();
  }

  Future<void> enterDms(String degrees, String minutes, String seconds) async {
    await enter(_degrees, degrees);
    await enter(_minutes, minutes);
    await enter(_seconds, seconds);
  }

  void expectDms(List<String> values) {
    expect(
      [for (final id in _dms) controller(id).text],
      values,
    );
  }

  Future<void> changeChoice<T>(String id, T value) async {
    choice<T>(id).onChanged!(value);
    await tester.pump();
  }

  Future<void> pickMenu(String id, String label, {required Color ink}) async {
    final scale = MediaQuery.textScalerOf(tester.element(_byId(id))).scale(10);
    await tap(id);
    await tester.pumpAndSettle();
    final option = find.text(label).hitTestable();
    expect(option, findsOneWidget);
    final context = tester.element(option);
    expect(DefaultTextStyle.of(context).style.color, ink);
    expect(MediaQuery.textScalerOf(context).scale(10), scale);
    expect(tester.takeException(), isNull);
    await tester.tap(option, kind: PointerDeviceKind.mouse);
    await tester.pumpAndSettle();
  }
}

/// Supplying a place and disabling autolocation should avoid both seams.
/// Overrides and the injected geocoder independently prevent real IO even if
/// that contract regresses; the harness also asserts that no call was made.
class _NoIoLocationService extends AstrologyLocationService {
  _NoIoLocationService() : super(geocoder: const _NoIoGeocoder());

  final calls = <String>[];

  @override
  Future<AstrologyPlace> current({bool force = false}) async {
    calls.add('current');
    throw StateError('Unexpected location request in an ayanamsha form test.');
  }

  @override
  Future<List<AstrologyPlace>> search(String query) async {
    calls.add('search');
    throw StateError('Unexpected place search in an ayanamsha form test.');
  }
}

class _NoIoGeocoder implements MapGeocoder {
  const _NoIoGeocoder();

  @override
  Future<GeocodeResult?> lookUp(MapLocation location) =>
      throw StateError('Unexpected geocoder access in an ayanamsha form test.');

  @override
  Future<List<GeocodeResult>> search(String query, {int limit = 6}) =>
      throw StateError('Unexpected geocoder access in an ayanamsha form test.');
}
