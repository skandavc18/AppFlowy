import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_page.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
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

/// A dashboard is a first-class page, opened the same way every other page is.
class DashboardPlugin extends Plugin {
  DashboardPlugin({required ViewPB view})
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
  PluginWidgetBuilder get widgetBuilder => DashboardPluginWidgetBuilder(
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

class DashboardPluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  DashboardPluginWidgetBuilder({
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
  }) {
    notifier.isDeleted.addListener(() {
      final deletedView = notifier.isDeleted.value;
      if (deletedView != null && deletedView.hasIndex()) {
        context.onDeleted?.call(view, deletedView.index);
      }
    });
    return DashboardPage(key: ValueKey(view.id), view: view);
  }

  @override
  String? get viewName =>
      view.name.isNotEmpty ? view.name : LocaleKeys.dashboard_untitled.tr();

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
