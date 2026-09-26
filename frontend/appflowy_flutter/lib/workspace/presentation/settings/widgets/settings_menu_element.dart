import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:flowy_infra_ui/widget/spacing.dart';
import 'package:flutter/material.dart';

class SettingsMenuElement extends StatelessWidget {
  const SettingsMenuElement({
    super.key,
    required this.page,
    required this.label,
    required this.icon,
    required this.changeSelectedPage,
    required this.selectedPage,
  });

  final SettingsPage page;
  final SettingsPage selectedPage;
  final String label;
  final Widget icon;
  final Function changeSelectedPage;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    final selected = page == selectedPage;
    final ink = workspaceGlyphInk(context);
    return Semantics(
      selected: selected,
      child: Tooltip(
        message: label,
        child: TextButton(
          onPressed: () => changeSelectedPage(page),
          style: ButtonStyle(
            animationDuration:
                WorkspaceTokens.motion(context, WorkspaceTokens.hoverDuration),
            alignment: AlignmentDirectional.centerStart,
            minimumSize: const WidgetStatePropertyAll(
              Size(0, WorkspaceTokens.navigationHeight),
            ),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            ),
            foregroundColor: WidgetStatePropertyAll(ink),
            iconColor: WidgetStatePropertyAll(ink),
            backgroundColor: WidgetStateProperty.resolveWith((states) {
              if (selected) return palette.selected;
              if (states.contains(WidgetState.hovered) ||
                  states.contains(WidgetState.focused)) {
                return palette.hover;
              }
              return palette.hover.withValues(alpha: 0);
            }),
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius:
                    BorderRadius.circular(WorkspaceTokens.controlRadius),
              ),
            ),
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: 24,
                child: Center(
                  child: WorkspaceGlyph.adapt(
                    icon,
                    color: ink,
                  ),
                ),
              ),
              const HSpace(WorkspaceTokens.space3),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.body,
                    color: ink,
                  ).copyWith(
                    fontWeight: FontWeight.w500,
                    fontVariations: const [FontVariation.weight(500)],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // return FlowyHover(
  //   isSelected: () => page == selectedPage,
  //   resetHoverOnRebuild: false,
  //   style: HoverStyle(
  //     hoverColor: AFThemeExtension.of(context).greyHover,
  //     borderRadius: BorderRadius.circular(4),
  //   ),
  //   builder: (_, isHovering) => ListTile(
  //     dense: true,
  //     leading: iconWidget(
  //       isHovering || page == selectedPage
  //           ? Theme.of(context).colorScheme.onSurface
  //           : AFThemeExtension.of(context).textColor,
  //     ),
  //     onTap: () => changeSelectedPage(page),
  //     selected: page == selectedPage,
  //     selectedColor: Theme.of(context).colorScheme.onSurface,
  //     selectedTileColor: Theme.of(context).colorScheme.primary,
  //     shape: RoundedRectangleBorder(
  //       borderRadius: BorderRadius.circular(5),
  //     ),
  //     minLeadingWidth: 0,
  //     title: FlowyText.medium(
  //       label,
  //       fontSize: FontSizes.s14,
  //       overflow: TextOverflow.ellipsis,
  //       color: page == selectedPage
  //           ? Theme.of(context).colorScheme.onSurface
  //           : null,
  //     ),
  //   ),
  // );
}
