import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/mobile_appearance.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestAppearance extends BaseAppearance {
  @override
  ThemeData getThemeData(
    AppTheme appTheme,
    Brightness brightness,
    String fontFamily,
    String codeFontFamily,
  ) =>
      ThemeData();
}

void main() {
  group('default typography', () {
    test('resolves the default to rounded DM Sans with Inter fallback', () {
      expect(defaultFontFamily, isEmpty);
      expect(resolveFontFamily(defaultFontFamily), preferredFontFamily);
      expect(defaultFontFamily.fontFamilyName, preferredFontFamily);

      final style = getGoogleFontSafely(defaultFontFamily);
      expect(style.fontFamily, preferredFontFamily);
      expect(style.fontFamilyFallback, defaultFontFamilyFallback);
    });

    test('uses stronger, tighter default typography', () {
      final style = _TestAppearance().getFontStyle(
        fontFamily: defaultFontFamily,
      );

      expect(style.fontFamily, preferredFontFamily);
      expect(style.fontFamilyFallback, defaultFontFamilyFallback);
      expect(style.fontWeight, defaultFontWeight);
      expect(style.fontVariations, defaultFontVariations);
      expect(style.letterSpacing, lessThan(0));
      expect(style.fontFeatures, AppTextRendering.fontFeatures);
      expect(
        style.leadingDistribution,
        TextLeadingDistribution.even,
      );
    });

    test('applies DM Sans to desktop, mobile, and AppFlowy themes', () {
      final themes = [
        DesktopAppearance().getThemeData(
          AppTheme.fallback,
          Brightness.light,
          defaultFontFamily,
          builtInCodeFontFamily,
        ),
        MobileAppearance().getThemeData(
          AppTheme.fallback,
          Brightness.light,
          defaultFontFamily,
          builtInCodeFontFamily,
        ),
      ];

      for (final theme in themes) {
        expect(theme.textTheme.bodyMedium?.fontFamily, preferredFontFamily);
        expect(
          theme.textTheme.bodyMedium?.fontFamilyFallback,
          defaultFontFamilyFallback,
        );
        expect(theme.textTheme.bodyMedium?.fontWeight, defaultFontWeight);
        expect(
          theme.textTheme.bodyMedium?.fontVariations,
          defaultFontVariations,
        );
      }

      final appFlowyTheme = AppFlowyDefaultTheme().light(
        fontFamily: defaultFontFamily.fontFamilyName,
      );
      expect(
        appFlowyTheme.textStyle.body.standard().fontFamily,
        preferredFontFamily,
      );
      expect(
        appFlowyTheme.textStyle.body.standard().fontFamilyFallback,
        defaultFontFamilyFallback,
      );
      expect(
        appFlowyTheme.textStyle.body.standard().fontWeight,
        defaultFontWeight,
      );
      expect(
        appFlowyTheme.textStyle.body.standard().fontVariations,
        defaultFontVariations,
      );
      expect(
        appFlowyTheme.textStyle.body.standard().fontFeatures,
        AppTextRendering.fontFeatures,
      );
      expect(
        appFlowyTheme.textStyle.body.enhanced().fontWeight,
        emphasizedFontWeight,
      );
      expect(
        appFlowyTheme.textStyle.body.enhanced().fontVariations,
        const [FontVariation.weight(600)],
      );
      expect(
        appFlowyTheme.textStyle.body.prominent().fontWeight,
        FontWeight.w700,
      );
      expect(
        appFlowyTheme.textStyle.caption.standard().fontSize,
        14,
      );
    });

    test('uses a 550/600 weight hierarchy in shared text primitives', () {
      expect(
        const FlowyText.regular('Regular').fontWeight,
        defaultFontWeight,
      );
      expect(
        FlowyText.small('Small').fontWeight,
        defaultFontWeight,
      );
      expect(FlowyText.small('Small').fontSize, 14);
      expect(
        const FlowyText.medium('Medium').fontWeight,
        emphasizedFontWeight,
      );
      expect(
        const FlowyText.semibold('Semibold').fontWeight,
        emphasizedFontWeight,
      );
    });

    testWidgets('renders shared regular text at exact variable weight 550',
        (tester) async {
      final theme = DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      );

      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const FlowyText.regular('Regular'),
        ),
      );

      final text = tester.widget<Text>(find.text('Regular'));
      expect(text.style?.fontWeight, defaultFontWeight);
      expect(text.style?.fontVariations, defaultFontVariations);
    });

    test('uses ObjectType system font families for each desktop platform', () {
      expect(
        SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
        'Segoe UI',
      );
      expect(
        SidebarTypography.fontFamilyForPlatform(TargetPlatform.macOS),
        '.AppleSystemUIFont',
      );
    });

    test('uses Notion sidebar geometry and neutral palette', () {
      expect(HomeSizes.minimumSidebarWidth, 240);
      expect(HomeSizes.workspaceSectionHeight, 30);
      expect(HomeSizes.sidebarHorizontalInset, 6);
      expect(HomeSizes.sidebarButtonHorizontalMargin, 4);
      expect(HomeSizes.sidebarActionIconSize, 22);
      expect(HomeSizes.sidebarActionIconTextSpacing, 8);
      expect(HomeSpaceViewSizes.viewHeight, 32);
      expect(HomeSpaceViewSizes.viewIconSize, 18);
      expect(HomeSpaceViewSizes.viewIconTextSpacing, 10);
      expect(HomeSpaceViewSizes.viewListLeftPadding, 2);
      expect(HomeSpaceViewSizes.viewLeadingSpacing, 0);
      expect(HomeSpaceViewSizes.viewDisclosureIconSpacing, 2);
      expect(HomeSpaceViewSizes.viewIconOpacity, 0.82);
      expect(
        SidebarStyle.backgroundFor(Brightness.light),
        SidebarStyle.defaultLightBackground,
      );
      expect(
        SidebarStyle.backgroundFor(
          Brightness.light,
          isPaper: true,
        ),
        const Color(0xFFF8F3E8),
      );
      expect(
        SidebarStyle.backgroundFor(Brightness.dark),
        const Color(0xFF202020),
      );
      expect(
        SidebarStyle.selectedBackgroundFor(Brightness.light),
        const Color(0x1437352F),
      );
      expect(
        SidebarStyle.iconColorFor(Brightness.light),
        const Color(0xD137352F),
      );
      expect(
        SidebarStyle.iconColorFor(Brightness.dark),
        const Color(0xCFFFFFFF),
      );
      expect(
        SidebarStyle.searchIconColorFor(Brightness.light),
        const Color(0xFF403E39),
      );
      expect(SidebarSearchIcon.iconData, Icons.search_rounded);
    });

    testWidgets('uses Notion desktop sidebar typography', (tester) async {
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Builder(
            builder: (context) {
              style = SidebarTypography.textStyle(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(style.fontFamily, 'Segoe UI');
      expect(
        style.fontFamilyFallback,
        SidebarTypography.fontFamilyFallbackForPlatform(
          TargetPlatform.windows,
        ),
      );
      expect(style.fontSize, 14);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontVariations, isEmpty);
      expect(style.height, closeTo(20 / 14, 0.0001));
      expect(style.letterSpacing, closeTo(-0.14, 0.0001));
    });

    testWidgets('uses compact muted section-label typography', (tester) async {
      late TextStyle style;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: Builder(
            builder: (context) {
              style = SidebarTypography.textStyle(
                context,
                role: SidebarTextRole.section,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(style.fontFamily, 'Segoe UI');
      expect(style.fontSize, 11);
      expect(style.fontWeight, FontWeight.w600);
      expect(style.fontVariations, isEmpty);
      expect(style.height, closeTo(16 / 11, 0.0001));
      expect(style.letterSpacing, 0.5);
    });

    testWidgets('renders larger page labels at the shared selected weight',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: const SidebarText.page(
            'Selected',
          ),
        ),
      );

      final text = tester.widget<Text>(find.text('Selected'));
      expect(text.style?.fontFamily, 'Segoe UI');
      expect(text.style?.fontSize, 15);
      expect(text.style?.fontWeight, FontWeight.w600);
      expect(text.style?.fontVariations, isEmpty);
      expect(text.style?.height, closeTo(21 / 15, 0.0001));
      expect(text.style?.letterSpacing, closeTo(-0.15, 0.0001));
    });

    test('uses a crisp global underprint only in light mode', () {
      final lightStyle = AppTextRendering.rootStyleFor(Brightness.light);
      expect(lightStyle.fontFeatures, AppTextRendering.fontFeatures);
      expect(lightStyle.leadingDistribution, TextLeadingDistribution.even);
      expect(lightStyle.shadows, AppTextRendering.lightTextUnderprint);

      final darkStyle = AppTextRendering.rootStyleFor(Brightness.dark);
      expect(darkStyle.fontFeatures, AppTextRendering.fontFeatures);
      expect(darkStyle.shadows, isEmpty);
    });

    test('uses ObjectType editor metrics', () {
      expect(ObjectTypeTypography.editorFontSize, 16);
      expect(ObjectTypeTypography.editorLineHeight, 1.6);
      expect(
        ObjectTypeTypography.fontWeightForPlatform(TargetPlatform.windows),
        FontWeight.w600,
      );
      expect(
        ObjectTypeTypography.fontWeightForPlatform(TargetPlatform.macOS),
        FontWeight.w500,
      );
      expect(
        ObjectTypeTypography.letterSpacingForFontSize(16),
        closeTo(-0.16, 0.0001),
      );
    });

    test('strengthens light desktop editor text without affecting dark mode',
        () {
      const fallback = Color(0xFFBBC3CD);
      const base = TextStyle(fontSize: 16);

      final lightStyle = ObjectTypeTypography.enhanceEditorTextStyle(
        base,
        platform: TargetPlatform.windows,
        brightness: Brightness.light,
        fallbackColor: fallback,
      );
      expect(lightStyle.color, const Color(0xFF2C2C2C));
      expect(lightStyle.shadows, hasLength(1));
      expect(lightStyle.shadows!.single.color, const Color(0x18000000));
      expect(lightStyle.shadows!.single.offset, Offset.zero);
      expect(lightStyle.shadows!.single.blurRadius, 0);

      final darkStyle = ObjectTypeTypography.enhanceEditorTextStyle(
        base,
        platform: TargetPlatform.windows,
        brightness: Brightness.dark,
        fallbackColor: fallback,
      );
      expect(darkStyle.color, fallback);
      expect(darkStyle.shadows, isEmpty);
    });

    test('falls back to DM Sans and Inter for an unknown font', () {
      final style = getGoogleFontSafely('Missing Font Family');

      expect(style.fontFamily, preferredFontFamily);
      expect(style.fontFamilyFallback, defaultFontFamilyFallback);
    });
  });
}
