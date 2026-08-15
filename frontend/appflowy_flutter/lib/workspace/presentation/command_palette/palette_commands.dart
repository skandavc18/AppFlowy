import 'dart:async';

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_delete_button.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_folder_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_section_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

/// Every command the palette offers, in the order they read best.
///
/// [context] is the palette's own context and stays alive until the palette is
/// dismissed, so a command may use it before it calls `dismiss`. Anything that
/// opens a route of its own must dismiss first and then reach for the root
/// navigator, or the pop would close that route instead of the palette.
List<PaletteCommand> buildPaletteCommands(BuildContext context) {
  final workspaceBloc = context.read<UserWorkspaceBloc?>();
  final spaceBloc = context.read<SpaceBloc?>();
  final openView = getIt<MenuSharedState>().latestOpenView;
  final canCreate = workspaceBloc != null;

  return [
    if (canCreate) ...[
      _create(
        context,
        id: 'new_page',
        title: LocaleKeys.commandPalette_command_newPage.tr(),
        icon: Icons.description_rounded,
        kind: SidebarRootCreateKind.page,
        layout: ViewLayoutPB.Document,
        shortcut: _shortcut('N'),
        keywords: const ['document', 'doc', 'note', 'add'],
      ),
      _create(
        context,
        id: 'new_table',
        title: LocaleKeys.commandPalette_command_newTable.tr(),
        icon: Icons.table_chart_rounded,
        kind: SidebarRootCreateKind.table,
        layout: ViewLayoutPB.Grid,
        keywords: const ['grid', 'database', 'spreadsheet', 'add'],
      ),
      _create(
        context,
        id: 'new_board',
        title: LocaleKeys.commandPalette_command_newBoard.tr(),
        icon: Icons.view_kanban_rounded,
        kind: SidebarRootCreateKind.board,
        layout: ViewLayoutPB.Board,
        keywords: const ['kanban', 'database', 'add'],
      ),
      _create(
        context,
        id: 'new_calendar',
        title: LocaleKeys.commandPalette_command_newCalendar.tr(),
        icon: Icons.calendar_month_rounded,
        kind: SidebarRootCreateKind.calendar,
        layout: ViewLayoutPB.Calendar,
        keywords: const ['date', 'schedule', 'database', 'add'],
      ),
      _create(
        context,
        id: 'new_chat',
        title: LocaleKeys.commandPalette_command_newChat.tr(),
        icon: Icons.forum_rounded,
        kind: SidebarRootCreateKind.chat,
        layout: ViewLayoutPB.Chat,
        keywords: const ['ai', 'assistant', 'ask', 'add'],
      ),
      _create(
        context,
        id: 'new_dashboard',
        title: LocaleKeys.commandPalette_command_newDashboard.tr(),
        icon: Icons.dashboard_rounded,
        kind: SidebarRootCreateKind.dashboard,
        keywords: const ['widgets', 'home', 'add'],
      ),
      _create(
        context,
        id: 'new_canvas',
        title: LocaleKeys.commandPalette_command_newCanvas.tr(),
        icon: Icons.dashboard_customize_rounded,
        kind: SidebarRootCreateKind.canvas,
        keywords: const ['board', 'whiteboard', 'infinite', 'add'],
      ),
      _create(
        context,
        id: 'new_folder',
        title: LocaleKeys.commandPalette_command_newFolder.tr(),
        icon: Icons.create_new_folder_rounded,
        kind: SidebarRootCreateKind.folder,
        keywords: const ['directory', 'add'],
      ),
    ],
    PaletteCommand(
      id: 'open_trash',
      title: LocaleKeys.commandPalette_command_openTrash.tr(),
      icon: Icons.delete_outline_rounded,
      group: PaletteCommandGroup.navigate,
      keywords: const ['deleted', 'bin', 'restore'],
      run: (palette) {
        palette.dismiss();
        getIt<MenuSharedState>().latestOpenView = null;
        getIt<TabsBloc>().add(
          TabsEvent.openPlugin(plugin: makePlugin(pluginType: PluginType.trash)),
        );
      },
    ),
    if (spaceBloc != null && spaceBloc.state.spaces.length > 1)
      PaletteCommand(
        id: 'next_space',
        title: LocaleKeys.commandPalette_command_nextSpace.tr(),
        icon: Icons.swap_horiz_rounded,
        group: PaletteCommandGroup.navigate,
        shortcut: _shortcut('O'),
        keywords: const ['space', 'switch', 'workspace'],
        run: (palette) {
          palette.dismiss();
          switchToTheNextSpace.value++;
        },
      ),
    PaletteCommand(
      id: 'close_tab',
      title: LocaleKeys.commandPalette_command_closeTab.tr(),
      icon: Icons.tab_rounded,
      group: PaletteCommandGroup.navigate,
      shortcut: _shortcut('W'),
      keywords: const ['tab', 'close'],
      run: (palette) {
        palette.dismiss();
        getIt<TabsBloc>().add(const TabsEvent.closeCurrentTab());
      },
    ),
    if (PaletteDeleteButton.canDelete(openView))
      PaletteCommand(
        id: 'trash_current_page',
        title: LocaleKeys.commandPalette_command_trashCurrentPage
            .tr(args: [openView!.nameOrDefault]),
        icon: Icons.delete_outline_rounded,
        group: PaletteCommandGroup.navigate,
        keywords: const ['delete', 'remove', 'trash', 'bin'],
        run: (palette) async {
          palette.dismiss();
          final result =
              await ViewBackendService.deleteView(viewId: openView.id);
          result.fold(
            (_) => showToastNotification(
              message: LocaleKeys.commandPalette_movedToTrash.tr(),
            ),
            (error) => showToastNotification(
              message: error.msg.isEmpty
                  ? LocaleKeys.commandPalette_couldNotDelete.tr()
                  : error.msg,
              type: ToastificationType.error,
            ),
          );
        },
      ),
    PaletteCommand(
      id: 'toggle_theme',
      title: LocaleKeys.commandPalette_command_toggleTheme.tr(),
      icon: Icons.dark_mode_rounded,
      group: PaletteCommandGroup.view,
      shortcut: _shortcut('L', shift: true),
      keywords: const ['dark', 'light', 'appearance', 'theme'],
      run: (palette) {
        final cubit =
            AppGlobals.rootNavKey.currentContext?.read<AppearanceSettingsCubit>();
        palette.dismiss();
        cubit?.toggleThemeMode();
      },
    ),
    PaletteCommand(
      id: 'toggle_sidebar',
      title: LocaleKeys.commandPalette_command_toggleSidebar.tr(),
      icon: Icons.view_sidebar_rounded,
      group: PaletteCommandGroup.view,
      shortcut: _shortcut('\\'),
      keywords: const ['menu', 'collapse', 'hide', 'panel'],
      run: (palette) {
        palette.dismiss();
        collapseMenuNotifier.value++;
      },
    ),
    PaletteCommand(
      id: 'zoom_in',
      title: LocaleKeys.commandPalette_command_zoomIn.tr(),
      icon: Icons.zoom_in_rounded,
      group: PaletteCommandGroup.view,
      shortcut: _shortcut('+'),
      keywords: const ['scale', 'bigger', 'larger'],
      run: (palette) {
        palette.dismiss();
        unawaited(scaleAppWithStep(0.1));
      },
    ),
    PaletteCommand(
      id: 'zoom_out',
      title: LocaleKeys.commandPalette_command_zoomOut.tr(),
      icon: Icons.zoom_out_rounded,
      group: PaletteCommandGroup.view,
      shortcut: _shortcut('-'),
      keywords: const ['scale', 'smaller'],
      run: (palette) {
        palette.dismiss();
        unawaited(scaleAppWithStep(-0.1));
      },
    ),
    PaletteCommand(
      id: 'reset_zoom',
      title: LocaleKeys.commandPalette_command_resetZoom.tr(),
      icon: Icons.youtube_searched_for_rounded,
      group: PaletteCommandGroup.view,
      shortcut: _shortcut('0'),
      keywords: const ['scale', 'default', 'actual size'],
      run: (palette) {
        palette.dismiss();
        unawaited(scaleApp(1));
      },
    ),
    if (workspaceBloc != null) ...[
      _settings(
        workspaceBloc,
        id: 'open_settings',
        title: LocaleKeys.commandPalette_command_openSettings.tr(),
        icon: Icons.settings_rounded,
        shortcut: _shortcut(','),
        keywords: const ['preferences', 'options', 'configure'],
      ),
      _settings(
        workspaceBloc,
        id: 'account_settings',
        title: LocaleKeys.commandPalette_command_accountSettings.tr(),
        icon: Icons.person_rounded,
        page: SettingsPage.account,
        keywords: const ['profile', 'sign out', 'email', 'password'],
      ),
      _settings(
        workspaceBloc,
        id: 'workspace_settings',
        title: LocaleKeys.commandPalette_command_workspaceSettings.tr(),
        icon: Icons.workspaces_rounded,
        page: SettingsPage.workspace,
        keywords: const ['appearance', 'theme', 'font', 'language'],
      ),
      _settings(
        workspaceBloc,
        id: 'ai_settings',
        title: LocaleKeys.commandPalette_command_aiSettings.tr(),
        icon: Icons.auto_awesome_rounded,
        page: SettingsPage.ai,
        keywords: const ['model', 'provider', 'assistant', 'local ai'],
      ),
      _settings(
        workspaceBloc,
        id: 'shortcut_settings',
        title: LocaleKeys.commandPalette_command_shortcuts.tr(),
        icon: Icons.keyboard_rounded,
        page: SettingsPage.shortcuts,
        keywords: const ['keys', 'keybindings', 'hotkeys'],
      ),
    ],
    PaletteCommand(
      id: 'ask_ai',
      title: LocaleKeys.commandPalette_command_askAI.tr(),
      icon: Icons.auto_awesome_rounded,
      group: PaletteCommandGroup.ai,
      keywords: const ['chat', 'assistant', 'question', 'ai'],
      run: (palette) => startPaletteAIChat(context, dismiss: palette.dismiss),
    ),
  ];
}

/// The words that head each section of the command list.
String paletteCommandGroupLabel(PaletteCommandGroup group) => switch (group) {
      PaletteCommandGroup.create =>
        LocaleKeys.commandPalette_group_create.tr(),
      PaletteCommandGroup.navigate =>
        LocaleKeys.commandPalette_group_navigate.tr(),
      PaletteCommandGroup.view => LocaleKeys.commandPalette_group_view.tr(),
      PaletteCommandGroup.workspace =>
        LocaleKeys.commandPalette_group_workspace.tr(),
      PaletteCommandGroup.ai => LocaleKeys.commandPalette_group_ai.tr(),
    };

PaletteCommand _create(
  BuildContext context, {
  required String id,
  required String title,
  required IconData icon,
  required SidebarRootCreateKind kind,
  ViewLayoutPB? layout,
  String shortcut = '',
  List<String> keywords = const [],
}) {
  return PaletteCommand(
    id: id,
    title: title,
    icon: icon,
    group: PaletteCommandGroup.create,
    shortcut: shortcut,
    keywords: keywords,
    run: (palette) => createPaletteView(
      context,
      dismiss: palette.dismiss,
      kind: kind,
      layout: layout,
    ),
  );
}

/// Creates an object from the palette and opens it.
///
/// A space knows where a new page belongs; without one it lands at the root of
/// the workspace, which is what the sidebar's own `+` does.
Future<void> createPaletteView(
  BuildContext context, {
  required VoidCallback dismiss,
  required SidebarRootCreateKind kind,
  ViewLayoutPB? layout,
}) async {
  final spaceBloc = context.mounted ? context.read<SpaceBloc?>() : null;
  if (layout != null && (spaceBloc?.state.spaces.isNotEmpty ?? false)) {
    dismiss();
    spaceBloc!.add(
      SpaceEvent.createPage(
        name: '',
        layout: layout,
        index: 0,
        openAfterCreate: true,
      ),
    );
    return;
  }
  if (!context.mounted || context.read<UserWorkspaceBloc?>() == null) {
    dismiss();
    return;
  }
  final view = await createSidebarRootItem(
    context,
    spaceType: FolderSpaceType.public,
    kind: kind,
  );
  dismiss();
  if (view != null) {
    getIt<TabsBloc>().openPlugin(view);
  }
}

/// Opens a fresh AI chat, wherever this workspace keeps its pages.
Future<void> startPaletteAIChat(
  BuildContext context, {
  required VoidCallback dismiss,
}) =>
    createPaletteView(
      context,
      dismiss: dismiss,
      kind: SidebarRootCreateKind.chat,
      layout: ViewLayoutPB.Chat,
    );

PaletteCommand _settings(
  UserWorkspaceBloc workspaceBloc, {
  required String id,
  required String title,
  required IconData icon,
  SettingsPage? page,
  String shortcut = '',
  List<String> keywords = const [],
}) {
  return PaletteCommand(
    id: id,
    title: title,
    icon: icon,
    group: PaletteCommandGroup.workspace,
    shortcut: shortcut,
    keywords: ['settings', ...keywords],
    run: (palette) {
      palette.dismiss();
      final host = AppGlobals.rootNavKey.currentContext;
      if (host == null) {
        return;
      }
      showSettingsDialog(
        host,
        userWorkspaceBloc: workspaceBloc,
        initPage: page,
      );
    },
  );
}

String _shortcut(String key, {bool shift = false}) {
  if (UniversalPlatform.isMacOS) {
    return shift ? '⌘⇧$key' : '⌘$key';
  }
  return shift ? 'Ctrl Shift $key' : 'Ctrl $key';
}
