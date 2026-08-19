import 'dart:async';

import 'package:appflowy/plugins/collection/collection_kind_menu.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/context_menu_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/canvas/canvas_metadata.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/encryption/encryption.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/move_to/move_page_menu.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// ··· button beside the view name
class ViewMoreActionPopover extends StatelessWidget {
  const ViewMoreActionPopover({
    super.key,
    required this.view,
    this.controller,
    required this.onEditing,
    required this.onAction,
    required this.spaceType,
    required this.isExpanded,
    required this.buildChild,
    this.showAtCursor = false,
  });

  final ViewPB view;
  final PopoverController? controller;
  final void Function(bool value) onEditing;
  final void Function(ViewMoreActionType type, dynamic data) onAction;
  final FolderSpaceType spaceType;
  final bool isExpanded;
  final Widget Function(PopoverController) buildChild;
  final bool showAtCursor;

  @override
  Widget build(BuildContext context) {
    final wrappers = _buildActionTypeWrappers();
    return PopoverActionList<PopoverAction>(
      controller: controller,
      direction: PopoverDirection.bottomWithLeftAligned,
      offset: const Offset(0, 8),
      actions: [
        if (view.canContainWorkspaceItems) ...[
          CollectionAddAction(
            onCreate: (kind) => unawaited(_createCollection(context, kind)),
          ),
          ViewMoreActionTypeWrapper(
            ViewMoreActionType.divider,
            view,
            (_, __) {},
            useInlineMoveMenu: false,
          ),
        ],
        ...wrappers,
      ],
      constraints: const BoxConstraints(minWidth: 260),
      backgroundColor: ContextMenuSurfaceStyle.background(context),
      onPopupBuilder: () => onEditing(true),
      buildChild: buildChild,
      onSelected: (_, __) {},
      onClosed: () => onEditing(false),
      showAtCursor: showAtCursor,
    );
  }

  Future<void> _createCollection(
    BuildContext context,
    CollectionKind kind,
  ) async {
    onEditing(false);
    final created = await const CollectionService().createCollection(
      parentViewId: view.id,
      kind: kind,
      name: CollectionRegistry.typeFor(kind).defaultName,
    );
    if (!context.mounted) {
      return;
    }
    created.fold(
      (created) => context.read<TabsBloc>().openPlugin(created),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }

  List<ViewMoreActionTypeWrapper> _buildActionTypeWrappers() {
    final actionTypes = _buildActionTypes();
    return actionTypes.map(
      (e) {
        final actionWrapper = ViewMoreActionTypeWrapper(
          e,
          view,
          (controller, data) {
            onEditing(false);
            onAction(e, data);
            bool enableClose = true;
            if (data is SelectedEmojiIconResult) {
              if (data.keepOpen) enableClose = false;
            }
            if (enableClose) controller.close();
          },
          useInlineMoveMenu: false,
        );

        return actionWrapper;
      },
    ).toList();
  }

  List<ViewMoreActionType> _buildActionTypes() {
    final List<ViewMoreActionType> actionTypes = [];

    if (spaceType == FolderSpaceType.favorite) {
      actionTypes.addAll([
        ViewMoreActionType.unFavorite,
        ViewMoreActionType.divider,
        ViewMoreActionType.rename,
        ViewMoreActionType.copyTo,
        ViewMoreActionType.cut,
        ViewMoreActionType.moveTo,
        if (view.canContainWorkspaceItems &&
            WorkspaceItemClipboard.instance.hasData)
          ViewMoreActionType.pasteInto,
        ViewMoreActionType.divider,
        ViewMoreActionType.openInNewTab,
      ]);
    } else {
      actionTypes.add(
        view.isFavorite
            ? ViewMoreActionType.unFavorite
            : ViewMoreActionType.favorite,
      );

      actionTypes.addAll([
        ViewMoreActionType.divider,
        ViewMoreActionType.rename,
      ]);

      // Chat doesn't change icon and duplicate
      if (view.layout != ViewLayoutPB.Chat) {
        actionTypes.addAll([
          ViewMoreActionType.changeIcon,
          ViewMoreActionType.duplicate,
        ]);
      }

      // An ordinary page can be laid out as a dashboard instead. Turning one
      // back is offered on the dashboard itself, where it is unambiguous.
      if (view.layout == ViewLayoutPB.Document &&
          !view.isWorkspaceItem &&
          !view.isDashboard) {
        actionTypes.add(ViewMoreActionType.turnIntoDashboard);
      }

      // The same for a canvas: a page whose ideas turned out to be spatial
      // rather than linear should not have to be recreated.
      if (view.layout == ViewLayoutPB.Document &&
          !view.isWorkspaceItem &&
          !view.isDashboard &&
          !view.isCanvas) {
        actionTypes.add(ViewMoreActionType.turnIntoCanvas);
      }

      actionTypes.addAll([
        ViewMoreActionType.copyTo,
        ViewMoreActionType.cut,
        ViewMoreActionType.moveTo,
      ]);

      // Every kind of item can be put behind the workspace key: a page, a
      // folder, a collection, a table or a file.
      if (view.layout != ViewLayoutPB.Chat) {
        actionTypes.addAll([
          ViewMoreActionType.divider,
          if (view.isProtected)
            view.isLockedNow
                ? ViewMoreActionType.unlockItem
                : ViewMoreActionType.lockItem,
          view.isProtected
              ? ViewMoreActionType.decrypt
              : ViewMoreActionType.encrypt,
          ViewMoreActionType.divider,
        ]);
      }
      if (view.canContainWorkspaceItems &&
          WorkspaceItemClipboard.instance.hasData) {
        actionTypes.add(ViewMoreActionType.pasteInto);
      }
      actionTypes.addAll([
        ViewMoreActionType.delete,
        ViewMoreActionType.divider,
      ]);

      // Chat doesn't change collapse
      // Only show collapse all pages if the view has child views
      if (view.layout != ViewLayoutPB.Chat &&
          view.childViews.isNotEmpty &&
          isExpanded) {
        actionTypes.add(ViewMoreActionType.collapseAllPages);
        actionTypes.add(ViewMoreActionType.divider);
      }

      actionTypes.add(ViewMoreActionType.openInNewTab);
    }

    return actionTypes;
  }
}

class ViewMoreActionTypeWrapper extends CustomActionCell {
  ViewMoreActionTypeWrapper(
    this.inner,
    this.sourceView,
    this.onTap, {
    this.moveActionDirection,
    this.moveActionOffset,
    this.useInlineMoveMenu = true,
  });

  final ViewMoreActionType inner;
  final ViewPB sourceView;
  final void Function(PopoverController controller, dynamic data) onTap;

  // custom the move to action button
  final PopoverDirection? moveActionDirection;
  final Offset? moveActionOffset;
  final bool useInlineMoveMenu;

  @override
  Widget buildWithContext(
    BuildContext context,
    PopoverController controller,
    PopoverMutex? mutex,
  ) {
    Widget child;

    if (inner == ViewMoreActionType.divider) {
      child = _buildDivider();
    } else if (inner == ViewMoreActionType.lastModified) {
      child = _buildLastModified(context);
    } else if (inner == ViewMoreActionType.created) {
      child = _buildCreated(context);
    } else if (inner == ViewMoreActionType.changeIcon) {
      child = _buildEmojiActionButton(context, controller);
    } else if (inner == ViewMoreActionType.moveTo && useInlineMoveMenu) {
      child = _buildMoveToActionButton(context, controller);
    } else {
      child = _buildNormalActionButton(context, controller);
    }

    if (ViewMoreActionType.disableInLockedView.contains(inner) &&
        sourceView.isLocked) {
      child = LockPageButtonWrapper(
        child: child,
      );
    }

    return child;
  }

  Widget _buildNormalActionButton(
    BuildContext context,
    PopoverController controller,
  ) {
    return _buildActionButton(context, () => onTap(controller, null));
  }

  Widget _buildEmojiActionButton(
    BuildContext context,
    PopoverController controller,
  ) {
    final child = _buildActionButton(context, null);

    return AppFlowyPopover(
      constraints: BoxConstraints.loose(const Size(364, 356)),
      margin: const EdgeInsets.all(0),
      clickHandler: PopoverClickHandler.gestureDetector,
      popupBuilder: (_) => FlowyIconEmojiPicker(
        tabs: const [
          PickerTabType.emoji,
          PickerTabType.icon,
          PickerTabType.custom,
        ],
        documentId: sourceView.id,
        initialType: sourceView.icon.toEmojiIconData().type.toPickerTabType(),
        onSelectedEmoji: (result) => onTap(controller, result),
      ),
      child: child,
    );
  }

  Widget _buildMoveToActionButton(
    BuildContext context,
    PopoverController controller,
  ) {
    final userProfile = context.read<SpaceBloc>().userProfile;
    if (userProfile.workspaceType != WorkspaceTypePB.ServerW) {
      return const SizedBox.shrink();
    }
    return BlocProvider.value(
      value: context.read<SpaceBloc>(),
      child: BlocBuilder<SpaceBloc, SpaceState>(
        builder: (context, state) {
          final child = _buildActionButton(context, null);
          return AppFlowyPopover(
            constraints: const BoxConstraints(
              maxWidth: 260,
              maxHeight: 345,
            ),
            margin: const EdgeInsets.symmetric(
              horizontal: 14.0,
              vertical: 12.0,
            ),
            clickHandler: PopoverClickHandler.gestureDetector,
            direction:
                moveActionDirection ?? PopoverDirection.rightWithTopAligned,
            offset: moveActionOffset,
            popupBuilder: (_) {
              return BlocProvider.value(
                value: context.read<SpaceBloc>(),
                child: MovePageMenu(
                  sourceView: sourceView,
                  onSelected: (space, view) {
                    onTap(controller, (space, view));
                  },
                ),
              );
            },
            child: child,
          );
        },
      ),
    );
  }

  Widget _buildDivider() {
    return const Padding(
      padding: EdgeInsets.all(8.0),
      child: FlowyDivider(),
    );
  }

  Widget _buildLastModified(BuildContext context) {
    return Container(
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }

  Widget _buildCreated(BuildContext context) {
    return Container(
      height: 40,
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 8.0),
      child: const Column(
        crossAxisAlignment: CrossAxisAlignment.start,
      ),
    );
  }

  Widget _buildActionButton(
    BuildContext context,
    VoidCallback? onTap,
  ) {
    return AppMenuRow(
      label: inner.name,
      icon: inner.leftIcon,
      trailing: inner.rightIcon,
      tracksHover: true,
      destructive: inner == ViewMoreActionType.delete,
      onTap: onTap ?? () {},
    );
  }
}
