import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workflows/presentation/workflows_page.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class WorkflowsPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => WorkflowsPlugin();

  @override
  String get menuName => 'Workflows';

  @override
  FlowySvgData get icon => FlowySvgs.settings_s;

  @override
  PluginType get pluginType => PluginType.workflows;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class WorkflowsPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class WorkflowsPlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => WorkflowsPluginDisplay();

  @override
  PluginId get id => 'WorkflowsStack';

  @override
  PluginType get pluginType => PluginType.workflows;
}

class WorkflowsPluginDisplay extends PluginWidgetBuilder {
  @override
  String? get viewName => LocaleKeys.workflows_title.tr();

  @override
  Widget get leftBarItem => FlowyText.medium(LocaleKeys.workflows_title.tr());

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  Widget? get rightBarItem => null;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const WorkflowsPage(key: ValueKey('WorkflowsPage'));

  @override
  List<NavigationItem> get navigationItems => [this];
}
