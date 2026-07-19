import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';

class PaperThemeExtension extends ThemeExtension<PaperThemeExtension> {
  const PaperThemeExtension({required this.enabled});

  final bool enabled;

  @override
  PaperThemeExtension copyWith({bool? enabled}) =>
      PaperThemeExtension(enabled: enabled ?? this.enabled);

  @override
  PaperThemeExtension lerp(
    covariant ThemeExtension<PaperThemeExtension>? other,
    double t,
  ) =>
      other is PaperThemeExtension && t >= 0.5 ? other : this;
}

abstract final class PaperTheme {
  static const editorBackground = Color(0xFFFFFCF5);
  static const editorPreviewBackground = Color(0xFFFCFBF9);
  static const codeBlockBackground = Color(0xFFF7F4ED);
  static const calloutBackground = Color(0xFFF8F5EE);
  static const sidebarBackground = Color(0xFFF8F3E8);
  static const popupBackground = Color(0xFFFFF8EE);

  static bool isPaper(AppTheme theme) => theme.themeName == BuiltInTheme.paper;

  static bool isEnabled(BuildContext context) =>
      Theme.of(context).extension<PaperThemeExtension>()?.enabled ?? false;

  static AppFlowyThemeData appFlowyTheme({
    required AppFlowyThemeData base,
    required bool enabled,
    required Brightness brightness,
  }) {
    if (!enabled || brightness != Brightness.light) {
      return base;
    }

    final surface = base.surfaceColorScheme;
    final surfaceContainer = base.surfaceContainerColorScheme;
    return AppFlowyThemeData(
      textColorScheme: base.textColorScheme,
      textStyle: base.textStyle,
      iconColorScheme: base.iconColorScheme,
      borderColorScheme: base.borderColorScheme,
      backgroundColorScheme: const AppFlowyBackgroundColorScheme(
        primary: popupBackground,
      ),
      fillColorScheme: base.fillColorScheme,
      surfaceColorScheme: AppFlowySurfaceColorScheme(
        primary: popupBackground,
        primaryHover: surface.primaryHover,
        layer01: popupBackground,
        layer01Hover: surface.layer01Hover,
        layer02: popupBackground,
        layer02Hover: surface.layer02Hover,
        layer03: popupBackground,
        layer03Hover: surface.layer03Hover,
        layer04: popupBackground,
        layer04Hover: surface.layer04Hover,
        inverse: surface.inverse,
        secondary: surface.secondary,
        overlay: surface.overlay,
      ),
      borderRadius: base.borderRadius,
      spacing: base.spacing,
      shadow: base.shadow,
      brandColorScheme: base.brandColorScheme,
      surfaceContainerColorScheme: AppFlowySurfaceContainerColorScheme(
        layer01: sidebarBackground,
        layer02: popupBackground,
        layer03: surfaceContainer.layer03,
      ),
      badgeColorScheme: base.badgeColorScheme,
      otherColorsColorScheme: base.otherColorsColorScheme,
    );
  }
}
