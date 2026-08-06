import 'dart:async';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/slides/slide_stage.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/slides/slide_metadata.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

/// A table opened as a stack of slides.
class SlidePlugin extends Plugin {
  SlidePlugin({required ViewPB view})
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
  PluginWidgetBuilder get widgetBuilder => SlidePluginWidgetBuilder(
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

class SlidePluginWidgetBuilder extends PluginWidgetBuilder with NavigationItem {
  SlidePluginWidgetBuilder({
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
      SlidePage(key: ValueKey(view.id), view: view);

  @override
  String? get viewName =>
      view.name.isNotEmpty ? view.name : LocaleKeys.slides_name.tr();

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

/// One table, read one row at a time, with its rows a click away.
class SlidePage extends StatefulWidget {
  const SlidePage({super.key, required this.view});

  final ViewPB view;

  @override
  State<SlidePage> createState() => _SlidePageState();
}

class _SlidePageState extends State<SlidePage> {
  final GlobalKey<SlideStageState> _stage = GlobalKey<SlideStageState>();

  late SlideMetadata _metadata =
      widget.view.slideView ?? const SlideMetadata(spec: SlideSpec());

  DatabaseController? _controller;

  @override
  void initState() {
    super.initState();
    // The page owns no database of its own, so one is opened to answer a click
    // on a slide with the real row editor.
    final controller = DatabaseController(view: widget.view);
    _controller = controller;
    controller.open();
  }

  @override
  void didUpdateWidget(covariant SlidePage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.extra != widget.view.extra) {
      _metadata = widget.view.slideView ?? _metadata;
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  void _write(SlideMetadata next) {
    setState(() => _metadata = next);
    ViewBackendService.updateView(
      viewId: widget.view.id,
      extra: next.mergeIntoExtra(widget.view.extra),
    );
  }

  void _openRow(String rowId) {
    final controller = _controller;
    final rowMeta = controller?.rowCache.getRow(rowId)?.rowMeta;
    if (controller == null || rowMeta == null) {
      return;
    }
    _openRowMeta(controller, rowMeta);
  }

  void _openRowMeta(DatabaseController controller, RowMetaPB rowMeta) {
    unawaited(
      FlowyOverlay.show(
        context: context,
        builder: (_) => BlocProvider.value(
          value: context.read<UserWorkspaceBloc>(),
          child: RowDetailPage(
            rowController: RowController(
              rowMeta: rowMeta,
              viewId: controller.viewId,
              rowCache: controller.rowCache,
            ),
            databaseController: controller,
          ),
        ),
      ).then((_) {
        if (!mounted) {
          return;
        }
        // Whatever was written on the row's page has to be read again, and a
        // page made during the visit had no id to forget.
        RowPageText.forget();
        _stage.currentState?.reload();
      }),
    );
  }

  Future<String?> _addRow() async {
    final controller = _controller;
    if (controller == null) {
      return null;
    }
    final created = await RowBackendService.createRow(viewId: widget.view.id);
    if (!mounted) {
      return null;
    }
    return created.fold(
      (rowMeta) {
        _stage.currentState?.reload();
        _openRowMeta(controller, rowMeta);
        return rowMeta.id;
      },
      (error) {
        Log.error(error);
        return null;
      },
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
                icon: Icons.view_carousel_rounded,
                label: LocaleKeys.slides_name.tr(),
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
      padding: const EdgeInsets.fromLTRB(40, 12, 40, 24),
      child: SlideStage(
        key: _stage,
        viewId: widget.view.id,
        title: widget.view.name.isEmpty
            ? LocaleKeys.slides_name.tr()
            : widget.view.name,
        spec: _metadata.spec,
        onSpecChanged: (spec) => _write(_metadata.copyWith(spec: spec)),
        onOpenRow: _openRow,
        onEditRow: _openRow,
        onAddRow: _addRow,
        padding: const EdgeInsets.fromLTRB(4, 8, 4, 6),
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
    final palette = slidePaletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: SlideMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color:
                _hovered ? palette.hover : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(SlideMetrics.controlRadius),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(widget.icon, size: 15, color: palette.textSecondary),
              const SizedBox(width: 7),
              Text(
                widget.label,
                style: TextStyle(fontSize: 12.5, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
