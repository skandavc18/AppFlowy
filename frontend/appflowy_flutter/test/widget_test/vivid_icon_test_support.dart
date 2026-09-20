import 'package:appflowy/plugins/base/emoji/emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_emoji_mart/flutter_emoji_mart.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

const vividIconTestGroup = 'appflowy_vivid_essentials';
const vividIconTestAppearances = ['light', 'dark', 'paper'];

Future<void> prepareVividIconTestAssets() async {
  SharedPreferences.setMockInitialValues({});
  EasyLocalization.logger.enableLevels = [];
  await EasyLocalization.ensureInitialized();
  kCachedEmojiData = await EmojiData.builtIn();
  final families = {
    SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
    for (final appearance in vividIconTestAppearances)
      vividIconTestTheme(appearance).textTheme.bodyMedium?.fontFamily,
  }.whereType<String>();
  for (final family in families) {
    await (FontLoader(family)
          ..addFont(
            rootBundle.load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
          ))
        .load();
  }
}

Future<void> resetVividIconTestPacks() async {
  resetIconPacksForTesting();
  kIconGroups = null;
  // Load outside the widget test's fake clock. Vivid itself needs no preload.
  await loadIconPack(kDefaultIconPack);
}

/// Await the actual SVG loaders/decoder, not an arbitrary rasterization delay.
Future<void> settleVividIconPictures(WidgetTester tester) async {
  await tester.pumpAndSettle();
  final elements = find.byType(SvgPicture).evaluate().toList();
  await tester.runAsync(() async {
    for (final element in elements) {
      final svg = element.widget as SvgPicture;
      final decoded = await vg.loadPicture(svg.bytesLoader, element);
      decoded.picture.dispose();
    }
  });
  await tester.pumpAndSettle();
}

Future<void> disposeVividIconPicker(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // The existing emoji library batches visibility-exit callbacks for 500ms.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder vividIconStyleButton(String label) =>
    find.widgetWithText(TextButton, label);

Finder vividIconOption(String name) => find.descendant(
      of: find.byKey(ValueKey('picker-icon-$vividIconTestGroup/$name')),
      matching: find.byType(TextButton),
    );

Widget vividIconTestPicker({
  ValueChanged<SelectedEmojiIconResult>? onSelected,
  bool colors = true,
  double width = 360,
  double height = 380,
}) =>
    SizedBox(
      width: width,
      height: height,
      child: FlowyIconEmojiPicker(
        tabs: const [
          PickerTabType.emoji,
          PickerTabType.icon,
          PickerTabType.custom,
        ],
        initialType: PickerTabType.icon,
        enableBackgroundColorSelection: colors,
        onSelectedEmoji: onSelected,
      ),
    );

ThemeData vividIconTestTheme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget vividIconTestApp(String appearance, Widget child) => EasyLocalization(
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
          theme: vividIconTestTheme(appearance),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
