import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/plugins/database/board/presentation/toolbar/card_preview_button.dart';
import 'package:appflowy/plugins/database/widgets/card/card.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

// Regression boundary: real response adapter -> registry -> menu and card face.
// Rust UpdateView returns Result<(), FlowyError>; the generated Dart event
// decodes the successful empty bytes as ViewPB. Do not replace that ACK with a
// populated view, or inject the already-adapted void writeExtra callback here.
// The protocol store is synthetic: no dispatch, Rust, network or workspace data.
// Real populated-document rendering, row editors and goldens remain covered by
// board_card_preview_test.dart and board_card_content_test.dart, not this file.
const _viewId = 'card-preview-switching-board';
const _appearances = ['light', 'dark', 'paper'];
const _oldModes = [CardPreviewMode.none, CardPreviewMode.cover];
const _titleKey = ValueKey('switching-card-title');
const _propertyKey = ValueKey('switching-card-due-property');
const _coverColor = Color(0xFF368F72);
const _labels = {
  CardPreviewMode.pageAndTitle: LocaleKeys.gallery_facePage,
  CardPreviewMode.cover: LocaleKeys.gallery_faceCover,
  CardPreviewMode.pageContent: LocaleKeys.gallery_faceContent,
  CardPreviewMode.none: LocaleKeys.gallery_faceNone,
  CardPreviewMode.portrait: LocaleKeys.gallery_facePortrait,
  CardPreviewMode.titleAndProperties: LocaleKeys.cardPreview_titleAndProperties,
};

typedef _SelectionSnapshot = ({String face, String checked});

late Map<String, ThemeData> _themes;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousDisableLog = Log.shared.disableLog;
  final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;

  setUpAll(() async {
    Log.shared.disableLog = true;
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    _themes = {
      for (final appearance in _appearances) appearance: _theme(appearance),
    };
    await GoogleFonts.pendingFonts();
  });

  tearDownAll(() {
    Log.shared.disableLog = previousDisableLog;
    GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
  });

  group('CardPreviewBackend protocol contracts', () {
    test('GET accepts a serialized matching view and preserves its extra',
        () async {
      final source = _view(CardPreviewMode.none);
      final protocol = _FolderProtocol(source);

      expect(await protocol.backend.readExtra(_viewId), source.extra);

      expect(protocol.readIds, [_viewId]);
      expect(protocol.readViews.single, isNot(same(source)));
      expect(
        protocol.readViews.single.writeToBuffer(),
        orderedEquals(source.writeToBuffer()),
      );
      expect(protocol.writes, isEmpty);
    });

    test('successful empty update ACK completes writeExtra without throwing',
        () async {
      final protocol = _FolderProtocol(_view(CardPreviewMode.none));
      final extra = const CardPreviewSetting(
        mode: CardPreviewMode.pageAndTitle,
      ).mergeIntoExtra(protocol.reopen().extra);
      Object? adapterError;
      try {
        await protocol.backend.writeExtra(_viewId, extra);
      } on Object catch (error) {
        adapterError = error;
      }

      expect(protocol.reopen().extra, extra, reason: 'persistence succeeded');
      expect(protocol.acknowledgements.single.id, isEmpty);
      expect(protocol.acknowledgements.single.writeToBuffer(), isEmpty);
      expect(protocol.readIds, isEmpty, reason: 'an ACK needs no extra GET');
      expect(
        adapterError,
        isNull,
        reason: 'UpdateView succeeded; its unit ACK never promised a ViewPB ID',
      );
    });

    test('wrong or absent GET view ID is rejected without writing', () async {
      for (final wrongId in ['different-board', '']) {
        final protocol = _FolderProtocol(_view(CardPreviewMode.none))
          ..returnedReadId = wrongId;
        final registry = CardPreviewRegistry(backend: protocol.backend);
        final view = _view(CardPreviewMode.cover);
        final notifications = _record(registry, view);
        final save = registry.set(view, CardPreviewMode.pageAndTitle);
        try {
          expect(registry.modeFor(view), CardPreviewMode.pageAndTitle);
          await save;
          expect(protocol.readIds, [_viewId]);
          expect(protocol.readViews.single.id, wrongId);
          expect(protocol.writes, isEmpty);
          expect(protocol.storedMode, CardPreviewMode.none);
          expect(registry.modeFor(view), CardPreviewMode.cover);
          expect(
            notifications,
            [CardPreviewMode.pageAndTitle, CardPreviewMode.cover],
          );
        } finally {
          await _finish(registry, protocol, [save]);
        }
      }
    });
  });

  group('registry through the real response adapter', () {
    for (final delayed in [false, true]) {
      for (final choice in CardPreviewMode.values) {
        test(
          '${delayed ? 'delayed' : 'fast'} ACK: none/cover -> ${choice.id} '
          'stays selected after settlement',
          () async {
            final observed = <String, Object?>{};
            // Both legacy starts are independent. Including a same-mode save
            // also checks idempotence; the other start always changes mode.
            for (final oldMode in _oldModes) {
              final protocol = _FolderProtocol(_view(oldMode));
              final readGate = delayed ? protocol.holdRead(0) : null;
              final ackGate = delayed ? protocol.holdAck(0) : null;
              final registry = CardPreviewRegistry(backend: protocol.backend);
              final view = _view(oldMode, metadata: 'stale');
              final before = view.writeToBuffer();
              final notifier = registry.notifierFor(view);
              final notifications = _record(registry, view);
              var settled = false;
              final save = registry.set(view, choice).whenComplete(() {
                settled = true;
              });
              try {
                expect(
                  notifier.value,
                  choice,
                  reason: 'optimistic immediately',
                );
                if (delayed) {
                  await _turn();
                  expect(protocol.readIds, [_viewId]);
                  expect(protocol.writes, isEmpty);
                  expect(settled, isFalse);
                  expect(notifier.value, choice);
                  readGate!.complete();
                  await _turn();
                  expect(protocol.writes, hasLength(1));
                  expect(protocol.storedMode, choice);
                  expect(protocol.acknowledgements, isEmpty);
                  expect(notifier.value, choice, reason: 'saved but not ACKed');
                  expect(settled, isFalse);
                  ackGate!.complete();
                }
                await save;
                expect(settled, isTrue);
                expect(protocol.storedMode, choice);
                expect(protocol.writtenModes, [choice]);
                expect(protocol.acknowledgements.single.id, isEmpty);
                expect(
                  protocol.readIds,
                  [_viewId],
                  reason: 'no second bad GET',
                );
                expect(jsonDecode(protocol.reopen().extra)['unrelated'], {
                  'keep': [1, 'fresh', null, true],
                });
                expect(view.writeToBuffer(), orderedEquals(before));
                observed[oldMode.id] = {
                  'visible': notifier.value.id,
                  'notifications':
                      notifications.map((mode) => mode.id).toList(),
                };
              } finally {
                await _finish(registry, protocol, [save]);
              }
            }
            expect(
              observed,
              {
                for (final oldMode in _oldModes)
                  oldMode.id: {
                    'visible': choice.id,
                    'notifications': [if (oldMode != choice) choice.id],
                  },
              },
              reason: 'both stores contain ${choice.id}; successful empty ACKs '
                  'must not roll back to their pre-save none/cover modes',
            );
          },
        );
      }
    }

    test('rapid queued choices serialize; older ACKs never flicker the last',
        () async {
      final protocol = _FolderProtocol(_view(CardPreviewMode.none));
      final choices = CardPreviewMode.values;
      final gates = [
        for (var i = 0; i < choices.length; i++) protocol.holdAck(i),
      ];
      final registry = CardPreviewRegistry(backend: protocol.backend);
      final view = _view(CardPreviewMode.none);
      final notifications = _record(registry, view);
      final saves = [for (final choice in choices) registry.set(view, choice)];
      try {
        expect(registry.modeFor(view), choices.last);
        expect(notifications, choices);
        for (var i = 0; i < choices.length; i++) {
          await _turn();
          expect(protocol.readIds, hasLength(i + 1));
          expect(protocol.writes, hasLength(i + 1));
          expect(protocol.activeUpdates, 1);
          expect(protocol.maxActiveUpdates, 1);
          expect(
            CardPreviewSetting.fromExtra(protocol.readViews[i].extra).mode,
            i == 0 ? CardPreviewMode.none : choices[i - 1],
          );
          expect(protocol.storedMode, choices[i]);
          gates[i].complete();
          await saves[i];
          if (i < choices.length - 1) {
            expect(registry.modeFor(view), choices.last);
            expect(notifications, choices, reason: 'no older-ACK flicker');
          }
        }
        expect(protocol.writtenModes, choices);
        expect(protocol.storedMode, choices.last);
        expect(protocol.readIds, hasLength(choices.length));
        expect(
          protocol.acknowledgements.map((ack) => ack.id),
          everyElement(''),
        );
        expect(protocol.events, [
          for (var i = 0; i < choices.length; i++) ...[
            'GET:$i',
            'UPDATE:$i',
            'ACK:$i',
          ],
        ]);
        expect(
          registry.modeFor(view),
          choices.last,
          reason:
              'the final successful ACK must not restore the penultimate mode',
        );
        expect(notifications, choices);
      } finally {
        await _finish(registry, protocol, saves);
      }
    });

    for (final operation in ['GET', 'UPDATE']) {
      test(
          '$operation Result.failure rolls back correctly and a retry recovers',
          () async {
        final protocol = _FolderProtocol(_view(CardPreviewMode.none));
        (operation == 'GET' ? protocol.failReads : protocol.failUpdates).add(0);
        final registry = CardPreviewRegistry(backend: protocol.backend);
        final view = _view(CardPreviewMode.cover, metadata: 'stale');
        final notifications = _record(registry, view);
        final saves = <Future<void>>[];
        try {
          final failed = registry.set(view, CardPreviewMode.portrait);
          saves.add(failed);
          expect(registry.modeFor(view), CardPreviewMode.portrait);
          await failed;
          final rollback =
              operation == 'GET' ? CardPreviewMode.cover : CardPreviewMode.none;
          expect(registry.modeFor(view), rollback);
          expect(notifications, [CardPreviewMode.portrait, rollback]);
          expect(protocol.storedMode, CardPreviewMode.none);
          expect(protocol.returnedFailures, [operation]);
          expect(protocol.writes, hasLength(operation == 'GET' ? 0 : 1));

          final retry = registry.set(view, CardPreviewMode.pageContent);
          saves.add(retry);
          await retry;
          expect(protocol.readIds, hasLength(2));
          expect(protocol.acknowledgements.single.id, isEmpty);
          expect(protocol.storedMode, CardPreviewMode.pageContent);
          expect(
            registry.modeFor(view),
            CardPreviewMode.pageContent,
            reason: 'a genuine result failure must not poison a later unit ACK',
          );
          expect(notifications, [
            CardPreviewMode.portrait,
            rollback,
            CardPreviewMode.pageContent,
          ]);
        } finally {
          await _finish(registry, protocol, saves);
        }
      });
    }

    test('older GET/UPDATE failures cannot roll back a newer queued choice',
        () async {
      final observed = <String, Object?>{};
      for (final operation in ['GET', 'UPDATE']) {
        final protocol = _FolderProtocol(_view(CardPreviewMode.none));
        (operation == 'GET' ? protocol.failReads : protocol.failUpdates).add(0);
        final failureGate =
            operation == 'GET' ? protocol.holdRead(0) : protocol.holdAck(0);
        final successGate = protocol.holdAck(operation == 'GET' ? 0 : 1);
        final registry = CardPreviewRegistry(backend: protocol.backend);
        final view = _view(CardPreviewMode.none);
        final notifications = _record(registry, view);
        final saves = <Future<void>>[];
        try {
          final earlier = registry.set(view, CardPreviewMode.pageAndTitle);
          saves.add(earlier);
          await _turn();
          final latest = registry.set(view, CardPreviewMode.portrait);
          saves.add(latest);
          failureGate.complete();
          await earlier;
          await _turn();
          expect(protocol.returnedFailures, [operation]);
          expect(protocol.storedMode, CardPreviewMode.portrait);
          expect(protocol.acknowledgements, isEmpty);
          expect(registry.modeFor(view), CardPreviewMode.portrait);
          expect(
            notifications,
            [CardPreviewMode.pageAndTitle, CardPreviewMode.portrait],
            reason: 'a failure belonging to an older revision cannot flicker',
          );
          successGate.complete();
          await latest;
          expect(protocol.readIds, hasLength(2));
          expect(protocol.acknowledgements.single.id, isEmpty);
          expect(protocol.maxActiveUpdates, 1);
          observed[operation] = {
            'visible': registry.modeFor(view).id,
            'notifications': notifications.map((mode) => mode.id).toList(),
          };
        } finally {
          await _finish(registry, protocol, saves);
        }
      }
      expect(observed, {
        for (final operation in ['GET', 'UPDATE'])
          operation: {
            'visible': 'portrait',
            'notifications': ['page_title', 'portrait'],
          },
      });
    });

    test('latest update failure restores the preceding persisted queued choice',
        () async {
      final protocol = _FolderProtocol(_view(CardPreviewMode.none))
        ..failUpdates.add(1);
      final gate = protocol.holdAck(0);
      final registry = CardPreviewRegistry(backend: protocol.backend);
      final view = _view(CardPreviewMode.none);
      final notifications = _record(registry, view);
      final saves = <Future<void>>[];
      try {
        saves.add(registry.set(view, CardPreviewMode.pageContent));
        await _turn();
        expect(protocol.storedMode, CardPreviewMode.pageContent);
        saves.add(registry.set(view, CardPreviewMode.portrait));
        expect(registry.modeFor(view), CardPreviewMode.portrait);
        gate.complete();
        await Future.wait(saves);

        expect(protocol.readIds, hasLength(2));
        expect(protocol.writtenModes, [
          CardPreviewMode.pageContent,
          CardPreviewMode.portrait,
        ]);
        expect(protocol.acknowledgements.single.id, isEmpty);
        expect(protocol.returnedFailures, ['UPDATE']);
        expect(protocol.storedMode, CardPreviewMode.pageContent);
        expect(registry.modeFor(view), CardPreviewMode.pageContent);
        expect(notifications, [
          CardPreviewMode.pageContent,
          CardPreviewMode.portrait,
          CardPreviewMode.pageContent,
        ]);
      } finally {
        await _finish(registry, protocol, saves);
      }
    });
  });

  group('real menu and physical card face', () {
    for (final appearance in _appearances) {
      for (final delayed in [false, true]) {
        testWidgets(
          '$appearance / ${delayed ? 'delayed' : 'fast'} ACK: all '
          '${CardPreviewMode.values.length} mouse choices survive settlement, '
          'same-ID rebuild and persisted reopen',
          (tester) async {
            final initial =
                delayed ? CardPreviewMode.cover : CardPreviewMode.none;
            final original = _view(initial, metadata: 'stale');
            final beforeView = original.writeToBuffer();
            final row = _row();
            final beforeRow = row.writeToBuffer();
            final protocol = _FolderProtocol(_view(initial));
            final gates = [
              if (delayed)
                for (var i = 0; i < CardPreviewMode.values.length; i++)
                  protocol.holdAck(i),
            ];
            final registry = CardPreviewRegistry(backend: protocol.backend);
            final notifier = registry.notifierFor(original);
            final notifications = _record(registry, original);
            final observed = <String, _SelectionSnapshot>{};
            final expected = <String, _SelectionSnapshot>{};
            var view = original;
            try {
              await _pump(tester, appearance, view, registry, row);
              await _openMenu(tester);
              expect(_capture(tester, appearance), _selected(initial));

              for (final choice in CardPreviewMode.values) {
                await _clickChoice(tester, choice);
                expect(protocol.writes, hasLength(choice.index + 1));
                expect(protocol.storedMode, choice);
                if (delayed) {
                  expect(protocol.acknowledgements, hasLength(choice.index));
                  await _openMenu(tester);
                  expect(_capture(tester, appearance), _selected(choice));
                  await _closeMenu(tester);
                  view = _decode(original);
                  await _pump(tester, appearance, view, registry, row);
                  expect(registry.notifierFor(view), same(notifier));
                  await _openMenu(tester);
                  expect(
                    _capture(tester, appearance),
                    _selected(choice),
                    reason:
                        'fresh same-ID snapshots cannot erase a pending choice',
                  );
                  await _closeMenu(tester);
                  gates[choice.index].complete();
                  await _settle(tester);
                }
                expect(protocol.acknowledgements, hasLength(choice.index + 1));
                expect(protocol.readIds, hasLength(choice.index + 1));
                await _openMenu(tester);
                observed['${choice.id}: ACK'] = _capture(tester, appearance);
                expected['${choice.id}: ACK'] = _selected(choice);

                await _closeMenu(tester);
                view = _decode(original);
                expect(view, isNot(same(original)));
                await _pump(tester, appearance, view, registry, row);
                expect(registry.notifierFor(view), same(notifier));
                await _openMenu(tester);
                observed['${choice.id}: rebuild'] =
                    _capture(tester, appearance);
                expected['${choice.id}: rebuild'] = _selected(choice);
              }

              // Collect before asserting the ACK results so even a RED run
              // exercises every face and the reset/reopen path. No expected
              // state is read from the faulty notifier or adjusted to match it.
              await _closeMenu(tester);
              observed['persisted reopen'] = await _resetAndReopen(
                tester,
                appearance,
                registry,
                protocol,
                row,
              );
              expected['persisted reopen'] =
                  _selected(CardPreviewMode.values.last);
              expect(protocol.writtenModes, CardPreviewMode.values);
              expect(
                protocol.readIds,
                hasLength(CardPreviewMode.values.length),
                reason: 'no hidden rereads',
              );
              expect(
                protocol.acknowledgements.map((ack) => ack.id),
                everyElement(''),
              );
              expect(protocol.returnedFailures, isEmpty);
              expect(original.writeToBuffer(), orderedEquals(beforeView));
              expect(row.writeToBuffer(), orderedEquals(beforeRow));
              expect(tester.takeException(), isNull);
              expect(
                observed,
                expected,
                reason: 'each empty successful ACK must preserve BOTH the '
                    'physical face key and the reopened menu checkmark',
              );
              expect(notifications, CardPreviewMode.values);
            } finally {
              await _disposeWidgets(tester, registry, protocol);
            }
          },
        );
      }
    }

    testWidgets(
      'paper: keyboard choices queue behind an ACK while menus reopen and views rebuild',
      (tester) async {
        final protocol = _FolderProtocol(_view(CardPreviewMode.none));
        final gates = [for (var i = 0; i < 3; i++) protocol.holdAck(i)];
        final registry = CardPreviewRegistry(backend: protocol.backend);
        final original = _view(CardPreviewMode.none);
        final notifier = registry.notifierFor(original);
        final notifications = _record(registry, original);
        final row = _row();
        final observed = <String, _SelectionSnapshot>{};
        const choices = [
          CardPreviewMode.pageAndTitle,
          CardPreviewMode.portrait,
          CardPreviewMode.pageContent,
        ];
        try {
          await _pump(tester, 'paper', original, registry, row);
          await tester.sendKeyEvent(LogicalKeyboardKey.tab);
          await tester.pump();
          await tester.pump();
          await tester.sendKeyEvent(LogicalKeyboardKey.enter);
          await _settle(tester);
          expect(_capture(tester, 'paper'), _selected(CardPreviewMode.none));

          await _keys(
            tester,
            [LogicalKeyboardKey.home, LogicalKeyboardKey.enter],
          );
          expect(protocol.writes, hasLength(1));
          await _openMenu(tester);
          expect(_capture(tester, 'paper'), _selected(choices[0]));
          // Keep the legacy full-cover choice: row data now follows it.
          await _keys(tester, [
            LogicalKeyboardKey.end,
            LogicalKeyboardKey.arrowUp,
            LogicalKeyboardKey.space,
          ]);
          await _openMenu(tester);
          expect(_capture(tester, 'paper'), _selected(choices[1]));

          final fresh = _decode(original);
          await _pump(tester, 'paper', fresh, registry, row);
          expect(registry.notifierFor(fresh), same(notifier));
          expect(_capture(tester, 'paper'), _selected(choices[1]));
          await _keys(tester, [
            LogicalKeyboardKey.home,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.arrowDown,
            LogicalKeyboardKey.enter,
          ]);
          await _openMenu(tester);
          expect(_capture(tester, 'paper'), _selected(choices.last));
          expect(protocol.readIds, hasLength(1));
          expect(protocol.writes, hasLength(1));
          expect(protocol.acknowledgements, isEmpty);
          expect(notifications, choices);

          for (var i = 0; i < gates.length; i++) {
            await _closeMenu(tester);
            gates[i].complete();
            await _settle(tester);
            expect(protocol.acknowledgements, hasLength(i + 1));
            expect(protocol.readIds, hasLength(i < 2 ? i + 2 : 3));
            expect(protocol.writes, hasLength(i < 2 ? i + 2 : 3));
            if (i < gates.length - 1) {
              expect(notifications, choices, reason: 'no older-ACK flicker');
              expect(notifier.value, choices.last);
            }
            await _openMenu(tester);
            observed['ACK:$i'] = _capture(tester, 'paper');
          }
          expect(protocol.writtenModes, choices);
          expect(protocol.storedMode, choices.last);
          expect(protocol.maxActiveUpdates, 1);
          await _closeMenu(tester);
          observed['persisted reopen'] = await _resetAndReopen(
            tester,
            'paper',
            registry,
            protocol,
            row,
          );
          expect(protocol.readIds, hasLength(3));
          expect(tester.takeException(), isNull);
          expect(
            observed,
            {
              for (var i = 0; i < gates.length; i++)
                'ACK:$i': _selected(choices.last),
              'persisted reopen': _selected(choices.last),
            },
            reason:
                'the last keyboard choice wins, including after its own ACK',
          );
          expect(notifications, choices);
        } finally {
          await _disposeWidgets(tester, registry, protocol);
        }
      },
    );
  });
}

ViewPB _view(CardPreviewMode mode, {String metadata = 'fresh'}) => ViewPB(
      id: _viewId,
      name: 'Synthetic preview board',
      layout: ViewLayoutPB.Board,
      extra: jsonEncode({
        'unrelated': {
          'keep': [1, metadata, null, true],
        },
        CardPreviewSetting.envelopeKey: {'version': 1, 'mode': mode.id},
      }),
    );

ViewPB _decode(ViewPB view) => ViewPB.fromBuffer(view.writeToBuffer());

RowMetaPB _row() => RowMetaPB(
      id: 'card-preview-switching-row',
      documentId: '',
      isDocumentEmpty: true,
      cover: RowCoverPB(
        coverType: CoverTypePB.ColorCover,
        data: '0xFF368F72',
      ),
    );

List<CardPreviewMode> _record(CardPreviewRegistry registry, ViewPB view) {
  final notifications = <CardPreviewMode>[];
  final notifier = registry.notifierFor(view);
  notifier.addListener(() => notifications.add(notifier.value));
  return notifications;
}

// Only plain tests use a real event-loop turn. Widget tests flush microtasks
// with tester.pump instead, never await a blocked Completer or real-clock timer.
Future<void> _turn() => Future<void>.delayed(Duration.zero);

Future<void> _finish(
  CardPreviewRegistry registry,
  _FolderProtocol protocol,
  List<Future<void>> saves,
) async {
  protocol.releaseAll();
  await Future.wait(saves);
  registry.reset();
}

class _FolderProtocol {
  _FolderProtocol(ViewPB stored) : _storedBytes = stored.writeToBuffer();

  List<int> _storedBytes;
  final readIds = <String>[];
  final readViews = <ViewPB>[];
  final writes = <String>[];
  final acknowledgements = <ViewPB>[];
  final returnedFailures = <String>[];
  final events = <String>[];
  final failReads = <int>{};
  final failUpdates = <int>{};
  final _readGates = <int, Completer<void>>{};
  final _ackGates = <int, Completer<void>>{};
  String? returnedReadId;
  int activeUpdates = 0;
  int maxActiveUpdates = 0;

  CardPreviewBackend get backend => CardPreviewBackend(
        readView: readView,
        updateView: updateView,
      );

  ViewPB reopen() => ViewPB.fromBuffer(_storedBytes);

  CardPreviewMode get storedMode =>
      CardPreviewSetting.fromExtra(reopen().extra).mode;

  List<CardPreviewMode> get writtenModes => [
        for (final extra in writes) CardPreviewSetting.fromExtra(extra).mode,
      ];

  Completer<void> holdRead(int index) =>
      _readGates.putIfAbsent(index, Completer<void>.new);

  Completer<void> holdAck(int index) =>
      _ackGates.putIfAbsent(index, Completer<void>.new);

  Future<FlowyResult<ViewPB, FlowyError>> readView(String id) async {
    // These callbacks also run inside guarded widget taps/pumps. Using expect
    // here would throw a test guard error that the registry catches as a read
    // failure, hiding the response-adapter regression we actually want to test.
    expectSync(id, _viewId);
    final index = readIds.length;
    readIds.add(id);
    events.add('GET:$index');
    final gate = _readGates[index];
    if (gate != null) await gate.future;
    if (failReads.contains(index)) return _failure('GET');

    final stored = reopen();
    if (returnedReadId != null) stored.id = returnedReadId!;
    final decoded = ViewPB.fromBuffer(stored.writeToBuffer());
    readViews.add(decoded);
    return FlowyResult.success(decoded);
  }

  Future<FlowyResult<ViewPB, FlowyError>> updateView(
    String id,
    String extra,
  ) async {
    expectSync(id, _viewId);
    final index = writes.length;
    writes.add(extra);
    events.add('UPDATE:$index');
    activeUpdates++;
    if (activeUpdates > maxActiveUpdates) maxActiveUpdates = activeUpdates;
    try {
      final refused = failUpdates.contains(index);
      if (!refused) {
        // Persist FIRST, before delivering either a fast or manually gated ACK.
        // The caller's merged extra is stored verbatim through actual PB bytes.
        final updated = reopen()..extra = extra;
        _storedBytes = updated.writeToBuffer();
      }
      final gate = _ackGates[index];
      if (gate != null) await gate.future;
      if (refused) return _failure('UPDATE');

      // Mirrors FolderEventUpdateView.send's decoder for Rust's Ok(()).
      final ack = ViewPB.fromBuffer(const <int>[]);
      acknowledgements.add(ack);
      events.add('ACK:$index');
      return FlowyResult.success(ack);
    } finally {
      activeUpdates--;
    }
  }

  FlowyResult<ViewPB, FlowyError> _failure(String operation) {
    returnedFailures.add(operation);
    return FlowyResult.failure(
      FlowyError.fromBuffer(
        FlowyError(msg: 'Synthetic $operation refusal').writeToBuffer(),
      ),
    );
  }

  void releaseAll() {
    // Gates are registered before dispatch, including not-yet-started queued
    // calls. Release every one even if an assertion failed halfway through.
    for (final gate in [..._readGates.values, ..._ackGates.values]) {
      if (!gate.isCompleted) gate.complete();
    }
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpAndSettle(
    const Duration(milliseconds: 100),
    EnginePhase.sendSemanticsUpdate,
    const Duration(seconds: 5),
  );
}

Future<void> _pump(
  WidgetTester tester,
  String appearance,
  ViewPB view,
  CardPreviewRegistry registry,
  RowMetaPB row,
) async {
  await tester.pumpWidget(_app(appearance, view, registry, row));
  await _settle(tester);
}

Future<void> _openMenu(WidgetTester tester) async {
  await tester.tap(find.byType(FlowyIconButton), kind: PointerDeviceKind.mouse);
  await _settle(tester);
  expect(find.byType(AppMenuSurface), findsOneWidget);
}

Future<void> _closeMenu(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await _settle(tester);
  expect(find.byType(AppMenuSurface), findsNothing);
}

Future<void> _clickChoice(WidgetTester tester, CardPreviewMode choice) async {
  await tester.tap(
    find.descendant(
      of: find.byType(AppMenuSurface),
      matching: find.text(_labels[choice]!.tr()),
    ),
    kind: PointerDeviceKind.mouse,
  );
  await _settle(tester);
  expect(find.byType(AppMenuSurface), findsNothing);
}

Future<void> _keys(WidgetTester tester, List<LogicalKeyboardKey> keys) async {
  for (final key in keys) {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }
  await _settle(tester);
  expect(find.byType(AppMenuSurface), findsNothing);
}

Future<_SelectionSnapshot> _resetAndReopen(
  WidgetTester tester,
  String appearance,
  CardPreviewRegistry registry,
  _FolderProtocol protocol,
  RowMetaPB row,
) async {
  final fresh = protocol.reopen();
  final previous = registry.notifierFor(fresh);
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
  registry.reset();
  expect(registry.notifierFor(fresh), isNot(same(previous)));
  await _pump(tester, appearance, fresh, registry, row);
  await _openMenu(tester);
  return _capture(tester, appearance);
}

Future<void> _disposeWidgets(
  WidgetTester tester,
  CardPreviewRegistry registry,
  _FolderProtocol protocol,
) async {
  protocol.releaseAll();
  // The real menu discards the set() future. Pumping after releasing all gates
  // drains that queue before disposing its notifier, including on a RED exit.
  await _settle(tester);
  await tester.pumpWidget(const SizedBox.shrink());
  await _settle(tester);
  registry.reset();
}

_SelectionSnapshot _selected(CardPreviewMode mode) => (
      face: 'row-card-face-${mode.id}',
      checked: _labels[mode]!.tr(),
    );

_SelectionSnapshot _capture(WidgetTester tester, String appearance) {
  final faces = [
    for (final mode in CardPreviewMode.values)
      if (find
          .byKey(ValueKey('row-card-face-${mode.id}'))
          .evaluate()
          .isNotEmpty)
        mode,
  ];
  expect(faces, hasLength(1), reason: 'exactly one actual production face');
  final mode = faces.single;
  final face = find.byKey(ValueKey('row-card-face-${mode.id}'));
  expect(face, findsOneWidget);
  expect(tester.widget<ClipRRect>(face).borderRadius, BorderRadius.circular(4));
  expect(tester.getSize(face).width, 232);
  expect(tester.getSize(face).height, greaterThan(0));
  expect(
    tester.widget<RowCardPreviewLayout>(find.byType(RowCardPreviewLayout)).mode,
    mode,
  );
  final page = mode == CardPreviewMode.pageAndTitle ||
      mode == CardPreviewMode.pageContent;
  final cover =
      mode == CardPreviewMode.cover || mode == CardPreviewMode.portrait;
  final rowData = mode == CardPreviewMode.titleAndProperties;
  expect(find.byType(RowPagePreview), page ? findsOneWidget : findsNothing);
  expect(find.byType(CardCover), cover ? findsOneWidget : findsNothing);
  expect(
    find.byKey(_titleKey),
    mode == CardPreviewMode.pageContent ? findsNothing : findsOneWidget,
  );
  expect(
    find.byKey(_propertyKey, skipOffstage: false),
    rowData ? findsOneWidget : findsNothing,
    reason: 'only the row-data face mounts the supplied row property',
  );
  expect(
    find.descendant(of: face, matching: find.text('Due: Tomorrow')),
    rowData ? findsOneWidget : findsNothing,
  );
  if (rowData) {
    expect(
      find.byKey(const ValueKey('row-card-face-title_properties')),
      findsOneWidget,
    );
  }
  if (page) {
    expect(
      tester.widget<RowPagePreview>(find.byType(RowPagePreview)).documentId,
      isEmpty,
    );
    expect(find.text(LocaleKeys.cardPreview_pageEmpty.tr()), findsOneWidget);
  }
  if (cover) {
    expect(
      find.descendant(
        of: find.byType(CardCover),
        matching: find.byWidgetPredicate(
          (widget) => widget is ColoredBox && widget.color == _coverColor,
        ),
      ),
      findsOneWidget,
    );
  }
  expect(find.byType(Image), findsNothing);

  final rows = tester.widgetList<AppMenuRow>(find.byType(AppMenuRow)).toList();
  expect(
    rows.map((row) => row.label),
    _labels.values.map((label) => label.tr()),
  );
  for (final label in _labels.values) {
    expect(label.tr(), isNot(label), reason: 'real bundled translations');
  }
  expect(
    LocaleKeys.cardPreview_titleAndProperties.tr(),
    'Title and row data',
  );
  final checked = rows.where((row) => row.selected).toList();
  expect(checked, hasLength(1));
  expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  expect(
    find.descendant(
      of: find.byWidget(checked.single),
      matching: find.byIcon(Icons.check_rounded),
    ),
    findsOneWidget,
  );
  final style =
      tester.widget<AppMenuSurface>(find.byType(AppMenuSurface)).style!;
  expect(
    style.brightness,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
  );
  expect(
    PaperTheme.isEnabled(tester.element(find.byType(CardPreviewButton))),
    appearance == 'paper',
  );
  if (appearance == 'paper') {
    expect(style.surface, PaperTheme.popupBackground);
    expect(style.hover, PaperTheme.controlHover);
    expect(style.accent, PaperTheme.accent);
  }
  return (face: 'row-card-face-${mode.id}', checked: checked.single.label);
}

ThemeData _theme(String appearance) => DesktopAppearance()
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
    .copyWith(platform: TargetPlatform.windows);

Widget _app(
  String appearance,
  ViewPB view,
  CardPreviewRegistry registry,
  RowMetaPB row,
) =>
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
          theme: _themes[appearance],
          themeAnimationDuration: Duration.zero,
          home: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: SizedBox(
                  width: 232,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      CardPreviewButton(view: view, registry: registry),
                      const SizedBox(height: 24),
                      ValueListenableBuilder<CardPreviewMode>(
                        valueListenable: registry.notifierFor(view),
                        builder: (context, mode, _) => RowCardPreviewLayout(
                          rowMeta: row,
                          mode: mode,
                          titleBuilder: (context, foreground) => Text(
                            'Preview switching',
                            key: _titleKey,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium!
                                .copyWith(
                                  color: foreground,
                                ),
                          ),
                          properties: const [
                            Text('Due: Tomorrow', key: _propertyKey),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
