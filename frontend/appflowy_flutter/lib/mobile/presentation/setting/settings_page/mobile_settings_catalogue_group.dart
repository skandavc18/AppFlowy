import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/setting/settings_page/mobile_settings_page_screen.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/mobile_setting_trailing.dart';
import 'package:appflowy/mobile/presentation/setting/widgets/widgets.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/settings_catalogue.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

/// Every settings category of the desktop settings dialog, as mobile rows that
/// open the same pages full screen.
class MobileSettingsCatalogueGroup extends StatelessWidget {
  const MobileSettingsCatalogueGroup({super.key, required this.userProfile});

  final UserProfilePB userProfile;

  @override
  Widget build(BuildContext context) {
    final role = context.select<UserWorkspaceBloc, AFRolePB?>(
      (bloc) => bloc.state.currentWorkspace?.role,
    );
    // The bloc resolves billing availability for this role, as on desktop.
    return BlocProvider(
      key: ValueKey(role),
      create: (_) => SettingsDialogBloc(userProfile, role)
        ..add(const SettingsDialogEvent.initial()),
      child: BlocBuilder<SettingsDialogBloc, SettingsDialogState>(
        builder: (context, state) {
          final entries = settingsCatalogue(
            userProfile: state.userProfile,
            currentUserRole: role,
            isBillingEnabled: state.isBillingEnabled,
          );
          final ink = workspaceGlyphInk(context);
          return MobileSettingGroup(
            groupTitle: LocaleKeys.settings_title.tr(),
            settingItemList: [
              for (final (index, entry) in entries.indexed) ...[
                if (index > 0 &&
                    settingsCatalogueGroupStarts.contains(entry.page))
                  const VSpace(8),
                MobileSettingItem(
                  key: ValueKey('mobile-settings-${entry.page.name}'),
                  name: entry.label,
                  leadingIcon: WorkspaceGlyph.adapt(
                    entry.icon,
                    size: 20,
                    color: ink,
                  ),
                  trailing: const MobileSettingTrailing(text: ''),
                  onTap: () => context.push(
                    MobileSettingsPageScreen.location(entry.page),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
