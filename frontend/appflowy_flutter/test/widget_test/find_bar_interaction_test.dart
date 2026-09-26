import 'dart:ui' as ui;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _firstBar = ValueKey('first-find-bar');
const _secondBar = ValueKey('second-find-bar');
const _query = ValueKey('findTextField');
const _replacement = ValueKey('replaceTextField');
const _previous = ValueKey('findPreviousMatch');
const _next = ValueKey('findNextMatch');
const _close = ValueKey('findClose');
const _toggleReplace = ValueKey('findToggleReplace');
const _replaceOne = ValueKey('findReplaceOne');
const _replaceAll = ValueKey('findReplaceAll');
const _outside = ValueKey('outside-native-field');
const _dialogField = ValueKey('dialog-native-field');
const _modes = ['light', 'dark', 'paper'];
const _optionKeys = [
  LocaleKeys.findAndReplace_caseSensitive,
  LocaleKeys.findAndReplace_wholeWord,
  LocaleKeys.findAndReplace_useRegex,
];
late Map<String, dynamic> _translations;

// Only the host's result counts and callback bookkeeping are controlled. The
// bar, fields, tap regions, routes, shortcuts, semantics and desktop themes are
// production widgets. Intentionally UNRUN in the restricted authoring session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      const Locale('en', 'US'),
    );
  });

  test('outside dismissal defaults to enabled with an optional callback', () {
    final controller = TextEditingController();
    final focus = FocusNode();
    try {
      final bar = FindReplaceBar(
        findController: controller,
        findFocusNode: focus,
        options: const FindOptions(),
        onOptionsChanged: (_) {},
        matchCount: 0,
        currentMatch: 0,
        onPrevious: null,
        onNext: null,
        onClose: () {},
      );
      expect(bar.dismissOnTapOutside, isTrue);
      expect(bar.onTapOutside, isNull);
    } finally {
      controller.dispose();
      focus.dispose();
    }
  });

  for (final customOutside in [true, false]) {
    _test(
      'one outside mouse click dismisses once and types in the sibling '
      '(custom callback: $customOutside)',
      (tester, host) async {
        final bar = host.first;
        final draft = bar.queryController.value;
        final replacement = bar.replaceController.value;
        expect(bar.queryFocus.hasPrimaryFocus, isTrue);

        await _click(tester, find.byKey(_outside));
        expect(host.outsidePointerDowns, 1);
        expect(host.outsideTaps, 1);
        expect(bar.outsideCalls, customOutside ? 1 : 0);
        expect(bar.closeCalls, customOutside ? 0 : 1);
        expect(find.byType(FindReplaceBar), findsNothing);
        expect(bar.disposed, isTrue);
        expect(bar.queryFocus.parent, isNull);
        expect(bar.replaceFocus.parent, isNull);
        expect(bar.queryAtDisposal, draft);
        expect(bar.replaceAtDisposal, replacement);
        expect(host.outsideController.text, 'Page title draft');

        // No tester.enterText/showKeyboard/requestFocus here: those would
        // repair a failed first click and conceal the lost-typing regression.
        await _typeInFocusedField(
          tester,
          host.outsideFocus,
          host.outsideController,
          'Page title draft continued',
        );
        await tester.pump(const Duration(milliseconds: 500));
        expect(host.outsideFocus.hasPrimaryFocus, isTrue);
        expect(bar.outsideCalls + bar.closeCalls, 1);
        expect(host.outsideTaps, 1);
      },
      configuration: _BarConfiguration(customOutside: customOutside),
    );
  }

  _test('query, replace, options, counts and navigation stay inside the bar',
      (tester, host) async {
    final bar = host.first;
    await _click(tester, _within(_query));
    await _typeInFocusedField(
      tester,
      bar.queryFocus,
      bar.queryController,
      'query draft',
    );
    await _click(tester, _within(_replacement));
    await _typeInFocusedField(
      tester,
      bar.replaceFocus,
      bar.replaceController,
      'replacement draft',
    );
    final querySnapshot = _FieldSnapshot(tester, _within(_query));
    final replacementSnapshot = _FieldSnapshot(tester, _within(_replacement));

    for (var index = 0; index < _optionKeys.length; index++) {
      await _click(tester, _option(_optionKeys[index]));
      expect(bar.optionChanges, hasLength(index + 1));
      expect(_optionValues(bar.options)[index], isTrue);
      expect(bar.replaceFocus.hasPrimaryFocus, isTrue);
      querySnapshot.expectUnchanged(tester);
      replacementSnapshot.expectUnchanged(tester);
      expect(bar.outsideCalls + bar.closeCalls, 0);
    }
    expect(
      bar.options,
      const FindOptions(caseSensitive: true, wholeWord: true, useRegex: true),
    );

    await _click(tester, find.text(_matchLabel(1, 3)));
    for (final key in [_next, _previous, _replaceOne, _replaceAll]) {
      await _click(tester, _within(key));
      expect(bar.replaceFocus.hasPrimaryFocus, isTrue);
      querySnapshot.expectUnchanged(tester);
      replacementSnapshot.expectUnchanged(tester);
      expect(bar.outsideCalls + bar.closeCalls, 0);
    }
    expect(bar.nextCalls, 1);
    expect(bar.previousCalls, 1);
    expect(bar.replaceCalls, 1);
    expect(bar.replaceAllCalls, 1);
    expect(find.text(_matchLabel(1, 3)), findsOneWidget);

    await _click(tester, _within(_query));
    final beforeCollapse = _FieldSnapshot(tester, _within(_query));
    await _click(tester, _within(_toggleReplace));
    expect(_within(_replacement), findsNothing);
    expect(bar.queryFocus.hasPrimaryFocus, isTrue);
    beforeCollapse.expectUnchanged(tester);
    await _click(tester, _within(_toggleReplace));
    expect(_within(_replacement), findsOneWidget);
    expect(bar.replaceController.text, 'replacement draft');
    expect(bar.queryFocus.hasPrimaryFocus, isTrue);
    beforeCollapse.expectUnchanged(tester);
    expect(bar.outsideCalls + bar.closeCalls, 0);
  });

  for (final field in [_query, _replacement]) {
    _test(
        'Escape from ${field.value} closes once, not through outside dismissal',
        (tester, host) async {
      final bar = host.first;
      await _click(tester, _within(field));
      expect(
        (field == _query ? bar.queryFocus : bar.replaceFocus).hasPrimaryFocus,
        isTrue,
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();
      expect(bar.closeCalls, 1);
      expect(bar.outsideCalls, 0);
      expect(bar.disposed, isTrue);
      expect(find.byType(FindReplaceBar), findsNothing);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      expect(bar.closeCalls, 1);
    });
  }

  for (final submitMode in [_SubmitMode.next, _SubmitMode.callback]) {
    _test(
      'repeated Enter keeps native focus and dispatches ${submitMode.name}',
      (tester, host) async {
        final bar = host.first;
        final draft = bar.queryController.value;
        for (var count = 1; count <= 3; count++) {
          // Enter reaches a single-line TextField as its configured IME action.
          // Sending only a raw key event does not simulate that engine message.
          await tester.testTextInput.receiveAction(TextInputAction.search);
          expect(
            bar.queryFocus.hasPrimaryFocus,
            isTrue,
            reason: 'Focus must survive before any post-frame callback.',
          );
          await tester.pump();
          expect(bar.queryFocus.hasPrimaryFocus, isTrue);
          expect(tester.testTextInput.hasAnyClients, isTrue);
          expect(bar.nextCalls, submitMode == _SubmitMode.next ? count : 0);
          expect(
            bar.submitCalls,
            submitMode == _SubmitMode.callback ? count : 0,
          );
          expect(bar.queryController.value, draft);
        }
        await _click(tester, _within(_replacement));
        for (var count = 1; count <= 2; count++) {
          await tester.testTextInput.receiveAction(TextInputAction.search);
          expect(bar.replaceFocus.hasPrimaryFocus, isTrue);
          await tester.pump();
          expect(bar.replaceCalls, count);
          expect(bar.replaceFocus.hasPrimaryFocus, isTrue);
          expect(bar.queryController.value, draft);
        }
        await _typeInFocusedField(
          tester,
          bar.replaceFocus,
          bar.replaceController,
          'continued replacement',
        );
        expect(bar.outsideCalls + bar.closeCalls, 0);
      },
      configuration: _BarConfiguration(submitMode: submitMode),
    );
  }

  _test(
      'Enter then an outside click before the next frame cannot reclaim focus',
      (tester, host) async {
    final bar = host.first;
    await tester.testTextInput.receiveAction(TextInputAction.search);
    // Deliberately no pump between submission and the new native click.
    await _click(tester, find.byKey(_outside));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(bar.nextCalls, 1);
    expect(bar.outsideCalls, 1);
    expect(bar.closeCalls, 0);
    expect(bar.disposed, isTrue);
    expect(bar.queryFocus.parent, isNull);
    expect(host.outsideTaps, 1);
    await _typeInFocusedField(
      tester,
      host.outsideFocus,
      host.outsideController,
      'typed after Enter and dismissal',
    );
  });

  _test(
    'submission may unmount and dispose the owner without a late focus request',
    (tester, host) async {
      final bar = host.first;
      await tester.testTextInput.receiveAction(TextInputAction.search);
      // Model a host-directed focus handoff, independently of outside clicks.
      host.outsideFocus.requestFocus();
      await tester.pump();
      await tester.pump();
      expect(bar.disposed, isTrue);
      expect(bar.submitCalls, 1);
      expect(bar.nextCalls, 0);
      expect(bar.closeCalls + bar.outsideCalls, 0);
      expect(bar.queryFocus.parent, isNull);
      expect(find.byType(FindReplaceBar), findsNothing);
      await _typeInFocusedField(
        tester,
        host.outsideFocus,
        host.outsideController,
        'successor input',
      );
    },
    configuration: const _BarConfiguration(submitMode: _SubmitMode.unmount),
  );

  for (final clickedBar in [_firstBar, _secondBar]) {
    _test(
      'two equal queries have independent tap groups: click ${clickedBar.value}',
      (tester, host) async {
        final first = host.first;
        final second = host.second;
        expect(first.queryController.text, second.queryController.text);
        expect(first.queryController, isNot(same(second.queryController)));
        for (final entry in [(_firstBar, first), (_secondBar, second)]) {
          final region = tester.widget<TapRegion>(
            find.descendant(
              of: find.byKey(entry.$1),
              matching: find.byWidgetPredicate(
                (widget) =>
                    widget is TapRegion &&
                    identical(widget.groupId, entry.$2.queryController),
              ),
            ),
          );
          expect(region.consumeOutsideTaps, isFalse);
        }
        final clicked = clickedBar == _firstBar ? first : second;
        final other = clickedBar == _firstBar ? second : first;
        final field = _within(_query, bar: clickedBar);
        final fieldState = tester.state<State<TextField>>(field);

        await _click(tester, field);
        expect(other.outsideCalls, 1);
        expect(other.closeCalls, 0);
        expect(other.disposed, isTrue);
        expect(clicked.outsideCalls + clicked.closeCalls, 0);
        expect(clicked.disposed, isFalse);
        expect(find.byType(FindReplaceBar), findsOneWidget);
        expect(tester.state<State<TextField>>(field), same(fieldState));
        await _typeInFocusedField(
          tester,
          clicked.queryFocus,
          clicked.queryController,
          'independent query',
        );
        await _click(tester, find.byKey(_outside));
        expect(clicked.outsideCalls, 1);
        expect(other.outsideCalls, 1);
        expect(find.byType(FindReplaceBar), findsNothing);
        await _typeInFocusedField(
          tester,
          host.outsideFocus,
          host.outsideController,
          'outside both bars',
        );
      },
      twoBars: true,
    );
  }

  _test(
    'a covering modal protects both bars and dismissal resumes after pop',
    (tester, host) async {
      final first = host.first;
      final second = host.second;
      final firstFieldState = tester.state<State<TextField>>(_within(_query));
      final route = ModalRoute.of(tester.element(find.byKey(_firstBar)))!;
      final closed = showDialog<void>(
        context: tester.element(find.byKey(_firstBar)),
        barrierDismissible: false,
        builder: (_) => Dialog(
          child: SizedBox(
            width: 280,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: TextField(
                key: _dialogField,
                controller: host.dialogController,
                focusNode: host.dialogFocus,
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(route.isCurrent, isFalse);
      final dialogPoint = tester.getCenter(find.byKey(_dialogField));
      for (final key in [_firstBar, _secondBar]) {
        expect(tester.getRect(find.byKey(key)).contains(dialogPoint), isFalse);
      }
      await _click(tester, find.byKey(_dialogField));
      await _typeInFocusedField(
        tester,
        host.dialogFocus,
        host.dialogController,
        'modal draft',
      );
      await tester.tapAt(
        const Offset(880, 780),
        kind: ui.PointerDeviceKind.mouse,
      );
      await tester.pump();
      expect(find.byType(Dialog), findsOneWidget);
      expect(first.outsideCalls + first.closeCalls, 0);
      expect(second.outsideCalls + second.closeCalls, 0);
      expect(first.disposed, isFalse);
      expect(second.disposed, isFalse);
      expect(
        tester.state<State<TextField>>(_within(_query)),
        same(firstFieldState),
      );

      host.navigator.currentState!.pop();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await closed;
      expect(route.isCurrent, isTrue);
      await _click(tester, find.byKey(_outside));
      expect(first.outsideCalls, 1);
      expect(second.outsideCalls, 1);
      expect(first.closeCalls + second.closeCalls, 0);
      expect(find.byType(FindReplaceBar), findsNothing);
      await _typeInFocusedField(
        tester,
        host.outsideFocus,
        host.outsideController,
        'after the protected modal',
      );
    },
    twoBars: true,
  );

  _test(
    'OCR-style read-only opt-out retains the bar but not focus after an outside click',
    (tester, host) async {
      final bar = host.first;
      final state = tester.state<State<TextField>>(_within(_query));
      final query = bar.queryController.value;
      expect(_within(_replacement), findsNothing);
      expect(_within(_toggleReplace), findsNothing);
      await tester.testTextInput.receiveAction(TextInputAction.search);
      await _click(tester, find.byKey(_outside));
      await tester.pump(const Duration(milliseconds: 300));
      expect(bar.outsideCalls + bar.closeCalls, 0);
      expect(bar.nextCalls, 1);
      expect(bar.disposed, isFalse);
      expect(find.byType(FindReplaceBar), findsOneWidget);
      expect(tester.state<State<TextField>>(_within(_query)), same(state));
      expect(bar.queryController.value, query);
      expect(bar.queryFocus.hasFocus, isFalse);
      await _typeInFocusedField(
        tester,
        host.outsideFocus,
        host.outsideController,
        'OCR selection must not capture this input',
      );
      expect(bar.queryController.value, query);
      await _click(tester, _within(_close));
      expect(bar.closeCalls, 1);
      expect(bar.outsideCalls, 0);
      expect(find.byType(FindReplaceBar), findsNothing);
    },
    configuration: const _BarConfiguration(
      dismissOnTapOutside: false,
      replaceable: false,
    ),
  );

  for (final mode in _modes) {
    _test('$mode: native glyph buttons and toggles expose working semantics',
        (tester, host) async {
      final handle = tester.ensureSemantics();
      try {
        host.layout(mode: mode);
        await tester.pump();
        await tester.pump();
        final bar = host.first;
        _expectTheme(tester, mode);
        expect(
          LocaleKeys.findAndReplace_find.tr(),
          isNot(LocaleKeys.findAndReplace_find),
        );
        expect(
          tester.widget<TextField>(_within(_query)).decoration!.hintText,
          LocaleKeys.findAndReplace_find.tr(),
        );
        for (final entry in [
          (
            _toggleReplace,
            LocaleKeys.findAndReplace_hideReplace,
            Icons.keyboard_arrow_down_rounded
          ),
          (
            _previous,
            LocaleKeys.findAndReplace_previousMatch,
            Icons.keyboard_arrow_up_rounded
          ),
          (
            _next,
            LocaleKeys.findAndReplace_nextMatch,
            Icons.keyboard_arrow_down_rounded
          ),
          (_close, LocaleKeys.findAndReplace_close, Icons.close_rounded),
          (
            _replaceOne,
            LocaleKeys.findAndReplace_replace,
            Icons.find_replace_rounded
          ),
          (
            _replaceAll,
            LocaleKeys.findAndReplace_replaceAll,
            Icons.change_circle_rounded
          ),
        ]) {
          _expectNativeButton(tester, entry.$1, entry.$2.tr());
          final glyph = tester.widget<IconButton>(_within(entry.$1)).icon
              as WorkspaceGlyph;
          expect(glyph.icon, entry.$3);
          expect(glyph.role, WorkspaceGlyphRole.standard);
        }
        _expectLiveCount(_matchLabel(1, 3));

        for (final key in [_next, _previous, _replaceOne, _replaceAll]) {
          final node = tester.getSemantics(_within(key));
          node.owner!.performAction(node.id, ui.SemanticsAction.tap);
          await tester.pump();
        }
        expect(bar.nextCalls, 1);
        expect(bar.previousCalls, 1);
        expect(bar.replaceCalls, 1);
        expect(bar.replaceAllCalls, 1);
        expect(bar.queryFocus.hasPrimaryFocus, isTrue);

        expect(
          find.semantics.byFlag(ui.SemanticsFlag.hasToggledState),
          findsNWidgets(3),
        );
        for (final selected in [true, false]) {
          for (var index = 0; index < _optionKeys.length; index++) {
            final key = _optionKeys[index];
            _expectOptionSemantics(key, selected: !selected);
            final node = _optionNode(key);
            node.owner!.performAction(node.id, ui.SemanticsAction.tap);
            await tester.pump();
            _expectOptionSemantics(key, selected: selected);
            expect(_optionValues(bar.options)[index], selected);
            final ink = find.descendant(
              of: _option(key),
              matching: find.byType(InkWell),
            );
            final palette = FindBarPalette.of(tester.element(_within(_query)));
            expect(tester.widget<InkWell>(ink).hoverColor, palette.hover);
            final material = tester.widget<Material>(
              find.ancestor(of: ink, matching: find.byType(Material)).first,
            );
            expect(
              material.color,
              selected ? palette.selected : Colors.transparent,
            );
          }
        }
        expect(bar.optionChanges, hasLength(6));
        expect(bar.options, const FindOptions());

        for (final show in [false, true]) {
          final node = tester.getSemantics(_within(_toggleReplace));
          node.owner!.performAction(node.id, ui.SemanticsAction.tap);
          await tester.pump();
          expect(_within(_replacement), show ? findsOneWidget : findsNothing);
          _expectNativeButton(
            tester,
            _toggleReplace,
            (show
                    ? LocaleKeys.findAndReplace_hideReplace
                    : LocaleKeys.findAndReplace_showReplace)
                .tr(),
          );
        }

        bar.setResults(0);
        await tester.pump();
        _expectLiveCount(LocaleKeys.findAndReplace_noResult.tr());
        for (final entry in [
          (_previous, LocaleKeys.findAndReplace_previousMatch),
          (_next, LocaleKeys.findAndReplace_nextMatch),
          (_replaceOne, LocaleKeys.findAndReplace_replace),
          (_replaceAll, LocaleKeys.findAndReplace_replaceAll),
        ]) {
          _expectNativeButton(tester, entry.$1, entry.$2.tr(), enabled: false);
          final glyph = tester.widget<IconButton>(_within(entry.$1)).icon
              as WorkspaceGlyph;
          expect(glyph.role, WorkspaceGlyphRole.preserveInk);
          await _click(tester, _within(entry.$1));
        }
        expect(bar.nextCalls, 1);
        expect(bar.previousCalls, 1);
        expect(bar.replaceCalls, 1);
        expect(bar.replaceAllCalls, 1);
        expect(bar.queryFocus.hasPrimaryFocus, isTrue);
        expect(bar.outsideCalls + bar.closeCalls, 0);

        _expectNativeButton(
          tester,
          _close,
          LocaleKeys.findAndReplace_close.tr(),
        );
        final close = tester.getSemantics(_within(_close));
        close.owner!.performAction(close.id, ui.SemanticsAction.tap);
        await tester.pump();
        expect(bar.closeCalls, 1);
        expect(bar.outsideCalls, 0);
        expect(close.attached, isFalse);
        expect(find.byType(FindReplaceBar), findsNothing);
      } finally {
        // The framework checks semantics leaks before addTearDown callbacks.
        handle.dispose();
      }
    });

    for (final activeField in [_query, _replacement]) {
      _test(
        '$mode: 2x text at 240/320/560 keeps both field states and ${activeField.value} focus',
        (tester, host) async {
          host.layout(mode: mode, textScale: 2);
          await tester.pump();
          await tester.pump();
          final bar = host.first;
          await _click(tester, _within(activeField));
          bar.queryController.value = TextEditingValue(
            text: 'needle draft',
            selection: const TextSelection(baseOffset: 2, extentOffset: 6),
            composing: activeField == _query
                ? const TextRange(start: 1, end: 7)
                : TextRange.empty,
          );
          bar.replaceController.value = TextEditingValue(
            text: 'replacement draft',
            selection: const TextSelection(baseOffset: 3, extentOffset: 8),
            composing: activeField == _replacement
                ? const TextRange(start: 2, end: 10)
                : TextRange.empty,
          );
          await tester.pump();
          final querySnapshot = _FieldSnapshot(tester, _within(_query));
          final replaceSnapshot = _FieldSnapshot(tester, _within(_replacement));
          final activeFocus =
              activeField == _query ? bar.queryFocus : bar.replaceFocus;

          for (final width in [
            560.0,
            240.0,
            320.0,
            560.0,
            720.0,
            240.0,
            560.0,
          ]) {
            host.layout(mode: mode, width: width, textScale: 2);
            await tester.pump();
            await tester.pump();
            expect(
              tester.takeException(),
              isNull,
              reason: '$mode at $width px',
            );
            querySnapshot.expectUnchanged(tester);
            replaceSnapshot.expectUnchanged(tester);
            expect(FocusManager.instance.primaryFocus, same(activeFocus));
            expect(activeFocus.hasPrimaryFocus, isTrue);
            expect(tester.testTextInput.hasAnyClients, isTrue);
            final bounds = tester.getRect(find.byKey(_firstBar));
            expect(bounds.width, closeTo(width > 560 ? 560 : width, 0.01));
            expect(
              MediaQuery.textScalerOf(tester.element(_within(_query)))
                  .scale(13),
              26,
            );
            for (final key in [
              _query,
              _replacement,
              _toggleReplace,
              _previous,
              _next,
              _close,
              _replaceOne,
              _replaceAll,
            ]) {
              final child = _within(key);
              expect(child.hitTestable(), findsOneWidget);
              _expectWithin(tester.getRect(child), bounds);
            }
            for (final key in _optionKeys) {
              expect(_option(key).hitTestable(), findsOneWidget);
              _expectWithin(tester.getRect(_option(key)), bounds);
            }
            final queryGroup =
                tester.getRect(_within(const ValueKey('findQueryGroup')));
            final navigation =
                tester.getRect(_within(const ValueKey('findNavigationGroup')));
            expect(navigation.top, greaterThanOrEqualTo(queryGroup.bottom));
            _expectTheme(tester, mode);
          }
          expect(bar.outsideCalls + bar.closeCalls, 0);
          expect(bar.optionChanges, isEmpty);
        },
      );
    }
  }

  _test(
      'normal-scale 560px layout fits navigation beside the query (border regression)',
      (tester, host) async {
    // Source regression, not an assertion of the accidental layout: Container
    // adds its 0.6px borders to the 6px padding. Previously, _buildFindRow
    // budgeted only width - 12, so its two inline children plus gap exceeded
    // the actual Wrap width by 1.2px and wrapped even at the maximum width.
    final before = _FieldSnapshot(tester, _within(_query));
    host.layout(width: 240);
    await tester.pump();
    final narrowQuery =
        tester.getRect(_within(const ValueKey('findQueryGroup')));
    final narrowNavigation =
        tester.getRect(_within(const ValueKey('findNavigationGroup')));
    expect(narrowNavigation.top, greaterThanOrEqualTo(narrowQuery.bottom));
    host.layout();
    await tester.pump();
    before.expectUnchanged(tester);
    expect(host.first.queryFocus.hasPrimaryFocus, isTrue);
    final query = tester.getRect(_within(const ValueKey('findQueryGroup')));
    final navigation =
        tester.getRect(_within(const ValueKey('findNavigationGroup')));
    expect(navigation.center.dy, closeTo(query.center.dy, 0.01));
    expect(navigation.left, greaterThan(query.right));
  });
}

enum _SubmitMode { next, callback, unmount }

class _BarConfiguration {
  const _BarConfiguration({
    this.customOutside = true,
    this.dismissOnTapOutside = true,
    this.replaceable = true,
    this.submitMode = _SubmitMode.next,
  });

  final bool customOutside;
  final bool dismissOnTapOutside;
  final bool replaceable;
  final _SubmitMode submitMode;
}

void _test(
  String name,
  Future<void> Function(WidgetTester, _HarnessState) body, {
  _BarConfiguration configuration = const _BarConfiguration(),
  bool twoBars = false,
}) {
  testWidgets(
    name,
    (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 800);
      final key = GlobalKey<_HarnessState>();
      try {
        await tester.pumpWidget(
          _Harness(
            key: key,
            configuration: configuration,
            twoBars: twoBars,
          ),
        );
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        expect(key.currentState!.first.queryFocus.hasPrimaryFocus, isTrue);
        await body(tester, key.currentState!);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        tester.view.reset();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: const Timeout(Duration(seconds: 30)),
  );
}

class _Harness extends StatefulWidget {
  const _Harness({
    super.key,
    required this.configuration,
    required this.twoBars,
  });

  final _BarConfiguration configuration;
  final bool twoBars;

  @override
  State<_Harness> createState() => _HarnessState();
}

class _HarnessState extends State<_Harness> {
  final navigator = GlobalKey<NavigatorState>();
  final firstKey = GlobalKey<_BarHostState>();
  final secondKey = GlobalKey<_BarHostState>();
  final outsideController = TextEditingController(text: 'Page title draft');
  final outsideFocus = FocusNode(debugLabel: 'outside native field');
  final dialogController = TextEditingController();
  final dialogFocus = FocusNode(debugLabel: 'protected modal field');
  final styles = ValueNotifier(DefaultIconStyle.monochrome);
  bool firstVisible = true;
  bool secondVisible = true;
  int outsidePointerDowns = 0;
  int outsideTaps = 0;
  double width = 560;
  double textScale = 1;
  String mode = 'light';

  _BarHostState get first => firstKey.currentState!;
  _BarHostState get second => secondKey.currentState!;

  void layout({
    String mode = 'light',
    double width = 560,
    double textScale = 1,
  }) {
    setState(() {
      this.mode = mode;
      this.width = width;
      this.textScale = textScale;
    });
  }

  @override
  Widget build(BuildContext context) => EasyLocalization(
        supportedLocales: const [Locale('en', 'US')],
        startLocale: const Locale('en', 'US'),
        fallbackLocale: const Locale('en', 'US'),
        path: 'assets/translations',
        saveLocale: false,
        assetLoader: const _PreloadedTranslations(),
        child: Builder(
          builder: (context) => DefaultIconStyleScope(
            styles: styles,
            child: MaterialApp(
              navigatorKey: navigator,
              locale: context.locale,
              supportedLocales: context.supportedLocales,
              localizationsDelegates: context.localizationDelegates,
              theme: _theme(mode),
              themeAnimationDuration: Duration.zero,
              builder: (context, child) => MediaQuery(
                data: MediaQuery.of(context).copyWith(
                  textScaler: TextScaler.linear(textScale),
                ),
                child: child!,
              ),
              home: Scaffold(
                body: Stack(
                  children: [
                    if (firstVisible)
                      _positionedBar(firstKey, _firstBar, 24, () {
                        setState(() => firstVisible = false);
                      }),
                    if (widget.twoBars && secondVisible)
                      _positionedBar(secondKey, _secondBar, 196, () {
                        setState(() => secondVisible = false);
                      }),
                    Positioned(
                      left: 24,
                      top: 440,
                      width: 320,
                      child: Listener(
                        onPointerDown: (_) => outsidePointerDowns++,
                        child: TextField(
                          key: _outside,
                          controller: outsideController,
                          focusNode: outsideFocus,
                          onTap: () => outsideTaps++,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

  Widget _positionedBar(
    GlobalKey<_BarHostState> key,
    Key barKey,
    double top,
    VoidCallback dismiss,
  ) =>
      Positioned(
        key: ValueKey(barKey),
        top: top,
        left: 24,
        width: width,
        // The pane bounds the bar without forcing it wider than its 560px cap.
        child: Align(
          alignment: Alignment.topLeft,
          child: _BarHost(
            key: key,
            barKey: barKey,
            configuration: widget.configuration,
            autofocus: barKey == _firstBar,
            dismiss: dismiss,
          ),
        ),
      );

  @override
  void dispose() {
    outsideController.dispose();
    outsideFocus.dispose();
    dialogController.dispose();
    dialogFocus.dispose();
    styles.dispose();
    super.dispose();
  }
}

class _BarHost extends StatefulWidget {
  const _BarHost({
    super.key,
    required this.barKey,
    required this.configuration,
    required this.autofocus,
    required this.dismiss,
  });

  final Key barKey;
  final _BarConfiguration configuration;
  final bool autofocus;
  final VoidCallback dismiss;

  @override
  State<_BarHost> createState() => _BarHostState();
}

class _BarHostState extends State<_BarHost> {
  final queryController = TextEditingController.fromValue(
    const TextEditingValue(
      text: 'needle',
      selection: TextSelection.collapsed(offset: 6),
    ),
  );
  final replaceController = TextEditingController.fromValue(
    const TextEditingValue(
      text: 'replacement',
      selection: TextSelection.collapsed(offset: 11),
    ),
  );
  final queryFocus = FocusNode(debugLabel: 'find query');
  final replaceFocus = FocusNode(debugLabel: 'find replacement');
  final optionChanges = <FindOptions>[];
  FindOptions options = const FindOptions();
  int count = 3;
  int current = 1;
  int outsideCalls = 0;
  int closeCalls = 0;
  int nextCalls = 0;
  int previousCalls = 0;
  int submitCalls = 0;
  int replaceCalls = 0;
  int replaceAllCalls = 0;
  bool showReplace = true;
  bool disposed = false;
  TextEditingValue? queryAtDisposal;
  TextEditingValue? replaceAtDisposal;

  @override
  void initState() {
    super.initState();
    queryController.addListener(_queryChanged);
  }

  void _queryChanged() => setState(() {});

  void setResults(int value) => setState(() {
        count = value;
        current = value == 0 ? 0 : 1;
      });

  void _nextMatch() => setState(() {
        nextCalls++;
        current = current % count + 1;
      });

  void _previousMatch() => setState(() {
        previousCalls++;
        current = (current + count - 2) % count + 1;
      });

  void _submitted() {
    submitCalls++;
    if (widget.configuration.submitMode == _SubmitMode.unmount) {
      widget.dismiss();
    }
  }

  @override
  Widget build(BuildContext context) => FindReplaceBar(
        key: widget.barKey,
        findController: queryController,
        findFocusNode: queryFocus,
        options: options,
        onOptionsChanged: (value) => setState(() {
          options = value;
          optionChanges.add(value);
        }),
        matchCount: count,
        currentMatch: current,
        onPrevious: count == 0 ? null : _previousMatch,
        onNext: count == 0 ? null : _nextMatch,
        onClose: () {
          closeCalls++;
          widget.dismiss();
        },
        onTapOutside: widget.configuration.customOutside
            ? () {
                outsideCalls++;
                widget.dismiss();
              }
            : null,
        dismissOnTapOutside: widget.configuration.dismissOnTapOutside,
        replaceController:
            widget.configuration.replaceable ? replaceController : null,
        replaceFocusNode:
            widget.configuration.replaceable ? replaceFocus : null,
        showReplace: showReplace,
        onToggleReplace: () => setState(() => showReplace = !showReplace),
        onReplace: () => replaceCalls++,
        onReplaceAll: () => replaceAllCalls++,
        onSubmitted: widget.configuration.submitMode == _SubmitMode.next
            ? null
            : _submitted,
        autofocus: widget.autofocus,
      );

  @override
  void dispose() {
    queryAtDisposal = queryController.value;
    replaceAtDisposal = replaceController.value;
    queryController.removeListener(_queryChanged);
    queryController.dispose();
    replaceController.dispose();
    queryFocus.dispose();
    replaceFocus.dispose();
    disposed = true;
    super.dispose();
  }
}

class _PreloadedTranslations extends AssetLoader {
  const _PreloadedTranslations();

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

ThemeData _theme(String mode) => DesktopAppearance()
    .getThemeData(
      mode == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      mode == 'dark' ? Brightness.dark : Brightness.light,
      'Ahem',
      'Ahem',
    )
    .copyWith(platform: TargetPlatform.windows);

Finder _within(Key key, {Key bar = _firstBar}) => find.descendant(
      of: find.byKey(bar),
      matching: find.byKey(key),
    );

Finder _option(String key) => find.descendant(
      of: find.byKey(_firstBar),
      matching: find.byTooltip(key.tr()),
    );

Future<void> _click(WidgetTester tester, Finder target) async {
  expect(target.hitTestable(), findsOneWidget);
  // A fresh pointer for each click avoids a reused mouse's double-tap arena.
  await tester.tap(target, kind: ui.PointerDeviceKind.mouse);
  await tester.pump();
}

Future<void> _typeInFocusedField(
  WidgetTester tester,
  FocusNode focus,
  TextEditingController controller,
  String text,
) async {
  expect(focus.hasPrimaryFocus, isTrue);
  expect(tester.testTextInput.hasAnyClients, isTrue);
  tester.testTextInput.enterText(text);
  await tester.pump();
  expect(controller.text, text);
  expect(controller.selection, TextSelection.collapsed(offset: text.length));
  expect(focus.hasPrimaryFocus, isTrue);
}

List<bool> _optionValues(FindOptions options) =>
    [options.caseSensitive, options.wholeWord, options.useRegex];

String _matchLabel(int current, int total) =>
    LocaleKeys.findAndReplace_matchOfTotal.tr(args: ['$current', '$total']);

void _expectNativeButton(
  WidgetTester tester,
  Key key,
  String label, {
  bool enabled = true,
}) {
  final button = tester.widget<IconButton>(_within(key));
  expect(button.icon, isA<WorkspaceGlyph>());
  expect(button.tooltip, label);
  expect(button.onPressed, enabled ? isNotNull : isNull);
  final node = tester.getSemantics(_within(key));
  final data = node.getSemanticsData();
  expect(node.attached, isTrue);
  // Native IconButton exposes its description as tooltip, not as label.
  expect(data.tooltip, label);
  expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.hasEnabledState), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isEnabled), enabled);
  expect(data.hasAction(ui.SemanticsAction.tap), enabled);
}

// Search the attached semantics tree, not cached debugSemantics on render
// objects. The decorative Aa/ab/.* text may be merged into the same label.
SemanticsNode _optionNode(String key) =>
    find.semantics.byLabel(RegExp(RegExp.escape(key.tr()))).evaluate().single;

void _expectOptionSemantics(String key, {required bool selected}) {
  final node = _optionNode(key);
  final data = node.getSemanticsData();
  expect(node.attached, isTrue);
  expect(data.label.split(key.tr()), hasLength(2));
  expect(
    data.tooltip,
    isEmpty,
    reason: 'The option tooltip must not be announced twice.',
  );
  expect(data.hasFlag(ui.SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.hasToggledState), isTrue);
  expect(data.hasFlag(ui.SemanticsFlag.isToggled), selected);
  expect(data.hasAction(ui.SemanticsAction.tap), isTrue);
}

void _expectLiveCount(String label) {
  expect(find.text(label), findsOneWidget);
  final node = find.semantics.byLabel(label).evaluate().single;
  expect(node.attached, isTrue);
  expect(
    node.getSemanticsData().hasFlag(ui.SemanticsFlag.isLiveRegion),
    isTrue,
  );
}

void _expectWithin(Rect child, Rect parent) {
  expect(child.width, greaterThan(0));
  expect(child.height, greaterThan(0));
  expect(parent.inflate(0.01).contains(child.topLeft), isTrue);
  expect(parent.inflate(0.01).contains(child.bottomRight), isTrue);
}

void _expectTheme(WidgetTester tester, String mode) {
  final context = tester.element(find.byKey(_firstBar));
  final palette = PremiumThemeExtension.of(context);
  final paper = mode == 'paper';
  expect(PaperTheme.isEnabled(context), paper);
  expect(
    Theme.of(context).brightness,
    mode == 'dark' ? Brightness.dark : Brightness.light,
  );
  final surface = tester
      .widget<Container>(
        find
            .descendant(
              of: find.byKey(_firstBar),
              matching: find.byType(Container),
            )
            .first,
      )
      .decoration! as BoxDecoration;
  expect(
    surface.color,
    paper ? PaperTheme.popupBackground : palette.floatingSurface,
  );
  for (final key in [_query, _replacement]) {
    final container = tester.widget<Container>(
      find.ancestor(of: _within(key), matching: find.byType(Container)).first,
    );
    final field = container.decoration! as BoxDecoration;
    expect(
      field.color,
      paper ? PaperTheme.controlBackground : palette.mutedSurface,
    );
  }
  if (paper) {
    expect(surface.color!.r, greaterThan(surface.color!.b));
    expect(surface.color, isNot(Colors.white));
  }
}

class _FieldSnapshot {
  _FieldSnapshot(WidgetTester tester, this.finder)
      : element = tester.element(finder),
        state = tester.state<State<TextField>>(finder),
        editableState = tester.state<EditableTextState>(
          find.descendant(of: finder, matching: find.byType(EditableText)),
        ),
        controller = tester.widget<TextField>(finder).controller!,
        focus = tester.widget<TextField>(finder).focusNode!,
        value = tester.widget<TextField>(finder).controller!.value,
        key = tester.widget<TextField>(finder).key;

  final Finder finder;
  final Element element;
  final State<TextField> state;
  final EditableTextState editableState;
  final TextEditingController controller;
  final FocusNode focus;
  final TextEditingValue value;
  final Key? key;

  void expectUnchanged(WidgetTester tester) {
    final field = tester.widget<TextField>(finder);
    final editable =
        find.descendant(of: finder, matching: find.byType(EditableText));
    final input = tester.widget<EditableText>(editable);
    expect(element.mounted, isTrue);
    expect(state.mounted, isTrue);
    expect(editableState.mounted, isTrue);
    expect(tester.element(finder), same(element));
    expect(tester.state<State<TextField>>(finder), same(state));
    expect(tester.state<EditableTextState>(editable), same(editableState));
    expect(field.key, key);
    expect(field.controller, same(controller));
    expect(input.controller, same(controller));
    expect(field.focusNode, same(focus));
    expect(input.focusNode, same(focus));
    expect(
      controller.value,
      value,
      reason: 'Draft, selection and IME composing range must survive.',
    );
  }
}
