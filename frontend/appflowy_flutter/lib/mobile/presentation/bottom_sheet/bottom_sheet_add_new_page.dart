import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/widgets/widgets.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class AddNewPageWidgetBottomSheet extends StatelessWidget {
  const AddNewPageWidgetBottomSheet({
    super.key,
    required this.view,
    required this.onAction,
    this.section,
  });

  final ViewPB view;

  /// The section new pages join when [view] is the workspace itself.
  final ViewSectionPB? section;
  final void Function(ViewLayoutPB layout) onAction;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        FlowyOptionTile.text(
          text: LocaleKeys.document_menuName.tr(),
          height: 52.0,
          leftIcon: const FlowySvg(
            FlowySvgs.icon_document_s,
            size: Size.square(20),
          ),
          showTopBorder: false,
          showBottomBorder: false,
          onTap: () => onAction(ViewLayoutPB.Document),
        ),
        FlowyOptionTile.text(
          text: LocaleKeys.grid_menuName.tr(),
          height: 52.0,
          leftIcon: const FlowySvg(
            FlowySvgs.icon_grid_s,
            size: Size.square(20),
          ),
          showTopBorder: false,
          showBottomBorder: false,
          onTap: () => onAction(ViewLayoutPB.Grid),
        ),
        FlowyOptionTile.text(
          text: LocaleKeys.board_menuName.tr(),
          height: 52.0,
          leftIcon: const FlowySvg(
            FlowySvgs.icon_board_s,
            size: Size.square(20),
          ),
          showTopBorder: false,
          showBottomBorder: false,
          onTap: () => onAction(ViewLayoutPB.Board),
        ),
        FlowyOptionTile.text(
          text: LocaleKeys.calendar_menuName.tr(),
          height: 52.0,
          leftIcon: const FlowySvg(
            FlowySvgs.icon_calendar_s,
            size: Size.square(20),
          ),
          showTopBorder: false,
          showBottomBorder: false,
          onTap: () => onAction(ViewLayoutPB.Calendar),
        ),
        FlowyOptionTile.text(
          text: LocaleKeys.chat_newChat.tr(),
          height: 52.0,
          leftIcon: const FlowySvg(
            FlowySvgs.chat_ai_page_s,
            size: Size.square(20),
          ),
          showTopBorder: false,
          showBottomBorder: false,
          onTap: () => onAction(ViewLayoutPB.Chat),
        ),
        // Everything else the desktop sidebar's "+" makes.
        _tile(
          icon: Icons.dashboard_rounded,
          text: LocaleKeys.dashboard_name.tr(),
          onTap: () => _create(
            context,
            (parent) => ViewBackendService.createView(
              layoutType: ViewLayoutPB.Document,
              parentViewId: parent,
              name: LocaleKeys.dashboard_defaultName.tr(),
              section: section,
              extra: DashboardMetadata.newExtra(),
            ).then(_viewOrToast),
          ),
        ),
        _tile(
          icon: Icons.dashboard_customize_rounded,
          text: LocaleKeys.canvas_name.tr(),
          onTap: () => _create(
            context,
            (parent) => ViewBackendService.createView(
              layoutType: ViewLayoutPB.Document,
              parentViewId: parent,
              name: LocaleKeys.canvas_defaultName.tr(),
              section: section,
              extra: CanvasMetadata.newExtra(),
            ).then(_viewOrToast),
          ),
        ),
        _tile(
          icon: workspaceAddFolderIcon,
          text: LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
          onTap: () => _create(
            context,
            (parent) => const WorkspaceItemService()
                .createFolder(
                  parentViewId: parent,
                  name: LocaleKeys.workspaceFolderExplorer_untitledFolder.tr(),
                  section: section,
                )
                .then(_viewOrToast),
          ),
        ),
        _SectionHeader(LocaleKeys.collections_plural.tr()),
        for (final type in CollectionRegistry.types)
          _tile(
            icon: type.icon,
            text: type.label,
            onTap: () => _create(
              context,
              (parent) => const CollectionService()
                  .createCollection(
                    parentViewId: parent,
                    kind: type.kind,
                    name: type.defaultName,
                    section: section,
                  )
                  .then(_viewOrToast),
            ),
          ),
        _SectionHeader(LocaleKeys.workspaceFolderExplorer_newTable.tr()),
        for (final kind in WorkspaceTableKind.values)
          if (!_coreTableKinds.contains(kind))
            _tile(
              icon: workspaceTableKindIcon(kind),
              text: workspaceTableKindLabel(kind),
              onTap: () => _create(
                context,
                (parent) => createWorkspaceDatabase(
                  parentViewId: parent,
                  kind: kind,
                  section: section,
                ),
              ),
            ),
        _SectionHeader(LocaleKeys.workspaceFolderExplorer_newFile.tr()),
        for (final kind in WorkspaceFileKind.values)
          if (kind.isBlankCreatable)
            _tile(
              icon: kind.icon,
              text: kind.label,
              onTap: () => _create(
                context,
                (parent) => createWorkspaceFile(
                  parentViewId: parent,
                  section: section,
                  action:
                      WorkspaceFileMenuAction(kind, WorkspaceFileSource.create),
                ).then(_fileOrToast),
              ),
            ),
        _tile(
          icon: Icons.upload_file_rounded,
          text: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
          onTap: () => _create(
            context,
            (parent) => createWorkspaceFile(
              parentViewId: parent,
              section: section,
              action: const WorkspaceFileMenuAction(
                WorkspaceFileKind.file,
                WorkspaceFileSource.upload,
              ),
            ).then(_fileOrToast),
          ),
        ),
      ],
    );
  }

  Widget _tile({
    required IconData icon,
    required String text,
    required VoidCallback onTap,
  }) =>
      FlowyOptionTile.text(
        text: text,
        height: 52.0,
        leftIcon: Icon(icon, size: 20),
        showTopBorder: false,
        showBottomBorder: false,
        onTap: onTap,
      );

  /// Closes the sheet, makes the page under [view], then opens it.
  Future<void> _create(
    BuildContext context,
    Future<ViewPB?> Function(String parentViewId) create,
  ) async {
    Navigator.of(context).pop();
    final created = await create(view.id);
    final root = AppGlobals.rootNavKey.currentContext;
    if (created == null || root == null || !root.mounted) return;
    await root.pushView(created);
  }

  static ViewPB? _viewOrToast(FlowyResult<ViewPB, FlowyError> result) =>
      result.fold(
        (view) => view,
        (error) {
          showToastNotification(
            message: error.msg,
            type: ToastificationType.error,
          );
          return null;
        },
      );

  /// A cancelled upload makes nothing and says nothing.
  static ViewPB? _fileOrToast(FlowyResult<ViewPB, FlowyError>? result) =>
      result == null ? null : _viewOrToast(result);
}

/// Grid, board and calendar already have tiles of their own above.
const _coreTableKinds = {
  WorkspaceTableKind.table,
  WorkspaceTableKind.board,
  WorkspaceTableKind.calendar,
};

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Align(
        alignment: AlignmentDirectional.centerStart,
        child: Text(
          title,
          style: theme.textTheme.labelMedium?.copyWith(color: theme.hintColor),
        ),
      ),
    );
  }
}
