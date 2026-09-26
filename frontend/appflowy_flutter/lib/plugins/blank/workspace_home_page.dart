import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/workspace_folder/workspace_folder_plugin.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/command_palette.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart'
    show UserWorkspacePB;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// A navigation-only Home when no existing dashboard is selected. Reading the
/// shell's current identity never creates a view, preference, cache or preview.
class WorkspaceHomePage extends StatelessWidget {
  const WorkspaceHomePage({
    super.key,
    this.workspace,
    this.userName,
    this.onNavigate,
    this.onSearch,
  });

  /// Optional snapshots/callbacks for isolated hosts; otherwise use the shell.
  final UserWorkspacePB? workspace;
  final String? userName;
  final ValueChanged<TabsEvent>? onNavigate;
  final VoidCallback? onSearch;

  bool get _templatesAvailable =>
      getIt.isRegistered<PluginSandbox>() &&
      getIt<PluginSandbox>().supportPluginTypes.contains(PluginType.templates);

  ValueChanged<TabsEvent>? _navigation(BuildContext context) {
    if (onNavigate != null) return onNavigate;
    final tabs = context.read<TabsBloc?>();
    return tabs == null || tabs.isClosed ? null : tabs.add;
  }

  void _openWorkspace(BuildContext context) {
    // Resolve again at activation: a workspace switch may precede its repaint.
    final current =
        workspace ?? context.read<UserWorkspaceBloc?>()?.state.currentWorkspace;
    final navigate = _navigation(context);
    if (current == null ||
        current.workspaceId.trim().isEmpty ||
        navigate == null) {
      return;
    }
    final view = workspaceRootFolderView(
      workspaceId: current.workspaceId,
      name: current.name.trim().isEmpty
          ? LocaleKeys.sideBar_workspace.tr()
          : current.name,
      icon: current.icon,
    );
    _open(navigate, WorkspaceFolderPlugin(view: view), view: view);
  }

  void _openTemplates(BuildContext context) {
    final navigate = _navigation(context);
    if (navigate == null || !_templatesAvailable) return;
    _open(navigate, makePlugin(pluginType: PluginType.templates));
  }

  void _open(
    ValueChanged<TabsEvent> navigate,
    Plugin plugin, {
    ViewPB? view,
  }) {
    if (getIt.isRegistered<MenuSharedState>()) {
      getIt<MenuSharedState>().latestOpenView = view;
    }
    // The tab host owns init/dispose. The root is not a persisted page record.
    navigate(
      TabsEvent.openPlugin(plugin: plugin, view: view, setLatest: false),
    );
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<UserWorkspaceBloc?>()?.state;
    final current = workspace ?? state?.currentWorkspace;
    final name = (userName ?? state?.userProfile.name ?? '').trim();
    final workspaceName = current?.name.trim() ?? '';
    final hasWorkspace = current?.workspaceId.trim().isNotEmpty ?? false;
    final canNavigate = _navigation(context) != null;
    final palette = CommandPalette.maybeOf(context);
    final search = onSearch ??
        (palette == null
            ? null
            : () => palette.toggle(
                  workspaceBloc: context.read<UserWorkspaceBloc?>(),
                  spaceBloc: context.read<SpaceBloc?>(),
                ));
    final actions = [
      _HomeAction(
        id: 'workspace',
        icon: Icons.folder_open_rounded,
        label: LocaleKeys.sideBar_workspace.tr(),
        description: hasWorkspace
            ? null
            : LocaleKeys.workspaceFolderExplorer_workspaceUnavailable.tr(),
        onPressed:
            hasWorkspace && canNavigate ? () => _openWorkspace(context) : null,
      ),
      if (search != null)
        _HomeAction(
          id: 'search',
          icon: Icons.search_rounded,
          label: LocaleKeys.search_label.tr(),
          onPressed: search,
        ),
      if (canNavigate && _templatesAvailable)
        _HomeAction(
          id: 'templates',
          icon: Icons.dashboard_rounded,
          label: LocaleKeys.templates_name.tr(),
          onPressed: () => _openTemplates(context),
        ),
    ];

    return SizedBox.expand(
      child: WorkspaceSurface(
        kind: WorkspaceSurfaceKind.canvas,
        radius: 0,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final narrow = constraints.maxWidth < 600;
            final inset = constraints.maxWidth < 360
                ? WorkspaceTokens.space4
                : WorkspaceTokens.pageInset(constraints.maxWidth);
            return SingleChildScrollView(
              primary: false,
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: WorkspaceTokens.pageMaxWidth,
                  ),
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(
                      inset,
                      narrow ? WorkspaceTokens.space8 : WorkspaceTokens.space16,
                      inset,
                      WorkspaceTokens.space8,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        WorkspacePageIdentity(
                          title: Text(
                            LocaleKeys.dashboard_home.tr(),
                            style: WorkspaceTypography.style(
                              context,
                              WorkspaceTextRole.pageTitle,
                              compact: narrow,
                            ),
                          ),
                          description: Wrap(
                            spacing: WorkspaceTokens.space2,
                            runSpacing: WorkspaceTokens.space1,
                            children: [
                              Text(LocaleKeys.label_welcome.tr()),
                              if (name.isNotEmpty) Text(name),
                            ],
                          ),
                          metadata: workspaceName.isEmpty
                              ? null
                              : Text(workspaceName),
                        ),
                        const SizedBox(height: WorkspaceTokens.space8),
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const gap = WorkspaceTokens.space3;
                            final minimum =
                                MediaQuery.textScalerOf(context).scale(200);
                            final columns =
                                ((constraints.maxWidth + gap) / (minimum + gap))
                                    .floor()
                                    .clamp(1, actions.length);
                            final width =
                                (constraints.maxWidth - gap * (columns - 1)) /
                                    columns;
                            return Wrap(
                              spacing: gap,
                              runSpacing: gap,
                              children: [
                                for (final action in actions)
                                  SizedBox(
                                    key: ValueKey(action.id),
                                    width: width,
                                    child: action,
                                  ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class _HomeAction extends StatelessWidget {
  const _HomeAction({
    required this.id,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.description,
  });

  final String id;
  final IconData icon;
  final String label;
  final String? description;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => WorkspaceSurface(
        child: TextButton(
          key: ValueKey('workspace-home-$id'),
          onPressed: onPressed,
          style: WorkspaceChrome.controlStyle(
            context,
            accent: WorkspacePalette.of(context).primaryText,
          ).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size(0, 112)),
            padding: const WidgetStatePropertyAll(
              EdgeInsets.all(WorkspaceTokens.space4),
            ),
            alignment: AlignmentDirectional.centerStart,
            shape: WidgetStatePropertyAll(
              RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(WorkspaceTokens.cardRadius),
              ),
            ),
            textStyle: WidgetStatePropertyAll(
              WorkspaceTypography.style(context, WorkspaceTextRole.cardTitle),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Builder(
                builder: (context) => WorkspaceGlyph(
                  icon,
                  size: 24,
                  color: IconTheme.of(context).color,
                  role: onPressed == null
                      ? WorkspaceGlyphRole.preserveInk
                      : WorkspaceGlyphRole.standard,
                ),
              ),
              const SizedBox(height: WorkspaceTokens.space3),
              Text(label),
              if (description != null) ...[
                const SizedBox(height: WorkspaceTokens.space2),
                Text(
                  description!,
                  style: WorkspaceTypography.style(
                    context,
                    WorkspaceTextRole.metadata,
                  ),
                ),
              ],
            ],
          ),
        ),
      );
}
