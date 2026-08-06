import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/grid/presentation/layout/sizes.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/table_view_host.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/shared/table_views/feed_stage.dart';
import 'package:appflowy/shared/table_views/form_stage.dart';
import 'package:appflowy/shared/table_views/gallery_stage.dart';
import 'package:appflowy/shared/table_views/mailbox_stage.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/table_views/timeline_stage.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/table_views/feed_spec.dart';
import 'package:appflowy/workspace/application/table_views/form_spec.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/mailbox_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_view_mark.dart';
import 'package:appflowy/workspace/application/table_views/timeline_spec.dart';
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

/// The name a view of this kind falls back to before it is titled.
String tableViewName(TableViewKind kind) => switch (kind) {
      TableViewKind.timeline => LocaleKeys.timeline_name.tr(),
      TableViewKind.feed => LocaleKeys.feed_name.tr(),
      TableViewKind.form => LocaleKeys.form_name.tr(),
      TableViewKind.gallery => LocaleKeys.gallery_name.tr(),
      TableViewKind.mailbox => LocaleKeys.mailbox_name.tr(),
    };

/// A table opened as one of its other readings.
class TableViewPlugin extends Plugin {
  TableViewPlugin({required ViewPB view, required this.kind})
      : notifier = ViewPluginNotifier(view: view);

  @override
  final ViewPluginNotifier notifier;

  final TableViewKind kind;

  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => PluginType.grid;

  @override
  PluginWidgetBuilder get widgetBuilder => TableViewPluginWidgetBuilder(
        notifier: notifier,
        kind: kind,
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

class TableViewPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  TableViewPluginWidgetBuilder({
    required this.notifier,
    required this.kind,
    required this.viewInfoBloc,
    required this.pageAccessLevelBloc,
  });

  final ViewPluginNotifier notifier;
  final TableViewKind kind;
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
      TableViewPage(key: ValueKey(view.id), view: view, kind: kind);

  @override
  String? get viewName =>
      view.name.isNotEmpty ? view.name : tableViewName(kind);

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

/// One table, read the way this view reads it, with the rows a click away.
class TableViewPage extends StatefulWidget {
  const TableViewPage({super.key, required this.view, required this.kind});

  final ViewPB view;
  final TableViewKind kind;

  @override
  State<TableViewPage> createState() => _TableViewPageState();
}

class _TableViewPageState extends State<TableViewPage>
    with TableViewHostPlumbing<TableViewPage> {
  final GlobalKey<TimelineStageState> _timeline =
      GlobalKey<TimelineStageState>();
  final GlobalKey<FeedStageState> _feed = GlobalKey<FeedStageState>();
  final GlobalKey<FormStageState> _form = GlobalKey<FormStageState>();
  final GlobalKey<GalleryStageState> _gallery = GlobalKey<GalleryStageState>();
  final GlobalKey<MailboxStageState> _mailbox = GlobalKey<MailboxStageState>();

  late final DatabaseController _controller =
      DatabaseController(view: widget.view);
  late TableViewMark _mark = widget.view.tableViewMark(widget.kind) ??
      TableViewMark(kind: widget.kind);

  @override
  ViewPB get hostView => widget.view;

  @override
  DatabaseController get hostController => _controller;

  @override
  TableViewKind get hostKind => widget.kind;

  @override
  void onRowsChanged() {
    _timeline.currentState?.reload();
    _feed.currentState?.reload();
    _gallery.currentState?.reload();
    _mailbox.currentState?.reload();
  }

  @override
  void initState() {
    super.initState();
    startHosting();
  }

  @override
  void didUpdateWidget(covariant TableViewPage old) {
    super.didUpdateWidget(old);
    if (old.view.extra != widget.view.extra) {
      _mark = widget.view.tableViewMark(widget.kind) ?? _mark;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _write(TableViewMark next) {
    setState(() => _mark = next);
    ViewBackendService.updateView(
      viewId: widget.view.id,
      extra: next.mergeIntoExtra(widget.view.extra),
    );
  }

  void _save(Map<String, dynamic> settings) =>
      _write(_mark.copyWith(settings: settings));

  String get _title =>
      widget.view.name.isEmpty ? tableViewName(widget.kind) : widget.view.name;

  Widget _buildStage() {
    const padding = EdgeInsets.fromLTRB(4, 8, 4, 6);
    switch (widget.kind) {
      case TableViewKind.timeline:
        final spec = TimelineSpec.fromJson(_mark.settings);
        return TimelineStage(
          key: _timeline,
          viewId: widget.view.id,
          title: _title,
          spec: spec,
          padding: padding,
          onSpecChanged: (next) => _save(next.toJson()),
          onOpenRow: openRow,
          onAddRow: addRow,
          onReschedule: (rowId, start, end) => rescheduleRow(
            spec.startColumn.isNotEmpty
                ? spec.startColumn
                : _timeline.currentState?.startFieldId ?? '',
            rowId,
            start,
            end,
          ),
        );
      case TableViewKind.feed:
        return FeedStage(
          key: _feed,
          viewId: widget.view.id,
          title: _title,
          spec: FeedSpec.fromJson(_mark.settings),
          padding: padding,
          onSpecChanged: (next) => _save(next.toJson()),
          onOpenRow: openRow,
          onAddRow: addRow,
        );
      case TableViewKind.form:
        return FormStage(
          key: _form,
          viewId: widget.view.id,
          title: _title,
          spec: FormSpec.fromJson(_mark.settings),
          padding: padding,
          onSpecChanged: (next) => _save(next.toJson()),
          onSubmit: addRowWithAnswers,
          onOpenRow: openRow,
        );
      case TableViewKind.gallery:
        return GalleryStage(
          key: _gallery,
          viewId: widget.view.id,
          title: _title,
          spec: GallerySpec.fromJson(_mark.settings),
          padding: padding,
          onSpecChanged: (next) => _save(next.toJson()),
          onOpenRow: openRow,
          onAddRow: addRow,
        );
      case TableViewKind.mailbox:
        return MailboxStage(
          key: _mailbox,
          viewId: widget.view.id,
          title: _title,
          spec: MailboxSpec.fromJson(_mark.settings),
          padding: padding,
          onSpecChanged: (next) => _save(next.toJson()),
          onOpenRow: openRow,
          onAddRow: addRow,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_mark.showTable) {
      return Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(40, 12, 40, 0),
            child: Align(
              alignment: Alignment.centerLeft,
              child: _BackToView(
                icon: tableViewIcon(widget.kind),
                label: tableViewName(widget.kind),
                onTap: () => _write(_mark.copyWith(showTable: false)),
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
      child: _buildStage(),
    );
  }
}

/// The way back from the rows to the view that was left.
class _BackToView extends StatefulWidget {
  const _BackToView({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  State<_BackToView> createState() => _BackToViewState();
}

class _BackToViewState extends State<_BackToView> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: TableViewMetrics.hover,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: _hovered ? palette.hover : palette.hoverAtRest,
            borderRadius: BorderRadius.circular(TableViewMetrics.controlRadius),
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
