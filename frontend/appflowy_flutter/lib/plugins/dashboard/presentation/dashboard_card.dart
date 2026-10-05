import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_embed_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_find.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_document.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

/// Which edge of a card is being dragged.
enum DashboardResizeEdge { right, bottom, corner }

/// What a grip draws so it can be found.
enum _GripMarker { vertical, horizontal, corner }

/// The chrome around one widget: the surface, the title, the hover controls
/// and the grips.
///
/// Everything a widget shares with every other widget lives here, so a widget
/// itself is only its content.
class DashboardCard extends StatefulWidget {
  const DashboardCard({
    super.key,
    required this.controller,
    required this.spec,
    required this.palette,
    required this.selected,
    required this.dragging,
    this.onDragStart,
    this.onDragUpdate,
    this.onDragEnd,
    this.onResizeStart,
    this.onResizeUpdate,
    this.onResizeEnd,
  });

  final DashboardController controller;
  final DashboardWidgetSpec spec;
  final DashboardPalette palette;
  final bool selected;
  final bool dragging;

  final VoidCallback? onDragStart;
  final void Function(Offset delta, Offset globalPosition)? onDragUpdate;
  final VoidCallback? onDragEnd;

  final void Function(DashboardResizeEdge edge)? onResizeStart;
  final void Function(DashboardResizeEdge edge, Offset delta)? onResizeUpdate;
  final VoidCallback? onResizeEnd;

  @override
  State<DashboardCard> createState() => _DashboardCardState();
}

class _DashboardCardState extends State<DashboardCard> {
  bool _hovered = false;

  /// How far the pointer has travelled since it went down, and whether that
  /// was far enough to count as moving the card rather than clicking it.
  Offset _travel = Offset.zero;
  bool _moving = false;

  /// Double clicks are timed by hand. A `DoubleTapGestureRecognizer` in the
  /// same arena holds the single tap back for 300ms, which is exactly what
  /// "clicking a widget does nothing" feels like.
  DateTime? _lastTap;

  DashboardController get controller => widget.controller;

  DashboardWidgetSpec get spec => widget.spec;

  DashboardPalette get palette => widget.palette;

  bool get _editable => controller.isEditable;

  Duration get _motion => controller.document.settings.reduceMotion
      ? Duration.zero
      : WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration);

  @override
  Widget build(BuildContext context) {
    final definition = DashboardWidgetRegistry.definitionFor(spec.type);
    if (!(definition?.requiresScrollActivation ?? false)) {
      return _buildCard(context);
    }
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) => ScrollActivationRegion(
        key: ValueKey('dashboard-scroll-activation-${spec.id}'),
        active: controller.selectedWidgetId == spec.id,
        onActiveChanged: _selectForScrolling,
        // Invoke builders below the gate. Some embed builders capture this
        // context's ScrollConfiguration before constructing their descendants.
        child: Builder(builder: _buildCard),
      ),
    );
  }

  void _selectForScrolling(bool active) {
    if (!mounted) return;
    if (active) {
      if (controller.document.widgetById(spec.id) != null) {
        controller.select(spec.id);
      }
    } else if (controller.selectedWidgetId == spec.id) {
      // A losing card must never clear the card selected by the same click.
      controller.select(null);
    }
  }

  Widget _buildCard(BuildContext context) {
    final definition = DashboardWidgetRegistry.definitionFor(spec.type);
    final selected = definition?.requiresScrollActivation == true
        ? controller.selectedWidgetId == spec.id
        : widget.selected;
    final appearance = dashboardAppearanceOf(spec, palette);
    final tone = appearance.tone;
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

    final bare = appearance.media;
    final showsTitle = spec.showTitle && spec.title.isNotEmpty;
    final trailing = definition?.headerTrailing?.call(widgetContext);
    // Only a widget with its own navigation along its top edge gives its
    // management controls a row of their own. Everything else keeps a clean
    // top and shows them floating over the corner while it is hovered — a
    // dashboard at rest should never look like it is being edited.
    final reserves = definition?.reservesHeader ?? false;
    final showsHeader =
        showsTitle || trailing != null || (_editable && reserves);
    final floatingControls = _editable && !showsHeader;
    final scale = spec.number(dashboardTextScaleKey, fallback: 1);
    final headerHeight = showsTitle || trailing != null
        ? (MediaQuery.textScalerOf(context).scale(13) * scale * 1.25 +
                (trailing == null ? 8 : 16))
            .clamp(
            trailing == null ? DashboardMetrics.headerHeight : 40.0,
            double.infinity,
          )
        : DashboardMetrics.headerHeight;
    final inset = bare ? 0.0 : 16.0;

    Widget content = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // The header slot stays mounted across access and title changes, at
        // zero height when unused. Hover and focus only reveal controls;
        // they never move or reparent the body.
        _buildTitle(
          appearance,
          definition,
          showsTitle: showsTitle,
          height: showsHeader ? headerHeight : 0,
          selected: selected,
          trailing: trailing,
          controls: _editable && showsHeader,
        ),
        if (!spec.collapsed || dashboardFindRevealsWidget(context, spec.id))
          Expanded(
            key: ValueKey('dashboard-card-body-${spec.id}'),
            child: Padding(
              padding: definition?.padding ??
                  EdgeInsets.fromLTRB(
                    inset,
                    showsHeader ? (bare ? 0 : 2) : (bare ? 0 : 14),
                    inset,
                    bare ? 0 : 14,
                  ),
              child: DashboardFindEmbed.supports(spec)
                  ? DashboardFindEmbed(
                      dashboard: controller,
                      spec: spec,
                      child: body,
                    )
                  : body,
            ),
          ),
      ],
    );

    // One setting sizes everything the widget says, whatever it is made of:
    // a note, a reminder list and a callout all answer to it.
    final ambient = MediaQuery.textScalerOf(context);
    content = MediaQuery(
      data: MediaQuery.of(context).copyWith(
        // Keep the wrapper even at the default size: changing a setting must
        // not replace the field/renderer underneath it.
        textScaler: scale == 1
            ? ambient
            : TextScaler.linear(scale * ambient.scale(100) / 100),
      ),
      child: content,
    );

    if (!bare) {
      content = AnimatedContainer(
        duration: _motion,
        curve: DashboardMetrics.curve,
        decoration: palette.surfaceDecoration(
          appearance.surface,
          tone,
          hovered: _hovered,
          dragging: widget.dragging,
        ),
        foregroundDecoration: palette.selectionRing(
          selected: selected,
          radius: DashboardMetrics.cardRadius,
        ),
        clipBehavior: Clip.antiAlias,
        // Always present, so choosing another surface never rebuilds the
        // content underneath it.
        child: DecoratedBox(
          decoration: palette.sheenFor(appearance.surface),
          child: content,
        ),
      );
    } else {
      content = ClipRRect(
        borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
        child: content,
      );
    }

    // The floating controls are a slot of their own, inside the gesture
    // detectors so their handle can carry the card.
    content = Stack(
      children: [
        Positioned.fill(child: content),
        if (floatingControls)
          PositionedDirectional(
            top: 8,
            start: (definition?.controlsAtStart ?? false) ? 8 : null,
            end: (definition?.controlsAtStart ?? false)
                ? null
                : DashboardMetrics.resizeHandle + 4,
            child: _buildManagementControls(selected: selected, floating: true),
          ),
      ],
    );

    Widget card = GestureDetector(
      behavior: HitTestBehavior.translucent,
      // A control inside the card is deeper in the tree, so it wins the arena
      // and these only fire on the card's own surface. That is what lets the
      // whole card be grabbed without the widget inside it losing its taps.
      onTap: _editable ? _handleTap : null,
      onSecondaryTapDown:
          _editable ? (details) => _showMenuAt(details.globalPosition) : null,
      child: content,
    );

    // Access changes remove recognizers and editing chrome, never ancestors
    // of the body. Removing these wrappers disposed unsaved text fields.
    card = RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: {
        if (_editable)
          _CardPanRecognizer:
              GestureRecognizerFactoryWithHandlers<_CardPanRecognizer>(
            _CardPanRecognizer.new,
            (recognizer) {
              recognizer.onStart = (_) {
                _panStart();
              };
              recognizer.onUpdate = (details) {
                _panUpdate(details.delta, details.globalPosition);
              };
              recognizer.onEnd = (_) {
                _panEnd();
              };
              // Cancelled means the pan never won: the tap recogniser did,
              // and it is already reporting the click.
              recognizer.onCancel = _panStart;
            },
          ),
      },
      child: card,
    );

    card = Stack(
      children: [
        Positioned.fill(child: card),
        if (_editable && !widget.dragging) ..._buildGrips(selected: selected),
      ],
    );
    card = DashboardEditingScope(controller: controller, child: card);

    return PreviewToolbarRegion(
      child: MouseRegion(
        // The header and body share one hover boundary, so moving onto a
        // management control does not make it flicker away.
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        // The hand only appears once a widget has been picked up (or on its
        // handle): an ordinary hover is for reading, not for rearranging.
        cursor: _editable && (selected || widget.dragging)
            ? (widget.dragging
                ? SystemMouseCursors.grabbing
                : SystemMouseCursors.grab)
            : MouseCursor.defer,
        child: AnimatedScale(
          duration: _motion,
          curve: DashboardMetrics.curve,
          scale: widget.dragging && _motion != Duration.zero ? 1.015 : 1,
          child: AnimatedOpacity(
            duration: _motion,
            opacity: spec.hidden ? 0.45 : 1,
            child: card,
          ),
        ),
      ),
    );
  }

  Widget _buildTitle(
    DashboardAppearance appearance,
    DashboardWidgetDefinition? definition, {
    required bool showsTitle,
    required double height,
    required bool selected,
    required bool controls,
    Widget? trailing,
  }) {
    // On a wash of colour the label is written in that colour's own ink; on
    // a neutral sheet it stays a quiet grey.
    final ink =
        appearance.onColour ? appearance.tone.label : palette.textSecondary;
    return SizedBox(
      key: ValueKey('dashboard-card-header-${spec.id}'),
      height: height,
      child: Padding(
        // Both widget and management controls participate in the Row. The
        // last target also stays clear of the overlaid right resize grip.
        padding: EdgeInsets.only(
          left: appearance.media ? 12 : 16,
          right: DashboardMetrics.resizeHandle + 4,
        ),
        child: LayoutBuilder(
          builder: (context, constraints) {
            // The widget's own controls take what they need, up to the
            // two-thirds of the row they have always been allowed, and the
            // title has the rest — a lone "+" no longer squeezes it.
            final managementWidth = controls ? 8.0 + 2 * 24 + 4 : 0.0;
            final shared = math.max(
              0.0,
              constraints.maxWidth - managementWidth - 8,
            );
            final trailingLimit = math.min(240.0, shared * 2 / 3);
            return Row(
              children: [
                Expanded(
                  child: showsTitle
                      ? GestureDetector(
                          behavior: HitTestBehavior.translucent,
                          onDoubleTap: _editable ? _rename : null,
                          child: SingleChildScrollView(
                            scrollDirection: Axis.horizontal,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                // A header that also carries the widget's
                                // own controls has no room to spare: the
                                // words win.
                                if (definition != null && trailing == null) ...[
                                  Icon(
                                    definition.icon,
                                    size: 14,
                                    color: appearance.onColour
                                        ? appearance.tone.label
                                        : appearance.tone.strong
                                            .withValues(alpha: 0.85),
                                  ),
                                  const SizedBox(width: 7),
                                ],
                                SurfaceFindTarget(
                                  id: dashboardFindWidget(spec.id, 'title'),
                                  child: Text(
                                    spec.title,
                                    maxLines: 1,
                                    style: DashboardType.eyebrow(
                                      palette,
                                      color: ink,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: trailingLimit),
                    child: trailing,
                  ),
                ],
                if (controls) ...[
                  const SizedBox(width: 8),
                  _buildManagementControls(selected: selected, floating: false),
                ],
              ],
            );
          },
        ),
      ),
    );
  }

  /// Configure and More — revealed on hover, focus or selection.
  ///
  /// Floating over a widget they sit on a small frosted pill with a handle,
  /// so they read against any content and the card can be carried by them.
  Widget _buildManagementControls({
    required bool selected,
    required bool floating,
  }) {
    final buttons = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (floating)
          Tooltip(
            message: LocaleKeys.dashboard_card_drag.tr(),
            child: MouseRegion(
              cursor: SystemMouseCursors.grab,
              child: SizedBox(
                key: ValueKey('dashboard-card-handle-${spec.id}'),
                width: 18,
                height: 24,
                child: WorkspaceGlyph(
                  Icons.drag_indicator_rounded,
                  size: 14,
                  color: palette.textMuted,
                ),
              ),
            ),
          ),
        DashboardIconButton(
          icon: Icons.tune_rounded,
          palette: palette,
          size: 24,
          iconSize: 15,
          tooltip: LocaleKeys.dashboard_card_configure.tr(),
          onPressed: () => controller.configure(spec.id),
        ),
        SizedBox(width: floating ? 2 : 4),
        Builder(
          builder: (anchor) => DashboardIconButton(
            icon: Icons.more_horiz_rounded,
            palette: palette,
            size: 24,
            tooltip: LocaleKeys.dashboard_card_more.tr(),
            onPressed: () => _showMenuForCard(anchor),
          ),
        ),
      ],
    );
    return PreviewToolbar(
      key: ValueKey('dashboard-card-management-${spec.id}'),
      keepVisible: selected,
      child: floating
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: palette.raised.withValues(
                  alpha: palette.isDark ? 0.94 : 0.96,
                ),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: palette.shadowColor.withValues(
                      alpha: palette.isDark ? 0.4 : 0.14,
                    ),
                    blurRadius: 10,
                    spreadRadius: -2,
                    offset: const Offset(0, 2),
                  ),
                  if (palette.isDark)
                    BoxShadow(
                      color: Colors.white.withValues(alpha: 0.06),
                      spreadRadius: 0.5,
                    ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: buttons,
              ),
            )
          : buttons,
    );
  }

  /// The grips sit just INSIDE the card. A grip hanging off the edge is
  /// outside the stack's own box and can never be hit, which is what made
  /// resizing feel broken.
  ///
  /// They are always there to be found by the pointer — the cursor changes
  /// as soon as it reaches an edge — but their marks only show on the edge
  /// being pointed at, or around a widget that has been picked up.
  List<Widget> _buildGrips({required bool selected}) => [
        Positioned(
          top: DashboardMetrics.cardRadius,
          right: 0,
          bottom: DashboardMetrics.cornerHandle,
          width: DashboardMetrics.resizeHandle,
          child: _buildGrip(
            DashboardResizeEdge.right,
            SystemMouseCursors.resizeLeftRight,
            marker: _GripMarker.vertical,
            selected: selected,
          ),
        ),
        Positioned(
          left: DashboardMetrics.cardRadius,
          right: DashboardMetrics.cornerHandle,
          bottom: 0,
          height: DashboardMetrics.resizeHandle,
          child: _buildGrip(
            DashboardResizeEdge.bottom,
            SystemMouseCursors.resizeUpDown,
            marker: _GripMarker.horizontal,
            selected: selected,
          ),
        ),
        Positioned(
          right: 0,
          bottom: 0,
          width: DashboardMetrics.cornerHandle,
          height: DashboardMetrics.cornerHandle,
          child: _buildGrip(
            DashboardResizeEdge.corner,
            SystemMouseCursors.resizeDownRight,
            marker: _GripMarker.corner,
            selected: selected,
          ),
        ),
      ];

  Widget _buildGrip(
    DashboardResizeEdge edge,
    MouseCursor cursor, {
    required _GripMarker marker,
    required bool selected,
  }) =>
      _ResizeGrip(
        cursor: cursor,
        visible: selected || (_hovered && marker == _GripMarker.corner),
        motion: _motion,
        onStart: () {
          if (_editable) widget.onResizeStart?.call(edge);
        },
        onUpdate: (delta) {
          if (_editable) widget.onResizeUpdate?.call(edge, delta);
        },
        onEnd: () {
          if (_editable) widget.onResizeEnd?.call();
        },
        builder: (active) => _buildMarker(marker, active: active),
      );

  /// A handle nobody can see is a handle nobody uses — each edge shows the
  /// grab bar it answers to once the pointer is near it.
  Widget _buildMarker(_GripMarker marker, {required bool active}) {
    final ink = active
        ? palette.accent.withValues(alpha: 0.85)
        : palette.textMuted.withValues(alpha: 0.6);
    return switch (marker) {
      _GripMarker.vertical => Container(
          width: 3,
          height: 26,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      _GripMarker.horizontal => Container(
          width: 26,
          height: 3,
          decoration: BoxDecoration(
            color: ink,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      _GripMarker.corner => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(
            border: Border(
              right: BorderSide(color: ink, width: 2),
              bottom: BorderSide(color: ink, width: 2),
            ),
            borderRadius: const BorderRadius.only(
              bottomRight: Radius.circular(5),
            ),
          ),
        ),
    };
  }

  /// A click picks the widget up; a second one within the double-click window
  /// opens its settings. Opening them on every click would narrow the canvas
  /// under the pointer, which is what made a card impossible to move.
  void _handleTap() {
    if (!_editable) return;
    final now = DateTime.now();
    final again =
        _lastTap != null && now.difference(_lastTap!) < kDoubleTapTimeout;
    _lastTap = now;
    if (again) {
      controller.configure(spec.id);
    } else {
      controller.select(spec.id);
    }
  }

  void _panStart() {
    _travel = Offset.zero;
    _moving = false;
  }

  /// The card wins the arena as soon as the pointer moves at all, so the page
  /// cannot scroll away with the gesture — but it does not actually move
  /// until the pointer has gone somewhere, so a click that wobbles is still a
  /// click.
  void _panUpdate(Offset delta, Offset globalPosition) {
    if (!_editable) return;
    _travel += delta;
    if (_moving) {
      widget.onDragUpdate?.call(delta, globalPosition);
      return;
    }
    if (_travel.distance < _dragThreshold) {
      return;
    }
    _moving = true;
    widget.onDragStart?.call();
    widget.onDragUpdate?.call(_travel, globalPosition);
  }

  void _panEnd() {
    if (!_editable) {
      _panStart();
      return;
    }
    if (!_moving) {
      // The pointer wandered a pixel or two before it was let go. That was
      // somebody clicking, not somebody moving the card.
      _handleTap();
      return;
    }
    _moving = false;
    widget.onDragEnd?.call();
  }

  void _showMenuAt(Offset position) {
    if (!_editable) {
      return;
    }
    showAppMenu<void>(
      context: context,
      entries: _menuEntries(),
      globalPosition: position,
    );
  }

  void _showMenuForCard(BuildContext anchor) {
    if (!_editable) {
      return;
    }
    showAppMenuForWidget<void>(context: anchor, entries: _menuEntries());
  }

  List<AppMenuEntry> _menuEntries() {
    final document = controller.document;
    final section = document.sectionOf(spec.id);
    return [
      AppMenuItem(
        label: LocaleKeys.dashboard_card_rename.tr(),
        icon: Icons.edit_rounded,
        onSelected: _rename,
      ),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_configure.tr(),
        icon: Icons.tune_rounded,
        onSelected: () => controller.configure(spec.id),
      ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_width.tr(),
        icon: Icons.width_normal_rounded,
        submenu: [
          for (final entry in _widthChoices)
            AppMenuItem(
              label: entry.$1(),
              selected: spec.placement.columnSpan == entry.$2,
              onSelected: () => _resizeTo(columnSpan: entry.$2),
            ),
        ],
      ),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_height.tr(),
        icon: Icons.height_rounded,
        submenu: [
          for (final entry in _heightChoices)
            AppMenuItem(
              label: entry.$1(),
              selected: spec.placement.rowSpan == entry.$2,
              onSelected: () => _resizeTo(rowSpan: entry.$2),
            ),
        ],
      ),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_colour.tr(),
        icon: Icons.palette_rounded,
        submenu: [
          for (final accent in DashboardAccent.values)
            AppMenuItem(
              label: dashboardAccentLabel(accent),
              selected: spec.accent == accent,
              iconWidget: _swatch(accent),
              onSelected: () => controller.edit(
                (document) =>
                    document.withWidget(spec.copyWith(accent: accent)),
              ),
            ),
        ],
      ),
      if (!(DashboardWidgetRegistry.definitionFor(spec.type)
              ?.paintsOwnSurface ??
          false))
        AppMenuItem(
          label: LocaleKeys.dashboard_card_style.tr(),
          icon: Icons.layers_rounded,
          submenu: [
            for (final surface in DashboardSurface.values)
              AppMenuItem(
                label: dashboardSurfaceLabel(surface),
                selected: dashboardChosenSurface(spec) == surface,
                icon: dashboardSurfaceIcon(surface),
                onSelected: () => controller.edit(
                  (document) => document.withWidget(
                    spec.withSettings({
                      dashboardSurfaceKey: surface == DashboardSurface.automatic
                          ? null
                          : surface.name,
                    }),
                  ),
                ),
              ),
          ],
        ),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_textSize.tr(),
        icon: Icons.format_size_rounded,
        submenu: [
          for (final entry in _textSizeChoices)
            AppMenuItem(
              label: entry.$1(),
              selected:
                  (spec.number(dashboardTextScaleKey, fallback: 1) - entry.$2)
                          .abs() <
                      0.01,
              onSelected: () => controller.edit(
                (document) => document.withWidget(
                  spec.withSettings({dashboardTextScaleKey: entry.$2}),
                ),
              ),
            ),
        ],
      ),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_showTitle.tr(),
        icon: Icons.title_rounded,
        selected: spec.showTitle,
        onSelected: () => controller.edit(
          (document) =>
              document.withWidget(spec.copyWith(showTitle: !spec.showTitle)),
        ),
      ),
      if (document.sections.length > 1)
        AppMenuItem(
          label: LocaleKeys.dashboard_card_moveTo.tr(),
          icon: Icons.drive_file_move_rounded,
          submenu: [
            for (final target in document.sections)
              AppMenuItem(
                label: target.title.isEmpty
                    ? LocaleKeys.dashboard_section_untitled.tr()
                    : target.title,
                enabled: target.id != section?.id,
                onSelected: () => controller.edit(
                  (document) => document.moveWidget(spec.id, target.id),
                ),
              ),
          ],
        ),
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_openLarge.tr(),
        icon: Icons.open_in_full_rounded,
        onSelected: () => controller.openModal(spec.id),
      ),
      AppMenuItem(
        label: LocaleKeys.button_duplicate.tr(),
        icon: Icons.copy_rounded,
        onSelected: _duplicate,
      ),
      AppMenuItem(
        label: LocaleKeys.dashboard_card_hide.tr(),
        icon: spec.hidden
            ? Icons.visibility_rounded
            : Icons.visibility_off_rounded,
        selected: spec.hidden,
        onSelected: () => controller.edit(
          (document) =>
              document.withWidget(spec.copyWith(hidden: !spec.hidden)),
        ),
      ),
      AppMenuItem(
        label: LocaleKeys.button_delete.tr(),
        icon: Icons.delete_outline_rounded,
        destructive: true,
        onSelected: () {
          controller.select(null);
          controller.edit((document) => document.withoutWidget(spec.id));
        },
      ),
    ];
  }

  Widget _swatch(DashboardAccent accent) => Container(
        width: 13,
        height: 13,
        decoration: BoxDecoration(
          color: palette.strongFor(accent),
          shape: BoxShape.circle,
        ),
      );

  void _resizeTo({int? columnSpan, int? rowSpan}) => controller.edit(
        (document) => document.withWidget(
          spec.copyWith(
            placement: spec.placement.copyWith(
              columnSpan: columnSpan,
              rowSpan: rowSpan,
            ),
          ),
        ),
      );

  void _duplicate() => controller.edit((document) {
        final section = document.sectionOf(spec.id);
        final copy = spec.copyWith(
          id: newDashboardId('w'),
          placement: spec.placement.copyWith(row: spec.placement.endRow),
        );
        return document.addWidget(copy, sectionId: section?.id ?? '');
      });

  Future<void> _rename() async {
    if (!_editable) return;
    final controllerText = TextEditingController(text: spec.title);
    final route = DialogRoute<String>(
      context: context,
      builder: (dialogContext) => _RenameDialog(
        palette: palette,
        controller: controllerText,
        title: LocaleKeys.dashboard_card_rename.tr(),
      ),
    );
    final name = await Navigator.of(context, rootNavigator: true).push(route);
    // Popping resolves the result before the reverse animation detaches the
    // TextField. Its controller must live until the route is really gone.
    await route.completed;
    controllerText.dispose();
    if (!mounted || name == null || !_editable) {
      return;
    }
    controller.edit(
      (document) => document.withWidget(
        spec.copyWith(title: name.trim(), showTitle: true),
      ),
    );
  }

  static final List<(String Function(), int)> _widthChoices = [
    (() => LocaleKeys.dashboard_size_quarter.tr(), 3),
    (() => LocaleKeys.dashboard_size_third.tr(), 4),
    (() => LocaleKeys.dashboard_size_half.tr(), 6),
    (() => LocaleKeys.dashboard_size_twoThirds.tr(), 8),
    (() => LocaleKeys.dashboard_size_full.tr(), 12),
  ];

  static final List<(String Function(), int)> _heightChoices = [
    (() => LocaleKeys.dashboard_size_short.tr(), 2),
    (() => LocaleKeys.dashboard_size_medium.tr(), 4),
    (() => LocaleKeys.dashboard_size_tall.tr(), 7),
    (() => LocaleKeys.dashboard_size_veryTall.tr(), 11),
  ];

  static final List<(String Function(), double)> _textSizeChoices = [
    (() => LocaleKeys.dashboard_textSize_smaller.tr(), 0.85),
    (() => LocaleKeys.dashboard_textSize_normal.tr(), 1.0),
    (() => LocaleKeys.dashboard_textSize_larger.tr(), 1.2),
    (() => LocaleKeys.dashboard_textSize_largest.tr(), 1.45),
  ];
}

/// How much bigger than usual this widget's words are.
const dashboardTextScaleKey = 'text_scale';

/// The words for one of the widget colours.
String dashboardAccentLabel(DashboardAccent accent) => switch (accent) {
      DashboardAccent.neutral => LocaleKeys.dashboard_accent_neutral.tr(),
      DashboardAccent.paper => LocaleKeys.dashboard_accent_paper.tr(),
      DashboardAccent.blue => LocaleKeys.dashboard_accent_blue.tr(),
      DashboardAccent.green => LocaleKeys.dashboard_accent_green.tr(),
      DashboardAccent.amber => LocaleKeys.dashboard_accent_amber.tr(),
      DashboardAccent.orange => LocaleKeys.dashboard_accent_orange.tr(),
      DashboardAccent.red => LocaleKeys.dashboard_accent_red.tr(),
      DashboardAccent.pink => LocaleKeys.dashboard_accent_pink.tr(),
      DashboardAccent.purple => LocaleKeys.dashboard_accent_purple.tr(),
      DashboardAccent.teal => LocaleKeys.dashboard_accent_teal.tr(),
    };

/// The words for one of the ways a widget can meet the page.
String dashboardSurfaceLabel(DashboardSurface surface) => switch (surface) {
      DashboardSurface.automatic => LocaleKeys.dashboard_surface_automatic.tr(),
      DashboardSurface.floating => LocaleKeys.dashboard_surface_floating.tr(),
      DashboardSurface.tinted => LocaleKeys.dashboard_surface_tinted.tr(),
      DashboardSurface.gradient => LocaleKeys.dashboard_surface_gradient.tr(),
      DashboardSurface.plain => LocaleKeys.dashboard_surface_plain.tr(),
    };

IconData dashboardSurfaceIcon(DashboardSurface surface) => switch (surface) {
      DashboardSurface.automatic => Icons.auto_awesome_rounded,
      DashboardSurface.floating => Icons.layers_rounded,
      DashboardSurface.tinted => Icons.format_color_fill_rounded,
      DashboardSurface.gradient => Icons.gradient_rounded,
      DashboardSurface.plain => Icons.text_fields_rounded,
    };

/// How far the pointer has to go before a press becomes a move.
const double _dragThreshold = 4;

/// A card is at least as eager to be moved as the page under it is to scroll.
///
/// A plain pan needs twice the distance a scroll view does, so the page took
/// every vertical drag and a card could only ever be shoved sideways. Sharing
/// the scroll view's threshold means the deeper recogniser — the card — gets
/// there first and keeps the gesture.
class _CardPanRecognizer extends PanGestureRecognizer {
  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      globalDistanceMoved.abs() >
      computeHitSlop(pointerDeviceKind, gestureSettings);

  /// A trackpad's two fingers are how a page is scrolled, not how a card is
  /// picked up. Declining pan-zoom leaves the gesture to the scroll view.
  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}

/// A pan that cannot be taken away by the page scrolling underneath it.
///
/// A card sits inside a scroll view, and a plain drag recogniser loses the
/// arena to it — the card can be pressed but never moved. Accepting on
/// rejection keeps the gesture where it was aimed.
class _EagerPan extends StatelessWidget {
  const _EagerPan({
    required this.child,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
  });

  final Widget child;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;

  @override
  Widget build(BuildContext context) => RawGestureDetector(
        behavior: HitTestBehavior.opaque,
        gestures: {
          _EagerPanRecognizer:
              GestureRecognizerFactoryWithHandlers<_EagerPanRecognizer>(
            _EagerPanRecognizer.new,
            (recognizer) {
              recognizer.onStart = (_) {
                onStart();
              };
              recognizer.onUpdate = (details) {
                onUpdate(details.delta);
              };
              recognizer.onEnd = (_) {
                onEnd();
              };

              recognizer.onCancel = () {
                onEnd();
              };
            },
          ),
        },
        child: child,
      );
}

class _EagerPanRecognizer extends PanGestureRecognizer {
  @override
  void rejectGesture(int pointer) => acceptGesture(pointer);

  // A two-finger scroll over a grip is still scrolling, not mouse resizing.
  @override
  void addAllowedPointerPanZoom(PointerPanZoomStartEvent event) {}
}

/// One edge a card is resized by.
///
/// Its mark appears on its own when the pointer reaches it (or while it is
/// held), so a dashboard at rest is not fringed with handles.
class _ResizeGrip extends StatefulWidget {
  const _ResizeGrip({
    required this.cursor,
    required this.visible,
    required this.motion,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.builder,
  });

  final MouseCursor cursor;

  /// Shown regardless of the pointer: the card was picked up.
  final bool visible;
  final Duration motion;
  final VoidCallback onStart;
  final ValueChanged<Offset> onUpdate;
  final VoidCallback onEnd;
  final Widget Function(bool active) builder;

  @override
  State<_ResizeGrip> createState() => _ResizeGripState();
}

class _ResizeGripState extends State<_ResizeGrip> {
  bool _hovered = false;
  bool _held = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _held;
    return MouseRegion(
      cursor: widget.cursor,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: _EagerPan(
        onStart: () {
          setState(() => _held = true);
          widget.onStart();
        },
        onUpdate: widget.onUpdate,
        onEnd: () {
          if (mounted) {
            setState(() => _held = false);
          }
          widget.onEnd();
        },
        child: AnimatedOpacity(
          duration: widget.motion,
          opacity: widget.visible || active ? 1 : 0,
          child: Center(child: widget.builder(active)),
        ),
      ),
    );
  }
}

class _RenameDialog extends StatelessWidget {
  const _RenameDialog({
    required this.palette,
    required this.controller,
    required this.title,
  });

  final DashboardPalette palette;
  final TextEditingController controller;
  final String title;

  @override
  Widget build(BuildContext context) => AlertDialog(
        backgroundColor: palette.raised,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
        ),
        title: Text(title, style: DashboardType.title(palette, size: 17)),
        content: SizedBox(
          width: 320,
          child: TextField(
            controller: controller,
            autofocus: true,
            style: DashboardType.body(palette),
            decoration: InputDecoration(
              filled: true,
              fillColor: palette.sunken,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
            ),
            onSubmitted: (value) => Navigator.of(context).pop(value),
          ),
        ),
        actions: [
          DashboardButton(
            label: LocaleKeys.button_cancel.tr(),
            palette: palette,
            onPressed: () => Navigator.of(context).pop(),
          ),
          DashboardButton(
            label: LocaleKeys.button_save.tr(),
            palette: palette,
            primary: true,
            onPressed: () => Navigator.of(context).pop(controller.text),
          ),
        ],
      );
}
