import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/presentation/settings/settings_catalogue.dart';
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
                  top: settingsCatalogueGroupStarts.contains(entry.page)
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
        for (final entry in settingsCatalogue(
          userProfile: userProfile,
          currentUserRole: currentUserRole,
          isBillingEnabled: isBillingEnabled,
        ))
          SettingsMenuElement(
            page: entry.page,
            selectedPage: currentPage,
            label: entry.label,
            icon: entry.icon,
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
