import 'dart:ui' as ui;

import 'package:appflowy/shared/calendar/calendar_event.dart';
import 'package:appflowy/shared/calendar/calendar_provider.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

Future<void> initializeCalendarTests() async {
  SharedPreferences.setMockInitialValues({});
  EasyLocalization.logger.enableLevels = [];
  GoogleFonts.config.allowRuntimeFetching = false;
  await EasyLocalization.ensureInitialized();
}

/// Only the provider boundary is substituted. CalendarWorkspace, filters,
/// event models, shell, layout, menus and delegates are production code.
class CalendarFixtureProvider extends CalendarProvider {
  CalendarFixtureProvider({
    List<CalendarEvent> events = const [],
    this.capabilities = CalendarCapabilities.full,
  }) : _events = events;

  List<CalendarEvent> _events;
  final List<CalendarWindow> windows = [];
  bool disposed = false;

  void publish(List<CalendarEvent> events) {
    _events = events;
    notifyListeners();
  }

  @override
  List<CalendarInfo> get calendars => const [
        CalendarInfo(
          id: 'calendar-fixture',
          name: 'Offline calendar',
          service: CalendarService.local,
          color: Color(0xFF43955A),
        ),
      ];

  @override
  final CalendarCapabilities capabilities;

  @override
  List<CalendarEvent> get events => _events;

  @override
  CalendarService get service => CalendarService.local;

  @override
  CalendarSyncStatus get status => CalendarSyncStatus.idle;

  @override
  Future<void> load(CalendarWindow window) async => windows.add(window);

  @override
  Future<void> refresh() async {}

  @override
  void dispose() {
    disposed = true;
    super.dispose();
  }
}

CalendarEvent calendarFixtureEvent(
  String id,
  DateTime start, {
  DateTime? end,
  bool allDay = false,
  String? title,
  CalendarEventKind kind = CalendarEventKind.event,
  bool readOnly = false,
  String description = '',
  String location = '',
}) =>
    CalendarEvent(
      id: id,
      calendarId: 'calendar-fixture',
      title: title ?? id,
      start: allDay ? ZonedDateTime.allDay(start) : ZonedDateTime.local(start),
      end: end == null
          ? null
          : allDay
              ? ZonedDateTime.allDay(end)
              : ZonedDateTime.local(end),
      kind: kind,
      readOnly: readOnly,
      description: description,
      location: location,
    );

Widget calendarTestApp(
  Widget child, {
  String appearance = 'light',
  Size size = const Size(680, 320),
  double textScale = 1,
  bool rtl = false,
  bool reducedMotion = true,
  bool accessibleNavigation = true,
}) {
  final brightness = appearance == 'dark' ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance()
      .getThemeData(
        appearance == 'paper'
            ? AppTheme.builtins
                .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
            : AppTheme.fallback,
        brightness,
        defaultFontFamily,
        builtInCodeFontFamily,
      )
      .copyWith(platform: TargetPlatform.windows);
  final defaults = AppFlowyDefaultTheme();
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
        supportedLocales: context.supportedLocales,
        theme: theme,
        themeAnimationDuration: Duration.zero,
        builder: (context, navigator) => AppFlowyTheme(
          data: PremiumTheme.appFlowyTheme(
            base: brightness == Brightness.dark
                ? defaults.dark()
                : defaults.light(),
            palette: theme.extension<PremiumThemeExtension>()!,
            brightness: brightness,
          ),
          child: MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: TextScaler.linear(textScale),
              disableAnimations: reducedMotion,
              accessibleNavigation: accessibleNavigation,
              alwaysUse24HourFormat: true,
            ),
            child: Directionality(
              textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
              child: TooltipVisibility(visible: false, child: navigator!),
            ),
          ),
        ),
        home: Scaffold(
          body: Center(
            child: Directionality(
              textDirection: rtl ? ui.TextDirection.rtl : ui.TextDirection.ltr,
              child: SizedBox(
                key: const ValueKey('calendar-test-frame'),
                width: size.width,
                height: size.height,
                child: child,
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

Future<void> mountCalendarTest(
  WidgetTester tester,
  Widget child, {
  String appearance = 'light',
  Size size = const Size(680, 320),
  double textScale = 1,
  bool rtl = false,
  bool reducedMotion = true,
  bool accessibleNavigation = true,
}) async {
  Widget app(Widget content) => calendarTestApp(
        content,
        appearance: appearance,
        size: size,
        textScale: textScale,
        rtl: rtl,
        reducedMotion: reducedMotion,
        accessibleNavigation: accessibleNavigation,
      );
  await tester.pumpWidget(app(const SizedBox()));
  await tester.pumpAndSettle();
  await tester.pumpWidget(app(child));
  await tester.pumpAndSettle();
}
