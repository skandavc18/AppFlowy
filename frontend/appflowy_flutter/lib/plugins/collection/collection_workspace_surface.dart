import 'dart:math' as math;

import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';

/// Body geometry shared by collections. The collection page owns its identity;
/// these insets start at the child view, never around the cover or page title.
abstract final class CollectionWorkspaceMetrics {
  static const gutter = WorkspaceTokens.space6;
  static const topGap = WorkspaceTokens.space4;
  static const paneGap = WorkspaceTokens.space6;
  static const railWidth = 220.0;
  static const minimumStageWidth = 560.0;
  static const bodyInsets = EdgeInsets.fromLTRB(gutter, topGap, gutter, gutter);

  static double railWidthFor(BuildContext context, double width) =>
      width * (MediaQuery.textScalerOf(context).scale(13) / 13).clamp(1, 1.4);

  static bool fitsRail(
    BuildContext context,
    double available, {
    double railWidth = CollectionWorkspaceMetrics.railWidth,
    double minimumStageWidth = CollectionWorkspaceMetrics.minimumStageWidth,
  }) =>
      available >=
      railWidthFor(context, railWidth) +
          paneGap +
          minimumStageWidth +
          math.max(0, MediaQuery.textScalerOf(context).scale(120) - 120);
}

/// Navigation is medium weight in both system and variable faces. A selected
/// item changes its outline, not its weight, icon family or text measure.
TextStyle collectionWorkspaceLabel(
  BuildContext context, {
  Color? color,
  double size = 13,
}) =>
    (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      fontSize: size,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation.weight(500)],
      height: 1.35,
      letterSpacing: 0,
      color: color ?? WorkspacePalette.of(context).secondaryText,
    );

/// A continuous, unelevated surface. A *content object* may opt into one rounded
/// tonal panel; navigation and stages do not become cards merely by existing.
/// Decoration and clipping stay at a constant depth when these values change.
class CollectionWorkspaceSurface extends StatelessWidget {
  const CollectionWorkspaceSurface({
    super.key,
    required this.child,
    this.padding = EdgeInsets.zero,
    this.tonal = false,
    this.rounded = false,
    this.color,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool tonal;
  final bool rounded;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final radius =
        BorderRadius.circular(rounded ? WorkspaceTokens.cardRadius : 0);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color ?? (tonal ? palette.secondarySurface : palette.background),
        borderRadius: radius,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: Padding(padding: padding, child: child),
      ),
    );
  }
}

/// A fixed-depth rail + stage. Compact composition hides navigation, not data.
/// The rail remains mounted offstage, retaining its filter, expansion and scroll;
/// the stage never moves into a different Row/Column or AnimatedSwitcher branch.
class CollectionWorkspaceSplit extends StatelessWidget {
  const CollectionWorkspaceSplit({
    super.key,
    required this.navigation,
    required this.compactNavigation,
    required this.child,
    this.headerBuilder,
    this.navigationVisible = true,
    this.railWidth = CollectionWorkspaceMetrics.railWidth,
    this.minimumStageWidth = CollectionWorkspaceMetrics.minimumStageWidth,
    this.padding = CollectionWorkspaceMetrics.bodyInsets,
  });

  final Widget navigation;
  final Widget compactNavigation;
  final Widget child;
  final Widget Function(BuildContext context, bool railVisible)? headerBuilder;
  final bool navigationVisible;
  final double railWidth;
  final double minimumStageWidth;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final wide = navigationVisible &&
                CollectionWorkspaceMetrics.fitsRail(
                  context,
                  constraints.maxWidth,
                  railWidth: railWidth,
                  minimumStageWidth: minimumStageWidth,
                );
            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Offstage(
                  key: const ValueKey('collection-workspace-navigation'),
                  offstage: !wide,
                  child: ExcludeFocus(
                    excluding: !wide,
                    child: TickerMode(
                      enabled: wide,
                      child: SizedBox(
                        width: CollectionWorkspaceMetrics.railWidthFor(
                          context,
                          railWidth,
                        ),
                        child: navigation,
                      ),
                    ),
                  ),
                ),
                SizedBox(width: wide ? CollectionWorkspaceMetrics.paneGap : 0),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Offstage(
                        key: const ValueKey('collection-workspace-picker'),
                        offstage: wide || headerBuilder != null,
                        child: ExcludeFocus(
                          excluding: wide || headerBuilder != null,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              bottom: WorkspaceTokens.space2,
                            ),
                            child: compactNavigation,
                          ),
                        ),
                      ),
                      if (headerBuilder != null) headerBuilder!(context, wide),
                      Expanded(
                        child: KeyedSubtree(
                          key: const ValueKey('collection-workspace-stage'),
                          child: child,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      );
}

/// One unboxed row of context and tools. Narrow panes wrap tools rather than
/// stealing width from the data or putting required actions in a clipped strip.
class CollectionWorkspaceToolbar extends StatelessWidget {
  const CollectionWorkspaceToolbar({
    super.key,
    this.identity,
    this.actions = const [],
    this.keepVisible = false,
    this.padding = const EdgeInsets.symmetric(
      horizontal: CollectionWorkspaceMetrics.gutter,
    ),
  });

  final Widget? identity;
  final List<Widget> actions;
  final bool keepVisible;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Padding(
        padding: padding,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final stacked = width < MediaQuery.textScalerOf(context).scale(640);
            return ConstrainedBox(
              constraints: const BoxConstraints(
                minHeight: WorkspaceTokens.controlHeight,
              ),
              child: Wrap(
                spacing: WorkspaceTokens.space2,
                runSpacing: WorkspaceTokens.space2,
                alignment: WrapAlignment.spaceBetween,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (identity != null)
                    SizedBox(
                      width: stacked || actions.isEmpty ? width : width * 0.38,
                      child: identity,
                    ),
                  if (actions.isNotEmpty)
                    SizedBox(
                      width: stacked || identity == null
                          ? width
                          : math.max(0, width * 0.62 - WorkspaceTokens.space2),
                      child: PreviewToolbar(
                        keepVisible: keepVisible,
                        child: Wrap(
                          spacing: WorkspaceTokens.space1,
                          runSpacing: WorkspaceTokens.space1,
                          alignment: fileActionRunAlignment(context),
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: actions,
                        ),
                      ),
                    ),
                ],
              ),
            );
          },
        ),
      );
}

class CollectionWorkspaceRailHeader extends StatelessWidget {
  const CollectionWorkspaceRailHeader({
    super.key,
    required this.label,
    this.actions = const [],
  });

  final String label;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: WorkspaceTokens.space2),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: collectionWorkspaceLabel(context, size: 12),
              ),
            ),
            PreviewToolbar(
              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
            ),
          ],
        ),
      );
}

/// Native focus/activation semantics, with the same outline family as rows.
class CollectionWorkspaceAction extends StatelessWidget {
  const CollectionWorkspaceAction({
    super.key,
    required this.icon,
    required this.tooltip,
    this.label,
    this.onPressed,
    this.selected = false,
    this.size = WorkspaceTokens.controlHeight,
    this.color,
    this.trailingIcon,
  });

  final IconData icon;
  final String tooltip;
  final String? label;
  final VoidCallback? onPressed;
  final bool selected;
  final double size;
  final Color? color;
  final IconData? trailingIcon;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final baseInk = color ?? palette.secondaryText;
    final ink = onPressed == null
        ? baseInk.withValues(alpha: baseInk.a * 0.45)
        : baseInk;
    return Tooltip(
      message: tooltip,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 500),
      child: TextButton(
        onPressed: onPressed,
        style:
            WorkspaceChrome.controlStyle(context, selected: selected).copyWith(
          minimumSize: WidgetStatePropertyAll(Size(size, size)),
          padding: WidgetStatePropertyAll(
            EdgeInsets.symmetric(
              horizontal: label == null ? 6 : 10,
              vertical: 6,
            ),
          ),
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          foregroundColor: WidgetStatePropertyAll(ink),
          iconColor: WidgetStatePropertyAll(ink),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(WorkspaceTokens.controlRadius),
            ),
          ),
        ),
        child: Semantics(
          label: tooltip,
          selected: selected,
          excludeSemantics: true,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              WorkspaceGlyph(icon, size: 16, color: ink),
              if (label != null) ...[
                const SizedBox(width: 6),
                Flexible(
                  child: Text(
                    label!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        collectionWorkspaceLabel(context, color: ink, size: 12),
                  ),
                ),
              ],
              if (trailingIcon != null) ...[
                const SizedBox(width: 4),
                WorkspaceGlyph(trailingIcon!, size: 14, color: ink),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class CollectionWorkspaceNavRow extends StatefulWidget {
  const CollectionWorkspaceNavRow({
    super.key,
    this.child,
    this.builder,
    this.selected = false,
    this.onTap,
    this.onDoubleTap,
    this.onContextMenu,
    this.minHeight = WorkspaceTokens.navigationHeight,
    this.padding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
  }) : assert(child != null || builder != null);

  final Widget? child;
  final Widget Function(BuildContext context, bool engaged)? builder;
  final bool selected;
  final VoidCallback? onTap;
  final VoidCallback? onDoubleTap;
  final ValueChanged<Offset>? onContextMenu;
  final double minHeight;
  final EdgeInsetsGeometry padding;

  @override
  State<CollectionWorkspaceNavRow> createState() =>
      _CollectionWorkspaceNavRowState();
}

class _CollectionWorkspaceNavRowState extends State<CollectionWorkspaceNavRow> {
  bool hovered = false;
  bool focused = false;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final hover = WorkspaceChrome.hoverColor(context);
    final selected = WorkspaceChrome.selectedColor(context);
    final engaged = hovered || focused;
    final radius = BorderRadius.circular(WorkspaceTokens.controlRadius);
    return Semantics(
      selected: widget.selected,
      button: widget.onTap != null,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: widget.onTap,
          onDoubleTap: widget.onDoubleTap,
          onSecondaryTapDown: widget.onContextMenu == null
              ? null
              : (details) => widget.onContextMenu!(details.globalPosition),
          onHover: (value) => setState(() => hovered = value),
          onFocusChange: (value) => setState(() => focused = value),
          borderRadius: radius,
          splashFactory: NoSplash.splashFactory,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
          highlightColor: WorkspaceChrome.pressedColor(context),
          child: AnimatedContainer(
            duration:
                WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
            curve: WorkspaceTokens.curve,
            constraints: BoxConstraints(minHeight: widget.minHeight),
            padding: widget.padding,
            decoration: BoxDecoration(
              // A semantic selection survives hover; keyboard focus has its
              // own full-contrast stroke, rather than a stronger grey wash.
              color: widget.selected
                  ? engaged
                      ? Color.alphaBlend(hover, selected)
                      : selected
                  : engaged
                      ? hover
                      : hover.withValues(alpha: 0),
              borderRadius: radius,
              border: Border.all(
                color: focused
                    ? palette.focus
                    : widget.selected || hovered
                        ? palette.border
                        : palette.border.withValues(alpha: 0),
              ),
            ),
            child: widget.builder?.call(context, engaged) ?? widget.child,
          ),
        ),
      ),
    );
  }
}

/// The compact alternative to a rail. Menu entries retain the original model
/// callbacks, and AppMenu holds the originating preview while the popup is open.
class CollectionWorkspacePicker extends StatelessWidget {
  const CollectionWorkspacePicker({
    super.key,
    required this.label,
    required this.tooltip,
    required this.entries,
    this.icon = Icons.menu_open_rounded,
  });

  final String label;
  final String tooltip;
  final List<AppMenuEntry> entries;
  final IconData icon;

  @override
  Widget build(BuildContext context) => Builder(
        builder: (anchor) => Align(
          alignment: AlignmentDirectional.centerStart,
          child: CollectionWorkspaceAction(
            icon: icon,
            label: label,
            tooltip: tooltip,
            trailingIcon: Icons.expand_more_rounded,
            onPressed: () => showAppMenuForWidget<void>(
              context: anchor,
              entries: entries,
            ),
          ),
        ),
      );
}
