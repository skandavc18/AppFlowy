import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:flutter/material.dart';

/// The folder explorer palette, tinted by the collection type's own hue.
///
/// The hue is never painted flat — it is always blended against the resolved
/// surface, so a collection reads the same in paper, light and dark.
@immutable
class CollectionPalette {
  const CollectionPalette._({
    required this.base,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
  });

  factory CollectionPalette.of(BuildContext context, CollectionKind kind) {
    final base = FolderExplorerPalette.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hue = CollectionRegistry.typeFor(kind).accent;
    final accent = isDark
        ? Color.lerp(hue, Colors.white, 0.24)!
        : Color.lerp(hue, Colors.black, 0.06)!;
    return CollectionPalette._(
      base: base,
      accent: accent,
      accentSoft: Color.alphaBlend(
        accent.withValues(alpha: isDark ? 0.17 : 0.10),
        base.surface,
      ),
      accentBorder: accent.withValues(alpha: isDark ? 0.32 : 0.22),
    );
  }

  final FolderExplorerPalette base;
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;

  Color get background => base.background;
  Color get surface => base.surface;
  Color get floatingSurface => base.floatingSurface;
  Color get hover => base.hover;
  Color get selected => base.selected;
  Color get border => base.border;
  Color get textPrimary => base.textPrimary;
  Color get textSecondary => base.textSecondary;
  Color get textMuted => base.textMuted;
}

abstract final class CollectionMetrics {
  static const headerHorizontalPadding = 28.0;
  static const headerTopPadding = 22.0;
  static const identityIconSize = 24.0;
  static const identityTileSize = 44.0;
  static const identityTileRadius = 13.0;
  static const switcherHeight = 32.0;
  static const switcherRadius = 10.0;
  static const switcherSegmentRadius = 8.0;
  static const searchFieldWidth = 236.0;
  static const searchFieldHeight = 32.0;
}
