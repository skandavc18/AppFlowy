import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_card.dart'
    show dashboardTextScaleKey;
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:appflowy/plugins/dashboard/presentation/widgets/dashboard_widget_kit.dart';
import 'package:appflowy/shared/scrolling/scroll_activation_region.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_controller.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_widget_spec.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A dashboard widget drawn on its own, away from a dashboard's grid.
///
/// It is drawn from the same definition, with the same surface, title and
/// padding a dashboard card gives it, and it reads and writes through the
/// same controller — so a to-do list or a note works on Home, in a page or on
/// a canvas exactly as it does on a dashboard. Only a dashboard's grid, grips
/// and hover controls are left behind: whoever hosts the card arranges it.
///
/// It fills the space it is given unless [height] says otherwise.
class DashboardStandaloneCard extends StatelessWidget {
  const DashboardStandaloneCard({
    super.key,
    required this.controller,
    required this.spec,
    required this.palette,
    this.keyPrefix = 'dashboard-standalone',
    this.height,
  });

  final DashboardController controller;
  final DashboardWidgetSpec spec;
  final DashboardPalette palette;

  /// Keys inside the card start with this, so each host can be found apart.
  final String keyPrefix;

  final double? height;

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
        key: ValueKey('$keyPrefix-scroll-activation-${spec.id}'),
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
    // The same treatment the widget wears on a dashboard: a sheet, a wash of
    // colour, a gradient, or type set straight onto the page.
    final appearance = widgetContext.appearance;
    final tone = appearance.tone;
    final bare = appearance.media;
    final ink =
        appearance.onColour ? appearance.tone.label : palette.textSecondary;
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
                        ? Row(
                            children: [
                              if (definition != null) ...[
                                Icon(
                                  definition.icon,
                                  size: 14,
                                  color: appearance.onColour
                                      ? tone.label
                                      : tone.strong.withValues(alpha: 0.85),
                                ),
                                const SizedBox(width: 7),
                              ],
                              Flexible(
                                child: Text(
                                  spec.title,
                                  key: ValueKey('$keyPrefix-title-${spec.id}'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DashboardType.eyebrow(
                                    palette,
                                    color: ink,
                                  ),
                                ),
                              ),
                            ],
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
            decoration: palette.surfaceDecoration(appearance.surface, tone),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(DashboardMetrics.cardRadius),
              child: DecoratedBox(
                decoration: palette.sheenFor(appearance.surface),
                child: content,
              ),
            ),
          );
    return DashboardEditingScope(
      controller: controller,
      child: SizedBox(
        key: ValueKey('$keyPrefix-${spec.id}'),
        height: height,
        child: content,
      ),
    );
  }
}
