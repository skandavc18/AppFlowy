import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/blank/workspace_home_page.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class BlankPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) {
    return BlankPagePlugin();
  }

  @override
  String get menuName => "Blank";

  @override
  FlowySvgData get icon => const FlowySvgData('');

  @override
  PluginType get pluginType => PluginType.blank;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class BlankPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class BlankPagePlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => BlankPagePluginWidgetBuilder();

  @override
  PluginId get id => "";

  @override
  PluginType get pluginType => PluginType.blank;
}

class BlankPagePluginWidgetBuilder extends PluginWidgetBuilder
    with NavigationItem {
  @override
  EdgeInsets get contentPadding => EdgeInsets.zero;

  @override
  String? get viewName => LocaleKeys.dashboard_home.tr();

  @override
  Widget get leftBarItem => FlowyText.medium(LocaleKeys.dashboard_home.tr());

  @override
  Widget tabBarItem(String pluginId, [bool shortForm = false]) => leftBarItem;

  @override
  Widget buildWidget({
    required PluginContext context,
    required bool shrinkWrap,
    Map<String, dynamic>? data,
  }) =>
      const BlankPage();

  @override
  List<NavigationItem> get navigationItems => [this];
}

class BlankPage extends StatefulWidget {
  const BlankPage({super.key});

  @override
  State<BlankPage> createState() => _BlankPageState();
}

class _BlankPageState extends State<BlankPage> {
  @override
  Widget build(BuildContext context) => const WorkspaceHomePage();
}
