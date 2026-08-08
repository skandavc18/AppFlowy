import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/widgets/favorite_button.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_stage.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/more_view_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/tab_bar_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_title_bar.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class WorkspaceFolderPlugin extends Plugin {
  WorkspaceFolderPlugin({required ViewPB view})
      : notifier = ViewPluginNotifier(view: view);

  @override
  final ViewPluginNotifier notifier;

  late final ViewInfoBloc _viewInfoBloc;
  late final PageAccessLevelBloc _pageAccessLevelBloc;

  @override
  PluginId get id => notifier.view.id;

  @override
  PluginType get pluginType => PluginType.document;

  @override
  PluginWidgetBuilder get widgetBuilder => WorkspaceFolderPluginWidgetBuilder(
        notifier: notifier,
        viewInfoBloc: _viewInfoBloc,
        pageAccessLevelBloc: _pageAccessLevelBloc,
      );

  @override
  void init() {
    final isWorkspaceRoot =
        notifier.view.parentViewId.isEmpty && notifier.view.isWorkspaceFolder;
    _viewInfoBloc = ViewInfoBloc(view: notifier.view);
    _pageAccessLevelBloc = PageAccessLevelBloc(view: notifier.view);
    if (!isWorkspaceRoot) {
      _viewInfoBloc.add(const ViewInfoEvent.started());
      _pageAccessLevelBloc.add(const PageAccessLevelEvent.initial());
    }
  }

  @override
  void dispose() {
    _viewInfoBloc.close();
    _pageAccessLevelBloc.close();
    notifier.dispose();
  }
}

class WorkspaceFolderPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  WorkspaceFolderPluginWidgetBuilder({
    required this.notifier,
    required this.viewInfoBloc,
    required this.pageAccessLevelBloc,
  });

  final ViewPluginNotifier notifier;
  final ViewInfoBloc viewInfoBloc;
  final PageAccessLevelBloc pageAccessLevelBloc;
  int? deletedViewIndex;

  ViewPB get view => notifier.view;
  bool get isWorkspaceRoot =>
      view.parentViewId.isEmpty && view.isWorkspaceFolder;

  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) {
    notifier.isDeleted.addListener(() {
      final deletedView = notifier.isDeleted.value;
      if (deletedView != null && deletedView.hasIndex()) {
        deletedViewIndex = deletedView.index;
        context.onDeleted?.call(view, deletedViewIndex);
      }
    });
    return Padding(
      padding: const EdgeInsets.fromLTRB(28, 18, 28, 26),
      child: WorkspaceFolderStage(
        key: ValueKey(view.id),
        view: view,
      ),
    );
  }

  @override
  String? get viewName => view.name.isEmpty ? 'Untitled folder' : view.name;

  @override
  Widget get leftBarItem => BlocProvider<PageAccessLevelBloc>.value(
        value: pageAccessLevelBloc,
        child: ViewTitleBar(
          key: ValueKey(view.id),
          view: view,
          hideCurrentView: true,
        ),
      );

  @override
  Widget? get rightBarItem {
    if (isWorkspaceRoot) {
      return null;
    }
    return MultiBlocProvider(
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
  }

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) =>
      ViewTabBarItem(view: view, shortForm: shortForm);

  @override
  List<NavigationItem> get navigationItems => [this];
}
