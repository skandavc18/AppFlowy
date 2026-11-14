// Draws the AppFlowy password's places in light, dark and paper, for a person
// to look at: `flutter test --dart-define=APP_PASSWORD_SHOT=/tmp/shot.png`.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/workspace/application/sync/sync_engine.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_dialogs.dart';
import 'package:appflowy/workspace/presentation/app_password/app_password_section.dart';
import 'package:appflowy/workspace/presentation/settings/pages/account/reset_everything_section.dart';
import 'package:appflowy/workspace/presentation/settings/pages/backup/sync_section.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const _shot = String.fromEnvironment('APP_PASSWORD_SHOT');

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

  testWidgets('the AppFlowy password and linked devices, in every theme',
      (tester) async {
    tester.view.physicalSize = const Size(1560, 1280);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final now = DateTime.now();
    final devices = [
      SyncDeviceSummary(
        id: 'this',
        name: 'skanda-desktop',
        isThisComputer: true,
        platform: 'linux',
        lastSeen: now.subtract(const Duration(seconds: 20)),
        joinedAt: DateTime(2026, 11, 6),
      ),
      SyncDeviceSummary(
        id: 'laptop',
        name: 'Office laptop',
        isThisComputer: false,
        platform: 'windows',
        lastSeen: now.subtract(const Duration(minutes: 5)),
        joinedAt: DateTime(2026, 11, 7),
      ),
      SyncDeviceSummary(
        id: 'phone',
        name: 'Pixel 9',
        isThisComputer: false,
        platform: 'android',
        lastSeen: now.subtract(const Duration(days: 2)),
        joinedAt: DateTime(2026, 11, 2),
        waiting: true,
      ),
    ];
    await tester.pumpWidget(
      _app(
        RepaintBoundary(
          key: const ValueKey('shot'),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (final appearance in ['light', 'dark', 'paper'])
                Expanded(
                  child: Theme(
                    data: _theme(appearance),
                    child: Builder(
                      builder: (context) => Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.all(18),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              const AppPasswordStateRow(),
                              const SizedBox(height: 18),
                              SyncDevicesList(
                                devices: devices,
                                thisComputer: 'skanda-desktop',
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 610,
                                child: AppPasswordDialog(
                                  question: AppPasswordQuestion.choose,
                                  allowUnencryptedSync: true,
                                  check: (_) async => null,
                                ),
                              ),
                              const SizedBox(height: 14),
                              SizedBox(
                                height: 510,
                                child: ResetEverythingDialog(
                                  requiresPassword: true,
                                  syncDestinationLabel:
                                      'Google Drive (AppFlowy)',
                                  onConfirm: ({
                                    required password,
                                    required clearCloudSync,
                                  }) async =>
                                      null,
                                ),
                              ),
                            ],
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
    expect(find.text('Linked devices (3)'), findsNWidgets(3));
    expect(find.text('Waiting to catch up'), findsNWidgets(3));
    expect(find.text('Encrypt synced data on cloud'), findsNWidgets(3));
    expect(find.text('Choose your AppFlowy password'), findsNWidgets(3));
    expect(find.text('Reset everything and start fresh?'), findsNWidgets(3));
    expect(
      find.byKey(const ValueKey('reset-app-password-field')),
      findsNWidgets(3),
    );
    expect(
      find.byKey(const ValueKey('reset-clear-cloud-checkbox')),
      findsNWidgets(3),
    );

    if (_shot.isNotEmpty) {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')),
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

  testWidgets(
      'reset dialog omits password field when no AppFlowy password is set',
      (tester) async {
    var confirmed = false;
    await tester.pumpWidget(
      _app(
        ResetEverythingDialog(
          requiresPassword: false,
          onConfirm: ({required password, required clearCloudSync}) async {
            expect(password, isNull);
            expect(clearCloudSync, isFalse);
            confirmed = true;
            return null;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('reset-app-password-field')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('reset-confirm-button')));
    await tester.pumpAndSettle();
    expect(confirmed, isTrue);
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
