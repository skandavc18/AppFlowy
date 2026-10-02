import 'dart:async';

import 'package:appflowy/extensions/application/action_definition.dart';
import 'package:appflowy/extensions/application/action_run.dart';
import 'package:appflowy/extensions/application/action_scheduler.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/dart/dart_extension_host.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/settings/appearance/appearance_cubit.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/templates/template_registry.dart';
import 'package:appflowy/workspace/application/templates/template_service.dart';
import 'package:appflowy/workspace/application/templates/workspace_template.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_creator.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_delete_button.dart';
import 'package:appflowy/workspace/presentation/home/hotkeys.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_folder_header.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/folder/_section_folder.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
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
        phrases: const ['create page', 'add page', 'new document', 'new doc'],
      ),
      _create(
        context,
        id: 'new_table',
        title: LocaleKeys.commandPalette_command_newTable.tr(),
        icon: Icons.table_chart_rounded,
        kind: SidebarRootCreateKind.table,
        layout: ViewLayoutPB.Grid,
        keywords: const ['grid', 'database', 'spreadsheet', 'add'],
        phrases: const ['create table', 'add table', 'new grid'],
      ),
      _create(
        context,
        id: 'new_board',
        title: LocaleKeys.commandPalette_command_newBoard.tr(),
        icon: Icons.view_kanban_rounded,
        kind: SidebarRootCreateKind.board,
        layout: ViewLayoutPB.Board,
        keywords: const ['kanban', 'database', 'add'],
        phrases: const ['create board', 'add board', 'new kanban'],
      ),
      _create(
        context,
        id: 'new_calendar',
        title: LocaleKeys.commandPalette_command_newCalendar.tr(),
        icon: Icons.calendar_month_rounded,
        kind: SidebarRootCreateKind.calendar,
        layout: ViewLayoutPB.Calendar,
        keywords: const ['date', 'schedule', 'database', 'add'],
        phrases: const ['create calendar', 'add calendar'],
      ),
      _create(
        context,
        id: 'new_chat',
        title: LocaleKeys.commandPalette_command_newChat.tr(),
        icon: Icons.forum_rounded,
        kind: SidebarRootCreateKind.chat,
        layout: ViewLayoutPB.Chat,
        keywords: const ['ai', 'assistant', 'ask', 'add'],
        phrases: const ['create chat', 'new chat'],
      ),
      _create(
        context,
        id: 'new_dashboard',
        title: LocaleKeys.commandPalette_command_newDashboard.tr(),
        icon: Icons.dashboard_rounded,
        kind: SidebarRootCreateKind.dashboard,
        keywords: const ['widgets', 'home', 'add'],
        phrases: const ['create dashboard', 'add dashboard'],
      ),
      _create(
        context,
        id: 'new_canvas',
        title: LocaleKeys.commandPalette_command_newCanvas.tr(),
        icon: Icons.dashboard_customize_rounded,
        kind: SidebarRootCreateKind.canvas,
        keywords: const ['board', 'whiteboard', 'infinite', 'add'],
        phrases: const ['create canvas', 'add canvas', 'new whiteboard'],
      ),
      _create(
        context,
        id: 'new_folder',
        title: LocaleKeys.commandPalette_command_newFolder.tr(),
        icon: Icons.create_new_folder_rounded,
        kind: SidebarRootCreateKind.folder,
        keywords: const ['directory', 'add'],
        phrases: const ['create folder', 'add folder', 'new directory'],
      ),
      // The long tail waits to be searched for, so the list that opens on `>`
      // still starts with the things people make every day.
      for (final type in CollectionRegistry.types)
        PaletteCommand(
          id: 'new_collection_${type.kind.name}',
          title: LocaleKeys.commandPalette_command_newItem.tr(
            args: [type.label],
          ),
          subtitle: LocaleKeys.commandPalette_command_collection.tr(),
          icon: type.icon,
          group: PaletteCommandGroup.create,
          keywords: ['collection', 'add', ...type.searchKeywords],
          takesArgument: true,
          argumentPhrases: [
            'create ${type.label.toLowerCase()}',
            'add ${type.label.toLowerCase()}',
          ],
          searchOnly: true,
          run: (palette) => _createAndOpen(
            context,
            dismiss: palette.dismiss,
            name: palette.argument,
            create: (parent, section) async {
              final created = await const CollectionService().createCollection(
                parentViewId: parent,
                kind: type.kind,
                name: palette.argument.isEmpty
                    ? type.defaultName
                    : palette.argument,
                section: section,
              );
              return created.fold((view) => view, (_) => null);
            },
          ),
        ),
      for (final kind in WorkspaceTableKind.values)
        if (!_coreTableKinds.contains(kind))
          PaletteCommand(
            id: 'new_table_${kind.name}',
            title: LocaleKeys.commandPalette_command_newItem.tr(
              args: [workspaceTableKindLabel(kind)],
            ),
            subtitle: LocaleKeys.commandPalette_command_tableView.tr(),
            icon: workspaceTableKindIcon(kind),
            group: PaletteCommandGroup.create,
            keywords: ['database', 'table', 'view', 'add', kind.name],
            takesArgument: true,
            argumentPhrases: [
              'create ${workspaceTableKindLabel(kind).toLowerCase()}',
              'add ${workspaceTableKindLabel(kind).toLowerCase()}',
            ],
            searchOnly: true,
            run: (palette) => _createAndOpen(
              context,
              dismiss: palette.dismiss,
              name: palette.argument,
              create: (parent, section) => createWorkspaceDatabase(
                parentViewId: parent,
                kind: kind,
                section: section,
              ),
            ),
          ),
      for (final kind in WorkspaceFileKind.values)
        if (kind.isBlankCreatable)
          PaletteCommand(
            id: 'new_file_${kind.name}',
            title: LocaleKeys.commandPalette_command_newItem.tr(
              args: [kind.label],
            ),
            subtitle: '.${kind.fileExtension}',
            icon: kind.icon,
            group: PaletteCommandGroup.create,
            keywords: ['file', 'add', kind.fileExtension, kind.name],
            takesArgument: true,
            argumentPhrases: [
              'create ${kind.label.toLowerCase()}',
              'add ${kind.label.toLowerCase()}',
            ],
            searchOnly: true,
            run: (palette) => _createAndOpen(
              context,
              dismiss: palette.dismiss,
              create: (parent, section) async {
                final created = await createWorkspaceFile(
                  parentViewId: parent,
                  action: WorkspaceFileMenuAction(
                    kind,
                    WorkspaceFileSource.create,
                  ),
                  section: section,
                  name: palette.argument.isEmpty ? null : palette.argument,
                );
                return created?.fold((view) => view, (_) => null);
              },
            ),
          ),
      for (final template in TemplateRegistry.all())
        if (template.requires.every(DartExtensionHost.instance.isEnabled))
          _template(context, template),
    ],
    ..._navigation(workspaceBloc),
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
          TabsEvent.openPlugin(
              plugin: makePlugin(pluginType: PluginType.trash)),
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
        final cubit = AppGlobals.rootNavKey.currentContext
            ?.read<AppearanceSettingsCubit>();
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
      for (final (page, label, icon, words) in _settingsPages())
        _settings(
          workspaceBloc,
          id: 'settings_${page.name}',
          title: LocaleKeys.commandPalette_command_settingsPage.tr(
            args: [label],
          ),
          icon: icon,
          page: page,
          keywords: words,
        ),
    ],
    PaletteCommand(
      id: 'ask_ai',
      title: LocaleKeys.commandPalette_command_askAI.tr(),
      icon: Icons.auto_awesome_rounded,
      group: PaletteCommandGroup.ai,
      keywords: const ['chat', 'assistant', 'question', 'ai'],
      takesArgument: true,
      argumentPhrases: const ['ask', 'ai', 'ask ai about'],
      run: (palette) {
        final ask = palette.askAI;
        if (ask != null) {
          ask(palette.argument);
          return null;
        }
        return startPaletteAIChat(context, dismiss: palette.dismiss);
      },
    ),
    if (openView != null && openView.layout == ViewLayoutPB.Document) ...[
      PaletteCommand(
        id: 'ai_summarize_page',
        title: LocaleKeys.commandPalette_command_summarizePage.tr(),
        subtitle: openView.nameOrDefault,
        icon: Icons.short_text_rounded,
        group: PaletteCommandGroup.ai,
        keywords: const ['summary', 'tldr', 'ai', 'digest'],
        run: (palette) => palette.askAI?.call(
          LocaleKeys.commandPalette_ai_suggestionSummarize.tr(),
        ),
      ),
      PaletteCommand(
        id: 'ai_action_items',
        title: LocaleKeys.commandPalette_command_actionItems.tr(),
        subtitle: openView.nameOrDefault,
        icon: Icons.checklist_rounded,
        group: PaletteCommandGroup.ai,
        keywords: const ['todo', 'tasks', 'ai', 'follow up'],
        searchOnly: true,
        run: (palette) => palette.askAI?.call(
          LocaleKeys.commandPalette_ai_suggestionActionItems.tr(),
        ),
      ),
    ],
    // Read as the palette opens, so switching an extension off removes its
    // commands with no restart.
    for (final command in ExtensionCommandRegistry.all())
      _extensionCommand(command),
    for (final extension in ExtensionStore.instance.active)
      for (final action in extension.actions)
        if (action.enabled) _extensionAction(extension, action),
  ];
}

/// The table kinds the main create commands already cover.
const _coreTableKinds = {
  WorkspaceTableKind.table,
  WorkspaceTableKind.board,
  WorkspaceTableKind.calendar,
};

/// The Settings pages without a command of their own above.
List<(SettingsPage, String, IconData, List<String>)> _settingsPages() => [
      (
        SettingsPage.editor,
        LocaleKeys.settings_editorPage_menuLabel.tr(),
        Icons.edit_note_rounded,
        const ['spell check', 'grammar', 'dictionary'],
      ),
      (
        SettingsPage.notifications,
        LocaleKeys.settings_menu_notifications.tr(),
        Icons.notifications_rounded,
        const ['alerts', 'reminders'],
      ),
      (
        SettingsPage.manageData,
        LocaleKeys.settings_manageDataPage_menuLabel.tr(),
        Icons.storage_rounded,
        const ['data', 'storage', 'cache', 'export', 'import'],
      ),
      (
        SettingsPage.cloud,
        LocaleKeys.settings_menu_cloudSettings.tr(),
        Icons.cloud_rounded,
        const ['sync', 'server', 'self-hosted'],
      ),
      (
        SettingsPage.pageVersions,
        LocaleKeys.pageVersions_settingsTitle.tr(),
        Icons.history_rounded,
        const ['history', 'versions', 'snapshots'],
      ),
      (
        SettingsPage.encryption,
        LocaleKeys.encryption_settingsTitle.tr(),
        Icons.lock_outline_rounded,
        const ['encryption', 'passphrase', 'privacy'],
      ),
      (
        SettingsPage.backup,
        LocaleKeys.backup_settingsTitle.tr(),
        Icons.backup_rounded,
        const ['backup', 'restore', 'export'],
      ),
      (
        SettingsPage.maps,
        LocaleKeys.map_settingsTitle.tr(),
        Icons.map_rounded,
        const ['maps', 'tiles', 'location'],
      ),
      (
        SettingsPage.connections,
        LocaleKeys.providers_connections.tr(),
        Icons.hub_rounded,
        const ['providers', 'integrations', 'api keys', 'accounts'],
      ),
      (
        SettingsPage.extensions,
        LocaleKeys.extensions_settingsTitle.tr(),
        Icons.extension_rounded,
        const ['extensions', 'plugins', 'add-ons'],
      ),
    ];

/// The places the sidebar can go to, offered by name.
List<PaletteCommand> _navigation(UserWorkspaceBloc? workspaceBloc) {
  final workspaceId = workspaceBloc?.state.currentWorkspace?.workspaceId ?? '';
  return [
    if (workspaceId.isNotEmpty)
      PaletteCommand(
        id: 'go_home',
        title: LocaleKeys.commandPalette_command_goHome.tr(),
        icon: Icons.home_rounded,
        group: PaletteCommandGroup.navigate,
        keywords: const ['home', 'dashboard', 'start'],
        run: (palette) {
          palette.dismiss();
          unawaited(getIt<TabsBloc>().openHome(workspaceId: workspaceId));
        },
      ),
    for (final (id, type, title, icon, words) in [
      (
        'open_recents',
        PluginType.recents,
        LocaleKeys.commandPalette_command_openRecents.tr(),
        Icons.schedule_rounded,
        const ['recent', 'history', 'last opened'],
      ),
      (
        'open_favorites',
        PluginType.favorites,
        LocaleKeys.commandPalette_command_openFavorites.tr(),
        Icons.star_rounded,
        const ['starred', 'favourites', 'pinned'],
      ),
      (
        'open_library',
        PluginType.pageLibrary,
        LocaleKeys.commandPalette_command_openLibrary.tr(),
        Icons.book_rounded,
        const ['all pages', 'library', 'everything'],
      ),
      (
        'open_templates',
        PluginType.templates,
        LocaleKeys.commandPalette_command_openTemplates.tr(),
        Icons.auto_awesome_mosaic_rounded,
        const ['templates', 'gallery', 'starter'],
      ),
      (
        'open_extensions',
        PluginType.extensions,
        LocaleKeys.commandPalette_command_openExtensions.tr(),
        Icons.extension_rounded,
        const ['extensions', 'plugins', 'add-ons', 'marketplace'],
      ),
    ])
      if (_canOpenPlugin(type))
        PaletteCommand(
          id: id,
          title: title,
          icon: icon,
          group: PaletteCommandGroup.navigate,
          keywords: words,
          run: (palette) {
            palette.dismiss();
            getIt<MenuSharedState>().latestOpenView = null;
            getIt<TabsBloc>().add(
              TabsEvent.openPlugin(
                plugin: makePlugin(pluginType: type),
                setLatest: false,
              ),
            );
          },
        ),
  ];
}

bool _canOpenPlugin(PluginType type) =>
    getIt.isRegistered<PluginSandbox>() &&
    getIt<PluginSandbox>().supportPluginTypes.contains(type);

PaletteCommand _template(BuildContext context, WorkspaceTemplate template) =>
    PaletteCommand(
      id: 'template_${template.id}',
      title: LocaleKeys.commandPalette_command_fromTemplate.tr(
        args: [template.label()],
      ),
      subtitle: template.description(),
      icon: template.icon,
      group: PaletteCommandGroup.templates,
      keywords: ['template', 'starter', ...template.keywords],
      searchOnly: true,
      run: (palette) => _createAndOpen(
        context,
        dismiss: palette.dismiss,
        create: (parent, section) async {
          final outcome = await TemplateService.create(
            parentViewId: parent,
            template: template,
            section: section,
          );
          return outcome?.primary;
        },
      ),
    );

PaletteCommand _extensionAction(
  LoadedExtension extension,
  ActionDefinition action,
) {
  final name = extension.manifest.name.isEmpty
      ? extension.id
      : extension.manifest.name;
  return PaletteCommand(
    id: 'extension_action_${extension.id}_${action.id}',
    title: LocaleKeys.commandPalette_command_runAction.tr(args: [action.id]),
    subtitle: action.description.isEmpty
        ? name
        : '$name · ${action.description}',
    icon: Icons.play_circle_outline_rounded,
    group: PaletteCommandGroup.extensions,
    keywords: ['run', 'action', 'extension', extension.id, name],
    run: (palette) async {
      palette.dismiss();
      final run = await ActionScheduler.instance.runNow(
        extensionId: extension.id,
        actionId: action.id,
      );
      final ok = run.status == ActionRunStatus.ok;
      showToastNotification(
        message: ok
            ? LocaleKeys.extensions_ranOk.tr(args: [action.id])
            : (run.message.isEmpty ? run.status.name : run.message),
        type: ok ? ToastificationType.success : ToastificationType.error,
      );
    },
  );
}

PaletteCommand _extensionCommand(ExtensionCommand command) => PaletteCommand(
      id: 'extension_${command.extensionId}_${command.id}',
      title: command.name,
      subtitle: command.description,
      icon: command.icon,
      group: PaletteCommandGroup.extensions,
      keywords: [command.extensionId, ...command.keywords],
      run: (palette) {
        // Dismissed first because an extension command may well open a route of
        // its own, and popping afterwards would close that instead. The root
        // navigator is then the only context still alive.
        palette.dismiss();
        final host = AppGlobals.rootNavKey.currentContext;
        if (host != null) {
          unawaited(command.run(host));
        }
      },
    );

/// The words that head each section of the command list.
String paletteCommandGroupLabel(PaletteCommandGroup group) => switch (group) {
      PaletteCommandGroup.create => LocaleKeys.commandPalette_group_create.tr(),
      PaletteCommandGroup.templates =>
        LocaleKeys.commandPalette_group_templates.tr(),
      PaletteCommandGroup.navigate =>
        LocaleKeys.commandPalette_group_navigate.tr(),
      PaletteCommandGroup.view => LocaleKeys.commandPalette_group_view.tr(),
      PaletteCommandGroup.workspace =>
        LocaleKeys.commandPalette_group_workspace.tr(),
      PaletteCommandGroup.extensions =>
        LocaleKeys.commandPalette_group_extensions.tr(),
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
  List<String> phrases = const [],
}) {
  return PaletteCommand(
    id: id,
    title: title,
    icon: icon,
    group: PaletteCommandGroup.create,
    shortcut: shortcut,
    keywords: keywords,
    takesArgument: true,
    argumentPhrases: phrases,
    run: (palette) => createPaletteView(
      context,
      dismiss: palette.dismiss,
      kind: kind,
      layout: layout,
      name: palette.argument,
    ),
  );
}

/// Creates an object from the palette and opens it.
///
/// A space knows where a new page belongs; without one it lands at the root of
/// the workspace, which is what the sidebar's own `+` does. [name] is what
/// somebody typed after the command, if anything.
Future<void> createPaletteView(
  BuildContext context, {
  required VoidCallback dismiss,
  required SidebarRootCreateKind kind,
  ViewLayoutPB? layout,
  String name = '',
}) async {
  final spaceBloc = context.mounted ? context.read<SpaceBloc?>() : null;
  if (layout != null && (spaceBloc?.state.spaces.isNotEmpty ?? false)) {
    dismiss();
    spaceBloc!.add(
      SpaceEvent.createPage(
        name: name.trim(),
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
    name: name,
  );
  dismiss();
  if (view != null) {
    getIt<TabsBloc>().openPlugin(view);
  }
}

/// Where something made from the palette goes: into the open space when the
/// workspace has spaces, otherwise to the top of the workspace. Null when no
/// workspace is open.
({String parentViewId, ViewSectionPB? section})? paletteCreationTarget(
  BuildContext context,
) {
  final spaceState = context.read<SpaceBloc?>()?.state;
  final space = spaceState?.currentSpace;
  if (space != null && (spaceState?.spaces.isNotEmpty ?? false)) {
    return (parentViewId: space.id, section: null);
  }
  final workspaceId =
      context.read<UserWorkspaceBloc?>()?.state.currentWorkspace?.workspaceId;
  if (workspaceId == null || workspaceId.isEmpty) {
    return null;
  }
  return (
    parentViewId: workspaceId,
    section: FolderSpaceType.public.toViewSectionPB,
  );
}

/// Makes something with [create] where [paletteCreationTarget] says it
/// belongs, then opens it. The palette closes first, so making a template
/// of several parts never holds it open.
Future<void> _createAndOpen(
  BuildContext context, {
  required VoidCallback dismiss,
  required Future<ViewPB?> Function(String parentViewId, ViewSectionPB? section)
      create,
  String name = '',
}) async {
  final target = context.mounted ? paletteCreationTarget(context) : null;
  dismiss();
  if (target == null) {
    showToastNotification(
      message: LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
      type: ToastificationType.error,
    );
    return;
  }
  final view = await create(target.parentViewId, target.section);
  if (view == null) {
    showToastNotification(
      message: LocaleKeys.commandPalette_command_createFailed.tr(),
      type: ToastificationType.error,
    );
    return;
  }
  final wanted = name.trim();
  if (wanted.isNotEmpty && view.name != wanted) {
    await ViewBackendService.updateView(viewId: view.id, name: wanted);
  }
  getIt<TabsBloc>().openPlugin(view);
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
