import 'dart:async';

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/command_palette/workspace_content_search_controller.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/palette_commands.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/content_search_widgets.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/recent_views_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_layout.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
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
    DocumentFindReadProvider? readProvider,
  }) : super(
          child: _CommandPaletteController(
            notifier: notifier,
            child: child,
            readProvider: readProvider,
          ),
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

  /// Find from navigation always opens search; repeating it never closes a
  /// popup the user is already typing in (Ctrl+P remains a toggle).
  void show({UserWorkspaceBloc? workspaceBloc, SpaceBloc? spaceBloc}) {
    notifier.value = notifier.value.copyWith(
      isOpen: true,
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
    this.readProvider,
  });

  final Widget? child;
  final ValueNotifier<CommandPaletteNotifierValue> notifier;
  final DocumentFindReadProvider? readProvider;

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
      final workspaceBloc = _toggleNotifier.value.userWorkspaceBloc ??
          context.read<UserWorkspaceBloc?>();
      final spaceBloc =
          _toggleNotifier.value.spaceBloc ?? context.read<SpaceBloc?>();
      final commandBloc = context.read<CommandPaletteBloc>();
      Log.info(
        'CommandPalette onToggle: workspaceType ${workspaceBloc?.state.userProfile.workspaceType}',
      );
      commandBloc.add(CommandPaletteEvent.refreshCachedViews());
      final navigator = Navigator.of(context, rootNavigator: true);
      final themes =
          InheritedTheme.capture(from: context, to: navigator.context);
      final palette = WorkspacePalette.of(context);
      final route = _CommandPaletteRoute(
        context: context,
        themes: themes,
        reduceMotion: () {
          if (!mounted) return true;
          final media = MediaQuery.maybeOf(context);
          return media?.disableAnimations == true ||
              media?.accessibleNavigation == true;
        },
        barrierColor:
            palette.shadow.withValues(alpha: palette.isDark ? .16 : .10),
        builder: (dialogContext) {
          return MultiBlocProvider(
            providers: [
              BlocProvider.value(value: commandBloc),
              if (workspaceBloc != null)
                BlocProvider.value(value: workspaceBloc),
              if (spaceBloc != null) BlocProvider.value(value: spaceBloc),
            ],
            child: CommandPaletteModal(
              shortcutBuilder: _buildShortcut,
              contentReadProvider: widget.readProvider,
            ),
          );
        },
      );
      _paletteRoute = route;
      navigator.push<void>(route).then((_) {
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

/// Only the popup moves. The underlying page and its focus tree stay mounted.
/// Both accessibility flags suppress entry AND reverse motion.
class _CommandPaletteRoute extends DialogRoute<void> {
  _CommandPaletteRoute({
    required this.reduceMotion,
    required super.context,
    required super.builder,
    required super.themes,
    required super.barrierColor,
  }) : super(traversalEdgeBehavior: TraversalEdgeBehavior.closedLoop);

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation, Widget child) {
    final media = MediaQuery.maybeOf(context);
    final reduced = reduceMotion() ||
        media?.disableAnimations == true ||
        media?.accessibleNavigation == true;
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (_, child) {
        final progress =
            reduced ? 1.0 : Curves.easeOutCubic.transform(animation.value);
        return Opacity(
          opacity: progress,
          child: Transform.translate(
            offset: Offset(0, -8 * (1 - progress)),
            child: child,
          ),
        );
      },
    );
  }

  final bool Function() reduceMotion;
  @override
  Duration get transitionDuration =>
      reduceMotion() ? Duration.zero : const Duration(milliseconds: 160);
  @override
  Duration get reverseTransitionDuration => transitionDuration;

  @override
  bool didPop(dynamic result) {
    // Accessibility can change while this route is open. The controller was
    // created on entry, so refresh its reverse timing before Flutter pops it.
    controller?.reverseDuration = reverseTransitionDuration;
    return super.didPop(result);
  }
}

class CommandPaletteModal extends StatefulWidget {
  const CommandPaletteModal({
    super.key,
    required this.shortcutBuilder,
    this.contentReadProvider,
    this.initialQuery,
    this.initialFilter,
    this.anchoredSize,
  });

  final Widget Function(Widget) shortcutBuilder;
  final DocumentFindReadProvider? contentReadProvider;

  /// Seeds the search box instead of the palette's last query, keeping the
  /// caret at its end (the words were typed into another search bar).
  final String? initialQuery;
  final CommandPaletteFilter? initialFilter;

  /// Draws the same search as a panel of this size inside a host route (the
  /// Home search bar) instead of as a centred dialog.
  final Size? anchoredSize;

  @override
  State<CommandPaletteModal> createState() => _CommandPaletteModalState();
}

class _CommandPaletteModalState extends State<CommandPaletteModal> {
  late CommandPaletteFilter filter =
      widget.initialFilter ?? const CommandPaletteFilter();
  late final CommandPaletteBloc _paletteBloc;
  late final UserWorkspaceBloc? _workspaceBloc;
  late final WorkspaceContentSearchController _contentSearch;
  late final WorkspaceTitleSearchController _titleSearch;
  late String _draft;
  StreamSubscription<CommandPaletteState>? _paletteSubscription;
  StreamSubscription<UserWorkspaceState>? _workspaceSubscription;
  final _sourceRefresh = Debouncer(delay: const Duration(milliseconds: 300));
  bool _closing = false;
  bool _titleSourceInvalidated = false;
  int _titleRefreshGeneration = 0;
  String _titleWorkspaceId = '';

  @override
  void initState() {
    super.initState();
    _paletteBloc = context.read<CommandPaletteBloc>();
    _workspaceBloc = context.read<UserWorkspaceBloc?>();
    _draft = widget.initialQuery ?? _paletteBloc.state.query ?? '';
    final provider = widget.contentReadProvider;
    _contentSearch = provider == null
        ? WorkspaceContentSearchController.native(
            isWorkspaceCurrent: _workspaceIsCurrent,
            onSourceInvalidated: _refreshContentSource,
          )
        : WorkspaceContentSearchController(
            provider: provider,
            isWorkspaceCurrent: _workspaceIsCurrent,
            onSourceInvalidated: _refreshContentSource,
          );
    _titleSearch = provider == null
        ? WorkspaceTitleSearchController.native(
            isWorkspaceCurrent: _workspaceIsCurrent,
            onSourceInvalidated: _refreshTitleSource,
          )
        : WorkspaceTitleSearchController(
            provider: provider,
            isWorkspaceCurrent: _workspaceIsCurrent,
            onSourceInvalidated: _refreshTitleSource,
          );
    _syncContentSource(_paletteBloc.state);
    _contentSearch.addListener(_contentChanged);
    _syncTitleSource(_paletteBloc.state);
    _titleSearch.addListener(_titleChanged);
    _paletteSubscription = _paletteBloc.stream.listen((state) {
      _syncContentSource(state);
      _syncTitleSource(state);
    });
    _workspaceSubscription = _workspaceBloc?.stream.listen((_) {
      _syncContentSource(_paletteBloc.state);
      _syncTitleSource(_paletteBloc.state);
      if (mounted && !_closing) setState(() {});
    });
    if (filter.pageContents) {
      _paletteBloc.setContentSearchEnabled(true);
      _syncContentSource(_paletteBloc.state);
      _contentSearch.search(_draft, enabled: true, filter: filter);
    } else if (widget.initialQuery != null &&
        _draft != (_paletteBloc.state.query ?? '')) {
      _paletteBloc.add(
        _draft.isEmpty
            ? const CommandPaletteEvent.clearSearch()
            : CommandPaletteEvent.searchChanged(search: _draft),
      );
    }
  }

  void _syncTitleSource(CommandPaletteState state) {
    if (_closing) return;
    final workspace = _workspaceBloc?.state;
    final id = workspace?.currentWorkspace?.workspaceId ?? '';
    if (_titleWorkspaceId != id) {
      _titleWorkspaceId = id;
      _titleRefreshGeneration++;
      _titleSourceInvalidated = false;
    }
    _titleSearch.updateSource(
      workspaceId: id,
      cachedViews: state.cachedViews,
      excludedViewIds: state.trash.map((item) => item.id),
      currentUserId: workspace?.userProfile.id,
      ready: !_titleSourceInvalidated &&
          state.cachedViews.isNotEmpty &&
          _workspaceIsCurrent(id),
    );
    _searchTitles(state);
  }

  void _searchTitles(CommandPaletteState state) => _titleSearch.search(
        _draft,
        filter,
        state.query == _draft
            ? state.combinedResponseItems.values
            : const <SearchResultItem>[],
      );

  Future<void> _refreshTitleSource() async {
    if (_closing || _paletteBloc.isClosed) return;
    _titleSourceInvalidated = true;
    final generation = ++_titleRefreshGeneration;
    final workspace = _workspaceBloc?.state;
    final id = workspace?.currentWorkspace?.workspaceId ?? '';
    final views = await _paletteBloc.reloadCachedViews();
    if (!mounted ||
        _closing ||
        generation != _titleRefreshGeneration ||
        views == null ||
        !_workspaceIsCurrent(id)) return;
    _titleSourceInvalidated = false;
    _titleSearch.updateSource(
      workspaceId: id,
      cachedViews: {for (final view in views) view.id: view},
      excludedViewIds: _paletteBloc.state.trash.map((item) => item.id),
      currentUserId: workspace?.userProfile.id,
      ready: true,
    );
    _searchTitles(_paletteBloc.state);
  }

  void _titleChanged() {
    if (mounted && !_closing && !filter.pageContents) setState(() {});
  }

  bool _workspaceIsCurrent(String workspaceId) {
    final state = _workspaceBloc?.state;
    final action = state?.actionResult;
    return mounted &&
        !_closing &&
        state?.currentWorkspace?.workspaceId == workspaceId &&
        !(action?.actionType == WorkspaceActionType.open &&
            action?.isLoading == true);
  }

  void _syncContentSource(CommandPaletteState state) {
    if (_closing || !filter.pageContents) return;
    final workspace = _workspaceBloc?.state;
    final id = workspace?.currentWorkspace?.workspaceId ?? '';
    _contentSearch.updateSource(
      workspaceId: id,
      cachedViews: state.cachedViews,
      excludedViewIds: state.trash.map((item) => item.id),
      currentUserId: workspace?.userProfile.id,
      ready: state.cachedViews.isNotEmpty && _workspaceIsCurrent(id),
    );
  }

  void _refreshContentSource() {
    _sourceRefresh.run(() {
      if (mounted &&
          !_closing &&
          !_paletteBloc.isClosed &&
          filter.pageContents) {
        _paletteBloc.add(const CommandPaletteEvent.refreshCachedViews());
      }
    });
  }

  void _contentChanged() {
    if (mounted && !_closing && filter.pageContents) setState(() {});
  }

  void _queryChanged(String value) {
    if (_closing || !mounted || _paletteBloc.isClosed) return;
    setState(() => _draft = value);
    _searchTitles(_paletteBloc.state);
    _contentSearch.search(value, enabled: filter.pageContents, filter: filter);
    if (!filter.pageContents) {
      _paletteBloc.add(
        value.isEmpty
            ? const CommandPaletteEvent.clearSearch()
            : CommandPaletteEvent.searchChanged(search: value),
      );
    }
  }

  void _filterChanged(CommandPaletteFilter value) {
    if (_closing || !mounted || _paletteBloc.isClosed) return;
    final wasContentSearch = filter.pageContents;
    setState(() => filter = value);
    _paletteBloc.setContentSearchEnabled(value.pageContents);
    if (value.pageContents) _syncContentSource(_paletteBloc.state);
    _contentSearch.search(_draft, enabled: value.pageContents, filter: value);
    _searchTitles(_paletteBloc.state);
    if (wasContentSearch && !value.pageContents) {
      _paletteBloc.add(CommandPaletteEvent.searchChanged(search: _draft));
    }
  }

  void _stopContentSearch() {
    if (_closing) return;
    _closing = true;
    _sourceRefresh.cancel();
    _contentSearch.stop();
    _titleSearch.stop();
    _paletteBloc.setContentSearchEnabled(false);
  }

  @override
  void dispose() {
    _stopContentSearch();
    _contentSearch.removeListener(_contentChanged);
    _contentSearch.dispose();
    _titleSearch.removeListener(_titleChanged);
    _titleSearch.dispose();
    _sourceRefresh.dispose();
    unawaited(_paletteSubscription?.cancel());
    unawaited(_workspaceSubscription?.cancel());
    super.dispose();
  }

  void _dismiss() {
    if (!mounted) return;
    final route = ModalRoute.of(context);
    if (route != null && route.isCurrent && Navigator.canPop(context)) {
      _stopContentSearch();
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
        // Discard an action queued before switching to local content mode.
        if (filter.pageContents || _closing) return;
        unawaited(startPaletteAIChat(context, dismiss: _dismiss));
      },
      child: BlocBuilder<CommandPaletteBloc, CommandPaletteState>(
        builder: (context, state) {
          final palette = WorkspacePalette.of(context);
          final rawQuery = _draft;
          final commandQuery = paletteCommandModeQuery(rawQuery);
          final inCommandMode = commandQuery != null;
          final inContentMode = filter.pageContents && !inCommandMode;
          final contentState = _contentSearch.state;
          final searchQuery = rawQuery;
          final noQuery = searchQuery.trim().isEmpty, hasQuery = !noQuery;
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
          var cachedViews =
              inContentMode || noQuery ? state.cachedViews : _titleSearch.views;
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
          final searchableItems = inContentMode
              ? contentState.results
                  .map(
                    (hit) => SearchResultItem(
                      id: hit.view.id,
                      icon: ResultIconPB(),
                      content: hit.snippet,
                      displayName: hit.view.name,
                      workspaceId: currentWorkspace?.workspaceId,
                    ),
                  )
                  .toList(growable: false)
              : _titleSearch.results;
          final resultItems = searchableItems
              .where(
                (item) => cachedViews.containsKey(item.id),
              )
              .where(
                (item) => filter.matchesSearchResult(
                  item: item,
                  view: cachedViews[item.id],
                  query: searchQuery,
                  cachedViews: cachedViews,
                  currentUserId: currentUserId,
                ),
              )
              .toList();
          final hasResult = resultItems.isNotEmpty;
          final searching = inContentMode
              ? contentState.isSearching
              : _titleSearch.searching || state.searching;
          final commands = buildPaletteCommands(context);
          final matchedCommands = inCommandMode
              ? rankPaletteCommands(commands, commandQuery)
              // One stray letter matches half of them, which is noise beside
              // the pages somebody was actually looking for.
              : inContentMode || rawQuery.trim().length < 2
                  ? const <PaletteCommand>[]
                  : rankPaletteCommands(
                      commands,
                      rawQuery,
                      limit: paletteInlineCommandLimit,
                    );
          final hasCommands = matchedCommands.isNotEmpty;
          final commandRunQuery = commandQuery ?? rawQuery;
          final spaces =
              context.watch<SpaceBloc?>()?.state.spaces ?? const <ViewPB>[];
          final media = MediaQuery.of(context);
          final anchoredSize = widget.anchoredSize;
          final dialogSize = anchoredSize ??
              commandPaletteDialogSize(
                media.size,
                viewInsets: media.viewInsets,
              );
          final contentInset = media.size.width < 640
              ? WorkspaceTokens.space4
              : WorkspaceTokens.space6;
          final content = widget.shortcutBuilder(
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
                            query: _draft,
                            isLoading: searching,
                            selectAllOnOpen: widget.initialQuery == null,
                            onChanged: _queryChanged,
                            onSubmit: inCommandMode && hasCommands
                                ? () => _runCommand(
                                      matchedCommands.first,
                                      commandRunQuery,
                                    )
                                : hasResult
                                    ? () {
                                        final id = resultItems.first.id;
                                        final allowed = inContentMode
                                            ? _contentSearch.canUseResult(
                                                id, _draft)
                                            : _titleSearch.canUseResult(
                                                id, _draft);
                                        if (!allowed ||
                                            ModalRoute.of(context)?.isCurrent ==
                                                false) return;
                                        final view = cachedViews[id];
                                        if (view == null) return;
                                        _dismiss();
                                        view.navigateTo();
                                      }
                                    : null,
                          ),
                          if (!inCommandMode)
                            SearchFilterBar(
                              filter: filter,
                              spaces: spaces,
                              onChanged: _filterChanged,
                            )
                          else
                            const VSpace(WorkspaceTokens.space4),
                          if (inContentMode)
                            WorkspaceContentSearchStatusView(
                              state: contentState,
                            ),
                          if (!inContentMode &&
                              !inCommandMode &&
                              _titleSearch.timedOut)
                            Semantics(
                              liveRegion: true,
                              child: Text(
                                'Title search timed out. Coverage is incomplete.',
                                key: const ValueKey(
                                    'command-palette-title-timeout'),
                                style: WorkspaceTypography.style(
                                    context, WorkspaceTextRole.metadata),
                              ),
                            ),
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
                  else if (inContentMode)
                    Expanded(
                      child: hasResult
                          ? SearchResultList(
                              cachedViews: {
                                for (final hit in contentState.results)
                                  hit.view.id: hit.view,
                              },
                              resultItems: resultItems,
                              resultSummaries: const [],
                              query: rawQuery,
                              contentSearch: true,
                              canUseResult: (id) =>
                                  _contentSearch.canUseResult(id, _draft),
                            )
                          : WorkspaceContentSearchEmpty(
                              state: contentState,
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
                        resultSummaries: const [],
                        query: rawQuery,
                        metadataOnly: true,
                        canUseResult: (id) =>
                            _titleSearch.canUseResult(id, _draft),
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
                  else if (hasQuery &&
                      !searching &&
                      !_titleSearch.timedOut) ...[
                    SearchAskAiEntrance(),
                    Expanded(
                      child: const NoSearchResultsHint(),
                    ),
                  ],
                  if (hasQuery &&
                      searching &&
                      !hasResult &&
                      !hasCommands &&
                      !inContentMode &&
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
          );
          final shape = RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(WorkspaceTokens.dialogRadius),
          );
          return PopScope<Object?>(
            onPopInvokedWithResult: (didPop, _) {
              if (didPop) _stopContentSearch();
            },
            child: anchoredSize != null
                ? Material(
                    key: const ValueKey('command-palette-anchored-panel'),
                    color: palette.elevatedSurface,
                    elevation: 8,
                    shadowColor: palette.shadow,
                    surfaceTintColor: Colors.transparent,
                    shape: shape,
                    clipBehavior: Clip.antiAlias,
                    child:
                        SizedBox.fromSize(size: anchoredSize, child: content),
                  )
                : FlowyDialog(
                    backgroundColor: palette.elevatedSurface,
                    width: dialogSize.width,
                    elevation: 8,
                    shadowColor: palette.shadow,
                    surfaceTintColor: Colors.transparent,
                    shape: shape,
                    alignment: Alignment.center,
                    insetPadding: commandPaletteDialogInsets(media.size),
                    padding: EdgeInsets.zero,
                    constraints: BoxConstraints.tight(dialogSize),
                    expandHeight: false,
                    child: content,
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
            WorkspaceGlyph.svg(
              FlowySvgs.m_home_search_icon_m,
              color: palette.secondaryText,
              size: 32,
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
