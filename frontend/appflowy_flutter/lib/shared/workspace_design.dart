import 'dart:math' as math;

import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_tokens.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

export 'workspace_tokens.dart';

/// A projection of the application's existing themes, not another theme store.
/// All surfaces stay warm in paper mode, including transient interaction layers.
@immutable
class WorkspacePalette {
  const WorkspacePalette._({
    required this.background,
    required this.chrome,
    required this.surface,
    required this.elevatedSurface,
    required this.secondarySurface,
    required this.primaryText,
    required this.secondaryText,
    required this.mutedText,
    required this.accent,
    required this.border,
    required this.hover,
    required this.selected,
    required this.focus,
    required this.destructive,
    required this.success,
    required this.shadow,
    required this.isDark,
  });

  factory WorkspacePalette.of(BuildContext context) {
    final theme = Theme.of(context);
    final premium = PremiumThemeExtension.maybeOf(context);
    final paper = PaperTheme.isEnabled(context);
    final dark = theme.brightness == Brightness.dark;
    return WorkspacePalette._(
      background: EditorSurfaceStyle.canvasBackgroundFor(
        theme.brightness,
        premium?.canvas ?? theme.scaffoldBackgroundColor,
        isPaper: paper,
      ),
      chrome: EditorSurfaceStyle.chromeBackground(context),
      surface: EditorSurfaceStyle.previewBackgroundFor(
        theme.brightness,
        premium?.surface ?? theme.colorScheme.surface,
        isPaper: paper,
      ),
      elevatedSurface: premium?.floatingSurface ?? theme.dialogBackgroundColor,
      secondarySurface:
          premium?.mutedSurface ?? theme.colorScheme.surfaceContainerLow,
      primaryText: premium?.textPrimary ?? theme.colorScheme.onSurface,
      secondaryText:
          premium?.textSecondary ?? theme.colorScheme.onSurfaceVariant,
      mutedText: premium?.textMuted ?? theme.hintColor,
      accent: premium?.accent ?? theme.colorScheme.primary,
      border: premium?.border ?? theme.colorScheme.outlineVariant,
      hover: premium?.hover ?? theme.colorScheme.surfaceContainer,
      selected: premium?.selected ?? theme.colorScheme.secondaryContainer,
      focus: premium?.accent ?? theme.colorScheme.primary,
      destructive: theme.colorScheme.error,
      success: dark
          ? const Color(0xFF71C68B)
          : paper
              ? const Color(0xFF588C42)
              : const Color(0xFF43955A),
      shadow: premium?.shadow ?? theme.shadowColor,
      isDark: dark,
    );
  }

  final Color background;

  /// A single opaque caption/sidebar surface, independent of a page's canvas.
  final Color chrome;
  final Color surface;
  final Color elevatedSurface;
  final Color secondarySurface;
  final Color primaryText;
  final Color secondaryText;
  final Color mutedText;
  final Color accent;
  final Color border;
  final Color hover;
  final Color selected;
  final Color focus;
  final Color destructive;
  final Color success;
  final Color shadow;
  final bool isDark;

  /// Contact, then ambient depth. Cards stay grounded; only popovers float.
  List<BoxShadow> elevation({bool floating = false, bool raised = false}) => [
        BoxShadow(
          color: shadow.withValues(alpha: isDark ? 0.16 : 0.045),
          blurRadius: 3,
          offset: const Offset(0, 1),
          spreadRadius: -1,
        ),
        BoxShadow(
          color: shadow.withValues(
            alpha: isDark ? 0.24 : (floating ? 0.10 : 0.055),
          ),
          blurRadius: floating ? 32 : (raised ? 16 : 10),
          offset: Offset(0, floating ? 12 : (raised ? 5 : 3)),
          spreadRadius: floating ? -8 : -4,
        ),
      ];
}

enum WorkspaceTextRole {
  pageTitle,
  section,
  cardTitle,
  body,
  metadata,
  caption
}

abstract final class WorkspaceTypography {
  static TextStyle style(
    BuildContext context,
    WorkspaceTextRole role, {
    Color? color,
    bool compact = false,
  }) {
    final palette = WorkspacePalette.of(context);
    final (size, weight, axis, height, tracking, ink) = switch (role) {
      WorkspaceTextRole.pageTitle => (
          compact ? 32.0 : 40.0,
          FontWeight.w700,
          700.0,
          1.15,
          -1.0,
          palette.primaryText,
        ),
      WorkspaceTextRole.section => (
          20.0,
          FontWeight.w600,
          650.0,
          1.3,
          -0.35,
          palette.primaryText
        ),
      WorkspaceTextRole.cardTitle => (
          15.0,
          FontWeight.w600,
          620.0,
          1.35,
          -0.2,
          palette.primaryText
        ),
      WorkspaceTextRole.body => (
          14.0,
          FontWeight.w400,
          450.0,
          1.5,
          0.0,
          palette.primaryText
        ),
      WorkspaceTextRole.metadata => (
          12.0,
          FontWeight.w400,
          450.0,
          1.4,
          0.0,
          palette.secondaryText
        ),
      WorkspaceTextRole.caption => (
          11.0,
          FontWeight.w500,
          500.0,
          1.4,
          0.1,
          palette.mutedText
        ),
    };
    return (Theme.of(context).textTheme.bodyMedium ?? const TextStyle())
        .copyWith(
      fontSize: size,
      fontWeight: weight,
      fontVariations: [FontVariation.weight(axis)],
      height: height,
      letterSpacing: tracking,
      color: color ?? ink,
    );
  }
}

enum WorkspaceSurfaceKind { canvas, secondary, card, floating }

/// Presentation-only surface. It never owns a renderer, controller or gesture.
class WorkspaceSurface extends StatelessWidget {
  const WorkspaceSurface({
    super.key,
    required this.child,
    this.kind = WorkspaceSurfaceKind.card,
    this.padding = EdgeInsets.zero,
    this.selected = false,
    this.raised = false,
    this.radius,
  });

  final Widget child;
  final WorkspaceSurfaceKind kind;
  final EdgeInsetsGeometry padding;
  final bool selected;
  final bool raised;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final floating = kind == WorkspaceSurfaceKind.floating;
    final corners = BorderRadius.circular(
      radius ??
          (floating
              ? WorkspaceTokens.dialogRadius
              : WorkspaceTokens.cardRadius),
    );
    return Container(
      decoration: BoxDecoration(
        color: switch (kind) {
          WorkspaceSurfaceKind.canvas => palette.background,
          WorkspaceSurfaceKind.secondary => palette.secondarySurface,
          WorkspaceSurfaceKind.card => palette.surface,
          WorkspaceSurfaceKind.floating => palette.elevatedSurface,
        },
        borderRadius: corners,
        boxShadow: kind == WorkspaceSurfaceKind.card || floating
            ? palette.elevation(floating: floating, raised: raised)
            : null,
      ),
      // A nullable foreground inserts/removes a DecoratedBox in Container's
      // implementation, remounting a stateful renderer on selection. Keep it.
      foregroundDecoration: BoxDecoration(
        borderRadius: corners,
        border: Border.all(
          color: selected ? palette.focus : palette.focus.withValues(alpha: 0),
          width: 1.5,
        ),
      ),
      child: ClipRRect(
        borderRadius: corners,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// Page identity is a vertical composition, never an icon/title toolbar row.
/// Slots keep the original editable title, icon picker and their focus state.
class WorkspacePageIdentity extends StatelessWidget {
  const WorkspacePageIdentity({
    super.key,
    required this.title,
    this.icon,
    this.iconActions,
    this.description,
    this.metadata,
    this.actions,
    this.trailing,
    this.trailingTopInset = 0,
    this.metadataSpacing = WorkspaceTokens.space3,
  });

  final Widget title;
  final Widget? icon;
  final Widget? iconActions;
  final Widget? description;
  final Widget? metadata;
  final Widget? actions;

  /// Tools that share the title block's row when both fit, and otherwise
  /// wrap below it at the physical right. The subtree is never reparented.
  final Widget? trailing;

  /// Transparent space [trailing] reserves above its controls (for example
  /// action feedback); it may overlap the icon row instead of adding height.
  final double trailingTopInset;
  final double metadataSpacing;

  @override
  Widget build(BuildContext context) {
    final overlap = _WorkspacePageHeaderGeometry.maybeOf(context)?.overlap ?? 0;
    final heading = <Widget>[
      Semantics(
        key: const ValueKey('workspace-page-title'),
        header: true,
        child: title,
      ),
      if (description != null)
        Padding(
          key: const ValueKey('workspace-page-description'),
          padding: const EdgeInsets.only(top: WorkspaceTokens.space2),
          child: DefaultTextStyle(
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.body,
              color: WorkspacePalette.of(context).secondaryText,
            ),
            child: description!,
          ),
        ),
      if (metadata != null)
        Padding(
          key: const ValueKey('workspace-page-metadata'),
          padding: EdgeInsets.only(top: metadataSpacing),
          child: DefaultTextStyle(
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.metadata,
            ),
            child: metadata!,
          ),
        ),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (icon != null || iconActions != null)
          Padding(
            key: const ValueKey('workspace-page-icon-row'),
            padding: const EdgeInsets.only(
              bottom: WorkspaceTokens.pageIconTitleGap,
            ),
            child: Align(
              alignment: AlignmentDirectional.centerStart,
              // The header, not just this row, owns hover/touch reveal.
              // Start alignment keeps the icon's overlap exact even when
              // enlarged labels make the neighboring actions taller.
              child: Wrap(
                spacing: WorkspaceTokens.space2,
                runSpacing: WorkspaceTokens.space1,
                crossAxisAlignment: overlap > 0
                    ? WrapCrossAlignment.start
                    : WrapCrossAlignment.center,
                children: [
                  if (icon != null)
                    KeyedSubtree(
                      key: const ValueKey('workspace-page-icon'),
                      child: icon!,
                    ),
                  if (iconActions != null)
                    Padding(
                      key: const ValueKey('workspace-page-icon-actions'),
                      // Only artwork crosses the image edge. Native button
                      // hit targets stay below it, including at 200% scale.
                      padding: EdgeInsets.only(
                        top: overlap > 0 ? overlap + WorkspaceTokens.space2 : 0,
                      ),
                      child: iconActions,
                    ),
                ],
              ),
            ),
          ),
        if (trailing == null)
          ...heading
        else
          _WorkspaceIdentityTrailingLayout(
            key: const ValueKey('workspace-page-title-row'),
            topInset: trailingTopInset,
            // A readable, text-scaled title allowance before tools wrap.
            minimumIdentityWidth: MediaQuery.textScalerOf(context).scale(200),
            identity: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: heading,
            ),
            trailing: KeyedSubtree(
              key: const ValueKey('workspace-page-trailing'),
              child: trailing!,
            ),
          ),
        if (actions != null)
          Padding(
            key: const ValueKey('workspace-page-actions'),
            padding: const EdgeInsets.only(
              top: WorkspaceTokens.pageActionsGap,
            ),
            child: actions,
          ),
      ],
    );
  }
}

/// Places [trailing] beside the identity block, centring its controls (below
/// any reserved top inset) on that block, or wraps it below at the right when
/// the identity would drop under its minimum width.
class _WorkspaceIdentityTrailingLayout extends MultiChildRenderObjectWidget {
  _WorkspaceIdentityTrailingLayout({
    super.key,
    required Widget identity,
    required Widget trailing,
    required this.topInset,
    required this.minimumIdentityWidth,
  }) : super(children: [identity, trailing]);

  final double topInset;
  final double minimumIdentityWidth;

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderWorkspaceIdentityTrailing(
        topInset: topInset,
        minimumIdentityWidth: minimumIdentityWidth,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderWorkspaceIdentityTrailing renderObject,
  ) {
    renderObject
      ..topInset = topInset
      ..minimumIdentityWidth = minimumIdentityWidth;
  }
}

class _WorkspaceIdentityTrailingParentData
    extends ContainerBoxParentData<RenderBox> {}

class _RenderWorkspaceIdentityTrailing extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox,
            _WorkspaceIdentityTrailingParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox,
            _WorkspaceIdentityTrailingParentData> {
  _RenderWorkspaceIdentityTrailing({
    required double topInset,
    required double minimumIdentityWidth,
  })  : _topInset = topInset,
        _minimumIdentityWidth = minimumIdentityWidth;

  static const _spacing = WorkspaceTokens.space4;

  double _topInset;
  set topInset(double value) {
    if (_topInset == value) return;
    _topInset = value;
    markNeedsLayout();
  }

  double _minimumIdentityWidth;
  set minimumIdentityWidth(double value) {
    if (_minimumIdentityWidth == value) return;
    _minimumIdentityWidth = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _WorkspaceIdentityTrailingParentData) {
      child.parentData = _WorkspaceIdentityTrailingParentData();
    }
  }

  @override
  void performLayout() {
    assert(constraints.hasBoundedWidth);
    final identity = firstChild!;
    final trailing = lastChild!;
    final width = constraints.maxWidth;
    // Measure the real tools once; LayoutBuilder publishers have no intrinsics.
    trailing.layout(BoxConstraints(maxWidth: width), parentUsesSize: true);
    final remaining = width - trailing.size.width - _spacing;
    final stacked = remaining < _minimumIdentityWidth;
    identity.layout(
      BoxConstraints.tightFor(width: stacked ? width : remaining),
      parentUsesSize: true,
    );
    final identityData =
        identity.parentData! as _WorkspaceIdentityTrailingParentData;
    final trailingData =
        trailing.parentData! as _WorkspaceIdentityTrailingParentData;
    if (stacked) {
      identityData.offset = Offset.zero;
      trailingData.offset = Offset(
        width - trailing.size.width,
        identity.size.height,
      );
      size = constraints.constrain(
        Size(width, identity.size.height + trailing.size.height),
      );
      return;
    }
    final controls = math.max(0.0, trailing.size.height - _topInset);
    final height = math.max(identity.size.height, controls);
    identityData.offset = Offset(0, (height - identity.size.height) / 2);
    trailingData.offset = Offset(
      width - trailing.size.width,
      (height - controls) / 2 - _topInset,
    );
    size = constraints.constrain(Size(width, height));
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      defaultPaint(context, offset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

/// A broad cover and a quieter reading measure are intentionally independent.
/// Put this INSIDE the page scrollable so identity gives way to the content.
class WorkspacePageHeader extends StatelessWidget {
  const WorkspacePageHeader({
    super.key,
    required this.identity,
    this.leading,
    this.cover,
    this.coverActions,
    this.overlapIcon,
    this.maxWidth = WorkspaceTokens.pageMaxWidth,
    this.contentInset,
    this.coverHeight = WorkspaceTokens.coverHeight,
    this.coverView,
    this.coverEditable = false,
    this.coverBinding,
    this.canResizeCover,
    this.isSameCoverTarget,
    this.onCoverHeightChanged,
    this.coverBackend,
  });

  final Widget identity;

  /// Existing page context, outside the picture/identity overlap. Its owner
  /// keeps all navigation behavior; this slot only shares the reading insets.
  final Widget? leading;
  final Widget? cover;
  final Widget? coverActions;

  /// Wrapped identities can declare their icon. Direct WorkspacePageIdentity
  /// children are detected automatically; a title alone never overlaps.
  final bool? overlapIcon;
  final double maxWidth;
  final double? contentInset;
  final double coverHeight;
  final ViewPB? coverView;
  final bool coverEditable;
  final Object? coverBinding;
  final bool Function()? canResizeCover;
  final bool Function(ViewPB)? isSameCoverTarget;
  final ValueChanged<double?>? onCoverHeightChanged;

  /// Where [coverView]'s height is read and saved; null uses the folder.
  final PageCoverBackendService? coverBackend;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
        builder: (context, constraints) {
          final width = constraints.hasBoundedWidth
              ? constraints.maxWidth
              : WorkspaceTokens.pageMaxWidth;
          final inset = contentInset ?? WorkspaceTokens.pageInset(width);
          return PageCoverLayout(
            width: (width - WorkspaceTokens.coverInset * 2)
                .clamp(0.0, double.infinity)
                .toDouble(),
            fallbackHeight:
                width < 600 ? WorkspaceTokens.compactCoverHeight : coverHeight,
            view: coverView,
            editable: cover != null && coverEditable,
            binding: coverBinding,
            canResize: canResizeCover,
            isSameTarget: isSameCoverTarget,
            onHeightChanged: onCoverHeightChanged,
            backend: coverBackend,
            builder: (context, imageHeight, grip) {
              final hasIcon = overlapIcon ??
                  (identity is WorkspacePageIdentity &&
                      (identity as WorkspacePageIdentity).icon != null);
              final overlap = cover != null && hasIcon
                  ? WorkspaceTokens.pageIconCoverOverlap
                      .clamp(0.0, imageHeight)
                      .toDouble()
                  : 0.0;
              final identityTop = cover == null
                  ? (leading == null
                      ? WorkspaceTokens.pageTopWithoutCover
                      : 0.0)
                  : WorkspaceTokens.space2 +
                      imageHeight +
                      (overlap > 0
                          ? -overlap
                          : WorkspaceTokens.pageTopWithCover);
              return PreviewToolbarRegion(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (leading != null)
                      Center(
                        key: const ValueKey('workspace-page-leading'),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: maxWidth),
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(
                              inset,
                              WorkspaceTokens.pageTopWithoutCover,
                              inset,
                              0,
                            ),
                            child: SizedBox(
                              width: double.infinity,
                              child: leading,
                            ),
                          ),
                        ),
                      ),
                    _WorkspacePageHeaderGeometry(
                      key: const ValueKey('workspace-page-header-body'),
                      overlap: overlap,
                      // The non-positioned identity determines the actual extent.
                      // Its top padding reserves the cover minus the overlap, so
                      // the entire icon is inside this Stack's hit-test bounds.
                      child: Stack(
                        children: [
                          if (cover != null)
                            Positioned(
                              key: const ValueKey('workspace-page-cover'),
                              top: WorkspaceTokens.space2,
                              left: WorkspaceTokens.coverInset,
                              right: WorkspaceTokens.coverInset,
                              height: imageHeight,
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(
                                  PageCoverPresentation.maybeOf(context)!
                                      .appearance
                                      .radius,
                                ),
                                child: WorkspacePageCover(
                                  image: cover!,
                                  actions: coverActions,
                                  resizeGrip: grip,
                                ),
                              ),
                            ),
                          Padding(
                            key: const ValueKey('workspace-page-identity'),
                            padding: EdgeInsets.only(top: identityTop),
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(maxWidth: maxWidth),
                                child: Padding(
                                  padding: EdgeInsets.fromLTRB(
                                    inset,
                                    0,
                                    inset,
                                    WorkspaceTokens.pageHeaderBottom,
                                  ),
                                  child: SizedBox(
                                    width: double.infinity,
                                    child: identity,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      );
}

class _WorkspacePageHeaderGeometry extends InheritedWidget {
  const _WorkspacePageHeaderGeometry({
    super.key,
    required this.overlap,
    required super.child,
  });

  final double overlap;

  static _WorkspacePageHeaderGeometry? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_WorkspacePageHeaderGeometry>();

  @override
  bool updateShouldNotify(_WorkspacePageHeaderGeometry oldWidget) =>
      overlap != oldWidget.overlap;
}

/// Image-local tools share the existing preview interaction policy. The image
/// stays mounted at the same depth when access or toolbar visibility changes.
class WorkspacePageCover extends StatelessWidget {
  const WorkspacePageCover({
    super.key,
    required this.image,
    this.actions,
    this.resizeGrip,
    this.bottomInset = 0,
  });

  final Widget image;
  final Widget? actions;
  final Widget? resizeGrip;

  /// Room kept clear along the bottom edge for something laid across it,
  /// such as Home's search bar. The grip and actions sit above it.
  final double bottomInset;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final inherited = PageCoverPresentation.maybeOf(context);
    final appearance =
        inherited?.appearance ?? CoverAppearanceScope.of(context);
    return PageCoverPresentation(
      appearance: appearance,
      alignment: inherited?.alignment ?? appearance.alignment,
      child: PreviewToolbarRegion(
        child: ClipRRect(
          borderRadius: BorderRadius.circular(
            (PageCoverPresentation.maybeOf(context)?.appearance ??
                    CoverAppearanceScope.of(context))
                .radius,
          ),
          child: Stack(
            fit: StackFit.expand,
            children: [
              image,
              if (actions != null)
                PositionedDirectional(
                  bottom: (resizeGrip == null ? WorkspaceTokens.space2 : 28) +
                      bottomInset,
                  start: WorkspaceTokens.space2,
                  end: WorkspaceTokens.space2,
                  child: Align(
                    alignment: AlignmentDirectional.bottomEnd,
                    child: PreviewToolbar(
                      child: DecoratedBox(
                        key: const ValueKey('workspace-cover-action-surface'),
                        decoration: BoxDecoration(
                          // Nearly opaque floating ink/paper stays legible even
                          // on a high-contrast photograph, without tinting it.
                          color:
                              palette.elevatedSurface.withValues(alpha: 0.96),
                          borderRadius: BorderRadius.circular(
                            WorkspaceTokens.controlRadius,
                          ),
                          border: Border.all(color: palette.border),
                          boxShadow: palette.elevation(floating: true),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(2),
                          child: actions!,
                        ),
                      ),
                    ),
                  ),
                ),
              if (resizeGrip != null)
                Positioned(
                  bottom: bottomInset,
                  left: 0,
                  right: 0,
                  child: Center(child: resizeGrip),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Empty content remains a place to begin, not an empty bordered panel.
class WorkspaceEmptyState extends StatelessWidget {
  const WorkspaceEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.description,
    this.action,
  });

  final IconData icon;
  final String title;
  final String description;
  final Widget? action;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(WorkspaceTokens.space8),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 40,
                  color: WorkspacePalette.of(context).accent,
                ),
                const SizedBox(height: WorkspaceTokens.space6),
                Text(
                  title,
                  textAlign: TextAlign.center,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.section,
                  ),
                ),
                const SizedBox(height: WorkspaceTokens.space2),
                Text(
                  description,
                  textAlign: TextAlign.center,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.metadata,
                  ),
                ),
                if (action != null) ...[
                  const SizedBox(height: WorkspaceTokens.space6),
                  action!,
                ],
              ],
            ),
          ),
        ),
      );
}
