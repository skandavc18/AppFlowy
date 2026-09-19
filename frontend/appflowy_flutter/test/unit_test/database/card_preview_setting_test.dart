import 'dart:async';
import 'dart:convert';
import 'dart:ui' show SemanticsAction, SemanticsFlag;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/plugins/database/board/presentation/toolbar/card_preview_button.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../widget_test/test_asset_bundle.dart';

const _viewId = 'card-preview-test-board';
const _modeIds = {
  CardPreviewMode.pageAndTitle: 'page_title',
  CardPreviewMode.cover: 'cover',
  CardPreviewMode.pageContent: 'page',
  CardPreviewMode.none: 'none',
  CardPreviewMode.portrait: 'portrait',
  CardPreviewMode.titleAndProperties: 'title_properties',
};
const _labelKeys = {
  CardPreviewMode.pageAndTitle: LocaleKeys.gallery_facePage,
  CardPreviewMode.cover: LocaleKeys.gallery_faceCover,
  CardPreviewMode.pageContent: LocaleKeys.gallery_faceContent,
  CardPreviewMode.none: LocaleKeys.gallery_faceNone,
  CardPreviewMode.portrait: LocaleKeys.gallery_facePortrait,
  CardPreviewMode.titleAndProperties: LocaleKeys.cardPreview_titleAndProperties,
};
const _icons = {
  CardPreviewMode.pageAndTitle: Icons.sticky_note_2_rounded,
  CardPreviewMode.cover: Icons.image_rounded,
  CardPreviewMode.pageContent: Icons.article_rounded,
  CardPreviewMode.none: Icons.notes_rounded,
  CardPreviewMode.portrait: Icons.crop_portrait_rounded,
  CardPreviewMode.titleAndProperties: Icons.view_list_rounded,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousDisableLog = Log.shared.disableLog;

  setUpAll(() async {
    Log.shared.disableLog = true;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() {
    Log.shared.disableLog = previousDisableLog;
  });

  group('CardPreviewSetting', () {
    test('menu order, persisted IDs and default remain explicit', () {
      expect(CardPreviewMode.values, _modeIds.keys.toList());
      expect(
        CardPreviewMode.values.map((mode) => mode.id).toList(),
        _modeIds.values.toList(),
      );
      expect(const CardPreviewSetting().mode, CardPreviewMode.cover);
      expect(CardPreviewSetting.currentVersion, 1);
      expect(CardPreviewSetting.envelopeKey, 'appflowy_card_preview');
    });

    test(
        'row data is opt-in; the five legacy IDs and their order stay unchanged',
        () {
      const legacyModes = {
        'page_title': CardPreviewMode.pageAndTitle,
        'cover': CardPreviewMode.cover,
        'page': CardPreviewMode.pageContent,
        'none': CardPreviewMode.none,
        'portrait': CardPreviewMode.portrait,
      };
      expect(
        CardPreviewMode.values.take(legacyModes.length),
        legacyModes.values,
      );
      for (final entry in legacyModes.entries) {
        final setting = CardPreviewSetting.fromExtra(
          '{"appflowy_card_preview":{"version":1,"mode":"${entry.key}"}}',
        );
        expect(setting.mode, entry.value);
        expect(setting.toJson(), {'version': 1, 'mode': entry.key});
        expect(setting.mode.showsRowData, isFalse, reason: entry.key);
      }
      expect(CardPreviewMode.values.last, CardPreviewMode.titleAndProperties);
      expect(
        CardPreviewMode.values.where((mode) => mode.showsRowData),
        [CardPreviewMode.titleAndProperties],
      );
    });

    for (final entry in _modeIds.entries) {
      test('${entry.key.name} round-trips through version 1 and ViewPB', () {
        final setting = CardPreviewSetting(mode: entry.key);
        expect(setting.toJson(), {'version': 1, 'mode': entry.value});
        final view = _view(extra: setting.mergeIntoExtra(''));
        final reopened = ViewPB.fromBuffer(view.writeToBuffer());
        expect(CardPreviewSetting.fromExtra(reopened.extra).mode, entry.key);
        expect(CardPreviewMode.fromId(entry.value), entry.key);
      });
    }

    for (final entry in {
      'cover': CardPreviewMode.cover,
      'page': CardPreviewMode.pageContent,
      'none': CardPreviewMode.none,
    }.entries) {
      test('legacy ${entry.key} keeps its original meaning and ID', () {
        final setting = CardPreviewSetting.fromExtra(
          '{"appflowy_card_preview":{"version":1,"mode":"${entry.key}"}}',
        );
        expect(setting.mode, entry.value);
        expect(setting.toJson()['mode'], entry.key);
      });
    }

    test('missing and unknown IDs default to cover', () {
      for (final id in [
        null,
        '',
        'future-mode',
        'picture',
        'content',
        'writing',
      ]) {
        expect(
          CardPreviewMode.fromId(id),
          CardPreviewMode.cover,
          reason: '$id',
        );
      }
    });

    test('malformed JSON and primitive roots default safely', () {
      for (final extra in [
        '',
        '{broken',
        'null',
        'true',
        '7',
        '1.5',
        '"page"',
        '[]',
        '{}',
      ]) {
        expect(CardPreviewSetting.fromExtra(extra).mode, CardPreviewMode.cover);
      }
    });

    test('primitive, list and incomplete envelopes default safely', () {
      for (final envelope in <Object?>[null, true, 7, 'page', [], {}]) {
        expect(
          CardPreviewSetting.fromExtra(
            jsonEncode({CardPreviewSetting.envelopeKey: envelope}),
          ).mode,
          CardPreviewMode.cover,
          reason: '$envelope',
        );
      }
    });

    test('corrupt primitive, list and map modes cannot throw', () {
      for (final mode in <Object?>[
        null,
        true,
        7,
        1.5,
        [],
        {'id': 'page'},
        '',
        'future',
      ]) {
        expect(
          CardPreviewSetting.fromExtra(
            jsonEncode({
              CardPreviewSetting.envelopeKey: {'version': 1, 'mode': mode},
            }),
          ).mode,
          CardPreviewMode.cover,
          reason: '$mode',
        );
      }
    });

    test('missing, corrupt and unsupported versions default safely', () {
      for (final version in <Object?>[null, true, '1', 1.0, 0, -1, 2, [], {}]) {
        expect(
          CardPreviewSetting.fromExtra(
            jsonEncode({
              CardPreviewSetting.envelopeKey: {
                'version': version,
                'mode': 'none',
              },
            }),
          ).mode,
          CardPreviewMode.cover,
          reason: '$version (${version.runtimeType})',
        );
      }
    });

    test('merging replaces only its own envelope', () {
      final unrelated = <String, Object?>{
        'unknown': {
          'nested': [null, false, 7, 'unchanged'],
        },
        'other_setting': {'version': 42, 'enabled': true},
        'cover': 'existing cover',
      };
      final original = jsonEncode({
        ...unrelated,
        CardPreviewSetting.envelopeKey: {'version': 1, 'mode': 'page'},
      });
      for (final mode in CardPreviewMode.values) {
        expect(
          jsonDecode(CardPreviewSetting(mode: mode).mergeIntoExtra(original)),
          {
            ...unrelated,
            CardPreviewSetting.envelopeKey: {
              'version': 1,
              'mode': _modeIds[mode],
            },
          },
        );
      }
    });
  });

  group('CardPreviewRegistry', () {
    test('shares a notifier by view ID without rereading stale snapshots', () {
      final store = _MemoryExtras({});
      final registry = store.registry();
      addTearDown(registry.reset);
      final view = _view(mode: CardPreviewMode.none);
      final notifier = registry.notifierFor(view);
      expect(registry.notifierFor(_view()), same(notifier));
      expect(registry.modeFor(_view()), CardPreviewMode.none);
      expect(
        registry.modeFor(_view(id: 'other', mode: CardPreviewMode.pageContent)),
        CardPreviewMode.pageContent,
      );
      expect(store.reads, isEmpty);
      expect(store.writes, isEmpty);
    });

    test('updates locally before a read resolves without mutating the view',
        () async {
      final view = _view();
      final before = view.writeToBuffer();
      final read = Completer<String>();
      final started = Completer<void>();
      final store = _MemoryExtras({});
      final registry = CardPreviewRegistry(
        readExtra: (id) {
          expectSync(id, _viewId);
          started.complete();
          return read.future;
        },
        writeExtra: store.writeExtra,
      );
      addTearDown(registry.reset);
      final notifications = <CardPreviewMode>[];
      final notifier = registry.notifierFor(view);
      notifier.addListener(() => notifications.add(notifier.value));
      final save = registry.set(view, CardPreviewMode.portrait);
      expect(notifier.value, CardPreviewMode.portrait);
      expect(notifications, [CardPreviewMode.portrait]);
      await started.future;
      expect(store.writes, isEmpty);
      read.complete(_extra(CardPreviewMode.cover));
      await save;
      expect(store.modeFor(_viewId), CardPreviewMode.portrait);
      expect(view.writeToBuffer(), before);
      expect(notifications, [CardPreviewMode.portrait]);
    });

    test('merges fresh extra rather than resurrecting stale unrelated settings',
        () async {
      final view = _view(
        extra: _extra(CardPreviewMode.cover, '{"removed":true,"other":"old"}'),
      );
      final fresh = <String, Object?>{
        'other': 'new',
        'unknown': {
          'version': 9,
          'values': [null, false, 'kept'],
        },
      };
      final store = _MemoryExtras({
        _viewId: _extra(CardPreviewMode.none, jsonEncode(fresh)),
      });
      final registry = store.registry();
      addTearDown(registry.reset);

      await registry.set(view, CardPreviewMode.pageAndTitle);

      expect(store.reads.single.viewId, _viewId);
      expect(store.writes.single.viewId, _viewId);
      expect(jsonDecode(store.values[_viewId]!), {
        ...fresh,
        CardPreviewSetting.envelopeKey: {'version': 1, 'mode': 'page_title'},
      });
      store.values[_viewId] =
          _extra(CardPreviewMode.pageAndTitle, '{"other":"changed again"}');
      await registry.set(view, CardPreviewMode.portrait);
      expect(jsonDecode(store.values[_viewId]!), {
        'other': 'changed again',
        CardPreviewSetting.envelopeKey: {'version': 1, 'mode': 'portrait'},
      });
    });

    test('rapid choices read and write serially in selection order', () async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.cover)});
      final registry = store.registry();
      addTearDown(registry.reset);
      final modes = CardPreviewMode.values;
      final gates = List.generate(modes.length, (_) => Completer<void>());
      final started = List.generate(modes.length, (_) => Completer<void>());
      store.beforeWrite = (_, __) async {
        final index = store.writes.length - 1;
        started[index].complete();
        await gates[index].future;
      };
      final view = _view();
      final saves = [for (final mode in modes) registry.set(view, mode)];
      expect(registry.modeFor(view), modes.last);

      for (var index = 0; index < modes.length; index++) {
        await started[index].future;
        expect(store.reads.length, index + 1);
        expect(store.writes.length, index + 1);
        expect(
          CardPreviewSetting.fromExtra(store.reads[index].extra).mode,
          index == 0 ? CardPreviewMode.cover : modes[index - 1],
        );
        expect(registry.modeFor(view), modes.last);
        gates[index].complete();
        await saves[index];
      }

      expect(store.writtenModes, modes);
      expect(store.modeFor(_viewId), modes.last);
      expect(registry.modeFor(view), modes.last);
    });

    test('a synchronous read failure rolls back and does not poison the queue',
        () async {
      final view = _view(mode: CardPreviewMode.none);
      final store = _MemoryExtras({_viewId: view.extra});
      var fail = true;
      final registry = CardPreviewRegistry(
        readExtra: (id) {
          if (fail) throw StateError('test read refused');
          return store.readExtra(id);
        },
        writeExtra: store.writeExtra,
      );
      addTearDown(registry.reset);

      final failed = registry.set(view, CardPreviewMode.pageAndTitle);
      expect(registry.modeFor(view), CardPreviewMode.pageAndTitle);
      await failed;
      expect(registry.modeFor(view), CardPreviewMode.none);
      expect(store.writes, isEmpty);
      fail = false;
      await registry.set(view, CardPreviewMode.portrait);
      expect(store.modeFor(_viewId), CardPreviewMode.portrait);
      expect(registry.modeFor(view), CardPreviewMode.portrait);
    });

    test(
        'write failure rolls back to the fresh stored mode, not the stale view',
        () async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.none)});
      store.beforeWrite = (_, __) => throw StateError('test write refused');
      final registry = store.registry();
      addTearDown(registry.reset);
      final view = _view();

      await registry.set(view, CardPreviewMode.portrait);

      expect(registry.modeFor(view), CardPreviewMode.none);
      expect(store.modeFor(_viewId), CardPreviewMode.none);
      store.beforeWrite = null;
      await registry.set(view, CardPreviewMode.pageContent);
      expect(registry.modeFor(view), CardPreviewMode.pageContent);
      expect(store.modeFor(_viewId), CardPreviewMode.pageContent);
    });

    test('latest failed save restores the preceding successful queued choice',
        () async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.cover)});
      store.beforeWrite = (_, extra) async {
        if (CardPreviewSetting.fromExtra(extra).mode ==
            CardPreviewMode.portrait) {
          throw StateError('test latest save refused');
        }
      };
      final registry = store.registry();
      addTearDown(registry.reset);
      final view = _view();
      final earlier = registry.set(view, CardPreviewMode.pageAndTitle);
      final latest = registry.set(view, CardPreviewMode.portrait);
      expect(registry.modeFor(view), CardPreviewMode.portrait);

      await Future.wait([earlier, latest]);

      expect(registry.modeFor(view), CardPreviewMode.pageAndTitle);
      expect(store.modeFor(_viewId), CardPreviewMode.pageAndTitle);
    });

    for (final laterMode in [
      CardPreviewMode.portrait,
      CardPreviewMode.pageAndTitle,
    ]) {
      test('older failure cannot roll back a later ${laterMode.name} selection',
          () async {
        final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.none)});
        final gates = List.generate(2, (_) => Completer<void>());
        final started = List.generate(2, (_) => Completer<void>());
        store.beforeWrite = (_, __) async {
          final index = store.writes.length - 1;
          started[index].complete();
          await gates[index].future;
        };
        final registry = store.registry();
        addTearDown(registry.reset);
        final view = _view(mode: CardPreviewMode.none);
        final notifier = registry.notifierFor(view);
        final notifications = <CardPreviewMode>[];
        notifier.addListener(() => notifications.add(notifier.value));
        final earlier = registry.set(view, CardPreviewMode.pageAndTitle);
        await started[0].future;
        final later = registry.set(view, laterMode);
        final beforeFailure = [...notifications];

        gates[0].completeError(StateError('test earlier save refused'));
        await earlier;
        await started[1].future;
        expect(registry.modeFor(view), laterMode);
        expect(notifications, beforeFailure, reason: 'no transient rollback');
        gates[1].complete();
        await later;
        expect(store.modeFor(_viewId), laterMode);
        expect(registry.modeFor(view), laterMode);
      });
    }

    test(
        'a notifier listener can enqueue another choice without reversing writes',
        () async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.cover)});
      final registry = store.registry();
      addTearDown(registry.reset);
      final view = _view();
      final notifier = registry.notifierFor(view);
      Future<void>? later;
      notifier.addListener(() {
        if (notifier.value == CardPreviewMode.pageAndTitle) {
          later = registry.set(view, CardPreviewMode.portrait);
        }
      });

      await registry.set(view, CardPreviewMode.pageAndTitle);
      await later;

      expect(
        store.writtenModes,
        [CardPreviewMode.pageAndTitle, CardPreviewMode.portrait],
      );
      expect(store.modeFor(_viewId), CardPreviewMode.portrait);
      expect(registry.modeFor(view), CardPreviewMode.portrait);
    });

    test('one view can save while another is blocked and then fails', () async {
      final firstView = _view(mode: CardPreviewMode.none);
      final secondView =
          _view(id: 'second-board', mode: CardPreviewMode.pageContent);
      final store = _MemoryExtras(
        {firstView.id: firstView.extra, secondView.id: secondView.extra},
      );
      final gate = Completer<void>();
      final started = Completer<void>();
      store.beforeWrite = (id, _) async {
        if (id == firstView.id) {
          started.complete();
          await gate.future;
        }
      };
      final registry = store.registry();
      addTearDown(registry.reset);
      final first = registry.set(firstView, CardPreviewMode.portrait);
      await started.future;
      await registry.set(secondView, CardPreviewMode.pageAndTitle);
      expect(store.modeFor(secondView.id), CardPreviewMode.pageAndTitle);
      expect(registry.modeFor(firstView), CardPreviewMode.portrait);

      gate.completeError(StateError('test first view refused'));
      await first;

      expect(registry.modeFor(firstView), CardPreviewMode.none);
      expect(registry.modeFor(secondView), CardPreviewMode.pageAndTitle);
      expect(store.modeFor(firstView.id), CardPreviewMode.none);
    });

    test('reset skips a queued save that has not started', () async {
      final store = _MemoryExtras({});
      final registry = store.registry();
      addTearDown(registry.reset);
      final save = registry.set(_view(), CardPreviewMode.portrait);
      registry.reset();
      await save;
      expect(store.reads, isEmpty);
      expect(store.writes, isEmpty);
      expect(
        registry.modeFor(_view(mode: CardPreviewMode.none)),
        CardPreviewMode.none,
      );
    });

    test('reset during a read prevents its late write and notifier adoption',
        () async {
      final read = Completer<String>();
      final started = Completer<void>();
      final store = _MemoryExtras({});
      final registry = CardPreviewRegistry(
        readExtra: (_) {
          started.complete();
          return read.future;
        },
        writeExtra: store.writeExtra,
      );
      addTearDown(registry.reset);
      final save = registry.set(_view(), CardPreviewMode.portrait);
      await started.future;
      registry.reset();
      final replacement =
          registry.notifierFor(_view(mode: CardPreviewMode.pageContent));
      read.complete(_extra(CardPreviewMode.none));
      await save;
      expect(store.writes, isEmpty);
      expect(replacement.value, CardPreviewMode.pageContent);
    });

    test('reset keeps an in-flight write ahead of new saves for the same view',
        () async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.cover)});
      final gate = Completer<void>();
      final started = Completer<void>();
      store.beforeWrite = (_, __) async {
        if (store.writes.length == 1) {
          started.complete();
          await gate.future;
        }
      };
      final registry = store.registry();
      addTearDown(registry.reset);
      final view = _view();
      final oldSave = registry.set(view, CardPreviewMode.pageAndTitle);
      await started.future;
      registry.reset();
      final newSave = registry.set(view, CardPreviewMode.portrait);
      await Future<void>.delayed(Duration.zero);
      expect(store.writes.length, 1);
      expect(registry.modeFor(view), CardPreviewMode.portrait);

      gate.complete();
      await Future.wait([oldSave, newSave]);

      expect(
        store.writtenModes,
        [CardPreviewMode.pageAndTitle, CardPreviewMode.portrait],
      );
      expect(store.modeFor(_viewId), CardPreviewMode.portrait);
      expect(registry.modeFor(view), CardPreviewMode.portrait);
    });

    test('a failed write completing after reset cannot touch the new notifier',
        () async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.cover)});
      final gate = Completer<void>();
      final started = Completer<void>();
      store.beforeWrite = (_, __) {
        started.complete();
        return gate.future;
      };
      final registry = store.registry();
      addTearDown(registry.reset);
      final oldSave = registry.set(_view(), CardPreviewMode.portrait);
      await started.future;
      registry.reset();
      final replacement =
          registry.notifierFor(_view(mode: CardPreviewMode.none));

      gate.completeError(StateError('test late save refused'));
      await oldSave;

      expect(replacement.value, CardPreviewMode.none);
      expect(store.modeFor(_viewId), CardPreviewMode.cover);
    });
  });

  group('CardPreviewButton', () {
    for (final appearance in ['light', 'dark', 'paper']) {
      testWidgets(
          '$appearance: all preview choices, icons and checkmarks persist',
          (tester) async {
        final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.cover)});
        final registry = store.registry();
        final view = _view();
        final semantics = tester.ensureSemantics();
        try {
          await tester.pumpWidget(_app(appearance, view, registry));
          await tester.pumpAndSettle();
          final buttonContext = tester.element(find.byType(CardPreviewButton));
          final button =
              tester.widget<FlowyIconButton>(find.byType(FlowyIconButton));
          expect(
            button.hoverColor,
            AFThemeExtension.of(buttonContext).greyHover,
          );
          expect(PaperTheme.isEnabled(buttonContext), appearance == 'paper');
          _expectButtonSemantics(tester, CardPreviewMode.cover);
          await _openMenu(tester);

          final rows =
              tester.widgetList<AppMenuRow>(find.byType(AppMenuRow)).toList();
          expect(
            rows.map((row) => row.label).toList(),
            _labelKeys.values.map((key) => key.tr()).toList(),
          );
          for (final mode in CardPreviewMode.values) {
            expect(
              find.descendant(
                of: find.byWidget(rows[mode.index]),
                matching: find.byIcon(_icons[mode]!),
              ),
              findsOneWidget,
            );
          }
          for (final key in _labelKeys.values) {
            expect(
              key.tr(),
              isNot(key),
              reason: 'preview translations must be bundled',
            );
          }
          expect(
            LocaleKeys.cardPreview_titleAndProperties.tr(),
            'Title and row data',
          );
          final style =
              tester.widget<AppMenuSurface>(find.byType(AppMenuSurface)).style!;
          expect(
            style.brightness,
            appearance == 'dark' ? Brightness.dark : Brightness.light,
          );
          if (appearance == 'paper') {
            expect(style.surface, PaperTheme.popupBackground);
            expect(style.hover, PaperTheme.controlHover);
            expect(style.accent, PaperTheme.accent);
          }
          _expectChecked(tester, CardPreviewMode.cover);
          _expectMenuSemantics(tester, CardPreviewMode.cover);

          for (final mode in CardPreviewMode.values) {
            await tester.tap(find.text(_labelKeys[mode]!.tr()));
            await tester.pumpAndSettle();
            expect(registry.modeFor(view), mode);
            expect(store.modeFor(_viewId), mode);
            expect(find.byType(AppMenuSurface), findsNothing);
            final icon = tester
                .widget<FlowyIconButton>(find.byType(FlowyIconButton))
                .icon as Icon;
            expect(icon.icon, _icons[mode]);
            _expectButtonSemantics(tester, mode);
            await _openMenu(tester);
            _expectChecked(tester, mode);
            _expectMenuSemantics(tester, mode);
          }
          expect(store.writtenModes, CardPreviewMode.values);
          await tester.sendKeyEvent(LogicalKeyboardKey.escape);
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox.shrink());
          registry.reset();
          semantics.dispose();
        }
      });
    }

    testWidgets(
        'keyboard Home/End persist page-and-title and row data, then dismiss',
        (tester) async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.cover)});
      final registry = store.registry();
      final view = _view();
      try {
        await tester.pumpWidget(_app('paper', view, registry));
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.tab);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await tester.sendKeyEvent(LogicalKeyboardKey.home);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        expect(registry.modeFor(view), CardPreviewMode.pageAndTitle);

        await _openMenu(tester);
        await tester.sendKeyEvent(LogicalKeyboardKey.end);
        await tester.pump();
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(registry.modeFor(view), CardPreviewMode.titleAndProperties);
        expect(store.modeFor(_viewId), CardPreviewMode.titleAndProperties);

        await _openMenu(tester);
        _expectChecked(tester, CardPreviewMode.titleAndProperties);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byType(AppMenuSurface), findsNothing);
        expect(
          store.writtenModes,
          [CardPreviewMode.pageAndTitle, CardPreviewMode.titleAndProperties],
        );
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        registry.reset();
      }
    });

    testWidgets('failed menu saves roll back the button and the next checkmark',
        (tester) async {
      final store = _MemoryExtras({_viewId: _extra(CardPreviewMode.none)});
      final gate = Completer<void>();
      store.beforeWrite = (_, __) => gate.future;
      final registry = store.registry();
      final view = _view(mode: CardPreviewMode.none);
      try {
        await tester.pumpWidget(_app('paper', view, registry));
        await tester.pumpAndSettle();
        await _openMenu(tester);
        await tester.tap(find.text(LocaleKeys.gallery_facePortrait.tr()));
        await tester.pumpAndSettle();
        expect(registry.modeFor(view), CardPreviewMode.portrait);
        expect(store.writes.length, 1);

        gate.completeError(StateError('test menu save refused'));
        await tester.pumpAndSettle();
        expect(registry.modeFor(view), CardPreviewMode.none);
        expect(store.modeFor(_viewId), CardPreviewMode.none);
        await _openMenu(tester);
        _expectChecked(tester, CardPreviewMode.none);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      } finally {
        if (!gate.isCompleted) gate.complete();
        await tester.pumpWidget(const SizedBox.shrink());
        registry.reset();
      }
    });
  });
}

String _extra(CardPreviewMode mode, [String extra = '']) =>
    CardPreviewSetting(mode: mode).mergeIntoExtra(extra);

ViewPB _view({
  String id = _viewId,
  CardPreviewMode mode = CardPreviewMode.cover,
  String? extra,
}) =>
    ViewPB(id: id, layout: ViewLayoutPB.Board, extra: extra ?? _extra(mode));

class _MemoryExtras {
  _MemoryExtras(Map<String, String> values) : values = Map.of(values);

  final Map<String, String> values;
  final reads = <({String viewId, String extra})>[];
  final writes = <({String viewId, String extra})>[];
  Future<void> Function(String viewId, String extra)? beforeWrite;

  CardPreviewRegistry registry() => CardPreviewRegistry(
        readExtra: readExtra,
        writeExtra: writeExtra,
      );

  CardPreviewMode modeFor(String viewId) =>
      CardPreviewSetting.fromExtra(values[viewId] ?? '').mode;

  List<CardPreviewMode> get writtenModes => [
        for (final write in writes)
          CardPreviewSetting.fromExtra(write.extra).mode,
      ];

  Future<String> readExtra(String viewId) async {
    final extra = values[viewId] ?? '';
    reads.add((viewId: viewId, extra: extra));
    return extra;
  }

  Future<void> writeExtra(String viewId, String extra) async {
    writes.add((viewId: viewId, extra: extra));
    final before = beforeWrite;
    if (before != null) await before(viewId, extra);
    values[viewId] = extra;
  }
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(FlowyIconButton));
  await tester.pumpAndSettle();
  expect(find.byType(AppMenuSurface), findsOneWidget);
}

void _expectChecked(WidgetTester tester, CardPreviewMode mode) {
  final selected = find.byWidgetPredicate(
    (widget) => widget is AppMenuRow && widget.selected,
  );
  expect(selected, findsOneWidget);
  expect(tester.widget<AppMenuRow>(selected).label, _labelKeys[mode]!.tr());
  expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  expect(
    find.descendant(of: selected, matching: find.byIcon(Icons.check_rounded)),
    findsOneWidget,
  );
}

void _expectButtonSemantics(WidgetTester tester, CardPreviewMode mode) {
  final button = find.byWidgetPredicate(
    (widget) =>
        widget is Semantics &&
        widget.properties.label == LocaleKeys.cardPreview_tooltip.tr(),
  );
  expect(button, findsOneWidget);
  final node = tester.getSemantics(button);
  expect(node.label, LocaleKeys.cardPreview_tooltip.tr());
  expect(node.value, _labelKeys[mode]!.tr());
  expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
}

void _expectMenuSemantics(WidgetTester tester, CardPreviewMode selected) {
  for (final mode in CardPreviewMode.values) {
    final node = tester.getSemantics(find.text(_labelKeys[mode]!.tr()));
    expect(node.hasFlag(SemanticsFlag.isButton), isTrue);
    expect(node.hasFlag(SemanticsFlag.isInMutuallyExclusiveGroup), isTrue);
    expect(node.hasFlag(SemanticsFlag.isSelected), mode == selected);
    expect(node.getSemanticsData().hasAction(SemanticsAction.tap), isTrue);
  }
}

Widget _app(String appearance, ViewPB view, CardPreviewRegistry registry) =>
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: DesktopAppearance()
              .getThemeData(
                appearance == 'paper'
                    ? AppTheme.builtins.firstWhere(
                        (theme) => theme.themeName == BuiltInTheme.paper,
                      )
                    : AppTheme.fallback,
                appearance == 'dark' ? Brightness.dark : Brightness.light,
                defaultFontFamily,
                builtInCodeFontFamily,
              )
              .copyWith(platform: TargetPlatform.windows),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Center(
              child: CardPreviewButton(view: view, registry: registry),
            ),
          ),
        ),
      ),
    );
