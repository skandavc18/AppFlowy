import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_toast.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/setting_appflowy_cloud.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'sidebar_footer_button.dart';

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (FeatureFlag.planBilling.isOn)
          BillingGateGuard(
            builder: (context) {
              return const SidebarToast();
            },
          ),
        const Column(
          children: [
            SidebarTrashButton(),
          ],
        ),
      ],
    );
  }
}

class SidebarTrashButton extends StatelessWidget {
  const SidebarTrashButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: getIt<MenuSharedState>().notifier,
      builder: (context, value, child) {
        return SidebarFooterButton(
          icon: SidebarIcon.trash,
          text: LocaleKeys.trash_text.tr(),
          onTap: () {
            getIt<MenuSharedState>().latestOpenView = null;
            getIt<TabsBloc>().add(
              TabsEvent.openPlugin(
                plugin: makePlugin(pluginType: PluginType.trash),
              ),
            );
          },
        );
      },
    );
  }
}

class SidebarWidgetButton extends StatelessWidget {
  const SidebarWidgetButton({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: () {},
        child: const FlowySvg(FlowySvgs.sidebar_footer_widget_s),
      ),
    );
  }
}
