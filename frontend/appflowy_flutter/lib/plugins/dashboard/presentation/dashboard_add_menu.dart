import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_style.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_widget_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The words for one of the groups the "Add" panel is arranged in.
String dashboardGroupLabel(DashboardWidgetGroup group) => switch (group) {
      DashboardWidgetGroup.text => LocaleKeys.dashboard_group_text.tr(),
      DashboardWidgetGroup.content => LocaleKeys.dashboard_group_content.tr(),
      DashboardWidgetGroup.collections =>
        LocaleKeys.dashboard_group_collections.tr(),
      DashboardWidgetGroup.data => LocaleKeys.dashboard_group_data.tr(),
      DashboardWidgetGroup.time => LocaleKeys.dashboard_group_time.tr(),
      DashboardWidgetGroup.controls => LocaleKeys.dashboard_group_controls.tr(),
      DashboardWidgetGroup.info => LocaleKeys.dashboard_group_info.tr(),
    };

/// Choose something to put on the dashboard.
///
/// A searchable panel rather than a nested menu: there are thirty widgets and
/// growing, and the fastest way to the one somebody wants is to type its name.
Future<DashboardWidgetDefinition?> showDashboardWidgetPicker({
  required BuildContext context,
  required DashboardPalette palette,
}) =>
    showDialog<DashboardWidgetDefinition>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: palette.isDark ? 0.5 : 0.22),
      builder: (_) => _DashboardWidgetPicker(palette: palette),
    );

class _DashboardWidgetPicker extends StatefulWidget {
  const _DashboardWidgetPicker({required this.palette});

  final DashboardPalette palette;

  @override
  State<_DashboardWidgetPicker> createState() => _DashboardWidgetPickerState();
}

class _DashboardWidgetPickerState extends State<_DashboardWidgetPicker> {
  final TextEditingController _query = TextEditingController();
  final FocusNode _focus = FocusNode();
  DashboardWidgetGroup? _group;
  int _highlighted = 0;

  @override
  void dispose() {
    _query.dispose();
    _focus.dispose();
    super.dispose();
  }

  List<DashboardWidgetDefinition> get _results {
    final text = _query.text.trim();
    if (text.isNotEmpty) {
      return DashboardWidgetRegistry.search(text);
    }
    final group = _group;
    return group == null
        ? DashboardWidgetRegistry.all()
        : DashboardWidgetRegistry.inGroup(group);
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final results = _results;

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.all(40),
      child: Container(
        width: 660,
        constraints: const BoxConstraints(maxHeight: 560),
        decoration: BoxDecoration(
          color: palette.raised,
          borderRadius: BorderRadius.circular(20),
          boxShadow: palette.cardShadow(raised: true),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildSearch(palette),
            _buildGroups(palette),
            Flexible(
              child: results.isEmpty
                  ? DashboardPlaceholder(
                      palette: palette,
                      icon: Icons.search_off_rounded,
                      message: LocaleKeys.dashboard_add_noResults.tr(),
                    )
                  : _buildGrid(palette, results),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSearch(DashboardPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: palette.sunken,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Icon(Icons.search_rounded, size: 17, color: palette.textMuted),
              const SizedBox(width: 9),
              Expanded(
                child: Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.arrowDown):
                        _MoveIntent(1),
                    SingleActivator(LogicalKeyboardKey.arrowUp):
                        _MoveIntent(-1),
                  },
                  child: Actions(
                    actions: {
                      _MoveIntent: CallbackAction<_MoveIntent>(
                        onInvoke: (intent) {
                          final results = _results;
                          if (results.isEmpty) {
                            return null;
                          }
                          setState(
                            () => _highlighted = (_highlighted + intent.delta)
                                .clamp(0, results.length - 1),
                          );
                          return null;
                        },
                      ),
                    },
                    child: TextField(
                      controller: _query,
                      focusNode: _focus,
                      autofocus: true,
                      style: DashboardType.body(palette),
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: LocaleKeys.dashboard_add_search.tr(),
                        hintStyle: DashboardType.body(
                          palette,
                          color: palette.textMuted,
                        ),
                      ),
                      onChanged: (_) => setState(() => _highlighted = 0),
                      onSubmitted: (_) {
                        final results = _results;
                        if (results.isNotEmpty) {
                          Navigator.of(context).pop(
                            results[_highlighted.clamp(0, results.length - 1)],
                          );
                        }
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );

  Widget _buildGroups(DashboardPalette palette) => SizedBox(
        height: 34,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            _GroupChip(
              label: LocaleKeys.dashboard_group_all.tr(),
              palette: palette,
              selected: _group == null,
              onTap: () => setState(() => _group = null),
            ),
            for (final group in DashboardWidgetGroup.values)
              _GroupChip(
                label: dashboardGroupLabel(group),
                palette: palette,
                selected: _group == group,
                onTap: () => setState(() => _group = group),
              ),
          ],
        ),
      );

  Widget _buildGrid(
    DashboardPalette palette,
    List<DashboardWidgetDefinition> results,
  ) =>
      GridView.builder(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 210,
          mainAxisExtent: 62,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: results.length,
        itemBuilder: (context, index) => _WidgetTile(
          definition: results[index],
          palette: palette,
          highlighted: index == _highlighted,
          onTap: () => Navigator.of(context).pop(results[index]),
        ),
      );
}

class _MoveIntent extends Intent {
  const _MoveIntent(this.delta);

  final int delta;
}

class _GroupChip extends StatelessWidget {
  const _GroupChip({
    required this.label,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final DashboardPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 6),
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: selected
                    ? palette.accent.withValues(alpha: 0.14)
                    : palette.sunken,
                borderRadius:
                    BorderRadius.circular(DashboardMetrics.chipRadius),
              ),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: DashboardType.cardTitle(
                    palette,
                    color: selected ? palette.accent : palette.textSecondary,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
}

class _WidgetTile extends StatefulWidget {
  const _WidgetTile({
    required this.definition,
    required this.palette,
    required this.highlighted,
    required this.onTap,
  });

  final DashboardWidgetDefinition definition;
  final DashboardPalette palette;
  final bool highlighted;
  final VoidCallback onTap;

  @override
  State<_WidgetTile> createState() => _WidgetTileState();
}

class _WidgetTileState extends State<_WidgetTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final definition = widget.definition;
    final active = _hovered || widget.highlighted;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: DashboardMetrics.hover,
          curve: DashboardMetrics.curve,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: active ? palette.hover : palette.hoverBase,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: palette.accent.withValues(alpha: 0.11),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  definition.icon,
                  size: 16,
                  color: palette.accent,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      definition.label(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: DashboardType.cardTitle(
                        palette,
                        color: palette.textPrimary,
                      ),
                    ),
                    if (definition.description != null)
                      Text(
                        definition.description!(),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: DashboardType.caption(palette),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
