import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/mobile_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _lightSurfaces = {
  'canvas': Color(0xFFFFFCF6),
  'surface': Color(0xFFF8F5EE),
  'sidebar': Color(0xFFF2EFE6),
  'elevated': Color(0xFFFFFDF8),
};

const _paperSurfaces = {
  'canvas': Color(0xFFFBF5E9),
  'surface': Color(0xFFFEF8EE),
  'sidebar': Color(0xFFF0E6D4),
  'elevated': Color(0xFFFFFAF0),
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final paper = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );
  final appearances = <String, BaseAppearance>{
    'desktop': DesktopAppearance(),
    'mobile': MobileAppearance(),
  };
  final lightThemes = {'normal Light': AppTheme.fallback, 'Paper': paper};

  for (final entry in lightThemes.entries) {
    final appTheme = entry.value;
    final isPaper = appTheme.themeName == BuiltInTheme.paper;
    final expected = isPaper ? _paperSurfaces : _lightSurfaces;

    test('${entry.key} has the requested opaque cream surfaces', () {
      final palette = _resolve(appTheme, Brightness.light);
      expect(palette.isPaper, isPaper);
      expect(_surfaces(palette), expected);
      for (final surface in _surfaces(palette).entries) {
        _expectWarm(surface.value, '${entry.key} ${surface.key}');
      }
      if (isPaper) {
        expect(PaperTheme.editorBackground, _paperSurfaces['canvas']);
        expect(PaperTheme.editorPreviewBackground, _paperSurfaces['surface']);
        expect(PaperTheme.sidebarBackground, _paperSurfaces['sidebar']);
        expect(PaperTheme.popupBackground, _paperSurfaces['elevated']);
        expect(palette.paperGrain.a, greaterThan(0));
      } else {
        expect(palette.paperGrain, Colors.transparent);
        expect(palette.canvas, isNot(PaperTheme.editorBackground));
        expect(palette.sidebar, isNot(PaperTheme.sidebarBackground));
      }
    });

    test('${entry.key} has measurable, subtle canvas/sidebar separation', () {
      final palette = _resolve(appTheme, Brightness.light);
      final canvasLuminance = palette.canvas.computeLuminance();
      final sidebarLuminance = palette.sidebar.computeLuminance();
      final difference = canvasLuminance - sidebarLuminance;
      final ratio = _contrast(palette.canvas, palette.sidebar);

      // These are adjacent surfaces, not text. Calculate the actual sRGB
      // luminance rather than assuming an RGB distance is a contrast ratio.
      expect(
        difference,
        greaterThanOrEqualTo(0.06),
        reason: '${entry.key}: canvas=$canvasLuminance, '
            'sidebar=$sidebarLuminance, difference=$difference',
      );
      expect(
        ratio,
        greaterThanOrEqualTo(1.05),
        reason: '${entry.key}: measured surface ratio=$ratio',
      );
      expect(ratio, lessThan(1.5), reason: 'Surfaces should remain subtle.');
      expect(_surfaces(palette).values.toSet(), hasLength(4));
    });

    test('${entry.key} preserves body and supporting-text contrast', () {
      final palette = _resolve(appTheme, Brightness.light);
      for (final surface in _surfaces(palette).entries) {
        _expectContrast(
          palette.textPrimary,
          surface.value,
          4.5,
          '${entry.key} body on ${surface.key}',
        );
        _expectContrast(
          palette.textSecondary,
          surface.value,
          4.5,
          '${entry.key} secondary text on ${surface.key}',
        );
      }
      // Muted captions are a separate metadata tier, not body text. They are
      // checked on the reading surfaces, not the darker sidebar/control fills.
      for (final surface in [
        palette.canvas,
        palette.surface,
        palette.floatingSurface,
      ]) {
        _expectContrast(palette.textMuted, surface, 3, '${entry.key} caption');
      }
      for (final fill in [
        palette.mutedSurface,
        palette.hover,
        palette.pressed,
        palette.selected,
      ]) {
        _expectContrast(palette.textPrimary, fill, 4.5, '${entry.key} control');
      }
    });

    for (final appearance in appearances.entries) {
      test('${appearance.key} ${entry.key} maps cream into both design systems',
          () {
        final material =
            _material(appearance.value, appTheme, Brightness.light);
        final palette = material.extension<PremiumThemeExtension>()!;
        final legacy = material.extension<AFThemeExtension>()!;
        final appFlowy = PremiumTheme.appFlowyTheme(
          base: AppFlowyDefaultTheme().light(),
          palette: palette,
          brightness: Brightness.light,
        );

        expect(_surfaces(palette), expected);
        expect(material.extension<PaperThemeExtension>()!.enabled, isPaper);
        expect(material.canvasColor, expected['canvas']);
        expect(material.scaffoldBackgroundColor, expected['canvas']);
        expect(material.colorScheme.surface, expected['canvas']);
        expect(material.colorScheme.surfaceContainerLow, expected['surface']);
        expect(
          material.colorScheme.surfaceContainerHighest,
          expected['sidebar'],
        );
        expect(material.colorScheme.surfaceBright, expected['elevated']);
        expect(material.cardColor, expected['elevated']);
        expect(material.dialogTheme.backgroundColor, expected['elevated']);
        expect(material.popupMenuTheme.color, expected['elevated']);
        expect(
          material.menuTheme.style!.backgroundColor!.resolve(const {}),
          expected['elevated'],
        );
        expect(material.colorScheme.surfaceTint, Colors.transparent);
        expect(legacy.background, expected['canvas']);
        expect(legacy.tableCellBGColor, expected['surface']);
        expect(legacy.greyHover, palette.hover);
        expect(legacy.greySelect, palette.selected);
        expect(appFlowy.backgroundColorScheme.primary, expected['canvas']);
        expect(appFlowy.surfaceColorScheme.layer01, expected['surface']);
        expect(
          appFlowy.surfaceContainerColorScheme.layer01,
          expected['sidebar'],
        );
        expect(appFlowy.surfaceColorScheme.primary, expected['elevated']);
        expect(appFlowy.fillColorScheme.primary, palette.mutedSurface);
        expect(
          appFlowy.fillColorScheme.primaryHover,
          Color.alphaBlend(palette.subtleHover, palette.mutedSurface),
        );
        expect(appFlowy.fillColorScheme.contentHover, palette.subtleHover);
        _expectQuietWarmHover(
          appFlowy.fillColorScheme.contentHover,
          palette.mutedSurface,
          '${appearance.key} ${entry.key} primary hover',
        );
        expect(appFlowy.fillColorScheme.secondary, palette.pressed);
        expect(appFlowy.fillColorScheme.secondaryHover, palette.selected);
        expect(appFlowy.fillColorScheme.content.a, 0);
        expect(
          appFlowy.fillColorScheme.content.withValues(alpha: 1),
          expected['elevated'],
        );
        _expectContrast(
          material.textTheme.bodyMedium!.color!,
          material.scaffoldBackgroundColor,
          4.5,
          '${appearance.key} actual body style',
        );
      });
    }

    testWidgets('${entry.key} workspace and editor helpers use the cream roles',
        (tester) async {
      final material =
          _material(DesktopAppearance(), appTheme, Brightness.light);
      late WorkspacePalette workspace;
      late bool paperEnabled;
      late Color editorCanvas;
      late Color editorPreview;
      late Color inlineCode;
      late TextStyle body;
      late TextStyle metadata;
      late TextStyle caption;

      await tester.pumpWidget(
        MaterialApp(
          theme: material,
          home: Builder(
            builder: (context) {
              workspace = WorkspacePalette.of(context);
              paperEnabled = PaperTheme.isEnabled(context);
              editorCanvas = EditorSurfaceStyle.canvasBackgroundFor(
                Theme.of(context).brightness,
                Theme.of(context).scaffoldBackgroundColor,
                isPaper: paperEnabled,
              );
              editorPreview = EditorSurfaceStyle.previewBackgroundFor(
                Theme.of(context).brightness,
                PremiumThemeExtension.of(context).surface,
                isPaper: paperEnabled,
              );
              inlineCode = EditorSurfaceStyle.inlineCodeBackground(context);
              body = WorkspaceTypography.style(context, WorkspaceTextRole.body);
              metadata = WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
              );
              caption = WorkspaceTypography.style(
                context,
                WorkspaceTextRole.caption,
              );
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      expect(paperEnabled, isPaper);
      expect(workspace.isDark, isFalse);
      expect(workspace.background, expected['canvas']);
      expect(workspace.surface, expected['surface']);
      expect(workspace.elevatedSurface, expected['elevated']);
      expect(editorCanvas, expected['canvas']);
      expect(editorPreview, expected['surface']);
      expect(
        inlineCode,
        material.extension<PremiumThemeExtension>()!.mutedSurface,
      );
      expect(body.color, workspace.primaryText);
      expect(metadata.color, workspace.secondaryText);
      expect(caption.color, workspace.mutedText);
      _expectContrast(body.color!, workspace.background, 4.5, 'workspace body');
      _expectContrast(
        metadata.color!,
        workspace.background,
        4.5,
        'workspace metadata',
      );
      _expectContrast(
        caption.color!,
        workspace.background,
        3,
        'workspace caption',
      );
      expect(tester.takeException(), isNull);
    });
  }

  test('Paper controls and composited interaction washes stay warm', () {
    final palette = _resolve(paper, Brightness.light);
    final controls = {
      'code': PaperTheme.codeBlockBackground,
      'code header': PaperTheme.codeBlockHeaderBackground,
      'callout': PaperTheme.calloutBackground,
      'resting control': palette.mutedSurface,
      'hover': palette.hover,
      'pressed': palette.pressed,
      'selected': palette.selected,
    };
    expect(palette.mutedSurface, const Color(0xFFF4EAD9));
    expect(palette.hover, const Color(0xFFF0E7D9));
    expect(palette.pressed, const Color(0xFFE1D4C2));
    expect(palette.selected, const Color(0xFFD8C8B2));
    for (final control in controls.entries) {
      _expectWarm(control.value, control.key);
      _expectContrast(palette.textPrimary, control.value, 4.5, control.key);
    }
    expect(controls.values.toSet().length, greaterThanOrEqualTo(6));

    for (final surface in _surfaces(palette).entries) {
      _expectQuietWarmHover(
        palette.subtleHover,
        surface.value,
        'Paper hover on ${surface.key}',
      );
      for (final overlay in [
        palette.hoverOverlay,
        palette.subtleHover,
        palette.subtlePressed,
        palette.selectedOverlay,
        palette.focusRing,
      ]) {
        final painted = Color.alphaBlend(overlay, surface.value);
        _expectWarm(painted, 'interaction on ${surface.key}');
        expect(painted, isNot(surface.value));
        _expectContrast(palette.textPrimary, painted, 4.5, 'interaction body');
      }
    }
    final material = _material(DesktopAppearance(), paper, Brightness.light);
    final iconHover = material.iconButtonTheme.style!.backgroundColor!
        .resolve(const {WidgetState.hovered})!;
    final textPressed = material.textButtonTheme.style!.backgroundColor!
        .resolve(const {WidgetState.pressed})!;
    expect(iconHover, palette.subtleHover);
    _expectQuietWarmHover(iconHover, palette.canvas, 'Paper icon hover');
    expect(textPressed, palette.subtlePressed);
    expect(
      textPressed.a,
      allOf(greaterThan(iconHover.a), lessThanOrEqualTo(0.12)),
    );
  });

  test('default and Paper-selected dark themes share the same semantic tokens',
      () {
    const expected = {
      'canvas': Color(0xFF191A19),
      'surface': Color(0xFF232422),
      'sidebar': Color(0xFF20211F),
      'elevated': Color(0xFF2B2C29),
      'muted': Color(0xFF272825),
      'hover': Color(0xFF2B2C29),
      'pressed': Color(0xFF383A35),
      'selected': Color(0xFF333D37),
      'hover overlay': Color(0x0FFFFFF4),
      'selected overlay': Color(0x2498B7AA),
      'border': Color(0x16F0EFE8),
      'strong border': Color(0x38F0EFE8),
      'primary text': Color(0xFFEDECE7),
      'secondary text': Color(0xFFB6B5B0),
      'muted text': Color(0xFF918F89),
      'accent': Color(0xFF98B7AA),
      'accent hover': Color(0xFFB0CCBF),
      'accent pressed': Color(0xFF86A697),
      'on accent': Color(0xFF18221C),
      'focus': Color(0x6698B7AA),
      'shadow': Color(0x44000000),
      'scrim': Color(0x99000000),
      'grain': Colors.transparent,
    };
    for (final appTheme in [AppTheme.fallback, paper]) {
      final palette = _resolve(appTheme, Brightness.dark);
      expect(palette.isPaper, isFalse);
      expect(_allColors(palette), expected);
      for (final appearance in appearances.values) {
        final material = _material(appearance, appTheme, Brightness.dark);
        expect(
          _allColors(material.extension<PremiumThemeExtension>()!),
          expected,
        );
        expect(material.scaffoldBackgroundColor, expected['canvas']);
        expect(material.dialogTheme.backgroundColor, expected['elevated']);
      }
    }
  });

  testWidgets('selecting Paper does not paint paper over a dark workspace',
      (tester) async {
    final material = _material(DesktopAppearance(), paper, Brightness.dark);
    final palette = material.extension<PremiumThemeExtension>()!;
    late WorkspacePalette workspace;
    late Color canvas;
    late Color preview;
    await tester.pumpWidget(
      MaterialApp(
        theme: material,
        home: Builder(
          builder: (context) {
            workspace = WorkspacePalette.of(context);
            // The preference may still name Paper; brightness wins in the
            // actual surface helpers, not a test-only replacement of the flag.
            canvas = EditorSurfaceStyle.canvasBackgroundFor(
              Theme.of(context).brightness,
              palette.canvas,
              isPaper: PaperTheme.isEnabled(context),
            );
            preview = EditorSurfaceStyle.previewBackgroundFor(
              Theme.of(context).brightness,
              palette.surface,
              isPaper: PaperTheme.isEnabled(context),
            );
            return const SizedBox.shrink();
          },
        ),
      ),
    );
    expect(workspace.isDark, isTrue);
    expect(palette.isPaper, isFalse);
    expect(workspace.background, const Color(0xFF191A19));
    expect(workspace.surface, const Color(0xFF232422));
    expect(workspace.elevatedSurface, const Color(0xFF2B2C29));
    expect(canvas, palette.canvas);
    expect(preview, palette.surface);
    expect(canvas, isNot(PaperTheme.editorBackground));
    expect(preview, isNot(PaperTheme.editorPreviewBackground));
    expect(tester.takeException(), isNull);
  });

  for (final custom in AppTheme.builtins.where(
    (theme) =>
        theme.themeName != BuiltInTheme.defaultTheme &&
        theme.themeName != BuiltInTheme.paper,
  )) {
    test('${custom.themeName} keeps its selected identity, not Paper', () {
      final light = _resolve(custom, Brightness.light);
      final dark = _resolve(custom, Brightness.dark);
      final legacy = custom.darkTheme;

      expect(light.isPaper, isFalse);
      expect(light.canvas, _lightSurfaces['canvas']);
      expect(light.surface, _lightSurfaces['surface']);
      expect(light.floatingSurface, _lightSurfaces['elevated']);
      expect(
        light.sidebar,
        Color.alphaBlend(
          custom.lightTheme.sidebarBg.withValues(alpha: 0.22),
          _lightSurfaces['sidebar']!,
        ),
      );
      expect(light.sidebar, isNot(_lightSurfaces['sidebar']));
      expect(light.sidebar, isNot(PaperTheme.sidebarBackground));
      expect(light.accent, isNot(PaperTheme.accent));
      expect(light.paperGrain, Colors.transparent);
      expect(
        PremiumTheme.tintFor(custom.lightTheme.tint1, light),
        custom.lightTheme.tint1,
      );
      expect(dark.isPaper, isFalse);
      expect(dark.canvas, legacy.surface);
      expect(dark.surface, legacy.surface);
      expect(dark.floatingSurface, legacy.input);
      expect(dark.mutedSurface, legacy.hoverBG3);
      expect(dark.sidebar, legacy.sidebarBg);
      expect(dark.hover, legacy.hoverBG1);
      expect(dark.pressed, legacy.bg3);
      expect(dark.selected, legacy.selector);
      expect(dark.textPrimary, legacy.text);
      expect(dark.textSecondary, legacy.secondaryText);
      expect(dark.textMuted, legacy.hint);
      expect(dark.accent, legacy.primary);
      expect(dark.onAccent, legacy.onPrimary);
      expect(dark.paperGrain, Colors.transparent);
      for (final appearance in appearances.values) {
        final material = _material(appearance, custom, Brightness.light);
        expect(material.extension<PaperThemeExtension>()!.enabled, isFalse);
      }
    });
  }

  testWidgets('an explicitly selected extension theme keeps its own surfaces',
      (tester) async {
    const extensionId = 'workspace-cream-palette-test';
    final savedSelection = ExtensionThemeRegistry.selected.value;
    addTearDown(() {
      ExtensionThemeRegistry.selected.value = savedSelection;
      ExtensionThemeRegistry.unregisterAll(extensionId);
    });
    final base =
        _material(DesktopAppearance(), AppTheme.fallback, Brightness.light);
    final custom = base.extension<PremiumThemeExtension>()!.copyWith(
          canvas: const Color(0xFFF0F4FF),
          surface: const Color(0xFFE7ECFA),
          sidebar: const Color(0xFFDCE3F5),
          floatingSurface: const Color(0xFFF5F7FF),
        );
    var builds = 0;
    ExtensionThemeRegistry.register(
      ExtensionTheme(
        extensionId: extensionId,
        id: 'cool',
        name: 'Explicit cool theme',
        brightness: Brightness.light,
        build: (theme) {
          builds++;
          return theme.copyWith(
            scaffoldBackgroundColor: custom.canvas,
            canvasColor: custom.canvas,
            colorScheme: theme.colorScheme.copyWith(surface: custom.canvas),
            extensions: [
              ...theme.extensions.values,
              custom,
              const PaperThemeExtension(enabled: false),
            ],
          );
        },
      ),
    );
    ExtensionThemeRegistry.selected.value = '$extensionId/cool';
    final selected = ExtensionThemeRegistry.apply(base, Brightness.light);
    late WorkspacePalette workspace;
    late bool paperEnabled;

    await tester.pumpWidget(
      MaterialApp(
        theme: selected,
        home: Builder(
          builder: (context) {
            workspace = WorkspacePalette.of(context);
            paperEnabled = PaperTheme.isEnabled(context);
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    expect(builds, 1);
    expect(paperEnabled, isFalse);
    expect(selected.extension<PremiumThemeExtension>(), same(custom));
    expect(workspace.background, custom.canvas);
    expect(workspace.surface, custom.surface);
    expect(workspace.elevatedSurface, custom.floatingSurface);
    expect(workspace.background, isNot(_lightSurfaces['canvas']));
    expect(workspace.background, isNot(PaperTheme.editorBackground));
    final dark =
        _material(DesktopAppearance(), AppTheme.fallback, Brightness.dark);
    expect(ExtensionThemeRegistry.apply(dark, Brightness.dark), same(dark));
    expect(
      builds,
      1,
      reason: 'A selected Light extension must not repaint Dark.',
    );
    expect(dark.extension<PremiumThemeExtension>()!.isPaper, isFalse);
    expect(tester.takeException(), isNull);
  });
}

PremiumThemeExtension _resolve(AppTheme theme, Brightness brightness) =>
    PremiumTheme.resolve(
      appTheme: theme,
      legacy:
          brightness == Brightness.light ? theme.lightTheme : theme.darkTheme,
      brightness: brightness,
    );

ThemeData _material(
  BaseAppearance appearance,
  AppTheme theme,
  Brightness brightness,
) =>
    appearance.getThemeData(
      theme,
      brightness,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

Map<String, Color> _surfaces(PremiumThemeExtension palette) => {
      'canvas': palette.canvas,
      'surface': palette.surface,
      'sidebar': palette.sidebar,
      'elevated': palette.floatingSurface,
    };

Map<String, Color> _allColors(PremiumThemeExtension palette) => {
      ..._surfaces(palette),
      'muted': palette.mutedSurface,
      'hover': palette.hover,
      'pressed': palette.pressed,
      'selected': palette.selected,
      'hover overlay': palette.hoverOverlay,
      'selected overlay': palette.selectedOverlay,
      'border': palette.border,
      'strong border': palette.borderStrong,
      'primary text': palette.textPrimary,
      'secondary text': palette.textSecondary,
      'muted text': palette.textMuted,
      'accent': palette.accent,
      'accent hover': palette.accentHover,
      'accent pressed': palette.accentPressed,
      'on accent': palette.onAccent,
      'focus': palette.focusRing,
      'shadow': palette.shadow,
      'scrim': palette.scrim,
      'grain': palette.paperGrain,
    };

void _expectWarm(Color color, String role) {
  expect(color.a, 1, reason: '$role must be opaque');
  expect(color, isNot(Colors.white), reason: role);
  expect(color.r, greaterThanOrEqualTo(color.g), reason: role);
  expect(color.g, greaterThan(color.b), reason: role);
}

void _expectQuietWarmHover(Color hover, Color surface, String role) {
  expect(
    hover.a,
    allOf(greaterThan(0), lessThanOrEqualTo(0.07)),
    reason: role,
  );
  final painted = Color.alphaBlend(hover, surface);
  _expectWarm(painted, role);
  expect(
    _contrast(painted, surface),
    allOf(greaterThan(1), lessThan(1.15)),
    reason: '$role must be visible without becoming an opaque selection fill.',
  );
}

double _contrast(Color foreground, Color background) {
  final paintedLuminance =
      Color.alphaBlend(foreground, background).computeLuminance();
  final backgroundLuminance = background.computeLuminance();
  final lighter = paintedLuminance > backgroundLuminance
      ? paintedLuminance
      : backgroundLuminance;
  final darker = paintedLuminance > backgroundLuminance
      ? backgroundLuminance
      : paintedLuminance;
  return (lighter + 0.05) / (darker + 0.05);
}

void _expectContrast(Color ink, Color background, double minimum, String role) {
  final ratio = _contrast(ink, background);
  expect(
    ratio,
    greaterThanOrEqualTo(minimum),
    reason: '$role: measured ratio=$ratio',
  );
}
