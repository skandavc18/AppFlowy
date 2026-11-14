import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/feature_flags.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One settings category, as both the desktop settings menu and the mobile
/// settings list present it.
class SettingsCatalogueEntry {
  const SettingsCatalogueEntry({
    required this.page,
    required this.label,
    required this.icon,
  });

  final SettingsPage page;
  final String label;
  final Widget icon;
}

/// Categories that open a new group in the settings menu.
const settingsCatalogueGroupStarts = {
  SettingsPage.documentEditing,
  SettingsPage.maps,
  SettingsPage.sites,
  SettingsPage.featureFlags,
};

const _menuOrder = [
  SettingsPage.account,
  SettingsPage.workspace,
  SettingsPage.member,
  SettingsPage.manageData,
  SettingsPage.notifications,
  SettingsPage.documentEditing,
  SettingsPage.editor,
  SettingsPage.pageVersions,
  SettingsPage.maps,
  SettingsPage.connections,
  SettingsPage.extensions,
  SettingsPage.shortcuts,
  SettingsPage.ai,
  SettingsPage.sites,
  SettingsPage.plan,
  SettingsPage.billing,
  SettingsPage.featureFlags,
];

/// The settings categories available to [userProfile], in menu order.
///
/// Desktop and mobile share this exact catalogue, including its role and
/// billing gates, so a settings page added here is reachable on every platform.
List<SettingsCatalogueEntry> settingsCatalogue({
  required UserProfilePB userProfile,
  required AFRolePB? currentUserRole,
  required bool isBillingEnabled,
}) {
  final isWorkspaceMember =
      userProfile.workspaceType == WorkspaceTypePB.ServerW &&
          currentUserRole != null &&
          currentUserRole != AFRolePB.Guest;
  bool isAvailable(SettingsPage page) => switch (page) {
        SettingsPage.member =>
          FeatureFlag.membersSettings.isOn && isWorkspaceMember,
        SettingsPage.sites => isWorkspaceMember,
        SettingsPage.plan ||
        SettingsPage.billing =>
          FeatureFlag.planBilling.isOn && isBillingEnabled,
        _ => true,
      };
  return [
    for (final page in _menuOrder)
      if (isAvailable(page)) settingsCatalogueEntry(page),
  ];
}

/// The label and icon of [page], whether or not it is currently available.
SettingsCatalogueEntry settingsCatalogueEntry(SettingsPage page) {
  final (label, icon) = switch (page) {
    SettingsPage.account => (
        LocaleKeys.settings_accountPage_menuLabel.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_user_m),
      ),
    SettingsPage.workspace => (
        LocaleKeys.settings_workspacePage_menuLabel.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_workspace_m),
      ),
    SettingsPage.member => (
        LocaleKeys.settings_appearance_members_label.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_users_m),
      ),
    SettingsPage.manageData => (
        LocaleKeys.settings_manageDataPage_menuLabel.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_database_m),
      ),
    SettingsPage.notifications => (
        LocaleKeys.settings_menu_notifications.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_bell_m),
      ),
    SettingsPage.cloud => (
        LocaleKeys.settings_menu_cloudSettings.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_cloud_m),
      ),
    SettingsPage.documentEditing => (
        'Document editing',
        const WorkspaceGlyph(Icons.description_rounded),
      ),
    SettingsPage.editor => (
        LocaleKeys.settings_editorPage_menuLabel.tr(),
        const WorkspaceGlyph(Icons.edit_note_rounded),
      ),
    SettingsPage.pageVersions => (
        LocaleKeys.pageVersions_settingsTitle.tr(),
        const WorkspaceGlyph(Icons.history_rounded),
      ),
    SettingsPage.encryption => (
        LocaleKeys.encryption_settingsTitle.tr(),
        const WorkspaceGlyph(Icons.lock_outline_rounded),
      ),
    SettingsPage.backup => (
        LocaleKeys.backup_settingsTitle.tr(),
        const WorkspaceGlyph(Icons.backup_rounded),
      ),
    SettingsPage.maps => (
        LocaleKeys.map_settingsTitle.tr(),
        const WorkspaceGlyph(Icons.map_rounded),
      ),
    SettingsPage.connections => (
        LocaleKeys.providers_connections.tr(),
        const WorkspaceGlyph(Icons.hub_rounded),
      ),
    SettingsPage.extensions => (
        LocaleKeys.extensions_settingsTitle.tr(),
        const WorkspaceGlyph(Icons.extension_rounded),
      ),
    SettingsPage.shortcuts => (
        LocaleKeys.settings_shortcutsPage_menuLabel.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_keyboard_m),
      ),
    SettingsPage.ai => (
        LocaleKeys.settings_aiPage_menuLabel.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_ai_m),
      ),
    SettingsPage.sites => (
        LocaleKeys.settings_sites_title.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_earth_m),
      ),
    SettingsPage.plan => (
        LocaleKeys.settings_planPage_menuLabel.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_plan_m),
      ),
    SettingsPage.billing => (
        LocaleKeys.settings_billingPage_menuLabel.tr(),
        const WorkspaceGlyph.svg(FlowySvgs.settings_page_credit_card_m),
      ),
    // no need to translate this page
    SettingsPage.featureFlags => (
        'Feature Flags',
        const WorkspaceGlyph(Icons.flag),
      ),
  };
  return SettingsCatalogueEntry(page: page, label: label, icon: icon);
}
