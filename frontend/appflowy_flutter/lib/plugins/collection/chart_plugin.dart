import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/charts/chart_stage.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/charts/chart_metadata.dart';
import 'package:appflowy/workspace/application/charts/chart_spec.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

/// A table opened as a picture of itself.
class ChartPlugin extends Plugin {
  ChartPlugin({required ViewPB view})
      : notifier = ViewPluginNotifier(view: view);

  @override
  final ViewPluginNotifier notifier;

  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => PluginType.grid;

  @override
  PluginWidgetBuilder get widgetBuilder => ChartPluginWidgetBuilder(
        notifier: notifier,
        viewInfoBloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  void init() {
    _viewInfoBloc = ViewInfoBloc(view: notifier.view);
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view);
    _viewInfoBloc.add(const ViewInfoEvent.started());
    _pageAccessLevelBloc.add(const PageAccessLevelEvent.initial());
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class ChartPluginWidgetBuilder extends PluginWidgetBuilder with NavigationItem {
  ChartPluginWidgetBuilder({
    required this.notifier,
    required this.viewInfoBloc,
    required this.pageAccessLevelBloc,
  });

  final ViewPluginNotifier notifier;
  final ViewInfoBloc viewInfoBloc;
  final PageAccessLevelBloc pageAccessLevelBloc;

  ViewPB get view => notifier.view;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      ChartPage(key: ValueKey(view.id), view: view);

  @override
  String? get viewName =>
      view.name.isNotEmpty ? view.name : LocaleKeys.charts_chart.tr();

  @override
  Widget get leftBarItem => BlocProvider<PageAccessLevelBloc>.value(
        value: pageAccessLevelBloc,
        child: ViewTitleBar(key: ValueKey(view.id), view: view),
      );

  @override
  Widget? get rightBarItem => MultiBlocProvider(
        providers: [
          BlocProvider<ViewInfoBloc>.value(value: viewInfoBloc),
          BlocProvider<PageAccessLevelBloc>.value(value: pageAccessLevelBloc),
        ],
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            ViewFavoriteButton(
              key: ValueKey('favorite_button_${view.id}'),
              view: view,
            ),
            const HSpace(4),
            MoreViewActions(view: view),
          ],
        ),
      );

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: view, shortForm: shortForm);

  @override
  List<NavigationItem> get navigationItems => [this];
}

/// One table, shown as a chart, with its rows a click away.
class ChartPage extends StatefulWidget {
  const ChartPage({super.key, required this.view});

  final ViewPB view;

  @override
  State<ChartPage> createState() => _ChartPageState();
}

class _ChartPageState extends State<ChartPage> {
  late ChartMetadata _metadata =
      widget.view.chart ?? const ChartMetadata(spec: ChartSpec());

  @override
  void didUpdateWidget(covariant ChartPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.extra != widget.view.extra) {
      _metadata = widget.view.chart ?? _metadata;
    }
  }

  void _write(ChartMetadata next) {
    setState(() => _metadata = next);
    // The mark lives on the view, so the chart is the same everywhere the
    // table is opened — and on the next launch.
    ViewBackendService.updateView(
      viewId: widget.view.id,
      extra: next.mergeIntoExtra(widget.view.extra),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_metadata.showTable) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _Toggle(
                icon: Icons.insert_chart_outlined_rounded,
                label: LocaleKeys.charts_showChart.tr(),
                onTap: () => _write(_metadata.copyWith(showTable: false)),
              ),
            ),
          ),
          Expanded(
            child: Provider(
              create: (_) => DatabasePluginWidgetBuilderSize(
                horizontalPadding: GridSize.horizontalHeaderPadding,
                verticalPadding: 8,
              ),
              child: DatabaseTabBarView(
                key: ValueKey(widget.view.id),
                view: widget.view,
                shrinkWrap: false,
                showActions: true,
              ),
            ),
          ),
        ],
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 28),
      child: ChartStage(
        key: ValueKey(widget.view.id),
        viewId: widget.view.id,
        title: widget.view.name.isEmpty
            ? LocaleKeys.charts_untitled.tr()
            : widget.view.name,
        spec: _metadata.spec,
        onSpecChanged: (spec) => _write(_metadata.copyWith(spec: spec)),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 18),
        trailing: [
          _Toggle(
            icon: Icons.table_rows_rounded,
            label: LocaleKeys.charts_showTable.tr(),
            onTap: () => _write(_metadata.copyWith(showTable: true)),
          ),
        ],
      ),
    );
  }
}

class _Toggle extends StatefulWidget {
  const _Toggle({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_Toggle> createState() => _ToggleState();
}

class _ToggleState extends State<_Toggle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onSurface = theme.colorScheme.onSurface;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 10),
          decoration: BoxDecoration(
            color: onSurface.withValues(alpha: _hovered ? 0.09 : 0.05),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                widget.icon,
                size: 14,
                color: onSurface.withValues(alpha: 0.62),
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style:
                    (theme.textTheme.bodyMedium ?? const TextStyle()).copyWith(
                  fontSize: 11.5,
                  color: onSurface.withValues(alpha: 0.86),
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
