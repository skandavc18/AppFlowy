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
  // Warm, low-contrast stationery layers. None of the opaque surfaces are
  // pure white, so floating elements remain integrated with the paper canvas.
  static const editorBackground = Color(0xFFF7F1E7);
  static const editorPreviewBackground = Color(0xFFFAF5EB);
  static const codeBlockBackground = Color(0xFFF2EADF);
  static const codeBlockHeaderBackground = Color(0xFFECE2D4);
  static const codeBlockBorder = Color(0x24675443);
  static const strongBorder = Color(0x3D675443);
  static const calloutBackground = Color(0xFFF3EBDE);
  static const sidebarBackground = Color(0xFFF0E8DA);
  static const popupBackground = Color(0xFFFCF7ED);
  static const controlBackground = Color(0xFFF2EADD);
  static const controlHover = Color(0xFFEAE0D1);
  static const controlSelected = Color(0xFFE1D4C2);
  static const controlSelectedHover = Color(0xFFD8C8B2);

  static const textPrimary = Color(0xFF3B352E);
  static const textSecondary = Color(0xFF6C6258);
  static const textMuted = Color(0xFF918577);
  static const onAccent = Color(0xFFFBF7EF);

  static const hoverOverlay = Color(0x12675443);
  static const selectedOverlay = Color(0x24715438);
  static const textSelection = Color(0x3D715438);
  static const accent = Color(0xFF715438);
  static const accentHover = Color(0xFF5E452D);
  static const accentPressed = Color(0xFF4E3925);
  static const focusRing = Color(0x47715438);
  static const resizeHandle = Color(0xFF7A6955);

  static const shadow = Color(0x12604F3E);
  static const scrim = Color(0x70504335);
  static const grain = Color(0x076A5947);

  static bool isPaper(AppTheme theme) => theme.themeName == BuiltInTheme.paper;

  static bool isEnabled(BuildContext context) =>
      Theme.of(context).extension<PaperThemeExtension>()?.enabled ?? false;
}
