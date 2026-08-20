import 'package:appflowy/extensions/presentation/extensions_page.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pbenum.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flutter/material.dart';

class ExtensionsPluginBuilder extends PluginBuilder {
  @override
  Plugin build(dynamic data) => ExtensionsPlugin();

  @override
  String get menuName => 'Extensions';

  @override
  FlowySvgData get icon => FlowySvgs.settings_s;

  @override
  PluginType get pluginType => PluginType.extensions;

  @override
  ViewLayoutPB get layoutType => ViewLayoutPB.Document;
}

class ExtensionsPluginConfig implements PluginConfig {
  @override
  bool get creatable => false;
}

class ExtensionsPlugin extends Plugin {
  @override
  PluginWidgetBuilder get widgetBuilder => ExtensionsPluginDisplay();

  @override
  PluginId get id => 'ExtensionsStack';

  @override
  PluginType get pluginType => PluginType.extensions;
}

class ExtensionsPluginDisplay extends PluginWidgetBuilder {
  @override
  String? get viewName => LocaleKeys.extensions_settingsTitle.tr();

  @override
  Widget get leftBarItem =>
      FlowyText.medium(LocaleKeys.extensions_settingsTitle.tr());

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
      const ExtensionsPage(key: ValueKey('ExtensionsPage'));

  @override
  List<NavigationItem> get navigationItems => [this];
}
