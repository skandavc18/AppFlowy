import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

Future<void> initializeWorkspaceOverlayTests() async {
  TestWidgetsFlutterBinding.ensureInitialized();
  SharedPreferences.setMockInitialValues({});
  EasyLocalization.logger.enableLevels = [];
  await EasyLocalization.ensureInitialized();
}

/// Real application palettes, but no backend, live preferences or workspace.
Widget workspaceOverlayTestApp({
  required Widget child,
  String appearance = 'light',
  double textScale = 1,
  bool disableAnimations = false,
  bool accessibleNavigation = false,
}) {
  final brightness = appearance == 'dark' ? Brightness.dark : Brightness.light;
  final theme = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins.firstWhere(
            (theme) => theme.themeName == BuiltInTheme.paper,
          )
        : AppTheme.fallback,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final appTheme = PremiumTheme.appFlowyTheme(
    base: brightness == Brightness.dark
        ? AppFlowyDefaultTheme().dark()
        : AppFlowyDefaultTheme().light(),
    palette: theme.extension<PremiumThemeExtension>()!,
    brightness: brightness,
  );
  return EasyLocalization(
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
        theme: theme,
        themeAnimationDuration: Duration.zero,
        // Both route content and the originating controls inherit the same
        // palette and accessibility flags, including through the Navigator.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: TextScaler.linear(textScale),
            disableAnimations: disableAnimations,
            accessibleNavigation: accessibleNavigation,
          ),
          child: AppFlowyTheme(data: appTheme, child: child!),
        ),
        home: Scaffold(body: child),
      ),
    ),
  );
}
