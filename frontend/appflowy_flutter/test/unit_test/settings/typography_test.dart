import 'dart:io';

import 'package:appflowy/shared/google_fonts_extension.dart';
import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy/util/font_family_extension.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/mobile_appearance.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
    test('resolves the default to the bundled Inter', () {
      expect(defaultFontFamily, isEmpty);
      expect(preferredFontFamily, 'Inter');
      expect(resolveFontFamily(defaultFontFamily), preferredFontFamily);
      expect(defaultFontFamily.fontFamilyName, preferredFontFamily);

      final style = getGoogleFontSafely(defaultFontFamily);
      expect(style.fontFamily, preferredFontFamily);
      expect(style.fontFamilyFallback, isNull);
    });

    test('keeps a previously chosen DM Sans on its bundled face', () {
      final style = getGoogleFontSafely('DM Sans', fontWeight: FontWeight.w600);

      expect(style.fontFamily, 'DM Sans');
      expect(style.fontFamilyFallback, defaultFontFamilyFallback);
      expect(style.fontVariations, const [FontVariation.weight(560)]);
    });

    test('maps every FontWeight onto one held-back weight ladder', () {
      expect(
        [for (final weight in FontWeight.values) flowyFontWeightAxis(weight)],
        [200, 270, 350, 440, 480, 560, 640, 720, 800],
      );
      expect(defaultFontWeight, FontWeight.w500);
      expect(defaultFontWeightValue, 480);
      expect(defaultFontVariations, const [FontVariation.weight(480)]);
      expect(
        flowyFontVariationsForWeight(FontWeight.w700),
        const [FontVariation.weight(640)],
      );
    });

    test('reads hand-set wght axes as the step they were written for', () {
      expect(flowyFontWeightForAxis(450), FontWeight.w400);
      expect(flowyFontWeightForAxis(545), FontWeight.w500);
      expect(flowyFontWeightForAxis(570), FontWeight.w500);
      expect(flowyFontWeightForAxis(580), FontWeight.w600);
      expect(flowyFontWeightForAxis(650), FontWeight.w600);
      expect(flowyFontWeightForAxis(660), FontWeight.w700);
      expect(flowyFontWeightForAxis(700), FontWeight.w700);
    });

    test('registers static Inter faces cut at the ladder for w300 to w900', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final faces = RegExp(
        r'- asset: (assets/google_fonts/Inter/static/Inter-(\d+)(-Italic)?\.ttf)'
        r'\s+weight: (\d+)(\s+style: italic)?',
      ).allMatches(pubspec);

      final registered = <String>{};
      for (final face in faces) {
        final axis = double.parse(face.group(2)!);
        final weight = FontWeight.values[int.parse(face.group(4)!) ~/ 100 - 1];
        final italic = face.group(3) != null;
        expect(File(face.group(1)!).existsSync(), isTrue, reason: face[1]);
        expect(face.group(5) != null, italic, reason: face[1]);
        expect(axis, flowyFontWeightAxis(weight), reason: face[1]);
        registered.add('${weight.value}${italic ? 'i' : ''}');
      }
      expect(registered, {
        for (final weight in [300, 400, 500, 600, 700, 800, 900]) ...[
          '$weight',
          '${weight}i',
        ],
      });
    });

    testWidgets('draws every FontWeight with its own static Inter cut',
        (tester) async {
      final cuts = {
        FontWeight.w300: 350,
        FontWeight.w400: 440,
        FontWeight.w500: 480,
        FontWeight.w600: 560,
        FontWeight.w700: 640,
        FontWeight.w800: 720,
        FontWeight.w900: 800,
      };
      ByteData face(int cut, bool italic) => ByteData.sublistView(
            File(
              'assets/google_fonts/Inter/static/'
              'Inter-$cut${italic ? '-Italic' : ''}.ttf',
            ).readAsBytesSync(),
          );
      await tester.runAsync(() async {
        // Every face under one family, the way the engine registers assets:
        // it matches by the weight each file declares, not pubspec's.
        final family = FontLoader('InterLadder');
        for (final cut in cuts.values) {
          family
            ..addFont(Future.value(face(cut, false)))
            ..addFont(Future.value(face(cut, true)));
          await (FontLoader('InterCut$cut')
                ..addFont(Future.value(face(cut, false))))
              .load();
          await (FontLoader('InterCut${cut}Italic')
                ..addFont(Future.value(face(cut, true))))
              .load();
        }
        await family.load();
      });

      Future<List<int>> render(TextStyle style) async {
        final key = GlobalKey();
        await tester.pumpWidget(
          Directionality(
            textDirection: TextDirection.ltr,
            child: Center(
              child: RepaintBoundary(
                key: key,
                child: Text(
                  'Highlight any text, and use the menu.',
                  style: style.copyWith(fontSize: 16, color: Colors.black),
                ),
              ),
            ),
          ),
        );
        final boundary =
            tester.renderObject<RenderRepaintBoundary>(find.byKey(key));
        late List<int> pixels;
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData();
          pixels = bytes!.buffer.asUint8List();
          image.dispose();
        });
        return pixels;
      }

      for (final MapEntry(key: weight, value: cut) in cuts.entries) {
        for (final italic in [false, true]) {
          final style = italic ? FontStyle.italic : FontStyle.normal;
          expect(
            await render(
              TextStyle(
                fontFamily: 'InterLadder',
                fontWeight: weight,
                fontStyle: style,
              ),
            ),
            await render(
              TextStyle(
                fontFamily: 'InterCut$cut${italic ? 'Italic' : ''}',
                fontStyle: style,
              ),
            ),
            reason: '$weight${italic ? ' italic' : ''} should draw cut $cut',
          );
        }
      }
    });

    test('uses stronger, tighter default typography', () {
      final style = _TestAppearance().getFontStyle(
        fontFamily: defaultFontFamily,
      );

      expect(style.fontFamily, preferredFontFamily);
      expect(style.fontFamilyFallback, isNull);
      expect(style.fontWeight, defaultFontWeight);
      expect(style.fontVariations, defaultFontVariations);
      expect(style.letterSpacing, lessThan(0));
      expect(style.fontFeatures, AppTextRendering.fontFeatures);
      expect(
        style.leadingDistribution,
        TextLeadingDistribution.even,
      );
    });

    test('applies Inter to desktop, mobile, and AppFlowy themes', () {
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
        expect(theme.textTheme.bodyMedium?.fontFamilyFallback, isNull);
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
        const [FontVariation.weight(560)],
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

    testWidgets('renders shared regular text on the weight ladder',
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

    test('sets Inter on every desktop platform and keeps mobile system faces',
        () {
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(SidebarTypography.fontFamilyForPlatform(platform), 'Inter');
        expect(
          ObjectTypeTypography.usesBundledFontForPlatform(platform),
          isTrue,
        );
      }
      expect(
        ObjectTypeTypography.fontFamilyForPlatform(TargetPlatform.iOS),
        '.AppleSystemUIFont',
      );
      expect(
        ObjectTypeTypography.fontFamilyForPlatform(TargetPlatform.android),
        'Roboto',
      );
      expect(
        ObjectTypeTypography.fontFamilyFallbackForPlatform(
          TargetPlatform.windows,
        ).first,
        'Segoe UI',
      );
    });

    test('uses Notion sidebar geometry and neutral palette', () {
      expect(HomeSizes.minimumSidebarWidth, 260);
      expect(HomeSizes.workspaceSectionHeight, 32);
      expect(HomeSizes.sidebarHorizontalInset, SidebarMetrics.gutter);
      expect(HomeSizes.sidebarActionIconSize, SidebarMetrics.iconSize);
      expect(
        HomeSizes.sidebarActionIconTextSpacing,
        SidebarMetrics.iconGap,
      );
      expect(HomeSpaceViewSizes.viewHeight, SidebarMetrics.rowHeight);
      expect(HomeSpaceViewSizes.viewIconSize, SidebarMetrics.iconSize);
      expect(HomeSpaceViewSizes.leftPadding, SidebarMetrics.indent);
      expect(
        SidebarStyle.backgroundFor(Brightness.light),
        SidebarStyle.defaultLightBackground,
      );
      expect(
        SidebarStyle.backgroundFor(
          Brightness.light,
          isPaper: true,
        ),
        PaperTheme.sidebarBackground,
      );
      expect(
        SidebarStyle.backgroundFor(Brightness.dark),
        const Color(0xFF1F1F1F),
      );
      expect(
        SidebarStyle.selectedBackgroundFor(Brightness.light),
        const Color(0x1416150F),
      );
      expect(SidebarSearchIcon.iconData, Icons.search_rounded);
    });

    testWidgets('sets navigation copy at medium, never the editor semibold',
        (tester) async {
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

      expect(style.fontFamily, 'Inter');
      expect(
        style.fontFamilyFallback,
        SidebarTypography.fontFamilyFallbackForPlatform(
          TargetPlatform.windows,
        ),
      );
      expect(style.fontSize, SidebarTypography.fontSize);
      expect(style.fontWeight, FontWeight.w500);
      expect(
        style.fontWeight!.index,
        lessThan(ObjectTypeTypography.emphasisFontWeight.index),
      );
      expect(style.fontVariations, defaultFontVariations);
      expect(style.height, closeTo(18 / 13.5, 0.0001));
      expect(style.letterSpacing, closeTo(-0.135, 0.0001));
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

      expect(style.fontFamily, 'Inter');
      expect(style.fontSize, 11.5);
      expect(style.fontWeight, FontWeight.w500);
      expect(style.fontVariations, defaultFontVariations);
      expect(style.height, closeTo(16 / 11.5, 0.0001));
      expect(style.letterSpacing, 0.35);
    });

    testWidgets('keeps page names lighter than the section heading above them',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.windows),
          home: const Column(
            children: [
              SidebarText.page('Selected'),
              SidebarText.heading('My workspace'),
            ],
          ),
        ),
      );

      final page = tester.widget<Text>(find.text('Selected'));
      expect(page.style?.fontFamily, 'Inter');
      expect(page.style?.fontSize, SidebarTypography.pageFontSize);
      expect(page.style?.fontWeight, FontWeight.w500);
      expect(page.style?.fontVariations, defaultFontVariations);
      expect(page.style?.height, closeTo(18 / 13.5, 0.0001));

      final heading = tester.widget<Text>(find.text('My workspace'));
      expect(heading.style?.fontWeight, FontWeight.w600);
      expect(
        heading.style!.fontWeight!.index,
        greaterThan(page.style!.fontWeight!.index),
      );
    });

    testWidgets('sets Linux sidebar copy in Inter on the shared ladder',
        (tester) async {
      late TextStyle page;
      late TextStyle heading;
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(platform: TargetPlatform.linux),
          home: Builder(
            builder: (context) {
              page = SidebarTypography.textStyle(
                context,
                role: SidebarTextRole.page,
              );
              heading = SidebarTypography.textStyle(
                context,
                role: SidebarTextRole.heading,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(page.fontFamily, bundledFontFamily);
      expect(page.fontWeight, FontWeight.w500);
      expect(page.fontVariations, defaultFontVariations);
      expect(heading.fontFamily, bundledFontFamily);
      expect(heading.fontWeight, FontWeight.w600);
      expect(heading.fontVariations, const [FontVariation.weight(560)]);
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
      for (final platform in [
        TargetPlatform.windows,
        TargetPlatform.macOS,
        TargetPlatform.linux,
      ]) {
        expect(
          ObjectTypeTypography.fontWeightForPlatform(platform),
          FontWeight.w500,
        );
      }
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

    test('falls back to Inter for an unknown font', () {
      final style = getGoogleFontSafely('Missing Font Family');

      expect(style.fontFamily, preferredFontFamily);
      expect(style.fontFamilyFallback, defaultFontFamilyFallback);
    });
  });

  group('sidebar labels', () {
    testWidgets('set every label in the navigation grey in each appearance',
        (tester) async {
      for (final (brightness, paper) in [
        (Brightness.light, true),
        (Brightness.light, false),
        (Brightness.dark, false),
      ]) {
        late SidebarPalette palette;
        await tester.pumpWidget(
          MaterialApp(
            theme: ThemeData(
              brightness: brightness,
              extensions: [PaperThemeExtension(enabled: paper)],
            ),
            home: Builder(
              builder: (context) {
                palette = SidebarPalette.of(context);
                return Theme(
                  data: SidebarStyle.themeData(context),
                  child: const Column(
                    children: [
                      SidebarText('Search'),
                      SidebarText.page('Quick Notes'),
                      SidebarText.heading('My Workspace'),
                    ],
                  ),
                );
              },
            ),
          ),
        );

        for (final label in ['Search', 'Quick Notes', 'My Workspace']) {
          expect(
            tester.widget<Text>(find.text(label)).style!.color,
            palette.textSecondary,
            reason: '$label, $brightness${paper ? ' paper' : ''}',
          );
        }
      }
    });
  });

  group('document text smoothing', () {
    test('moves each run colour into one cached, blurred paint', () {
      const ink = Color(0xFF2C2C2C);
      const link = Color(0xFF2383E2);
      final recognizer = TapGestureRecognizer();
      addTearDown(recognizer.dispose);
      const plain = TextSpan(text: 'plain ');
      const inline = WidgetSpan(child: SizedBox.square(dimension: 4));
      final span = TextSpan(
        style: const TextStyle(color: ink),
        children: [
          plain,
          TextSpan(
            text: 'a link',
            style: const TextStyle(
              color: link,
              decoration: TextDecoration.underline,
            ),
            recognizer: recognizer,
          ),
          inline,
        ],
      );

      final smoothed = AppTextRendering.smoothDocumentText(span) as TextSpan;
      const blur = MaskFilter.blur(
        BlurStyle.normal,
        AppTextRendering.documentTextSmoothing,
      );
      expect(smoothed.style!.color, isNull);
      expect(smoothed.style!.foreground!.color, isSameColorAs(ink));
      // Paint keeps the blur radius as a float, so compare what it describes.
      expect('${smoothed.style!.foreground!.maskFilter}', '$blur');
      expect(smoothed.children![0], same(plain));
      final smoothedLink = smoothed.children![1] as TextSpan;
      expect(smoothedLink.recognizer, same(recognizer));
      expect(smoothedLink.style!.foreground!.color, isSameColorAs(link));
      expect(smoothedLink.style!.decorationColor, link);
      expect(smoothed.children![2], same(inline));

      final again = AppTextRendering.smoothDocumentText(span) as TextSpan;
      expect(again.style!.foreground, same(smoothed.style!.foreground));
      expect(AppTextRendering.smoothDocumentText(smoothed), same(smoothed));
    });

    testWidgets('applies only where Linux shows a 2x frame rescaled',
        (tester) async {
      addTearDown(tester.view.resetDevicePixelRatio);
      for (final (platform, ratio, smooths) in [
        (TargetPlatform.linux, 2.0, true),
        (TargetPlatform.linux, 1.0, false),
        (TargetPlatform.windows, 2.0, false),
        (TargetPlatform.macOS, 2.0, false),
      ]) {
        tester.view.devicePixelRatio = ratio;
        debugDefaultTargetPlatformOverride = platform;
        try {
          late bool result;
          await tester.pumpWidget(
            Builder(
              builder: (context) {
                result = AppTextRendering.smoothsDocumentText(context);
                return const SizedBox.shrink();
              },
            ),
          );
          expect(result, smooths, reason: '$platform at ${ratio}x');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      }
    });
  });
}
