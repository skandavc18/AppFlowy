import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/templates/presentation/templates_page.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class TemplatesPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => TemplatesPlugin();

  @override
  String get menuName => 'Templates';

  @override
  FlowySvgData get icon => FlowySvgs.settings_s;

  @override
  PluginType get pluginType => PluginType.templates;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class TemplatesPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class TemplatesPlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => TemplatesPluginDisplay();

  @override
  PluginId get id => 'TemplatesStack';

  @override
  PluginType get pluginType => PluginType.templates;
}

class TemplatesPluginDisplay extends PluginWidgetBuilder {
  @override
  String? get viewName => LocaleKeys.templates_name.tr();

  @override
  Widget get leftBarItem => FlowyText.medium(LocaleKeys.templates_name.tr());

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
      const TemplatesPage(key: ValueKey('TemplatesPage'));

  @override
  List<NavigationItem> get navigationItems => [this];
}
