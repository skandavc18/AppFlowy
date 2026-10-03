import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_toast.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/notifications/widgets/notification_button.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/setting_appflowy_cloud.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'sidebar_footer_button.dart';

class SidebarFooter extends StatelessWidget {
  const SidebarFooter({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (FeatureFlag.planBilling.isOn)
          BillingGateGuard(
            builder: (context) {
              return const SidebarToast();
            },
          ),
        // Utilities remain one click/Tab away, without occupying three
        // permanent navigation rows. Wrap only at exceptionally narrow widths.
        Wrap(
          key: const ValueKey('sidebar-utility-footer'),
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: SidebarMetrics.space1,
          runSpacing: SidebarMetrics.space1,
          children: [
            const UserSettingButton(),
            const SidebarTemplatesButton(compact: true),
            const SidebarExtensionsButton(compact: true),
            const SidebarWorkflowsButton(compact: true),
            const SidebarTrashButton(compact: true),
            BlocSelector<UserWorkspaceBloc, UserWorkspaceState, String>(
              selector: (state) =>
                  state.isCollabWorkspaceOn && state.workspaces.isNotEmpty
                      ? state.currentWorkspace?.workspaceId ??
                          state.userProfile.id.toString()
                      : state.userProfile.id.toString(),
              // Preserve the identity change that restarts the notification
              // button when the workspace changes, even though it moved here.
              builder: (_, id) => NotificationButton(key: ValueKey(id)),
            ),
          ],
        ),
      ],
    );
  }
}

class SidebarTemplatesButton extends StatelessWidget {
  const SidebarTemplatesButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SidebarFooterButton(
      compact: compact,
      icon: SidebarIcon.templates,
      text: LocaleKeys.templates_name.tr(),
      onTap: () {
        getIt<MenuSharedState>().latestOpenView = null;
        getIt<TabsBloc>().add(
          TabsEvent.openPlugin(
            plugin: makePlugin(pluginType: PluginType.templates),
          ),
        );
      },
    );
  }
}

class SidebarExtensionsButton extends StatelessWidget {
  const SidebarExtensionsButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SidebarFooterButton(
      compact: compact,
      icon: SidebarIcon.extensions,
      text: LocaleKeys.extensions_settingsTitle.tr(),
      onTap: () {
        getIt<MenuSharedState>().latestOpenView = null;
        getIt<TabsBloc>().add(
          TabsEvent.openPlugin(
            plugin: makePlugin(pluginType: PluginType.extensions),
          ),
        );
      },
    );
  }
}

class SidebarWorkflowsButton extends StatelessWidget {
  const SidebarWorkflowsButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return SidebarFooterButton(
      compact: compact,
      icon: SidebarIcon.workflows,
      text: LocaleKeys.workflows_title.tr(),
      onTap: () {
        getIt<MenuSharedState>().latestOpenView = null;
        getIt<TabsBloc>().add(
          TabsEvent.openPlugin(
            plugin: makePlugin(pluginType: PluginType.workflows),
          ),
        );
      },
    );
  }
}

class SidebarTrashButton extends StatelessWidget {
  const SidebarTrashButton({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder(
      valueListenable: getIt<MenuSharedState>().notifier,
      builder: (context, value, child) {
        return SidebarFooterButton(
          compact: compact,
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
