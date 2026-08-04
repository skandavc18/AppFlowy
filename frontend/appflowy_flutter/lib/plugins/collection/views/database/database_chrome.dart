import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

/// The fixed geometry and motion a database collection is drawn to.
abstract final class DatabaseMetrics {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;
  static const double space8 = 32;

  static const double gutter = 24;
  static const double railWidth = 236;
  static const double rowHeight = 30;
  static const double rowRadius = 8;
  static const double controlRadius = 8;
  static const double panelRadius = EditorSurfaceStyle.embedCornerRadius;

  static const double schemaCardWidth = 320;

  static const double titleSize = 14;
  static const double bodySize = 12.5;
  static const double metaSize = 11.5;
  static const double sectionSize = 10.5;
  static const double tracking = -0.006;
  static const double sectionTracking = 0.07;
  static const double bodyWeightAxis = 545;
  static const double strongWeightAxis = 620;
  static const double sectionWeightAxis = 640;

  static const Duration hover = Duration(milliseconds: 140);
  static const Curve curve = Curves.easeOutCubic;
}

/// Every colour a database collection draws with.
@immutable
class DatabaseTheme {
  const DatabaseTheme._({
    required this.palette,
    required this.brightness,
    required this.canvas,
    required this.panel,
    required this.raised,
    required this.sunken,
    required this.hover,
    required this.selected,
    required this.textStrong,
    required this.textBody,
    required this.textSoft,
    required this.textFaint,
    required this.iconRest,
    required this.accent,
    required this.baseTextStyle,
  });

  factory DatabaseTheme.of(BuildContext context, CollectionPalette palette) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return DatabaseTheme._(
      palette: palette,
      brightness: theme.brightness,
      canvas: palette.background,
      panel: palette.surface,
      raised: palette.floatingSurface,
      sunken: Color.alphaBlend(
        palette.hover.withValues(alpha: isDark ? 0.42 : 0.6),
        palette.background,
      ),
      hover: palette.hover.withValues(alpha: isDark ? 0.62 : 0.8),
      selected: palette.accent.withValues(alpha: isDark ? 0.16 : 0.10),
      textStrong: palette.textPrimary,
      textBody: Color.lerp(palette.textSecondary, palette.textPrimary, 0.5)!,
      textSoft: palette.textSecondary,
      textFaint: palette.textMuted,
      iconRest: palette.textMuted.withValues(alpha: isDark ? 0.92 : 0.86),
      accent: palette.accent,
      baseTextStyle: theme.textTheme.bodyMedium ?? const TextStyle(),
    );
  }

  final CollectionPalette palette;
  final Brightness brightness;
  final Color canvas;
  final Color panel;
  final Color raised;
  final Color sunken;
  final Color hover;
  final Color selected;
  final Color textStrong;
  final Color textBody;
  final Color textSoft;
  final Color textFaint;
  final Color iconRest;
  final Color accent;
  final TextStyle baseTextStyle;

  bool get isDark => brightness == Brightness.dark;

  /// A transparent stand-in that keeps a colour's own channels, so a hover
  /// tween never passes through transparent black.
  Color transparentAs(Color color) => color.withValues(alpha: 0);

  List<Shadow> get _underprint =>
      AppTextRendering.rootStyleFor(brightness).shadows ?? const [];

  TextStyle face({
    required double fontSize,
    required Color color,
    double axis = DatabaseMetrics.bodyWeightAxis,
    FontWeight weight = FontWeight.w500,
    double tracking = DatabaseMetrics.tracking,
    double height = 1.0,
  }) =>
      AppTextRendering.polish(
        baseTextStyle.copyWith(
          fontSize: fontSize,
          fontWeight: weight,
          fontVariations: [FontVariation.weight(axis)],
          height: height,
          letterSpacing: fontSize * tracking,
          color: color,
          shadows: _underprint,
          decoration: TextDecoration.none,
        ),
      );

  TextStyle get title => face(
        fontSize: DatabaseMetrics.titleSize,
        color: textStrong,
        axis: DatabaseMetrics.strongWeightAxis,
        weight: FontWeight.w600,
        height: 1.3,
      );

  TextStyle get body => face(
        fontSize: DatabaseMetrics.bodySize,
        color: textBody,
        height: 1.4,
      );

  TextStyle get meta => face(
        fontSize: DatabaseMetrics.metaSize,
        color: textFaint,
        axis: 500,
        weight: FontWeight.w400,
      );

  TextStyle get sectionLabel => face(
        fontSize: DatabaseMetrics.sectionSize,
        color: textFaint,
        axis: DatabaseMetrics.sectionWeightAxis,
        weight: FontWeight.w600,
        tracking: DatabaseMetrics.sectionTracking,
      );
}

/// A region of the collection, drawn as the application's own card.
class DatabasePanel extends StatelessWidget {
  const DatabasePanel({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.elevation = ViewerCardElevation.resting,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final ViewerCardElevation elevation;
  final Color? color;

  @override
  Widget build(BuildContext context) => ViewerCard(
        reactsToPointer: false,
        elevation: elevation,
        color: color ?? databaseThemeOf(context).panel,
        child: Padding(padding: padding, child: child),
      );
}

/// The whitespace between one region and the next. Nothing is separated by a
/// drawn line.
class DatabaseGap extends StatelessWidget {
  const DatabaseGap({super.key, this.size = DatabaseMetrics.space3});
  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

/// A borderless control: the toolbar buttons and the rail actions.
class DatabaseAction extends StatefulWidget {
  const DatabaseAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.theme,
    this.label,
    this.onPressed,
    this.active = false,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final DatabaseTheme theme;
  final String? label;
  final VoidCallback? onPressed;
  final bool active;
  final double size;

  @override
  State<DatabaseAction> createState() => _DatabaseActionState();
}

class _DatabaseActionState extends State<DatabaseAction> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onPressed != null;
    final tint = widget.active
        ? theme.accent
        : enabled
            ? theme.iconRest
            : theme.textFaint.withValues(alpha: 0.5);
    final fill = widget.active
        ? theme.accent.withValues(alpha: theme.isDark ? 0.18 : 0.11)
        : _hovered
            ? theme.hover
            : theme.transparentAs(theme.hover);
    final label = widget.label;

    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 500),
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onPressed,
          child: AnimatedContainer(
            duration: DatabaseMetrics.hover,
            curve: DatabaseMetrics.curve,
            height: widget.size,
            padding: label == null
                ? EdgeInsets.symmetric(horizontal: (widget.size - 16) / 2)
                : const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: fill,
              borderRadius:
                  BorderRadius.circular(DatabaseMetrics.controlRadius),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(widget.icon, size: 16, color: tint),
                if (label != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    label,
                    style: theme.face(
                      fontSize: DatabaseMetrics.metaSize + 0.5,
                      color: tint,
                      axis: DatabaseMetrics.strongWeightAxis,
                      weight: FontWeight.w600,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A row in the table rail, with the hover pill every collection uses.
class DatabaseRow extends StatefulWidget {
  const DatabaseRow({
    super.key,
    required this.theme,
    required this.child,
    this.onTap,
    this.onContextMenu,
    this.selected = false,
    this.height = DatabaseMetrics.rowHeight,
  });

  final DatabaseTheme theme;
  final Widget child;
  final VoidCallback? onTap;
  final ValueChanged<Offset>? onContextMenu;
  final bool selected;
  final double height;

  @override
  State<DatabaseRow> createState() => _DatabaseRowState();
}

class _DatabaseRowState extends State<DatabaseRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final fill = widget.selected
        ? theme.selected
        : _hovered
            ? theme.hover
            : theme.transparentAs(theme.hover);

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onSecondaryTapDown: widget.onContextMenu == null
            ? null
            : (details) => widget.onContextMenu!(details.globalPosition),
        child: AnimatedContainer(
          duration: DatabaseMetrics.hover,
          curve: DatabaseMetrics.curve,
          height: widget.height,
          padding: const EdgeInsets.symmetric(
            horizontal: DatabaseMetrics.space2,
          ),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(DatabaseMetrics.rowRadius),
          ),
          child: Row(children: [Expanded(child: widget.child)]),
        ),
      ),
    );
  }
}

/// Nothing to show yet.
class DatabaseEmptyState extends StatelessWidget {
  const DatabaseEmptyState({
    super.key,
    required this.theme,
    required this.icon,
    required this.title,
    this.message,
    this.action,
  });

  final DatabaseTheme theme;
  final IconData icon;
  final String title;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(DatabaseMetrics.space8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 30,
                color: theme.textFaint.withValues(alpha: 0.7),
              ),
              const SizedBox(height: DatabaseMetrics.space3),
              Text(
                title,
                textAlign: TextAlign.center,
                style: theme.face(
                  fontSize: DatabaseMetrics.titleSize,
                  color: theme.textBody,
                  axis: DatabaseMetrics.strongWeightAxis,
                  weight: FontWeight.w600,
                ),
              ),
              if (message != null) ...[
                const SizedBox(height: DatabaseMetrics.space2),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 340),
                  child: Text(
                    message!,
                    textAlign: TextAlign.center,
                    style: theme.body.copyWith(color: theme.textSoft),
                  ),
                ),
              ],
              if (action != null) ...[
                const SizedBox(height: DatabaseMetrics.space4),
                action!,
              ],
            ],
          ),
        ),
      );
}

/// The glyph a table wears, taken from the layout it is shown in.
IconData databaseLayoutIcon(ViewLayoutPB layout) => switch (layout) {
      ViewLayoutPB.Board => Icons.view_kanban_rounded,
      ViewLayoutPB.Calendar => Icons.calendar_month_rounded,
      _ => Icons.table_rows_rounded,
    };

/// The glyph a column wears, taken from what it holds.
IconData databaseFieldIcon(FieldType type) => switch (type) {
      FieldType.RichText => Icons.notes_rounded,
      FieldType.Number => Icons.numbers_rounded,
      FieldType.DateTime => Icons.calendar_today_rounded,
      FieldType.SingleSelect => Icons.radio_button_checked_rounded,
      FieldType.MultiSelect => Icons.checklist_rounded,
      FieldType.Checkbox => Icons.check_box_rounded,
      FieldType.URL => Icons.link_rounded,
      FieldType.Checklist => Icons.fact_check_rounded,
      FieldType.LastEditedTime => Icons.update_rounded,
      FieldType.CreatedTime => Icons.schedule_rounded,
      FieldType.Relation => Icons.hub_rounded,
      FieldType.Summary => Icons.auto_awesome_rounded,
      FieldType.Translate => Icons.translate_rounded,
      FieldType.Time => Icons.timer_rounded,
      FieldType.Media => Icons.perm_media_rounded,
      _ => Icons.short_text_rounded,
    };

/// A readable name for a column's type.
String databaseFieldTypeLabel(FieldType type) => switch (type) {
      FieldType.RichText => 'Text',
      FieldType.Number => 'Number',
      FieldType.DateTime => 'Date',
      FieldType.SingleSelect => 'Select',
      FieldType.MultiSelect => 'Multi-select',
      FieldType.Checkbox => 'Checkbox',
      FieldType.URL => 'URL',
      FieldType.Checklist => 'Checklist',
      FieldType.LastEditedTime => 'Last edited',
      FieldType.CreatedTime => 'Created',
      FieldType.Relation => 'Relation',
      FieldType.Summary => 'Summary',
      FieldType.Translate => 'Translate',
      FieldType.Time => 'Time',
      FieldType.Media => 'Media',
      _ => 'Field',
    };

/// The palette a database collection resolves from.
DatabaseTheme databaseThemeOf(BuildContext context) => DatabaseTheme.of(
      context,
      CollectionPalette.of(context, CollectionKind.database),
    );
