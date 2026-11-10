import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/legible_color.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:flutter/material.dart';

/// Ink for type and buttons laid straight on a page's cover rather than on
/// the page, so they stay legible over the picture in every theme.
abstract final class CoverInk {
  /// Dark type for light artwork, whatever the theme.
  static const dark = Color(0xFF252522);

  /// The ink over [cover], or null where the theme's own ink applies.
  ///
  /// A photograph gets white, over a shade. The abstract artwork is light
  /// whatever the theme, so it keeps dark ink even in dark mode, where the
  /// theme's light ink sat at under 2:1 on it. A plain colour or gradient
  /// takes whichever of the two reads better on it.
  static Color? over(BuildContext context, PageStyleCover cover) {
    if (cover.isNone) {
      return null;
    }
    if (cover.isPhotographic) {
      return Colors.white;
    }
    final Color? fill;
    if (cover.isPureColor) {
      fill = cover.value.coverColor(context);
    } else if (cover.isGradient) {
      final colors = FlowyGradientColor.fromId(cover.value).linear.colors;
      fill = Color.lerp(colors.first, colors.last, 0.5);
    } else {
      return dark;
    }
    if (fill == null) {
      return null;
    }
    return LegibleColor.contrast(Colors.white, fill) >
            LegibleColor.contrast(dark, fill)
        ? Colors.white
        : dark;
  }

  /// The ink and the disc behind it for a small button on [cover], or null
  /// where the theme's own ink applies.
  ///
  /// A cover is not one colour where a button sits — the abstract artwork
  /// has dark swirls beside pale ones — so the glyph gets a disc of the
  /// opposite tone. Over every built-in cover that keeps it above 3:1.
  static ({Color ink, Color disc})? button(
    BuildContext context,
    PageStyleCover? cover,
  ) {
    if (cover == null) {
      return null;
    }
    final ink = over(context, cover);
    if (ink == null) {
      return null;
    }
    return (
      ink: ink,
      disc: ink.computeLuminance() > 0.5
          ? Colors.black.withValues(alpha: 0.35)
          : Colors.white.withValues(alpha: 0.5),
    );
  }
}
