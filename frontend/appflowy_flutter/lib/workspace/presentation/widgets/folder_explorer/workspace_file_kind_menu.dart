import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The one shape every "add a file" menu wears.
///
/// The sidebar submenu, the explorer toolbar, the gallery header and every
/// context menu render these entries, so a file type is named with the same
/// glyph and the same row wherever it is offered.
abstract final class WorkspaceFileKindMenuStyle {
  static const width = 248.0;

  /// Constraints for a popover hosting the menu, so the popover neither
  /// squeezes nor stretches the card.
  static const popoverConstraints = BoxConstraints(
    minWidth: width,
    maxWidth: width,
    maxHeight: 640,
  );
}

/// The creatable and uploadable file types, as menu entries.
///
/// [onSelected] is optional: a menu opened with `showAppMenu` reads the row's
/// value instead, while a submenu inside a popover needs the callback.
List<AppMenuEntry> workspaceFileKindEntries({
  ValueChanged<WorkspaceFileMenuAction>? onSelected,
}) {
  final entries = <AppMenuEntry>[];
  WorkspaceFileSource? section;
  for (final action in workspaceFileMenuActions) {
    if (action.source != section) {
      section = action.source;
      entries
        ..add(const AppMenuSeparator())
        ..add(AppMenuHeader(action.source.heading));
    }
    entries.add(
      AppMenuItem(
        label: action.label,
        icon: action.icon,
        value: action,
        onSelected: onSelected == null ? null : () => onSelected(action),
      ),
    );
  }
  return entries;
}

/// Shows the creatable and uploadable file types anchored at [globalPosition].
Future<WorkspaceFileMenuAction?> showWorkspaceFileKindMenu({
  required BuildContext context,
  required Offset globalPosition,
}) =>
    showAppMenu<WorkspaceFileMenuAction>(
      context: context,
      globalPosition: globalPosition,
      entries: workspaceFileKindEntries(),
      width: WorkspaceFileKindMenuStyle.width,
    );

/// The nested "Add file" entry, which reveals every supported file type.
///
/// Shared by the sidebar `+` button, the folder header and the sidebar
/// background menu so a submenu is never a second design.
class WorkspaceFileAddAction extends PopoverActionCell {
  WorkspaceFileAddAction({required this.onCreate});

  final void Function(WorkspaceFileMenuAction action) onCreate;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        workspaceAddFileIcon,
        color: iconColor,
        size: AppMenuMetrics.iconSize,
      );

  @override
  String get name => LocaleKeys.workspaceFolderExplorer_addFile.tr();

  @override
  bool get openOnHover => true;

  @override
  BoxConstraints? get popoverConstraints =>
      WorkspaceFileKindMenuStyle.popoverConstraints;

  @override
  PopoverActionCellBuilder get builder =>
      (context, parentController, controller) => WorkspaceFileKindList(
            onSelected: (action) {
              controller.close();
              parentController.close();
              onCreate(action);
            },
          );
}

/// The file-type rows on their own, for a popover that supplies the card.
class WorkspaceFileKindList extends StatelessWidget {
  const WorkspaceFileKindList({super.key, required this.onSelected});

  final ValueChanged<WorkspaceFileMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final entries = normalizeAppMenuEntries(workspaceFileKindEntries());
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final entry in entries)
            switch (entry) {
              AppMenuSeparator() => const AppMenuSeparatorLine(),
              AppMenuHeader(:final label) => AppMenuSectionLabel(label: label),
              AppMenuCustom(:final builder) => Builder(builder: builder),
              AppMenuItem() => AppMenuRow(
                  label: entry.label,
                  icon: entry.icon,
                  tracksHover: true,
                  onTap: () =>
                      onSelected(entry.value! as WorkspaceFileMenuAction),
                ),
            },
        ],
      ),
    );
  }
}
