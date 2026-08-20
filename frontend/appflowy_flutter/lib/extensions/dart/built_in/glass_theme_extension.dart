import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// A translucent appearance, supplied entirely by an extension.
///
/// This is the worked example for the theme tier, and it is the thing a
/// scripting tier could not have done: every surface in the app reads
/// [PremiumThemeExtension], so rewriting that one object re-skins menus,
/// dialogs, the sidebar and the editor at once — no per-widget callback, and
/// nothing to repaint at 120 Hz.
///
/// The blur itself already exists (`PremiumThemeBackdrop`); what makes it read
/// as glass is surfaces that let it through.
class GlassThemeExtension extends AppFlowyExtension {
  @override
  DartExtensionInfo get info => const DartExtensionInfo(
        id: 'glass',
        name: 'Glass',
        description: 'A translucent appearance for light and dark.',
      );

  @override
  Future<void> activate(ExtensionContext context) async {
    final ctx = context as DartExtensionContext;

    ctx.themes.add(
      id: 'light',
      name: 'Glass (light)',
      brightness: Brightness.light,
      build: (base) => _glass(base, tint: Colors.white),
    );

    ctx.themes.add(
      id: 'dark',
      name: 'Glass (dark)',
      brightness: Brightness.dark,
      build: (base) => _glass(base, tint: const Color(0xFF1B1D21)),
    );
  }

  static ThemeData _glass(ThemeData base, {required Color tint}) {
    final palette = base.extension<PremiumThemeExtension>();
    if (palette == null) {
      return base;
    }
    Color veil(Color over, double alpha) =>
        Color.alphaBlend(tint.withValues(alpha: alpha), over);

    final glassed = palette.copyWith(
      // The canvas stays opaque; it is what everything else is seen against.
      surface: veil(palette.surface, 0.55),
      floatingSurface: veil(palette.floatingSurface, 0.4),
      mutedSurface: veil(palette.mutedSurface, 0.5),
      sidebar: veil(palette.sidebar, 0.45),
      border: palette.border.withValues(alpha: 0.35),
      borderStrong: palette.borderStrong.withValues(alpha: 0.5),
      hover: palette.hover.withValues(alpha: 0.5),
      selected: palette.selected.withValues(alpha: 0.6),
    );

    final others =
        base.extensions.values.where((e) => e is! PremiumThemeExtension);

    return base.copyWith(
      extensions: [...others, glassed],
      cardColor: glassed.surface,
      canvasColor: glassed.surface,
      dialogTheme: base.dialogTheme.copyWith(
        backgroundColor: glassed.floatingSurface,
      ),
      popupMenuTheme: base.popupMenuTheme.copyWith(
        color: glassed.floatingSurface,
      ),
    );
  }
}
