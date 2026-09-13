import 'package:appflowy/extensions/dart/built_in/astrology/astrology_chart_panel.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_chart_selector.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_dashboard_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_model.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/astrology_style.dart';
import 'package:appflowy/extensions/dart/built_in/astrology/vedic_chart_view.dart';
import 'package:appflowy/extensions/dart/built_in/astrology_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

const _epsilon = 0.01;
const _appearances = [
  (name: 'light', brightness: Brightness.light, paper: false),
  (name: 'dark', brightness: Brightness.dark, paper: false),
  (name: 'paper', brightness: Brightness.light, paper: true),
];
const _chart = DashboardWidgetSpec(
  id: 'selector-test-chart',
  type: astrologyChartWidgetType,
  title: 'Personal chart title',
  placement: DashboardPlacement(columnSpan: 12, rowSpan: 6),
  settings: {'division': 1, 'custom_note': 'Keep me'},
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AstrologyChartSelector', () {
    _widgetTest(
        'opens all nine names, selects D-9 once and ignores reselection',
        (tester) async {
      final value = ValueNotifier<int>(1);
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder<int>(
              valueListenable: value,
              builder: (_, division, __) => _selectorHost(
                value: division,
                onChanged: (next) {
                  changes.add(next);
                  value.value = next;
                },
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selector = find.byType(AstrologyChartSelector);
        await _openMenu(tester, selector);
        _expectMenu(tester, selected: 1);
        expect(changes, isEmpty);

        await _choose(tester, 9);
        expect(changes, [9]);
        expect(value.value, 9);
        _expectFullValue(tester, selector, 9, semantics: true);

        await _openMenu(tester, selector);
        _expectMenu(tester, selected: 9);
        await _choose(tester, 9);
        expect(changes, [9], reason: 'The selected row is not a new edit.');
        expect(value.value, 9);
      } finally {
        await _unmount(tester);
        value.dispose();
      }
    });

    _widgetTest('Escape dismisses without changing the current division',
        (tester) async {
      final changes = <int>[];
      await _pumpSelector(tester, value: 4, onChanged: changes.add);
      final selector = find.byType(AstrologyChartSelector);
      await _openMenu(tester, selector);
      _expectMenu(tester, selected: 4);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await _escape(tester);
      expect(changes, isEmpty);
      expect(tester.widget<AstrologyChartSelector>(selector).value, 4);
      _expectFullValue(tester, selector, 4, semantics: true);
    });

    _widgetTest('Tab focuses the pill; Enter, Down and Tab operate its menu',
        (tester) async {
      final changes = <int>[];
      await _pumpSelector(tester, onChanged: changes.add);
      final selector = find.byType(AstrologyChartSelector);
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      final label = _within(_pill(selector), find.byType(Text));
      expect(Focus.of(tester.element(label)).hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      _expectMenu(tester, selected: 1);
      // The first Down skips the section header, not the first choice.
      for (final division in astrologyDivisions.keys.takeWhile((d) => d != 9)) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        _expectHighlight(tester, division);
        expect(changes, isEmpty);
      }
      await tester.sendKeyEvent(LogicalKeyboardKey.tab);
      await tester.pumpAndSettle();
      _expectHighlight(tester, 9);
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pumpAndSettle();
      expect(changes, [9]);
      expect(find.byType(AppMenuSurface), findsNothing);
    });

    _widgetTest('disabling with a pending menu discards its eventual selection',
        (tester) async {
      final enabled = ValueNotifier<bool>(true);
      final changes = <int>[];
      try {
        await tester.pumpWidget(
          _app(
            ValueListenableBuilder<bool>(
              valueListenable: enabled,
              builder: (_, canChange, __) => _selectorHost(
                onChanged: canChange ? changes.add : null,
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final selector = find.byType(AstrologyChartSelector);
        final state = tester.state(selector);
        await _openMenu(tester, selector);
        enabled.value = false;
        await tester.pumpAndSettle();
        expect(tester.state(selector), same(state));
        expect(tester.widget<TextButton>(_pill(selector)).onPressed, isNull);
        expect(find.byType(AppMenuSurface), findsOneWidget);
        await _choose(tester, 9);
        expect(changes, isEmpty);
        expect(tester.widget<AstrologyChartSelector>(selector).value, 1);

        // The discarded result must not leave the open-menu guard stuck.
        enabled.value = true;
        await tester.pumpAndSettle();
        await _openMenu(tester, selector);
        _expectMenu(tester, selected: 1);
        await _choose(tester, 9);
        expect(changes, [9]);
      } finally {
        await _unmount(tester);
        enabled.dispose();
      }
    });

    for (final appearance in _appearances) {
      for (final width in const [80.0, 240.0]) {
        for (final textScale in const [1.0, 2.0]) {
          _widgetTest(
            '${appearance.name}, ${width.toInt()}px, text $textScale: '
            'themed surfaces, full accessible value and disabled behavior',
            (tester) async {
              final theme = _theme(
                brightness: appearance.brightness,
                paper: appearance.paper,
              );
              final changes = <int>[];
              await _pumpSelector(
                tester,
                value: 9,
                onChanged: changes.add,
                width: width,
                textScale: textScale,
                theme: theme,
              );
              final selector = find.byType(AstrologyChartSelector);
              final context = tester.element(selector);
              final palette = AstrologyPalette.of(context);
              expect(Theme.of(context).brightness, appearance.brightness);
              expect(PaperTheme.isEnabled(context), appearance.paper);
              final style = tester.widget<TextButton>(_pill(selector)).style!;
              expect(style.backgroundColor!.resolve({}), palette.control);
              expect(style.foregroundColor!.resolve({}), palette.ink);
              expect(style.shape!.resolve({}), isA<StadiumBorder>());
              expect(
                style.side!.resolve({WidgetState.focused})!.color,
                palette.accent,
              );
              final compact = width == 80 || textScale == 2;
              expect(
                _within(
                  selector,
                  find.text(compact ? 'D-9' : astrologyDivisions[9]!),
                ),
                findsOneWidget,
              );
              expect(
                tester.getSize(selector).width,
                inExclusiveRange(0, width + _epsilon),
              );
              _expectFullValue(tester, selector, 9, semantics: true);
              _expectClean(tester);

              await _openMenu(tester, selector);
              _expectMenu(tester, selected: 9);
              expect(_background(tester, selector), palette.selection);
              final surface = find.byType(AppMenuSurface);
              final menuStyle = AppMenuStyle.of(tester.element(surface));
              final actualStyle = tester.widget<AppMenuSurface>(surface).style!;
              expect(actualStyle.surface, menuStyle.surface);
              expect(actualStyle.blurred, menuStyle.blurred);
              expect(
                tester
                    .widget<ColoredBox>(
                      _within(surface, find.byType(ColoredBox)),
                    )
                    .color,
                menuStyle.blurred
                    ? menuStyle.translucentSurface
                    : menuStyle.surface,
              );
              expect(
                tester
                    .widget<Icon>(
                      _within(_menuRow(9), find.byIcon(Icons.check_rounded)),
                    )
                    .color,
                palette.accent,
              );
              if (appearance.paper) {
                expect(menuStyle.surface, PaperTheme.popupBackground);
                expect(palette.control.r, greaterThan(palette.control.b));
                expect(menuStyle.surface.r, greaterThan(menuStyle.surface.b));
              }
              _expectClean(tester);
              await _escape(tester);
              expect(_background(tester, selector), palette.control);

              await _pumpSelector(
                tester,
                value: 9,
                width: width,
                textScale: textScale,
                theme: theme,
              );
              final disabled = tester.widget<TextButton>(_pill(selector));
              expect(disabled.onPressed, isNull);
              expect(
                disabled.style!.backgroundColor!
                    .resolve({WidgetState.disabled}),
                palette.control,
              );
              expect(
                disabled.style!.foregroundColor!
                    .resolve({WidgetState.disabled}),
                palette.muted,
              );
              await tester.tap(_pill(selector));
              await tester.pumpAndSettle();
              expect(find.byType(AppMenuSurface), findsNothing);
              expect(changes, isEmpty);
              _expectFullValue(tester, selector, 9, semantics: true);
            },
          );
        }
      }
    }
  });

  group('registered Astrology dashboard headers', () {
    for (final appearance in _appearances) {
      for (final width in const [280.0, 520.0]) {
        for (final textScale in const [1.0, 2.0]) {
          for (final showTitle in const [true, false]) {
            for (final mode in const [
              DashboardMode.edit,
              DashboardMode.presentation,
            ]) {
              _widgetTest(
                '${appearance.name}, ${width.toInt()}px, text $textScale, '
                '${showTitle ? 'title' : 'hidden title'}, ${mode.name}',
                (tester) async {
                  final spec = _chart.copyWith(showTitle: showTitle);
                  final document = _document([spec]);
                  await _withDashboard(
                    tester,
                    document,
                    (controller) async {
                      await _pumpCard(
                        tester,
                        controller,
                        spec,
                        width: width,
                        textScale: textScale,
                        theme: _theme(
                          brightness: appearance.brightness,
                          paper: appearance.paper,
                        ),
                      );
                      final card = _card(spec.id);
                      final selector = _selectorIn(card);
                      final header = _headerBox(card, selector);
                      expect(header, findsOneWidget);
                      final cardRect = tester.getRect(card);
                      final headerRect = tester.getRect(header);
                      final selectorRect = tester.getRect(selector);
                      final panelRect = tester.getRect(_panelIn(card));
                      expect(cardRect.width, closeTo(width, _epsilon));
                      expect(headerRect.top, closeTo(cardRect.top, _epsilon));
                      expect(headerRect.height, greaterThanOrEqualTo(40));
                      if (textScale == 2) {
                        expect(headerRect.height, greaterThan(40));
                      }
                      expect(selectorRect.center.dx,
                          greaterThan(cardRect.center.dx));
                      expect(selectorRect.top,
                          greaterThanOrEqualTo(headerRect.top));
                      expect(selectorRect.bottom,
                          lessThanOrEqualTo(headerRect.bottom));
                      expect(selectorRect.right,
                          lessThanOrEqualTo(cardRect.right));
                      expect(
                        selectorRect.right,
                        closeTo(
                          cardRect.right - (mode.isEditable ? 60 : 14),
                          _epsilon,
                        ),
                        reason:
                            'The pill stays at the right edge even when compact.',
                      );
                      expect(
                          headerRect.bottom, lessThanOrEqualTo(panelRect.top));
                      expect(
                        _within(card, find.text(spec.title)),
                        showTitle ? findsOneWidget : findsNothing,
                      );
                      expect(
                        tester
                            .widget<AstrologyChartSelector>(selector)
                            .onChanged,
                        mode.isEditable ? isNotNull : isNull,
                      );
                      _expectDivision(tester, card, 1);
                      _expectPreviews(tester, count: 1);

                      if (mode.isEditable) {
                        final mouse = await tester.createGesture(
                          kind: PointerDeviceKind.mouse,
                        );
                        await mouse.addPointer(location: Offset.zero);
                        try {
                          await tester.pump();
                          await mouse.moveTo(cardRect.center);
                          await tester.pumpAndSettle();
                          for (final icon in const [
                            Icons.tune_rounded,
                            Icons.more_horiz_rounded,
                          ]) {
                            final action = _dashboardAction(card, icon);
                            expect(action.hitTestable(), findsOneWidget);
                            final opacities =
                                tester.widgetList<AnimatedOpacity>(
                              _within(
                                card,
                                find.ancestor(
                                  of: action,
                                  matching: find.byType(AnimatedOpacity),
                                ),
                              ),
                            );
                            expect(opacities, isNotEmpty);
                            expect(
                                opacities.every((w) => w.opacity == 1), isTrue);
                            expect(
                              tester.getRect(selector).right,
                              lessThanOrEqualTo(tester.getRect(action).left),
                            );
                          }
                        } finally {
                          await mouse.removePointer();
                        }
                      } else {
                        expect(
                          _dashboardAction(card, Icons.more_horiz_rounded),
                          findsNothing,
                        );
                        expect(
                          _dashboardAction(card, Icons.tune_rounded),
                          findsNothing,
                        );
                      }
                      // Narrow headers may omit the layout toggle; the selector
                      // must remain usable without requiring that extra icon.
                      expect(controller.document, document);
                      expect(controller.canUndo, isFalse);
                    },
                    mode: mode,
                  );
                },
              );
            }
          }
        }
      }
    }

    _widgetTest(
        'the title still renames and stays separate from chart selection',
        (tester) async {
      await _withDashboard(tester, _document([_chart]), (controller) async {
        await _pumpCard(tester, controller, _chart);
        final card = _card(_chart.id);
        final title = _within(card, find.text(_chart.title));
        await tester.tap(title);
        await tester.pump(kDoubleTapMinTime + const Duration(milliseconds: 10));
        await tester.tap(title);
        await tester.pumpAndSettle();
        final field = _within(find.byType(AlertDialog), find.byType(TextField));
        expect(field, findsOneWidget);
        await tester.enterText(field, '  Renamed personal chart  ');
        await tester.testTextInput.receiveAction(TextInputAction.done);
        await tester.pumpAndSettle();
        expect(find.byType(AlertDialog), findsNothing);
        final renamed = controller.document.widgetById(_chart.id)!;
        expect(renamed.title, 'Renamed personal chart');
        expect(renamed.showTitle, isTrue);
        expect(_within(card, find.text(renamed.title)), findsOneWidget);
        _expectDivision(tester, card, 1);
        await _openMenu(tester, _selectorIn(card));
        await _choose(tester, 9);
        expect(controller.document.widgetById(_chart.id)!.title, renamed.title);
        expect(_within(card, find.text(renamed.title)), findsOneWidget);
        _expectDivision(tester, card, 9);
        _expectPreviews(tester, count: 1);
      });
    });

    _widgetTest('the style icon declares a standalone draft and preserves it',
        (tester) async {
      await _withDashboard(tester, _document([_chart]), (controller) async {
        expect(controller.document.variableFor(astrologyDraftKey), isNull);
        await _pumpCard(tester, controller, _chart);
        final card = _card(_chart.id);
        for (final style in const [
          IndianChartStyle.south,
          IndianChartStyle.north
        ]) {
          final toggle = _within(
            card,
            find.byTooltip('Switch to ${style.label}'),
          );
          expect(toggle.hitTestable(), findsOneWidget);
          await tester.tap(toggle);
          await tester.pumpAndSettle();
          final draft = controller.state[astrologyDraftKey] as AstrologyInput;
          expect(draft.style, style);
          expect(draft.utc, isNull);
          expect(draft.place, isNull);
          expect(controller.document.variableFor(astrologyDraftKey), isNotNull);
          expect(
            controller.document.variableFor(astrologyDraftKey)!.initialValue,
            isNull,
          );
          expect(controller.document.widgetById(_chart.id), _chart);
          expect(
            tester.widget<AstrologyChartPanel>(_panelIn(card)).input,
            same(draft),
          );
        }
        final draft = controller.state[astrologyDraftKey];
        await _openMenu(tester, _selectorIn(card));
        await _choose(tester, 9);
        expect(controller.state[astrologyDraftKey], same(draft));
        expect(
          controller.document.widgetById(_chart.id)!.settings,
          _chart.withSettings({'division': 9}).settings,
        );
        _expectDivision(tester, card, 9);
        _expectPreviews(tester, count: 1);
      });
    });

    _widgetTest('the real template persists division per card with Undo/Redo',
        (tester) async {
      final document = buildAstrologyDashboard();
      final charts = document.allWidgets
          .where((spec) => spec.type == astrologyChartWidgetType)
          .toList();
      await _withDashboard(tester, document, (controller) async {
        expect(charts, hasLength(3));
        await tester.pumpWidget(
          _app(
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final spec in charts)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: SizedBox(
                      width: 360,
                      height: 320,
                      child: _cardView(controller, spec),
                    ),
                  ),
              ],
            ),
          ),
        );
        await tester.pumpAndSettle();
        _expectPreviews(tester, count: 3);
        final first = charts.first;
        await _openMenu(tester, _selectorIn(_card(first.id)));
        await _choose(tester, 9);
        final expected =
            document.withWidget(first.withSettings({'division': 9}));
        expect(controller.document.toJson(), expected.toJson());
        expect(controller.state[astrologyDraftKey], isNull);
        final restored =
            DashboardDocument.fromJson(controller.document.toJson());
        expect(
            restored.widgetById(first.id)!.integer('division', fallback: 1), 9);
        for (final spec in charts) {
          _expectDivision(
            tester,
            _card(spec.id),
            spec.id == first.id ? 9 : spec.integer('division', fallback: 1),
          );
        }
        expect(controller.canUndo, isTrue);
        expect(controller.canRedo, isFalse);
        controller.undo();
        await tester.pumpAndSettle();
        expect(controller.document.toJson(), document.toJson());
        expect(controller.canUndo, isFalse, reason: 'One choice is one edit.');
        expect(controller.canRedo, isTrue);
        _expectDivision(tester, _card(first.id), 1);
        controller.redo();
        await tester.pumpAndSettle();
        expect(controller.document.toJson(), expected.toJson());
        expect(controller.canRedo, isFalse);
        _expectDivision(tester, _card(first.id), 9);
        _expectPreviews(tester, count: 3);
      });
    });

    _widgetTest(
        'an old root spec cannot overwrite edits made while its menu is open',
        (tester) async {
      await _withDashboard(tester, _document([_chart]), (controller) async {
        // Only the registered header/body listeners may rebuild here.
        await _pumpCard(tester, controller, _chart, listen: false);
        final card = _card(_chart.id);
        final oldRoot = tester.widget<DashboardCard>(card);
        await _openMenu(tester, _selectorIn(card));
        controller.edit(
          (document) => document.withWidget(
            document
                .widgetById(_chart.id)!
                .copyWith(title: 'Renamed while choosing')
                .withSettings({
              'division': 7,
              'custom_note': 'Newer note',
              'future_option': {
                'keep': [1, true, 'nested'],
              },
            }),
          ),
        );
        await tester.pumpAndSettle();
        final concurrent = controller.document;
        expect(tester.widget<DashboardCard>(card), same(oldRoot));
        expect(oldRoot.spec, same(_chart));
        _expectDivision(tester, card, 7);

        await _choose(tester, 9);
        final expected = concurrent.withWidget(
          concurrent.widgetById(_chart.id)!.withSettings({'division': 9}),
        );
        expect(controller.document.toJson(), expected.toJson());
        expect(tester.widget<DashboardCard>(card), same(oldRoot));
        _expectDivision(tester, card, 9);
        controller.undo();
        await tester.pumpAndSettle();
        expect(controller.document.toJson(), concurrent.toJson());
        _expectDivision(tester, card, 7);
        controller.redo();
        await tester.pumpAndSettle();
        expect(controller.document.toJson(), expected.toJson());
        _expectDivision(tester, card, 9);
        _expectPreviews(tester, count: 1);
      });
    });
  });

  _widgetTest(
      'the real enlarged page hosts a second header selector without IO',
      (tester) async {
    await _withDashboard(
      tester,
      _document([_chart]),
      (controller) async {
        // Focus mode is editable in this controller. Presentation really hides
        // the page chrome, without inventing providers or a backend-bound page.
        await tester.pumpWidget(
          _app(
            SizedBox(
              width: 1160,
              height: 800,
              child: DashboardPage(
                view: ViewPB()
                  ..id = ''
                  ..name = 'Chart selector preview',
                controller: controller,
              ),
            ),
            theme: _theme(paper: true),
          ),
        );
        await tester.pumpAndSettle();
        expect(controller.document.settings.showHeader, isFalse);
        expect(controller.document.settings.showControlBar, isFalse);
        expect(controller.isEditable, isFalse);
        expect(
          tester.widget<DashboardPage>(find.byType(DashboardPage)).controller,
          same(controller),
        );
        expect(find.text('Chart selector preview'), findsNothing);
        expect(find.byType(AstrologyChartSelector), findsOneWidget);
        _expectPreviews(tester, count: 1);
        controller.openModal(_chart.id);
        await tester.pumpAndSettle();
        expect(controller.modalWidgetId, _chart.id);
        expect(find.byType(AstrologyChartSelector), findsNWidgets(2));
        _expectPreviews(tester, count: 2);

        final modalSelector = find.byType(AstrologyChartSelector).last;
        expect(
          find.ancestor(
              of: modalSelector, matching: find.byType(DashboardCard)),
          findsNothing,
          reason:
              'This is the enlarged header, not the card behind the overlay.',
        );
        final close =
            _dashboardAction(find.byType(DashboardPage), Icons.close_rounded);
        expect(close.hitTestable(), findsOneWidget);
        final selectorRect = tester.getRect(modalSelector);
        final panelRect = tester.getRect(find.byType(AstrologyChartPanel).last);
        expect(selectorRect.bottom, lessThanOrEqualTo(panelRect.top));
        expect(selectorRect.center.dx, greaterThan(panelRect.center.dx));
        expect(
            selectorRect.right, lessThanOrEqualTo(tester.getRect(close).left));
        expect(
          selectorRect.right,
          closeTo(tester.getRect(close).left - 8, _epsilon),
        );

        controller.edit(
          (document) => document.withWidget(
            document.widgetById(_chart.id)!.withSettings({'division': 9}),
          ),
        );
        await tester.pumpAndSettle();
        for (final selector in find.byType(AstrologyChartSelector).evaluate()) {
          final finder = find.byWidget(selector.widget);
          _expectFullValue(tester, finder, 9);
          expect((selector.widget as AstrologyChartSelector).onChanged, isNull);
        }
        for (final panel in tester.widgetList<AstrologyChartPanel>(
          find.byType(AstrologyChartPanel),
        )) {
          expect(panel.division, 9);
        }
        await tester.tap(close);
        await tester.pumpAndSettle();
        expect(controller.modalWidgetId, isNull);
        expect(find.byType(AstrologyChartSelector), findsOneWidget);
        _expectDivision(tester, _card(_chart.id), 9);
        _expectPreviews(tester, count: 1);
        await _unmount(tester);
        controller.setValue('borrowed_owner_is_alive', true);
        expect(controller.state['borrowed_owner_is_alive'], isTrue);
      },
      mode: DashboardMode.presentation,
    );
  });

  _widgetTest('a plain built-in widget still has a 30-pixel header',
      (tester) async {
    final definition = DashboardWidgetRegistry.definitionFor('text')!;
    expect(definition.headerTrailing, isNull);
    final spec = definition.create().copyWith(
      title: 'Plain widget title',
      showTitle: true,
      settings: {'text': 'Ordinary dashboard content'},
    );
    final controller =
        DashboardController(viewId: '', document: _document([spec]));
    try {
      for (final mode in const [
        DashboardMode.edit,
        DashboardMode.presentation
      ]) {
        controller.setMode(mode);
        await _pumpCard(tester, controller, spec);
        final card = _card(spec.id);
        final title = _within(card, find.text(spec.title));
        expect(title, findsOneWidget);
        final header = _headerBox(card, title);
        expect(header, findsOneWidget);
        expect(tester.getSize(header).height, closeTo(30, _epsilon));
        expect(find.byType(AstrologyChartSelector), findsNothing);
      }
      expect(controller.canUndo, isFalse);
    } finally {
      await _unmount(tester);
      controller.dispose();
    }
  });
}

// Every test owns its platform guard and unmounts inside the body, before
// flutter_test checks timers. No registry reset or shared notifier mutation.
void _widgetTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(
    name,
    (tester) async {
      tester.view
        ..devicePixelRatio = 1
        ..physicalSize = const Size(1280, 900);
      final semantics = tester.ensureSemantics();
      final previousLocation = GeolocatorPlatform.instance;
      final location = _NoDeviceLocation();
      GeolocatorPlatform.instance = location;
      try {
        await body(tester);
        _expectClean(tester);
      } finally {
        try {
          await _unmount(tester);
        } finally {
          GeolocatorPlatform.instance = previousLocation;
          semantics.dispose();
          tester.view.reset();
        }
      }
      expect(location.calls, isEmpty, reason: 'No device/geolocation IO.');
      _expectClean(tester);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
  );
}

Future<void> _withDashboard(
  WidgetTester tester,
  DashboardDocument document,
  Future<void> Function(DashboardController) body, {
  DashboardMode mode = DashboardMode.edit,
}) async {
  final extension = AstrologyExtension();
  final context = DartExtensionContext(info: extension.info);
  // Both the panel preview guard and controller persistence guard use this ID.
  final controller =
      DashboardController(viewId: '', document: document, mode: mode);
  try {
    await extension.activate(context);
    expect(AstrologyRuntime.active.value, isTrue);
    expect(controller.viewId, isEmpty);
    await body(controller);
    await tester.pump(const Duration(minutes: 2));
    await tester.pumpAndSettle();
  } finally {
    try {
      await _unmount(tester);
    } finally {
      controller.dispose();
      context.scope.close();
    }
  }
}

DashboardDocument _document(List<DashboardWidgetSpec> widgets) =>
    DashboardDocument(
      sections: [
        DashboardSection(id: 'selector-test-section', widgets: widgets)
      ],
      settings:
          const DashboardSettings(showHeader: false, showControlBar: false),
    );

ThemeData _theme(
        {Brightness brightness = Brightness.light, bool paper = false}) =>
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

Widget _app(Widget child, {ThemeData? theme, double textScale = 1}) =>
    MaterialApp(
      theme: theme ?? _theme(),
      themeAnimationDuration: Duration.zero,
      // Wrap the navigator too: an overlay must see the same text scaling.
      builder: (context, navigator) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: navigator!,
      ),
      home: Scaffold(body: Center(child: child)),
    );

Widget _selectorHost({
  int value = 1,
  ValueChanged<int>? onChanged,
  double width = 240,
}) =>
    SizedBox(
      width: width,
      child: AstrologyChartSelector(value: value, onChanged: onChanged),
    );

Future<void> _pumpSelector(
  WidgetTester tester, {
  int value = 1,
  ValueChanged<int>? onChanged,
  double width = 240,
  double textScale = 1,
  ThemeData? theme,
}) async {
  await tester.pumpWidget(
    _app(
      _selectorHost(value: value, onChanged: onChanged, width: width),
      theme: theme,
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
}

Widget _cardView(
  DashboardController controller,
  DashboardWidgetSpec initialSpec, {
  bool listen = true,
}) =>
    Builder(
      builder: (context) {
        Widget card() => DashboardCard(
              key: ValueKey('test-card-${initialSpec.id}'),
              controller: controller,
              spec: listen
                  ? controller.document.widgetById(initialSpec.id)!
                  : initialSpec,
              palette: DashboardPalette.of(context),
              selected: controller.selectedWidgetId == initialSpec.id,
              dragging: false,
            );
        return listen
            ? ListenableBuilder(
                listenable: controller,
                builder: (_, __) => card(),
              )
            : card();
      },
    );

Future<void> _pumpCard(
  WidgetTester tester,
  DashboardController controller,
  DashboardWidgetSpec spec, {
  double width = 520,
  double textScale = 1,
  ThemeData? theme,
  bool listen = true,
}) async {
  await tester.pumpWidget(
    _app(
      SizedBox(
        width: width,
        height: 320,
        child: _cardView(controller, spec, listen: listen),
      ),
      theme: theme,
      textScale: textScale,
    ),
  );
  await tester.pumpAndSettle();
}

Finder _within(Finder parent, Finder matching) =>
    find.descendant(of: parent, matching: matching);

Finder _card(String id) => find.byWidgetPredicate(
      (widget) => widget is DashboardCard && widget.spec.id == id,
    );

Finder _selectorIn(Finder card) =>
    _within(card, find.byType(AstrologyChartSelector));

Finder _panelIn(Finder card) => _within(card, find.byType(AstrologyChartPanel));

// TextButton.icon is a subclass; exact runtime-type finders miss that form.
Finder _pill(Finder selector) => _within(
      selector,
      find.byWidgetPredicate((widget) => widget is TextButton),
    );

Finder _headerBox(Finder card, Finder child) => _within(
      card,
      find.ancestor(
        of: child,
        matching: find.byWidgetPredicate(
          (widget) => widget is SizedBox && widget.height != null,
        ),
      ),
    );

Finder _dashboardAction(Finder parent, IconData icon) => _within(
      parent,
      find.byWidgetPredicate(
        (widget) => widget is DashboardIconButton && widget.icon == icon,
      ),
    );

Finder _menuRow(int division) => find.byWidgetPredicate(
      (widget) =>
          widget is AppMenuRow && widget.label == astrologyDivisions[division],
    );

Color? _background(WidgetTester tester, Finder selector) => tester
    .widget<TextButton>(_pill(selector))
    .style!
    .backgroundColor!
    .resolve({});

Future<void> _openMenu(WidgetTester tester, Finder selector) async {
  expect(selector, findsOneWidget);
  expect(tester.widget<TextButton>(_pill(selector)).onPressed, isNotNull);
  await tester.tap(_pill(selector));
  await tester.pumpAndSettle();
  expect(find.byType(AppMenuSurface), findsOneWidget);
}

Future<void> _choose(WidgetTester tester, int division) async {
  expect(_menuRow(division).hitTestable(), findsOneWidget);
  await tester.tap(_menuRow(division));
  await tester.pumpAndSettle();
  expect(find.byType(AppMenuSurface), findsNothing);
}

Future<void> _escape(WidgetTester tester) async {
  await tester.sendKeyEvent(LogicalKeyboardKey.escape);
  await tester.pumpAndSettle();
  expect(find.byType(AppMenuSurface), findsNothing);
}

void _expectMenu(WidgetTester tester, {required int selected}) {
  expect(astrologyDivisions, hasLength(9));
  final headers = tester.widgetList<AppMenuSectionLabel>(
    find.byType(AppMenuSectionLabel),
  );
  expect(headers.map((header) => header.label), ['Divisional chart']);
  final rows = tester.widgetList<AppMenuRow>(find.byType(AppMenuRow));
  expect(rows, hasLength(9));
  expect(
      rows.map((row) => row.label), orderedEquals(astrologyDivisions.values));
  for (final entry in astrologyDivisions.entries) {
    final row = _menuRow(entry.key);
    expect(tester.widget<AppMenuRow>(row).selected, entry.key == selected);
    expect(_within(row, find.text(entry.value)), findsOneWidget);
    expect(
      _within(row, find.byIcon(Icons.check_rounded)),
      entry.key == selected ? findsOneWidget : findsNothing,
    );
  }
}

void _expectHighlight(WidgetTester tester, int division) {
  expect(
    tester
        .widgetList<AppMenuRow>(find.byType(AppMenuRow))
        .where((row) => row.highlighted)
        .map((row) => row.label),
    [astrologyDivisions[division]],
  );
}

void _expectFullValue(
  WidgetTester tester,
  Finder selector,
  int division, {
  bool semantics = false,
}) {
  final label = astrologyDivisions[division]!;
  expect(tester.widget<AstrologyChartSelector>(selector).value, division);
  expect(
      _within(selector, find.byTooltip('Chart type: $label')), findsOneWidget);
  final semantic = _within(
    selector,
    find.byWidgetPredicate(
      (widget) =>
          widget is Semantics && widget.properties.label == 'Chart type',
    ),
  );
  expect(semantic, findsOneWidget);
  expect(tester.widget<Semantics>(semantic).properties.value, label);
  if (semantics) {
    final data = tester.getSemantics(semantic).getSemanticsData();
    expect(data.label, 'Chart type');
    expect(data.value, label);
  }
}

void _expectDivision(WidgetTester tester, Finder card, int division) {
  _expectFullValue(tester, _selectorIn(card), division);
  expect(tester.widget<AstrologyChartPanel>(_panelIn(card)).division, division);
  expect(_within(card, find.byType(DropdownButton<int>)), findsNothing);
}

void _expectPreviews(WidgetTester tester, {required int count}) {
  final panels = find.byType(AstrologyChartPanel);
  expect(panels, findsNWidgets(count));
  for (final panel in tester.widgetList<AstrologyChartPanel>(panels)) {
    expect(panel.preview, isTrue);
    expect(panel.calculator, isNull);
    expect(panel.locationService, isNull);
    expect(panel.input.utc, isNull);
    expect(panel.input.place, isNull);
    expect(
      _within(
        find.byWidget(panel),
        find.text(
          'Live charts appear after you use this template. '
          'No location is requested in a preview.',
        ),
      ),
      findsOneWidget,
    );
  }
  expect(find.byType(DropdownButton<int>), findsNothing);
  expect(find.byType(VedicChartView), findsNothing);
  expect(find.byType(CircularProgressIndicator), findsNothing);
}

void _expectClean(WidgetTester tester) {
  expect(find.byType(ErrorWidget), findsNothing);
  expect(tester.takeException(), isNull,
      reason: 'No layout, overflow or IO error.');
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
}

/// Observe only the platform boundary. Never supply a position that could
/// accidentally allow a preview to reach the native ephemeris engine.
class _NoDeviceLocation extends Fake
    with MockPlatformInterfaceMixin
    implements GeolocatorPlatform {
  final calls = <Symbol>[];

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName);
    throw StateError(
        'Unexpected selector-test geolocation: ${invocation.memberName}');
  }
}
