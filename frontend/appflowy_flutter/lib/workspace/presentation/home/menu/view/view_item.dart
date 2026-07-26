import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/favorite/favorite_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/rename_view/rename_view_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/prelude.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_transfer_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/move_to/workspace_destination_picker.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_style.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/draggable_view_item.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_action_type.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_add_button.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_more_action_button.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_inline_name_editor.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_item_icon.dart';
import 'package:appflowy/workspace/presentation/widgets/more_view_actions/widgets/lock_page_action.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flowy_infra_ui/style_widget/hover.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

typedef ViewItemOnSelected = void Function(BuildContext context, ViewPB view);
typedef ViewItemLeftIconBuilder = Widget Function(
  BuildContext context,
  ViewPB view,
);
typedef ViewItemRightIconsBuilder = List<Widget> Function(
  BuildContext context,
  ViewPB view,
);

enum IgnoreViewType { none, hide, disable }

class ViewItem extends StatelessWidget {
  const ViewItem({
    super.key,
    required this.view,
    this.parentView,
    required this.spaceType,
    required this.level,
    this.leftPadding = 10,
    required this.onSelected,
    this.onTertiarySelected,
    this.isFirstChild = false,
    this.isDraggable = true,
    required this.isFeedback,
    this.height = HomeSpaceViewSizes.viewHeight,
    this.isHoverEnabled = false,
    this.isPlaceholder = false,
    this.isHovered,
    this.shouldRenderChildren = true,
    this.leftIconBuilder,
    this.rightIconsBuilder,
    this.includeDefaultMoreAction = false,
    this.shouldLoadChildViews = true,
    this.isExpandedNotifier,
    this.extendBuilder,
    this.disableSelectedStatus,
    this.shouldIgnoreView,
    this.engagedInExpanding = false,
    this.enableRightClickContext = false,
  });

  final ViewPB view;
  final ViewPB? parentView;

  final FolderSpaceType spaceType;

  // indicate the level of the view item
  // used to calculate the left padding
  final int level;

  // the left padding of the view item for each level
  // the left padding of the each level = level * leftPadding
  final double leftPadding;

  // Selected by normal conventions
  final ViewItemOnSelected onSelected;

  // Selected by middle mouse button
  final ViewItemOnSelected? onTertiarySelected;

  // used for indicating the first child of the parent view, so that we can
  // add top border to the first child
  final bool isFirstChild;

  // it should be false when it's rendered as feedback widget inside DraggableItem
  final bool isDraggable;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final double height;

  final bool isHoverEnabled;

  // all the view movement depends on the [ViewItem] widget, so we have to add a
  // placeholder widget to receive the drop event when moving view across sections.
  final bool isPlaceholder;

  // used for control the expand/collapse icon
  final ValueNotifier<bool>? isHovered;

  // render the child views of the view
  final bool shouldRenderChildren;

  // custom the left icon widget, if it's null, the default expand/collapse icon will be used
  final ViewItemLeftIconBuilder? leftIconBuilder;

  // custom the right icon widget, if it's null, the default ... and + button will be used
  final ViewItemRightIconsBuilder? rightIconsBuilder;

  // keep the standard action menu when adding custom right-side actions
  final bool includeDefaultMoreAction;

  final bool shouldLoadChildViews;
  final PropertyValueNotifier<bool>? isExpandedNotifier;

  final List<Widget> Function(ViewPB view)? extendBuilder;

  // disable the selected status of the view item
  final bool? disableSelectedStatus;

  // ignore the views when rendering the child views
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;

  /// Whether to add right-click to show the view action context menu
  ///
  final bool enableRightClickContext;

  /// to record the ViewBlock which is expanded or collapsed
  final bool engagedInExpanding;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => ViewBloc(
        view: view,
        shouldLoadChildViews: shouldLoadChildViews,
        engagedInExpanding: engagedInExpanding,
      )..add(const ViewEvent.initial()),
      child: BlocConsumer<ViewBloc, ViewState>(
        listenWhen: (p, c) =>
            c.lastCreatedView != null &&
            p.lastCreatedView?.id != c.lastCreatedView!.id,
        listener: (context, state) =>
            context.read<TabsBloc>().openPlugin(state.lastCreatedView!),
        builder: (context, state) {
          // filter the child views that should be ignored
          List<ViewPB> childViews = state.view.childViews;
          if (shouldIgnoreView != null) {
            childViews = childViews
                .where((v) => shouldIgnoreView!(v) != IgnoreViewType.hide)
                .toList();
          }

          final Widget child = InnerViewItem(
            view: state.view,
            parentView: parentView,
            childViews: childViews,
            spaceType: spaceType,
            level: level,
            leftPadding: leftPadding,
            showActions: state.isEditing,
            enableRightClickContext: enableRightClickContext,
            isExpanded: state.isExpanded,
            disableSelectedStatus: disableSelectedStatus,
            onSelected: onSelected,
            onTertiarySelected: onTertiarySelected,
            isFirstChild: isFirstChild,
            isDraggable: isDraggable,
            isFeedback: isFeedback,
            height: height,
            isHoverEnabled: isHoverEnabled,
            isPlaceholder: isPlaceholder,
            isHovered: isHovered,
            shouldRenderChildren: shouldRenderChildren,
            leftIconBuilder: leftIconBuilder,
            rightIconsBuilder: rightIconsBuilder,
            includeDefaultMoreAction: includeDefaultMoreAction,
            isExpandedNotifier: isExpandedNotifier,
            extendBuilder: extendBuilder,
            shouldIgnoreView: shouldIgnoreView,
            engagedInExpanding: engagedInExpanding,
          );

          if (shouldIgnoreView?.call(view) == IgnoreViewType.disable) {
            return Opacity(
              opacity: 0.5,
              child: FlowyTooltip(
                message: LocaleKeys.space_cannotMovePageToDatabase.tr(),
                child: MouseRegion(
                  cursor: SystemMouseCursors.forbidden,
                  child: IgnorePointer(child: child),
                ),
              ),
            );
          }

          return child;
        },
      ),
    );
  }
}

// TODO: We shouldn't have local global variables
bool _isDragging = false;

class InnerViewItem extends StatefulWidget {
  const InnerViewItem({
    super.key,
    required this.view,
    required this.parentView,
    required this.childViews,
    required this.spaceType,
    this.isDraggable = true,
    this.isExpanded = true,
    required this.level,
    required this.leftPadding,
    required this.showActions,
    this.enableRightClickContext = false,
    required this.onSelected,
    this.onTertiarySelected,
    this.isFirstChild = false,
    required this.isFeedback,
    required this.height,
    this.isHoverEnabled = true,
    this.isPlaceholder = false,
    this.isHovered,
    this.shouldRenderChildren = true,
    required this.leftIconBuilder,
    required this.rightIconsBuilder,
    required this.includeDefaultMoreAction,
    this.isExpandedNotifier,
    required this.extendBuilder,
    this.disableSelectedStatus,
    this.engagedInExpanding = false,
    required this.shouldIgnoreView,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final List<ViewPB> childViews;
  final FolderSpaceType spaceType;

  final bool isDraggable;
  final bool isExpanded;
  final bool isFirstChild;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final int level;
  final double leftPadding;

  final bool showActions;
  final bool enableRightClickContext;
  final ViewItemOnSelected onSelected;
  final ViewItemOnSelected? onTertiarySelected;
  final double height;

  final bool isHoverEnabled;
  final bool isPlaceholder;
  final bool? disableSelectedStatus;
  final ValueNotifier<bool>? isHovered;
  final bool shouldRenderChildren;
  final ViewItemLeftIconBuilder? leftIconBuilder;
  final ViewItemRightIconsBuilder? rightIconsBuilder;
  final bool includeDefaultMoreAction;

  final PropertyValueNotifier<bool>? isExpandedNotifier;
  final List<Widget> Function(ViewPB view)? extendBuilder;
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;
  final bool engagedInExpanding;

  @override
  State<InnerViewItem> createState() => _InnerViewItemState();
}

class _InnerViewItemState extends State<InnerViewItem> {
  @override
  void initState() {
    super.initState();
    widget.isExpandedNotifier?.addListener(_collapseAllPages);
  }

  @override
  void dispose() {
    widget.isExpandedNotifier?.removeListener(_collapseAllPages);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = ValueListenableBuilder(
      valueListenable: getIt<MenuSharedState>().notifier,
      builder: (context, value, _) {
        final isSelected = value?.id == widget.view.id;
        return SingleInnerViewItem(
          view: widget.view,
          parentView: widget.parentView,
          level: widget.level,
          showActions: widget.showActions,
          enableRightClickContext: widget.enableRightClickContext,
          spaceType: widget.spaceType,
          onSelected: widget.onSelected,
          onTertiarySelected: widget.onTertiarySelected,
          isExpanded: widget.isExpanded,
          isDraggable: widget.isDraggable,
          leftPadding: widget.leftPadding,
          isFeedback: widget.isFeedback,
          height: widget.height,
          isPlaceholder: widget.isPlaceholder,
          isHovered: widget.isHovered,
          leftIconBuilder: widget.leftIconBuilder,
          rightIconsBuilder: widget.rightIconsBuilder,
          includeDefaultMoreAction: widget.includeDefaultMoreAction,
          extendBuilder: widget.extendBuilder,
          disableSelectedStatus: widget.disableSelectedStatus,
          shouldIgnoreView: widget.shouldIgnoreView,
          isSelected: isSelected,
        );
      },
    );

    // if the view is expanded and has child views, render its child views
    if (widget.isExpanded &&
        widget.shouldRenderChildren &&
        widget.childViews.isNotEmpty) {
      final children = widget.childViews.map((childView) {
        return ViewItem(
          key: ValueKey('${widget.spaceType.name} ${childView.id}'),
          parentView: widget.view,
          spaceType: widget.spaceType,
          isFirstChild: childView.id == widget.childViews.first.id,
          view: childView,
          level: widget.level + 1,
          enableRightClickContext: widget.enableRightClickContext,
          onSelected: widget.onSelected,
          onTertiarySelected: widget.onTertiarySelected,
          isDraggable: widget.isDraggable,
          disableSelectedStatus: widget.disableSelectedStatus,
          leftPadding: widget.leftPadding,
          isFeedback: widget.isFeedback,
          isPlaceholder: widget.isPlaceholder,
          isHovered: widget.isHovered,
          leftIconBuilder: widget.leftIconBuilder,
          rightIconsBuilder: widget.rightIconsBuilder,
          includeDefaultMoreAction: widget.includeDefaultMoreAction,
          extendBuilder: widget.extendBuilder,
          shouldIgnoreView: widget.shouldIgnoreView,
          engagedInExpanding: widget.engagedInExpanding,
        );
      }).toList();

      child = Column(
        mainAxisSize: MainAxisSize.min,
        children: [child, ...children],
      );
    }

    // wrap the child with DraggableItem if isDraggable is true
    if ((widget.isDraggable || widget.isPlaceholder) &&
        !isReferencedDatabaseView(widget.view, widget.parentView)) {
      child = DraggableViewItem(
        isFirstChild: widget.isFirstChild,
        view: widget.view,
        onDragging: (isDragging) => _isDragging = isDragging,
        onMove: widget.isPlaceholder
            ? (from, to) => moveViewCrossSpace(
                  context,
                  null,
                  widget.view,
                  widget.parentView,
                  widget.spaceType,
                  from,
                  to.parentViewId,
                )
            : null,
        feedback: (context) => Container(
          width: 250,
          decoration: BoxDecoration(
            color: Brightness.light == Theme.of(context).brightness
                ? Colors.white
                : Colors.black54,
            borderRadius: BorderRadius.circular(8),
          ),
          child: ViewItem(
            view: widget.view,
            parentView: widget.parentView,
            spaceType: widget.spaceType,
            level: widget.level,
            onSelected: widget.onSelected,
            onTertiarySelected: widget.onTertiarySelected,
            isDraggable: false,
            leftPadding: widget.leftPadding,
            isFeedback: true,
            enableRightClickContext: widget.enableRightClickContext,
            leftIconBuilder: widget.leftIconBuilder,
            rightIconsBuilder: widget.rightIconsBuilder,
            includeDefaultMoreAction: widget.includeDefaultMoreAction,
            extendBuilder: widget.extendBuilder,
            shouldIgnoreView: widget.shouldIgnoreView,
          ),
        ),
        child: child,
      );
    } else {
      // keep the same height of the DraggableItem
      child = Padding(
        padding: const EdgeInsets.only(top: kDraggableViewItemDividerHeight),
        child: child,
      );
    }

    return child;
  }

  void _collapseAllPages() {
    if (widget.isExpandedNotifier?.value == true) {
      context.read<ViewBloc>().add(const ViewEvent.collapseAllPages());
    }
  }
}

class SingleInnerViewItem extends StatefulWidget {
  const SingleInnerViewItem({
    super.key,
    required this.view,
    required this.parentView,
    required this.isExpanded,
    required this.level,
    required this.leftPadding,
    this.isDraggable = true,
    required this.spaceType,
    required this.showActions,
    this.enableRightClickContext = false,
    required this.onSelected,
    this.onTertiarySelected,
    required this.isFeedback,
    required this.height,
    this.isHoverEnabled = true,
    this.isPlaceholder = false,
    this.isHovered,
    required this.leftIconBuilder,
    required this.rightIconsBuilder,
    required this.includeDefaultMoreAction,
    required this.extendBuilder,
    required this.disableSelectedStatus,
    required this.shouldIgnoreView,
    required this.isSelected,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final bool isExpanded;

  // identify if the view item is rendered as feedback widget inside DraggableItem
  final bool isFeedback;

  final int level;
  final double leftPadding;

  final bool isDraggable;
  final bool showActions;
  final bool enableRightClickContext;
  final ViewItemOnSelected onSelected;
  final ViewItemOnSelected? onTertiarySelected;
  final FolderSpaceType spaceType;
  final double height;

  final bool isHoverEnabled;
  final bool isPlaceholder;
  final bool? disableSelectedStatus;
  final ValueNotifier<bool>? isHovered;
  final ViewItemLeftIconBuilder? leftIconBuilder;
  final ViewItemRightIconsBuilder? rightIconsBuilder;
  final bool includeDefaultMoreAction;

  final List<Widget> Function(ViewPB view)? extendBuilder;
  final IgnoreViewType Function(ViewPB view)? shouldIgnoreView;
  final bool isSelected;

  @override
  State<SingleInnerViewItem> createState() => _SingleInnerViewItemState();
}

class _SingleInnerViewItemState extends State<SingleInnerViewItem> {
  final controller = PopoverController();
  final viewMoreActionController = PopoverController();
  final rowFocusNode = FocusNode(debugLabel: 'sidebar-view-item');

  bool isIconPickerOpened = false;
  bool isRenaming = false;
  RenameViewBloc? renameViewBloc;
  int lastInlineRenameRequest = 0;

  DateTime? _lastClickTime;
  static const _clickThrottleDuration = Duration(milliseconds: 200);

  @override
  void initState() {
    super.initState();
    if (getIt.isRegistered<RenameViewBloc>()) {
      final bloc = getIt<RenameViewBloc>();
      renameViewBloc = bloc;
      lastInlineRenameRequest = bloc.inlineRenameRequests.value;
      bloc.inlineRenameRequests.addListener(_handleInlineRenameRequest);
    }
  }

  @override
  void didUpdateWidget(covariant SingleInnerViewItem oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id && isRenaming) {
      isRenaming = false;
    }
  }

  @override
  void dispose() {
    renameViewBloc?.inlineRenameRequests
        .removeListener(_handleInlineRenameRequest);
    rowFocusNode.dispose();
    super.dispose();
  }

  void _handleViewTap() {
    rowFocusNode.requestFocus();
    final now = DateTime.now();

    if (_lastClickTime != null) {
      final timeSinceLastClick = now.difference(_lastClickTime!);
      if (timeSinceLastClick < _clickThrottleDuration) {
        return;
      }
    }

    _lastClickTime = now;
    widget.onSelected(context, widget.view);
  }

  void _handleInlineRenameRequest() {
    final request = renameViewBloc?.inlineRenameRequests.value ?? 0;
    if (request == lastInlineRenameRequest) {
      return;
    }
    lastInlineRenameRequest = request;
    if (widget.isSelected) {
      _beginInlineRename();
    }
  }

  void _beginInlineRename() {
    if (!isRenaming && mounted) {
      setState(() => isRenaming = true);
    }
  }

  void _cancelInlineRename() {
    if (isRenaming && mounted) {
      setState(() => isRenaming = false);
    }
  }

  Future<bool> _submitInlineRename(String rawName) async {
    final name = rawName.trim();
    if (name.isEmpty) {
      return false;
    }
    if (name == widget.view.name) {
      _cancelInlineRename();
      return true;
    }
    final result = await ViewBackendService.updateView(
      viewId: widget.view.id,
      name: name,
    );
    return result.fold(
      (_) {
        _cancelInlineRename();
        return true;
      },
      (error) {
        Log.error(error.msg);
        if (mounted) {
          showSnackBarMessage(context, error.msg);
        }
        return false;
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isSelected = widget.isSelected;

    if (widget.disableSelectedStatus == true) {
      isSelected = false;
    }

    if (widget.isPlaceholder) {
      return const SizedBox(height: 4, width: double.infinity);
    }

    if (widget.isFeedback || !widget.isHoverEnabled) {
      return _buildViewItem(false);
    }

    return FlowyHover(
      style: HoverStyle(
        hoverColor: isSelected || widget.showActions
            ? SidebarStyle.selectedBackground(context)
            : Theme.of(context).colorScheme.secondary,
      ),
      resetHoverOnRebuild: widget.showActions || !isIconPickerOpened,
      buildWhenOnHover: () =>
          !widget.showActions && !_isDragging && !isIconPickerOpened,
      isSelected: () => widget.showActions || isSelected,
      builder: (_, onHover) => _buildViewItem(onHover),
    );
  }

  Widget _buildViewItem(bool onHover) {
    final nameStyle = SidebarTypography.textStyle(
      context,
      color: Theme.of(context).colorScheme.onSecondary,
      role: SidebarTextRole.page,
    );
    final name = WorkspaceInlineEditableText(
      text: widget.view.nameOrDefault,
      editingValue: widget.view.name,
      editing: isRenaming,
      onSubmitted: _submitInlineRename,
      onCancelled: _cancelInlineRename,
      onDoubleTap: _beginInlineRename,
      selectFileStem: widget.view.isWorkspaceFile,
      style: nameStyle,
    );
    final children = [
      const HSpace(HomeSpaceViewSizes.viewLeadingSpacing),
      // expand icon or placeholder
      widget.leftIconBuilder?.call(context, widget.view) ?? _buildLeftIcon(),
      const HSpace(HomeSpaceViewSizes.viewDisclosureIconSpacing),
      // icon
      _buildViewIconButton(),
      const HSpace(HomeSpaceViewSizes.viewIconTextSpacing),
      // title
      Expanded(
        child: widget.extendBuilder != null && !isRenaming
            ? Row(
                children: [
                  Flexible(child: name),
                  ...widget.extendBuilder!(widget.view),
                ],
              )
            : name,
      ),
    ];

    // hover action
    if (widget.showActions || onHover) {
      if (widget.rightIconsBuilder != null) {
        if (widget.includeDefaultMoreAction) {
          children.add(
            _buildViewMoreActionButton(
              context,
              viewMoreActionController,
              (_) => FlowyTooltip(
                message: LocaleKeys.menuAppHeader_moreButtonToolTip.tr(),
                child: FlowyIconButton(
                  width: 24,
                  icon: const FlowySvg(FlowySvgs.workspace_three_dots_s),
                  onPressed: viewMoreActionController.show,
                ),
              ),
            ),
          );
          children.add(const HSpace(8.0));
        }
        children.addAll(widget.rightIconsBuilder!(context, widget.view));
      } else {
        // ··· more action button
        children.add(
          _buildViewMoreActionButton(
            context,
            viewMoreActionController,
            (_) => FlowyTooltip(
              message: LocaleKeys.menuAppHeader_moreButtonToolTip.tr(),
              child: FlowyIconButton(
                width: 24,
                icon: const FlowySvg(FlowySvgs.workspace_three_dots_s),
                onPressed: viewMoreActionController.show,
              ),
            ),
          ),
        );
        children.add(const HSpace(8.0));
        children.add(_buildViewAddButton(context));
        children.add(const HSpace(4.0));
      }
    }

    final child = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onTap: isRenaming ? null : _handleViewTap,
      onTertiaryTapDown: (_) =>
          widget.onTertiarySelected?.call(context, widget.view),
      child: SizedBox(
        height: widget.height,
        child: Padding(
          padding: EdgeInsets.only(left: widget.level * widget.leftPadding),
          child: Listener(
            onPointerDown: (event) {
              if (event.buttons == kSecondaryMouseButton &&
                  widget.enableRightClickContext) {
                viewMoreActionController.showAt(
                  // We add some horizontal offset
                  event.position + const Offset(4, 0),
                );
              }
            },
            behavior: HitTestBehavior.opaque,
            child: Row(children: children),
          ),
        ),
      ),
    );

    return Focus(
      focusNode: rowFocusNode,
      onKeyEvent: (_, event) {
        if (event is KeyDownEvent &&
            !isRenaming &&
            widget.isSelected &&
            isWorkspaceRenameShortcut(
              Theme.of(context).platform,
              event.logicalKey,
            )) {
          _beginInlineRename();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: child,
    );
  }

  Widget _buildViewIconButton() {
    final iconData = widget.view.icon.toEmojiIconData();
    // A picture or a clip previews itself; dimming a thumbnail the way an icon
    // is dimmed would only make it muddy.
    final showsThumbnail = WorkspaceItemIcon.showsThumbnail(widget.view);
    final defaultIcon = widget.view.defaultIcon(
      size: const Size.square(HomeSpaceViewSizes.viewIconSize),
    );
    final icon = iconData.isNotEmpty
        ? RawEmojiIconWidget(
            emoji: iconData,
            emojiSize: HomeSpaceViewSizes.viewIconSize,
            lineHeight: HomeSpaceViewSizes.viewIconLineHeight /
                HomeSpaceViewSizes.viewIconSize,
          )
        : showsThumbnail
            ? defaultIcon
            : Opacity(
                opacity: HomeSpaceViewSizes.viewIconOpacity,
                child: defaultIcon,
              );

    final Widget child = AppFlowyPopover(
      offset: const Offset(20, 0),
      controller: controller,
      direction: PopoverDirection.rightWithCenterAligned,
      constraints: BoxConstraints.loose(const Size(364, 356)),
      margin: const EdgeInsets.all(0),
      onClose: () => setState(() => isIconPickerOpened = false),
      child: GestureDetector(
        // prevent the tap event from being passed to the parent widget
        onTap: () {},
        child: FlowyTooltip(
          message: LocaleKeys.document_plugins_cover_changeIcon.tr(),
          child: SizedBox.square(
            dimension: HomeSpaceViewSizes.viewIconSize,
            child: icon,
          ),
        ),
      ),
      popupBuilder: (context) {
        isIconPickerOpened = true;
        return FlowyIconEmojiPicker(
          initialType: iconData.type.toPickerTabType(),
          tabs: const [
            PickerTabType.emoji,
            PickerTabType.icon,
            PickerTabType.custom,
          ],
          documentId: widget.view.id,
          onSelectedEmoji: (r) {
            ViewBackendService.updateViewIcon(
              view: widget.view,
              viewIcon: r.data,
            );
            if (!r.keepOpen) controller.close();
          },
        );
      },
    );

    if (widget.view.isLocked) {
      return LockPageButtonWrapper(
        child: child,
      );
    }

    return child;
  }

  // > button or · button
  // show > if the view is expandable.
  // show · if the view can't contain child views.
  Widget _buildLeftIcon() {
    return ViewItemDefaultLeftIcon(
      view: widget.view,
      parentView: widget.parentView,
      isExpanded: widget.isExpanded,
      leftPadding: widget.leftPadding,
      isHovered: widget.isHovered,
    );
  }

  // + button
  Widget _buildViewAddButton(BuildContext context) {
    return FlowyTooltip(
      message: LocaleKeys.menuAppHeader_addPageTooltip.tr(),
      child: ViewAddButton(
        parentViewId: widget.view.id,
        sourceView: widget.view,
        onEditing: (value) =>
            context.read<ViewBloc>().add(ViewEvent.setIsEditing(value)),
        onSelected: _onSelected,
        onTransfer: (action) => unawaited(_handleTransferAction(action)),
      ),
    );
  }

  void _onSelected(
    PluginBuilder pluginBuilder,
    String? name,
    List<int>? initialDataBytes,
    bool openAfterCreated,
    bool createNewView,
  ) {
    final viewBloc = context.read<ViewBloc>();

    // the name of new document should be empty
    final viewName = ![ViewLayoutPB.Document, ViewLayoutPB.Chat]
            .contains(pluginBuilder.layoutType)
        ? LocaleKeys.menuAppHeader_defaultNewPageName.tr()
        : '';
    viewBloc.add(
      ViewEvent.createView(
        viewName,
        pluginBuilder.layoutType!,
        openAfterCreated: openAfterCreated,
        section: widget.spaceType.toViewSectionPB,
      ),
    );

    viewBloc.add(const ViewEvent.setIsExpanded(true));
  }

  // ··· more action button
  Widget _buildViewMoreActionButton(
    BuildContext context,
    PopoverController controller,
    Widget Function(PopoverController) buildChild,
  ) {
    return ViewMoreActionPopover(
      view: widget.view,
      controller: controller,
      isExpanded: widget.isExpanded,
      spaceType: widget.spaceType,
      onEditing: (value) =>
          context.read<ViewBloc>().add(ViewEvent.setIsEditing(value)),
      buildChild: buildChild,
      onAction: (action, data) async {
        switch (action) {
          case ViewMoreActionType.favorite:
          case ViewMoreActionType.unFavorite:
            context.read<FavoriteBloc>().add(FavoriteEvent.toggle(widget.view));
            break;
          case ViewMoreActionType.rename:
            _beginInlineRename();
            break;
          case ViewMoreActionType.delete:
            // get if current page contains published child views
            final (containPublishedPage, _) =
                await ViewBackendService.containPublishedPage(widget.view);
            if (containPublishedPage && context.mounted) {
              await showConfirmDeletionDialog(
                context: context,
                name: widget.view.name,
                description: LocaleKeys.publish_containsPublishedPage.tr(),
                onConfirm: () =>
                    context.read<ViewBloc>().add(const ViewEvent.delete()),
              );
            } else if (context.mounted) {
              context.read<ViewBloc>().add(const ViewEvent.delete());
            }
            break;
          case ViewMoreActionType.duplicate:
            context.read<ViewBloc>().add(const ViewEvent.duplicate());
            break;
          case ViewMoreActionType.openInNewTab:
            context.read<TabsBloc>().openTab(widget.view);
            break;
          case ViewMoreActionType.collapseAllPages:
            context.read<ViewBloc>().add(const ViewEvent.collapseAllPages());
            break;
          case ViewMoreActionType.changeIcon:
            if (data is! SelectedEmojiIconResult) {
              return;
            }
            await ViewBackendService.updateViewIcon(
              view: widget.view,
              viewIcon: data.data,
            );
            break;
          case ViewMoreActionType.moveTo:
          case ViewMoreActionType.copyTo:
          case ViewMoreActionType.cut:
          case ViewMoreActionType.pasteInto:
            await _handleTransferAction(action);
            break;
          default:
            throw UnsupportedError('$action is not supported');
        }
      },
    );
  }

  Future<void> _handleTransferAction(ViewMoreActionType action) async {
    final clipboard = WorkspaceItemClipboard.instance;
    if (action == ViewMoreActionType.cut) {
      clipboard.cut([widget.view]);
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_cutReady.tr(),
      );
      return;
    }

    final transferService = WorkspaceItemTransferService(clipboard: clipboard);
    if (action == ViewMoreActionType.pasteInto) {
      final result = await transferService.pasteTo(
        destinationId: widget.view.id,
      );
      if (!mounted) {
        return;
      }
      result.fold(
        (_) => showSnackBarMessage(
          context,
          LocaleKeys.workspaceFolderExplorer_pastedSuccessfully.tr(),
        ),
        (error) => showSnackBarMessage(context, error.msg),
      );
      return;
    }

    final workspaceState = context.read<UserWorkspaceBloc>().state;
    final currentWorkspace = workspaceState.currentWorkspace;
    if (currentWorkspace == null || currentWorkspace.workspaceId.isEmpty) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      );
      return;
    }
    final workspaceId = currentWorkspace.workspaceId;
    final currentSpace = context.read<SpaceBloc>().state.currentSpace;
    final useCurrentSpace =
        widget.spaceType == FolderSpaceType.unknown && currentSpace != null;
    final rootId = useCurrentSpace ? currentSpace.id : workspaceId;
    final rootName = useCurrentSpace
        ? currentSpace.name
        : workspaceState.isCollabWorkspaceOn
            ? widget.spaceType == FolderSpaceType.private
                ? LocaleKeys.sideBar_private.tr()
                : LocaleKeys.sideBar_workspace.tr()
            : currentWorkspace.name;

    await Future<void>.delayed(Duration.zero);
    if (!mounted) {
      return;
    }
    final operation = action == ViewMoreActionType.moveTo
        ? WorkspaceDestinationOperation.move
        : WorkspaceDestinationOperation.copy;
    final destinationId = await showWorkspaceDestinationPicker(
      context: context,
      sourceViews: [widget.view],
      rootId: rootId,
      rootName: rootName,
      rootIcon: useCurrentSpace ? null : currentWorkspace.icon,
      operation: operation,
    );
    if (!mounted || destinationId == null) {
      return;
    }

    final result = switch (operation) {
      WorkspaceDestinationOperation.move => transferService.moveTo(
          views: [widget.view],
          destinationId: destinationId,
        ),
      WorkspaceDestinationOperation.copy => transferService.copyTo(
          views: [widget.view],
          destinationId: destinationId,
        ),
    };
    final transferred = await result;
    if (!mounted) {
      return;
    }
    transferred.fold(
      (_) => showSnackBarMessage(
        context,
        operation == WorkspaceDestinationOperation.move
            ? LocaleKeys.workspaceFolderExplorer_movedSuccessfully.tr()
            : LocaleKeys.workspaceFolderExplorer_copiedSuccessfully.tr(),
      ),
      (error) => showSnackBarMessage(context, error.msg),
    );
  }
}

class _DotIconWidget extends StatelessWidget {
  const _DotIconWidget();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(6.0),
      child: Container(
        width: 4,
        height: 4,
        decoration: BoxDecoration(
          color: Theme.of(context).iconTheme.color,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

// workaround: we should use view.isEndPoint or something to check if the view can contain child views. But currently, we don't have that field.
bool isReferencedDatabaseView(ViewPB view, ViewPB? parentView) {
  if (parentView == null) {
    return false;
  }
  return view.layout.isDatabaseView && parentView.layout.isDatabaseView;
}

void moveViewCrossSpace(
  BuildContext context,
  ViewPB? toSpace,
  ViewPB view,
  ViewPB? parentView,
  FolderSpaceType spaceType,
  ViewPB from,
  String toId,
) {
  if (isReferencedDatabaseView(view, parentView)) {
    return;
  }

  if (from.id == toId) {
    return;
  }

  final currentSpace = context.read<SpaceBloc>().state.currentSpace;
  if (currentSpace != null &&
      toSpace != null &&
      currentSpace.id != toSpace.id) {
    Log.info(
      'Move view(${from.name}) to another space(${toSpace.name}), unpublish the view',
    );
    context.read<ViewBloc>().add(const ViewEvent.unpublish(sync: false));

    switchToSpaceNotifier.value = toSpace;
  }

  context.read<ViewBloc>().add(ViewEvent.move(from, toId, null, null, null));
}

class ViewItemDefaultLeftIcon extends StatelessWidget {
  const ViewItemDefaultLeftIcon({
    super.key,
    required this.view,
    required this.parentView,
    required this.isExpanded,
    required this.leftPadding,
    required this.isHovered,
  });

  final ViewPB view;
  final ViewPB? parentView;
  final bool isExpanded;
  final double leftPadding;
  final ValueNotifier<bool>? isHovered;

  @override
  Widget build(BuildContext context) {
    if (isReferencedDatabaseView(view, parentView)) {
      return const _DotIconWidget();
    }

    if (context.read<ViewBloc>().state.view.childViews.isEmpty) {
      return HSpace(leftPadding);
    }

    final child = FlowyHover(
      child: GestureDetector(
        child: FlowySvg(
          isExpanded
              ? FlowySvgs.view_item_expand_s
              : FlowySvgs.view_item_unexpand_s,
          size: const Size.square(16.0),
        ),
        onTap: () =>
            context.read<ViewBloc>().add(ViewEvent.setIsExpanded(!isExpanded)),
      ),
    );

    if (isHovered != null) {
      return ValueListenableBuilder<bool>(
        valueListenable: isHovered!,
        builder: (_, isHovered, child) =>
            Opacity(opacity: isHovered ? 1.0 : 0.0, child: child),
        child: child,
      );
    }

    return child;
  }
}
