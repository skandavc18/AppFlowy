import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:flutter/material.dart';

/// Geometry and motion for the sidebar.
///
/// Everything the navigation surface measures with lives here so rows,
/// section headings and utility actions cannot drift apart from each other.
abstract final class SidebarMetrics {
  // A 4px spacing scale. Nothing in the sidebar should use a value that is
  // not on it.
  static const space1 = 4.0;
  static const space2 = 8.0;
  static const space3 = 12.0;
  static const space4 = 16.0;
  static const space6 = 24.0;

  /// Distance from the window edge to the hover pill.
  static const gutter = 8.0;

  /// Height of an ordinary page row.
  static const rowHeight = 32.0;

  /// Height of a top level action (search, new page, trash…).
  static const actionRowHeight = 34.0;

  /// Height of a section heading.
  static const headingHeight = 30.0;

  static const rowRadius = 8.0;

  /// Horizontal padding inside the hover pill.
  static const rowInset = 4.0;

  /// Added per level of nesting, inside the pill so every pill still aligns.
  static const indent = 14.0;

  /// The disclosure chevron takes the icon's place on hover, so it costs no
  /// horizontal room of its own.
  static const disclosureIconSize = 12.0;

  static const iconSlot = 22.0;
  static const iconSize = 18.0;
  static const iconGap = 8.0;

  /// One contextual action button.
  static const actionSlot = 24.0;
  static const actionGap = 2.0;

  /// Space kept for contextual actions at all times, so a title never moves
  /// when they fade in.
  static double trailingReserve(int slots) =>
      slots <= 0 ? 0 : slots * actionSlot + (slots - 1) * actionGap;

  static const hover = Duration(milliseconds: 140);
  static const reveal = Duration(milliseconds: 150);
  static const disclosure = Duration(milliseconds: 180);
  static const structural = Duration(milliseconds: 280);
  static const curve = Curves.easeOutCubic;

  /// Opacity an icon rests at before the pointer arrives.
  static const iconRestingOpacity = 0.86;
}

/// The sidebar's icon family.
///
/// Phosphor "Bold" — already bundled as one of the application's icon packs.
/// Every glyph is hollow outline artwork with rounded joins, so a page reads
/// as an outlined sheet rather than a solid Material slab.
enum SidebarIcon {
  search('editor', 'magnifying-glass'),
  newPage('office', 'note-pencil'),
  home('maps_travel', 'house'),
  add('technology_development', 'plus'),
  more('system', 'dots-three'),
  disclosure('arrows', 'caret-right'),
  dropDown('arrows', 'caret-down'),
  switcher('arrows', 'caret-up-down'),
  collapse('design', 'sidebar-simple'),
  trash('office', 'trash'),
  pin('office', 'push-pin'),
  settings('system', 'gear'),
  bell('system', 'bell'),
  document('office', 'file-text'),
  folder('office', 'folder'),
  folderOpen('office', 'folder-open'),
  grid('finances', 'table'),
  board('office', 'kanban'),
  calendar('office', 'calendar-blank'),
  chat('communications', 'chat-circle'),
  chart('finances', 'chart-bar'),
  atlas('maps_travel', 'map-trifold'),
  slides('finances', 'presentation-chart'),
  timeline('office', 'graph'),
  feed('media', 'article'),
  form('office', 'list-checks'),
  gallery('design', 'squares-four'),
  mailbox('communications', 'envelope-simple'),
  book('office', 'book-open'),
  album('media', 'images'),
  repository('technology_development', 'git-branch'),
  database('technology_development', 'database'),
  link('communications', 'link-simple'),
  file('office', 'file'),
  pdf('office', 'file-pdf'),
  word('office', 'file-doc'),
  sheet('office', 'file-xls'),
  deck('office', 'file-ppt'),
  archive('office', 'file-zip'),
  code('office', 'file-code'),
  csv('office', 'file-csv'),
  image('media', 'image'),
  video('media', 'film-strip'),
  audio('media', 'music-note');

  const SidebarIcon(this._category, this.name);

  final String _category;
  final String name;

  String get group => '${_sidebarIconPackId}_$_category';
}

const _sidebarIconPackId = 'phosphor_bold';

/// The pack every [SidebarIcon] is drawn from.
final IconPack sidebarIconPack =
    kIconPacks.firstWhere((pack) => pack.id == _sidebarIconPackId);

/// Loads the sidebar's icon pack so the first frame is not drawn blank.
void warmSidebarIcons() {
  if (!isIconPackLoaded(sidebarIconPack)) {
    unawaited(loadIconPack(sidebarIconPack));
  }
}

class SidebarGlyph extends StatelessWidget {
  const SidebarGlyph(
    this.icon, {
    super.key,
    this.size = SidebarMetrics.iconSize,
    this.color,
  });

  final SidebarIcon icon;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<int>(
      valueListenable: iconPacksVersion,
      builder: (context, _, __) {
        if (!isIconPackLoaded(sidebarIconPack)) {
          warmSidebarIcons();
          return SizedBox.square(dimension: size);
        }
        final svg = findLoadedIcon(icon.group, icon.name)?.content;
        if (svg == null) {
          return SizedBox.square(dimension: size);
        }
        return FlowySvg.string(
          svg,
          size: Size.square(size),
          color: color ?? SidebarPalette.of(context).icon,
        );
      },
    );
  }
}

/// The sidebar's colour hierarchy, tuned separately for each appearance
/// rather than inverted from one another.
@immutable
class SidebarPalette {
  const SidebarPalette({
    required this.brightness,
    required this.isPaper,
    required this.background,
    required this.textPrimary,
    required this.textSecondary,
    required this.textTertiary,
    required this.icon,
    required this.hover,
    required this.selected,
    required this.selectedHover,
    required this.accent,
    required this.edge,
    required this.dropIndicator,
    required this.scrollThumb,
  });

  final Brightness brightness;
  final bool isPaper;
  final Color background;

  /// Page and workspace names. Deliberately a dark charcoal, never black.
  final Color textPrimary;

  /// Utility actions and metadata.
  final Color textSecondary;

  /// Section labels and anything at rest.
  final Color textTertiary;

  /// Icon ink.
  ///
  /// Deliberately lighter than [textBody]: a bold stroke carries far more ink
  /// than a letterform, so matching the two numerically makes the glyph read
  /// as the darker of the pair.
  final Color icon;
  final Color hover;
  final Color selected;
  final Color selectedHover;
  final Color accent;
  final Color edge;
  final Color dropIndicator;
  final Color scrollThumb;

  bool get isDark => brightness == Brightness.dark;

  /// A page name at rest: nearly as dark as a heading, so a listing reads as
  /// content rather than as a row of secondary labels.
  Color get textBody => Color.lerp(textSecondary, textPrimary, 0.68)!;

  static SidebarPalette of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final isPaper = PaperTheme.isEnabled(context);
    if (theme.brightness == Brightness.dark) {
      return _dark(premium);
    }
    if (isPaper) {
      return _paper(premium);
    }
    return _light(premium);
  }

  static SidebarPalette _light(PremiumThemeExtension? premium) =>
      SidebarPalette(
        brightness: Brightness.light,
        isPaper: false,
        background: premium?.sidebar ?? const Color(0xFFFAF9F6),
        textPrimary: const Color(0xFF2B2A28),
        textSecondary: const Color(0xFF6B6963),
        textTertiary: const Color(0xFF96938C),
        icon: const Color(0xFF6F6C66),
        hover: const Color(0x0A16150F),
        selected: const Color(0x1416150F),
        selectedHover: const Color(0x1C16150F),
        accent: premium?.accent ?? const Color(0xFF2F6FE4),
        edge: const Color(0x0F16150F),
        dropIndicator: premium?.accent ?? const Color(0xFF2F6FE4),
        scrollThumb: const Color(0x2416150F),
      );
  static SidebarPalette _paper(PremiumThemeExtension? premium) =>
      SidebarPalette(
        brightness: Brightness.light,
        isPaper: true,
        background: PaperTheme.sidebarBackground,
        textPrimary: PaperTheme.textPrimary,
        textSecondary: PaperTheme.textSecondary,
        textTertiary: PaperTheme.textMuted,
        icon: const Color(0xFF7B6F62),
        hover: const Color(0x0F6A5947),
        selected: const Color(0x1F6A5947),
        selectedHover: const Color(0x2A6A5947),
        accent: premium?.accent ?? PaperTheme.accent,
        edge: const Color(0x146A5947),
        dropIndicator: PaperTheme.accent,
        scrollThumb: const Color(0x306A5947),
      );

  static SidebarPalette _dark(PremiumThemeExtension? premium) => SidebarPalette(
        brightness: Brightness.dark,
        isPaper: false,
        background: premium?.sidebar ?? const Color(0xFF1F1F1F),
        textPrimary: const Color(0xE8FFFFFF),
        textSecondary: const Color(0x9EFFFFFF),
        textTertiary: const Color(0x70FFFFFF),
        icon: const Color(0xAEFFFFFF),
        hover: const Color(0x0FFFFFFF),
        selected: const Color(0x1FFFFFFF),
        selectedHover: const Color(0x29FFFFFF),
        accent: premium?.accent ?? const Color(0xFF6E9BF5),
        edge: const Color(0x14FFFFFF),
        dropIndicator: premium?.accent ?? const Color(0xFF6E9BF5),
        scrollThumb: const Color(0x33FFFFFF),
      );

  /// The colour a hover wash should animate *from*.
  ///
  /// Fading out of [Colors.transparent] passes through transparent black and
  /// flashes grey on a light surface.
  Color get hoverAtRest => hover.withValues(alpha: 0);
}

/// A single navigation row: one height, one indent, one hover pill.
///
/// Contextual actions are laid over a reserved gutter rather than taking part
/// in the row's layout, so revealing them can never move the title.
class SidebarRow extends StatefulWidget {
  const SidebarRow({
    super.key,
    required this.label,
    this.leading,
    this.icon,
    this.trailingBuilder,
    this.trailingSlots = 0,
    this.height = SidebarMetrics.rowHeight,
    this.indent = 0,
    this.selected = false,
    this.active = false,
    this.hoverEnabled = true,
    this.dimIcon = true,
    this.onTap,
    this.onSecondaryPointerDown,
    this.onTertiaryTapDown,
    this.onHoverChanged,
  });

  final Widget label;

  /// The disclosure control. When present it takes the icon's place while the
  /// row is hovered, the way Notion does, so nothing is indented to make room
  /// for a chevron that is usually invisible.
  final Widget? leading;
  final Widget? icon;

  /// Built only while the row is hovered or [active], so a sidebar of a
  /// thousand pages does not carry a thousand popovers.
  final List<Widget> Function(BuildContext context)? trailingBuilder;

  /// How many action slots to keep clear on the right.
  final int trailingSlots;

  final double height;
  final double indent;
  final bool selected;

  /// Keeps the actions visible while one of their menus is open.
  final bool active;
  final bool hoverEnabled;
  final bool dimIcon;
  final VoidCallback? onTap;
  final void Function(PointerDownEvent event)? onSecondaryPointerDown;
  final void Function(TapDownDetails details)? onTertiaryTapDown;
  final ValueChanged<bool>? onHoverChanged;

  @override
  State<SidebarRow> createState() => _SidebarRowState();
}

class _SidebarRowState extends State<SidebarRow> {
  bool _hovered = false;

  void _setHovered(bool value) {
    if (_hovered == value || !widget.hoverEnabled) {
      return;
    }
    setState(() => _hovered = value);
    widget.onHoverChanged?.call(value);
  }

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    final revealed = _hovered || widget.active;
    final background = widget.selected
        ? (revealed ? palette.selectedHover : palette.selected)
        : revealed
            ? palette.hover
            : palette.hoverAtRest;
    final reserve = SidebarMetrics.trailingReserve(widget.trailingSlots);
    final showsDisclosure = widget.leading != null && revealed;

    final content = Row(
      children: [
        SizedBox(width: SidebarMetrics.rowInset + widget.indent),
        if (widget.icon != null || widget.leading != null) ...[
          SizedBox(
            width: SidebarMetrics.iconSlot,
            child: Center(
              child: showsDisclosure
                  ? widget.leading
                  : widget.dimIcon
                      ? AnimatedOpacity(
                          duration: SidebarMetrics.hover,
                          curve: SidebarMetrics.curve,
                          opacity: revealed || widget.selected
                              ? 1
                              : SidebarMetrics.iconRestingOpacity,
                          child: widget.icon,
                        )
                      : widget.icon,
            ),
          ),
          const SizedBox(width: SidebarMetrics.iconGap),
        ],
        Expanded(child: widget.label),
        SizedBox(width: reserve + SidebarMetrics.rowInset),
      ],
    );

    Widget row = AnimatedContainer(
      duration: SidebarMetrics.hover,
      curve: SidebarMetrics.curve,
      height: widget.height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SidebarMetrics.rowRadius),
      ),
      child: reserve == 0
          ? content
          : Stack(
              // A stack of nothing but positioned children takes no width.
              fit: StackFit.expand,
              children: [
                content,
                PositionedDirectional(
                  end: SidebarMetrics.rowInset,
                  top: 0,
                  bottom: 0,
                  width: reserve,
                  child: SidebarActionReveal(
                    revealed: revealed,
                    builder: widget.trailingBuilder,
                  ),
                ),
              ],
            ),
    );

    if (widget.onSecondaryPointerDown != null) {
      row = Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.onSecondaryPointerDown,
        child: row,
      );
    }

    return MouseRegion(
      opaque: false,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => _setHovered(true),
      onExit: (_) => _setHovered(false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.onTap,
        onTertiaryTapDown: widget.onTertiaryTapDown,
        child: row,
      ),
    );
  }
}

/// Fades contextual actions in and lets them settle a couple of pixels to the
/// left, without ever changing the space they occupy.
class SidebarActionReveal extends StatelessWidget {
  const SidebarActionReveal({
    super.key,
    required this.revealed,
    required this.builder,
  });

  final bool revealed;
  final List<Widget> Function(BuildContext context)? builder;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: SidebarMetrics.reveal,
      switchInCurve: SidebarMetrics.curve,
      switchOutCurve: SidebarMetrics.curve,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.18, 0),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: revealed && builder != null
          ? Row(
              key: const ValueKey('revealed'),
              mainAxisAlignment: MainAxisAlignment.end,
              children: builder!(context),
            )
          : const SizedBox.shrink(key: ValueKey('hidden')),
    );
  }
}

/// The expand/collapse control. `›` rotates into `⌄` rather than swapping.
class SidebarDisclosure extends StatelessWidget {
  const SidebarDisclosure({
    super.key,
    required this.expanded,
    required this.onTap,
    this.tooltip,
  });

  final bool expanded;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    Widget child = AnimatedRotation(
      duration: SidebarMetrics.disclosure,
      curve: SidebarMetrics.curve,
      turns: expanded ? 0.25 : 0,
      child: SidebarGlyph(
        SidebarIcon.disclosure,
        size: SidebarMetrics.disclosureIconSize,
        color: palette.textSecondary,
      ),
    );

    if (tooltip != null) {
      child = Tooltip(message: tooltip!, child: child);
    }

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: SizedBox(
          width: SidebarMetrics.iconSlot,
          height: SidebarMetrics.iconSlot,
          child: Center(child: child),
        ),
      ),
    );
  }
}

/// A borderless icon button sized to one action slot.
class SidebarIconButton extends StatefulWidget {
  const SidebarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 16,
  });

  final SidebarIcon icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;

  @override
  State<SidebarIconButton> createState() => _SidebarIconButtonState();
}

class _SidebarIconButtonState extends State<SidebarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    Widget button = MouseRegion(
      opaque: false,
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onPressed,
        child: AnimatedContainer(
          duration: SidebarMetrics.hover,
          curve: SidebarMetrics.curve,
          width: SidebarMetrics.actionSlot,
          height: SidebarMetrics.actionSlot,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: _hovered ? palette.selected : palette.hoverAtRest,
            borderRadius: BorderRadius.circular(6),
          ),
          child: SidebarGlyph(
            widget.icon,
            size: widget.size,
            color: _hovered ? palette.textPrimary : palette.textSecondary,
          ),
        ),
      ),
    );

    if (widget.tooltip != null) {
      button = Tooltip(message: widget.tooltip!, child: button);
    }
    return button;
  }
}

/// A top level navigation action: search, new page, templates, trash.
class SidebarNavItem extends StatelessWidget {
  const SidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    this.onTap,
    this.shortcut,
    this.trailing,
    this.reserveTrailing = 0,
    this.selected = false,
    this.height = SidebarMetrics.actionRowHeight,
  });

  final SidebarIcon icon;
  final String label;

  /// Null when an ancestor (a popover, for instance) owns the gesture.
  final VoidCallback? onTap;

  /// Rendered flush right, the way a command palette entry reads.
  final String? shortcut;
  final Widget? trailing;

  /// Action slots kept clear for a control the host paints over the row.
  final int reserveTrailing;
  final bool selected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    return SidebarRow(
      height: height,
      selected: selected,
      onTap: onTap,
      trailingSlots: reserveTrailing,
      icon: SidebarGlyph(icon, color: palette.icon),
      label: Row(
        children: [
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: SidebarTypography.textStyle(
                context,
                color: palette.textSecondary,
              ),
            ),
          ),
          if (shortcut != null)
            Padding(
              padding: const EdgeInsets.only(left: SidebarMetrics.space2),
              child: Text(
                shortcut!,
                style: SidebarTypography.textStyle(
                  context,
                  color: palette.textTertiary,
                  role: SidebarTextRole.meta,
                ),
              ),
            ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// The quiet label that opens a section of the tree.
class SidebarSectionLabel extends StatelessWidget {
  const SidebarSectionLabel(this.text, {super.key, this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    return Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: SidebarTypography.textStyle(
        context,
        color: color ?? palette.textTertiary,
        role: SidebarTextRole.section,
      ),
    );
  }
}

/// A thin overlay scrollbar that stays out of the way until the list moves.
class SidebarScrollbar extends StatelessWidget {
  const SidebarScrollbar({
    super.key,
    required this.controller,
    required this.child,
  });

  final ScrollController controller;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    return RawScrollbar(
      controller: controller,
      thumbColor: palette.scrollThumb,
      radius: const Radius.circular(3),
      thickness: 4,
      thumbVisibility: false,
      fadeDuration: SidebarMetrics.structural,
      timeToFade: const Duration(milliseconds: 700),
      crossAxisMargin: 2,
      mainAxisMargin: 4,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        child: child,
      ),
    );
  }
}
