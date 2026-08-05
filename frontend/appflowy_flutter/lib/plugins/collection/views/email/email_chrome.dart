import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/text_rendering.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:flutter/material.dart';

/// The fixed geometry and motion a mailbox is drawn to.
abstract final class EmailMetrics {
  static const double space1 = 4;
  static const double space2 = 8;
  static const double space3 = 12;
  static const double space4 = 16;
  static const double space5 = 20;
  static const double space6 = 24;

  static const double gutter = 20;
  static const double toolbarHeight = 40;

  /// The three panes.
  static const double railWidth = 216;
  static const double listWidth = 380;
  static const double minimumReadingWidth = 420;

  /// The measure a message is read at.
  static const double readingWidth = 760;

  static const double panelRadius = EditorSurfaceStyle.embedCornerRadius;
  static const double controlRadius = 9;
  static const double rowRadius = 8;

  static const double avatarSize = 30;
  static const double compactAvatarSize = 18;
  static const double unreadDot = 7;

  /// Typography.
  static const double subjectSize = 13.5;
  static const double senderSize = 13;
  static const double bodySize = 13.5;
  static const double snippetSize = 12;
  static const double metaSize = 11.5;
  static const double sectionSize = 10.5;
  static const double tracking = -0.006;
  static const double sectionTracking = 0.07;
  static const double bodyWeightAxis = 545;
  static const double strongWeightAxis = 640;
  static const double sectionWeightAxis = 640;

  static const Duration hover = Duration(milliseconds: 140);
  static const Duration reveal = Duration(milliseconds: 220);
  static const Curve curve = Curves.easeOutCubic;
}

/// Every colour a mailbox draws with.
@immutable
class EmailTheme {
  const EmailTheme._({
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
    required this.accentSoft,
    required this.accentBorder,
    required this.baseTextStyle,
  });

  factory EmailTheme.of(BuildContext context, CollectionPalette palette) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return EmailTheme._(
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
      selected: palette.accent.withValues(alpha: isDark ? 0.18 : 0.11),
      textStrong: palette.textPrimary,
      textBody: Color.lerp(palette.textSecondary, palette.textPrimary, 0.5)!,
      textSoft: palette.textSecondary,
      textFaint: palette.textMuted,
      iconRest: palette.textMuted.withValues(alpha: isDark ? 0.92 : 0.86),
      accent: palette.accent,
      accentSoft: palette.accentSoft,
      accentBorder: palette.accentBorder,
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
  final Color accentSoft;
  final Color accentBorder;
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
    double axis = EmailMetrics.bodyWeightAxis,
    FontWeight weight = FontWeight.w500,
    double tracking = EmailMetrics.tracking,
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

  /// A subject line. An unread one is set heavier and darker, which is the
  /// whole of how a mailbox says "you have not seen this".
  TextStyle subject({required bool unread}) => face(
        fontSize: EmailMetrics.subjectSize,
        color: unread ? textStrong : textBody,
        axis: unread ? EmailMetrics.strongWeightAxis : 545,
        weight: unread ? FontWeight.w600 : FontWeight.w500,
        height: 1.3,
      );

  TextStyle sender({required bool unread}) => face(
        fontSize: EmailMetrics.senderSize,
        color: unread ? textStrong : textSoft,
        axis: unread ? 620 : 545,
        weight: unread ? FontWeight.w600 : FontWeight.w500,
        height: 1.3,
      );

  TextStyle get snippet => face(
        fontSize: EmailMetrics.snippetSize,
        color: textFaint,
        axis: 500,
        weight: FontWeight.w400,
        height: 1.4,
      );

  TextStyle get body => face(
        fontSize: EmailMetrics.bodySize,
        color: textBody,
        axis: 500,
        weight: FontWeight.w400,
        height: 1.6,
      );

  TextStyle get meta => face(
        fontSize: EmailMetrics.metaSize,
        color: textFaint,
        axis: 500,
        weight: FontWeight.w400,
      );

  TextStyle get metaStrong => meta.copyWith(color: textSoft);

  TextStyle get sectionLabel => face(
        fontSize: EmailMetrics.sectionSize,
        color: textFaint,
        axis: EmailMetrics.sectionWeightAxis,
        weight: FontWeight.w600,
        tracking: EmailMetrics.sectionTracking,
      );
}

EmailTheme emailThemeOf(BuildContext context) => EmailTheme.of(
      context,
      CollectionPalette.of(context, CollectionKind.email),
    );

/// A region of the mailbox, drawn as the application's own card.
class EmailPanel extends StatelessWidget {
  const EmailPanel({
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
        // A card left transparent shows its own shadow through its face.
        color: color ?? emailThemeOf(context).panel,
        child: Padding(padding: padding, child: child),
      );
}

/// The whitespace between one region and the next. Nothing is separated by a
/// drawn line.
class EmailGap extends StatelessWidget {
  const EmailGap({super.key, this.size = EmailMetrics.space3});

  final double size;

  @override
  Widget build(BuildContext context) => SizedBox(width: size, height: size);
}

/// A borderless control: the toolbar buttons and the row actions.
class EmailAction extends StatefulWidget {
  const EmailAction({
    super.key,
    required this.icon,
    required this.tooltip,
    required this.theme,
    this.label,
    this.onPressed,
    this.active = false,
    this.tint,
    this.size = 28,
  });

  final IconData icon;
  final String tooltip;
  final EmailTheme theme;
  final String? label;
  final VoidCallback? onPressed;
  final bool active;
  final Color? tint;
  final double size;

  @override
  State<EmailAction> createState() => _EmailActionState();
}

class _EmailActionState extends State<EmailAction> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme;
    final enabled = widget.onPressed != null;
    final tint = widget.tint ??
        (widget.active
            ? theme.accent
            : enabled
                ? theme.iconRest
                : theme.textFaint.withValues(alpha: 0.5));
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
          onTapDown: enabled ? (_) => setState(() => _pressed = true) : null,
          onTapUp: enabled ? (_) => setState(() => _pressed = false) : null,
          onTapCancel: enabled ? () => setState(() => _pressed = false) : null,
          onTap: widget.onPressed,
          child: Opacity(
            opacity: _pressed ? 0.6 : 1,
            child: AnimatedContainer(
              duration: EmailMetrics.hover,
              curve: EmailMetrics.curve,
              height: widget.size,
              padding: EdgeInsets.symmetric(
                horizontal: label == null ? 0 : EmailMetrics.space2 + 2,
              ),
              constraints: BoxConstraints(
                minWidth: label == null ? widget.size : 0,
              ),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(EmailMetrics.controlRadius),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(widget.icon, size: 16, color: tint),
                  if (label != null) ...[
                    const SizedBox(width: EmailMetrics.space1 + 2),
                    Text(
                      label,
                      style: theme.face(
                        fontSize: EmailMetrics.metaSize + 0.5,
                        color: widget.active ? theme.accent : theme.textBody,
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A label or a state, shown as a soft pill.
class EmailChip extends StatelessWidget {
  const EmailChip({
    super.key,
    required this.label,
    required this.theme,
    this.icon,
    this.tone,
    this.onTap,
  });

  final String label;
  final EmailTheme theme;
  final IconData? icon;
  final Color? tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colour = tone ?? theme.textSoft;
    final chip = Container(
      padding: const EdgeInsets.symmetric(
        horizontal: EmailMetrics.space2,
        vertical: 3,
      ),
      decoration: BoxDecoration(
        color: colour.withValues(alpha: theme.isDark ? 0.2 : 0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: colour),
            const SizedBox(width: EmailMetrics.space1 + 1),
          ],
          Text(
            label,
            style: theme.face(
              fontSize: EmailMetrics.metaSize - 0.5,
              color: colour,
              axis: 580,
              weight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    return onTap == null
        ? chip
        : MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(onTap: onTap, child: chip),
          );
  }
}

/// A correspondent, drawn as their initials in a colour of their own.
///
/// Nobody has a picture in a folder of `.eml` files, so the colour is derived
/// from the address: the same person keeps the same one for ever.
class EmailAvatar extends StatelessWidget {
  const EmailAvatar({
    super.key,
    required this.name,
    required this.seed,
    required this.theme,
    this.size = EmailMetrics.avatarSize,
  });

  final String name;
  final String seed;
  final EmailTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) {
    final hue = emailSenderHue(seed.isEmpty ? name : seed);
    final fill = HSLColor.fromAHSL(
      1,
      hue,
      theme.isDark ? 0.34 : 0.52,
      theme.isDark ? 0.34 : 0.86,
    ).toColor();
    final ink = HSLColor.fromAHSL(
      1,
      hue,
      theme.isDark ? 0.55 : 0.62,
      theme.isDark ? 0.86 : 0.3,
    ).toColor();

    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Text(
        emailInitials(name),
        style: theme.face(
          fontSize: size * 0.38,
          color: ink,
          axis: 660,
          weight: FontWeight.w700,
        ),
      ),
    );
  }
}

/// The mark against a message nobody has opened.
class EmailUnreadDot extends StatelessWidget {
  const EmailUnreadDot({
    super.key,
    required this.theme,
    this.size = EmailMetrics.unreadDot,
  });

  final EmailTheme theme;
  final double size;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: theme.accent, shape: BoxShape.circle),
      );
}

/// The search field above a message list.
class EmailSearchField extends StatelessWidget {
  const EmailSearchField({
    super.key,
    required this.controller,
    required this.theme,
    required this.hintText,
    this.onChanged,
    this.width,
  });

  final TextEditingController controller;
  final EmailTheme theme;
  final String hintText;
  final ValueChanged<String>? onChanged;
  final double? width;

  @override
  Widget build(BuildContext context) {
    final field = Container(
      height: 30,
      padding: const EdgeInsets.symmetric(horizontal: EmailMetrics.space2 + 2),
      decoration: BoxDecoration(
        color: theme.sunken,
        borderRadius: BorderRadius.circular(EmailMetrics.controlRadius),
      ),
      child: Row(
        children: [
          Icon(Icons.search_rounded, size: 15, color: theme.textFaint),
          const SizedBox(width: EmailMetrics.space2 - 1),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: theme.face(
                fontSize: EmailMetrics.metaSize + 1,
                color: theme.textStrong,
              ),
              cursorColor: theme.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
                filled: false,
                hoverColor: Colors.transparent,
                hintText: hintText,
                hintStyle: theme.face(
                  fontSize: EmailMetrics.metaSize + 1,
                  color: theme.textFaint,
                  weight: FontWeight.w400,
                ),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged?.call('');
              },
              child:
                  Icon(Icons.close_rounded, size: 14, color: theme.textFaint),
            ),
        ],
      ),
    );

    return width == null ? field : SizedBox(width: width, child: field);
  }
}

/// What a pane shows when it has nothing to show.
class EmailEmptyState extends StatelessWidget {
  const EmailEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.theme,
    this.message,
    this.action,
  });

  final IconData icon;
  final String title;
  final EmailTheme theme;
  final String? message;
  final Widget? action;

  @override
  Widget build(BuildContext context) {
    final note = message;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(EmailMetrics.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 46,
              height: 38,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.sunken,
                borderRadius: BorderRadius.circular(11),
              ),
              child: Icon(icon, size: 19, color: theme.textFaint),
            ),
            const SizedBox(height: EmailMetrics.space3),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.face(
                fontSize: EmailMetrics.senderSize,
                color: theme.textSoft,
                axis: 600,
                weight: FontWeight.w600,
                height: 1.35,
              ),
            ),
            if (note != null) ...[
              const SizedBox(height: EmailMetrics.space1 + 2),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Text(
                  note,
                  textAlign: TextAlign.center,
                  style: theme.meta.copyWith(height: 1.5),
                ),
              ),
            ],
            if (action != null) ...[
              const SizedBox(height: EmailMetrics.space4),
              action!,
            ],
          ],
        ),
      ),
    );
  }
}

/// A scrolling region with a thin overlay scrollbar.
class EmailScrollArea extends StatelessWidget {
  const EmailScrollArea({
    super.key,
    required this.child,
    this.controller,
    this.padding = EdgeInsets.zero,
  });

  final Widget child;
  final ScrollController? controller;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) {
    final theme = emailThemeOf(context);
    return Scrollbar(
      controller: controller,
      thumbVisibility: false,
      thickness: 5,
      radius: const Radius.circular(4),
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: SingleChildScrollView(
          controller: controller,
          padding: padding,
          child: DefaultTextStyle(style: theme.body, child: child),
        ),
      ),
    );
  }
}

/// How a mailbox writes a date: the time for today, the weekday for this week,
/// the day and month for this year, and the year for anything older.
String emailDateLabel(DateTime? moment, {DateTime? now}) {
  if (moment == null) {
    return '';
  }
  final local = moment.toLocal();
  final today = (now ?? DateTime.now()).toLocal();
  final difference = today.difference(local);

  if (local.year == today.year &&
      local.month == today.month &&
      local.day == today.day) {
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${local.hour < 12 ? 'am' : 'pm'}';
  }
  if (difference.inDays < 7 && !difference.isNegative) {
    return _weekdays[local.weekday - 1];
  }
  if (local.year == today.year) {
    return '${_months[local.month - 1]} ${local.day}';
  }
  return '${_months[local.month - 1]} ${local.day}, ${local.year}';
}

/// The whole date, for the head of an open message.
String emailFullDateLabel(DateTime? moment) {
  if (moment == null) {
    return '';
  }
  final local = moment.toLocal();
  final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
  final minute = local.minute.toString().padLeft(2, '0');
  return '${_weekdays[local.weekday - 1]}, ${local.day} '
      '${_months[local.month - 1]} ${local.year} at '
      '$hour:$minute ${local.hour < 12 ? 'am' : 'pm'}';
}

/// A size in the units a person reads.
String emailSizeLabel(int? bytes) {
  if (bytes == null || bytes <= 0) {
    return '';
  }
  if (bytes < 1024) {
    return '$bytes B';
  }
  if (bytes < 1024 * 1024) {
    return '${(bytes / 1024).toStringAsFixed(bytes < 10 * 1024 ? 1 : 0)} KB';
  }
  return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

const _weekdays = <String>[
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

const _months = <String>[
  'Jan',
  'Feb',
  'Mar',
  'Apr',
  'May',
  'Jun',
  'Jul',
  'Aug',
  'Sep',
  'Oct',
  'Nov',
  'Dec',
];
