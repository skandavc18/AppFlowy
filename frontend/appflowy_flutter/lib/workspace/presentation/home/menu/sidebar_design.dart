import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/scrolling/scroll_hover_suppression.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Geometry and motion for the sidebar.
///
/// Everything the navigation surface measures with lives here so rows,
/// section headings and utility actions cannot drift apart from each other.
abstract final class SidebarMetrics {
  // A 4px spacing scale. Nothing in the sidebar should use a value that is
  // not on it.
  static const space1 = WorkspaceTokens.space1;
  static const space2 = WorkspaceTokens.space2;
  static const space3 = WorkspaceTokens.space3;
  static const space4 = WorkspaceTokens.space4;
  static const space6 = WorkspaceTokens.space6;

  /// Distance from the window edge to the hover pill.
  static const gutter = 8.0;

  /// Height of an ordinary page row.
  static const rowHeight = WorkspaceTokens.navigationHeight;

  /// Height of a top level action (search, new page, trash…).
  static const actionRowHeight = WorkspaceTokens.navigationHeight;

  /// Height of a section heading.
  static const headingHeight = 30.0;

  static const rowRadius = WorkspaceTokens.controlRadius;

  /// Horizontal padding inside the hover pill.
  static const rowInset = 4.0;

  /// Added per level of nesting, inside the pill so every pill still aligns.
  static const indent = 14.0;

  /// A separate disclosure target; it must never replace an editable icon.
  static const disclosureSlot = 16.0;
  static const disclosureIconSize = 12.0;

  static const iconSlot = 24.0;
  static const iconSize = WorkspaceTokens.iconSize;
  static const iconGap = 8.0;

  /// One contextual action button.
  static const actionSlot = 24.0;
  static const actionGap = 2.0;

  /// Space kept for contextual actions at all times, so a title never moves
  /// when they fade in.
  static double trailingReserve(int slots) =>
      slots <= 0 ? 0 : slots * actionSlot + (slots - 1) * actionGap;

  static const hover = WorkspaceTokens.hoverDuration;
  static const reveal = WorkspaceTokens.hoverDuration;
  static const disclosure = WorkspaceTokens.entranceDuration;
  static const structural = WorkspaceTokens.transitionDuration;
  static const curve = WorkspaceTokens.curve;

  /// Ink is already muted; hover/selection changes the row, not its artwork.
  static const iconRestingOpacity = 1.0;
}

/// The sidebar's icon family.
///
/// Stable picker identities, drawn with a small, rounded navigation set rather
/// than the picker's heavy bold artwork. Keep these names for compatibility;
/// an unmapped future symbol uses the shared diagnostic outline fallback.
enum SidebarIcon {
  search('editor', 'magnifying-glass'),
  newPage('office', 'note-pencil'),
  home('maps_travel', 'house'),
  recents('system', 'clock'),
  favorites('communications', 'star'),
  pageLibrary('office', 'books'),
  add('technology_development', 'plus'),
  more('system', 'dots-three'),
  disclosure('arrows', 'caret-right'),
  dropDown('arrows', 'caret-down'),
  switcher('arrows', 'caret-up-down'),
  collapse('design', 'sidebar-simple'),
  trash('office', 'trash'),
  templates('design', 'layout'),
  extensions('games', 'puzzle-piece'),
  workflows('technology_development', 'infinity'),
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
  list('design', 'rows'),
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

/// Collections use the same default identity in the sidebar and page header.
SidebarIcon sidebarCollectionIcon(CollectionKind kind) => switch (kind) {
      CollectionKind.book => SidebarIcon.book,
      CollectionKind.album => SidebarIcon.album,
      CollectionKind.repository => SidebarIcon.repository,
      CollectionKind.database => SidebarIcon.database,
      CollectionKind.bookmark => SidebarIcon.link,
      CollectionKind.email => SidebarIcon.mailbox,
      CollectionKind.folder => SidebarIcon.folder,
    };

const _sidebarIconPackId = 'phosphor_bold';

/// Legacy compatibility identity; default glyph rendering never loads it.
final IconPack sidebarIconPack =
    kIconPacks.firstWhere((pack) => pack.id == _sidebarIconPackId);

/// Kept for existing startup callers. WorkspaceGlyph defaults are synchronous.
void warmSidebarIcons() {}

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
    return WorkspaceGlyph.named(
      icon.name,
      size: size,
      color: color ?? workspaceGlyphInk(context),
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
  /// Deliberately quieter than [textBody], so the navigation symbols support
  /// the names rather than competing with them.
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
    final dark = theme.brightness == Brightness.dark;
    final paper = !dark && PaperTheme.isEnabled(context);
    final hover = WorkspaceChrome.hoverColor(context);
    final selected = paper
        ? PaperTheme.selectedOverlay
        : WorkspaceChrome.selectedColor(context);
    final accent = premium?.accent ??
        (paper ? PaperTheme.accent : theme.colorScheme.primary);
    final secondary = premium?.textSecondary ??
        (paper ? PaperTheme.textSecondary : theme.colorScheme.onSurfaceVariant);

    return SidebarPalette(
      brightness: theme.brightness,
      isPaper: paper,
      background: WorkspacePalette.of(context).chrome,
      textPrimary: premium?.textPrimary ??
          (paper ? PaperTheme.textPrimary : theme.colorScheme.onSurface),
      textSecondary: secondary,
      textTertiary: premium?.textMuted ??
          (paper ? PaperTheme.textMuted : theme.hintColor),
      icon: secondary,
      hover: hover,
      selected: selected,
      selectedHover: Color.alphaBlend(hover, selected),
      accent: accent,
      edge: paper
          ? const Color(0x146A5947)
          : dark
              ? const Color(0x14FFFFFF)
              : const Color(0x0F16150F),
      dropIndicator: accent,
      scrollThumb: paper
          ? const Color(0x306A5947)
          : dark
              ? const Color(0x33FFFFFF)
              : const Color(0x2416150F),
    );
  }

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
    this.reserveLeadingSpace = false,
    this.onTap,
    this.onSecondaryPointerDown,
    this.onTertiaryTapDown,
    this.onHoverChanged,
  });

  final Widget label;

  /// The disclosure control, beside (never in place of) the editable icon.
  final Widget? leading;
  final Widget? icon;

  /// Leaf rows reserve the same gutter as their expandable siblings.
  final bool reserveLeadingSpace;

  /// Built only while hovered, focused or [active], so a sidebar of a thousand
  /// pages does not carry a thousand popovers. Focusing a row reveals its tools.
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
  final _focusNode = FocusNode(debugLabel: 'Sidebar row');
  bool _hovered = false;
  bool _focused = false;

  @override
  void dispose() {
    FocusManager.instance.removeListener(_syncFocus);
    _focusNode.dispose();
    super.dispose();
  }

  void _syncFocus() {
    final focused = _focusNode.hasFocus;
    if (!mounted || _focused == focused) return;
    // Only the focused row observes the global focus tree. Removing a focused
    // rename field can detach it before the ancestor's blur callback arrives.
    if (focused) {
      FocusManager.instance.addListener(_syncFocus);
    } else {
      FocusManager.instance.removeListener(_syncFocus);
    }
    setState(() => _focused = focused);
  }

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
    final revealed = _hovered ||
        _focused ||
        widget.active ||
        MediaQuery.accessibleNavigationOf(context);
    final background = widget.selected
        ? (revealed ? palette.selectedHover : palette.selected)
        : revealed
            ? palette.hover
            : palette.hoverAtRest;
    final reserve = SidebarMetrics.trailingReserve(widget.trailingSlots);

    final content = Row(
      children: [
        SizedBox(width: SidebarMetrics.rowInset + widget.indent),
        if (widget.leading != null || widget.reserveLeadingSpace)
          SizedBox(
            width: SidebarMetrics.disclosureSlot,
            child: Center(child: widget.leading),
          ),
        if (widget.icon != null) ...[
          SizedBox(
            width: SidebarMetrics.iconSlot,
            child: Center(
              // Keep the picker mounted when a save changes a dimmed default
              // into an undimmed custom icon (including keep-open selections).
              child: AnimatedOpacity(
                duration: WorkspaceTokens.motion(context, SidebarMetrics.hover),
                curve: SidebarMetrics.curve,
                opacity: !widget.dimIcon || revealed || widget.selected
                    ? 1
                    : SidebarMetrics.iconRestingOpacity,
                child: widget.icon,
              ),
            ),
          ),
          const SizedBox(width: SidebarMetrics.iconGap),
        ],
        Expanded(child: widget.label),
        SizedBox(width: reserve + SidebarMetrics.rowInset),
      ],
    );

    Widget row = AnimatedContainer(
      duration: WorkspaceTokens.motion(context, SidebarMetrics.hover),
      curve: SidebarMetrics.curve,
      height: widget.height,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(SidebarMetrics.rowRadius),
      ),
      // Foreground-only: keyboard focus must not add padding or move a title.
      // Keep this decorator mounted even while the ring is transparent.
      foregroundDecoration: BoxDecoration(
        borderRadius: BorderRadius.circular(SidebarMetrics.rowRadius),
        border: Border.all(
          color:
              _focused ? palette.accent : palette.accent.withValues(alpha: 0),
          width: 1.5,
        ),
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

    return Focus(
      focusNode: _focusNode,
      canRequestFocus: widget.onTap != null,
      skipTraversal: widget.onTap == null,
      onFocusChange: (_) => _syncFocus(),
      onKeyEvent: (_, event) {
        // Editing a name or activating a child button must never open the page.
        if (!_focusNode.hasPrimaryFocus ||
            widget.onTap == null ||
            event is! KeyDownEvent ||
            HardwareKeyboard.instance.isControlPressed ||
            HardwareKeyboard.instance.isMetaPressed ||
            HardwareKeyboard.instance.isAltPressed) {
          return KeyEventResult.ignored;
        }
        if (event.logicalKey == LogicalKeyboardKey.enter ||
            event.logicalKey == LogicalKeyboardKey.space) {
          widget.onTap!();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Semantics(
        button: widget.onTap != null,
        selected: widget.selected,
        onTap: widget.onTap,
        child: MouseRegion(
          opaque: false,
          cursor: SystemMouseCursors.click,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: GestureDetector(
            excludeFromSemantics: true,
            behavior: HitTestBehavior.translucent,
            onTap: widget.onTap,
            onTertiaryTapDown: widget.onTertiaryTapDown,
            child: row,
          ),
        ),
      ),
    );
  }
}

/// Fades contextual actions inside their reserved targets. Hover never moves
/// either a glyph or its hit area.
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
    return ExcludeFocus(
      excluding: !revealed,
      child: IgnorePointer(
        ignoring: !revealed,
        child: ExcludeSemantics(
          excluding: !revealed,
          child: AnimatedSwitcher(
            duration: WorkspaceTokens.motion(context, SidebarMetrics.reveal),
            switchInCurve: SidebarMetrics.curve,
            switchOutCurve: SidebarMetrics.curve,
            transitionBuilder: (child, animation) => FadeTransition(
              opacity: animation,
              child: child,
            ),
            child: revealed && builder != null
                ? Row(
                    key: const ValueKey('revealed'),
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: builder!(context),
                  )
                : const SizedBox.shrink(key: ValueKey('hidden')),
          ),
        ),
      ),
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
    final label = tooltip ??
        (expanded
            ? MaterialLocalizations.of(context).expandedIconTapHint
            : MaterialLocalizations.of(context).collapsedIconTapHint);
    final child = AnimatedRotation(
      duration: WorkspaceTokens.motion(context, SidebarMetrics.disclosure),
      curve: SidebarMetrics.curve,
      turns: expanded ? 0.25 : 0,
      child: SidebarGlyph(
        SidebarIcon.disclosure,
        size: SidebarMetrics.disclosureIconSize,
        color: palette.icon,
      ),
    );

    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: SizedBox(
        width: SidebarMetrics.disclosureSlot,
        height: SidebarMetrics.iconSlot,
        child: IconButton(
          onPressed: onTap,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(
            width: SidebarMetrics.disclosureSlot,
            height: SidebarMetrics.iconSlot,
          ),
          style: WorkspaceChrome.controlStyle(context).copyWith(
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: const WidgetStatePropertyAll(
              Size(SidebarMetrics.disclosureSlot, SidebarMetrics.iconSlot),
            ),
          ),
          icon: Semantics(label: label, excludeSemantics: true, child: child),
        ),
      ),
    );
  }
}

/// A borderless icon button sized to one action slot.
class SidebarIconButton extends StatelessWidget {
  const SidebarIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.tooltip,
    this.size = 16,
    this.dimension = SidebarMetrics.actionSlot,
    this.focusNode,
  });

  final SidebarIcon icon;
  final VoidCallback onPressed;
  final String? tooltip;
  final double size;
  final double dimension;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    final label = tooltip ??
        switch (icon) {
          SidebarIcon.settings => LocaleKeys.settings_menu_open.tr(),
          SidebarIcon.bell =>
            LocaleKeys.settings_notifications_titles_notifications.tr(),
          SidebarIcon.collapse => LocaleKeys.sideBar_closeSidebar.tr(),
          SidebarIcon.add || SidebarIcon.newPage => LocaleKeys.newPageText.tr(),
          _ => LocaleKeys.button_more.tr(),
        };
    return Tooltip(
      message: label,
      excludeFromSemantics: true,
      child: SizedBox.square(
        dimension: dimension,
        child: IconButton(
          focusNode: focusNode,
          onPressed: onPressed,
          style: WorkspaceChrome.controlStyle(context).copyWith(
            foregroundColor: WidgetStatePropertyAll(palette.icon),
            iconColor: WidgetStatePropertyAll(palette.icon),
            padding: const WidgetStatePropertyAll(EdgeInsets.zero),
            minimumSize: WidgetStatePropertyAll(Size.square(dimension)),
          ),
          icon: Semantics(
            label: label,
            excludeSemantics: true,
            child: SidebarGlyph(
              icon,
              size: size,
              color: palette.icon,
            ),
          ),
        ),
      ),
    );
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
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.body,
                color: palette.textSecondary,
              ).copyWith(
                fontWeight: FontWeight.w500,
                fontVariations: const [FontVariation.weight(500)],
              ),
            ),
          ),
          if (shortcut != null)
            Padding(
              padding: const EdgeInsets.only(left: SidebarMetrics.space2),
              child: Text(
                shortcut!,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.caption,
                  color: palette.textTertiary,
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
      style: WorkspaceTypography.style(
        context,
        WorkspaceTextRole.caption,
        color: color ?? palette.textTertiary,
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
      fadeDuration: WorkspaceTokens.motion(context, SidebarMetrics.structural),
      timeToFade: const Duration(milliseconds: 700),
      crossAxisMargin: 2,
      mainAxisMargin: 4,
      child: ScrollConfiguration(
        behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
        // Only the viewport and scrollbar should update while scrolling, not
        // the page tree or the popovers of every row crossed by the pointer.
        child: ScrollHoverSuppression(child: child),
      ),
    );
  }
}
