import 'dart:async';

import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:flutter/material.dart';

import 'folder_explorer_style.dart';

const galleryCardHoverDuration = WorkspaceTokens.hoverDuration;
const galleryCardHairlineWidth = 0.75;

/// Gallery-only paint roles. Neither the workspace palette nor saved geometry
/// changes when a card needs separation from the sheet behind it.
@immutable
class GalleryCardPalette {
  const GalleryCardPalette._({
    required this.surface,
    required this.footer,
    required this.footerRule,
    required this.edge,
    required this.activeEdge,
    required this.restingShadows,
    required this.raisedShadows,
  });

  factory GalleryCardPalette.of(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final brightness = Theme.of(context).brightness;
    final dark = brightness == Brightness.dark;
    final paper = !dark && PaperTheme.isEnabled(context);
    final preview = Color.alphaBlend(
      EditorSurfaceStyle.previewBackgroundFor(
        brightness,
        palette.surface,
        isPaper: paper,
      ),
      EditorSurfaceStyle.canvasBackground(context),
    );
    final ink = palette.textPrimary;
    // Paper's explorer background and preview otherwise resolve to the same
    // color. A cream sheet separates from BOTH that preview and the writing
    // canvas; a weak blend would merely reproduce the canvas. Light/dark use
    // their own semantic ink, not hard-coded white, grey or accent washes.
    final surface = paper
        ? Color.lerp(preview, PaperTheme.controlBackground, 0.75)!
        : Color.alphaBlend(
            ink.withValues(alpha: ink.a * (dark ? 0.035 : 0.018)),
            preview,
          );
    final shadow = palette.shadow;
    Color shadowAt(double factor) => shadow.withValues(
          alpha: (shadow.a * factor).clamp(0.0, dark ? 0.4 : 0.18),
        );
    return GalleryCardPalette._(
      surface: surface,
      footer: Color.alphaBlend(
        ink.withValues(alpha: ink.a * (dark ? 0.025 : 0.018)),
        surface,
      ),
      footerRule: ink.withValues(alpha: ink.a * (dark ? 0.08 : 0.065)),
      edge: ink.withValues(alpha: ink.a * (dark ? 0.14 : 0.12)),
      activeEdge: ink.withValues(alpha: ink.a * (dark ? 0.24 : 0.22)),
      // Tight contact + restrained ambient depth fit even the archive gutter.
      // Alpha is scaled from the theme's shadow, including custom themes.
      restingShadows: [
        BoxShadow(
          color: shadowAt(dark ? 0.8 : 1.15),
          blurRadius: 3,
          offset: const Offset(0, 1),
          spreadRadius: -1,
        ),
        BoxShadow(
          color: shadowAt(dark ? 1 : 1.35),
          blurRadius: 12,
          offset: const Offset(0, 4),
          spreadRadius: -3,
        ),
      ],
      raisedShadows: [
        BoxShadow(
          color: shadowAt(dark ? 1 : 1.5),
          blurRadius: 5,
          offset: const Offset(0, 2),
          spreadRadius: -1,
        ),
        BoxShadow(
          color: shadowAt(dark ? 1.3 : 1.75),
          blurRadius: 16,
          offset: const Offset(0, 6),
          spreadRadius: -4,
        ),
      ],
    );
  }

  final Color surface;
  final Color footer;
  final Color footerRule;
  final Color edge;
  final Color activeEdge;
  final List<BoxShadow> restingShadows;
  final List<BoxShadow> raisedShadows;

  BoxDecoration decoration(double emphasis) => BoxDecoration(
        color: surface,
        borderRadius: EditorSurfaceStyle.embedBorderRadius,
        boxShadow: BoxShadow.lerpList(restingShadows, raisedShadows, emphasis),
      );

  BoxDecoration outline(double emphasis) => BoxDecoration(
        borderRadius: EditorSurfaceStyle.embedBorderRadius,
        border: Border.all(
          color: Color.lerp(edge, activeEdge, emphasis)!,
          width: galleryCardHairlineWidth,
        ),
      );

  /// Reusable thumbnails outside a gallery retain their host's old surface.
  /// Inside a card, empty/loading/text faces use the card's actual sheet.
  static Color previewSurface(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_GalleryCardScope>()
          ?.surface ??
      EditorSurfaceStyle.previewBackgroundFor(
        Theme.of(context).brightness,
        FolderExplorerPalette.of(context).floatingSurface,
        isPaper: PaperTheme.isEnabled(context),
      );
}

/// Paint-only elevation: no translation, scale, padding tween, gesture owner,
/// or conditional wrapper around a loaded renderer / inline name editor.
/// The card's existing mouse and focus boundary supplies interaction state;
/// this surface owns only the animation, not a second input boundary.
class GalleryCardSurface extends StatefulWidget {
  const GalleryCardSurface({
    super.key,
    required this.child,
    this.hovered = false,
    this.focused = false,
    this.selected = false,
  });

  final Widget child;
  final bool hovered;
  final bool focused;
  final bool selected;

  @override
  State<GalleryCardSurface> createState() => _GalleryCardSurfaceState();
}

class _GalleryCardSurfaceState extends State<GalleryCardSurface>
    with SingleTickerProviderStateMixin {
  late final AnimationController _emphasis;
  late double _target;
  Duration _duration = galleryCardHoverDuration;

  @override
  void initState() {
    super.initState();
    _target = widget.hovered || widget.focused ? 1.0 : 0.0;
    _emphasis = AnimationController(vsync: this, value: _target);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _duration = WorkspaceTokens.motion(context, galleryCardHoverDuration);
    _updateEmphasis();
  }

  @override
  void didUpdateWidget(GalleryCardSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    _updateEmphasis();
  }

  void _updateEmphasis() {
    final target = widget.hovered || widget.focused ? 1.0 : 0.0;
    if (_duration == Duration.zero) {
      _target = target;
      // Also stop an in-flight transition when the accessibility flag changes.
      if (_emphasis.value != target || _emphasis.isAnimating) {
        _emphasis.value = target;
      }
    } else if (_target != target) {
      _target = target;
      unawaited(
        _emphasis.animateTo(
          target,
          duration: _duration,
          curve: WorkspaceTokens.curve,
        ),
      );
    }
  }

  @override
  void dispose() {
    _emphasis.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = GalleryCardPalette.of(context);
    final corners = EditorSurfaceStyle.embedBorderRadius;
    return _GalleryCardScope(
      surface: palette.surface,
      // The exact existing selection/focus ring paints LAST, above both
      // the neutral hairline and media clip. It never animates or adds inset.
      child: DecoratedBox(
        key: const ValueKey('folder-gallery-selection'),
        position: DecorationPosition.foreground,
        decoration: BoxDecoration(
          borderRadius: corners,
          border: widget.selected || widget.focused
              ? Border.all(
                  color: WorkspacePalette.of(context).focus,
                  width: 1.5,
                )
              : null,
        ),
        child: AnimatedBuilder(
          animation: _emphasis,
          child: ClipRRect(borderRadius: corners, child: widget.child),
          builder: (context, child) => DecoratedBox(
            key: const ValueKey('gallery-card-surface'),
            decoration: palette.decoration(_emphasis.value),
            child: DecoratedBox(
              key: const ValueKey('gallery-card-edge'),
              position: DecorationPosition.foreground,
              decoration: palette.outline(_emphasis.value),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// A footer wash and hairline that consume none of the caption's layout space.
class GalleryCardFooter extends StatelessWidget {
  const GalleryCardFooter({
    super.key,
    required this.padding,
    required this.child,
  });

  final EdgeInsetsGeometry padding;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final palette = GalleryCardPalette.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.footer,
        border: Border(
          top: BorderSide(
            color: palette.footerRule,
            width: galleryCardHairlineWidth,
          ),
        ),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _GalleryCardScope extends InheritedWidget {
  const _GalleryCardScope({required this.surface, required super.child});

  final Color surface;

  @override
  bool updateShouldNotify(_GalleryCardScope oldWidget) =>
      surface != oldWidget.surface;
}
