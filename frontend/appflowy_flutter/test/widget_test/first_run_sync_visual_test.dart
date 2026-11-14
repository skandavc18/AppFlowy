// Draws the first screen's choices in light, dark and paper, for a person to
// look at: `flutter test --dart-define=FIRST_RUN_SHOT=/tmp/first-run.png`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/user/presentation/screens/sign_in_screen/widgets/first_run_sync_options.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _shot = String.fromEnvironment('FIRST_RUN_SHOT');

void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    await (FontLoader('MaterialIcons')
          ..addFont(rootBundle.load('fonts/MaterialIcons-Regular.otf')))
        .load();
    for (final family in ['light', 'dark', 'paper']
        .map((mode) => _theme(mode).textTheme.bodyMedium?.fontFamily)
        .whereType<String>()
        .toSet()) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  testWidgets('the first screen offers every way to start, in every theme',
      (tester) async {
    tester.view.physicalSize = const Size(1500, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        RepaintBoundary(
          key: const ValueKey('first-run'),
          child: Row(
            children: [
              for (final appearance in ['light', 'dark', 'paper'])
                Expanded(
                  child: Theme(
                    data: _theme(appearance),
                    child: Builder(
                      builder: (context) => Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: Center(
                            child: FirstRunSyncOptions(
                              startLocal: () async {},
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    for (final key in [
      'first-run-googleDrive',
      'first-run-oneDrive',
      'first-run-box',
      'first-run-selfHostedCloud',
      'first-run-self-hosted',
      'first-run-local',
    ]) {
      expect(find.byKey(ValueKey(key)), findsNWidgets(3), reason: key);
    }
    expect(find.text('Sync with Google Drive'), findsNWidgets(3));
    expect(
      find.text('Sync with self-hosted AppFlowy Cloud'),
      findsNWidgets(3),
    );
    expect(find.text('Work on an AppFlowy server'), findsNWidgets(3));
    expect(find.text('Create local account (no sync)'), findsNWidgets(3));

    if (_shot.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('first-run')),
      );
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        return data!.buffer.asUint8List();
      });
      File(_shot).writeAsBytesSync(bytes!);
    }
    await tester.pumpWidget(const SizedBox());
  });
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
    .copyWith(platform: TargetPlatform.linux);

Widget _app(Widget child) => EasyLocalization(
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
          theme: _theme('light'),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: child),
        ),
      ),
    );
