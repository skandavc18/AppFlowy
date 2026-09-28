import 'dart:math' as math;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/application/tab_bar_bloc.dart';
import 'package:appflowy/plugins/database/find/database_find_navigation.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/mention/mention_page_block.dart';
import 'package:appflowy/shared/context_menu_surface_style.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialog_v2.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/pop_up_action.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:provider/provider.dart';

import 'tab_bar_add_button.dart';

class TabBarHeader extends StatelessWidget {
  const TabBarHeader({
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return PreviewToolbarRegion(
      child: BlocBuilder<DatabaseTabBarBloc, DatabaseTabBarState>(
        builder: (context, state) {
          final settings = pageSettingBarFromState(context, state);
          final emptySettings = settings is SizedBox &&
              settings.width == 0 &&
              settings.height == 0;
          final access = context.watch<PageAccessLevelBloc?>();
          final canAdd = !state.parentView.isLocked &&
              databaseViewMutationsAllowed(access?.state);
          return DatabaseTabHeaderLayout(
            viewCount: state.tabBars.length,
            naturalTabsWidth: state.tabBars.fold<double>(
              DatabaseViewTabMetrics.addWidth,
              (width, tab) =>
                  width +
                  DatabaseViewTabMetrics.widthFor(context, tab.view) +
                  WorkspaceTokens.space1,
            ),
            tabs: DatabaseTabBar(
              trailing: AddDatabaseViewButton(
                key: const ValueKey('database-add-view'),
                enabled: canAdd,
                onTap: (kind) {
                  final bloc = context.read<DatabaseTabBarBloc>();
                  if (bloc.isClosed ||
                      bloc.state.parentView.isLocked ||
                      !databaseViewMutationsAllowed(
                        context.read<PageAccessLevelBloc?>()?.state,
                      )) {
                    return;
                  }
                  final fromExtension = kind.extensionView;
                  if (fromExtension != null) {
                    bloc.createExtensionTableView(fromExtension);
                  } else if (kind.charted) {
                    bloc.createChartView(kind.label);
                  } else if (kind.mapped) {
                    bloc.createMapView(kind.label);
                  } else if (kind.slided) {
                    bloc.createSlideView(kind.label);
                  } else if (kind.tableView != null) {
                    bloc.createTableView(kind.tableView!, kind.label);
                  } else {
                    bloc.add(DatabaseTabBarEvent.createView(kind.layout, null));
                  }
                },
              ),
            ),
            settings: emptySettings ? null : PreviewToolbar(child: settings),
          );
        },
      ),
    );
  }

  Widget pageSettingBarFromState(
    BuildContext context,
    DatabaseTabBarState state,
  ) {
    if (state.selectedIndex < 0 ||
        state.selectedIndex >= state.tabBars.length) {
      return const SizedBox.shrink();
    }
    final tabBar = state.tabBars[state.selectedIndex];
    final controller =
        state.tabBarControllerByViewId[tabBar.viewId]?.controller;
    if (controller == null) return const SizedBox.shrink();
    return tabBar.builder.settingBar(context, controller);
  }
}

/// Label-sized view tabs; the same measurement allocates their header slot.
abstract final class DatabaseViewTabMetrics {
  static const addWidth = 36.0;
  static const maxWidth = 224.0;
  static const largeViewCount = 20;

  static TextStyle labelStyle(BuildContext context) =>
      WorkspaceTypography.style(context, WorkspaceTextRole.metadata)
          .copyWith(fontSize: 13, height: 1.2);

  static double widthFor(BuildContext context, ViewPB view) {
    final painter = TextPainter(
      text: TextSpan(text: view.nameOrDefault, style: labelStyle(context)),
      maxLines: 1,
      textScaler: MediaQuery.textScalerOf(context),
      textDirection: Directionality.of(context),
    )..layout();
    final width = (painter.width + 46).clamp(96.0, maxWidth).toDouble();
    painter.dispose();
    return width;
  }
}

/// Only header geometry changes across widths. Both slots, their popover
/// anchors, and all keyed tabs keep the same ancestors. There is no view picker
/// and no horizontal scrolling. Very large sets remain fully present in a
/// bounded vertical viewport with an explicit scrollbar, not a feature limit.
class DatabaseTabHeaderLayout extends StatefulWidget {
  const DatabaseTabHeaderLayout({
    super.key,
    required this.viewCount,
    required this.naturalTabsWidth,
    required this.tabs,
    this.settings,
  });

  final int viewCount;
  final double naturalTabsWidth;
  final Widget tabs;
  final Widget? settings;

  @override
  State<DatabaseTabHeaderLayout> createState() =>
      _DatabaseTabHeaderLayoutState();
}

class _DatabaseTabHeaderLayoutState extends State<DatabaseTabHeaderLayout> {
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.hasBoundedWidth
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        final scale = MediaQuery.textScalerOf(context).scale(13) / 13;
        final settingsWidth =
            widget.settings == null ? 0.0 : math.min(width, 176 * scale);
        final separateSettings =
            widget.naturalTabsWidth + settingsWidth + WorkspaceTokens.space2 >
                width;
        final tabsWidth = widget.settings == null || separateSettings
            ? width
            : math.max(0.0, width - settingsWidth - WorkspaceTokens.space2);
        final large = widget.viewCount > DatabaseViewTabMetrics.largeViewCount;
        return ConstrainedBox(
          key: const ValueKey('database-view-header'),
          constraints: BoxConstraints(
            maxHeight: large
                ? (MediaQuery.sizeOf(context).height * 0.45)
                    .clamp(160.0, 480.0)
                    .toDouble()
                : double.infinity,
          ),
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: Scrollbar(
              controller: _scrollController,
              thumbVisibility: large,
              trackVisibility: large,
              child: SingleChildScrollView(
                controller: _scrollController,
                primary: false,
                padding: EdgeInsetsDirectional.only(end: large ? 12 : 0),
                child: FocusTraversalGroup(
                  child: Wrap(
                    spacing: WorkspaceTokens.space2,
                    runSpacing: WorkspaceTokens.space1,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: math.max(0.0, tabsWidth - (large ? 12 : 0)),
                        child: widget.tabs,
                      ),
                      if (widget.settings != null)
                        SizedBox(
                          width: math.max(
                            0.0,
                            (separateSettings ? width : settingsWidth) -
                                (large ? 12 : 0),
                          ),
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              child: widget.settings,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class DatabaseTabBar extends StatelessWidget {
  const DatabaseTabBar({super.key, this.trailing});

  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<DatabaseTabBarBloc, DatabaseTabBarState>(
      builder: (context, state) {
        return Wrap(
          key: const ValueKey('database-view-tabs-wrap'),
          spacing: WorkspaceTokens.space1,
          runSpacing: WorkspaceTokens.space1,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (var index = 0; index < state.tabBars.length; index++)
              DatabaseTabBarItem(
                key: ValueKey(state.tabBars[index].viewId),
                view: state.tabBars[index].view,
                width: DatabaseViewTabMetrics.widthFor(
                  context,
                  state.tabBars[index].view,
                ),
                isSelected: state.selectedIndex == index,
                onTap: (selectedView) {
                  context
                      .read<DatabaseTabBarBloc>()
                      .add(DatabaseTabBarEvent.selectView(selectedView.id));
                },
              ),
            if (trailing != null) trailing!,
          ],
        );
      },
    );
  }
}

class DatabaseTabBarItem extends StatelessWidget {
  const DatabaseTabBarItem({
    super.key,
    required this.view,
    required this.isSelected,
    required this.onTap,
    this.width,
  });

  final ViewPB view;
  final bool isSelected;
  final Function(ViewPB) onTap;
  final double? width;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      selected: isSelected,
      child: ConstrainedBox(
        constraints:
            const BoxConstraints(maxWidth: DatabaseViewTabMetrics.maxWidth),
        child: SizedBox(
          width: width,
          child: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: TabBarItemButton(
                  view: view,
                  isSelected: isSelected,
                  onTap: () => onTap(view),
                ),
              ),
              if (isSelected)
                Positioned(
                  bottom: 0,
                  left: WorkspaceTokens.space2,
                  right: WorkspaceTokens.space2,
                  child: Container(
                    height: 2,
                    decoration: BoxDecoration(
                      color: WorkspacePalette.of(context).secondaryText,
                      borderRadius: BorderRadius.circular(1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class TabBarItemButton extends StatefulWidget {
  const TabBarItemButton({
    super.key,
    required this.view,
    required this.isSelected,
    required this.onTap,
  });

  final ViewPB view;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  State<TabBarItemButton> createState() => _TabBarItemButtonState();
}

class _TabBarItemButtonState extends State<TabBarItemButton> {
  final menuController = PopoverController();
  final iconController = PopoverController();
  VoidCallback? _releasePreview;

  bool _canEditWith(
    PageAccessLevelState? access,
    DatabaseTabBarBloc? database,
  ) {
    if (widget.view.isLocked ||
        !databaseViewMutationsAllowed(access) ||
        (database?.isClosed ?? false)) {
      return false;
    }
    if (database == null) return true;
    return !database.state.parentView.isLocked &&
        database.state.tabBars.any(
          (tab) => tab.viewId == widget.view.id && !tab.view.isLocked,
        );
  }

  bool get _canEdit =>
      mounted &&
      _canEditWith(
        context.read<PageAccessLevelBloc?>()?.state,
        context.read<DatabaseTabBarBloc?>(),
      );

  bool _canEditView(String viewId) => _canEdit && widget.view.id == viewId;

  void _showMenu() {
    if (_releasePreview != null || !_canEdit) return;
    _releasePreview = PreviewToolbarRegion.hold(context);
    menuController.show();
  }

  void _release() {
    _releasePreview?.call();
    _releasePreview = null;
  }

  void _closeIfDisabled() {
    if (_releasePreview == null || _canEdit) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _canEdit) return;
      iconController.close();
      menuController.close();
      _release();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _closeIfDisabled();
  }

  @override
  void didUpdateWidget(TabBarItemButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    _closeIfDisabled();
  }

  @override
  void dispose() {
    final release = _releasePreview;
    _releasePreview = null;
    if (release != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => release());
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canEdit = _canEditWith(
      context.watch<PageAccessLevelBloc?>()?.state,
      context.watch<DatabaseTabBarBloc?>(),
    );
    final palette = WorkspacePalette.of(context);
    final color =
        widget.isSelected ? palette.primaryText : palette.secondaryText;
    return AppFlowyPopover(
      controller: menuController,
      constraints: const BoxConstraints(
        minWidth: 120,
        maxWidth: 460,
        maxHeight: 300,
      ),
      direction: PopoverDirection.bottomWithCenterAligned,
      triggerActions: PopoverTriggerFlags.none,
      onClose: _release,
      popupBuilder: (_) {
        final viewId = widget.view.id;
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: ColoredBox(
            color: ContextMenuSurfaceStyle.background(context),
            child: IntrinsicHeight(
              child: IntrinsicWidth(
                child: Column(
                  children: [
                    ActionCellWidget(
                      action: TabBarViewAction.rename,
                      itemHeight: ActionListSizes.itemHeight,
                      onSelected: (action) {
                        if (!_canEditView(viewId)) return;
                        showAFTextFieldDialog(
                          context: context,
                          title: LocaleKeys.menuAppHeader_renameDialog.tr(),
                          initialValue: widget.view.nameOrDefault,
                          onConfirm: (newValue) {
                            if (!_canEditView(viewId)) return;
                            context.read<DatabaseTabBarBloc>().add(
                                  DatabaseTabBarEvent.renameView(
                                    viewId,
                                    newValue,
                                  ),
                                );
                          },
                        );
                        menuController.close();
                      },
                    ),
                    AppFlowyPopover(
                      controller: iconController,
                      triggerActions: PopoverTriggerFlags.none,
                      direction: PopoverDirection.rightWithCenterAligned,
                      constraints: BoxConstraints.loose(const Size(364, 356)),
                      margin: const EdgeInsets.all(0),
                      child: ActionCellWidget(
                        action: TabBarViewAction.changeIcon,
                        itemHeight: ActionListSizes.itemHeight,
                        onSelected: (action) {
                          if (!_canEditView(viewId)) return;
                          iconController.show();
                        },
                      ),
                      popupBuilder: (context) {
                        return FlowyIconEmojiPicker(
                          tabs: const [PickerTabType.icon],
                          enableBackgroundColorSelection: false,
                          onSelectedEmoji: (r) {
                            if (!_canEditView(viewId)) return;
                            ViewBackendService.updateViewIcon(
                              view: widget.view,
                              viewIcon: r.data,
                            );
                            if (!r.keepOpen) {
                              iconController.close();
                              menuController.close();
                            }
                          },
                        );
                      },
                    ),
                    ActionCellWidget(
                      action: TabBarViewAction.delete,
                      itemHeight: ActionListSizes.itemHeight,
                      onSelected: (action) {
                        if (!_canEditView(viewId)) return;
                        NavigatorAlertDialog(
                          title: LocaleKeys.grid_deleteView.tr(),
                          confirm: () {
                            if (!_canEditView(viewId)) return;
                            context.read<DatabaseTabBarBloc>().add(
                                  DatabaseTabBarEvent.deleteView(
                                    viewId,
                                  ),
                                );
                          },
                        ).show(context);
                        menuController.close();
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
      child: IntrinsicWidth(
        child: Tooltip(
          message: widget.view.nameOrDefault,
          excludeFromSemantics: true,
          preferBelow: false,
          child: GestureDetector(
            onSecondaryTap: canEdit ? _showMenu : null,
            child: TextButton(
              style: WorkspaceChrome.controlStyle(context).copyWith(
                foregroundColor: WidgetStatePropertyAll(color),
                iconColor: WidgetStatePropertyAll(color),
                minimumSize: const WidgetStatePropertyAll(Size(0, 34)),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                alignment: AlignmentDirectional.centerStart,
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(6),
                  ),
                ),
              ),
              onPressed: () {
                if (widget.isSelected) _showMenu();
                widget.onTap.call();
              },
              child: Semantics(
                selected: widget.isSelected,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _buildViewIcon(),
                    const SizedBox(width: 7),
                    Flexible(
                      child: DatabaseFindAnchor(
                        target: DatabaseFindTarget.title(widget.view.id),
                        enabled: widget.isSelected,
                        child: Text(
                          widget.view.nameOrDefault,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: DatabaseViewTabMetrics.labelStyle(context)
                              .copyWith(color: color),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildViewIcon() {
    final iconData = widget.view.icon.toEmojiIconData();
    Widget icon;
    if (iconData.isEmpty) {
      icon = DSWorkspaceGlyph.adapt(widget.view.defaultIcon(), size: 16);
    } else {
      icon = RawEmojiIconWidget(
        emoji: iconData,
        emojiSize: 14.0,
      );
    }
    final isReference =
        Provider.of<ReferenceState?>(context)?.isReference ?? false;
    final iconWidget = icon;
    return isReference
        ? Stack(
            children: [
              iconWidget,
              const Positioned(
                right: 0,
                bottom: 0,
                child: FlowySvg(
                  FlowySvgs.referenced_page_s,
                  blendMode: BlendMode.dstIn,
                ),
              ),
            ],
          )
        : iconWidget;
  }
}

enum TabBarViewAction implements ActionCell {
  rename,
  changeIcon,
  delete;

  @override
  String get name {
    switch (this) {
      case TabBarViewAction.rename:
        return LocaleKeys.disclosureAction_rename.tr();
      case TabBarViewAction.changeIcon:
        return LocaleKeys.disclosureAction_changeIcon.tr();
      case TabBarViewAction.delete:
        return LocaleKeys.disclosureAction_delete.tr();
    }
  }

  Widget icon(Color iconColor) {
    switch (this) {
      case TabBarViewAction.rename:
        return DSWorkspaceGlyph.named('pen', color: iconColor);
      case TabBarViewAction.changeIcon:
        return DSWorkspaceGlyph.named('emoji', color: iconColor);
      case TabBarViewAction.delete:
        return DSWorkspaceGlyph.named('trash', color: iconColor);
    }
  }

  @override
  Widget? leftIcon(Color iconColor) => icon(iconColor);

  @override
  Widget? rightIcon(Color iconColor) => null;

  @override
  Color? textColor(BuildContext context) {
    return null;
  }
}
