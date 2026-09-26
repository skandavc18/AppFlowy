import 'dart:async';

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/palette_commands.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/recent_views_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_layout.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import 'widgets/search_ask_ai_entrance.dart';

class CommandPalette extends InheritedWidget {
  CommandPalette({
    super.key,
    required Widget? child,
    required this.notifier,
  }) : super(
          child: _CommandPaletteController(notifier: notifier, child: child),
        );

  final ValueNotifier<CommandPaletteNotifierValue> notifier;

  static CommandPalette of(BuildContext context) {
    final CommandPalette? result =
        context.dependOnInheritedWidgetOfExactType<CommandPalette>();

    assert(result != null, "CommandPalette could not be found");

    return result!;
  }

  static CommandPalette? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CommandPalette>();

  void toggle({
    UserWorkspaceBloc? workspaceBloc,
    SpaceBloc? spaceBloc,
  }) {
    final value = notifier.value;
    notifier.value = notifier.value.copyWith(
      isOpen: !value.isOpen,
      userWorkspaceBloc: workspaceBloc,
      spaceBloc: spaceBloc,
    );
  }

  void updateBlocs({
    UserWorkspaceBloc? workspaceBloc,
    SpaceBloc? spaceBloc,
  }) {
    notifier.value = notifier.value.copyWith(
      userWorkspaceBloc: workspaceBloc,
      spaceBloc: spaceBloc,
    );
  }

  @override
  bool updateShouldNotify(covariant InheritedWidget oldWidget) => false;
}

class _ToggleCommandPaletteIntent extends Intent {
  const _ToggleCommandPaletteIntent();
}

class _CommandPaletteController extends StatefulWidget {
  const _CommandPaletteController({
    required this.child,
    required this.notifier,
  });

  final Widget? child;
  final ValueNotifier<CommandPaletteNotifierValue> notifier;

  @override
  State<_CommandPaletteController> createState() =>
      _CommandPaletteControllerState();
}

class _CommandPaletteControllerState extends State<_CommandPaletteController> {
  late ValueNotifier<CommandPaletteNotifierValue> _toggleNotifier =
      widget.notifier;
  bool _isOpen = false;
  ModalRoute<dynamic>? _paletteRoute;

  @override
  void initState() {
    super.initState();
    _toggleNotifier.addListener(_onToggle);
  }

  @override
  void dispose() {
    _toggleNotifier.removeListener(_onToggle);
    super.dispose();
  }

  @override
  void didUpdateWidget(_CommandPaletteController oldWidget) {
    if (oldWidget.notifier != widget.notifier) {
      oldWidget.notifier.removeListener(_onToggle);
      _toggleNotifier = widget.notifier;
      _toggleNotifier.addListener(_onToggle);
    }
    super.didUpdateWidget(oldWidget);
  }

  void _onToggle() {
    if (_toggleNotifier.value.isOpen && !_isOpen) {
      _isOpen = true;
      final workspaceBloc = _toggleNotifier.value.userWorkspaceBloc;
      final spaceBloc = _toggleNotifier.value.spaceBloc;
      final commandBloc = context.read<CommandPaletteBloc>();
      Log.info(
        'CommandPalette onToggle: workspaceType ${workspaceBloc?.state.userProfile.workspaceType}',
      );
      commandBloc.add(CommandPaletteEvent.refreshCachedViews());
      FlowyOverlay.show(
        context: context,
        barrierColor: Colors.transparent,
        builder: (dialogContext) {
          _paletteRoute = ModalRoute.of(dialogContext);
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: commandBloc),
              if (workspaceBloc != null)
                BlocProvider.value(value: workspaceBloc),
              if (spaceBloc != null) BlocProvider.value(value: spaceBloc),
            ],
            child: CommandPaletteModal(shortcutBuilder: _buildShortcut),
          );
        },
      ).then((_) {
        _isOpen = false;
        _paletteRoute = null;
        if (mounted) {
          _toggleNotifier.value = _toggleNotifier.value.copyWith(isOpen: false);
        }
      });
    } else if (!_toggleNotifier.value.isOpen && _isOpen) {
      final route = _paletteRoute;
      if (route != null && route.isCurrent) {
        route.navigator?.pop();
      } else {
        // A newer modal owns dismissal; the palette is still open behind it.
        _toggleNotifier.value = _toggleNotifier.value.copyWith(isOpen: true);
      }
    }
  }

  @override
  Widget build(BuildContext context) =>
      _buildShortcut(widget.child ?? const SizedBox.shrink());

  Widget _buildShortcut(Widget child) => FocusableActionDetector(
        actions: {
          _ToggleCommandPaletteIntent:
              CallbackAction<_ToggleCommandPaletteIntent>(
            onInvoke: (intent) => _toggleNotifier.value = _toggleNotifier.value
                .copyWith(isOpen: !_toggleNotifier.value.isOpen),
          ),
        },
        shortcuts: {
          LogicalKeySet(
            UniversalPlatform.isMacOS
                ? LogicalKeyboardKey.meta
                : LogicalKeyboardKey.control,
            LogicalKeyboardKey.keyP,
          ): const _ToggleCommandPaletteIntent(),
        },
        child: child,
      );
}

class CommandPaletteModal extends StatefulWidget {
  const CommandPaletteModal({super.key, required this.shortcutBuilder});

  final Widget Function(Widget) shortcutBuilder;

  @override
  State<CommandPaletteModal> createState() => _CommandPaletteModalState();
}

class _CommandPaletteModalState extends State<CommandPaletteModal> {
  CommandPaletteFilter filter = const CommandPaletteFilter();

  void _dismiss() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent && Navigator.canPop(context)) {
      route.navigator?.pop();
    }
  }

  void _runCommand(PaletteCommand command, String query) {
    unawaited(
      Future.sync(
        () => command.run(
          PaletteCommandContext(query: query, dismiss: _dismiss),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final workspaceState = context.read<UserWorkspaceBloc?>()?.state;
    return BlocListener<CommandPaletteBloc, CommandPaletteState>(
      listener: (_, state) {
        if (!state.askAI || !context.mounted) {
          return;
        }
        // Put the flag down, or a second "Ask AI" emits an identical state and
        // the listener is never called again.
        context.read<CommandPaletteBloc>().add(CommandPaletteEvent.askedAI());
        unawaited(startPaletteAIChat(context, dismiss: _dismiss));
      },
      child: BlocBuilder<CommandPaletteBloc, CommandPaletteState>(
        builder: (context, state) {
          final palette = WorkspacePalette.of(context);
          final noQuery = state.query?.isEmpty ?? true, hasQuery = !noQuery;
          final currentUserId = workspaceState?.userProfile.id;
          final currentWorkspace = workspaceState?.currentWorkspace;
          PageStyleCover? currentWorkspaceCover;
          if (currentWorkspace != null) {
            currentWorkspaceCover =
                WorkspaceCoverCodec.decode(currentWorkspace.cover);
            if (currentWorkspaceCover == null &&
                currentWorkspace.cover.trim().isEmpty) {
              currentWorkspaceCover = AutomaticViewCover.forWorkspace(
                name: currentWorkspace.name,
              );
            }
          }
          var cachedViews = state.cachedViews;
          final workspaceRoot = currentWorkspace == null
              ? null
              : cachedViews[currentWorkspace.workspaceId];
          if (currentWorkspace != null && workspaceRoot != null) {
            cachedViews = {
              ...cachedViews,
              currentWorkspace.workspaceId: workspaceRoot.asWorkspaceRootFolder(
                workspaceId: currentWorkspace.workspaceId,
                name: currentWorkspace.name,
                icon: currentWorkspace.icon,
                cover: currentWorkspaceCover,
              ),
            };
          }
          final searchableItems = includeWorkspaceFolderSearchResults(
            searchResults: state.combinedResponseItems.values,
            cachedViews: cachedViews,
            query: state.query ?? '',
            excludedViewIds: state.trash.map((trash) => trash.id),
          );
          final resultItems = searchableItems
              .where(
                (item) =>
                    cachedViews.isEmpty || cachedViews.containsKey(item.id),
              )
              .where(
                (item) => filter.matchesSearchResult(
                  item: item,
                  view: cachedViews[item.id],
                  query: state.query ?? '',
                  cachedViews: cachedViews,
                  currentUserId: currentUserId,
                ),
              )
              .toList();
          final hasResult = resultItems.isNotEmpty, searching = state.searching;
          final rawQuery = state.query ?? '';
          final commandQuery = paletteCommandModeQuery(rawQuery);
          final inCommandMode = commandQuery != null;
          final commands = buildPaletteCommands(context);
          final matchedCommands = inCommandMode
              ? rankPaletteCommands(commands, commandQuery)
              // One stray letter matches half of them, which is noise beside
              // the pages somebody was actually looking for.
              : rawQuery.trim().length < 2
                  ? const <PaletteCommand>[]
                  : rankPaletteCommands(
                      commands,
                      rawQuery,
                      limit: paletteInlineCommandLimit,
                    );
          final hasCommands = matchedCommands.isNotEmpty;
          final commandRunQuery = commandQuery ?? rawQuery;
          final spaces =
              context.read<SpaceBloc?>()?.state.spaces ?? const <ViewPB>[];
          final media = MediaQuery.of(context);
          final dialogSize = commandPaletteDialogSize(
            media.size,
            viewInsets: media.viewInsets,
          );
          final contentInset = media.size.width < 640
              ? WorkspaceTokens.space4
              : WorkspaceTokens.space6;
          return FlowyDialog(
            backgroundColor: palette.elevatedSurface,
            width: dialogSize.width,
            elevation: 1,
            shadowColor: palette.shadow,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(WorkspaceTokens.dialogRadius),
            ),
            alignment: Alignment.center,
            insetPadding: commandPaletteDialogInsets(media.size),
            padding: EdgeInsets.zero,
            constraints: BoxConstraints.tight(dialogSize),
            expandHeight: false,
            child: widget.shortcutBuilder(
              Padding(
                padding: EdgeInsets.fromLTRB(
                  contentInset,
                  contentInset,
                  contentInset,
                  0,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxHeight: dialogSize.height * 0.4),
                      child: SingleChildScrollView(
                        primary: false,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            SearchField(
                              query: state.query,
                              isLoading: searching,
                              onSubmit: inCommandMode && hasCommands
                                  ? () => _runCommand(
                                        matchedCommands.first,
                                        commandRunQuery,
                                      )
                                  : null,
                            ),
                            if (!inCommandMode)
                              SearchFilterBar(
                                filter: filter,
                                spaces: spaces,
                                onChanged: (value) =>
                                    setState(() => filter = value),
                              )
                            else
                              const VSpace(WorkspaceTokens.space4),
                          ],
                        ),
                      ),
                    ),
                    if (inCommandMode)
                      Expanded(
                        child: CommandPalettePanel(
                          commands: matchedCommands,
                          onRun: (command) =>
                              _runCommand(command, commandRunQuery),
                        ),
                      )
                    else if (noQuery)
                      Expanded(
                        child: RecentViewsList(
                          onSelected: _dismiss,
                          filter: filter,
                          cachedViews: cachedViews,
                          currentUserId: currentUserId,
                          currentWorkspaceId: currentWorkspace?.workspaceId,
                          currentWorkspaceName: currentWorkspace?.name,
                          currentWorkspaceIcon: currentWorkspace?.icon,
                          currentWorkspaceCover: currentWorkspaceCover,
                        ),
                      )
                    else if (hasQuery && (hasResult || hasCommands))
                      Expanded(
                        child: SearchResultList(
                          cachedViews: cachedViews,
                          resultItems: resultItems,
                          resultSummaries: state.resultSummaries,
                          commands: matchedCommands,
                          onRunCommand: (command) =>
                              _runCommand(command, commandRunQuery),
                          currentWorkspaceId: currentWorkspace?.workspaceId,
                          currentWorkspaceName: currentWorkspace?.name,
                          currentWorkspaceIcon: currentWorkspace?.icon,
                          currentWorkspaceCover: currentWorkspaceCover,
                        ),
                      )
                    // When there are no results and the query is not empty and not loading,
                    // show the no results message, centered in the available space.
                    else if (hasQuery && !searching) ...[
                      SearchAskAiEntrance(),
                      Expanded(
                        child: const NoSearchResultsHint(),
                      ),
                    ],
                    if (hasQuery &&
                        searching &&
                        !hasResult &&
                        !hasCommands &&
                        !inCommandMode)
                      // Show a loading indicator when searching
                      Expanded(
                        child: Center(
                          child: Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        ),
                      ),
                    LayoutBuilder(
                      builder: (context, constraints) {
                        final minimumWidth =
                            MediaQuery.textScalerOf(context).scale(400);
                        return SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: SizedBox(
                            width: constraints.maxWidth < minimumWidth
                                ? minimumWidth
                                : constraints.maxWidth,
                            child: CommandPaletteHintBar(
                              commandMode: inCommandMode,
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Updated _NoResultsHint now centers its content.
class NoSearchResultsHint extends StatelessWidget {
  const NoSearchResultsHint({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WorkspaceTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            FlowySvg(
              FlowySvgs.m_home_search_icon_m,
              color: palette.secondaryText,
              size: const Size.square(32),
            ),
            const VSpace(WorkspaceTokens.space4),
            Text(
              LocaleKeys.search_noResultForSearching.tr(),
              textAlign: TextAlign.center,
              style:
                  WorkspaceTypography.style(context, WorkspaceTextRole.section),
            ),
            const VSpace(WorkspaceTokens.space2),
            Text(
              LocaleKeys.search_noResultForSearchingHintWithoutTrash.tr(),
              textAlign: TextAlign.center,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
              ),
            ),
            TextButton(
              onPressed: () {
                FlowyOverlay.pop(context);
                getIt<MenuSharedState>().latestOpenView = null;
                getIt<TabsBloc>().add(
                  TabsEvent.openPlugin(
                    plugin: makePlugin(pluginType: PluginType.trash),
                  ),
                );
              },
              child: Text(LocaleKeys.trash_text.tr()),
            ),
          ],
        ),
      ),
    );
  }
}

class CommandPaletteNotifierValue {
  CommandPaletteNotifierValue({
    this.isOpen = false,
    this.userWorkspaceBloc,
    this.spaceBloc,
  });

  final bool isOpen;
  final UserWorkspaceBloc? userWorkspaceBloc;
  final SpaceBloc? spaceBloc;

  CommandPaletteNotifierValue copyWith({
    bool? isOpen,
    UserWorkspaceBloc? userWorkspaceBloc,
    SpaceBloc? spaceBloc,
  }) {
    return CommandPaletteNotifierValue(
      isOpen: isOpen ?? this.isOpen,
      userWorkspaceBloc: userWorkspaceBloc ?? this.userWorkspaceBloc,
      spaceBloc: spaceBloc ?? this.spaceBloc,
    );
  }
}
