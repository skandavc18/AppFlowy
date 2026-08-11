import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:flutter/material.dart';

/// The colours a mind map is drawn with.
///
/// Branch accents are soft on purpose: a map with eight colours shouting at
/// once is a diagramming tool, not a thinking surface.
@immutable
class MindMapPalette {
  const MindMapPalette({
    required this.canvas,
    required this.node,
    required this.nodeHover,
    required this.rootFill,
    required this.onRoot,
    required this.line,
    required this.text,
    required this.textMuted,
    required this.accent,
    required this.selection,
    required this.shadow,
    required this.branches,
    required this.isDark,
  });

  factory MindMapPalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isDark = theme.brightness == Brightness.dark;
    final isPaper = !isDark && PaperTheme.isEnabled(context);

    if (isPaper) {
      return const MindMapPalette(
        canvas: PaperTheme.editorBackground,
        node: PaperTheme.popupBackground,
        nodeHover: PaperTheme.controlBackground,
        rootFill: PaperTheme.accent,
        onRoot: PaperTheme.onAccent,
        line: Color(0x59675443),
        text: PaperTheme.textPrimary,
        textMuted: PaperTheme.textMuted,
        accent: PaperTheme.accent,
        selection: PaperTheme.accent,
        shadow: PaperTheme.shadow,
        branches: _paperBranches,
        isDark: false,
      );
    }

    final accent = premium?.accent ?? theme.colorScheme.primary;
    return MindMapPalette(
      canvas: premium?.canvas ?? theme.colorScheme.surface,
      node: premium?.floatingSurface ?? theme.colorScheme.surfaceBright,
      nodeHover: premium?.hover ?? theme.colorScheme.surfaceContainerHighest,
      rootFill: accent,
      onRoot: premium?.onAccent ?? theme.colorScheme.onPrimary,
      line: (premium?.border ?? theme.colorScheme.outlineVariant)
          .withValues(alpha: isDark ? 0.85 : 0.9),
      text: premium?.textPrimary ?? theme.colorScheme.onSurface,
      textMuted: premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
      accent: accent,
      selection: accent,
      shadow: (premium?.shadow ?? Colors.black)
          .withValues(alpha: isDark ? 0.42 : 0.10),
      branches: isDark ? _darkBranches : _lightBranches,
      isDark: isDark,
    );
  }

  final Color canvas;
  final Color node;
  final Color nodeHover;
  final Color rootFill;
  final Color onRoot;
  final Color line;
  final Color text;
  final Color textMuted;
  final Color accent;
  final Color selection;
  final Color shadow;
  final List<Color> branches;
  final bool isDark;

  Color branchAt(int index) => branches[index.abs() % branches.length];

  /// The surface a node wears once a colour has been chosen for it.
  ///
  /// The accent is blended into the node rather than replacing it, so a
  /// coloured box still belongs to the paper it sits on.
  Color fillFor(Color accent, {bool hovered = false}) => Color.alphaBlend(
        accent.withValues(
          alpha: isDark ? (hovered ? 0.46 : 0.36) : (hovered ? 0.32 : 0.24),
        ),
        node,
      );

  /// Ink that stays readable on [surface].
  Color inkOn(Color surface) => surface.computeLuminance() > 0.5
      ? const Color(0xFF1B1E22)
      : const Color(0xFFF7F8FA);

  @override
  bool operator ==(Object other) =>
      other is MindMapPalette &&
      other.canvas == canvas &&
      other.node == node &&
      other.accent == accent &&
      other.isDark == isDark;

  @override
  int get hashCode => Object.hash(canvas, node, accent, isDark);
}

const _lightBranches = <Color>[
  Color(0xFF5B8DEF),
  Color(0xFF57B894),
  Color(0xFFE0995E),
  Color(0xFFCE6E7C),
  Color(0xFF8F7BD3),
  Color(0xFF4FADC4),
  Color(0xFFBE9A4C),
  Color(0xFF7E8CA0),
];

const _darkBranches = <Color>[
  Color(0xFF7BA6F5),
  Color(0xFF6FC9A6),
  Color(0xFFE8AC74),
  Color(0xFFDE8391),
  Color(0xFFA694E0),
  Color(0xFF69C2D6),
  Color(0xFFD1AF64),
  Color(0xFF95A2B5),
];

const _paperBranches = <Color>[
  Color(0xFF6E7FA8),
  Color(0xFF6F9077),
  Color(0xFFBF8A55),
  Color(0xFFB0707A),
  Color(0xFF8A7BA4),
  Color(0xFF5F94A0),
  Color(0xFF9B8046),
  Color(0xFF87816F),
];

/// The geometry and motion of the canvas.
abstract final class MindMapCanvasMetrics {
  static const double nodeRadius = 12;
  static const double rootRadius = 18;
  static const double nodePaddingX = 18;
  static const double nodePaddingY = 12;
  static const double minimumNodeWidth = 92;
  static const double minimumNodeHeight = 44;
  static const double maximumNodeWidth = 300;

  /// How many lines a node wraps to before it stops growing.
  static const int maximumNodeLines = 6;

  static const double minimumScale = 0.25;
  static const double maximumScale = 3;

  static const Duration motion = Duration(milliseconds: 180);
  static const Curve curve = Curves.easeOutCubic;

  static double fontSizeFor(int depth) => switch (depth) {
        0 => 16,
        1 => 14.5,
        _ => 13.5,
      };

  static FontWeight weightFor(int depth) =>
      depth <= 1 ? FontWeight.w600 : FontWeight.w500;
}
