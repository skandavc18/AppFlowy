import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/context_menu_surface_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/mobile_appearance.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flowy_infra_ui/style_widget/font_weight.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final paperTheme = AppTheme.builtins.firstWhere(
    (theme) => theme.themeName == BuiltInTheme.paper,
  );

  test('context menus use a distinct warm tint only for light Paper', () {
    const darkFallback = Color(0xFF202020);

    expect(
      ContextMenuSurfaceStyle.backgroundFor(
        Brightness.light,
        darkFallback,
        isPaper: true,
      ),
      PaperTheme.popupBackground,
    );
    expect(
      ContextMenuSurfaceStyle.lightBackground,
      isNot(EditorSurfaceStyle.lightCanvasBackground),
    );
    expect(
      ContextMenuSurfaceStyle.lightBackground,
      isNot(SidebarStyle.lightBackground),
    );
    expect(
      ContextMenuSurfaceStyle.backgroundFor(
        Brightness.light,
        darkFallback,
      ),
      darkFallback,
    );
    expect(
      ContextMenuSurfaceStyle.backgroundFor(
        Brightness.dark,
        darkFallback,
        isPaper: true,
      ),
      darkFallback,
    );
  });

  test('editor canvas uses warm tint only for light Paper', () {
    const darkFallback = Color(0xFF202020);

    expect(
      EditorSurfaceStyle.canvasBackgroundFor(
        Brightness.light,
        darkFallback,
        isPaper: true,
      ),
      PaperTheme.editorBackground,
    );
    expect(
      EditorSurfaceStyle.canvasBackgroundFor(
        Brightness.light,
        darkFallback,
      ),
      darkFallback,
    );
    expect(
      EditorSurfaceStyle.canvasBackgroundFor(
        Brightness.dark,
        darkFallback,
        isPaper: true,
      ),
      darkFallback,
    );
    expect(
      EditorSurfaceStyle.codeBlockHeaderBackgroundFor(
        Brightness.light,
        darkFallback,
        isPaper: true,
      ),
      PaperTheme.codeBlockHeaderBackground,
    );
    expect(
      EditorSurfaceStyle.codeBlockBorderFor(
        Brightness.light,
        darkFallback,
        isPaper: true,
      ),
      PaperTheme.codeBlockBorder,
    );
    expect(
      EditorSurfaceStyle.codeBlockHeaderBackgroundFor(
        Brightness.dark,
        darkFallback,
        isPaper: true,
      ),
      darkFallback,
    );
  });

  test('Paper themes dialogs, settings sidebar, and AppFlowy surfaces', () {
    final materialTheme = DesktopAppearance().getThemeData(
      paperTheme,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    final palette = materialTheme.extension<PremiumThemeExtension>()!;
    final appFlowyTheme = PremiumTheme.appFlowyTheme(
      base: AppFlowyDefaultTheme().light(),
      palette: palette,
      brightness: Brightness.light,
    );

    expect(
      materialTheme.dialogBackgroundColor,
      ContextMenuSurfaceStyle.lightBackground,
    );
    expect(
      materialTheme.cardColor,
      ContextMenuSurfaceStyle.lightBackground,
    );
    expect(
      appFlowyTheme.surfaceColorScheme.primary,
      ContextMenuSurfaceStyle.lightBackground,
    );
    expect(
      appFlowyTheme.surfaceColorScheme.layer04,
      ContextMenuSurfaceStyle.lightBackground,
    );
    expect(
      appFlowyTheme.backgroundColorScheme.primary,
      PaperTheme.editorBackground,
    );
    expect(
      appFlowyTheme.surfaceContainerColorScheme.layer01,
      PaperTheme.sidebarBackground,
    );
    expect(
      appFlowyTheme.surfaceContainerColorScheme.layer03,
      PaperTheme.controlSelected,
    );
    expect(
      appFlowyTheme.fillColorScheme.primary,
      PaperTheme.controlBackground,
    );
    expect(
      appFlowyTheme.fillColorScheme.contentHover,
      PaperTheme.hoverOverlay,
    );
    expect(
      appFlowyTheme.fillColorScheme.themeSelect,
      PaperTheme.selectedOverlay,
    );
    expect(appFlowyTheme.fillColorScheme.themeThick, PaperTheme.accent);
    expect(
      appFlowyTheme.borderColorScheme.primary,
      PaperTheme.codeBlockBorder,
    );
    expect(materialTheme.colorScheme.primary, PaperTheme.accent);
    expect(materialTheme.colorScheme.surface, PaperTheme.editorBackground);
    expect(
      materialTheme.colorScheme.surfaceContainerHighest,
      PaperTheme.sidebarBackground,
    );
    expect(materialTheme.dividerColor, PaperTheme.codeBlockBorder);
    expect(materialTheme.hoverColor, PaperTheme.hoverOverlay);
  });

  test('Paper warms mobile Material surfaces and interactions', () {
    final materialTheme = MobileAppearance().getThemeData(
      paperTheme,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );

    expect(materialTheme.scaffoldBackgroundColor, PaperTheme.editorBackground);
    expect(materialTheme.colorScheme.surface, PaperTheme.editorBackground);
    expect(
      materialTheme.colorScheme.surfaceContainerLowest,
      PaperTheme.popupBackground,
    );
    expect(
      materialTheme.colorScheme.surfaceContainerHighest,
      PaperTheme.sidebarBackground,
    );
    expect(materialTheme.colorScheme.primary, PaperTheme.accent);
    expect(materialTheme.dividerColor, PaperTheme.codeBlockBorder);
  });

  test('Default Light uses warm premium surfaces without Paper tint', () {
    final materialTheme = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    final palette = materialTheme.extension<PremiumThemeExtension>()!;
    final appFlowyTheme = PremiumTheme.appFlowyTheme(
      base: AppFlowyDefaultTheme().light(),
      palette: palette,
      brightness: Brightness.light,
    );

    expect(materialTheme.dialogBackgroundColor, palette.floatingSurface);
    expect(materialTheme.dialogBackgroundColor, isNot(Colors.white));
    expect(palette.isPaper, isFalse);
    expect(
      appFlowyTheme.surfaceColorScheme.primary,
      isNot(ContextMenuSurfaceStyle.lightBackground),
    );
    expect(
      appFlowyTheme.backgroundColorScheme.primary,
      isNot(ContextMenuSurfaceStyle.lightBackground),
    );
  });

  testWidgets('code blocks use polished 550 text and warm surfaces',
      (tester) async {
    final appearanceCubit = DocumentAppearanceCubit();
    addTearDown(appearanceCubit.close);
    late CodeBlockStyle codeBlockStyle;
    final theme = DesktopAppearance()
        .getThemeData(
          paperTheme,
          Brightness.light,
          defaultFontFamily,
          builtInCodeFontFamily,
        )
        .copyWith(platform: TargetPlatform.windows);

    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: BlocProvider.value(
          value: appearanceCubit,
          child: Builder(
            builder: (context) {
              codeBlockStyle = EditorStyleCustomizer(
                context: context,
                padding: EdgeInsets.zero,
              ).codeBlockStyleBuilder();
              return const SizedBox.shrink();
            },
          ),
        ),
      ),
    );

    final textStyle = codeBlockStyle.textStyle!;
    expect(
      textStyle.fontFamily?.replaceAll(' ', ''),
      contains('JetBrainsMono'),
    );
    expect(textStyle.fontWeight, FontWeight.w500);
    expect(textStyle.fontVariations, flowyRegularFontVariations);
    expect(textStyle.fontFeatures, isNotEmpty);
    expect(textStyle.color, ObjectTypeTypography.lightEditorTextColor);
    expect(textStyle.shadows, isNotEmpty);
    expect(
      codeBlockStyle.backgroundColor,
      EditorSurfaceStyle.lightCodeBlockBackground,
    );
    expect(
      theme.extension<AFThemeExtension>()?.calloutBGColor,
      EditorSurfaceStyle.lightCalloutBackground,
    );
  });
}
