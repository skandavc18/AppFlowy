import 'package:appflowy/plugins/dashboard/presentation/dashboard_config_field.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/time_widgets.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_chrome.dart';
import 'package:appflowy/plugins/database/calendar/presentation/calendar_shell.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_agenda_view.dart';
import 'package:appflowy/plugins/database/calendar/presentation/views/month_view.dart';
import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_layout.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'calendar_test_support.dart';

DashboardController _controller(CalendarViewMode mode) => DashboardController(
      viewId:
          '', // The real controller explicitly does not persist an empty ID.
      document: DashboardDocument(
        sections: [
          DashboardSection(
            id: 'calendar-section',
            widgets: [
              DashboardWidgetSpec(
                id: 'calendar-widget',
                type: 'calendar',
                settings: {'mode': mode.name},
              ),
            ],
          ),
        ],
      ),
      mode: DashboardMode.edit,
      persistDebounce: const Duration(days: 1),
    );

Widget _calendar(
  DashboardController controller,
  CalendarWorkspace workspace, {
  CalendarViewDelegate? delegate,
  ValueChanged<DashboardWidgetContext>? captureContext,
}) =>
    ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final data = DashboardWidgetContext(
          context: context,
          controller: controller,
          spec: controller.document.widgetById('calendar-widget')!,
          palette: DashboardPalette.of(context),
        );
        captureContext?.call(data);
        return DashboardCalendar(
          key: const ValueKey('dashboard-calendar-fixture'),
          context: data,
          workspace: workspace,
          delegate:
              delegate ?? CalendarViewDelegate(colorOf: workspace.colorFor),
          initialDate: DateTime(2026, 8, 14),
          now: () => DateTime(2026, 8, 14),
        );
      },
    );

void main() {
  setUpAll(initializeCalendarTests);

  for (final mode in [
    CalendarViewMode.monthAgenda,
    CalendarViewMode.monthSplit,
  ]) {
    for (final appearance in ['light', 'dark', 'paper']) {
      testWidgets(
          'dashboard ${mode.name} $appearance uses the shared shell and persists its menu choice',
          (tester) async {
        final provider = CalendarFixtureProvider(
          events: [
            calendarFixtureEvent('dashboard event', DateTime(2026, 8, 14, 9)),
          ],
        );
        final workspace = CalendarWorkspace(providers: [provider]);
        final controller = _controller(mode);
        late DashboardWidgetContext data;
        try {
          await mountCalendarTest(
            tester,
            _calendar(
              controller,
              workspace,
              captureContext: (value) => data = value,
            ),
            appearance: appearance,
          );
          expect(find.byType(CalendarShell), findsOneWidget);
          expect(find.byType(CalendarMonthAgendaView), findsOneWidget);
          final shellState = tester.state(find.byType(CalendarShell));
          final readingState =
              tester.state(find.byType(CalendarMonthAgendaView));
          expect(find.text('dashboard event'), findsOneWidget);
          final definition = DashboardWidgetRegistry.definitionFor('calendar')!;
          final config = definition.configure!(data)
              .whereType<DashboardConfigChoice>()
              .first;
          expect(
            config.choices.map((choice) => choice.value),
            CalendarViewMode.values.map((mode) => mode.name),
          );
          expect(
            config.choices.map((choice) => choice.label),
            containsAll([
              calendarViewModeLabel(CalendarViewMode.monthAgenda),
              calendarViewModeLabel(CalendarViewMode.monthSplit),
            ]),
          );
          final next = mode == CalendarViewMode.monthAgenda
              ? CalendarViewMode.monthSplit
              : CalendarViewMode.monthAgenda;
          await tester.tap(find.byKey(const ValueKey('calendar-mode-menu')));
          await tester.pumpAndSettle();
          await tester.tap(
            find.widgetWithText(AppMenuRow, calendarViewModeLabel(next)),
          );
          await tester.pumpAndSettle();
          expect(
            controller.document.widgetById('calendar-widget')!.setting('mode'),
            next.name,
          );
          expect(
            tester
                .widget<CalendarShell>(find.byType(CalendarShell))
                .initialMode,
            next,
          );
          expect(tester.state(find.byType(CalendarShell)), same(shellState));
          expect(
            tester.state(find.byType(CalendarMonthAgendaView)),
            same(readingState),
          );
          // The configuration panel updates the SAME mounted shell too.
          config.onChanged(mode.name);
          await tester.pumpAndSettle();
          expect(
            tester
                .widget<CalendarMonthAgendaView>(
                  find.byType(CalendarMonthAgendaView),
                )
                .sideBySide,
            mode == CalendarViewMode.monthSplit,
          );
          final decoded =
              DashboardDocument.fromJson(controller.document.toJson());
          expect(
            decoded.widgetById('calendar-widget')!.setting('mode'),
            mode.name,
          );
          expect(provider.windows, hasLength(1));
          expect(tester.takeException(), isNull);
        } finally {
          await tester.pumpWidget(const SizedBox());
          expect(
            provider.disposed,
            isFalse,
            reason: 'Dashboard must not dispose a borrowed source.',
          );
          controller.dispose();
          workspace.dispose();
        }
      });
    }
  }

  testWidgets(
      'dashboard 400x300 and rectangular 680x320 reflow at 2x without losing selected day or scroll',
      (tester) async {
    final provider = CalendarFixtureProvider(
      events: [
        for (var i = 0; i < 40; i++)
          calendarFixtureEvent('dashboard row $i', DateTime(2026, 8, 14, 9, i)),
      ],
    );
    final workspace = CalendarWorkspace(providers: [provider]);
    final controller = _controller(CalendarViewMode.monthSplit);
    try {
      await mountCalendarTest(
        tester,
        _calendar(controller, workspace),
        textScale: 2,
      );
      final readingState = tester.state(find.byType(CalendarMonthAgendaView));
      final scroll = tester
          .widget<ListView>(
            find.byKey(const PageStorageKey('calendar-day-agenda-scroll')),
          )
          .controller!;
      scroll.jumpTo(160);
      await tester.pump();
      for (final size in [const Size(400, 300), const Size(680, 320)]) {
        await tester.pumpWidget(
          calendarTestApp(
            _calendar(controller, workspace),
            size: size,
            textScale: 2,
            appearance: 'paper',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.state(find.byType(CalendarMonthAgendaView)),
          same(readingState),
        );
        expect(scroll.offset, 160);
        final reading = tester.widget<CalendarMonthAgendaView>(
          find.byType(CalendarMonthAgendaView),
        );
        expect(reading.selectedDay, DateTime(2026, 8, 14));
        expect(
          reading.sideBySide,
          isTrue,
          reason: 'Reflow must not rewrite the chosen mode.',
        );
        expect(
          tester
              .widget<Flex>(
                find.byKey(const ValueKey('calendar-month-agenda-layout')),
              )
              .direction,
          size.width == 400 ? Axis.vertical : Axis.horizontal,
        );
        expect(tester.takeException(), isNull);
      }
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      workspace.dispose();
    }
  });

  testWidgets(
      'presentation, page read-only and provider capabilities reject calendar writes',
      (tester) async {
    final event = calendarFixtureEvent(
      'reminder',
      DateTime(2026, 8, 14, 9),
      kind: CalendarEventKind.reminder,
    );
    final provider = CalendarFixtureProvider(events: [event]);
    final workspace = CalendarWorkspace(providers: [provider]);
    final controller = _controller(CalendarViewMode.monthSplit);
    var creates = 0;
    var completes = 0;
    var opens = 0;
    final actions = CalendarViewDelegate(
      colorOf: workspace.colorFor,
      onCreateAt: (_, {bool hasTime = false}) => creates++,
      onToggleComplete: (_) => completes++,
      onOpenEvent: (_) => opens++,
    );
    try {
      await mountCalendarTest(
        tester,
        _calendar(controller, workspace, delegate: actions),
      );
      final retained =
          tester.widget<CalendarShell>(find.byType(CalendarShell)).delegate;
      await tester.tap(find.byKey(const ValueKey('calendar-agenda-add')));
      await tester
          .tap(find.byKey(const ValueKey('calendar-agenda-complete-reminder')));
      expect(creates, 1);
      expect(completes, 1);
      controller.setReadOnly(true);
      // Even callbacks already captured by a menu must recheck live access.
      retained.onCreateAt!(DateTime(2026, 8, 14), hasTime: false);
      retained.onToggleComplete!(event);
      await tester.pump();
      expect(creates, 1);
      expect(completes, 1);
      expect(find.byKey(const ValueKey('calendar-agenda-add')), findsNothing);
      expect(
        find.byKey(const ValueKey('calendar-agenda-complete-reminder')),
        findsNothing,
      );
      await tester
          .tap(find.byKey(const ValueKey('calendar-agenda-event-reminder')));
      expect(opens, 1);
      controller.setReadOnly(false);
      controller.setMode(DashboardMode.presentation);
      await tester.pump();
      expect(find.byKey(const ValueKey('calendar-agenda-add')), findsNothing);
      expect(
        find.byKey(const ValueKey('calendar-agenda-complete-reminder')),
        findsNothing,
      );
      controller.setMode(DashboardMode.edit);
      await tester.pump();
      expect(find.byKey(const ValueKey('calendar-agenda-add')), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      workspace.dispose();
    }

    final readonlyProvider = CalendarFixtureProvider(
      events: [event],
      capabilities: CalendarCapabilities.readOnly,
    );
    final readonlyWorkspace = CalendarWorkspace(providers: [readonlyProvider]);
    final readonlyController = _controller(CalendarViewMode.monthAgenda);
    try {
      await mountCalendarTest(
        tester,
        _calendar(
          readonlyController,
          readonlyWorkspace,
          delegate: CalendarViewDelegate(
            colorOf: readonlyWorkspace.colorFor,
            onCreateAt: (_, {bool hasTime = false}) => creates++,
            onToggleComplete: (_) => completes++,
          ),
        ),
      );
      expect(find.byKey(const ValueKey('calendar-agenda-add')), findsNothing);
      expect(
        find.byKey(const ValueKey('calendar-agenda-complete-reminder')),
        findsNothing,
      );
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      readonlyController.dispose();
      readonlyWorkspace.dispose();
    }
  });

  testWidgets('dashboard Keep it still reaches the retained calendar',
      (tester) async {
    final workspace = CalendarWorkspace(providers: [CalendarFixtureProvider()]);
    final controller = _controller(CalendarViewMode.monthSplit);
    try {
      await mountCalendarTest(
        tester,
        _calendar(controller, workspace),
        reducedMotion: false,
        accessibleNavigation: false,
      );
      final reading = find.byType(CalendarMonthAgendaView);
      final state = tester.state(reading);
      expect(MediaQuery.of(tester.element(reading)).disableAnimations, isFalse);
      controller.edit(
        (document) => document.copyWith(
          settings: document.settings.copyWith(reduceMotion: true),
        ),
      );
      await tester.pump();
      expect(tester.state(reading), same(state));
      expect(MediaQuery.of(tester.element(reading)).disableAnimations, isTrue);
      for (final box in tester.widgetList<AnimatedContainer>(
        find.descendant(
          of: reading,
          matching: find.byType(AnimatedContainer),
        ),
      )) {
        expect(box.duration, Duration.zero);
      }
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      workspace.dispose();
    }
  });

  testWidgets(
      'dashboard source rebinding retains shell state and invalidates old delegate callbacks',
      (tester) async {
    final day = DateTime(2026, 8, 14);
    final event = calendarFixtureEvent('old dashboard source', day);
    final firstProvider = CalendarFixtureProvider(events: [event]);
    final secondProvider = CalendarFixtureProvider(
      events: [calendarFixtureEvent('new dashboard source', day)],
    );
    final first = CalendarWorkspace(providers: [firstProvider]);
    final second = CalendarWorkspace(providers: [secondProvider]);
    final controller = _controller(CalendarViewMode.monthSplit);
    var oldWrites = 0;
    var newWrites = 0;
    try {
      await mountCalendarTest(
        tester,
        _calendar(
          controller,
          first,
          delegate: CalendarViewDelegate(
            colorOf: first.colorFor,
            onCreateAt: (_, {bool hasTime = false}) => oldWrites++,
          ),
        ),
      );
      final state = tester.state(find.byType(CalendarShell));
      final retained =
          tester.widget<CalendarShell>(find.byType(CalendarShell)).delegate;
      await tester.pumpWidget(
        calendarTestApp(
          _calendar(
            controller,
            second,
            delegate: CalendarViewDelegate(
              colorOf: second.colorFor,
              onCreateAt: (_, {bool hasTime = false}) => newWrites++,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.state(find.byType(CalendarShell)), same(state));
      expect(find.text('old dashboard source'), findsNothing);
      expect(find.text('new dashboard source'), findsOneWidget);
      expect(firstProvider.disposed, isFalse);
      retained.onCreateAt!(day, hasTime: false);
      expect(oldWrites, 0);
      await tester.tap(find.byKey(const ValueKey('calendar-agenda-add')));
      expect(newWrites, 1);
      firstProvider
          .publish([calendarFixtureEvent('late old dashboard source', day)]);
      await tester.pump();
      expect(find.text('late old dashboard source'), findsNothing);
      expect(secondProvider.windows, hasLength(1));
      expect(tester.takeException(), isNull);
    } finally {
      await tester.pumpWidget(const SizedBox());
      controller.dispose();
      first.dispose();
      second.dispose();
    }
  });
}
