import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_home.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_service.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/toast.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// The workspace's own front door.
///
/// The home dashboard is a preference, not a fixed page, so this opens
/// whichever dashboard was chosen and makes one the first time it is asked
/// for. Nothing is created until somebody presses it.
class SidebarHomeButton extends StatefulWidget {
  const SidebarHomeButton({super.key});

  @override
  State<SidebarHomeButton> createState() => _SidebarHomeButtonState();
}

class _SidebarHomeButtonState extends State<SidebarHomeButton> {
  bool _opening = false;

  @override
  void initState() {
    super.initState();
    unawaited(DashboardHome.instance.ensureLoaded());
  }

  @override
  Widget build(BuildContext context) => SidebarNavItem(
        icon: SidebarIcon.home,
        label: LocaleKeys.dashboard_home.tr(),
        onTap: _opening ? null : () => unawaited(_open()),
      );

  Future<void> _open() async {
    setState(() => _opening = true);
    try {
      final existing = await _existingHome();
      if (existing != null) {
        if (mounted) {
          context.read<TabsBloc>().openPlugin(existing);
        }
        return;
      }
      await _createHome();
    } finally {
      if (mounted) {
        setState(() => _opening = false);
      }
    }
  }

  Future<ViewPB?> _existingHome() async {
    await DashboardHome.instance.ensureLoaded();
    final viewId = DashboardHome.instance.viewId;
    if (viewId == null || viewId.isEmpty) {
      return null;
    }
    final result = await ViewBackendService.getView(viewId);
    return result.fold((view) => view, (_) => null);
  }

  /// A first home is worth arriving at, so it opens on the personal template
  /// rather than on an empty board.
  Future<void> _createHome() async {
    final parent = _resolveParent();
    if (parent == null) {
      return;
    }
    final created = await DashboardService.create(
      parentViewId: parent.id,
      name: LocaleKeys.dashboard_home.tr(),
      section: parent.section,
      document: dashboardTemplateFor('personal')?.build(),
    );
    if (created == null) {
      if (mounted) {
        showSnackBarMessage(
          context,
          LocaleKeys.workspaceFolderExplorer_operationFailed.tr(),
        );
      }
      return;
    }
    await DashboardHome.instance.toggle(created.id);
    if (mounted) {
      context.read<TabsBloc>().openPlugin(created);
    }
  }

  /// Where a root item belongs: the open space, or the workspace itself.
  ({String id, ViewSectionPB? section})? _resolveParent() {
    final workspaceState = context.read<UserWorkspaceBloc>().state;
    final space = context.read<SpaceBloc>().state.currentSpace;
    final parentId = space?.id ?? workspaceState.currentWorkspace?.workspaceId;
    if (parentId == null || parentId.isEmpty) {
      showSnackBarMessage(
        context,
        LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      );
      return null;
    }
    return (
      id: parentId,
      section: space == null
          ? workspaceState.isCollabWorkspaceOn
              ? ViewSectionPB.Private
              : ViewSectionPB.Public
          : null,
    );
  }
}
