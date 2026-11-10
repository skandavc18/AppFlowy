import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/application/mobile_router.dart';
import 'package:appflowy/mobile/presentation/bottom_sheet/bottom_sheet.dart';
import 'package:appflowy/mobile/presentation/home/section_folder/mobile_home_section_folder_header.dart';
import 'package:appflowy/mobile/presentation/page_item/mobile_view_item.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/menu/sidebar_sections_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/view/view_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/home/home_sizes.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class MobileSectionFolder extends StatelessWidget {
  const MobileSectionFolder({
    super.key,
    required this.title,
    required this.views,
    required this.spaceType,
    this.isWorkspaceRoot = false,
  });

  final String title;
  final List<ViewPB> views;
  final FolderSpaceType spaceType;
  final bool isWorkspaceRoot;

  @override
  Widget build(BuildContext context) {
    return BlocProvider<FolderBloc>(
      create: (context) => FolderBloc(type: spaceType)
        ..add(
          const FolderEvent.initial(),
        ),
      child: BlocBuilder<FolderBloc, FolderState>(
        builder: (context, state) {
          return Column(
            children: [
              SizedBox(
                height: HomeSpaceViewSizes.mViewHeight,
                child: MobileSectionFolderHeader(
                  title: title,
                  isExpanded: context.read<FolderBloc>().state.isExpanded,
                  onPressed: () => context
                      .read<FolderBloc>()
                      .add(const FolderEvent.expandOrUnExpand()),
                  onAdded: () => _showCreatePageMenu(context),
                  isWorkspaceRoot: isWorkspaceRoot,
                ),
              ),
              if (state.isExpanded)
                Padding(
                  padding: const EdgeInsets.only(
                    left: HomeSpaceViewSizes.leftPadding,
                  ),
                  child: _Pages(
                    views: views,
                    spaceType: spaceType,
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  /// Offers every kind of page desktop makes, as a space's "+" does.
  void _showCreatePageMenu(BuildContext context) {
    final workspaceId =
        context.read<UserWorkspaceBloc>().state.currentWorkspace?.workspaceId;
    if (workspaceId == null || workspaceId.isEmpty) {
      _createNewPage(context);
      return;
    }
    final section = spaceType.toViewSectionPB;
    showMobileBottomSheet(
      context,
      showHeader: true,
      title: title,
      showDragHandle: true,
      showCloseButton: true,
      useRootNavigator: true,
      showDivider: false,
      enableScrollable: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (sheetContext) => AddNewPageWidgetBottomSheet(
        // The workspace itself is the parent of a section's top-level pages.
        view: ViewPB(id: workspaceId, name: title),
        section: section,
        onAction: (layout) {
          Navigator.of(sheetContext).pop();
          if (layout == ViewLayoutPB.Document) {
            _createNewPage(context);
          } else {
            unawaited(_createRootPage(context, workspaceId, section, layout));
          }
        },
      ),
    );
  }

  Future<void> _createRootPage(
    BuildContext context,
    String workspaceId,
    ViewSectionPB section,
    ViewLayoutPB layout,
  ) async {
    final result = await ViewBackendService.createView(
      layoutType: layout,
      parentViewId: workspaceId,
      name: layout == ViewLayoutPB.Chat
          ? ''
          : LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
      section: section,
    );
    final view = result.toNullable();
    if (view == null || !context.mounted) return;
    context.read<FolderBloc>().add(
          const FolderEvent.expandOrUnExpand(isExpanded: true),
        );
    await context.pushView(view);
  }

  void _createNewPage(BuildContext context) {
    context.read<SidebarSectionsBloc>().add(
          SidebarSectionsEvent.createRootViewInSection(
            name: LocaleKeys.menuAppHeader_defaultNewPageName.tr(),
            index: 0,
            viewSection: spaceType.toViewSectionPB,
          ),
        );
    context.read<FolderBloc>().add(
          const FolderEvent.expandOrUnExpand(isExpanded: true),
        );
  }
}

class _Pages extends StatelessWidget {
  const _Pages({
    required this.views,
    required this.spaceType,
  });

  final List<ViewPB> views;
  final FolderSpaceType spaceType;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: views
          .map(
            (view) => MobileViewItem(
              key: ValueKey(
                '${FolderSpaceType.private.name} ${view.id}',
              ),
              spaceType: spaceType,
              isFirstChild: view.id == views.first.id,
              view: view,
              level: 0,
              leftPadding: HomeSpaceViewSizes.leftPadding,
              isFeedback: false,
              onSelected: (v) => context.pushView(
                v,
                tabs: [
                  PickerTabType.emoji,
                  PickerTabType.icon,
                  PickerTabType.custom,
                ].map((e) => e.name).toList(),
              ),
              endActionPane: (context) {
                final view = context.read<ViewBloc>().state.view;
                return buildEndActionPane(
                  context,
                  [
                    MobilePaneActionType.more,
                    if (view.layout == ViewLayoutPB.Document)
                      MobilePaneActionType.add,
                  ],
                  spaceType: spaceType,
                  needSpace: false,
                  spaceRatio: 5,
                );
              },
            ),
          )
          .toList(),
    );
  }
}
