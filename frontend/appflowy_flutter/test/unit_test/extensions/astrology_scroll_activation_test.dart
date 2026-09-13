import 'dart:convert';

import 'package:appflowy/extensions/dart/built_in/astrology/astrology_block.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_chart_panel.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_tables.dart';
import 'package:appflowy/extensions/dart/built_in/astrology_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/scrolling/no_scrollbar_behavior.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:provider/provider.dart';

const _fixtureExtension = 'scroll-activation-fixtures';
const _nativeTypes = {
  astrologyInputWidgetType,
  astrologyChartWidgetType,
  astrologyDashaWidgetType,
  astrologyShadbalaWidgetType,
  astrologyAshtakavargaWidgetType,
  astrologyPlacementsWidgetType,
  astrologyPanchangaWidgetType,
  astrologyLibraryWidgetType,
  astrologyEventsWidgetType,
};
const _modes = [
  (name: 'native', enabled: false, reduced: false),
  (name: 'kinetic', enabled: true, reduced: false),
  (name: 'reduced motion', enabled: true, reduced: true),
];

void main() {
  _case('all nine real registrations gate the entire card in offline preview',
      (tester, h) async {
    final definitions = DashboardWidgetRegistry.all()
        .where((definition) => definition.extensionId == 'astrology')
        .toList();
    expect(
      definitions.map((definition) => definition.type).toSet(),
      _nativeTypes,
    );
    expect(definitions, hasLength(9));
    for (final definition in DashboardWidgetRegistry.all()
        .where((definition) => definition.extensionId.isEmpty)) {
      expect(
        definition.requiresScrollActivation,
        isFalse,
        reason: definition.type,
      );
    }
    for (final definition in definitions) {
      expect(
        definition.requiresScrollActivation,
        isTrue,
        reason: definition.type,
      );
      final spec = definition.create().copyWith(
            title: 'Native ${definition.type}',
            showTitle: true,
          );
      await h.mount(tester, [spec]);
      final document = h.controller.document;
      expect(find.byType(ScrollActivationRegion), findsOneWidget);
      _expectSelection(tester, h, null);
      expect(
        find.ancestor(
          of: find.text(spec.title),
          matching: find.byType(ScrollActivationRegion),
        ),
        findsOneWidget,
      );
      for (final panel in tester.widgetList<AstrologyChartPanel>(
        find.byType(AstrologyChartPanel),
      )) {
        expect(panel.preview, isTrue);
        expect(panel.calculator, isNull);
        expect(panel.input.place, isNull);
        expect(
          find.textContaining('No location is requested in a preview.'),
          findsOneWidget,
        );
      }
      await _wheel(tester, find.byType(DashboardCard), const Offset(0, 40));
      final afterWheel = h.outerV.offset;
      expect(afterWheel, greaterThan(0));
      await _pan(tester, find.byType(DashboardCard), const Offset(0, -60));
      expect(h.outerV.offset, greaterThan(afterWheel));
      expect(h.drags, 0);
      _expectSelection(tester, h, null);
      expect(h.controller.document, same(document));
      expect(h.controller.canUndo, isFalse);
      expect(tester.takeException(), isNull, reason: definition.type);
    }
  });

  for (final (appearance, mode) in _modes.indexed) {
    _case(
      '${mode.name}: focused and hovered unselected cards scroll only the page',
      (tester, h) async {
        await h.mount(
          tester,
          [h.spec('entry0'), h.spec('entry1')],
          rebuildOnSelection: false,
        );
        final document = h.controller.document;
        final before = jsonEncode(document.toJson());
        _expectSelection(tester, h, null);
        h.entryFields[0].requestFocus();
        await tester.pumpAndSettle();
        expect(h.entryFields[0].hasPrimaryFocus, isTrue);
        _expectSelection(tester, h, null);

        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await mouse.addPointer(location: Offset.zero);
        try {
          await mouse.moveTo(tester.getCenter(_key('entry-v0')));
          await tester.pumpAndSettle();
          _expectSelection(tester, h, null);
          await _wheel(tester, _key('entry-v0'), const Offset(0, 40));
          await _wheel(tester, _key('entry-h0'), const Offset(40, 0));
          final page = Offset(h.outerH.offset, h.outerV.offset);
          expect(page.dx, greaterThan(0));
          expect(page.dy, greaterThan(0));
          await _pan(tester, _key('entry-v0'), const Offset(0, -60));
          await _pan(tester, _key('entry-h0'), const Offset(-60, 0));
          expect(h.outerV.offset, greaterThan(page.dy));
          expect(h.outerH.offset, greaterThan(page.dx));
          for (final controller in [...h.entryV, ...h.entryH]) {
            expect(controller.offset, 0);
          }
          expect(h.entryFields[0].hasPrimaryFocus, isTrue);
          expect(h.entryTaps, [0, 0]);
          _expectSelection(tester, h, null);
          _expectReadingOnly(h, document, before);
        } finally {
          await mouse.removePointer();
        }
      },
      appearance: appearance,
    );

    _case(
      '${mode.name}: child buttons select exactly one outlined scrollable card',
      (tester, h) async {
        await h.mount(
          tester,
          [h.spec('entry0'), h.spec('entry1')],
          rebuildOnSelection: false,
        );
        final document = h.controller.document;
        final before = jsonEncode(document.toJson());
        _expectSelection(tester, h, null);
        await _click(tester, _key('entry-button0'));
        expect(h.entryTaps, [1, 0]);
        // No parent rebuilt its selected prop: the card itself must listen
        // to the controller for both its gate and its foreground outline.
        expect(tester.widget<DashboardCard>(_card('entry0')).selected, isFalse);
        _expectSelection(tester, h, 'entry0');
        await _wheel(tester, _key('entry-v0'), const Offset(0, 40));
        await _wheel(tester, _key('entry-h0'), const Offset(40, 0));
        final first = Offset(h.entryH[0].offset, h.entryV[0].offset);
        expect(first.dx, greaterThan(0));
        expect(first.dy, greaterThan(0));
        expect(h.outerV.offset, 0);
        expect(h.outerH.offset, 0);

        await _click(tester, _key('entry-button1'));
        expect(h.entryTaps, [1, 1]);
        _expectSelection(tester, h, 'entry1');
        expect(Offset(h.entryH[0].offset, h.entryV[0].offset), first);
        expect(h.entryV[1].offset, 0);
        expect(h.entryH[1].offset, 0);
        await _wheel(tester, _key('entry-v0'), const Offset(0, 40));
        await _wheel(tester, _key('entry-h0'), const Offset(40, 0));
        final page = Offset(h.outerH.offset, h.outerV.offset);
        expect(page.dx, greaterThan(0));
        expect(page.dy, greaterThan(0));
        expect(Offset(h.entryH[0].offset, h.entryV[0].offset), first);
        await _wheel(tester, _key('entry-v1'), const Offset(0, 40));
        await _wheel(tester, _key('entry-h1'), const Offset(40, 0));
        final second = Offset(h.entryH[1].offset, h.entryV[1].offset);
        expect(second.dx, greaterThan(0));
        expect(second.dy, greaterThan(0));
        expect(Offset(h.outerH.offset, h.outerV.offset), page);
        _expectSelection(tester, h, 'entry1');

        await _click(tester, _key('outside'));
        _expectSelection(tester, h, null);
        await _wheel(tester, _key('entry-v1'), const Offset(0, 40));
        await _wheel(tester, _key('entry-h1'), const Offset(40, 0));
        expect(h.outerV.offset, greaterThan(page.dy));
        expect(h.outerH.offset, greaterThan(page.dx));
        expect(Offset(h.entryH[0].offset, h.entryV[0].offset), first);
        expect(Offset(h.entryH[1].offset, h.entryV[1].offset), second);
        expect(h.entryTaps, [1, 1]);
        _expectSelection(tester, h, null);
        _expectReadingOnly(h, document, before);
      },
      appearance: appearance,
    );

    _case(
      '${mode.name}: external selection replaces the gate despite retained focus',
      (tester, h) async {
        await h.mount(
          tester,
          [h.spec('entry0'), h.spec('entry1')],
          rebuildOnSelection: false,
        );
        final document = h.controller.document;
        final before = jsonEncode(document.toJson());
        await _click(tester, _key('entry-field0'));
        _expectSelection(tester, h, 'entry0');
        await _wheel(tester, _key('entry-v0'), const Offset(0, 40));
        await _wheel(tester, _key('entry-h0'), const Offset(40, 0));
        final first = Offset(h.entryH[0].offset, h.entryV[0].offset);
        final firstState = tester.state<ScrollableState>(
          find.descendant(
            of: _key('entry-v0'),
            matching: find.byType(Scrollable),
          ),
        );
        final selections = <String?>[];
        void recordSelection() => selections.add(h.controller.selectedWidgetId);
        h.controller.addListener(recordSelection);
        try {
          h.controller.select('entry1');
          await tester.pumpAndSettle();
          expect(h.entryFields[0].hasPrimaryFocus, isTrue);
          expect(selections, ['entry1']);
          _expectSelection(tester, h, 'entry1');
          expect(Offset(h.entryH[0].offset, h.entryV[0].offset), first);
          expect(h.entryV[1].offset, 0);
          expect(h.entryH[1].offset, 0);
          await _wheel(tester, _key('entry-v0'), const Offset(0, 40));
          await _wheel(tester, _key('entry-h0'), const Offset(40, 0));
          final page = Offset(h.outerH.offset, h.outerV.offset);
          expect(page.dx, greaterThan(0));
          expect(page.dy, greaterThan(0));
          expect(Offset(h.entryH[0].offset, h.entryV[0].offset), first);
          await _wheel(tester, _key('entry-v1'), const Offset(0, 40));
          await _wheel(tester, _key('entry-h1'), const Offset(40, 0));
          final second = Offset(h.entryH[1].offset, h.entryV[1].offset);
          expect(second.dx, greaterThan(0));
          expect(second.dy, greaterThan(0));
          expect(Offset(h.outerH.offset, h.outerV.offset), page);
          expect(h.entryFields[0].hasPrimaryFocus, isTrue);
          expect(selections, ['entry1']);

          // Also leave the previously selected field before the next build.
          // Its old gate can still receive focus loss while the controller
          // already belongs to entry1; it must not clear that new selection.
          h.controller.select('entry0');
          await tester.pumpAndSettle();
          selections.clear();
          h.controller.select('entry1');
          h.entryFields[1].requestFocus();
          await tester.pumpAndSettle();
          expect(h.entryFields[1].hasPrimaryFocus, isTrue);
          expect(selections, ['entry1']);
          _expectSelection(tester, h, 'entry1');
          expect(Offset(h.entryH[0].offset, h.entryV[0].offset), first);
          expect(Offset(h.entryH[1].offset, h.entryV[1].offset), second);
          expect(
            tester.state<ScrollableState>(
              find.descendant(
                of: _key('entry-v0'),
                matching: find.byType(Scrollable),
              ),
            ),
            same(firstState),
          );
          expect(h.entryTaps, [0, 0]);
          _expectReadingOnly(h, document, before);
        } finally {
          h.controller.removeListener(recordSelection);
        }
      },
      appearance: appearance,
    );

    _case(
      '${mode.name}: real presentation preview selects without entering edit mode',
      (tester, h) async {
        final definition = DashboardWidgetRegistry.definitionFor(
          astrologyDashaWidgetType,
        )!;
        final spec = definition.create().copyWith(
              id: 'preview',
              title: 'Presentation preview',
              showTitle: true,
            );
        await h.mount(
          tester,
          [spec],
          mode: DashboardMode.presentation,
          rebuildOnSelection: false,
        );
        final document = h.controller.document;
        final before = jsonEncode(document.toJson());
        final panel = tester.widget<AstrologyChartPanel>(
          find.byType(AstrologyChartPanel),
        );
        expect(panel.preview, isTrue);
        expect(panel.calculator, isNull);
        expect(panel.input.place, isNull);
        _expectSelection(tester, h, null);
        await _wheel(tester, _card('preview'), const Offset(0, 40));
        final page = h.outerV.offset;
        expect(page, greaterThan(0));
        await _click(tester, find.text(spec.title));
        _expectSelection(tester, h, 'preview');
        expect(
          tester.widget<DashboardCard>(_card('preview')).selected,
          isFalse,
        );
        expect(h.outerV.offset, page);
        _expectReadingOnly(
          h,
          document,
          before,
          mode: DashboardMode.presentation,
        );
        await _click(tester, _key('outside'));
        _expectSelection(tester, h, null);
        await _wheel(tester, _card('preview'), const Offset(0, 40));
        expect(h.outerV.offset, greaterThan(page));
        _expectReadingOnly(
          h,
          document,
          before,
          mode: DashboardMode.presentation,
        );
      },
      appearance: appearance,
    );

    _case(
      '${mode.name}: two-finger scrolling over resize grips never resizes',
      (tester, h) async {
        await h.mount(tester, [h.spec('dasha')]);
        final document = h.controller.document;
        final scroll = _controller(tester, _key('astrology-dasha-scroll'));
        for (final cursor in const [
          SystemMouseCursors.resizeLeftRight,
          SystemMouseCursors.resizeUpDown,
          SystemMouseCursors.resizeDownRight,
        ]) {
          h.outerV.jumpTo(0);
          await tester.pump();
          final grip = find.descendant(
            of: find.byType(DashboardCard),
            matching: find.byWidgetPredicate(
              (widget) => widget is MouseRegion && widget.cursor == cursor,
            ),
          );
          expect(grip, findsOneWidget);
          await _pan(tester, grip, const Offset(0, -60));
          final page = h.outerV.offset;
          expect(
            page,
            greaterThan(0),
            reason: 'The grip must not claim a trackpad gesture.',
          );
          expect(h.resizes, 0);
          expect(h.drags, 0);
          expect(scroll.offset, 0);
          await _wheel(
            tester,
            _key('astrology-dasha-scroll'),
            const Offset(0, 40),
          );
          expect(h.outerV.offset, greaterThan(page));
          expect(
            scroll.offset,
            0,
            reason: 'Trackpad gestures never activate the card.',
          );
        }
        expect(h.controller.document, same(document));
        expect(h.controller.canUndo, isFalse);

        // Actual mouse resizing must still work after ignoring trackpad pan/zoom.
        h.outerV.jumpTo(0);
        await tester.pump();
        final rectangle = tester.getRect(find.byType(DashboardCard));
        await tester.dragFrom(
          rectangle.bottomRight - const Offset(6, 6),
          const Offset(20, 20),
          kind: PointerDeviceKind.mouse,
        );
        await tester.pumpAndSettle();
        expect(h.resizes, greaterThan(0));
      },
      appearance: appearance,
    );

    for (final reading in ['placements', 'shadbala']) {
      _case(
        '${mode.name}: actual $reading card routes both axes without dragging',
        (tester, h) async {
          final spec = h.spec(reading);
          await h.mount(tester, [spec, h.spec('plain')]);
          final document = h.controller.document;
          final vertical = _key('astrology-$reading-scroll');
          final v = _controller(tester, vertical);
          final state = tester.state(
            find.byType(
              reading == 'placements'
                  ? AstrologyPlacementsTable
                  : AstrologyShadbalaView,
            ),
          );
          expect(v.position.maxScrollExtent, greaterThan(120));
          expect(
            find.ancestor(
              of: _key('plain-list'),
              matching: find.byType(ScrollActivationRegion),
            ),
            findsNothing,
          );
          // A positive control: unrelated definitions do not acquire the gate.
          await _wheel(tester, _key('plain-list'), const Offset(0, 40));
          final plainOffset = h.plain.offset;
          expect(plainOffset, greaterThan(0));
          await _pan(tester, _key('plain-list'), const Offset(0, -60));
          expect(h.plain.offset, greaterThan(plainOffset));
          expect(h.outerV.offset, 0);

          await _wheel(tester, vertical, const Offset(0, 40));
          final pageBeforePan = h.outerV.offset;
          expect(pageBeforePan, greaterThan(0));
          await _pan(tester, vertical, const Offset(0, -60));
          expect(h.outerV.offset, greaterThan(pageBeforePan));
          expect(v.offset, 0);
          expect(h.drags, 0);
          _expectSelection(tester, h, null);
          // Placements activates through the real title; Shadbala through its
          // real Table button, which must also change the reading on that tap.
          await _click(
            tester,
            reading == 'placements'
                ? find.text(spec.title)
                : _key('shadbala-table-toggle'),
          );
          _expectSelection(tester, h, spec.id);
          final horizontal = _key('$reading-horizontal-scroll');
          final horizontalController = _controller(tester, horizontal);
          expect(
            horizontalController.position.maxScrollExtent,
            greaterThan(240),
          );
          final page = Offset(h.outerH.offset, h.outerV.offset);
          await _wheel(tester, vertical, const Offset(0, 40));
          final wheelOffset = v.offset;
          expect(wheelOffset, greaterThan(0));
          await _pan(tester, vertical, const Offset(0, -60));
          expect(v.offset, greaterThan(wheelOffset));
          final retainedV = v.offset;
          await _wheel(tester, horizontal, const Offset(40, 0), clip: vertical);
          final directHorizontal = horizontalController.offset;
          expect(directHorizontal, greaterThan(0));
          await _wheel(
            tester,
            horizontal,
            const Offset(0, 40),
            clip: vertical,
            shift: true,
          );
          expect(horizontalController.offset, greaterThan(directHorizontal));
          final beforeHorizontalPan = horizontalController.offset;
          await _pan(tester, horizontal, const Offset(-60, 0), clip: vertical);
          expect(horizontalController.offset, greaterThan(beforeHorizontalPan));
          expect(v.offset, retainedV);
          expect(Offset(h.outerH.offset, h.outerV.offset), page);

          final retainedH = horizontalController.offset;
          await _click(tester, _key('outside'));
          _expectSelection(tester, h, null);
          await _wheel(tester, vertical, const Offset(0, 40));
          await _pan(tester, horizontal, const Offset(-60, 0), clip: vertical);
          expect(h.outerV.offset, greaterThan(page.dy));
          expect(h.outerH.offset, greaterThan(page.dx));
          expect(v.offset, retainedV);
          expect(horizontalController.offset, retainedH);
          expect(_controller(tester, vertical), same(v));
          expect(_controller(tester, horizontal), same(horizontalController));
          expect(
            tester.state(find.byType(state.widget.runtimeType)),
            same(state),
          );
          expect(h.drags, 0);
          expect(h.controller.document, same(document));
          expect(h.controller.canUndo, isFalse);
        },
        appearance: appearance,
      );
    }

    _case(
      '${mode.name}: first Dasha tile tap and local Escape retain navigation',
      (tester, h) async {
        await h.mount(
          tester,
          [h.spec('dasha')],
          rebuildOnSelection: false,
        );
        final document = h.controller.document;
        final before = jsonEncode(document.toJson());
        final scroll = _key('astrology-dasha-scroll');
        final controller = _controller(tester, scroll);
        final state = tester.state(find.byType(AstrologyDashaTable));
        await _wheel(tester, scroll, const Offset(0, 40));
        final page = h.outerV.offset;
        expect(page, greaterThan(0));
        expect(controller.offset, 0);
        _expectSelection(tester, h, null);
        await _click(tester, _key('dasha-open-venus'));
        expect(_key('dasha-page-venus'), findsOneWidget);
        expect(_key('dasha-page-venus-venus'), findsNothing);
        expect(_key('dasha-page-root'), findsNothing);
        expect(tester.state(find.byType(AstrologyDashaTable)), same(state));
        expect(_controller(tester, scroll), same(controller));
        expect(h.outerV.offset, page);
        _expectSelection(tester, h, 'dasha');
        expect(h.controller.configuringWidgetId, isNull);
        tester.widget<TextButton>(_key('dasha-back')).focusNode!.requestFocus();
        await tester.pumpAndSettle();
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(_key('dasha-page-root'), findsOneWidget);
        _expectSelection(tester, h, 'dasha');
        // Dasha consumed the first Escape. The root Escape must reach the gate.
        await _wheel(tester, scroll, const Offset(0, 40));
        final retained = controller.offset;
        expect(retained, greaterThan(0));
        expect(h.outerV.offset, page);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        _expectSelection(tester, h, null);
        await _wheel(tester, scroll, const Offset(0, 40));
        expect(h.outerV.offset, greaterThan(page));
        expect(controller.offset, retained);
        expect(h.controller.document, same(document));
        expect(jsonEncode(h.controller.document.toJson()), before);
        expect(h.controller.canUndo, isFalse);
        expect(h.controller.configuringWidgetId, isNull);
        expect(h.drags, 0);
      },
      appearance: appearance,
    );

    _case(
      '${mode.name}: actual enlarged DashboardPage content starts ungated',
      (tester, h) async {
        final spec = h.spec('dasha');
        await h.mount(tester, [spec], page: true);
        h.controller.openModal(spec.id);
        await tester.pumpAndSettle();
        expect(find.byType(AstrologyDashaTable), findsNWidgets(2));
        // The page's existing modal host rebuilds its stack on opening. Observe
        // the mounted background card, not its previous disposed controller.
        final cardScroll =
            _controller(tester, _key('astrology-dasha-scroll').first);
        final enlarged = _key('astrology-dasha-scroll').last;
        final enlargedScroll = _controller(tester, enlarged);
        expect(enlargedScroll, isNot(same(cardScroll)));
        expect(
          find.ancestor(
            of: enlarged,
            matching: find.byType(ScrollActivationRegion),
          ),
          findsNothing,
        );
        await _wheel(tester, enlarged, const Offset(0, 40));
        final wheelOffset = enlargedScroll.offset;
        expect(wheelOffset, greaterThan(0));
        await _pan(tester, enlarged, const Offset(0, -60));
        expect(enlargedScroll.offset, greaterThan(wheelOffset));
        expect(cardScroll.offset, 0);
        await _click(
          tester,
          find.byWidgetPredicate(
            (widget) =>
                widget is DashboardIconButton &&
                widget.icon == Icons.close_rounded,
          ),
        );
        expect(h.controller.modalWidgetId, isNull);
        expect(enlargedScroll.hasClients, isFalse);
        await tester.pumpWidget(const SizedBox.shrink());
        h.controller.setValue('borrowed-controller-survives', true);
        expect(h.controller.state['borrowed-controller-survives'], isTrue);
      },
      appearance: appearance,
    );
  }

  _case(
    'controller deselection cancels both queued inner axes while the field stays focused',
    (tester, h) async {
      await h.mount(
        tester,
        [h.spec('entry0'), h.spec('entry1')],
        rebuildOnSelection: false,
      );
      final document = h.controller.document;
      final before = jsonEncode(document.toJson());
      await _click(tester, _key('entry-field0'));
      await tester.enterText(_key('entry-field0'), 'Retained text');
      await tester.pumpAndSettle();
      _expectSelection(tester, h, 'entry0');
      await _wheel(
        tester,
        _key('entry-v0'),
        const Offset(0, 120),
        settle: false,
      );
      await _wheel(
        tester,
        _key('entry-h0'),
        const Offset(120, 0),
        settle: false,
      );
      await _wheel(
        tester,
        _key('entry-v1'),
        const Offset(0, 120),
        settle: false,
      );
      await _wheel(
        tester,
        _key('entry-h1'),
        const Offset(120, 0),
        settle: false,
      );
      await tester.pump(const Duration(milliseconds: 16));
      for (final controller in [h.entryV[0], h.entryH[0], h.outerV, h.outerH]) {
        expect(controller.position.isScrollingNotifier.value, isTrue);
      }
      final retained = Offset(h.entryH[0].offset, h.entryV[0].offset);
      final page = Offset(h.outerH.offset, h.outerV.offset);

      h.controller.select(null);
      // Allow didUpdateWidget's post-frame cancellation, but no extra tick.
      await tester.pump();
      expect(h.entryFields[0].hasPrimaryFocus, isTrue);
      expect(Offset(h.entryH[0].offset, h.entryV[0].offset), retained);
      expect(h.entryV[0].position.isScrollingNotifier.value, isFalse);
      expect(h.entryH[0].position.isScrollingNotifier.value, isFalse);
      await tester.pumpAndSettle();
      _expectSelection(tester, h, null);
      expect(Offset(h.entryH[0].offset, h.entryV[0].offset), retained);
      expect(h.outerV.offset, greaterThan(page.dy));
      expect(h.outerH.offset, greaterThan(page.dx));

      final drainedPage = Offset(h.outerH.offset, h.outerV.offset);
      await _wheel(tester, _key('entry-v0'), const Offset(0, 40));
      await _wheel(tester, _key('entry-h0'), const Offset(40, 0));
      expect(h.outerV.offset, greaterThan(drainedPage.dy));
      expect(h.outerH.offset, greaterThan(drainedPage.dx));
      expect(Offset(h.entryH[0].offset, h.entryV[0].offset), retained);
      expect(h.entryFields[0].hasPrimaryFocus, isTrue);
      expect(h.entryText[0].text, 'Retained text');
      expect(h.entryTaps, [0, 0]);
      _expectSelection(tester, h, null);
      _expectReadingOnly(h, document, before);
    },
    appearance: 1,
  );

  _case(
    'real read-only AstrologyBlock gates its overflowing controls, without IO',
    (tester, h) async {
      final node = astrologyNode()
        ..updateAttributes({'width': 280.0, 'height': 300.0});
      final editor =
          EditorState(document: Document(root: pageNode(children: [node])))
            ..editable = false
            ..editorStyle = EditorStyle.desktop();
      final before = editor.document.toJson();
      try {
        await tester.pumpWidget(
          h.app(
            h.board([
              SizedBox(
                width: 280,
                height: 300,
                child: Builder(
                  builder: (context) => MediaQuery(
                    data: MediaQuery.of(context)
                        .copyWith(textScaler: const TextScaler.linear(2)),
                    child: Provider<EditorState>.value(
                      value: editor,
                      child: AstrologyBlock(
                        key: node.key,
                        node: node,
                        configuration: BlockComponentConfiguration(
                          padding: (_) => EdgeInsets.zero,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ]),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester
              .widget<AstrologyChartPanel>(find.byType(AstrologyChartPanel))
              .preview,
          isTrue,
        );
        // This covers the real block's native control viewport, not a fabricated
        // live chart. Its read-only panel intentionally remains an offline preview.
        final viewport = find
            .descendant(
              of: find.byType(AstrologyBlock),
              matching: find.byType(Scrollable),
            )
            .first;
        final scroll = tester.state<ScrollableState>(viewport);
        expect(scroll.position.maxScrollExtent, greaterThan(40));
        await _wheel(tester, viewport, const Offset(0, 40));
        final afterWheel = h.outerV.offset;
        expect(afterWheel, greaterThan(0));
        await _pan(tester, viewport, const Offset(0, -60));
        expect(h.outerV.offset, greaterThan(afterWheel));
        expect(scroll.position.pixels, 0);
        await _click(tester, find.text('Vedic astrology'));
        final page = h.outerV.offset;
        await _wheel(tester, viewport, const Offset(0, 40));
        expect(scroll.position.pixels, greaterThan(0));
        expect(h.outerV.offset, page);
        final retained = scroll.position.pixels;
        await _click(tester, _key('outside'));
        await _wheel(tester, viewport, const Offset(0, 40));
        expect(h.outerV.offset, greaterThan(page));
        expect(scroll.position.pixels, retained);
        expect(editor.document.toJson(), before);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        editor.dispose();
        await tester.pump();
      }
    },
    appearance: 2,
  );
}

void _case(
  String name,
  Future<void> Function(WidgetTester, _DashboardHarness) body, {
  int appearance = 0,
}) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 1000);
      final previousLocation = GeolocatorPlatform.instance;
      final location = _NoLocation();
      GeolocatorPlatform.instance = location;
      final extension = AstrologyExtension();
      final context = DartExtensionContext(info: extension.info);
      _DashboardHarness? harness;
      try {
        await extension.activate(context);
        final h = harness = _DashboardHarness(appearance);
        await body(tester, h);
        expect(
          location.calls,
          0,
          reason: 'Preview must never reach device IO.',
        );
        expect(find.byType(ErrorWidget), findsNothing);
        expect(tester.takeException(), isNull);
      } finally {
        await tester.pumpWidget(const SizedBox.shrink());
        await tester.pump();
        harness?.dispose();
        DashboardWidgetRegistry.unregisterAll(_fixtureExtension);
        context.scope.close();
        GeolocatorPlatform.instance = previousLocation;
        tester.view.reset();
      }
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

class _DashboardHarness {
  _DashboardHarness(this.appearance) {
    // Clone metadata/opt-in, not the engine-backed builder. Actual registrations
    // are exercised separately above; these use actual reading widgets with a
    // fixed hand-authored chart and never touch profile data or native plugins.
    final chart = _chart();
    for (final entry in [
      (
        'dasha',
        astrologyDashaWidgetType,
        AstrologyDashaTable(chart: chart, at: chart.utc),
      ),
      (
        'placements',
        astrologyPlacementsWidgetType,
        AstrologyPlacementsTable(chart: chart),
      ),
      (
        'shadbala',
        astrologyShadbalaWidgetType,
        AstrologyShadbalaView(chart: chart),
      ),
    ]) {
      final source = DashboardWidgetRegistry.definitionFor(entry.$2)!;
      DashboardWidgetRegistry.register(
        DashboardWidgetDefinition(
          type: spec(entry.$1).type,
          extensionId: _fixtureExtension,
          label: source.label,
          icon: source.icon,
          group: source.group,
          padding: source.padding,
          requiresScrollActivation: source.requiresScrollActivation,
          // Capture the binding context immediately: moving DashboardCard's
          // Builder above its gate must break these input-routing tests.
          builder: (binding) => ScrollConfiguration(
            behavior:
                NoScrollbarBehavior(ScrollConfiguration.of(binding.context))
                    .copyWith(scrollbars: true),
            child: entry.$3,
          ),
        ),
      );
    }
    // Real offline birth previews intentionally disable their text fields.
    // These local-only controls reproduce retained text-entry focus inside
    // the actual DashboardCard without invoking birth/profile or device IO.
    for (var index = 0; index < 2; index++) {
      DashboardWidgetRegistry.register(
        DashboardWidgetDefinition(
          type: spec('entry$index').type,
          extensionId: _fixtureExtension,
          label: () => 'Focusable reading $index',
          icon: Icons.text_fields,
          group: DashboardWidgetGroup.text,
          padding: const EdgeInsets.all(12),
          requiresScrollActivation: true,
          builder: (binding) => ScrollConfiguration(
            behavior: NoScrollbarBehavior(
              ScrollConfiguration.of(binding.context),
            ).copyWith(scrollbars: true),
            child: Column(
              children: [
                SizedBox(
                  height: 56,
                  child: Row(
                    children: [
                      TextButton(
                        key: ValueKey('entry-button$index'),
                        focusNode: entryButtons[index],
                        onPressed: () => entryTaps[index]++,
                        child: Text('Action $index'),
                      ),
                      Expanded(
                        child: TextField(
                          key: ValueKey('entry-field$index'),
                          focusNode: entryFields[index],
                          controller: entryText[index],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    key: ValueKey('entry-v$index'),
                    controller: entryV[index],
                    primary: false,
                    itemCount: 80,
                    itemExtent: 32,
                    itemBuilder: (_, row) => Text('Reading $index row $row'),
                  ),
                ),
                SizedBox(
                  height: 60,
                  child: SingleChildScrollView(
                    key: ValueKey('entry-h$index'),
                    controller: entryH[index],
                    primary: false,
                    scrollDirection: Axis.horizontal,
                    child: SizedBox(
                      width: 1800,
                      child: Text('Wide reading $index'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }
    DashboardWidgetRegistry.register(
      DashboardWidgetDefinition(
        type: spec('plain').type,
        extensionId: _fixtureExtension,
        label: () => 'Ungated control',
        icon: Icons.notes,
        group: DashboardWidgetGroup.text,
        // Deliberately omit requiresScrollActivation: its default must be false.
        builder: (_) => ListView.builder(
          key: const ValueKey('plain-list'),
          controller: plain,
          primary: false,
          itemCount: 80,
          itemExtent: 32,
          itemBuilder: (_, index) => Text('Unrelated row $index'),
        ),
      ),
    );
  }

  final int appearance;
  final outerV = ScrollController();
  final outerH = ScrollController();
  final plain = ScrollController();
  final entryV = [ScrollController(), ScrollController()];
  final entryH = [ScrollController(), ScrollController()];
  final entryFields = [FocusNode(), FocusNode()];
  final entryButtons = [FocusNode(), FocusNode()];
  final entryText = [TextEditingController(), TextEditingController()];
  final entryTaps = [0, 0];
  DashboardController? _controller;
  DashboardController get controller => _controller!;
  var drags = 0;
  var resizes = 0;

  DashboardWidgetSpec spec(String id) => DashboardWidgetSpec(
        id: id,
        type: 'scroll-fixture-$id',
        title: 'Fixture $id',
        placement: const DashboardPlacement(columnSpan: 6, rowSpan: 6),
      );

  Future<void> mount(
    WidgetTester tester,
    List<DashboardWidgetSpec> specs, {
    bool page = false,
    DashboardMode mode = DashboardMode.edit,
    bool rebuildOnSelection = true,
  }) async {
    await tester.pumpWidget(const SizedBox.shrink());
    _controller?.dispose();
    _controller = DashboardController(
      viewId: '',
      mode: page ? DashboardMode.presentation : mode,
      document: DashboardDocument(
        sections: [DashboardSection(id: 'scroll-section', widgets: specs)],
        settings:
            const DashboardSettings(showHeader: false, showControlBar: false),
      ),
    );
    expect(controller.viewId, isEmpty);
    await tester.pumpWidget(
      app(
        page
            ? DashboardPage(view: ViewPB()..id = '', controller: controller)
            : board([
                for (final spec in specs)
                  SizedBox(
                    width: 420,
                    height: 420,
                    child: Builder(
                      builder: (context) {
                        Widget buildCard() => DashboardCard(
                              controller: controller,
                              spec: spec,
                              palette: DashboardPalette.of(context),
                              selected: controller.selectedWidgetId == spec.id,
                              dragging: false,
                              onDragStart: () => drags++,
                              onDragUpdate: (_, __) => drags++,
                              onDragEnd: () => drags++,
                              onResizeStart: (_) => resizes++,
                              onResizeUpdate: (_, __) => resizes++,
                              onResizeEnd: () => resizes++,
                            );
                        return rebuildOnSelection
                            ? ListenableBuilder(
                                listenable: controller,
                                builder: (_, __) => buildCard(),
                              )
                            : buildCard();
                      },
                    ),
                  ),
              ]),
      ),
    );
    await tester.pumpAndSettle();
  }

  Widget app(Widget child) => MaterialApp(
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
          data: MediaQuery.of(context)
              .copyWith(disableAnimations: _modes[appearance].reduced),
          child: PremiumScrollScope(
            enabled: _modes[appearance].enabled,
            child: navigator!,
          ),
        ),
        home: Scaffold(
          body: Column(
            children: [
              SizedBox(
                height: 48,
                child: TextButton(
                  key: const ValueKey('outside'),
                  onPressed: () {},
                  child: const Text('Outside cards'),
                ),
              ),
              Expanded(child: child),
            ],
          ),
        ),
      );

  Widget board(List<Widget> cards) => SingleChildScrollView(
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
                  padding: const EdgeInsets.only(left: 300, top: 300),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final card in cards)
                        Padding(
                          padding: const EdgeInsets.only(right: 24),
                          child: card,
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );

  void dispose() {
    _controller?.dispose();
    outerV.dispose();
    outerH.dispose();
    plain.dispose();
    for (final controller in [...entryV, ...entryH]) {
      controller.dispose();
    }
    for (final node in [...entryFields, ...entryButtons]) {
      node.dispose();
    }
    for (final controller in entryText) {
      controller.dispose();
    }
  }
}

Finder _key(String value) => find.byKey(ValueKey(value));
Finder _card(String id) => find.byWidgetPredicate(
      (widget) => widget is DashboardCard && widget.spec.id == id,
    );
ScrollController _controller(WidgetTester tester, Finder finder) =>
    tester.widget<SingleChildScrollView>(finder).controller!;

void _expectSelection(
  WidgetTester tester,
  _DashboardHarness h,
  String? selected,
) {
  expect(h.controller.selectedWidgetId, selected);
  final activeIds = <String>[];
  for (final card
      in tester.widgetList<DashboardCard>(find.byType(DashboardCard))) {
    final definition = DashboardWidgetRegistry.definitionFor(card.spec.type);
    if (definition?.requiresScrollActivation != true) continue;
    final region = _key('dashboard-scroll-activation-${card.spec.id}');
    expect(region, findsOneWidget);
    final active = tester.widget<ScrollActivationRegion>(region).active;
    expect(active, card.spec.id == selected, reason: card.spec.id);
    if (active == true) activeIds.add(card.spec.id);

    final chrome = find
        .descendant(
          of: region,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is AnimatedContainer &&
                widget.foregroundDecoration != null,
          ),
        )
        .first;
    final expectedRing = card.palette.selectionRing(
      selected: card.spec.id == selected,
      radius: DashboardMetrics.cardRadius,
    );
    expect(
      tester.widget<AnimatedContainer>(chrome).foregroundDecoration,
      expectedRing,
      reason: '${card.spec.id}: selection must drive the foreground outline.',
    );
    final paintedRing = find
        .descendant(
          of: chrome,
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is DecoratedBox &&
                widget.position == DecorationPosition.foreground,
          ),
        )
        .first;
    expect(
      tester.widget<DecoratedBox>(paintedRing).decoration,
      expectedRing,
      reason: '${card.spec.id}: the settled outline must actually be painted.',
    );
  }
  expect(activeIds, selected == null ? isEmpty : [selected]);
}

void _expectReadingOnly(
  _DashboardHarness h,
  DashboardDocument document,
  String before, {
  DashboardMode mode = DashboardMode.edit,
}) {
  expect(h.controller.document, same(document));
  expect(jsonEncode(h.controller.document.toJson()), before);
  expect(h.controller.canUndo, isFalse);
  expect(h.controller.canRedo, isFalse);
  expect(h.controller.configuringWidgetId, isNull);
  expect(h.controller.modalWidgetId, isNull);
  expect(h.controller.mode, mode);
  expect(h.drags, 0);
  expect(h.resizes, 0);
}

Offset _point(WidgetTester tester, Finder finder, Finder? clip) {
  var rect = tester.getRect(finder);
  if (clip != null) rect = rect.intersect(tester.getRect(clip));
  expect(
    rect.isEmpty,
    isFalse,
    reason: 'Input must land in the visible viewport.',
  );
  return rect.center;
}

Future<void> _click(WidgetTester tester, Finder finder) async {
  await tester.tap(finder, kind: PointerDeviceKind.mouse);
  await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 20));
  await tester.pumpAndSettle();
}

Future<void> _wheel(
  WidgetTester tester,
  Finder finder,
  Offset delta, {
  Finder? clip,
  bool shift = false,
  bool settle = true,
}) async {
  if (shift) await tester.sendKeyDownEvent(LogicalKeyboardKey.shiftLeft);
  try {
    await tester.sendEventToBinding(
      PointerScrollEvent(
        position: _point(tester, finder, clip),
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
  Finder finder,
  Offset delta, {
  Finder? clip,
}) async {
  final position = _point(tester, finder, clip);
  await tester.sendEventToBinding(
    PointerPanZoomStartEvent(pointer: 81, device: 81, position: position),
  );
  for (var step = 1; step <= 3; step++) {
    await tester.sendEventToBinding(
      PointerPanZoomUpdateEvent(
        pointer: 81,
        device: 81,
        position: position,
        pan: delta * (step / 3),
        panDelta: delta / 3,
        timeStamp: Duration(milliseconds: step * 10),
      ),
    );
  }
  await tester.sendEventToBinding(
    PointerPanZoomUpdateEvent(
      pointer: 81,
      device: 81,
      position: position,
      pan: delta,
      timeStamp: const Duration(milliseconds: 200),
    ),
  );
  await tester.sendEventToBinding(
    PointerPanZoomEndEvent(
      pointer: 81,
      device: 81,
      position: position,
      timeStamp: const Duration(milliseconds: 201),
    ),
  );
  await tester.pumpAndSettle();
}

// Synthetic UI data, not reference ephemeris output; fixed time/offset and no IO.
AstrologyChart _chart() {
  final utc = DateTime.utc(2000, 1, 2, 12);
  const longitudes = [
    10.0,
    20.0,
    96.0,
    151.0,
    215.0,
    278.0,
    305.0,
    345.0,
    165.0,
  ];
  return AstrologyChart(
    input: AstrologyInput(
      utc: utc,
      utcOffsetMinutes: 0,
      dashaYearDays: 360,
      place: const AstrologyPlace(
        name: 'Synthetic fixture',
        latitude: 12,
        longitude: 77,
        timeZone: 'Etc/UTC',
      ),
    ),
    utc: utc,
    julianDay: 2451546,
    ayanamsaDegrees: 23.85,
    ascendant: 33,
    midheaven: 301,
    planets: [
      for (final body in VedicBody.values)
        VedicPlacement(
          body: body,
          name: body.label,
          shortName: body.shortName,
          longitude: longitudes[body.index],
          speed: 1,
        ),
    ],
    specialLagnas: const [],
    sunrise: utc.subtract(const Duration(hours: 6)),
    sunset: utc.add(const Duration(hours: 6)),
    nextSunrise: utc.add(const Duration(hours: 18)),
    weekday: 0,
    localMeanHours: 12,
    ephemerisVersion: 'synthetic-ui-fixture',
  );
}

class _NoLocation extends Fake
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {
  var calls = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('Unexpected location access: ${invocation.memberName}');
  }
}
