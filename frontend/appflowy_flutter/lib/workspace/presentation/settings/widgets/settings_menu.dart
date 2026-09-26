import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';

class SettingsMenu extends StatelessWidget {
  const SettingsMenu({
    super.key,
    required this.changeSelectedPage,
    required this.currentPage,
    required this.userProfile,
    required this.isBillingEnabled,
    required this.currentUserRole,
    this.compact = false,
  });

  final Function changeSelectedPage;
  final SettingsPage currentPage;
  final UserProfilePB userProfile;
  final bool isBillingEnabled;
  final AFRolePB? currentUserRole;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final entries = _entries;
    if (compact) {
      final selected = entries.where((entry) => entry.page == currentPage);
      return TextButton(
        key: const ValueKey('settings-category-picker'),
        onPressed: () async {
          final page = await showAppMenuForWidget<SettingsPage>(
            context: context,
            entries: [
              for (final entry in entries)
                AppMenuItem(
                  label: entry.label,
                  iconWidget: entry.icon,
                  value: entry.page,
                  selected: entry.page == currentPage,
                ),
            ],
          );
          if (context.mounted && page != null) changeSelectedPage(page);
        },
        style: TextButton.styleFrom(
          foregroundColor: workspaceGlyphInk(context),
          backgroundColor: palette.secondarySurface,
          alignment: AlignmentDirectional.centerStart,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkspaceTokens.inputRadius),
          ),
        ).copyWith(
          animationDuration:
              WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                selected.isEmpty
                    ? LocaleKeys.signIn_settings.tr()
                    : selected.first.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.cardTitle,
                  color: workspaceGlyphInk(context),
                ).copyWith(
                  fontWeight: FontWeight.w500,
                  fontVariations: const [FontVariation.weight(500)],
                ),
              ),
            ),
            const SizedBox(width: WorkspaceTokens.space2),
            const WorkspaceGlyph(
              Icons.unfold_more_rounded,
            ),
          ],
        ),
      );
    }

    return ColoredBox(
      color: Color.alphaBlend(
        palette.secondarySurface.withValues(alpha: 0.6),
        palette.elevatedSurface,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 20),
              child: Text(
                LocaleKeys.signIn_settings.tr(),
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                ),
              ),
            ),
            for (final entry in entries)
              Padding(
                padding: EdgeInsets.only(
                  top: const {
                    SettingsPage.documentEditing,
                    SettingsPage.maps,
                    SettingsPage.sites,
                    SettingsPage.featureFlags,
                  }.contains(entry.page)
                      ? WorkspaceTokens.space4
                      : 2,
                ),
                child: entry,
              ),
          ],
        ),
      ),
    );
  }

  // Both compositions use this exact catalogue, including role/billing gates.
  List<SettingsMenuElement> get _entries => [
        SettingsMenuElement(
          page: SettingsPage.account,
          selectedPage: currentPage,
          label: LocaleKeys.settings_accountPage_menuLabel.tr(),
          icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_user_m),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.workspace,
          selectedPage: currentPage,
          label: LocaleKeys.settings_workspacePage_menuLabel.tr(),
          icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_workspace_m),
          changeSelectedPage: changeSelectedPage,
        ),
        if (FeatureFlag.membersSettings.isOn &&
            userProfile.workspaceType == WorkspaceTypePB.ServerW &&
            currentUserRole != null &&
            currentUserRole != AFRolePB.Guest)
          SettingsMenuElement(
            page: SettingsPage.member,
            selectedPage: currentPage,
            label: LocaleKeys.settings_appearance_members_label.tr(),
            icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_users_m),
            changeSelectedPage: changeSelectedPage,
          ),
        SettingsMenuElement(
          page: SettingsPage.manageData,
          selectedPage: currentPage,
          label: LocaleKeys.settings_manageDataPage_menuLabel.tr(),
          icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_database_m),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.notifications,
          selectedPage: currentPage,
          label: LocaleKeys.settings_menu_notifications.tr(),
          icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_bell_m),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.cloud,
          selectedPage: currentPage,
          label: LocaleKeys.settings_menu_cloudSettings.tr(),
          icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_cloud_m),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.documentEditing,
          selectedPage: currentPage,
          label: 'Document editing',
          icon: const WorkspaceGlyph(Icons.description_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.editor,
          selectedPage: currentPage,
          label: LocaleKeys.settings_editorPage_menuLabel.tr(),
          icon: const WorkspaceGlyph(Icons.edit_note_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.pageVersions,
          selectedPage: currentPage,
          label: LocaleKeys.pageVersions_settingsTitle.tr(),
          icon: const WorkspaceGlyph(Icons.history_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.encryption,
          selectedPage: currentPage,
          label: LocaleKeys.encryption_settingsTitle.tr(),
          icon: const WorkspaceGlyph(Icons.lock_outline_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.backup,
          selectedPage: currentPage,
          label: LocaleKeys.backup_settingsTitle.tr(),
          icon: const WorkspaceGlyph(Icons.backup_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.maps,
          selectedPage: currentPage,
          label: LocaleKeys.map_settingsTitle.tr(),
          icon: const WorkspaceGlyph(Icons.map_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.connections,
          selectedPage: currentPage,
          label: LocaleKeys.providers_connections.tr(),
          icon: const WorkspaceGlyph(Icons.hub_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.extensions,
          selectedPage: currentPage,
          label: LocaleKeys.extensions_settingsTitle.tr(),
          icon: const WorkspaceGlyph(Icons.extension_rounded),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.shortcuts,
          selectedPage: currentPage,
          label: LocaleKeys.settings_shortcutsPage_menuLabel.tr(),
          icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_keyboard_m),
          changeSelectedPage: changeSelectedPage,
        ),
        SettingsMenuElement(
          page: SettingsPage.ai,
          selectedPage: currentPage,
          label: LocaleKeys.settings_aiPage_menuLabel.tr(),
          icon: const WorkspaceGlyph.svg(
            FlowySvgs.settings_page_ai_m,
          ),
          changeSelectedPage: changeSelectedPage,
        ),
        if (userProfile.workspaceType == WorkspaceTypePB.ServerW &&
            currentUserRole != null &&
            currentUserRole != AFRolePB.Guest)
          SettingsMenuElement(
            page: SettingsPage.sites,
            selectedPage: currentPage,
            label: LocaleKeys.settings_sites_title.tr(),
            icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_earth_m),
            changeSelectedPage: changeSelectedPage,
          ),
        if (FeatureFlag.planBilling.isOn && isBillingEnabled) ...[
          SettingsMenuElement(
            page: SettingsPage.plan,
            selectedPage: currentPage,
            label: LocaleKeys.settings_planPage_menuLabel.tr(),
            icon: const WorkspaceGlyph.svg(FlowySvgs.settings_page_plan_m),
            changeSelectedPage: changeSelectedPage,
          ),
          SettingsMenuElement(
            page: SettingsPage.billing,
            selectedPage: currentPage,
            label: LocaleKeys.settings_billingPage_menuLabel.tr(),
            icon:
                const WorkspaceGlyph.svg(FlowySvgs.settings_page_credit_card_m),
            changeSelectedPage: changeSelectedPage,
          ),
        ],
        SettingsMenuElement(
          // no need to translate this page
          page: SettingsPage.featureFlags,
          selectedPage: currentPage,
          label: 'Feature Flags',
          icon: const WorkspaceGlyph(Icons.flag),
          changeSelectedPage: changeSelectedPage,
        ),
      ];
}

class SimpleSettingsMenu extends StatelessWidget {
  const SimpleSettingsMenu({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return Column(
      children: [
        Expanded(
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 8) +
                const EdgeInsets.only(left: 8, right: 4),
            decoration: BoxDecoration(
              color: palette.secondarySurface,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(WorkspaceTokens.dialogRadius),
                bottomLeft: Radius.circular(WorkspaceTokens.dialogRadius),
              ),
            ),
            child: SingleChildScrollView(
              // Right padding is added to make the scrollbar centered
              // in the space between the menu and the content
              padding: const EdgeInsets.only(right: 4) +
                  const EdgeInsets.symmetric(vertical: 16),
              child: SeparatedColumn(
                separatorBuilder: () => const VSpace(16),
                children: [
                  SettingsMenuElement(
                    page: SettingsPage.cloud,
                    selectedPage: SettingsPage.cloud,
                    label: LocaleKeys.settings_menu_cloudSettings.tr(),
                    icon: const WorkspaceGlyph(Icons.sync),
                    changeSelectedPage: () {},
                  ),
                  SettingsMenuElement(
                    // no need to translate this page
                    page: SettingsPage.featureFlags,
                    selectedPage: SettingsPage.cloud,
                    label: 'Feature Flags',
                    icon: const WorkspaceGlyph(Icons.flag),
                    changeSelectedPage: () {},
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
