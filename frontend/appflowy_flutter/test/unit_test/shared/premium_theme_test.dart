import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table_constants.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/premium_theme_backdrop.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/mobile_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final paperTheme = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );

  group('PremiumTheme palettes', () {
    test('Light is warm, layered, muted, and distinct from Paper', () {
      final light = PremiumTheme.resolve(
        appTheme: AppTheme.fallback,
        legacy: AppTheme.fallback.lightTheme,
        brightness: Brightness.light,
      );
      final paper = PremiumTheme.resolve(
        appTheme: paperTheme,
        legacy: paperTheme.lightTheme,
        brightness: Brightness.light,
      );

      expect(light.isPaper, isFalse);
      expect(light.canvas, isNot(Colors.white));
      expect(light.surface, isNot(light.canvas));
      expect(light.floatingSurface, isNot(light.surface));
      expect(light.border.a, lessThan(48 / 255));
      expect(
        HSLColor.fromColor(light.accent).saturation,
        lessThanOrEqualTo(.42),
      );

      expect(paper.isPaper, isTrue);
      expect(paper.canvas, PaperTheme.editorBackground);
      expect(paper.floatingSurface, PaperTheme.popupBackground);
      expect(paper.canvas, isNot(light.canvas));
      expect(paper.textPrimary, isNot(light.textPrimary));
      expect(paper.paperGrain.a, greaterThan(0));
      expect(paper.canvas.r, greaterThan(paper.canvas.b));
      expect(paper.surface.r, greaterThan(paper.surface.b));
      expect(
        [paper.canvas, paper.surface, paper.floatingSurface, paper.sidebar],
        everyElement(isNot(Colors.white)),
      );
    });

    test('Dark keeps existing legacy palette values', () {
      final legacy = AppTheme.fallback.darkTheme;
      final dark = PremiumTheme.resolve(
        appTheme: paperTheme,
        legacy: legacy,
        brightness: Brightness.dark,
      );

      expect(dark.isPaper, isFalse);
      expect(dark.canvas, legacy.surface);
      expect(dark.floatingSurface, legacy.input);
      expect(dark.sidebar, legacy.sidebarBg);
      expect(dark.textPrimary, legacy.text);
      expect(dark.accent, legacy.primary);
      expect(dark.paperGrain, Colors.transparent);
    });

    test('other built-in Light themes keep restrained visual identity', () {
      final defaultPalette = PremiumTheme.resolve(
        appTheme: AppTheme.fallback,
        legacy: AppTheme.fallback.lightTheme,
        brightness: Brightness.light,
      );
      final themedPalettes = {
        for (final theme in AppTheme.builtins.where(
          (theme) =>
              theme.themeName != BuiltInTheme.defaultTheme &&
              theme.themeName != BuiltInTheme.paper,
        ))
          theme: PremiumTheme.resolve(
            appTheme: theme,
            legacy: theme.lightTheme,
            brightness: Brightness.light,
          ),
      };

      expect(
        themedPalettes.values.map((palette) => palette.sidebar).toSet(),
        hasLength(themedPalettes.length),
      );
      for (final entry in themedPalettes.entries) {
        expect(entry.value.sidebar, isNot(defaultPalette.sidebar));
        expect(
          _contrastRatio(entry.value.onAccent, entry.value.accent),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          PremiumTheme.tintFor(entry.key.lightTheme.tint1, entry.value),
          entry.key.lightTheme.tint1,
        );
      }
    });
  });

  group('Material 3 component system', () {
    test('Desktop Light uses premium component geometry and states', () {
      final theme = DesktopAppearance().getThemeData(
        AppTheme.fallback,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      );
      final palette = theme.extension<PremiumThemeExtension>()!;
      final cardShape = theme.cardTheme.shape! as RoundedRectangleBorder;
      final filledStyle = theme.filledButtonTheme.style!;

      expect(theme.useMaterial3, isTrue);
      expect(theme.scaffoldBackgroundColor, palette.canvas);
      expect(theme.cardColor, palette.floatingSurface);
      expect(theme.dividerColor, palette.border);
      expect(cardShape.borderRadius, BorderRadius.circular(13));
      expect(cardShape.side.color, palette.border);
      expect(theme.inputDecorationTheme.filled, isNot(true));
      expect(theme.inputDecorationTheme.enabledBorder, isNull);
      expect(theme.inputDecorationTheme.focusedBorder, isNull);
      expect(
        filledStyle.backgroundColor!.resolve(const {}),
        palette.accent,
      );
      expect(
        filledStyle.backgroundColor!.resolve(const {WidgetState.hovered}),
        palette.accentHover,
      );
      expect(
        theme.outlinedButtonTheme.style!.backgroundColor!
            .resolve(const {WidgetState.hovered}),
        palette.hover,
      );
      expect(theme.textTheme.bodyLarge?.height, closeTo(1.5, 0.001));
      expect(theme.textTheme.bodySmall?.height, closeTo(1.5, 0.001));
    });

    test('Paper desktop and mobile share hierarchy, not a white inversion', () {
      final desktop = DesktopAppearance().getThemeData(
        paperTheme,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      );
      final mobile = MobileAppearance().getThemeData(
        paperTheme,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      );
      final desktopPalette = desktop.extension<PremiumThemeExtension>()!;
      final mobilePalette = mobile.extension<PremiumThemeExtension>()!;

      expect(desktop.useMaterial3, isTrue);
      expect(mobile.useMaterial3, isTrue);
      expect(desktopPalette.isPaper, isTrue);
      expect(mobilePalette.isPaper, isTrue);
      expect(desktop.colorScheme.surface, PaperTheme.editorBackground);
      expect(mobile.colorScheme.surface, PaperTheme.editorBackground);
      expect(desktop.cardColor, PaperTheme.popupBackground);
      expect(mobile.cardColor, PaperTheme.popupBackground);
      expect(desktop.colorScheme.onSurface, PaperTheme.textPrimary);
      expect(mobile.colorScheme.onSurfaceVariant, PaperTheme.textSecondary);
      expect(desktop.colorScheme.primary, PaperTheme.accent);
      expect(mobile.colorScheme.primary, PaperTheme.accent);
    });
  });

  group('AppFlowy design system mapping', () {
    test('Light and Paper map all core semantic roles', () {
      final materialTheme = DesktopAppearance().getThemeData(
        paperTheme,
        Brightness.light,
        defaultFontFamily,
        builtInCodeFontFamily,
      );
      final palette = materialTheme.extension<PremiumThemeExtension>()!;
      final transformed = PremiumTheme.appFlowyTheme(
        base: AppFlowyDefaultTheme().light(),
        palette: palette,
        brightness: Brightness.light,
      );

      expect(transformed.textColorScheme.primary, palette.textPrimary);
      expect(transformed.textColorScheme.secondary, palette.textSecondary);
      expect(transformed.backgroundColorScheme.primary, palette.canvas);
      expect(transformed.surfaceColorScheme.primary, palette.floatingSurface);
      expect(transformed.surfaceContainerColorScheme.layer01, palette.sidebar);
      expect(transformed.fillColorScheme.primary, palette.mutedSurface);
      expect(transformed.fillColorScheme.content.a, 0);
      expect(
        transformed.fillColorScheme.content.r,
        closeTo(palette.floatingSurface.r, 0.001),
      );
      expect(
        transformed.fillColorScheme.content.g,
        closeTo(palette.floatingSurface.g, 0.001),
      );
      expect(
        transformed.fillColorScheme.content.b,
        closeTo(palette.floatingSurface.b, 0.001),
      );
      expect(transformed.fillColorScheme.contentHover, palette.hoverOverlay);
      expect(transformed.borderColorScheme.primary, palette.border);
      expect(transformed.shadow.medium, isNotEmpty);
      expect(
        transformed.shadow.medium.first.color.a,
        lessThanOrEqualTo(PaperTheme.shadow.a),
      );
    });

    test('Dark AppFlowy theme is returned unchanged', () {
      final base = AppFlowyDefaultTheme().dark();
      final palette = PremiumTheme.resolve(
        appTheme: AppTheme.fallback,
        legacy: AppTheme.fallback.darkTheme,
        brightness: Brightness.dark,
      );
      final transformed = PremiumTheme.appFlowyTheme(
        base: base,
        palette: palette,
        brightness: Brightness.dark,
      );

      expect(transformed, same(base));
    });
  });

  testWidgets('procedural grain is rendered only for light Paper',
      (tester) async {
    final paper = DesktopAppearance().getThemeData(
      paperTheme,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    final light = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

    Future<void> pump(ThemeData theme) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: theme,
          home: const PremiumThemeBackdrop(
            child: SizedBox.expand(key: ValueKey('content')),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pump(paper);
    final backdrop = find.byType(PremiumThemeBackdrop);
    expect(
      find.descendant(of: backdrop, matching: find.byType(CustomPaint)),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: backdrop,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is IgnorePointer && widget.child is ExcludeSemantics,
        ),
      ),
      findsOneWidget,
    );

    await pump(light);
    expect(
      find.descendant(of: backdrop, matching: find.byType(CustomPaint)),
      findsNothing,
    );
    expect(find.byKey(const ValueKey('content')), findsOneWidget);
  });

  testWidgets('simple tables consume premium semantic surface roles',
      (tester) async {
    final theme = DesktopAppearance().getThemeData(
      paperTheme,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    final palette = theme.extension<PremiumThemeExtension>()!;
    late Color border;
    late Color background;
    late Color hover;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            border = context.simpleTableBorderColor;
            background = context.simpleTableActionButtonBackgroundColor;
            hover = context.simpleTableMoreActionHoverColor;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(border, palette.borderStrong);
    expect(background, palette.floatingSurface);
    expect(hover, palette.accent);
  });

  testWidgets('focused borderless editor fields remain borderless',
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
        home: const Scaffold(
          body: TextField(
            autofocus: true,
            decoration: InputDecoration(border: InputBorder.none),
          ),
        ),
      ),
    );
    await tester.pump();

    final decoration =
        tester.widget<InputDecorator>(find.byType(InputDecorator)).decoration;
    expect(decoration.border, InputBorder.none);
    expect(decoration.enabledBorder, isNull);
    expect(decoration.focusedBorder, isNull);
    expect(decoration.filled, isNot(true));
  });

  testWidgets('tooltips remain compact under premium typography',
      (tester) async {
    final theme = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    const target = ValueKey('tooltip-target');

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: const Center(
          child: Tooltip(
            message: 'Show page thumbnails',
            child: SizedBox.square(key: target, dimension: 30),
          ),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    addTearDown(mouse.removePointer);
    await mouse.addPointer(location: tester.getCenter(find.byKey(target)));
    await tester.pump(const Duration(milliseconds: 500));

    final tooltipText = find.text('Show page thumbnails');
    expect(tooltipText, findsOneWidget);
    expect(tester.getSize(tooltipText).height, lessThan(32));
  });

  testWidgets('inline code uses calm semantic colors', (tester) async {
    final theme = DesktopAppearance().getThemeData(
      paperTheme,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    final palette = theme.extension<PremiumThemeExtension>()!;
    late Color background;
    late Color foreground;

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: Builder(
          builder: (context) {
            background = EditorSurfaceStyle.inlineCodeBackground(context);
            foreground = EditorSurfaceStyle.inlineCodeForeground(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(background, palette.mutedSurface);
    expect(foreground, palette.textPrimary);
    expect(background.computeLuminance(), greaterThan(0.75));
    expect(_contrastRatio(foreground, background), greaterThanOrEqualTo(4.5));
  });
}

double _contrastRatio(Color foreground, Color background) {
  final foregroundLuminance = foreground.computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = foregroundLuminance > backgroundLuminance
      ? foregroundLuminance
      : backgroundLuminance;
  final darker = foregroundLuminance > backgroundLuminance
      ? backgroundLuminance
      : foregroundLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}
