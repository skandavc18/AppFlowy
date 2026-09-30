import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart'
    show dashboardTextScaleKey;
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The height a dashboard widget is given on Home, from its height units.
double homeWidgetHeight(DashboardWidgetSpec spec, DashboardDensity density) {
  final rows = math.max(1, spec.placement.rowSpan);
  return rows * density.rowHeight + (rows - 1) * density.gap;
}

/// The strip above Home's content: a way into customising, and while
/// customising, the ways to add to Home, start over and finish.
class HomeCustomizeBar extends StatelessWidget {
  const HomeCustomizeBar({
    super.key,
    required this.customizing,
    required this.onCustomize,
    required this.onDone,
    required this.onReset,
    required this.addEntries,
  });

  final bool customizing;
  final VoidCallback onCustomize;
  final VoidCallback onDone;
  final VoidCallback onReset;
  final List<AppMenuEntry> Function() addEntries;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    if (!customizing) {
      return Align(
        alignment: AlignmentDirectional.centerEnd,
        child: Tooltip(
          message: LocaleKeys.landing_customizeTooltip.tr(),
          child: TextButton.icon(
            key: const ValueKey('home-customize'),
            onPressed: onCustomize,
            style: WorkspaceChrome.controlStyle(context),
            icon: WorkspaceGlyph(
              Icons.dashboard_customize_rounded,
              size: 16,
              color: palette.secondaryText,
            ),
            label: Text(LocaleKeys.landing_customize.tr()),
          ),
        ),
      );
    }

    final hint = Row(
      children: [
        WorkspaceGlyph(
          Icons.dashboard_customize_rounded,
          color: palette.accent,
        ),
        const SizedBox(width: WorkspaceTokens.space2),
        Expanded(
          child: Text(
            LocaleKeys.landing_customizeHint.tr(),
            key: const ValueKey('home-customize-hint'),
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.metadata,
            ),
          ),
        ),
      ],
    );
    final actions = Wrap(
      spacing: WorkspaceTokens.space1,
      runSpacing: WorkspaceTokens.space1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        Builder(
          builder: (anchor) => TextButton.icon(
            key: const ValueKey('home-customize-add'),
            onPressed: () => showAppMenuForWidget<void>(
              context: anchor,
              entries: addEntries(),
            ),
            style: WorkspaceChrome.controlStyle(context),
            icon: const WorkspaceGlyph(Icons.add_rounded, size: 16),
            label: Text(LocaleKeys.landing_addToHome.tr()),
          ),
        ),
        TextButton.icon(
          key: const ValueKey('home-customize-reset'),
          onPressed: onReset,
          style: WorkspaceChrome.controlStyle(context),
          icon: const WorkspaceGlyph(Icons.restart_alt_rounded, size: 16),
          label: Text(LocaleKeys.landing_resetLayout.tr()),
        ),
        TextButton.icon(
          key: const ValueKey('home-customize-done'),
          onPressed: onDone,
          style: WorkspaceChrome.controlStyle(
            context,
            accent: palette.accent,
            selected: true,
          ),
          icon: WorkspaceGlyph(
            Icons.check_rounded,
            size: 16,
            color: palette.accent,
          ),
          label: Text(LocaleKeys.landing_customizeDone.tr()),
        ),
      ],
    );
    return WorkspaceSurface(
      key: const ValueKey('home-customize-bar'),
      kind: WorkspaceSurfaceKind.secondary,
      padding: const EdgeInsets.symmetric(
        horizontal: WorkspaceTokens.space3,
        vertical: WorkspaceTokens.space2,
      ),
      child: LayoutBuilder(
        builder: (context, constraints) =>
            constraints.maxWidth >= MediaQuery.textScalerOf(context).scale(640)
                ? Row(
                    children: [
                      Expanded(child: hint),
                      const SizedBox(width: WorkspaceTokens.space3),
                      actions,
                    ],
                  )
                : Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      hint,
                      const SizedBox(height: WorkspaceTokens.space2),
                      Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: actions,
                      ),
                    ],
                  ),
      ),
    );
  }
}

/// A small caption naming one of Home's columns while it is customised in a
/// window too narrow to show them side by side.
class HomeColumnCaption extends StatelessWidget {
  const HomeColumnCaption({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: WorkspaceTokens.space2),
        child: Semantics(
          header: true,
          child: Text(
            label,
            style: WorkspaceTypography.style(
              context,
              WorkspaceTextRole.caption,
            ),
          ),
        ),
      );
}

/// One block of Home while Home is being customised.
///
/// The whole block can be picked up and dropped on another block — above or
/// below it, whichever half it is dropped on — or at the end of a column.
/// Every move also has a button, so nothing needs a mouse. The block's own
/// content is shown as it is, but is not used while it is being arranged.
class HomeBlockFrame extends StatefulWidget {
  const HomeBlockFrame({
    super.key,
    required this.id,
    required this.label,
    required this.icon,
    required this.inSide,
    required this.child,
    required this.canAccept,
    required this.onDrop,
    required this.onMoveAcross,
    required this.onRemove,
    this.onMoveUp,
    this.onMoveDown,
    this.onConfigure,
    this.onResize,
    this.hidden = false,
  });

  final String id;
  final String label;
  final IconData icon;
  final bool hidden;

  /// Whether the block is in the side column, which decides where "move
  /// across" goes.
  final bool inSide;
  final Widget child;

  /// Whether a block being dragged may be dropped here.
  final bool Function(String dragged) canAccept;

  /// A block was dropped on this one: [before] says which half it landed on.
  final void Function(String dragged, bool before) onDrop;
  final VoidCallback? onMoveUp;
  final VoidCallback? onMoveDown;
  final VoidCallback onMoveAcross;
  final VoidCallback onRemove;
  final VoidCallback? onConfigure;

  /// For a widget: its height is dragged from the grip under it. Called with
  /// the vertical distance travelled since the grip was picked up, and with
  /// null when it is let go.
  final ValueChanged<double?>? onResize;

  @override
  State<HomeBlockFrame> createState() => _HomeBlockFrameState();
}

class _HomeBlockFrameState extends State<HomeBlockFrame> {
  /// Where a block hovering over this one would land; null when none is.
  bool? _dropBefore;
  double _resized = 0;

  void _track(DragTargetDetails<String> details) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final local = box.globalToLocal(details.offset);
    final before = local.dy < box.size.height / 2;
    if (before != _dropBefore) setState(() => _dropBefore = before);
  }

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final frame = _buildFrame(context, palette);
    final draggable = Draggable<String>(
      data: widget.id,
      dragAnchorStrategy: pointerDragAnchorStrategy,
      feedback: _HomeDragChip(label: widget.label, icon: widget.icon),
      childWhenDragging: Opacity(opacity: 0.35, child: frame),
      child: MouseRegion(cursor: SystemMouseCursors.grab, child: frame),
    );
    final target = DragTarget<String>(
      onWillAcceptWithDetails: (details) =>
          details.data != widget.id && widget.canAccept(details.data),
      onMove: _track,
      onLeave: (_) {
        if (_dropBefore != null) setState(() => _dropBefore = null);
      },
      onAcceptWithDetails: (details) {
        final before = _dropBefore ?? true;
        setState(() => _dropBefore = null);
        widget.onDrop(details.data, before);
      },
      builder: (context, candidates, _) {
        final before = candidates.isEmpty ? null : _dropBefore;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            draggable,
            if (before != null)
              PositionedDirectional(
                start: 0,
                end: 0,
                top: before ? -(WorkspaceTokens.space2 + 2) : null,
                bottom: before ? null : -(WorkspaceTokens.space2 + 2),
                child: _HomeInsertionLine(color: palette.accent),
              ),
          ],
        );
      },
    );
    final resize = widget.onResize;
    if (resize == null) return target;
    return Stack(
      children: [
        target,
        // Above the draggable, so picking up the grip never picks up the block.
        PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          height: 14,
          child: Tooltip(
            message: LocaleKeys.landing_resizeWidget.tr(),
            child: MouseRegion(
              cursor: SystemMouseCursors.resizeUpDown,
              child: GestureDetector(
                key: ValueKey('home-block-resize-${widget.id}'),
                behavior: HitTestBehavior.opaque,
                onVerticalDragStart: (_) => _resized = 0,
                onVerticalDragUpdate: (details) {
                  _resized += details.delta.dy;
                  resize(_resized);
                },
                onVerticalDragEnd: (_) => resize(null),
                onVerticalDragCancel: () => resize(null),
                child: Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: palette.accent.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildFrame(BuildContext context, WorkspacePalette palette) {
    Widget button({
      required String key,
      required IconData icon,
      required String tooltip,
      required VoidCallback? onPressed,
    }) =>
        IconButton(
          key: ValueKey('home-block-$key-${widget.id}'),
          tooltip: tooltip,
          onPressed: onPressed,
          iconSize: 16,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 28, height: 28),
          style: IconButton.styleFrom(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(7),
            ),
            hoverColor: WorkspaceChrome.hoverColor(context),
          ),
          icon: WorkspaceGlyph(
            icon,
            size: 16,
            color:
                onPressed == null ? palette.mutedText : palette.secondaryText,
          ),
        );

    // The side column is at the end of the row, and these arrows follow the
    // text direction, so "forward" always points at it.
    final towardsSide = !widget.inSide;
    final acrossIcon =
        towardsSide ? Icons.arrow_forward_rounded : Icons.arrow_back_rounded;
    final header = Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(4, 2, 2, 4),
      child: Row(
        children: [
          WorkspaceGlyph(
            Icons.drag_indicator_rounded,
            color: palette.mutedText,
          ),
          const SizedBox(width: 2),
          WorkspaceGlyph(widget.icon, size: 15, color: palette.accent),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              widget.label,
              key: ValueKey('home-block-label-${widget.id}'),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
                color: palette.primaryText,
              ).copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          if (widget.hidden)
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 4),
              child: Tooltip(
                message: LocaleKeys.landing_hiddenWidget.tr(),
                child: WorkspaceGlyph(
                  Icons.visibility_off_rounded,
                  size: 15,
                  color: palette.mutedText,
                ),
              ),
            ),
          button(
            key: 'up',
            icon: Icons.keyboard_arrow_up_rounded,
            tooltip: LocaleKeys.landing_moveUp.tr(),
            onPressed: widget.onMoveUp,
          ),
          button(
            key: 'down',
            icon: Icons.keyboard_arrow_down_rounded,
            tooltip: LocaleKeys.landing_moveDown.tr(),
            onPressed: widget.onMoveDown,
          ),
          button(
            key: 'across',
            icon: acrossIcon,
            tooltip: towardsSide
                ? LocaleKeys.landing_moveToSide.tr()
                : LocaleKeys.landing_moveToMain.tr(),
            onPressed: widget.onMoveAcross,
          ),
          if (widget.onConfigure != null)
            button(
              key: 'configure',
              icon: Icons.tune_rounded,
              tooltip: LocaleKeys.landing_configure.tr(),
              onPressed: widget.onConfigure,
            ),
          button(
            key: 'remove',
            icon: Icons.close_rounded,
            tooltip: LocaleKeys.landing_removeFromHome.tr(),
            onPressed: widget.onRemove,
          ),
        ],
      ),
    );
    return DecoratedBox(
      key: ValueKey('home-block-${widget.id}'),
      decoration: BoxDecoration(
        color: palette.hover.withValues(alpha: palette.hover.a * 0.55),
        borderRadius: BorderRadius.circular(WorkspaceTokens.cardRadius + 6),
        border: Border.all(
          color: palette.accent.withValues(alpha: palette.isDark ? 0.5 : 0.4),
          width: 1.2,
        ),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          6,
          2,
          6,
          widget.onResize == null ? 6 : 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            header,
            // Shown as it is, but not used while it is being arranged.
            ExcludeFocus(
              child: IgnorePointer(
                child: Opacity(
                  opacity: widget.hidden ? 0.45 : 1,
                  child: widget.child,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _HomeInsertionLine extends StatelessWidget {
  const _HomeInsertionLine({required this.color});

  final Color color;

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Container(
          height: 3,
          decoration: BoxDecoration(
            color: color,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      );
}

/// What follows the pointer while a block is being moved.
class _HomeDragChip extends StatelessWidget {
  const _HomeDragChip({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return Material(
      type: MaterialType.transparency,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 260),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: palette.elevatedSurface,
            borderRadius: BorderRadius.circular(WorkspaceTokens.controlRadius),
            border: Border.all(color: palette.accent, width: 1.2),
            boxShadow: palette.elevation(floating: true),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                WorkspaceGlyph(icon, size: 16, color: palette.accent),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: WorkspaceTypography.style(
                      context,
                      WorkspaceTextRole.metadata,
                      color: palette.primaryText,
                    ).copyWith(fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The end of a column while Home is being customised: a place to drop a
/// block, and the only one when the column is empty.
class HomeDropSlot extends StatelessWidget {
  const HomeDropSlot({
    super.key,
    required this.canAccept,
    required this.onAccept,
    this.empty = false,
  });

  final bool Function(String dragged) canAccept;
  final ValueChanged<String> onAccept;
  final bool empty;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => canAccept(details.data),
      onAcceptWithDetails: (details) => onAccept(details.data),
      builder: (context, candidates, _) {
        final active = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: WorkspaceTokens.motion(
            context,
            WorkspaceTokens.hoverDuration,
          ),
          height: empty ? 96 : (active ? 56 : 40),
          decoration: BoxDecoration(
            color: active
                ? palette.accent.withValues(alpha: palette.isDark ? 0.14 : 0.08)
                : palette.accent.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(WorkspaceTokens.cardRadius),
            border: Border.all(
              color: active
                  ? palette.accent
                  : palette.border.withValues(alpha: palette.border.a * 0.9),
            ),
          ),
          alignment: Alignment.center,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Text(
                empty
                    ? LocaleKeys.landing_dropEmpty.tr()
                    : LocaleKeys.landing_dropHere.tr(),
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.caption,
                  color: active ? palette.accent : palette.mutedText,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

/// A dashboard widget living on Home.
///
/// It is drawn from the same definition, with the same surface, title and
/// padding a dashboard card gives it, and it reads and writes through the
/// same controller — so a to-do list or a note works here exactly as it does
/// on a dashboard. Only a dashboard's grid, grips and hover controls are left
/// behind: on Home, a widget is arranged from the customise frame.
class HomeWidgetCard extends StatelessWidget {
  const HomeWidgetCard({
    super.key,
    required this.controller,
    required this.spec,
    required this.palette,
  });

  final DashboardController controller;
  final DashboardWidgetSpec spec;
  final DashboardPalette palette;

  @override
  Widget build(BuildContext context) {
    final definition = DashboardWidgetRegistry.definitionFor(spec.type);
    if (definition?.requiresScrollActivation != true) {
      return _buildCard(context, definition);
    }
    // An embedded list or table does not take the page's scrolling until it
    // is clicked, exactly as on a dashboard.
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ScrollActivationRegion(
        key: ValueKey('home-widget-scroll-activation-${spec.id}'),
        active: controller.selectedWidgetId == spec.id,
        onActiveChanged: (active) {
          if (active) {
            controller.select(spec.id);
          } else if (controller.selectedWidgetId == spec.id) {
            controller.select(null);
          }
        },
        child: Builder(builder: (context) => _buildCard(context, definition)),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context,
    DashboardWidgetDefinition? definition,
  ) {
    final widgetContext = DashboardWidgetContext(
      context: context,
      controller: controller,
      spec: spec,
      palette: palette,
    );
    final body = definition == null
        ? DashboardPlaceholder(
            palette: palette,
            icon: Icons.help_outline_rounded,
            message: LocaleKeys.dashboard_card_unknownWidget.tr(),
          )
        : definition.builder(widgetContext);
    final tone = palette.toneFor(spec.accent);
    final bare = definition?.paintsOwnSurface ?? false;
    final showsTitle = spec.showTitle && spec.title.isNotEmpty;
    final trailing = definition?.headerTrailing?.call(widgetContext);
    final showsHeader = showsTitle || trailing != null;
    final scale = spec.number(dashboardTextScaleKey, fallback: 1);
    final ambient = MediaQuery.textScalerOf(context);
    final headerHeight =
        (ambient.scale(13) * scale * 1.25 + (trailing == null ? 8 : 16)).clamp(
      trailing == null ? DashboardMetrics.headerHeight : 40.0,
      double.infinity,
    );

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (showsHeader)
          SizedBox(
            height: headerHeight,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 14, end: 10),
              child: Row(
                children: [
                  Expanded(
                    child: showsTitle
                        ? Text(
                            spec.title,
                            key: ValueKey('home-widget-title-${spec.id}'),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: DashboardType.cardTitle(
                              palette,
                              color: tone.inkSoft,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  if (trailing != null) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      flex: 2,
                      child: Align(
                        alignment: AlignmentDirectional.centerEnd,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(maxWidth: 240),
                          child: trailing,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        Expanded(
          child: Padding(
            padding: definition?.padding ??
                EdgeInsets.fromLTRB(
                  bare ? 0 : 14,
                  showsHeader ? 0 : (bare ? 0 : 12),
                  bare ? 0 : 14,
                  bare ? 0 : 12,
                ),
            child: body,
          ),
        ),
      ],
    );
    content = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        textScaler: scale == 1
            ? ambient
            : TextScaler.linear(scale * ambient.scale(100) / 100),
      ),
      child: content,
    );
    content = bare
        ? ClipRRect(
            borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
            child: content,
          )
        : DecoratedBox(
            decoration: BoxDecoration(
              color: tone.surface,
              borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
              boxShadow: palette.cardShadow(),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
              child: content,
            ),
          );
    return DashboardEditingScope(
      controller: controller,
      child: SizedBox(
        key: ValueKey('home-widget-${spec.id}'),
        height: homeWidgetHeight(spec, controller.document.settings.density),
        child: content,
      ),
    );
  }
}
