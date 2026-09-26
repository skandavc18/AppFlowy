import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:flutter/material.dart';

/// The fixed geometry and motion the repository browser is drawn to.
///
/// Nothing here depends on the theme, so a tree row, a listing row and a
/// symbol row occupy exactly the same box whatever the appearance.
abstract final class RepoMetrics {
  /// Everything is laid out on an 8px grid; halves are the only exception.
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space6 = 24;
  static const double space8 = 32;

  /// Chrome.
  static const double toolbarHeight = 44;
  static const double paneHeadingHeight = 36;
  static const double stageHeaderHeight = 40;
  static const double gutter = CollectionWorkspaceMetrics.gutter;
  static const double paneWidth = 272;
  static const double railWidth = 248;

  /// The measure a repository page is laid out to. Past this the listing is
  /// all whitespace with a file name lost at either end.
  static const double readingWidth = 1080;

  /// Rows. Compact enough to see a project, tall enough to read it.
  static const double treeRowHeight = 32;
  static const double listRowHeight = 36;
  static const double symbolRowHeight = 30;
  static const double rowRadius = 8;

  /// Rows are inset from the pane edge so the hover pill floats rather than
  /// running to the wall, the way GitHub and VS Code draw a tree.
  static const double rowInset = 8;
  static const double rowPadding = 8;
  static const double indentWidth = 14;

  /// Icons sit in a fixed slot so every name starts on the same pixel.
  static const double iconSize = 15;
  static const double iconSlot = 16;
  static const double iconGap = 8;
  static const double chevronSlot = 14;
  static const double chevronSize = 14;

  /// Only a content object opts into rounded containment; rails stay unboxed.
  static const double panelRadius = WorkspaceTokens.cardRadius;
  static const double controlRadius = WorkspaceTokens.controlRadius;

  /// The whitespace that separates one pane from the next. Nothing is
  /// separated by a drawn line.
  static const double paneGap = CollectionWorkspaceMetrics.paneGap;

  /// Typography.
  static const double titleSize = 15;
  static const double rowSize = 12.5;
  static const double metaSize = 11.5;
  static const double sectionSize = 12;
  static const double codeSize = 12.5;
  static const double codeLineHeight = 1.6;
  static const double rowTracking = -0.004;
  static const double sectionTracking = 0;

  /// Variable-weight axes, a step above body copy so small text reads firm
  /// without tipping into bold.
  static const double rowWeightAxis = 500;
  static const double strongWeightAxis = 500;
  static const double sectionWeightAxis = 500;

  /// Motion. Restrained on purpose — no bounce, no spring.
  static const Duration hover = Duration(milliseconds: 140);
  static const Duration expand = Duration(milliseconds: 170);
  static const Duration reveal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}

/// Every colour the repository browser draws with, resolved once from the
/// collection palette so dark, light and paper all read as the same tool.
@immutable
class RepoTheme {
  const RepoTheme._({
    required this.palette,
    required this.brightness,
    required this.canvas,
    required this.panel,
    required this.raised,
    required this.sunken,
    required this.separator,
    required this.hairlineColor,
    required this.rowRule,
    required this.rowHover,
    required this.rowSelected,
    required this.rowActiveBar,
    required this.textStrong,
    required this.textBody,
    required this.textSoft,
    required this.textFaint,
    required this.iconRest,
    required this.accent,
    required this.accentSoft,
    required this.accentBorder,
    required this.shadows,
    required this.baseTextStyle,
  });

  factory RepoTheme.of(BuildContext context, CollectionPalette palette) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Structure comes from tint and whitespace, not outlines: a separator is
    // barely there and a panel is a shade, not a box.
    final separator = palette.border.withValues(alpha: isDark ? 0.42 : 0.5);
    return RepoTheme._(
      palette: palette,
      brightness: theme.brightness,
      canvas: palette.background,
      panel: palette.surface,
      raised: palette.floatingSurface,
      sunken: Color.alphaBlend(
        palette.hover
            .withValues(alpha: palette.hover.a * (isDark ? 0.42 : 0.6)),
        palette.background,
      ),
      separator: separator,
      hairlineColor: palette.border.withValues(alpha: isDark ? 0.26 : 0.34),
      // ⚠️ withValues REPLACES the alpha rather than scaling it, so a row rule
      // has to be derived from the base border, never from hairlineColor.
      rowRule: palette.border.withValues(alpha: isDark ? 0.14 : 0.17),
      rowHover: palette.hover
          .withValues(alpha: palette.hover.a * (isDark ? 0.62 : 0.8)),
      rowSelected: palette.accent.withValues(alpha: isDark ? 0.15 : 0.09),
      rowActiveBar: palette.accent,
      textStrong: palette.textPrimary,
      // Row text sits between the title and the metadata: GitHub's file names
      // are nearly as dark as its headings, which is what makes a listing
      // read as content rather than as a form.
      textBody: Color.lerp(palette.textSecondary, palette.textPrimary, 0.5)!,
      textSoft: palette.textSecondary,
      textFaint: palette.textMuted,
      iconRest: palette.textMuted.withValues(alpha: isDark ? 0.92 : 0.86),
      accent: palette.accent,
      accentSoft: palette.accentSoft,
      accentBorder: palette.accentBorder,
      shadows: [
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.3 : 0.045),
          blurRadius: 22,
          offset: const Offset(0, 8),
          spreadRadius: -10,
        ),
        BoxShadow(
          color: Colors.black.withValues(alpha: isDark ? 0.18 : 0.028),
          blurRadius: 3,
          offset: const Offset(0, 1),
          spreadRadius: -1,
        ),
      ],
      baseTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
    );
  }

  final CollectionPalette palette;
  final Brightness brightness;
  final Color canvas;
  final Color panel;
  final Color raised;

  /// A recessed strip, used for pane headings and listing headers.
  final Color sunken;
  final Color separator;
  final Color hairlineColor;

  /// The whisper of a line between two rows in a listing.
  final Color rowRule;
  final Color rowHover;
  final Color rowSelected;
  final Color rowActiveBar;
  final Color textStrong;
  final Color textBody;
  final Color textSoft;
  final Color textFaint;
  final Color iconRest;
  final Color accent;
  final Color accentSoft;
  final Color accentBorder;
  final List<BoxShadow> shadows;
  final TextStyle baseTextStyle;

  bool get isDark => brightness == Brightness.dark;

  /// A transparent stand-in that keeps a colour's own channels.
  ///
  /// Animating to or from [Colors.transparent] interpolates through
  /// transparent *black*, which flashes dark before it settles.
  Color transparentAs(Color color) => color.withValues(alpha: 0);

  List<Shadow> get _underprint =>
      AppTextRendering.rootStyleFor(brightness).shadows ?? const [];

  TextStyle face({
    required double fontSize,
    required Color color,
    double axis = RepoMetrics.rowWeightAxis,
    FontWeight weight = FontWeight.w500,
    double tracking = RepoMetrics.rowTracking,
    double height = 1.0,
  }) =>
      AppTextRendering.polish(
        baseTextStyle.copyWith(
          fontSize: fontSize,
          fontWeight: weight,
          // The bundled UI face is variable: without an explicit axis it
          // renders at its default instance and looks thin next to the app.
          fontVariations: [FontVariation.weight(axis)],
          height: height,
          letterSpacing: fontSize * tracking,
          color: color,
          shadows: _underprint,
          decoration: TextDecoration.none,
        ),
      );

  TextStyle get title => face(
        fontSize: RepoMetrics.titleSize,
        color: textStrong,
        height: 1.2,
      );

  TextStyle get rowLabel => face(
        fontSize: RepoMetrics.rowSize,
        color: textBody,
      );

  TextStyle get rowLabelStrong => face(
        fontSize: RepoMetrics.rowSize,
        color: textStrong,
      );

  TextStyle get meta => face(
        fontSize: RepoMetrics.metaSize,
        color: textSoft,
        weight: FontWeight.w400,
      );

  TextStyle get metaFaint => meta.copyWith(color: textFaint);

  TextStyle get sectionLabel => face(
        fontSize: RepoMetrics.sectionSize,
        color: textSoft,
        tracking: RepoMetrics.sectionTracking,
      );
}

/// Resolves the repository theme without every widget repeating the lookup.
RepoTheme repoThemeOf(BuildContext context, CollectionPalette palette) =>
    RepoTheme.of(context, palette);

/// What a file looks like in a listing.
///
/// GitHub tells types apart by shape, VS Code by colour; a repository is
/// easiest to scan when it does both, so every entry gets a rounded glyph in
/// the hue of what it actually is.
@immutable
class RepoGlyph {
  const RepoGlyph(this.icon, this.color);

  final IconData icon;
  final Color color;
}

const _repoBlue = Color(0xFF3B82F6);
const _repoViolet = Color(0xFF8B5CF6);
const _repoGreen = Color(0xFF22C55E);
const _repoAmber = Color(0xFFF59E0B);
const _repoRed = Color(0xFFEF4444);
const _repoTeal = Color(0xFF14B8A6);
const _repoSlate = Color(0xFF94A3B8);

const Set<String> _repoLicenseNames = {
  'license',
  'license.md',
  'license.txt',
  'licence',
  'copying',
  'notice',
};

const Set<String> _repoGitNames = {
  '.gitignore',
  '.gitattributes',
  '.gitmodules',
  '.gitkeep',
};

/// The glyph and hue that stand for [entry].
RepoGlyph repoGlyphFor(RepoEntry entry, RepoTheme theme, {bool open = false}) {
  if (entry.isFolder) {
    return RepoGlyph(
      open ? Icons.folder_open_rounded : Icons.folder_rounded,
      entry.view.isCollection ? theme.accent : _repoBlue,
    );
  }
  final name = entry.name.toLowerCase();
  if (repoReadmeNames.contains(name)) {
    return RepoGlyph(Icons.menu_book_rounded, _repoBlue);
  }
  if (_repoLicenseNames.contains(name)) {
    return RepoGlyph(Icons.balance_rounded, _repoSlate);
  }
  if (_repoGitNames.contains(name)) {
    return RepoGlyph(Icons.commit_rounded, const Color(0xFFF05033));
  }
  if (name.endsWith('.lock') || name == 'pubspec.lock') {
    return RepoGlyph(Icons.lock_rounded, _repoSlate);
  }
  if (name == 'dockerfile' || name.startsWith('docker-compose')) {
    return RepoGlyph(Icons.inventory_2_rounded, const Color(0xFF2496ED));
  }
  if (name.endsWith('.pdf')) {
    return RepoGlyph(Icons.picture_as_pdf_rounded, _repoRed);
  }

  final language = entry.language;
  return switch (entry.kind) {
    RepoEntryKind.folder => RepoGlyph(Icons.folder_rounded, _repoBlue),
    RepoEntryKind.source => RepoGlyph(
        Icons.code_rounded,
        language?.color ?? _repoViolet,
      ),
    RepoEntryKind.documentation => RepoGlyph(
        Icons.article_rounded,
        const Color(0xFF7C8DA6),
      ),
    RepoEntryKind.data => RepoGlyph(
        _dataIconFor(entry.extension),
        _repoAmber,
      ),
    RepoEntryKind.asset => RepoGlyph(_assetIconFor(name), _repoGreen),
    RepoEntryKind.page => RepoGlyph(Icons.description_rounded, _repoTeal),
    RepoEntryKind.other => RepoGlyph(
        Icons.insert_drive_file_rounded,
        theme.iconRest,
      ),
  };
}

IconData _dataIconFor(String extension) => switch (extension) {
      'json' || 'jsonc' => Icons.data_object_rounded,
      'yaml' ||
      'yml' ||
      'toml' ||
      'ini' ||
      'cfg' ||
      'conf' ||
      'env' =>
        Icons.tune_rounded,
      'sql' => Icons.storage_rounded,
      'csv' || 'tsv' => Icons.table_chart_rounded,
      'xml' => Icons.data_array_rounded,
      _ => Icons.description_rounded,
    };

IconData _assetIconFor(String name) {
  if (RegExp(r'\.(mp4|mov|mkv|webm|avi)$').hasMatch(name)) {
    return Icons.movie_rounded;
  }
  if (RegExp(r'\.(mp3|wav|flac|m4a|ogg)$').hasMatch(name)) {
    return Icons.graphic_eq_rounded;
  }
  if (RegExp(r'\.(ttf|otf|woff2?)$').hasMatch(name)) {
    return Icons.text_fields_rounded;
  }
  return Icons.image_rounded;
}

/// A flush piece of the continuous workspace, not a floating card per pane.
class RepoPanel extends StatelessWidget {
  const RepoPanel({
    super.key,
    required this.theme,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.color,
    this.radius,
    this.elevation = ViewerCardElevation.flush,
  });

  final RepoTheme theme;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final double? radius;
  final ViewerCardElevation elevation;

  @override
  Widget build(BuildContext context) {
    return CollectionWorkspaceSurface(
      color: color,
      tonal: elevation != ViewerCardElevation.flush,
      rounded: elevation != ViewerCardElevation.flush,
      padding: padding,
      child: child,
    );
  }
}

/// The heading above a pane: a quiet label and whatever it needs beside it.
class RepoPaneHeading extends StatelessWidget {
  const RepoPaneHeading({
    super.key,
    required this.theme,
    required this.title,
    this.leading,
    this.trailing,
    this.height = RepoMetrics.paneHeadingHeight,
  });

  final RepoTheme theme;
  final String title;
  final Widget? leading;
  final Widget? trailing;
  final double height;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: height),
      child: Row(
        children: [
          if (leading != null) ...[
            leading!,
            const SizedBox(width: RepoMetrics.space2),
          ],
          Expanded(
            child: Text(
              title,
              overflow: TextOverflow.ellipsis,
              style: theme.sectionLabel,
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The whitespace between two panes.
///
/// Panes are told apart by the gap and the card edge, never by a rule.
class RepoGap extends StatelessWidget {
  const RepoGap({super.key, this.size = RepoMetrics.paneGap});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

/// The interaction every row in the repository shares.
///
/// One place owns the hover tint, the selection wash, the timing and the
/// rounded pill, so a tree row, a listing row and a symbol row can never
/// drift apart.
class RepoRow extends StatelessWidget {
  const RepoRow({
    super.key,
    required this.theme,
    required this.height,
    this.child,
    this.onTap,
    this.onDoubleTap,
    this.onSecondaryTap,
    this.selected = false,
    this.inset = RepoMetrics.rowInset,
    this.padding = RepoMetrics.rowPadding,
    this.showActiveBar = false,
    this.builder,
  }) : assert(
          child != null || builder != null,
          'A row needs either a child or a builder',
        );

  final RepoTheme theme;
  final Widget? child;
  final double height;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onSecondaryTap;
  final bool selected;

  /// How far the hover pill is held off the pane edge.
  final double inset;
  final double padding;

  /// A left rule on the selected row, for panes that need the selection to
  /// read from across the window.
  final bool showActiveBar;

  /// Rebuilds the contents when the hover state changes, for rows that lift
  /// an icon or reveal an action.
  final Widget Function(BuildContext context, bool hovered)? builder;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(horizontal: inset),
        child: CollectionWorkspaceNavRow(
          selected: selected,
          onTap: onTap,
          onDoubleTap: onDoubleTap,
          onContextMenu: onSecondaryTap,
          minHeight: height,
          padding: EdgeInsets.symmetric(horizontal: padding, vertical: 6),
          builder: builder,
          child: child,
        ),
      );
}

/// The icon slot every row starts with, so names line up down the pane.
class RepoGlyphIcon extends StatelessWidget {
  const RepoGlyphIcon({
    super.key,
    required this.glyph,
    this.size = RepoMetrics.iconSize,
    this.emphasised = false,
    this.muted,
  });

  final RepoGlyph glyph;
  final double size;

  /// Hovered and selected rows lift their glyph to full strength.
  final bool emphasised;
  final Color? muted;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: RepoMetrics.iconSlot,
      child: WorkspaceGlyph(
        glyph.icon == Icons.balance_rounded
            ? Icons.description_rounded
            : glyph.icon == Icons.commit_rounded
                ? Icons.source_rounded
                : glyph.icon == Icons.data_array_rounded
                    ? Icons.data_object_rounded
                    : glyph.icon,
        size: size,
        color: muted ?? workspaceGlyphInk(context),
      ),
    );
  }
}

/// A compact action, the only button shape the repository uses.
class RepoAction extends StatelessWidget {
  const RepoAction({
    super.key,
    required this.theme,
    required this.icon,
    required this.tooltip,
    this.label,
    this.onPressed,
    this.selected = false,
    this.primary = false,
    this.trailingIcon,
  });

  final RepoTheme theme;
  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onPressed;
  final bool selected;

  /// The one filled action a surface is allowed.
  final bool primary;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) => CollectionWorkspaceAction(
        icon: icon == Icons.segment_rounded ? Icons.notes_rounded : icon,
        tooltip: tooltip,
        label: label,
        onPressed: onPressed,
        selected: selected,
        trailingIcon: trailingIcon,
        color: theme.textSoft,
      );
}

/// Related actions, held together by proximity rather than by a box.
class RepoActionGroup extends StatelessWidget {
  const RepoActionGroup({
    super.key,
    required this.theme,
    required this.children,
  });

  final RepoTheme theme;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (children.isEmpty) {
      return const SizedBox.shrink();
    }
    return Wrap(
      spacing: 2,
      runSpacing: 4,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: children,
    );
  }
}

/// A quiet run of metadata: a dot, a word. Never a badge.
class RepoMeta extends StatelessWidget {
  const RepoMeta({
    super.key,
    required this.theme,
    required this.label,
    this.icon,
    this.dotColor,
    this.strong = false,
  });

  final RepoTheme theme;
  final String label;
  final IconData? icon;
  final Color? dotColor;
  final bool strong;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (dotColor != null) ...[
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
        ] else if (icon != null) ...[
          WorkspaceGlyph(icon!, size: 13, color: theme.textFaint),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: strong
                ? theme.face(
                    fontSize: RepoMetrics.metaSize,
                    color: theme.textBody,
                  )
                : theme.meta,
          ),
        ),
      ],
    );
  }
}

/// The dot that separates two pieces of metadata.
class RepoMetaDot extends StatelessWidget {
  const RepoMetaDot({super.key, required this.theme});

  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: RepoMetrics.space3),
      child: Container(
        width: 3,
        height: 3,
        decoration: BoxDecoration(
          color: theme.textFaint.withValues(alpha: 0.55),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}

/// The one search field the repository uses.
class RepoSearchField extends StatelessWidget {
  const RepoSearchField({
    super.key,
    required this.theme,
    required this.controller,
    required this.hint,
    required this.onChanged,
    this.width = 232,
  });

  final RepoTheme theme;
  final TextEditingController controller;
  final String hint;
  final ValueChanged<String> onChanged;
  final double width;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: MediaQuery.textScalerOf(context).scale(13) + 22,
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        cursorWidth: 1.4,
        cursorRadius: const Radius.circular(1),
        cursorColor: theme.accent,
        style: theme.face(fontSize: 12.5, color: theme.textStrong, axis: 520),
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: theme.sunken,
          hoverColor: theme.sunken,
          contentPadding: const EdgeInsets.symmetric(vertical: 9),
          prefixIcon: WorkspaceGlyph(
            Icons.search_rounded,
            size: 16,
            color: theme.textFaint,
          ),
          prefixIconConstraints: const BoxConstraints(minWidth: 34),
          suffixIcon: controller.text.isEmpty
              ? null
              : GestureDetector(
                  onTap: () {
                    controller.clear();
                    onChanged('');
                  },
                  child: WorkspaceGlyph(
                    Icons.close_rounded,
                    size: 15,
                    color: theme.textFaint,
                  ),
                ),
          suffixIconConstraints: const BoxConstraints(minWidth: 30),
          hintText: hint,
          hintStyle: theme.face(fontSize: 12.5, color: theme.textFaint),
          // A shade that deepens when it takes focus — nothing is outlined.
          border: _border,
          enabledBorder: _border,
          focusedBorder: _border,
        ),
      ),
    );
  }

  OutlineInputBorder get _border => OutlineInputBorder(
        borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
        borderSide: BorderSide.none,
      );
}

/// Nothing to show, said calmly.
class RepoEmptyState extends StatelessWidget {
  const RepoEmptyState({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final RepoTheme theme;
  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 360),
        child: Padding(
          padding: const EdgeInsets.all(RepoMetrics.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkspaceGlyph(
                icon == Icons.segment_rounded ? Icons.notes_rounded : icon,
                size: 26,
                color: theme.textFaint.withValues(alpha: 0.7),
              ),
              const SizedBox(height: RepoMetrics.space4),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.face(
                  fontSize: 13,
                  color: theme.textStrong,
                  weight: FontWeight.w600,
                  height: 1.35,
                ),
              ),
              const SizedBox(height: RepoMetrics.space1 + 2),
              Text(
                description,
                textAlign: TextAlign.center,
                style: theme.meta.copyWith(height: 1.6),
              ),
              if (action != null) ...[
                const SizedBox(height: RepoMetrics.space4),
                action!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// A thin overlay scrollbar, so a pane never reserves a gutter for one.
class RepoScrollArea extends StatefulWidget {
  const RepoScrollArea({
    super.key,
    required this.theme,
    required this.builder,
    this.controller,
  });

  final RepoTheme theme;
  final Widget Function(BuildContext context, ScrollController controller)
      builder;
  final ScrollController? controller;

  @override
  State<RepoScrollArea> createState() => _RepoScrollAreaState();
}

class _RepoScrollAreaState extends State<RepoScrollArea> {
  ScrollController? owned;

  ScrollController get controller =>
      widget.controller ?? (owned ??= ScrollController());

  @override
  void dispose() {
    owned?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ScrollbarTheme(
      data: ScrollbarThemeData(
        thickness: const WidgetStatePropertyAll(5),
        radius: const Radius.circular(3),
        thumbVisibility: const WidgetStatePropertyAll(false),
        interactive: true,
        crossAxisMargin: 2,
        mainAxisMargin: 4,
        thumbColor: WidgetStateProperty.resolveWith((states) {
          final hovered = states.contains(WidgetState.hovered) ||
              states.contains(WidgetState.dragged);
          return widget.theme.textSoft.withValues(alpha: hovered ? 0.5 : 0.26);
        }),
      ),
      child: Scrollbar(
        controller: controller,
        child: widget.builder(context, controller),
      ),
    );
  }
}
