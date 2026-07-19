import 'package:appflowy/plugins/document/application/document_appearance_cubit.dart';
import 'package:appflowy/plugins/document/presentation/editor_style.dart';
import 'package:appflowy/shared/context_menu_surface_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/object_type_typography.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
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
      const Color(0xFFFFF8EE),
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
      const Color(0xFFFFFCF5),
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
  });

  test('Paper themes dialogs, settings sidebar, and AppFlowy surfaces', () {
    final materialTheme = DesktopAppearance().getThemeData(
      paperTheme,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    final appFlowyTheme = PaperTheme.appFlowyTheme(
      base: AppFlowyDefaultTheme().light(),
      enabled: true,
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
      ContextMenuSurfaceStyle.lightBackground,
    );
    expect(
      appFlowyTheme.surfaceContainerColorScheme.layer01,
      PaperTheme.sidebarBackground,
    );
  });

  test('Default theme retains untinted surfaces', () {
    final materialTheme = DesktopAppearance().getThemeData(
      AppTheme.fallback,
      Brightness.light,
      defaultFontFamily,
      builtInCodeFontFamily,
    );
    final appFlowyTheme = AppFlowyDefaultTheme().light();

    expect(
      materialTheme.dialogBackgroundColor,
      AppTheme.fallback.lightTheme.surface,
    );
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
    expect(textStyle.fontFamily, builtInCodeFontFamily);
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
