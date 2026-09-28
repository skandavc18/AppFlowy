import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/spell_check/spell_check_settings.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';

import 'test_asset_bundle.dart';
import 'workspace_design_fixture.dart';

export 'workspace_design_fixture.dart' show WorkspaceDesignAppearance;

const _locale = Locale('en', 'US');
late Map<String, dynamic> _translations;

void surfaceFindTestEnvironment() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final environment = WorkspaceDesignEnvironment();
  setUpAll(() async {
    await environment.initialize();
    _translations = await const TestBundleAssetLoader()
        .load('assets/translations', _locale);
  });
  setUp(() =>
      SpellCheckSettings.instance.seedForTest(spelling: false, grammar: false));
  tearDown(() => SpellCheckSettings.instance.seedForTest());
  tearDownAll(environment.dispose);
  tearDown(environment.expectOffline);
}

Widget surfaceFindTestApp(
  Widget child, {
  WorkspaceDesignAppearance appearance = WorkspaceDesignAppearance.light,
  bool reduceMotion = true,
}) {
  final theme = workspaceDesignTheme(appearance);
  final base = AppFlowyDefaultTheme();
  return DefaultAssetBundle(
    bundle: testAssetBundle,
    child: EasyLocalization(
      supportedLocales: const [_locale],
      startLocale: _locale,
      fallbackLocale: _locale,
      path: 'assets/translations',
      saveLocale: false,
      assetLoader: _LoadedTranslations(),
      child: Builder(
          builder: (context) => MaterialApp(
                theme: theme,
                themeAnimationDuration: Duration.zero,
                locale: context.locale,
                supportedLocales: context.supportedLocales,
                localizationsDelegates: context.localizationDelegates,
                builder: (context, child) => MediaQuery(
                  data: MediaQuery.of(context)
                      .copyWith(disableAnimations: reduceMotion),
                  child: AppFlowyTheme(
                    data: PremiumTheme.appFlowyTheme(
                      base: theme.brightness == Brightness.dark
                          ? base.dark()
                          : base.light(),
                      palette: theme.extension<PremiumThemeExtension>()!,
                      brightness: theme.brightness,
                    ),
                    child: MultiProvider(
                      providers: [
                        Provider<AppearanceSettingsCubit>.value(
                            value: _SurfaceFindAppearance()),
                        BlocProvider<DocumentAppearanceCubit>(
                            create: (_) => DocumentAppearanceCubit()),
                      ],
                      child: child!,
                    ),
                  ),
                ),
                home: Scaffold(
                    body: ContextualFindScope(
                        findInControls: true, child: child)),
              )),
    ),
  );
}

class _LoadedTranslations extends AssetLoader {
  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) =>
      Future.value(_translations);
}

Future<void> openSurfaceFind(WidgetTester tester,
    {bool replace = false}) async {
  // Localization completes asynchronously after pumpWidget. Mount and lay out
  // its page before sending keys; a shortcut cannot target an absent surface.
  await tester.pump();
  await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft);
  await tester.sendKeyEvent(
      replace ? LogicalKeyboardKey.keyH : LogicalKeyboardKey.keyF,
      physicalKey:
          replace ? PhysicalKeyboardKey.keyH : PhysicalKeyboardKey.keyF);
  await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft,
      physicalKey: PhysicalKeyboardKey.controlLeft);
  await pumpSurfaceFind(tester);
}

Future<void> pumpSurfaceFind(WidgetTester tester) async {
  for (var frame = 0; frame < 6; frame++) {
    await tester.pump(const Duration(milliseconds: 20));
  }
  expect(tester.takeException(), isNull);
}

RenderSurfaceFindHighlight surfaceFindPaint(WidgetTester tester, Object id) {
  final target = find.byWidgetPredicate(
      (widget) => widget is SurfaceFindTarget && widget.id == id);
  expect(target, findsOneWidget);
  return tester.renderObject<RenderSurfaceFindHighlight>(find.descendant(
    of: target,
    matching: find.byType(SurfaceFindHighlight),
  ));
}

/// Immutable appearance data only: no storage/backend reads or preference writes.
class _SurfaceFindAppearance extends Fake implements AppearanceSettingsCubit {
  @override
  AppearanceSettingsState get state => AppearanceSettingsState(
        appTheme: AppTheme.fallback,
        themeMode: ThemeMode.light,
        font: preferredFontFamily,
        layoutDirection: LayoutDirection.ltrLayout,
        textDirection: AppFlowyTextDirection.ltr,
        enableRtlToolbarItems: false,
        locale: _locale,
        isMenuCollapsed: false,
        menuOffset: 0,
        dateFormat: UserDateFormatPB.Locally,
        timeFormat: UserTimeFormatPB.TwentyFourHour,
        timezoneId: 'UTC',
        documentCursorColor: null,
        documentSelectionColor: null,
        textScaleFactor: 1,
        enableKineticScrolling: false,
      );
}
