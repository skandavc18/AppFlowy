import 'package:appflowy/plugins/database/application/card_preview.dart';
import 'package:appflowy/plugins/database/application/cell/cell_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_controller.dart';
import 'package:appflowy/plugins/database/application/field/field_info.dart';
import 'package:appflowy/plugins/database/application/row/row_cache.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/widgets/card/card.dart';
import 'package:appflowy/plugins/database/widgets/card/card_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_builder.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_skeleton/text_card_cell.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_style_maps/desktop_board_card_cell_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

// Integration boundary: real RowCardContent, its PRIVATE _CardContentCell and
// title GlobalKey, real EditableCardNotifier, CardBloc and preview composition.
// Only FieldController, RowController and CardCellBuilder's leaves are fake.
// This does NOT exercise RowCard's outer shell, TextCardCell/TextCellBloc,
// persistence, Rust/FFI, a live database, network covers or document loading.
// Empty document IDs and color-only covers keep every preview mode offline.
const _appearances = ['light', 'dark', 'paper'];
const _primary = 'primary';
const _before = 'property-before';
const _after = 'property-after';
const _hidden = 'hidden';
const _unset = 'unset-visibility';
const _grouped = 'grouped';
const _unknown = 'unknown-field';
const _sourceFieldIds = [
  _before,
  _primary,
  _after,
  _hidden,
  _unset,
  _grouped,
  _unknown,
];
const _draft = TextEditingValue(
  text: 'An unsaved title still being composed',
  selection: TextSelection(baseOffset: 3, extentOffset: 14),
  composing: TextRange(start: 3, end: 14),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final previousFontFetching = GoogleFonts.config.allowRuntimeFetching;

  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
  });

  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = previousFontFetching;
  });

  testWidgets(
    'real CardBloc initializes the injected fake and filters field visibility',
    (tester) async {
      final card = _CardFixture();
      try {
        // CardBloc has already called the fake's virtual initialize, not a
        // production RowController constructor or a skip-initialize seam.
        expect(card.row.initializeCalls, 1);
        expect(card.row.loadCalls, 1);
        await _pump(tester, [card]);
        expect(card.row.listenerRegistrations, 1);
        expect(card.bloc.runtimeType, CardBloc);
        expect(
          card.bloc.state.cells.map((cell) => cell.fieldId),
          [_before, _primary, _after],
        );
        expect(card.bloc.state.cells.first.fieldType, FieldType.RichText);
        expect(card.fields.getField(_before)!.isPrimary, isFalse);
        expect(card.fields.getField(_primary)!.isPrimary, isTrue);
        expect(
          card.fields.getField(_after)!.visibility,
          FieldVisibility.HideWhenEmpty,
        );
        expect(card.fields.getField(_unset)!.visibility, isNull);
        expect(card.row.fieldIds, _sourceFieldIds);
        _expectComposition(tester, card, 'light');
        final probe = _probe(tester, card);

        // Notifications go through CardBloc.initial's actual row listener and
        // _makeCells again; no fabricated CardState is emitted by the harness.
        final before = card.fields.fields[_before]!;
        card.fields.fields[_before] = before.copyWith(
          fieldSettings: FieldSettingsPB(
            fieldId: _before,
            visibility: FieldVisibility.AlwaysHidden,
          ),
        );
        card.row.notifyCellsChanged();
        await _frames(tester);
        expect(
          card.bloc.state.cells.map((cell) => cell.fieldId),
          [_primary, _after],
        );
        expect(_property(card.id, _before), findsNothing);
        expect(_titleState(tester, card), same(probe.leafState));
        expect(card.builder.lastFor(_primary).notifier, same(probe.notifier));

        card.fields.fields[_before] = before;
        card.row.notifyCellsChanged();
        await _frames(tester);
        expect(
          card.bloc.state.cells.map((cell) => cell.fieldId),
          [_before, _primary, _after],
        );
        expect(
          card.bloc.state.changeReason,
          const ChangedReason.fieldDidChange(),
        );
        expect(card.row.fieldIds, _sourceFieldIds);
        expect(_titleState(tester, card), same(probe.leafState));
        _expectComposition(tester, card, 'light');
        _expectNotifierContract(card);
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, [card]);
      }
    },
  );

  testWidgets(
    'Calendar-style defaults keep cover properties in their original order '
    'without giving a nonprimary rich-text field the title notifier',
    (tester) async {
      final card = _CardFixture(isCalendar: true);
      final originalRow = card.row.rowMeta.writeToBuffer();
      try {
        await _pump(tester, [card]);
        final style =
            tester.widget<RowCardContent>(_body(card.id)).styleConfiguration;
        // This host deliberately omits showProperties and preview, as a
        // non-board caller does. Only board hosts opt out of the field stack.
        expect(style.showProperties, isTrue);
        expect(style.preview, CardPreviewMode.cover);
        expect(
          card.bloc.state.cells.map((cell) => cell.fieldId),
          [_before, _primary, _after],
        );
        _expectComposition(tester, card, 'light');
        expect(
          tester.getTopLeft(_title(card.id)).dy,
          lessThan(tester.getTopLeft(_property(card.id, _before)).dy),
        );
        expect(
          tester.getTopLeft(_property(card.id, _before)).dy,
          lessThan(tester.getTopLeft(_property(card.id, _after)).dy),
        );
        expect(
          card.builder.calls.map((call) => call.cell.fieldId).toSet(),
          {_primary, _before, _after},
        );
        _expectNotifierContract(card);
        expect(card.row.fieldIds, _sourceFieldIds);
        expect(card.row.rowMeta.writeToBuffer(), orderedEquals(originalRow));
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, [card]);
      }
    },
  );

  for (final appearance in _appearances) {
    for (final isCompact in [false, true]) {
      testWidgets(
        '$appearance / ${isCompact ? 'compact' : 'regular'}: idle mode '
        'changes never edit the title; page-only excludes its retained '
        'editor from layout, focus, hit-testing and semantics',
        (tester) async {
          final card = _CardFixture(isCompact: isCompact);
          card.mode.value = CardPreviewMode.pageContent;
          final originalRow = card.row.rowMeta.writeToBuffer();
          final semantics = tester.ensureSemantics();
          try {
            await _pump(tester, [card], appearance: appearance);
            final probe = _probe(tester, card);
            final initialValue = probe.controller.value;
            expect(probe.leafState.initialIsEditing, isFalse);

            for (final mode in [
              CardPreviewMode.pageContent,
              ...CardPreviewMode.values,
              ...CardPreviewMode.values.reversed,
              CardPreviewMode.pageContent,
            ]) {
              card.mode.value = mode;
              await _frames(tester);
              _expectRetained(
                tester,
                card,
                probe,
                initialValue,
                focused: false,
                dirty: false,
              );
              _expectComposition(tester, card, appearance);
              if (mode == CardPreviewMode.pageContent) {
                _expectPageOnlyClosed(tester, card);
                probe.focus.requestFocus();
                await _frames(tester);
                _expectPageOnlyClosed(tester, card);
                await tester.sendKeyEvent(LogicalKeyboardKey.tab);
                await _frames(tester);
                _expectPageOnlyClosed(tester, card);
              } else {
                // Positive control: the same retained TextField has an
                // accessible value whenever this face exposes its title.
                expect(
                  _semanticsValues(tester),
                  contains(_storedTitle(card.id)),
                );
              }
              expect(probe.leafState.editingChanges, isEmpty);
              expect(probe.leafState.notifierRebindings, 0);
              expect(
                card.row.rowMeta.writeToBuffer(),
                orderedEquals(originalRow),
              );
              _expectNotifierContract(card);
              expect(tester.takeException(), isNull, reason: mode.id);
            }
          } finally {
            semantics.dispose();
            await _dispose(tester, [card]);
          }
        },
      );
    }

    testWidgets(
      '$appearance: page-only initially editing gets a true production '
      'notifier and a usable focused editor without another edit event',
      (tester) async {
        final card = _CardFixture(isEditing: true);
        card.mode.value = CardPreviewMode.pageContent;
        final originalRow = card.row.rowMeta.writeToBuffer();
        try {
          await _pump(tester, [card], appearance: appearance);
          final probe = _probe(tester, card);
          expect(probe.leafState.initialIsEditing, isTrue);
          expect(probe.leafState.editingChanges, isEmpty);
          _expectEditing(tester, card, true);
          _expectComposition(tester, card, appearance);
          expect(FocusManager.instance.primaryFocus, same(probe.focus));

          // Do not use _startDraft: that sends an edit event and could mask
          // an incorrectly initialized production-owned notifier.
          await tester.showKeyboard(_title(card.id));
          tester.testTextInput.updateEditingValue(_draft);
          await _frames(tester);
          _expectRetained(tester, card, probe, _draft);
          expect(probe.leafState.editingChanges, isEmpty);
          _expectNotifierContract(card);
          expect(
            card.row.rowMeta.writeToBuffer(),
            orderedEquals(originalRow),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await _dispose(tester, [card]);
        }
      },
    );

    testWidgets(
      '$appearance: edit commands reveal the page-only editor; submission '
      'and blur hide it again without phantom focus or resetting its draft',
      (tester) async {
        final card = _CardFixture();
        card.mode.value = CardPreviewMode.pageContent;
        final originalRow = card.row.rowMeta.writeToBuffer();
        final semantics = tester.ensureSemantics();
        try {
          await _pump(tester, [card], appearance: appearance);
          final probe = _probe(tester, card);
          final notifications = <bool>[];
          _expectPageOnlyClosed(tester, card);

          for (final submit in [true, false]) {
            await _startDraft(tester, card, _draft);
            notifications.add(true);
            _expectRetained(
              tester,
              card,
              probe,
              _draft,
              submissions: submit ? 0 : 1,
            );
            _expectComposition(tester, card, appearance);
            expect(_semanticsValues(tester), contains(_draft.text));
            if (submit) {
              await tester.testTextInput.receiveAction(TextInputAction.done);
            } else {
              // A real focus loss must reach CardBloc through the supplied
              // notifier; do not directly clear the bloc's editing state.
              probe.focus.unfocus();
            }
            await _frames(tester);
            notifications.add(false);
            final closedValue = probe.controller.value;
            expect(closedValue.text, _draft.text);
            _expectRetained(
              tester,
              card,
              probe,
              closedValue,
              focused: false,
              submissions: 1,
            );
            _expectPageOnlyClosed(tester, card);
            probe.focus.requestFocus();
            await _frames(tester);
            _expectPageOnlyClosed(tester, card);

            // Merely revealing the title on another face must not restart
            // editing or restore the previous focus owner.
            for (final mode in [
              ...CardPreviewMode.values,
              CardPreviewMode.pageContent,
            ]) {
              card.mode.value = mode;
              await _frames(tester);
              _expectRetained(
                tester,
                card,
                probe,
                closedValue,
                focused: false,
                submissions: 1,
              );
              _expectComposition(tester, card, appearance);
              expect(probe.leafState.editingChanges, notifications);
              expect(probe.leafState.notifierRebindings, 0);
              _expectNotifierContract(card);
            }
            _expectPageOnlyClosed(tester, card);
            expect(
              card.row.rowMeta.writeToBuffer(),
              orderedEquals(originalRow),
            );
            expect(tester.takeException(), isNull);
          }
        } finally {
          semantics.dispose();
          await _dispose(tester, [card]);
        }
      },
    );

    testWidgets(
      '$appearance: actual body retains dirty title, selection, composing, '
      'state, controller, focus and notifier through all six modes and back',
      (tester) async {
        final card = _CardFixture();
        final originalRow = card.row.rowMeta.writeToBuffer();
        try {
          await _pump(tester, [card], appearance: appearance);
          final probe = _probe(tester, card);
          await _startDraft(tester, card, _draft);

          for (final mode in [
            ...CardPreviewMode.values,
            ...CardPreviewMode.values.reversed,
            CardPreviewMode.none,
          ]) {
            card.mode.value = mode;
            await _frames(tester);
            _expectRetained(tester, card, probe, _draft);
            _expectComposition(tester, card, appearance);
            expect(
              card.builder.calls
                  .where((call) => call.cell.fieldId == _primary)
                  .every((call) => identical(call.notifier, probe.notifier)),
              isTrue,
              reason: '$appearance / ${mode.id}: one production-owned notifier',
            );
            _expectNotifierContract(card);
            expect(
              card.row.rowMeta.writeToBuffer(),
              orderedEquals(originalRow),
            );
            expect(tester.takeException(), isNull, reason: mode.id);
          }
          expect(probe.leafState.editingChanges, [true]);
          expect(probe.leafState.notifierRebindings, 0);
          expect(card.row.initializeCalls, 1);
        } finally {
          await _dispose(tester, [card]);
        }
      },
    );

    testWidgets(
      '$appearance: real bloc editing events and leaf notifier communicate '
      'both ways in every mode',
      (tester) async {
        final card = _CardFixture();
        try {
          await _pump(tester, [card], appearance: appearance);
          final probe = _probe(tester, card);
          final notifications = <bool>[];
          for (final mode in CardPreviewMode.values) {
            card.mode.value = mode;
            await _frames(tester);
            expect(_titleState(tester, card), same(probe.leafState));
            expect(
              card.builder.lastFor(_primary).notifier,
              same(probe.notifier),
            );

            for (final editing in [true, false]) {
              card.bloc.add(CardEvent.setIsEditing(editing));
              await _frames(tester);
              notifications.add(editing);
              _expectEditing(tester, card, editing);
              expect(probe.leafState.editingChanges, notifications);
            }
            for (final editing in [true, false]) {
              // The fake leaf knows only the production-supplied notifier.
              // _CardContentCell's real listener must deliver the bloc event.
              probe.leafState.setEditing(editing);
              await _frames(tester);
              notifications.add(editing);
              _expectEditing(tester, card, editing);
              expect(probe.leafState.editingChanges, notifications);
            }
            card.bloc.add(const CardEvent.setIsEditing(false));
            await _frames(tester);
            expect(probe.leafState.editingChanges, notifications);
            expect(probe.leafState.notifierRebindings, 0);
            _expectNotifierContract(card);
            expect(tester.takeException(), isNull, reason: mode.id);
          }
        } finally {
          await _dispose(tester, [card]);
        }
      },
    );

    testWidgets(
      '$appearance: removing and reintroducing the primary in every mode '
      'does not promote a property or duplicate the production GlobalKey',
      (tester) async {
        final card = _CardFixture();
        try {
          await _pump(tester, [card], appearance: appearance);
          final bodyState = tester.state(_body(card.id));
          final titleKey = _productionTitleKey(tester, card);
          for (final mode in CardPreviewMode.values) {
            card.mode.value = mode;
            await _frames(tester);
            final old = _probe(tester, card);
            await _startDraft(tester, card, _draft);

            final primary = card.fields.fields.remove(_primary)!;
            card.row.notifyCellsChanged();
            await _frames(tester);
            expect(
              card.bloc.state.cells.map((cell) => cell.fieldId),
              [_before, _after],
            );
            expect(
              _within(
                card,
                find.byType(TextField, skipOffstage: false),
                skipOffstage: false,
              ),
              findsNothing,
            );
            expect(_productionTitleWrapper(card), findsNothing);
            expect(titleKey.currentState, isNull);
            expect(old.leafState.mounted, isFalse);
            expect(old.leafState.disposeCalls, 1);
            expect(
              () => ChangeNotifier.debugAssertNotDisposed(
                old.notifier.isCellEditing,
              ),
              throwsFlutterError,
              reason: 'the production cell owns and disposes its notifier',
            );
            _expectPropertyCells(tester, card);
            _expectNotifierContract(card);
            expect(
              tester.takeException(),
              isNull,
              reason: '${mode.id}: removed',
            );

            // Exercise another tree shape while the key has no mounted cell.
            // A removed editor is intentionally disposed, not a saved draft.
            card.mode.value = mode == CardPreviewMode.portrait
                ? CardPreviewMode.none
                : CardPreviewMode.portrait;
            card.bloc.add(const CardEvent.setIsEditing(false));
            await _frames(tester);
            card.fields.fields[_primary] = primary;
            card.row.notifyCellsChanged();
            card.mode.value = mode;
            await _frames(tester);

            final restored = _probe(tester, card);
            expect(restored.bodyState, same(bodyState));
            expect(restored.titleKey, same(titleKey));
            expect(restored.cellState, isNot(same(old.cellState)));
            expect(restored.leafState, isNot(same(old.leafState)));
            expect(restored.controller, isNot(same(old.controller)));
            expect(restored.notifier, isNot(same(old.notifier)));
            expect(restored.controller.text, _storedTitle(card.id));
            expect(restored.leafState.initialIsEditing, isFalse);
            expect(restored.leafState.dirty, isFalse);
            expect(restored.leafState.submissions, 0);
            _expectEditing(tester, card, false);
            _expectComposition(tester, card, appearance);
            card.bloc.add(const CardEvent.setIsEditing(true));
            await _frames(tester);
            _expectEditing(tester, card, true);
            restored.leafState.setEditing(false);
            await _frames(tester);
            _expectEditing(tester, card, false);
            expect(
              tester.takeException(),
              isNull,
              reason: '${mode.id}: reintroduced',
            );
          }
        } finally {
          await _dispose(tester, [card]);
        }
      },
    );

    testWidgets(
      '$appearance: reinserting the primary while already editing in every '
      'mode initializes a fresh true notifier under the same production key',
      (tester) async {
        final card = _CardFixture(isEditing: true);
        final originalRow = card.row.rowMeta.writeToBuffer();
        try {
          await _pump(tester, [card], appearance: appearance);
          final bodyState = tester.state(_body(card.id));
          final titleKey = _productionTitleKey(tester, card);
          for (final mode in CardPreviewMode.values) {
            card.mode.value = mode;
            await _frames(tester);
            final old = _probe(tester, card);
            await _startDraft(tester, card, _draft);
            final primary = card.fields.fields.remove(_primary)!;
            card.row.notifyCellsChanged();
            await _frames(tester);
            expect(
              card.bloc.state.cells.map((cell) => cell.fieldId),
              [_before, _after],
            );
            expect(_title(card.id, skipOffstage: false), findsNothing);
            expect(_productionTitleWrapper(card), findsNothing);
            expect(titleKey.currentState, isNull);
            expect(old.leafState.mounted, isFalse);
            expect(old.leafState.disposeCalls, 1);
            expect(
              () => ChangeNotifier.debugAssertNotDisposed(
                old.notifier.isCellEditing,
              ),
              throwsFlutterError,
            );

            _expectPropertyCells(tester, card);
            final callsWithoutPrimary = card.builder.calls.length;
            card.mode.value = mode == CardPreviewMode.portrait
                ? CardPreviewMode.pageContent
                : CardPreviewMode.portrait;
            card.bloc.add(const CardEvent.setIsEditing(true));
            await _frames(tester);
            expect(card.bloc.state.isEditing, isTrue);
            expect(card.builder.calls, hasLength(callsWithoutPrimary));
            _expectPropertyCells(tester, card);

            // No edit event is sent after reinsertion: the new cell must
            // initialize its notifier from the bloc's existing true state.
            card.fields.fields[_primary] = primary;
            card.row.notifyCellsChanged();
            card.mode.value = mode;
            await _frames(tester);
            final restored = _probe(tester, card);
            expect(restored.bodyState, same(bodyState));
            expect(restored.titleKey, same(titleKey));
            expect(restored.cellState, isNot(same(old.cellState)));
            expect(restored.leafState, isNot(same(old.leafState)));
            expect(restored.editableState, isNot(same(old.editableState)));
            expect(restored.controller, isNot(same(old.controller)));
            expect(restored.focus, isNot(same(old.focus)));
            expect(restored.notifier, isNot(same(old.notifier)));
            expect(restored.leafState.initialIsEditing, isTrue);
            expect(restored.leafState.editingChanges, isEmpty);
            expect(restored.controller.text, _storedTitle(card.id));
            expect(restored.leafState.dirty, isFalse);
            expect(restored.leafState.submissions, 0);
            _expectEditing(tester, card, true);
            expect(FocusManager.instance.primaryFocus, same(restored.focus));
            _expectComposition(tester, card, appearance);
            _expectNotifierContract(card);
            expect(card.row.fieldIds, _sourceFieldIds);
            expect(
              card.row.rowMeta.writeToBuffer(),
              orderedEquals(originalRow),
            );
            expect(tester.takeException(), isNull, reason: mode.id);
          }
        } finally {
          await _dispose(tester, [card]);
        }
      },
    );
  }

  testWidgets(
    'row data follows visible field order and keeps production property-cell '
    'state through reordering and field updates without promoting a property',
    (tester) async {
      final card = _CardFixture();
      card.mode.value = CardPreviewMode.titleAndProperties;
      final originalRow = card.row.rowMeta.writeToBuffer();
      final originalFields = {
        for (final id in [_before, _after]) id: card.fields.fields[id]!,
      };
      try {
        await _pump(tester, [card], appearance: 'paper');
        final probe = _probe(tester, card);
        await _startDraft(tester, card, _draft);
        _expectComposition(tester, card, 'paper');
        final propertyStates = {
          for (final id in [_before, _after])
            id: tester.state(_propertyCell(card.id, id)),
        };
        final propertyElements = {
          for (final id in [_before, _after])
            id: tester.element(_property(card.id, id)),
        };

        // Exercise primary at the start, end and middle of the supplied cells.
        // A simultaneous field-name update must follow the field's key, not its
        // old position; the real bloc receives fresh cells from its listener.
        for (final visibleOrder in [
          [_primary, _after, _before],
          [_after, _before, _primary],
          [_before, _primary, _after],
        ]) {
          card.fields.fields[_after] = _field(
            _after,
            'Updated property with ${visibleOrder.first} first',
            visibility: FieldVisibility.HideWhenEmpty,
          );
          card.row.fieldIds
            ..clear()
            ..addAll(visibleOrder)
            ..addAll([_hidden, _unset, _grouped, _unknown]);
          card.row.notifyCellsChanged();
          await _frames(tester);
          expect(
            card.bloc.state.cells.map((cell) => cell.fieldId),
            visibleOrder,
          );
          _expectComposition(tester, card, 'paper');
          _expectRetained(tester, card, probe, _draft);
          for (final id in [_before, _after]) {
            expect(
              tester.state(_propertyCell(card.id, id)),
              same(propertyStates[id]),
            );
            expect(
              tester.element(_property(card.id, id)),
              same(propertyElements[id]),
            );
          }
          _expectNotifierContract(card);
        }

        final callsBeforeHiding = card.builder.calls.length;
        for (final id in [_before, _after]) {
          card.fields.fields[id] = card.fields.fields[id]!.copyWith(
            fieldSettings: FieldSettingsPB(
              fieldId: id,
              visibility: FieldVisibility.AlwaysHidden,
            ),
          );
        }
        card.row.notifyCellsChanged();
        await _frames(tester);
        expect(card.bloc.state.cells.map((cell) => cell.fieldId), [_primary]);
        _expectComposition(tester, card, 'paper');
        _expectRetained(tester, card, probe, _draft);
        expect(
          card.builder.calls
              .skip(callsBeforeHiding)
              .map((call) => call.cell.fieldId)
              .toSet(),
          {_primary},
          reason: 'newly hidden properties must not even reach the builder',
        );
        for (final state in propertyStates.values) {
          expect(state.mounted, isFalse);
        }
        final padding = tester
            .widget<RowCardContent>(_body(card.id))
            .styleConfiguration
            .cardPadding;
        expect(
          tester.getSize(_body(card.id)).height,
          tester.getSize(_title(card.id)).height + padding.vertical,
          reason: 'filtering the last visible property removes the 6px gap',
        );

        card.fields.fields.addAll(originalFields);
        card.row.notifyCellsChanged();
        await _frames(tester);
        _expectComposition(tester, card, 'paper');
        _expectRetained(tester, card, probe, _draft);
        for (final id in [_before, _after]) {
          expect(
            tester.state(_propertyCell(card.id, id)),
            isNot(same(propertyStates[id])),
            reason: 'a removed property gets fresh state when shown again',
          );
        }
        _expectNotifierContract(card);
        expect(card.row.fieldIds, _sourceFieldIds);
        expect(card.row.rowMeta.writeToBuffer(), orderedEquals(originalRow));
        expect(tester.takeException(), isNull);
      } finally {
        await _dispose(tester, [card]);
      }
    },
  );

  testWidgets(
    'cover and notes metadata notifications plus light/dark/paper transitions '
    'update real body styles without resetting the draft',
    (tester) async {
      final card = _CardFixture();
      card.mode.value = CardPreviewMode.portrait;
      try {
        await _pump(tester, [card]);
        final probe = _probe(tester, card);
        await _startDraft(tester, card, _draft);
        var currentAppearance = 'light';
        for (final change in [
          (appearance: 'dark', color: '0xFF735799', notes: true),
          (appearance: 'paper', color: null, notes: false),
          (appearance: 'light', color: '0xFF368F72', notes: true),
        ]) {
          final updated = _rowMeta(
            card.id,
            color: change.color,
            hasNotes: change.notes,
          );
          card.row.updateMeta(updated);
          await _frames(tester);
          expect(card.bloc.state.rowMeta, same(updated));
          expect(
            tester.widget<RowCardContent>(_body(card.id)).rowMeta,
            same(updated),
          );
          expect(card.builder.lastFor(_primary).hasNotes, change.notes);
          expect(probe.leafState.widget.hasNotes, change.notes);
          _expectRetained(tester, card, probe, _draft);
          _expectComposition(tester, card, currentAppearance);

          await _pump(tester, [card], appearance: change.appearance);
          currentAppearance = change.appearance;
          _expectRetained(tester, card, probe, _draft);
          _expectComposition(tester, card, currentAppearance);
          expect(tester.takeException(), isNull);
        }
        // Notes metadata can say non-empty while documentId stays empty: the
        // real page-preview widgets must still take their backend-free branch.
        for (final mode in [
          CardPreviewMode.pageAndTitle,
          CardPreviewMode.pageContent,
          CardPreviewMode.none,
          CardPreviewMode.titleAndProperties,
        ]) {
          card.mode.value = mode;
          await _frames(tester);
          _expectRetained(tester, card, probe, _draft);
          _expectComposition(tester, card, currentAppearance);
          expect(card.builder.lastFor(_primary).hasNotes, isTrue);
          expect(tester.takeException(), isNull);
        }
        expect(probe.leafState.editingChanges, [true]);
        expect(probe.leafState.notifierRebindings, 0);
      } finally {
        await _dispose(tester, [card]);
      }
    },
  );

  testWidgets(
    'two independently keyed row bodies keep separate editors and notifiers '
    'through mode changes and sibling reordering',
    (tester) async {
      final first = _CardFixture(id: 'row-one');
      final second = _CardFixture(id: 'row-two');
      const secondDraft = TextEditingValue(
        text: 'A separate unsaved second title',
        selection: TextSelection(baseOffset: 2, extentOffset: 10),
        composing: TextRange(start: 2, end: 10),
      );
      try {
        await _pump(tester, [first, second], appearance: 'paper');
        final firstProbe = _probe(tester, first);
        final secondProbe = _probe(tester, second);
        expect(firstProbe.titleKey, isNot(same(secondProbe.titleKey)));
        expect(firstProbe.cellState, isNot(same(secondProbe.cellState)));
        expect(firstProbe.controller, isNot(same(secondProbe.controller)));
        expect(firstProbe.focus, isNot(same(secondProbe.focus)));
        expect(firstProbe.notifier, isNot(same(secondProbe.notifier)));

        await _startDraft(tester, first, _draft);
        firstProbe.leafState.setEditing(false);
        await _frames(tester);
        // Flutter ends IME composition on blur; preserve that legitimate
        // post-blur value, rather than asserting two simultaneous focus owners.
        final firstValue = firstProbe.controller.value;
        expect(firstValue.text, _draft.text);
        await _startDraft(tester, second, secondDraft);
        for (final mode in [
          ...CardPreviewMode.values,
          ...CardPreviewMode.values.reversed,
          CardPreviewMode.none,
        ]) {
          first.mode.value = mode;
          second.mode.value = CardPreviewMode
              .values[(mode.index + 2) % CardPreviewMode.values.length];
          await _pump(
            tester,
            mode.index.isEven ? [second, first] : [first, second],
            appearance: 'paper',
          );
          _expectRetained(
            tester,
            first,
            firstProbe,
            firstValue,
            focused: false,
          );
          _expectRetained(tester, second, secondProbe, secondDraft);
          _expectComposition(tester, first, 'paper');
          _expectComposition(tester, second, 'paper');
          expect(find.byType(RowCardContent), findsNWidgets(2));
          expect(
            find.byType(TextField, skipOffstage: false),
            findsNWidgets(2),
          );
          expect(
            find.byType(TextField),
            findsNWidgets(mode == CardPreviewMode.pageContent ? 1 : 2),
          );
          _expectNotifierContract(first);
          _expectNotifierContract(second);
          expect(tester.takeException(), isNull, reason: mode.id);
        }
        secondProbe.leafState.setEditing(false);
        await _frames(tester);
        _expectEditing(tester, first, false);
        _expectEditing(tester, second, false);
        first.bloc.add(const CardEvent.setIsEditing(true));
        await _frames(tester);
        _expectEditing(tester, first, true);
        _expectEditing(tester, second, false);
        expect(secondProbe.controller.text, secondDraft.text);
      } finally {
        await _dispose(tester, [first, second]);
      }
    },
  );
}

Finder _body(String rowId) => find.byKey(ValueKey(('row-body', rowId)));
Finder _title(String rowId, {bool skipOffstage = true}) => find.byKey(
      ValueKey(('fixture-title', rowId)),
      skipOffstage: skipOffstage,
    );
Finder _property(String rowId, String fieldId) => find.byKey(
      ValueKey(('fixture-property', rowId, fieldId)),
      skipOffstage: false,
    );
Finder _propertyCell(String rowId, String fieldId) => find.byKey(
      ValueKey((rowId, fieldId)),
      skipOffstage: false,
    );
Finder _within(
  _CardFixture card,
  Finder finder, {
  bool skipOffstage = true,
}) =>
    find.descendant(
      of: _body(card.id),
      matching: finder,
      skipOffstage: skipOffstage,
    );

Finder _titleFooter(_CardFixture card) => _within(
      card,
      find.byKey(
        const ValueKey('row-card-title-footer'),
        skipOffstage: false,
      ),
      skipOffstage: false,
    );

// Identity probes intentionally include offstage descendants. Visibility is
// asserted separately so retaining a hidden editor cannot pass as showing it.
Finder _productionTitleWrapper(_CardFixture card) => _within(
      card,
      find.byWidgetPredicate(
        (widget) =>
            widget.key is GlobalKey &&
            widget.key.toString().contains('row-card-title-editor'),
        skipOffstage: false,
      ),
      skipOffstage: false,
    );

GlobalKey<State<StatefulWidget>> _productionTitleKey(
  WidgetTester tester,
  _CardFixture card,
) =>
    tester.widget(_productionTitleWrapper(card)).key!
        as GlobalKey<State<StatefulWidget>>;

_TitleFixtureState _titleState(WidgetTester tester, _CardFixture card) =>
    tester.state<_TitleFixtureState>(
      _within(
        card,
        find.byType(_TitleFixture, skipOffstage: false),
        skipOffstage: false,
      ),
    );

typedef _EditorProbe = ({
  State<RowCardContent> bodyState,
  GlobalKey<State<StatefulWidget>> titleKey,
  State<StatefulWidget> cellState,
  _TitleFixtureState leafState,
  EditableTextState editableState,
  TextEditingController controller,
  FocusNode focus,
  EditableCardNotifier notifier,
});

_EditorProbe _probe(WidgetTester tester, _CardFixture card) {
  final titleKey = _productionTitleKey(tester, card);
  final leaf = _titleState(tester, card);
  return (
    bodyState: tester.state<State<RowCardContent>>(_body(card.id)),
    titleKey: titleKey,
    cellState: titleKey.currentState!,
    leafState: leaf,
    editableState: tester.state<EditableTextState>(
      find.descendant(
        of: _title(card.id, skipOffstage: false),
        matching: find.byType(EditableText, skipOffstage: false),
        skipOffstage: false,
      ),
    ),
    controller: leaf.controller,
    focus: leaf.focus,
    notifier: leaf.widget.notifier,
  );
}

void _expectRetained(
  WidgetTester tester,
  _CardFixture card,
  _EditorProbe before,
  TextEditingValue draft, {
  bool focused = true,
  bool dirty = true,
  int submissions = 0,
}) {
  final now = _probe(tester, card);
  final reason = '${card.id} / ${card.mode.value.id}';
  expect(now.bodyState, same(before.bodyState), reason: reason);
  expect(now.titleKey, same(before.titleKey), reason: reason);
  expect(now.cellState, same(before.cellState), reason: reason);
  expect(now.leafState, same(before.leafState), reason: reason);
  expect(now.editableState, same(before.editableState), reason: reason);
  expect(now.controller, same(before.controller), reason: reason);
  expect(now.focus, same(before.focus), reason: reason);
  expect(now.notifier, same(before.notifier), reason: reason);
  expect(now.controller.value, draft, reason: reason);
  expect(now.leafState.dirty, dirty, reason: reason);
  expect(now.leafState.submissions, submissions, reason: reason);
  expect(now.leafState.disposeCalls, 0, reason: reason);
  _expectEditing(tester, card, focused);
  if (focused) {
    expect(
      FocusManager.instance.primaryFocus,
      same(before.focus),
      reason: reason,
    );
  } else {
    expect(
      FocusManager.instance.primaryFocus,
      isNot(same(before.focus)),
      reason: reason,
    );
  }
}

void _expectEditing(WidgetTester tester, _CardFixture card, bool editing) {
  final leaf = _titleState(tester, card);
  final field = tester.widget<TextField>(
    _title(card.id, skipOffstage: false),
  );
  expect(card.bloc.state.isEditing, editing);
  expect(leaf.widget.notifier.isCellEditing.value, editing);
  expect(field.readOnly, !editing);
  expect(field.controller, same(leaf.controller));
  expect(field.focusNode, same(leaf.focus));
  expect(leaf.focus.hasFocus, editing);
}

List<String> _semanticsValues(WidgetTester tester) {
  final values = <String>[];
  bool collect(SemanticsNode node) {
    values.add(node.getSemanticsData().value);
    node.visitChildren(collect);
    return true;
  }

  var root = tester.getSemantics(find.byType(Scaffold));
  while (root.parent != null) {
    root = root.parent!;
  }
  collect(root);
  return values;
}

void _expectPageOnlyClosed(WidgetTester tester, _CardFixture card) {
  expect(card.mode.value, CardPreviewMode.pageContent);
  _expectEditing(tester, card, false);
  final title = _title(card.id, skipOffstage: false);
  final leaf = _titleState(tester, card);
  expect(title, findsOneWidget);
  expect(_title(card.id), findsNothing);
  expect(title.hitTestable(), findsNothing);
  expect(tester.widget<Offstage>(_titleFooter(card)).offstage, isTrue);
  expect(tester.getSize(_titleFooter(card)).height, 0);
  expect(TickerMode.of(tester.element(title)), isFalse);
  expect(leaf.focus.canRequestFocus, isFalse);
  expect(FocusManager.instance.primaryFocus, isNot(same(leaf.focus)));
  expect(_semanticsValues(tester), isNot(contains(leaf.controller.text)));
  expect(
    tester.getSize(_body(card.id)).height,
    tester.getSize(_within(card, find.byType(CardPagePreview))).height,
    reason: 'the retained footer contributes no height or padding',
  );
}

void _expectNotifierContract(_CardFixture card) {
  final titles =
      card.builder.calls.where((call) => call.cell.fieldId == _primary);
  expect(titles, isNotEmpty);
  expect(titles.every((call) => call.notifier != null), isTrue);
  final properties =
      card.builder.calls.where((call) => call.cell.fieldId != _primary);
  if (card.isCalendar) expect(properties, isNotEmpty);
  expect(
    properties.where(
      (call) =>
          !card.isCalendar && call.mode != CardPreviewMode.titleAndProperties,
    ),
    isEmpty,
    reason: 'each recorded build must belong to Calendar or the row-data face; '
        'visiting row data must not permit properties in the other five modes',
  );
  expect(properties.every((call) => call.notifier == null), isTrue);
  expect(
    card.builder.calls.every(
      (call) => [_before, _primary, _after].contains(call.cell.fieldId),
    ),
    isTrue,
    reason: 'hidden, unset, grouping and unknown fields never reach the leaves',
  );
  expect(
    card.builder.calls.every((call) => call.cell.rowId == card.id),
    isTrue,
  );
}

void _expectComposition(
  WidgetTester tester,
  _CardFixture card,
  String appearance,
) {
  final mode = card.mode.value;
  final body = tester.widget<RowCardContent>(_body(card.id));
  final styles = body.styleConfiguration.cellStyleMap;
  final original = styles[FieldType.RichText]! as TextCardCellStyle;
  final call = card.builder.lastFor(_primary);
  final actual = call.styles[FieldType.RichText]! as TextCardCellStyle;
  final coveredPortrait = mode == CardPreviewMode.portrait &&
      CardCover.canRender(
        body.rowMeta.hasCover() ? body.rowMeta.cover : null,
        null,
      );
  final expectedTitle = coveredPortrait
      ? original.titleTextStyle.copyWith(color: Colors.white)
      : original.titleTextStyle;
  final hideTitle =
      mode == CardPreviewMode.pageContent && !card.bloc.state.isEditing;
  final retainedTitle = _title(card.id, skipOffstage: false);
  final layout = tester.widget<RowCardPreviewLayout>(
    _within(card, find.byType(RowCardPreviewLayout)),
  );

  expect(body.styleConfiguration.showProperties, card.isCalendar);
  expect(layout.isEditing, card.bloc.state.isEditing);
  expect(_productionTitleWrapper(card), findsOneWidget);
  expect(
    _within(
      card,
      find.byType(_TitleFixture, skipOffstage: false),
      skipOffstage: false,
    ),
    findsOneWidget,
  );
  expect(retainedTitle, findsOneWidget);
  expect(_title(card.id), hideTitle ? findsNothing : findsOneWidget);
  expect(
    retainedTitle.hitTestable(),
    hideTitle ? findsNothing : findsOneWidget,
  );
  expect(find.byType(TextCardCell, skipOffstage: false), findsNothing);
  if (mode == CardPreviewMode.portrait) {
    expect(_titleFooter(card), findsNothing);
  } else {
    final footer = tester.widget<Offstage>(_titleFooter(card));
    expect(footer.offstage, hideTitle);
    final ticker = footer.child! as TickerMode;
    expect(ticker.enabled, !hideTitle);
    expect((ticker.child as ExcludeFocus).excluding, hideTitle);
    expect(TickerMode.of(tester.element(retainedTitle)), !hideTitle);
    expect(
      tester.getSize(_titleFooter(card)).height,
      hideTitle ? isZero : greaterThan(0),
    );
  }
  for (final face in CardPreviewMode.values) {
    expect(
      _within(card, find.byKey(ValueKey('row-card-face-${face.id}'))),
      face == mode ? findsOneWidget : findsNothing,
    );
  }
  expect(tester.widget<TextField>(retainedTitle).style, expectedTitle);
  expect(actual.titleTextStyle, expectedTitle);
  expect(actual.textStyle, same(original.textStyle));
  expect(actual.padding, original.padding);
  expect(actual.maxLines, original.maxLines);
  expect(call.styles[FieldType.Number], same(styles[FieldType.Number]));
  expect(call.styles, coveredPortrait ? isNot(same(styles)) : same(styles));
  final context = tester.element(_body(card.id));
  expect(
    original.titleTextStyle.color,
    tableViewPaletteOf(context).textPrimary,
  );
  expect(PaperTheme.isEnabled(context), appearance == 'paper');
  expect(
    Theme.of(context).brightness,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
  );

  _expectPropertyCells(tester, card);
  final showsPage = mode == CardPreviewMode.pageAndTitle ||
      mode == CardPreviewMode.pageContent;
  expect(
    _within(card, find.byType(CardPagePreview)),
    showsPage ? findsOneWidget : findsNothing,
  );
  expect(
    _within(card, find.byType(RowPagePreview)),
    showsPage ? findsOneWidget : findsNothing,
  );
  if (showsPage) {
    final preview = tester.widget<CardPagePreview>(
      _within(card, find.byType(CardPagePreview)),
    );
    final page = tester.widget<RowPagePreview>(
      _within(card, find.byType(RowPagePreview)),
    );
    final expectedHeight = card.isCompact ? 144.0 : 196.0;
    expect(preview.height, expectedHeight);
    expect(preview.isCompact, card.isCompact);
    expect(page.height, expectedHeight);
    expect(
      page.documentId,
      isEmpty,
    );
  }
  expect(
    _within(card, find.byType(CardCover)),
    mode == CardPreviewMode.cover || coveredPortrait
        ? findsOneWidget
        : findsNothing,
  );
  if (coveredPortrait) {
    expect(
      Theme.of(tester.element(_title(card.id))).textSelectionTheme.cursorColor,
      Colors.white,
    );
  }
  expect(call.hasNotes, !body.rowMeta.isDocumentEmpty);
}

void _expectPropertyCells(WidgetTester tester, _CardFixture card) {
  final mode = card.mode.value;
  final body = tester.widget<RowCardContent>(_body(card.id));
  final styles = body.styleConfiguration.cellStyleMap;
  final textStyle =
      (styles[FieldType.RichText]! as TextCardCellStyle).textStyle;
  final layout = tester.widget<RowCardPreviewLayout>(
    _within(card, find.byType(RowCardPreviewLayout)),
  );
  final includeProperties =
      card.isCalendar || mode == CardPreviewMode.titleAndProperties;
  final propertyIds = card.bloc.state.cells
      .where(
        (cell) => !(card.fields.getField(cell.fieldId)?.isPrimary ?? false),
      )
      .map((cell) => cell.fieldId)
      .toList();
  expect(layout.showProperties, includeProperties);
  expect(
    layout.properties.map((property) => property.key),
    [
      if (includeProperties)
        for (final id in propertyIds) ValueKey((card.id, id)),
    ],
    reason:
        'forward only the filtered nonprimary cells, in their original order',
  );
  final propertiesVisible = includeProperties &&
      (mode == CardPreviewMode.cover ||
          mode == CardPreviewMode.none ||
          mode == CardPreviewMode.titleAndProperties);
  for (final id in [_before, _after, _hidden, _unset, _grouped, _unknown]) {
    final visible = propertiesVisible && propertyIds.contains(id);
    expect(_property(card.id, id), visible ? findsOneWidget : findsNothing);
    expect(_propertyCell(card.id, id), visible ? findsOneWidget : findsNothing);
    if (visible) {
      final property = tester.widget<Text>(_property(card.id, id));
      expect(property.data, '${card.fields.getField(id)!.name}: ${card.id}');
      expect(property.style, textStyle);
      expect(card.builder.lastFor(id).styles, same(styles));
      expect(card.builder.lastFor(id).notifier, isNull);
      expect(card.builder.lastFor(id).mode, mode);
      expect(card.builder.lastFor(id).hasNotes, !body.rowMeta.isDocumentEmpty);
    }
  }
  if (propertiesVisible) {
    final title = _title(card.id);
    double? previousBottom = title.evaluate().isEmpty
        ? null
        : tester.getBottomLeft(title).dy +
            (mode == CardPreviewMode.titleAndProperties ? 6 : 0);
    for (final id in propertyIds) {
      final bounds = tester.getRect(_property(card.id, id));
      if (previousBottom != null) {
        expect(bounds.top, closeTo(previousBottom, 0.01));
      }
      previousBottom = bounds.bottom;
    }
  }
}

Future<void> _startDraft(
  WidgetTester tester,
  _CardFixture card,
  TextEditingValue draft,
) async {
  card.bloc.add(const CardEvent.setIsEditing(true));
  await _frames(tester);
  _expectEditing(tester, card, true);
  await tester.showKeyboard(_title(card.id));
  tester.testTextInput.updateEditingValue(draft);
  await _frames(tester);
  expect(_titleState(tester, card).controller.value, draft);
  expect(_titleState(tester, card).dirty, isTrue);
}

Future<void> _frames(WidgetTester tester) async {
  await tester.pump();
  await tester.pump();
}

Future<void> _pump(
  WidgetTester tester,
  List<_CardFixture> cards, {
  String appearance = 'light',
}) async {
  await tester.pumpWidget(
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
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final card in cards)
                      _CardHost(key: ValueKey(card.id), card: card),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
  expect(tester.takeException(), isNull);
}

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      'DM Sans',
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Future<void> _dispose(WidgetTester tester, List<_CardFixture> cards) async {
  try {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  } finally {
    // Bloc.close awaits stream cancellation; awaiting it on the widget test's
    // fake clock can hang and hide the original assertion failure.
    await tester.runAsync(() async {
      for (final card in cards) {
        await card.bloc.close();
        card.mode.dispose();
      }
    });
  }
  for (final card in cards) {
    expect(card.bloc.isClosed, isTrue);
    expect(card.row.disposeCalls, 1);
    expect(card.row.hasCallbacks, isFalse);
  }
  expect(tester.takeException(), isNull);
}

String _storedTitle(String rowId) => 'Stored title for $rowId';

RowMetaPB _rowMeta(
  String rowId, {
  String? color = '0xFF368F72',
  bool hasNotes = false,
}) =>
    RowMetaPB(
      id: rowId,
      documentId: '',
      isDocumentEmpty: !hasNotes,
      cover: color == null
          ? null
          : RowCoverPB(coverType: CoverTypePB.ColorCover, data: color),
    );

class _CardFixture {
  _CardFixture({
    this.id = 'row-card-content',
    bool isEditing = false,
    this.isCalendar = false,
    this.isCompact = false,
  }) {
    if (isCalendar) mode.value = CardPreviewMode.cover;
    row = _MemoryRowController(_rowMeta(id));
    builder = _RecordingCellBuilder(fields, mode: mode, isCalendar: isCalendar);
    bloc = CardBloc(
      fieldController: fields,
      groupFieldId: _grouped,
      viewId: isCalendar ? 'offline-calendar-content' : 'offline-board-content',
      isEditing: isEditing,
      rowController: row,
    )..add(const CardEvent.initial());
  }

  final String id;
  final bool isCalendar;
  final bool isCompact;
  final fields = _Fields();
  final mode = ValueNotifier(CardPreviewMode.none);
  late final _MemoryRowController row;
  late final _RecordingCellBuilder builder;
  late final CardBloc bloc;
}

class _CardHost extends StatelessWidget {
  const _CardHost({super.key, required this.card});

  final _CardFixture card;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 260,
        child: BlocProvider<CardBloc>.value(
          value: card.bloc,
          child: ValueListenableBuilder<CardPreviewMode>(
            valueListenable: card.mode,
            builder: (context, mode, _) => BlocBuilder<CardBloc, CardState>(
              builder: (context, state) => RowCardContent(
                key: ValueKey(('row-body', card.id)),
                rowMeta: state.rowMeta,
                cells: state.cells,
                cellBuilder: card.builder,
                isCompact: card.isCompact,
                styleConfiguration: card.isCalendar
                    ? RowCardStyleConfiguration(
                        cellStyleMap: desktopBoardCardCellStyleMap(context),
                      )
                    : RowCardStyleConfiguration(
                        cellStyleMap: desktopBoardCardCellStyleMap(context),
                        preview: mode,
                        showProperties: false,
                      ),
              ),
            ),
          ),
        ),
      );
}

FieldInfo _field(
  String id,
  String name, {
  bool primary = false,
  FieldVisibility? visibility = FieldVisibility.AlwaysShown,
}) =>
    FieldInfo.initial(
      FieldPB(
        id: id,
        name: name,
        fieldType: FieldType.RichText,
        isPrimary: primary,
      ),
    ).copyWith(
      fieldSettings: visibility == null
          ? null
          : FieldSettingsPB(fieldId: id, visibility: visibility),
    );

class _Fields extends Fake implements FieldController {
  final fields = <String, FieldInfo>{
    _before: _field(_before, 'A rich-text property before the title'),
    _primary: _field(_primary, 'Actual primary', primary: true),
    _after: _field(
      _after,
      'Another rich-text property',
      visibility: FieldVisibility.HideWhenEmpty,
    ),
    _hidden:
        _field(_hidden, 'Hidden', visibility: FieldVisibility.AlwaysHidden),
    _unset: _field(_unset, 'No visibility settings', visibility: null),
    _grouped: _field(_grouped, 'Grouping field'),
  };

  @override
  FieldInfo? getField(String fieldId) => fields[fieldId];
}

// Implements, rather than extends, RowController: no backend/listener/cache is
// constructed. The override exists BEFORE this object enters CardBloc's ctor.
class _MemoryRowController extends Fake implements RowController {
  _MemoryRowController(this._rowMeta);

  RowMetaPB _rowMeta;
  final fieldIds = List<String>.of(_sourceFieldIds);
  OnRowChanged? _onRowChanged;
  VoidCallback? _onMetaChanged;
  int initializeCalls = 0;
  int loadCalls = 0;
  int listenerRegistrations = 0;
  int disposeCalls = 0;

  bool get hasCallbacks => _onRowChanged != null || _onMetaChanged != null;

  @override
  String get rowId => _rowMeta.id;

  @override
  RowMetaPB get rowMeta => _rowMeta;

  @override
  Future<void> initialize() async {
    initializeCalls++;
  }

  @override
  List<CellContext> loadCells() {
    loadCalls++;
    // _makeCells mutates its result while filtering. Never hand it the fake's
    // own source list, or removing/reintroducing a field would be meaningless.
    return [
      for (final fieldId in fieldIds)
        CellContext(fieldId: fieldId, rowId: rowId),
    ];
  }

  @override
  void addListener({OnRowChanged? onRowChanged, VoidCallback? onMetaChanged}) {
    expectSync(initializeCalls, 1);
    expectSync(listenerRegistrations, 0);
    expectSync(onRowChanged, isNotNull);
    expectSync(onMetaChanged, isNotNull);
    listenerRegistrations++;
    _onRowChanged = onRowChanged;
    _onMetaChanged = onMetaChanged;
  }

  void notifyCellsChanged() {
    expectSync(_onRowChanged, isNotNull);
    _onRowChanged!(loadCells(), const ChangedReason.fieldDidChange());
  }

  void updateMeta(RowMetaPB meta) {
    expectSync(meta.id, rowId);
    expectSync(meta.documentId, isEmpty);
    expectSync(_onMetaChanged, isNotNull);
    _rowMeta = meta;
    _onMetaChanged!();
  }

  @override
  Future<void> dispose() async {
    disposeCalls++;
    _onRowChanged = null;
    _onMetaChanged = null;
  }
}

typedef _CellBuild = ({
  CellContext cell,
  CardPreviewMode mode,
  CardCellStyleMap styles,
  EditableCardNotifier? notifier,
  bool hasNotes,
});

class _RecordingCellBuilder extends Fake implements CardCellBuilder {
  _RecordingCellBuilder(
    this.fields, {
    required this.mode,
    required this.isCalendar,
  });

  final _Fields fields;
  final ValueNotifier<CardPreviewMode> mode;
  final bool isCalendar;
  final calls = <_CellBuild>[];

  _CellBuild lastFor(String fieldId) =>
      calls.lastWhere((call) => call.cell.fieldId == fieldId);

  @override
  Widget build({
    required CellContext cellContext,
    required CardCellStyleMap styleMap,
    EditableCardNotifier? cellNotifier,
    required bool hasNotes,
  }) {
    final field = fields.getField(cellContext.fieldId)!;
    final style = styleMap[FieldType.RichText]! as TextCardCellStyle;
    final currentMode = mode.value;
    calls.add(
      (
        cell: cellContext,
        mode: currentMode,
        styles: styleMap,
        notifier: cellNotifier,
        hasNotes: hasNotes,
      ),
    );
    // Called inside guarded pumps/builds: expectSync, not a foreign-zone expect.
    expectSync(cellNotifier, field.isPrimary ? isNotNull : isNull);
    expectSync(
      field.isPrimary ||
          isCalendar ||
          currentMode == CardPreviewMode.titleAndProperties,
      isTrue,
      reason:
          'only the current row-data board face may construct nonprimary cells',
    );
    if (!field.isPrimary) {
      return Text(
        '${field.name}: ${cellContext.rowId}',
        key: ValueKey(('fixture-property', cellContext.rowId, field.id)),
        style: style.textStyle,
        maxLines: style.maxLines,
      );
    }
    return _TitleFixture(
      // A LOCAL key cannot rescue an editor across layout parents. Retention
      // must come from RowCardContent's own GlobalKey on _CardContentCell.
      key: ValueKey(('fixture-leaf', cellContext.rowId, field.id)),
      rowId: cellContext.rowId,
      initialText: _storedTitle(cellContext.rowId),
      notifier: cellNotifier!,
      style: style,
      hasNotes: hasNotes,
    );
  }
}

// Real Flutter editor, deliberately NOT TextCardCell or a persistence fake.
// It consumes the passed style/notifier and reports focus changes back through
// that notifier. It never reads CardBloc or keeps state outside this leaf.
class _TitleFixture extends StatefulWidget {
  const _TitleFixture({
    super.key,
    required this.rowId,
    required this.initialText,
    required this.notifier,
    required this.style,
    required this.hasNotes,
  });

  final String rowId;
  final String initialText;
  final EditableCardNotifier notifier;
  final TextCardCellStyle style;
  final bool hasNotes;

  @override
  State<_TitleFixture> createState() => _TitleFixtureState();
}

class _TitleFixtureState extends State<_TitleFixture> {
  late final TextEditingController controller;
  late final bool initialIsEditing;
  final focus = FocusNode();
  final editingChanges = <bool>[];
  bool dirty = false;
  int submissions = 0;
  int disposeCalls = 0;
  int notifierRebindings = 0;

  @override
  void initState() {
    super.initState();
    controller = TextEditingController(text: widget.initialText);
    initialIsEditing = widget.notifier.isCellEditing.value;
    focus.addListener(_onFocusChanged);
    widget.notifier.isCellEditing.addListener(_onEditingChanged);
    if (initialIsEditing) _requestEditingFocus();
  }

  void setEditing(bool editing) =>
      widget.notifier.isCellEditing.value = editing;

  void _onFocusChanged() => setEditing(focus.hasFocus);

  void _onEditingChanged() {
    final editing = widget.notifier.isCellEditing.value;
    editingChanges.add(editing);
    setState(() {});
    if (editing) {
      _requestEditingFocus();
    } else {
      focus.unfocus();
    }
  }

  void _requestEditingFocus() {
    // Match TextCardCell's post-frame focus: the real parent must first
    // reveal a page-only footer and remove ExcludeFocus's restriction.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && widget.notifier.isCellEditing.value) {
        focus.requestFocus();
      }
    });
  }

  @override
  void didUpdateWidget(_TitleFixture oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.notifier, widget.notifier)) {
      notifierRebindings++;
      oldWidget.notifier.isCellEditing.removeListener(_onEditingChanged);
      widget.notifier.isCellEditing.addListener(_onEditingChanged);
    }
  }

  @override
  Widget build(BuildContext context) => TextField(
        key: ValueKey(('fixture-title', widget.rowId)),
        controller: controller,
        focusNode: focus,
        readOnly: !widget.notifier.isCellEditing.value,
        maxLines: null,
        minLines: 1,
        textInputAction: TextInputAction.done,
        showCursor: false,
        style: widget.style.titleTextStyle,
        decoration: InputDecoration(
          isDense: true,
          isCollapsed: true,
          contentPadding: widget.style.padding,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
        ),
        onTapOutside: (_) {},
        onChanged: (_) => dirty = true,
        onEditingComplete: () => focus.unfocus(),
        onSubmitted: (_) {
          submissions++;
          focus.unfocus();
        },
      );

  @override
  void dispose() {
    disposeCalls++;
    widget.notifier.isCellEditing.removeListener(_onEditingChanged);
    focus.removeListener(_onFocusChanged);
    focus.dispose();
    controller.dispose();
    // _CardContentCell, not its leaf, owns/disposes the notifier.
    super.dispose();
  }
}
