import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/blank/home/home_agenda.dart';
import 'package:appflowy/plugins/blank/home/home_arrangement.dart';
import 'package:appflowy/plugins/blank/home/home_grid.dart';
import 'package:appflowy/plugins/blank/home/home_weather.dart';
import 'package:appflowy/plugins/blank/workspace_home_page.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/database/calendar/application/calendar_workspace.dart';
import 'package:appflowy/plugins/view_library/view_library_plugin.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/shared/weather/weather_reading.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/user/application/reminder/reminder_service.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_placement.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:appflowy/workspace/application/favorite/favorite_service.dart';
import 'package:appflowy/workspace/application/recent/cached_recent_service.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/local_page_store.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_labels.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-notification/subject.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_backend/rust_stream.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../util/home_profile_test_support.dart' show pumpHomeProfileClose;
import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart' show vividIconTestTheme;

const _timeout = Timeout(Duration(seconds: 60));
late Map<String, dynamic> _translations;

/// A fixed Wednesday morning, so dates, periods and agendas are exact.
final _now = DateTime(2026, 9, 30, 9, 5);

void main() {
  final allowFontFetching = GoogleFonts.config.allowRuntimeFetching;
  setUpAll(() async {
    GoogleFonts.config.allowRuntimeFetching = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    // Bundled translations only, preloaded outside the widget fake clock.
    _translations = await const TestBundleAssetLoader().load(
      'assets/translations',
      const Locale('en', 'US'),
    );
  });
  tearDownAll(() {
    GoogleFonts.config.allowRuntimeFetching = allowFontFetching;
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets(
      '$appearance: BlankPage is a landing page without startup writes',
      (tester) async {
        final fixture = _Fixture();
        final semantics = tester.ensureSemantics();
        try {
          final plugin = BlankPagePlugin();
          await _pumpHome(
            tester,
            fixture,
            appearance: appearance,
            page: plugin.widgetBuilder.buildWidget(
              context: PluginContext(),
              shrinkWrap: false,
            ),
          );
          expect(plugin.id, isEmpty);
          expect(plugin.pluginType, PluginType.blank);
          expect(plugin.widgetBuilder.viewName, 'Home');
          expect(plugin.widgetBuilder.contentPadding, EdgeInsets.zero);
          expect(find.byType(WorkspaceHomePage), findsOneWidget);

          // No greeting or quote: the cover and one search bar lead.
          expect(find.textContaining('Good morning'), findsNothing);
          expect(find.byKey(const ValueKey('home-quote')), findsNothing);
          expect(find.byKey(const ValueKey('home-cover')), findsOneWidget);

          // The time, the weather and the page to resume share one card.
          final glance = find.byKey(const ValueKey('home-glance'));
          expect(
            find.descendant(
              of: glance,
              matching: find.text(DateFormat.jm().format(_now)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: glance,
              matching: find.text(DateFormat.MMMMEEEEd().format(_now)),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: glance,
              matching: find.byKey(const ValueKey('home-weather-add')),
            ),
            findsOneWidget,
          );
          expect(
            find.descendant(
              of: glance,
              matching: find.byKey(const ValueKey('home-resume')),
            ),
            findsOneWidget,
          );
          expect(find.text('fixture-workspace'), findsNothing);
          expect(find.text('private@example.invalid'), findsNothing);

          // One search bar, quick jumps, and the page to resume.
          expect(_bar, findsOneWidget);
          _expectButton(tester, _bar, label: 'Search this workspace');
          expect(
            find.byKey(const ValueKey('home-quick-jump-reading')),
            findsOneWidget,
          );
          expect(
            tester
                .widget<Text>(find.byKey(const ValueKey('home-resume-title')))
                .data,
            'Launch plan',
          );
          // Its preview shows the opening lines; one line says the rest.
          expect(
            find.byKey(const ValueKey('home-resume-stats')),
            findsOneWidget,
          );
          expect(find.textContaining('1,420 words'), findsOneWidget);
          expect(find.textContaining('Viewed 2m ago'), findsOneWidget);

          // Reminders wait in their own card, overdue first; the calendar
          // and the day's events sit beside them.
          final reminders = find.byKey(const ValueKey('home-reminders'));
          final titles = [
            'Renew passport',
            'Design review',
            'Pay invoices',
          ];
          for (final title in titles) {
            expect(
              find.descendant(of: reminders, matching: find.text(title)),
              findsOneWidget,
            );
          }
          final tops = [
            for (final title in titles)
              tester
                  .getTopLeft(
                    find.descendant(of: reminders, matching: find.text(title)),
                  )
                  .dy,
          ];
          expect(tops[0], lessThan(tops[1]));
          expect(tops[1], lessThan(tops[2]));
          expect(find.byKey(const ValueKey('home-calendar')), findsOneWidget);
          expect(
            find.byKey(const ValueKey('home-events-empty')),
            findsOneWidget,
          );
          // The rail is on the right of the pages worked on lately, the
          // glance card level with them.
          final pages = tester.getRect(
            find.byKey(const ValueKey('home-jump-back-in')),
          );
          for (final part in ['home-glance', 'home-calendar']) {
            expect(
              tester.getTopLeft(find.byKey(ValueKey(part))).dx,
              greaterThan(pages.right),
            );
          }
          expect(
            tester.getTopLeft(find.byKey(const ValueKey('home-glance'))).dy,
            pages.top,
          );

          // Thumbnails of the other recent pages; the resumed one leads.
          expect(
            find.byKey(const ValueKey('home-jump-card-budget')),
            findsOneWidget,
          );
          expect(
            find.byKey(const ValueKey('home-jump-card-launch')),
            findsNothing,
          );

          final canvas = find.byWidgetPredicate(
            (widget) =>
                widget is WorkspaceSurface &&
                widget.kind == WorkspaceSurfaceKind.canvas,
          );
          final container = tester.widget<Container>(
            find.descendant(of: canvas, matching: find.byType(Container)).first,
          );
          final background = (container.decoration! as BoxDecoration).color!;
          expect(
            background,
            WorkspacePalette.of(tester.element(canvas)).background,
          );
          if (appearance == 'paper') {
            expect(background.r, greaterThan(background.b));
            expect(background, isNot(Colors.white));
          }
          expect(fixture.tabs.events, isEmpty);
          expect(fixture.notifications.hasListener, isFalse);
          expect(fixture.menu.latestOpenView?.id, 'untouched-selection');
          expect(fixture.storage.accesses, isEmpty);
          expect(fixture.removedRecents, isEmpty);
          expect(fixture.favorites.toggled, isEmpty);
          expect(fixture.reminders.updated, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      '$appearance: wide, narrow, 2x and RTL stay usable',
      (tester) async {
        final fixture = _Fixture();
        try {
          fixture.workspace.show(
            _workspace(name: 'A long workspace name that wraps across lines'),
            userName: 'Alexandria Ocasio Long-Name Person',
          );
          for (final (size, scale, direction) in [
            (const Size(1440, 1000), 1.0, ui.TextDirection.ltr),
            (const Size(900, 700), 1.0, ui.TextDirection.rtl),
            (const Size(360, 640), 2.0, ui.TextDirection.ltr),
            (const Size(320, 600), 2.0, ui.TextDirection.rtl),
          ]) {
            await _pumpHome(
              tester,
              fixture,
              appearance: appearance,
              size: size,
              scale: scale,
              direction: direction,
            );
            expect(tester.takeException(), isNull);
            final bounds = tester.getRect(find.byType(WorkspaceHomePage));
            final bar = tester.getRect(_bar);
            expect(bar.width, greaterThan(0));
            expect(bar.left, greaterThanOrEqualTo(bounds.left));
            expect(bar.right, lessThanOrEqualTo(bounds.right));
            expect(find.byKey(const ValueKey('home-glance')), findsOneWidget);
          }
          await tester.ensureVisible(
            find.byKey(const ValueKey('home-jump-back-in')),
          );
          await _pumpInteraction(tester);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );
  }

  testWidgets(
    'the search bar opens search with what was typed, or searches contents',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture);
        await tester.tap(_bar);
        await _pumpInteraction(tester);
        expect(fixture.searches, [('', false)]);

        await tester.tap(find.byKey(const ValueKey('home-search-deep')));
        await _pumpInteraction(tester);
        expect(fixture.searches.last, ('', true));

        Focus.of(tester.element(find.text('Search pages, notes and more…')))
            .requestFocus();
        await _pumpInteraction(tester);
        await tester.sendKeyEvent(
          LogicalKeyboardKey.keyK,
          physicalKey: PhysicalKeyboardKey.keyK,
          character: 'k',
        );
        await _pumpInteraction(tester);
        expect(fixture.searches.last, ('k', false));
        await tester.sendKeyEvent(
          LogicalKeyboardKey.enter,
          physicalKey: PhysicalKeyboardKey.enter,
        );
        await _pumpInteraction(tester);
        expect(fixture.searches.last, ('', false));
        expect(fixture.searches, hasLength(4));
        expect(fixture.palette.requests, 0);
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'pages open from resume, quick jump and thumbnails; libraries via tabs',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture, size: const Size(1280, 1400));
        for (final key in [
          'home-resume-continue',
          'home-quick-jump-reading',
          'home-jump-card-budget',
        ]) {
          await _tapVisible(tester, find.byKey(ValueKey(key)));
        }
        expect(fixture.opened, ['launch', 'reading', 'budget']);
        expect(fixture.tabs.events, isEmpty);

        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-jump-view-all')),
        );
        final opened = _opened(fixture.tabs.events.single);
        expect(opened.plugin, isA<ViewLibraryPlugin>());
        expect(opened.plugin.pluginType, PluginType.recents);
        expect(opened.view, isNull);
        expect(opened.setLatest, isFalse);
        expect(fixture.menu.latestOpenView, isNull);

        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-jump-favorites')),
        );
        expect(
          find.byKey(const ValueKey('home-jump-card-reading')),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-jump-card-budget')),
          findsNothing,
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-jump-layout')),
        );
        expect(
          find.byKey(const ValueKey('home-jump-row-reading')),
          findsOneWidget,
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-jump-view-all')),
        );
        expect(
          _opened(fixture.tabs.events.last).plugin.pluginType,
          PluginType.favorites,
        );
        // Restore the session choice for later tests.
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-jump-layout')),
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-jump-recent')),
        );
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'marking a reminder done takes it off the list',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture, size: const Size(1280, 1400));
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-agenda-done-reminder:passport')),
        );
        final saved = AppReminder.fromPB(fixture.reminders.updated.single);
        expect(saved.id, 'passport');
        expect(saved.isDone, isTrue);
        final reminders = find.byKey(const ValueKey('home-reminders'));
        expect(
          find.descendant(
            of: reminders,
            matching: find.text('Renew passport'),
          ),
          findsNothing,
        );
        expect(
          find.descendant(of: reminders, matching: find.text('Pay invoices')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'the search bar sits across the cover edge as the cover is resized',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture);
        final cover = find.byKey(const ValueKey('home-cover'));
        double offset() =>
            tester.getRect(_bar).center.dy - tester.getRect(cover).bottom;
        expect(offset().abs(), lessThan(0.5));
        // Half of it lies on the picture, half on the page.
        expect(
          tester.getRect(_bar).top,
          lessThan(tester.getRect(cover).bottom),
        );
        final grip = find.byKey(const ValueKey('page-cover-resize'));
        expect(grip, findsOneWidget);
        expect(
          tester.getRect(grip).bottom,
          lessThanOrEqualTo(tester.getRect(_bar).top),
        );

        final before = tester.getRect(cover).height;
        // Frames between moves, as a real drag has: release commits the
        // height on screen.
        final pointer = await tester.startGesture(
          tester.getCenter(grip),
          kind: PointerDeviceKind.mouse,
        );
        await pointer.moveBy(const Offset(0, 4));
        await tester.pump();
        await pointer.moveBy(const Offset(0, 56));
        await tester.pump();
        await pointer.up();
        await _pumpInteraction(tester);
        expect(tester.getRect(cover).height, closeTo(before + 60, 0.5));
        expect(offset().abs(), lessThan(0.5));
        final stored =
            fixture.pages.peek(localPageId('home', 'fixture-workspace'));
        expect(PageCoverHeight.decode(stored!), closeTo(before + 60, 0.5));

        // Still one tap to search from its new place.
        await tester.tap(_bar);
        await _pumpInteraction(tester);
        expect(fixture.searches, [('', false)]);
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'the weather is read only for a chosen place, in the chosen units',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture, size: const Size(1280, 1400));
        expect(
          find.byKey(const ValueKey('home-weather-add')),
          findsOneWidget,
        );
        expect(fixture.weatherReads, isEmpty);

        await fixture.weather!.setPlace(
          const HomeWeatherPlace(
            name: 'Pune',
            latitude: 18.52,
            longitude: 73.85,
          ),
        );
        await _pumpInteraction(tester);
        expect(fixture.weatherReads, [('Pune', false)]);
        final weather = find.byKey(const ValueKey('home-weather'));
        for (final text in ['21°', 'Pune', 'H 24° · L 14°']) {
          expect(
            find.descendant(of: weather, matching: find.text(text)),
            findsOneWidget,
          );
        }

        await _tapVisible(tester, weather);
        await tester.tap(find.text('Show in °F'));
        await _pumpInteraction(tester);
        expect(fixture.weatherReads.last, ('Pune', true));
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'the calendar chooses the day the events card shows',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture, size: const Size(1280, 1400));
        final calendar = find.byKey(const ValueKey('home-calendar'));
        final events = find.byKey(const ValueKey('home-events'));
        expect(
          find.descendant(
            of: calendar,
            matching: find.textContaining('September 2026'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-calendar-day-2026-09-30')),
          findsOneWidget,
        );

        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-calendar-day-2026-10-02')),
        );
        expect(
          find.descendant(
            of: events,
            matching: find.textContaining('Fri, Oct 2'),
          ),
          findsOneWidget,
        );
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-events-today')),
        );
        expect(find.byKey(const ValueKey('home-events-today')), findsNothing);

        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-calendar-next')),
        );
        expect(
          find.descendant(
            of: calendar,
            matching: find.textContaining('October 2026'),
          ),
          findsOneWidget,
        );
        expect(
          find.byKey(const ValueKey('home-calendar-today')),
          findsOneWidget,
        );
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  for (final missing in ['shell', 'workspace']) {
    testWidgets(
      'missing $missing still renders an honest Home',
      (tester) async {
        final fixture = _Fixture(injectSearch: false);
        final semantics = tester.ensureSemantics();
        try {
          if (missing == 'workspace') fixture.workspace.show(null);
          await _pumpHome(
            tester,
            fixture,
            withShell: missing != 'shell',
            withPalette: false,
          );
          expect(find.textContaining('Good morning'), findsNothing);
          expect(find.byKey(const ValueKey('home-glance')), findsOneWidget);
          // Without a workspace there is no cover to lie across.
          expect(find.byKey(const ValueKey('home-cover')), findsNothing);
          _expectButton(
            tester,
            _bar,
            label: 'Search this workspace',
            enabled: false,
          );
          expect(find.byKey(const ValueKey('home-search-deep')), findsNothing);
          if (missing == 'shell') {
            expect(
              find.byKey(const ValueKey('home-jump-view-all')),
              findsNothing,
            );
          }
          await tester.tap(_bar);
          await _pumpInteraction(tester);
          expect(fixture.searches, isEmpty);
          expect(fixture.tabs.events, isEmpty);
          expect(fixture.storage.accesses, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          semantics.dispose();
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );
  }

  testWidgets(
    'closed tabs reject stale library links without constructing plugins',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture, size: const Size(1280, 1400));
        final viewAll = tester
            .widget<TextButton>(
              find.byKey(const ValueKey('home-jump-view-all')),
            )
            .onPressed!;
        await pumpHomeProfileClose(tester, fixture.tabs.close());
        viewAll();
        await _pumpInteraction(tester);
        expect(fixture.tabs.events, isEmpty);
        expect(fixture.menu.latestOpenView?.id, 'untouched-selection');
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'recent pages survive the workspace reset that follows launch',
    (tester) async {
      final fixture = _Fixture()..recentService = _SharedRecents();
      try {
        await _pumpHome(tester, fixture);
        final resume = find.byKey(const ValueKey('home-resume-title'));
        expect(resume, findsOneWidget);

        // The sidebar resets the shared history as soon as the workspace is
        // known, which empties it until somebody asks again.
        await fixture.recentService!.reset();
        await _pumpInteraction(tester);
        await _pumpInteraction(tester);
        expect(resume, findsOneWidget);
        expect((fixture.recentService! as _SharedRecents).reads, 2);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'switching workspaces reloads recent and favorite pages once',
    (tester) async {
      final fixture = _Fixture();
      try {
        await _pumpHome(tester, fixture);
        expect(fixture.recentReads, 1);
        expect(fixture.favorites.reads, 1);

        // The same workspace, renamed or with a new profile, is not a switch.
        fixture.workspace.show(
          _workspace(name: 'Renamed research'),
          userName: 'Grace Hopper',
        );
        await _pumpInteraction(tester);
        expect(fixture.recentReads, 1);
        expect(fixture.favorites.reads, 1);

        fixture.workspace.show(_workspace(id: 'other', name: 'Other place'));
        await _pumpInteraction(tester);
        expect(fixture.recentReads, 2);
        expect(fixture.favorites.reads, 2);
        expect(
          find.byKey(const ValueKey('home-resume-title')),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  testWidgets(
    'lightweight snapshots and callbacks work without shell providers',
    (tester) async {
      final fixture = _Fixture();
      final searches = <String>[];
      final opened = <String>[];
      try {
        await _pumpHome(
          tester,
          fixture,
          withShell: false,
          withPalette: false,
          page: WorkspaceHomePage(
            workspace: _workspace(id: 'injected-root', name: 'Offline fixture'),
            userName: 'Reader Person',
            onNavigate: fixture.tabs.events.add,
            onSearch: (query, _) => searches.add(query),
            onOpenView: (view) => opened.add(view.id),
            services: fixture.services,
          ),
        );
        expect(find.byKey(const ValueKey('home-cover')), findsOneWidget);
        await tester.tap(_bar);
        await _tapVisible(
          tester,
          find.byKey(const ValueKey('home-resume-continue')),
        );
        expect(searches, ['']);
        expect(opened, ['launch']);
        expect(fixture.searches, isEmpty);
        expect(fixture.opened, isEmpty);
        expect(fixture.palette.requests, 0);
        expect(fixture.storage.accesses, isEmpty);
        expect(tester.takeException(), isNull);
      } finally {
        await fixture.dispose(tester);
      }
    },
    timeout: _timeout,
  );

  group('customizing Home', () {
    testWidgets(
      'sections move up and down, and come back from the add menu',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpHome(tester, fixture, size: const Size(1440, 3600));
          final store = fixture.arrangement!;
          expect(store.arrangement, HomeArrangement.defaults());
          expect(
            find.byKey(const ValueKey('home-customize-bar')),
            findsNothing,
          );
          expect(_frame('glance'), findsNothing);

          await _tapVisible(tester, _customize);
          expect(
            find.byKey(const ValueKey('home-customize-bar')),
            findsOneWidget,
          );
          for (final part in HomeBlock.values) {
            expect(_frame(part.name), findsOneWidget);
          }
          // Up and down trade places with the nearest section sharing its
          // columns: none is above the glance card or below the reminders,
          // and none shares the columns of the pages worked on lately.
          expect(_frameButton(tester, 'up', 'glance').onPressed, isNull);
          expect(_frameButton(tester, 'down', 'reminders').onPressed, isNull);
          expect(_frameButton(tester, 'up', 'jumpBackIn').onPressed, isNull);
          expect(_frameButton(tester, 'down', 'jumpBackIn').onPressed, isNull);

          await _tapVisible(tester, _frameButtonFinder('down', 'glance'));
          expect(
            store.arrangement.blocks,
            ['jumpBackIn', 'calendar', 'glance', 'events', 'reminders'],
          );
          expect(
            tester.getRect(_frame('glance')).top,
            greaterThan(tester.getRect(_frame('calendar')).bottom),
          );
          await _tapVisible(tester, _frameButtonFinder('up', 'glance'));
          expect(
            store.arrangement.blocks,
            ['jumpBackIn', 'glance', 'calendar', 'events', 'reminders'],
          );
          expect(
            tester.getRect(_frame('glance')).bottom,
            lessThan(tester.getRect(_frame('calendar')).top),
          );

          await _tapVisible(tester, _frameButtonFinder('remove', 'reminders'));
          expect(store.arrangement.contains('reminders'), isFalse);
          expect(store.arrangement.missingBlocks, [HomeBlock.reminders]);
          expect(find.byKey(const ValueKey('home-reminders')), findsNothing);

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('home-customize-add')),
          );
          await tester.tap(find.text('Reminders').last);
          await _pumpInteraction(tester);
          // Back where it first was, after everything else.
          expect(store.arrangement.blocks.last, 'reminders');
          expect(
            store.arrangement.placementOf('reminders'),
            HomeBlock.reminders.defaultPlacement,
          );

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('home-customize-done')),
          );
          expect(
            find.byKey(const ValueKey('home-customize-bar')),
            findsNothing,
          );
          expect(_frame('glance'), findsNothing);
          // Still a rail beside the pages worked on lately.
          final pages = tester.getRect(
            find.byKey(const ValueKey('home-jump-back-in')),
          );
          for (final part in ['glance', 'calendar', 'events', 'reminders']) {
            expect(
              tester.getTopLeft(find.byKey(ValueKey('home-$part'))).dx,
              greaterThan(pages.right),
            );
          }
          expect(fixture.storage.accesses, isEmpty);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'a section is dragged anywhere, and the others make way',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpHome(tester, fixture, size: const Size(1440, 4200));
          await _tapVisible(tester, _customize);
          final store = fixture.arrangement!;

          // Above the pages worked on lately, at the start edge.
          await _dragBetween(
            tester,
            from: tester.getCenter(_frame('events')),
            to: tester.getTopLeft(_frame('jumpBackIn')) + const Offset(160, 20),
          );
          expect(
            store.arrangement.placementOf('events'),
            const HomeBlockPlacement(span: 4),
          );
          expect(
            store.arrangement.blocks,
            ['glance', 'events', 'jumpBackIn', 'calendar', 'reminders'],
          );
          // The pages made way below it; the rail stayed where it was.
          var events = tester.getRect(_frame('events'));
          expect(
            tester.getRect(_frame('jumpBackIn')).top,
            greaterThan(events.bottom),
          );
          expect(events.right, lessThan(tester.getRect(_frame('glance')).left));
          expect(
            tester.getRect(_frame('reminders')).top,
            greaterThan(tester.getRect(_frame('calendar')).bottom),
          );

          // Below the reminders, back in the rail.
          await _dragBetween(
            tester,
            from: tester.getCenter(_frame('events')),
            to: tester.getRect(_frame('reminders')).bottomCenter +
                const Offset(0, 60),
          );
          expect(
            store.arrangement.placementOf('events'),
            const HomeBlockPlacement(column: 8, span: 4),
          );
          expect(store.arrangement.blocks.last, 'events');
          events = tester.getRect(_frame('events'));
          expect(
            events.top,
            greaterThan(tester.getRect(_frame('reminders')).bottom),
          );
          // With nothing above it at the start edge, the pages rose again.
          expect(
            tester.getRect(_frame('jumpBackIn')).top,
            tester.getRect(_frame('glance')).top,
          );

          // A drag let go where it began changes nothing.
          final before = store.arrangement;
          await _dragBetween(
            tester,
            from: tester.getCenter(_frame('glance')),
            to: tester.getCenter(_frame('glance')) - const Offset(0, 24),
          );
          expect(store.arrangement, same(before));
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'sections are resized from their edges, and fit their content again',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpHome(tester, fixture, size: const Size(1440, 4200));
          await _tapVisible(tester, _customize);
          final store = fixture.arrangement!;
          final step =
              (tester.getSize(find.byKey(const ValueKey('home-grid'))).width +
                      24) /
                  12;

          // Narrower from its end edge, by whole columns.
          await tester.drag(_grip('end', 'jumpBackIn'), Offset(-2 * step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('jumpBackIn'),
            const HomeBlockPlacement(span: 6),
          );
          expect(
            tester.getRect(_frame('jumpBackIn')).width,
            moreOrLessEquals(6 * step - 24, epsilon: 0.01),
          );

          // While it is resized, the sections below make way; nothing is kept
          // until it is let go, and let go where it began, nothing changes.
          final grip = tester.getCenter(_grip('bottom', 'calendar'));
          final eventsTop = tester.getRect(_frame('events')).top;
          final resize = await tester.startGesture(
            grip,
            kind: PointerDeviceKind.mouse,
          );
          await tester.pump();
          for (var i = 1; i <= 6; i++) {
            await resize.moveTo(grip + Offset(0, 30.0 * i));
            await tester.pump();
          }
          await _pumpInteraction(tester);
          expect(
            tester.getRect(_frame('events')).top,
            greaterThan(eventsTop + 120),
          );
          expect(store.arrangement.placementOf('calendar').rows, isNull);
          await resize.moveTo(grip);
          await tester.pump();
          await resize.up();
          await _pumpInteraction(tester);
          await resize.removePointer();
          expect(
            store.arrangement.placementOf('calendar'),
            HomeBlock.calendar.defaultPlacement,
          );
          expect(tester.getRect(_frame('events')).top, eventsTop);

          // Taller from its bottom edge, by whole height units. Its height
          // is kept from then on, until it fits its content again.
          final calendar = find.byKey(const ValueKey('home-calendar'));
          final fitted = tester.getSize(calendar).height;
          expect(_frameButtonFinder('fit', 'calendar'), findsNothing);
          await tester.drag(_grip('bottom', 'calendar'), const Offset(0, 100));
          await _pumpInteraction(tester);
          final rows = homeGridRowsFor(fitted + 100, 46, 14, minimum: 3);
          expect(store.arrangement.placementOf('calendar').rows, rows);
          expect(
            tester.getSize(calendar).height,
            homeGridRowsHeight(rows, 46, 14),
          );
          await _tapVisible(tester, _frameButtonFinder('fit', 'calendar'));
          expect(store.arrangement.placementOf('calendar').rows, isNull);
          expect(tester.getSize(calendar).height, fitted);
          expect(_frameButtonFinder('fit', 'calendar'), findsNothing);

          // Both at once from the corner.
          final events =
              tester.getSize(find.byKey(const ValueKey('home-events')));
          await tester.drag(_grip('bottomEnd', 'events'), Offset(-step, 80));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('events'),
            HomeBlockPlacement(
              column: 8,
              span: 3,
              rows: homeGridRowsFor(events.height + 80, 46, 14, minimum: 3),
            ),
          );

          // Never narrower than a section reads well in.
          await tester.drag(_grip('end', 'glance'), Offset(-6 * step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('glance'),
            HomeBlockPlacement(
              column: 8,
              span: HomeBlock.glance.minimumSpan,
            ),
          );

          // From the start edge too: a section by the grid's end edge grows
          // towards the start, its end edge staying put. It still shares no
          // columns with the pages, so it stays beside them, under the glance.
          final grid = tester.getRect(find.byKey(const ValueKey('home-grid')));
          await tester.drag(_grip('start', 'calendar'), Offset(-2 * step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('calendar'),
            const HomeBlockPlacement(column: 6, span: 6),
          );
          final widened = tester.getRect(_frame('calendar'));
          expect(widened.right, moreOrLessEquals(grid.right, epsilon: 0.01));
          expect(widened.width, moreOrLessEquals(6 * step - 24, epsilon: 0.01));
          expect(
            widened.left,
            greaterThan(tester.getRect(_frame('jumpBackIn')).right),
          );
          expect(
            widened.top,
            moreOrLessEquals(
              tester.getRect(_frame('glance')).bottom + 14,
              epsilon: 0.01,
            ),
          );
          // Pushed in as far as it goes, it keeps its fewest columns.
          await tester.drag(_grip('start', 'calendar'), Offset(8 * step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('calendar'),
            HomeBlockPlacement(
              column: homeGridColumns - HomeBlock.calendar.minimumSpan,
              span: HomeBlock.calendar.minimumSpan,
            ),
          );

          // And both at once from the other bottom corner.
          final pinned =
              tester.getSize(find.byKey(const ValueKey('home-events')));
          await tester.drag(_grip('bottomStart', 'events'), Offset(-step, 80));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('events'),
            HomeBlockPlacement(
              column: 7,
              span: 4,
              rows: homeGridRowsFor(pinned.height + 80, 46, 14, minimum: 3),
            ),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'the layout menu moves and resizes a section without dragging',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpHome(tester, fixture, size: const Size(1440, 4200));
          await _tapVisible(tester, _customize);
          final store = fixture.arrangement!;
          HomeBlockPlacement calendar() =>
              store.arrangement.placementOf('calendar');

          await _choose(tester, 'calendar', 'Move left');
          expect(calendar(), const HomeBlockPlacement(column: 7, span: 4));
          // It shares a column with the pages now, so it goes below them.
          expect(
            tester.getRect(_frame('calendar')).top,
            greaterThan(tester.getRect(_frame('jumpBackIn')).bottom),
          );
          await _choose(tester, 'calendar', 'Wider');
          expect(calendar(), const HomeBlockPlacement(column: 7, span: 5));
          await _choose(tester, 'calendar', 'Narrower');
          expect(calendar(), const HomeBlockPlacement(column: 7, span: 4));
          await _choose(tester, 'calendar', 'Move right');
          expect(calendar(), HomeBlock.calendar.defaultPlacement);

          await _choose(tester, 'calendar', 'Taller');
          final rows = calendar().rows;
          expect(rows, isNotNull);
          await _choose(tester, 'calendar', 'Shorter');
          expect(calendar().rows, rows! - 1);
          await _choose(tester, 'calendar', 'Fit to content');
          expect(calendar().rows, isNull);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'in narrower windows sections pair up, then stack, in reading order',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpHome(tester, fixture, size: const Size(700, 4200));
          final store = fixture.arrangement!;
          Rect part(String name) =>
              tester.getRect(find.byKey(ValueKey('home-$name')));
          // Two narrow sections that follow each other share a row; the
          // rest take the whole width.
          expect(part('glance').bottom, lessThan(part('jump-back-in').top));
          expect(part('calendar').top, part('events').top);
          expect(part('calendar').right, lessThan(part('events').left));
          expect(
            part('reminders').top,
            greaterThan(
              math.max(part('calendar').bottom, part('events').bottom),
            ),
          );
          expect(part('reminders').width, part('glance').width);

          // Arranging follows the reading order; widths and columns are
          // kept for wider windows, so there is nothing to drag sideways,
          // and the hint says so.
          await _tapVisible(tester, _customize);
          expect(
            find.text(
              'Drag sections to reorder them and pull their bottom edges to '
              'change their height. Widen the window to change their widths.',
            ),
            findsOneWidget,
          );
          for (final edge in ['start', 'end', 'bottomStart', 'bottomEnd']) {
            expect(_grip(edge, 'glance'), findsNothing);
          }
          expect(_grip('bottom', 'glance'), findsOneWidget);
          await _tapVisible(tester, _frameButtonFinder('up', 'jumpBackIn'));
          expect(
            store.arrangement.blocks,
            ['jumpBackIn', 'glance', 'calendar', 'events', 'reminders'],
          );
          expect(
            store.arrangement.placementOf('jumpBackIn'),
            HomeBlock.jumpBackIn.defaultPlacement,
          );
          await _choose(tester, 'glance', 'Taller');
          expect(store.arrangement.placementOf('glance').rows, isNotNull);

          await _pumpHome(tester, fixture, size: const Size(500, 4200));
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('home-customize-done')),
          );
          final left = part('glance').left;
          for (final name in ['jump-back-in', 'calendar', 'events']) {
            expect(part(name).left, left);
          }
          expect(part('calendar').bottom, lessThan(part('events').top));
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'a medium window keeps the grid, resizable from every side, and '
      'sections never get too narrow to read',
      (tester) async {
        final fixture = _Fixture()
          ..seededArrangement = HomeArrangement.defaults().place(
            'calendar',
            const HomeBlockPlacement(column: 9, span: 3),
          );
        try {
          // About as wide as Home is beside a half-screen window's edges.
          await _pumpHome(tester, fixture, size: const Size(830, 4200));
          await _tapVisible(tester, _customize);
          final store = fixture.arrangement!;
          final grid = tester.getRect(find.byKey(const ValueKey('home-grid')));
          final step = (grid.width + 24) / 12;
          expect(homeGridReadableSpan(grid.width), 4);
          expect(
            find.text(
              'Drag sections anywhere and pull their edges to resize them, '
              'or add widgets from dashboards.',
            ),
            findsOneWidget,
          );
          for (final edge in ['start', 'end', 'bottomStart', 'bottomEnd']) {
            expect(_grip(edge, 'calendar'), findsOneWidget);
          }

          // Three columns would be too narrow here, so it is drawn across
          // four, against the end edge; what is stored is left alone.
          final shown = tester.getRect(_frame('calendar'));
          expect(shown.width, moreOrLessEquals(4 * step - 24, epsilon: 0.01));
          expect(shown.right, moreOrLessEquals(grid.right, epsilon: 0.01));
          expect(
            store.arrangement.placementOf('calendar'),
            const HomeBlockPlacement(column: 9, span: 3),
          );

          // Wider from its start edge, then back in, never under four.
          await tester.drag(_grip('start', 'calendar'), Offset(-step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('calendar'),
            const HomeBlockPlacement(column: 7, span: 5),
          );
          await tester.drag(_grip('start', 'calendar'), Offset(4 * step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('calendar'),
            const HomeBlockPlacement(column: 8, span: 4),
          );

          // Narrower from the other side, and both ways from a corner.
          await tester.drag(_grip('end', 'jumpBackIn'), Offset(-2 * step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('jumpBackIn'),
            const HomeBlockPlacement(span: 6),
          );
          final events =
              tester.getSize(find.byKey(const ValueKey('home-events')));
          await tester.drag(_grip('bottomStart', 'events'), Offset(-step, 80));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('events'),
            HomeBlockPlacement(
              column: 7,
              span: 5,
              rows: homeGridRowsFor(events.height + 80, 46, 14, minimum: 3),
            ),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'right to left, Home mirrors its columns',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpHome(
            tester,
            fixture,
            size: const Size(1440, 4200),
            direction: ui.TextDirection.rtl,
          );
          final store = fixture.arrangement!;
          final pages = tester.getRect(
            find.byKey(const ValueKey('home-jump-back-in')),
          );
          expect(
            tester.getRect(find.byKey(const ValueKey('home-glance'))).right,
            lessThan(pages.left),
          );

          await _tapVisible(tester, _customize);
          final step =
              (tester.getSize(find.byKey(const ValueKey('home-grid'))).width +
                      24) /
                  12;
          // The end edge is on the left.
          await tester.drag(_grip('end', 'jumpBackIn'), Offset(2 * step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('jumpBackIn'),
            const HomeBlockPlacement(span: 6),
          );
          // Right is towards the start edge.
          await _choose(tester, 'calendar', 'Move right');
          expect(
            store.arrangement.placementOf('calendar'),
            const HomeBlockPlacement(column: 7, span: 4),
          );
          // Dragged to the left edge: the last columns.
          await _dragBetween(
            tester,
            from: tester.getCenter(_frame('glance')),
            to: tester.getCenter(_frame('glance')) - Offset(step, 0),
          );
          expect(
            store.arrangement.placementOf('glance'),
            HomeBlock.glance.defaultPlacement,
          );
          await _dragBetween(
            tester,
            from: tester.getCenter(_frame('glance')),
            to: tester.getCenter(_frame('glance')) + Offset(2 * step, 0),
          );
          expect(
            store.arrangement.placementOf('glance'),
            const HomeBlockPlacement(column: 6, span: 4),
          );
          // The start edge is on the right, and pulled right it grows.
          await tester.drag(_grip('start', 'calendar'), Offset(step, 0));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.placementOf('calendar'),
            const HomeBlockPlacement(column: 6, span: 5),
          );
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'a dashboard widget works on Home and is configured, sized and removed',
      (tester) async {
        const note = DashboardWidgetSpec(
          id: 'w-note',
          type: 'text',
          title: 'Groceries',
          placement: DashboardPlacement(rowSpan: 3),
          settings: {'text': 'Remember the milk'},
        );
        const block = 'widget:w-note';
        final fixture = _Fixture()
          ..seededArrangement = HomeArrangement.defaults().addWidget(note);
        try {
          await _pumpHome(tester, fixture, size: const Size(1440, 4200));
          final store = fixture.arrangement!;
          final card = find.byKey(const ValueKey('home-widget-w-note'));
          // A narrow widget joins the rail.
          expect(
            tester.getTopLeft(card).dx,
            greaterThan(
              tester
                  .getTopRight(find.byKey(const ValueKey('home-jump-back-in')))
                  .dx,
            ),
          );
          expect(
            find.descendant(of: card, matching: find.text('Remember the milk')),
            findsOneWidget,
          );
          // Three height units, exactly as tall as on a dashboard.
          expect(tester.getSize(card).height, 3 * 46 + 2 * 14);

          await _tapVisible(tester, _customize);
          expect(
            tester
                .widget<Text>(
                  find.byKey(const ValueKey('home-block-label-$block')),
                )
                .data,
            'Groceries',
          );

          // Its settings are the dashboard's own panel.
          await _tapVisible(tester, _frameButtonFinder('configure', block));
          final settings =
              find.byKey(const ValueKey('home-widget-settings-w-note'));
          expect(settings, findsOneWidget);
          await tester.tap(
            find.descendant(of: settings, matching: find.byTooltip('Close')),
          );
          await _pumpInteraction(tester);
          expect(settings, findsNothing);

          // Its height follows the grip, in whole height units; a widget
          // always keeps one, so there is nothing to fit.
          final grip = _grip('bottom', block);
          await tester.ensureVisible(grip);
          await _pumpInteraction(tester);
          await tester.drag(grip, const Offset(0, 120));
          await _pumpInteraction(tester);
          expect(
            store.arrangement.widgets.widgetById('w-note')!.placement.rowSpan,
            5,
          );
          expect(tester.getSize(card).height, 5 * 46 + 4 * 14);
          expect(_frameButtonFinder('fit', block), findsNothing);

          // Taken off Home, a widget goes with its settings.
          await _tapVisible(tester, _frameButtonFinder('remove', block));
          expect(store.arrangement.widgets.widgetCount, 0);
          expect(store.arrangement.blocks, HomeArrangement.defaults().blocks);
          expect(_frame(block), findsNothing);
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    testWidgets(
      'a widget from the dashboard library is added to Home',
      (tester) async {
        final fixture = _Fixture();
        try {
          await _pumpHome(tester, fixture, size: const Size(1440, 3600));
          await _tapVisible(tester, _customize);
          await _tapVisible(
            tester,
            find.byKey(const ValueKey('home-customize-add')),
          );
          await tester.tap(find.text('Widget from dashboards…'));
          await _pumpInteraction(tester);
          await _pumpInteraction(tester);

          final definition =
              DashboardWidgetRegistry.definitionFor('sticky_note')!;
          await tester.enterText(
            find.byType(TextField).last,
            definition.label(),
          );
          await tester.testTextInput.receiveAction(TextInputAction.done);
          await _pumpInteraction(tester);
          await _pumpInteraction(tester);

          final store = fixture.arrangement!;
          final spec = store.arrangement.widgets.allWidgets.single;
          expect(spec.type, 'sticky_note');
          final block = homeWidgetBlockId(spec.id);
          expect(store.arrangement.blocks.last, block);
          // A wide widget starts at the start edge, a narrow one by the rail.
          final span = definition.defaultColumnSpan;
          expect(
            store.arrangement.placementOf(block),
            HomeBlockPlacement(
              column: span >= 6 ? 0 : 12 - span,
              span: span,
              rows: spec.placement.rowSpan,
            ),
          );
          expect(_frame(block), findsOneWidget);

          await _tapVisible(
            tester,
            find.byKey(const ValueKey('home-customize-done')),
          );
          expect(
            find.byKey(ValueKey('home-widget-${spec.id}')),
            findsOneWidget,
          );
          expect(tester.takeException(), isNull);
        } finally {
          await fixture.dispose(tester);
        }
      },
      timeout: _timeout,
    );

    for (final appearance in ['light', 'dark', 'paper']) {
      testWidgets(
        '$appearance: customizing stays usable wide, narrow, at 2x and RTL',
        (tester) async {
          final fixture = _Fixture()
            ..seededArrangement = HomeArrangement.defaults()
                .addWidget(
                  const DashboardWidgetSpec(
                    id: 'w-note',
                    type: 'text',
                    title: 'A note with a rather long title to wrap',
                    placement: DashboardPlacement(rowSpan: 3),
                    settings: {'text': 'Remember the milk'},
                  ),
                )
                .place(
                  'calendar',
                  const HomeBlockPlacement(column: 8, span: 4, rows: 3),
                )
                .place(
                  'jumpBackIn',
                  const HomeBlockPlacement(span: 8, rows: 4),
                );
          try {
            for (final (size, scale, direction) in [
              (const Size(1440, 1000), 1.0, ui.TextDirection.ltr),
              (const Size(1440, 1000), 1.0, ui.TextDirection.rtl),
              (const Size(2400, 1400), 2.0, ui.TextDirection.ltr),
              (const Size(900, 700), 1.0, ui.TextDirection.rtl),
              (const Size(360, 640), 2.0, ui.TextDirection.ltr),
              (const Size(320, 600), 2.0, ui.TextDirection.rtl),
            ]) {
              await _pumpHome(
                tester,
                fixture,
                appearance: appearance,
                size: size,
                scale: scale,
                direction: direction,
              );
              if (find
                  .byKey(const ValueKey('home-customize-bar'))
                  .evaluate()
                  .isEmpty) {
                await _tapVisible(tester, _customize);
              }
              expect(
                find.byKey(const ValueKey('home-customize-bar')),
                findsOneWidget,
              );
              // Home is at most 1280 wide, inside the page's margins.
              final inset = size.width < 360
                  ? 16
                  : size.width < 600
                      ? 24
                      : 48;
              final wide =
                  math.min(1280, size.width) - 2 * inset >= 660 * scale;
              expect(_frame('glance'), findsOneWidget);
              for (final edge in ['start', 'end', 'bottomStart']) {
                expect(
                  _grip(edge, 'glance'),
                  wide ? findsOneWidget : findsNothing,
                );
              }
              // Every section can be reached from its layout menu, however
              // little room its heading has.
              expect(_frameButtonFinder('more', 'glance'), findsOneWidget);
              expect(tester.takeException(), isNull);

              // The sections whose height is pinned scroll what doesn't fit.
              await tester.ensureVisible(
                find.byKey(const ValueKey('home-jump-back-in')),
              );
              await _pumpInteraction(tester);
              expect(tester.takeException(), isNull);
            }
            await _tapVisible(
              tester,
              find.byKey(const ValueKey('home-customize-done')),
            );
            expect(tester.takeException(), isNull);
          } finally {
            await fixture.dispose(tester);
          }
        },
        timeout: _timeout,
      );
    }
  });
}

final _customize = find.byKey(const ValueKey('home-customize'));

Finder _frame(String block) => find.byKey(ValueKey('home-frame-$block'));

Finder _grip(String edge, String block) =>
    find.byKey(ValueKey('home-grip-$edge-$block'));

Finder _frameButtonFinder(String action, String block) =>
    find.byKey(ValueKey('home-block-$action-$block'));

IconButton _frameButton(WidgetTester tester, String action, String block) =>
    tester.widget<IconButton>(_frameButtonFinder(action, block));

/// Picks [label] from the layout menu of [block].
Future<void> _choose(WidgetTester tester, String block, String label) async {
  await _tapVisible(tester, _frameButtonFinder('more', block));
  await tester.tap(find.text(label).last);
  await _pumpInteraction(tester);
}

/// A mouse drag that crosses the slop first, then travels in steps so each
/// target along the way hears the pointer, as a real drag does.
Future<void> _dragBetween(
  WidgetTester tester, {
  required Offset from,
  required Offset to,
}) async {
  final gesture =
      await tester.startGesture(from, kind: PointerDeviceKind.mouse);
  await tester.pump();
  final start = from + const Offset(0, 24);
  await gesture.moveTo(start);
  await tester.pump();
  const steps = 10;
  for (var step = 1; step <= steps; step++) {
    await gesture.moveTo(Offset.lerp(start, to, step / steps)!);
    await tester.pump();
  }
  await gesture.up();
  await _pumpInteraction(tester);
  await gesture.removePointer();
}

final _bar = find.byKey(const ValueKey('home-search-bar'));

void _expectButton(
  WidgetTester tester,
  Finder finder, {
  required String label,
  bool enabled = true,
}) {
  final node = tester.getSemantics(finder);
  final data = node.getSemanticsData();
  expect(node.attached, isTrue);
  expect(data.hasFlag(SemanticsFlag.isButton), isTrue);
  expect(data.hasFlag(SemanticsFlag.hasEnabledState), isTrue);
  expect(data.hasFlag(SemanticsFlag.isEnabled), enabled);
  expect(data.label, contains(label));
}

({Plugin plugin, ViewPB? view, bool setLatest}) _opened(TabsEvent event) =>
    event.maybeWhen(
      openPlugin: (plugin, view, setLatest) =>
          (plugin: plugin, view: view, setLatest: setLatest),
      orElse: () => throw StateError('Expected only plugin navigation'),
    );

Future<void> _pumpInteraction(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 200));
}

Future<void> _tapVisible(WidgetTester tester, Finder finder) async {
  await tester.ensureVisible(finder);
  await _pumpInteraction(tester);
  await tester.tap(finder);
  await _pumpInteraction(tester);
}

Future<void> _pumpHome(
  WidgetTester tester,
  _Fixture fixture, {
  String appearance = 'paper',
  Widget page = const BlankPage(),
  Size size = const Size(1280, 900),
  double scale = 1,
  ui.TextDirection direction = ui.TextDirection.ltr,
  bool withShell = true,
  bool withPalette = true,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  Widget child = WorkspaceHomeScope(services: fixture.services, child: page);
  if (withPalette) {
    child = CommandPalette(notifier: fixture.palette, child: child);
  }
  if (withShell) {
    child = MultiBlocProvider(
      providers: [
        BlocProvider<UserWorkspaceBloc>.value(value: fixture.workspace),
        BlocProvider<TabsBloc>.value(value: fixture.tabs),
      ],
      child: child,
    );
  }
  await tester.pumpWidget(
    EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      startLocale: const Locale('en', 'US'),
      fallbackLocale: const Locale('en', 'US'),
      path: 'assets/translations',
      saveLocale: false,
      assetLoader: const _Translations(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: context.locale,
          supportedLocales: context.supportedLocales,
          localizationsDelegates: context.localizationDelegates,
          theme: vividIconTestTheme(appearance),
          themeAnimationDuration: Duration.zero,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(scale),
            ),
            child: Directionality(textDirection: direction, child: child!),
          ),
          home: Scaffold(
            body: DefaultIconStyleScope(styles: fixture.styles, child: child),
          ),
        ),
      ),
    ),
  );
  await _pumpInteraction(tester);
  await tester.pump();
}

class _Translations extends AssetLoader {
  const _Translations();
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

UserWorkspacePB _workspace({
  String id = 'fixture-workspace',
  String name = 'Research',
}) =>
    UserWorkspacePB(workspaceId: id, name: name, role: AFRolePB.Owner);

ViewPB _view(String id, String name) => ViewPB(
      id: id,
      name: name,
      parentViewId: 'space',
      layout: ViewLayoutPB.Document,
    );

Int64 _stamp(Duration ago) =>
    Int64(_now.subtract(ago).millisecondsSinceEpoch ~/ 1000);

List<SectionViewPB> _recentSections() => [
      SectionViewPB(
        item: _view('launch', 'Launch plan'),
        timestamp: _stamp(const Duration(minutes: 2)),
      ),
      SectionViewPB(
        item: _view('budget', 'Budget'),
        timestamp: _stamp(const Duration(hours: 3)),
      ),
      SectionViewPB(
        item: _view('notes', 'Meeting notes'),
        timestamp: _stamp(const Duration(days: 1)),
      ),
    ];

class _WorkspaceBloc extends Cubit<UserWorkspaceState>
    implements UserWorkspaceBloc {
  _WorkspaceBloc() : super(_state(_workspace()));

  static UserWorkspaceState _state(
    UserWorkspacePB? workspace, [
    String name = 'Ada Lovelace',
  ]) =>
      UserWorkspaceState(
        currentWorkspace: workspace,
        userProfile: UserProfilePB(
          id: Int64(7),
          name: name,
          email: 'private@example.invalid',
        ),
      );

  void show(UserWorkspacePB? workspace, {String userName = 'Ada Lovelace'}) =>
      emit(_state(workspace, userName));

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records navigation without initializing plugins or mounting backend pages.
class _TabsBloc extends Cubit<TabsState> implements TabsBloc {
  _TabsBloc() : super(TabsState(pageManagers: []));
  final events = <TabsEvent>[];
  @override
  void add(TabsEvent event) => events.add(event);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Records the real CommandPalette.toggle request, not its backend-owned modal.
class _PaletteRequests extends ValueNotifier<CommandPaletteNotifierValue> {
  _PaletteRequests() : super(CommandPaletteNotifierValue());
  CommandPaletteNotifierValue? _requested;
  int requests = 0;
  @override
  CommandPaletteNotifierValue get value => _requested ?? super.value;
  @override
  set value(CommandPaletteNotifierValue next) {
    _requested = next;
    requests++;
  }
}

class _NoStorage extends Fake implements KeyValueStorage {
  final accesses = <Symbol>[];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    accesses.add(invocation.memberName);
    return super.noSuchMethod(invocation);
  }
}

/// The shared recent-pages cache without its backend: a reset empties it and
/// leaves it idle until it is asked again, as the real one does.
class _SharedRecents extends CachedRecentService {
  bool _armed = false;
  int reads = 0;

  @override
  Future<List<SectionViewPB>> recentViews() async {
    if (_armed) return notifier.value;
    _armed = true;
    reads++;
    await Future<void>.delayed(Duration.zero);
    notifier.value = _recentSections();
    return notifier.value;
  }

  @override
  Future<void> reset() async {
    _armed = false;
    notifier.value = const [];
  }
}

class _Notifications extends Fake implements RustStreamReceiver {
  _Notifications(this.observable);
  @override
  final StreamController<SubscribeObject> observable;
}

class _Favorites extends FavoriteService {
  final toggled = <String>[];
  final pinned = <String, bool>{};
  int reads = 0;

  @override
  Future<FlowyResult<RepeatedFavoriteViewPB, FlowyError>>
      readFavorites() async {
    reads++;
    return FlowyResult.success(
      RepeatedFavoriteViewPB(
        items: [
          SectionViewPB(
            item: _view('reading', 'Reading list')
              ..extra = '{"is_pinned":true}',
            timestamp: _stamp(const Duration(days: 3)),
          ),
          SectionViewPB(
            item: _view('launch', 'Launch plan'),
            timestamp: _stamp(const Duration(days: 9)),
          ),
        ],
      ),
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> toggleFavorite(String viewId) async {
    toggled.add(viewId);
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<void, FlowyError>> pinOrUnpinFavorite(
    ViewPB view,
    bool isPinned,
  ) async {
    pinned[view.id] = isPinned;
    return FlowyResult.success(null);
  }
}

class _Reminders implements IReminderService {
  final updated = <ReminderPB>[];

  static AppReminder _reminder(
    String id,
    String title,
    DateTime at, [
    ReminderPriority priority = ReminderPriority.none,
  ]) =>
      AppReminder(
        id: id,
        title: title,
        message: '',
        scheduledAt: at,
        priority: priority,
      );

  final _stored = [
    _reminder('review', 'Design review', DateTime(2026, 9, 30, 11)),
    _reminder(
      'invoices',
      'Pay invoices',
      DateTime(2026, 9, 30, 17),
      ReminderPriority.high,
    ),
    _reminder(
      'passport',
      'Renew passport',
      DateTime(2026, 9, 28, 9),
      ReminderPriority.low,
    ),
  ];

  @override
  Future<FlowyResult<List<ReminderPB>, FlowyError>> fetchReminders() async =>
      FlowyResult.success([for (final reminder in _stored) reminder.toPB()]);

  @override
  Future<FlowyResult<void, FlowyError>> updateReminder({
    required ReminderPB reminder,
  }) async {
    updated.add(reminder);
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<void, FlowyError>> addReminder({
    required ReminderPB reminder,
  }) async =>
      FlowyResult.success(null);

  @override
  Future<FlowyResult<void, FlowyError>> removeReminder({
    required String reminderId,
  }) async =>
      FlowyResult.success(null);
}

class _Previews extends FolderGalleryPreviewLoader {
  @override
  Future<FolderGalleryPreview> load({
    required ViewPB view,
    required WorkspaceExplorerItem item,
  }) async =>
      FolderGalleryPreview(
        kind: FolderGalleryPreviewKind.document,
        blocks: [
          FolderGalleryPreviewBlock(
            kind: FolderGalleryPreviewBlockKind.paragraph,
            runs: [FolderGalleryTextRun(text: 'Outline for ${view.name}.')],
          ),
        ],
        wordCount: 1420,
        readingMinutes: 7,
        tags: const [],
        fileTypeLabel: 'PAGE',
      );
}

class _Fixture {
  _Fixture({bool injectSearch = true}) : _injectSearch = injectSearch {
    getIt.pushNewScope();
    final sandbox = PluginSandbox()
      ..registerPlugin(
        PluginType.recents,
        ViewLibraryPluginBuilder(ViewLibrary.recents),
      )
      ..registerPlugin(
        PluginType.favorites,
        ViewLibraryPluginBuilder(ViewLibrary.favorites),
      );
    getIt.registerSingleton<PluginSandbox>(sandbox);
    getIt.registerSingleton<MenuSharedState>(menu);
    getIt.registerSingleton<KeyValueStorage>(storage);
    RustStreamReceiver.shared = _Notifications(notifications);
  }

  final bool _injectSearch;
  final workspace = _WorkspaceBloc();
  final tabs = _TabsBloc();
  final palette = _PaletteRequests();
  final storage = _NoStorage();
  final menu = MenuSharedState(view: ViewPB(id: 'untouched-selection'));
  final styles = ValueNotifier(DefaultIconStyle.vivid);
  final notifications = StreamController<SubscribeObject>.broadcast();
  final previousReceiver = RustStreamReceiver.shared;
  final reminders = _Reminders();
  late final store = ReminderStore(
    service: reminders,
    refreshEvery: const Duration(days: 1),
  );
  final favorites = _Favorites();
  final live = ValueNotifier<List<SectionViewPB>>(const []);
  final removedRecents = <String>[];

  /// The shared recent-pages cache, when a test wants the real reset path.
  CachedRecentService? recentService;
  final searches = <(String, bool)>[];
  final opened = <String>[];
  final pages = LocalPageStore(persist: false);
  final weatherReads = <(String, bool)>[];
  HomeWeatherSource? weather;
  int recentReads = 0;

  /// What Home starts arranged as; never read from or written to storage.
  HomeArrangement? seededArrangement;
  HomeArrangementStore? arrangement;

  late final services = WorkspaceHomeServices(
    now: () => _now,
    pages: pages,
    arrangement: () => arrangement = HomeArrangementStore(persist: false)
      ..update(seededArrangement ?? HomeArrangement.defaults()),
    weather: () => weather = HomeWeatherSource(
      persist: false,
      fetch: (place, fahrenheit) async {
        weatherReads.add((place.name, fahrenheit));
        return const WeatherReading(
          temperature: 21.4,
          high: 24.2,
          low: 13.6,
          code: 0,
        );
      },
    ),
    recents: () => RecentViewGallerySource(
      read: () async {
        recentReads++;
        return _recentSections();
      },
      remove: (ids) async => removedRecents.addAll(ids),
      live: recentService == null ? live : null,
      recents: recentService,
    ),
    favorites: () => FavoriteViewGallerySource(
      service: favorites,
      listen: false,
    ),
    agenda: () => HomeAgendaSource(
      store: store,
      calendar: CalendarWorkspace(providers: []),
      connectCalendars: false,
    ),
    locations: () => ViewGalleryLocations(
      readName: (id) async => id == 'space' ? 'General' : null,
    ),
    previews: () => FolderGalleryPreviewCache(loader: _Previews()),
    onSearch: _injectSearch
        ? (query, contents) => searches.add((query, contents))
        : null,
    onOpenView: (view) => opened.add(view.id),
  );

  Future<void> dispose(WidgetTester tester) async {
    try {
      await tester.pumpWidget(const SizedBox());
      for (final event in tabs.events) {
        _opened(event).plugin.notifier?.dispose();
      }
      store.dispose();
      live.dispose();
      await recentService?.dispose();
      await pumpHomeProfileClose(tester, notifications.close());
      await pumpHomeProfileClose(tester, workspace.close());
      if (!tabs.isClosed) await pumpHomeProfileClose(tester, tabs.close());
    } finally {
      RustStreamReceiver.shared = previousReceiver;
      palette.dispose();
      styles.dispose();
      menu.notifier.dispose();
      try {
        await pumpHomeProfileClose(tester, getIt.popScope());
      } finally {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      }
    }
  }
}
