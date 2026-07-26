import 'dart:async';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/document.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/import/import_panel.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class ViewAddButton extends StatelessWidget {
  const ViewAddButton({
    super.key,
    required this.parentViewId,
    required this.sourceView,
    required this.onEditing,
    required this.onSelected,
    required this.onTransfer,
    this.isHovered = false,
    this.showTransferActions = true,
  });

  final String parentViewId;
  final ViewPB sourceView;
  final void Function(bool value) onEditing;
  final Function(
    PluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) onSelected;
  final ValueChanged<ViewMoreActionType> onTransfer;
  final bool isHovered;
  final bool showTransferActions;

  List<PopoverAction> _actionsFor(BuildContext hostContext) {
    final actions = <PopoverAction>[];
    if (!sourceView.isWorkspaceFile) {
      actions.addAll([
        WorkspaceItemAddAction(WorkspaceItemAddKind.folder),
        WorkspaceFileAddAction(
          onCreate: (action) => _createWorkspaceFile(hostContext, action),
        ),
        // document, grid, kanban, calendar
        ...pluginBuilders().map(
          (pluginBuilder) => ViewAddButtonActionWrapper(
            pluginBuilder: pluginBuilder,
          ),
        ),
        // import from ...
        ...getIt<PluginSandbox>()
            .builders
            .whereType<DocumentPluginBuilder>()
            .map(
              (pluginBuilder) => ViewImportActionWrapper(
                pluginBuilder: pluginBuilder,
              ),
            ),
        if (showTransferActions) _ViewAddDivider(),
      ]);
    }
    if (showTransferActions) {
      actions.addAll([
        ViewTransferAction(ViewMoreActionType.moveTo),
        ViewTransferAction(ViewMoreActionType.copyTo),
        ViewTransferAction(ViewMoreActionType.cut),
        if (sourceView.canContainWorkspaceItems &&
            WorkspaceItemClipboard.instance.hasData)
          ViewTransferAction(ViewMoreActionType.pasteInto),
      ]);
    }
    return actions;
  }

  @override
  Widget build(BuildContext context) {
    return PopoverActionList<PopoverAction>(
      direction: PopoverDirection.bottomWithLeftAligned,
      actions: _actionsFor(context),
      offset: const Offset(0, 8),
      constraints: const BoxConstraints(
        minWidth: 200,
      ),
      buildChild: (popover) {
        return FlowyIconButton(
          width: 24,
          icon: FlowySvg(
            FlowySvgs.view_item_add_s,
            color: isHovered ? Theme.of(context).colorScheme.onSurface : null,
          ),
          onPressed: () {
            onEditing(true);
            popover.show();
          },
        );
      },
      onSelected: (action, popover) {
        onEditing(false);
        if (action is ViewAddButtonActionWrapper) {
          _showViewAddButtonActions(context, action);
        } else if (action is ViewImportActionWrapper) {
          _showViewImportAction(context, action);
        } else if (action is WorkspaceItemAddAction) {
          unawaited(_createWorkspaceItem(context, action.kind));
        } else if (action is ViewTransferAction) {
          onTransfer(action.type);
        }
        popover.close();
      },
      onClosed: () {
        onEditing(false);
      },
    );
  }

  Future<void> _createWorkspaceItem(
    BuildContext context,
    WorkspaceItemAddKind kind,
  ) async {
    const service = WorkspaceItemService();
    final result = switch (kind) {
      WorkspaceItemAddKind.folder => service.createFolder(
          parentViewId: parentViewId,
          name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
        ),
      WorkspaceItemAddKind.file => service.createTextFile(
          parentViewId: parentViewId,
          name: LocaleKeys.workspaceFolderExplorer_untitledFile.tr(),
        ),
    };
    final created = await result;
    if (!context.mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  Future<void> _createWorkspaceFile(
    BuildContext context,
    WorkspaceFileMenuAction action,
  ) async {
    final created = await createWorkspaceFile(
      parentViewId: parentViewId,
      action: action,
    );
    if (created == null || !context.mounted) {
      return;
    }
    created.fold(
      (view) => context.read<TabsBloc>().openPlugin(view),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  void _showViewAddButtonActions(
    BuildContext context,
    ViewAddButtonActionWrapper action,
  ) {
    onSelected(action.pluginBuilder, null, null, true, true);
  }

  void _showViewImportAction(
    BuildContext context,
    ViewImportActionWrapper action,
  ) {
    showImportPanel(
      parentViewId,
      context,
      (type, name, initialDataBytes) {
        onSelected(action.pluginBuilder, null, null, true, false);
      },
    );
  }
}

class ViewAddButtonActionWrapper extends ActionCell {
  ViewAddButtonActionWrapper({
    required this.pluginBuilder,
  });

  final PluginBuilder pluginBuilder;

  @override
  Widget? leftIcon(Color iconColor) => FlowySvg(
        pluginBuilder.icon,
        size: const Size.square(16),
      );

  @override
  String get name => switch (pluginBuilder.pluginType) {
        PluginType.document => LocaleKeys.workspaceFolderExplorer_newPage.tr(),
        PluginType.grid => LocaleKeys.workspaceFolderExplorer_newTable.tr(),
        _ => pluginBuilder.menuName,
      };

  PluginType get pluginType => pluginBuilder.pluginType;
}

class ViewImportActionWrapper extends ActionCell {
  ViewImportActionWrapper({
    required this.pluginBuilder,
  });

  final DocumentPluginBuilder pluginBuilder;

  @override
  Widget? leftIcon(Color iconColor) => const FlowySvg(FlowySvgs.icon_import_s);

  @override
  String get name => LocaleKeys.moreAction_import.tr();
}

enum WorkspaceItemAddKind {
  folder,
  file,
}

/// The "New file" entry, which opens a submenu with every supported file type.
class WorkspaceFileAddAction extends PopoverActionCell {
  WorkspaceFileAddAction({required this.onCreate});

  final void Function(WorkspaceFileMenuAction action) onCreate;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        Icons.note_add_outlined,
        color: iconColor,
        size: 17,
      );

  @override
  Widget? rightIcon(Color iconColor) => Icon(
        Icons.chevron_right_rounded,
        color: iconColor,
        size: 16,
      );

  @override
  String get name => LocaleKeys.workspaceFolderExplorer_newFile.tr();

  @override
  PopoverActionCellBuilder get builder =>
      (context, parentController, controller) => WorkspaceFileKindMenu(
            onSelected: (action) {
              controller.close();
              parentController.close();
              onCreate(action);
            },
          );
}

/// The list of creatable and uploadable file types.
class WorkspaceFileKindMenu extends StatelessWidget {
  const WorkspaceFileKindMenu({super.key, required this.onSelected});

  final ValueChanged<WorkspaceFileMenuAction> onSelected;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final iconColor = theme.colorScheme.onSurface;
    final children = <Widget>[];
    WorkspaceFileSource? section;
    for (final action in workspaceFileMenuActions) {
      if (action.source != section) {
        if (section != null) {
          children.add(
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              child: FlowyDivider(),
            ),
          );
        }
        section = action.source;
        children.add(
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 4),
            child: Text(
              action.source.heading.toUpperCase(),
              style: TextStyle(
                fontSize: 10.5,
                letterSpacing: 0.6,
                fontWeight: FontWeight.w600,
                color: theme.hintColor,
              ),
            ),
          ),
        );
      }
      children.add(
        HoverButton(
          itemHeight: ActionListSizes.itemHeight,
          leftIcon: Icon(action.icon, color: iconColor, size: 17),
          name: action.label,
          onTap: () => onSelected(action),
        ),
      );
    }

    return ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: 210,
        // The list is long enough to run past a short window, so it scrolls
        // instead of overflowing the popover.
        maxHeight: MediaQuery.sizeOf(context).height * 0.62,
      ),
      child: IntrinsicWidth(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      ),
    );
  }
}

class WorkspaceItemAddAction extends ActionCell {
  WorkspaceItemAddAction(this.kind);

  final WorkspaceItemAddKind kind;

  @override
  Widget? leftIcon(Color iconColor) => Icon(
        kind == WorkspaceItemAddKind.folder
            ? Icons.create_new_folder_outlined
            : Icons.note_add_outlined,
        color: iconColor,
        size: 17,
      );

  @override
  String get name => kind == WorkspaceItemAddKind.folder
      ? LocaleKeys.workspaceFolderExplorer_newFolder.tr()
      : LocaleKeys.workspaceFolderExplorer_newFile.tr();
}

class ViewTransferAction extends ActionCell {
  ViewTransferAction(this.type);

  final ViewMoreActionType type;

  @override
  Widget? leftIcon(Color iconColor) => FlowySvg(
        type.leftIconSvg,
        color: iconColor,
        size: const Size.square(16),
      );

  @override
  String get name => type.name;
}

class _ViewAddDivider extends CustomActionCell {
  @override
  Widget buildWithContext(
    BuildContext context,
    PopoverController controller,
    PopoverMutex? mutex,
  ) {
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: FlowyDivider(),
    );
  }
}
