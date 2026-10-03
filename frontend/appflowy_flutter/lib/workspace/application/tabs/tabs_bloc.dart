import 'dart:async';

import 'package:appflowy/plugins/blank/blank.dart';
import 'package:appflowy/plugins/util.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/tabs/page_navigation_history.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/home/home_stack.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:bloc/bloc.dart';
import 'package:collection/collection.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'tabs_bloc.freezed.dart';

class TabsBloc extends Bloc<TabsEvent, TabsState> {
  TabsBloc({
    Future<ViewPB?> Function(String)? loadHistoryView,
    Plugin Function(ViewPB)? buildHistoryPlugin,
    Future<ViewPB?> Function(String)? loadHomeView,
  })  : _loadHistoryView = loadHistoryView ?? _readHistoryView,
        _buildHistoryPlugin = buildHistoryPlugin ?? _pluginForHistory,
        _loadHomeView = loadHomeView ?? _landingHome,
        super(TabsState()) {
    menuSharedState = getIt<MenuSharedState>();
    _dispatch();
  }

  late final MenuSharedState menuSharedState;
  final navigationHistory = PageNavigationHistory();
  final Future<ViewPB?> Function(String) _loadHistoryView;
  final Plugin Function(ViewPB) _buildHistoryPlugin;
  final Future<ViewPB?> Function(String) _loadHomeView;
  final _homePlugins = Set<Plugin>.identity();
  final _newHomeTabs = Map<Plugin, _HomeTabRequest>.identity();
  final _resolvedHomeTabs = Map<Plugin, _HomeTabRequest>.identity();
  bool _closing = false;
  int _homeRequest = 0;
  String? _homeWorkspaceId;
  String? _startupHomeWorkspaceId;
  ({String workspaceId, int request})? _workspaceHomeRequest;
  String? homeViewId;
  int _navigationEpoch = 0;
  int? _pendingHistoryEpoch;

  bool get _historyNavigationPending =>
      _pendingHistoryEpoch == _navigationEpoch;

  bool get canGoBack =>
      !_historyNavigationPending && navigationHistory.canGoBack;
  bool get canGoForward =>
      !_historyNavigationPending && navigationHistory.canGoForward;

  /// Changes on ordinary navigation too, invalidating an in-progress swipe.
  int get navigationEpoch => _navigationEpoch;

  void goBack() => add(const TabsEvent.navigateHistory(forward: false));
  void goForward() => add(const TabsEvent.navigateHistory(forward: true));

  String? _lastOpenedPluginId;
  String? _lastOpenedViewId;
  DateTime? _lastOpenTime;
  static const _deduplicationWindow = Duration(milliseconds: 500);

  @override
  void add(TabsEvent event) {
    // Invalidate at dispatch, not later when the event is handled: a queued
    // deep link/click must also beat an asynchronous Home lookup.
    _homeRequest++;
    if (event is _SwitchWorkspace) {
      _homeWorkspaceId = null;
      homeViewId = null;
      // The shell opens Home only once the workspace change is confirmed.
      // Navigation queued while that change is pending must still win.
      _workspaceHomeRequest = (
        workspaceId: event.workspaceId,
        request: _homeRequest,
      );
    }
    super.add(event);
  }

  /// A fresh session starts at Home. Legacy openedTabs/pinned-tab preferences
  /// are deliberately neither read nor deleted; constructing those plugins
  /// offstage would still mount the page which crashed the previous session.
  /// Explicit navigation and manually opened tabs always take precedence.
  Future<void> openHome({
    required String workspaceId,
    bool startup = false,
    bool newTab = false,
    bool Function()? isCurrent,
  }) async {
    if (_closing ||
        isClosed ||
        workspaceId.isEmpty ||
        isCurrent?.call() == false) {
      return;
    }
    _homeWorkspaceId = workspaceId;
    if (newTab) {
      await _openNewHomeTab(workspaceId, isCurrent);
      return;
    }
    if (startup) {
      if (_startupHomeWorkspaceId == workspaceId) return;
      final firstWorkspace = _startupHomeWorkspaceId == null;
      _startupHomeWorkspaceId = workspaceId;
      final workspaceRequest = _workspaceHomeRequest;
      if (!firstWorkspace || workspaceRequest?.workspaceId == workspaceId) {
        homeViewId = null;
      }
      if (workspaceRequest?.workspaceId == workspaceId) {
        _workspaceHomeRequest = null;
        if (workspaceRequest!.request != _homeRequest) return;
      } else if (firstWorkspace &&
          (_homeRequest != 0 ||
              state.pages != 1 ||
              state.currentPageManager.isPinned ||
              state.currentPageManager.plugin.pluginType != PluginType.blank)) {
        return;
      }
    }
    final request = ++_homeRequest;
    ViewPB? view;
    try {
      view = await _loadHomeView(workspaceId);
    } catch (error, stackTrace) {
      Log.error('Could not open Home: $error', error, stackTrace);
    }
    if (_closing ||
        isClosed ||
        request != _homeRequest ||
        isCurrent?.call() == false) {
      return;
    }
    homeViewId = view?.id;
    final plugin = view == null ? BlankPagePlugin() : _buildHistoryPlugin(view);
    _homePlugins.add(plugin);
    add(
      TabsEvent.openPlugin(
        plugin: plugin,
        view: view,
        // Startup/Home is not a write to the shared latest-view preference.
        setLatest: false,
      ),
    );
  }

  /// A new Home has its own tab lifetime, even when another Home is open.
  /// Resolve into that exact placeholder without stealing a newer selection,
  /// resurrecting a closed tab or replacing a page opened while it was loading.
  Future<void> _openNewHomeTab(
    String workspaceId,
    bool Function()? isCurrent,
  ) async {
    final request = _HomeTabRequest(workspaceId, isCurrent);
    _newHomeTabs[request.placeholder] = request;
    add(
      TabsEvent.openPlugin(plugin: request.placeholder, setLatest: false),
    );
    if (!await request.started.future) return;
    ViewPB? view;
    try {
      view = await _loadHomeView(workspaceId);
    } catch (error, stackTrace) {
      Log.error('Could not open Home', error, stackTrace);
    }
    if (!_isCurrentHomeTab(request)) return;
    final plugin =
        view == null ? request.placeholder : _buildHistoryPlugin(view);
    _resolvedHomeTabs[plugin] = request;
    // This is completion of an existing navigation, not a new user intent.
    // In particular it must not cancel a newer explicit Home request.
    super.add(
      TabsEvent.openPlugin(plugin: plugin, view: view, setLatest: false),
    );
  }

  bool _isCurrentHomeTab(_HomeTabRequest request) =>
      !_closing &&
      !isClosed &&
      request.isCurrent?.call() != false &&
      _homeWorkspaceId == request.workspaceId &&
      state.pageManagers.contains(request.manager) &&
      identical(request.manager.plugin, request.placeholder);

  @override
  Future<void> close() {
    _closing = true;
    _homeRequest++;
    for (final request in _newHomeTabs.values) {
      request.manager.dispose();
      request.started.complete(false);
    }
    _newHomeTabs.clear();
    for (final plugin in [..._resolvedHomeTabs.keys, ..._homePlugins]) {
      state._disposeUnopenedPlugin(plugin);
    }
    _resolvedHomeTabs.clear();
    _homePlugins.clear();
    _navigationEpoch++;
    navigationHistory.clear();
    state.dispose();
    return super.close();
  }

  void _dispatch() {
    on<TabsEvent>(
      (event, emit) async {
        if (_closing) return;
        if (event is _NavigateHistory) {
          await _navigateHistory(event.forward, emit);
          return;
        }
        final switchingWorkspace = event is _SwitchWorkspace;
        _navigationEpoch++;
        ViewPB? visitedView;
        var recordVisit = true;
        event.when(
          navigateHistory: (_) {},
          selectTab: (int index) {
            if (index != state.currentIndex &&
                index >= 0 &&
                index < state.pages) {
              emit(state.copyWith(currentIndex: index));
              _setLatestOpenView();
            }
          },
          moveTab: (oldIndex, newIndex) {
            final next = state.reorderTab(oldIndex, newIndex);
            if (!identical(next, state)) {
              emit(next);
            }
          },
          closeTab: (String pluginId) {
            _closeTab(pluginId, emit);
          },
          closeCurrentTab: () {
            _closeTab(state.currentPageManager.tabId, emit);
          },
          openTab: (Plugin plugin, ViewPB view) {
            visitedView = view;
            state.currentPageManager
              ..hideSecondaryPlugin()
              ..setSecondaryPlugin(BlankPagePlugin());
            emit(state.openView(plugin));
            _setLatestOpenView(view);
          },
          openPlugin: (Plugin plugin, ViewPB? view, bool setLatest) {
            final newHome = _newHomeTabs.remove(plugin);
            if (newHome != null) {
              if (newHome.isCurrent?.call() == false ||
                  _homeWorkspaceId != newHome.workspaceId) {
                recordVisit = false;
                newHome.manager.dispose();
                newHome.started.complete(false);
                return;
              }
              emit(
                state.copyWith(
                  currentIndex: state.pages,
                  pageManagers: [...state.pageManagers, newHome.manager],
                ),
              );
              menuSharedState.latestOpenView = null;
              newHome.started.complete(true);
              return;
            }
            final resolvedHome = _resolvedHomeTabs.remove(plugin);
            if (resolvedHome != null) {
              recordVisit = false;
              if (!_isCurrentHomeTab(resolvedHome)) {
                state._disposeUnopenedPlugin(plugin);
                return;
              }
              final manager = resolvedHome.manager;
              homeViewId = view?.id;
              if (view != null) manager.setPlugin(plugin, false);
              final entry = _historyEntry(manager, view);
              if (entry != null) {
                navigationHistory.resolveHomeTab(manager.tabId, entry);
              }
              if (identical(state.currentPageManager, manager)) {
                menuSharedState.latestOpenView = view;
              }
              emit(state.copyWith(pageManagers: [...state.pageManagers]));
              return;
            }
            final now = DateTime.now();
            final openingHome = _homePlugins.remove(plugin);

            // deduplicate. skip if same plugin and view were just opened
            if (_lastOpenedPluginId == plugin.id &&
                state.currentPageManager.plugin.id == plugin.id &&
                _lastOpenedViewId == view?.id &&
                _lastOpenTime != null) {
              final timeSinceLastOpen = now.difference(_lastOpenTime!);
              if (timeSinceLastOpen < _deduplicationWindow) {
                state._disposeUnopenedPlugin(plugin);
                return;
              }
            }

            _lastOpenedPluginId = plugin.id;
            _lastOpenedViewId = view?.id;
            _lastOpenTime = now;
            visitedView = view;

            state.currentPageManager
              ..hideSecondaryPlugin()
              ..setSecondaryPlugin(BlankPagePlugin());
            // Home is its own destination. Reuse the initial empty tab, but
            // never replace a manually opened/pinned page just to go Home.
            emit(
              openingHome &&
                      (state.currentPageManager.isPinned ||
                          state.currentPageManager.plugin.pluginType !=
                              PluginType.blank)
                  ? state.openView(plugin, setLatest: false)
                  : state.openPlugin(plugin: plugin, setLatest: setLatest),
            );
            if (openingHome) menuSharedState.latestOpenView = view;
            if (setLatest) {
              // the space view should be filtered out.
              if (view != null && view.isSpace) {
                return;
              }
              _setLatestOpenView(view);
              // Opening/restoring a page must not unfold the sidebar. Tree
              // expansion is controlled explicitly by its disclosure buttons.
            }
          },
          closeOtherTabs: (String pluginId) {
            final target = state.managerForTab(pluginId);
            if (target == null) return;
            final previousManagers = [...state._pageManagers];
            final pageManagers = [
              ...state._pageManagers
                  .where((pm) => identical(pm, target) || pm.isPinned),
            ];

            int newIndex;
            if (state.currentPageManager.isPinned) {
              // Retain current index if it's already pinned
              newIndex = pageManagers.indexOf(state.currentPageManager);
            } else {
              newIndex = pageManagers.indexOf(target);
            }

            emit(
              state.copyWith(
                currentIndex: newIndex,
                pageManagers: pageManagers,
              ),
            );

            for (final manager in previousManagers) {
              if (!pageManagers.contains(manager)) manager.dispose();
            }
            _setLatestOpenView();
          },
          togglePin: (String pluginId) {
            final pm = state.managerForTab(pluginId);
            if (pm != null) {
              final index = state._pageManagers.indexOf(pm);

              int newIndex = state.currentIndex;
              if (pm.isPinned) {
                // Unpinning logic
                final indexOfFirstUnpinnedTab =
                    state._pageManagers.indexWhere((tab) => !tab.isPinned);

                // Determine the correct insertion point
                final newUnpinnedIndex = indexOfFirstUnpinnedTab != -1
                    ? indexOfFirstUnpinnedTab // Insert before the first unpinned tab
                    : state._pageManagers
                        .length; // Append at the end if no unpinned tabs exist

                state._pageManagers.removeAt(index);

                final adjustedUnpinnedIndex = newUnpinnedIndex > index
                    ? newUnpinnedIndex - 1
                    : newUnpinnedIndex;

                state._pageManagers.insert(adjustedUnpinnedIndex, pm);
                newIndex = _adjustCurrentIndex(
                  currentIndex: state.currentIndex,
                  tabIndex: index,
                  newIndex: adjustedUnpinnedIndex,
                );
              } else {
                // Pinning logic
                final indexOfLastPinnedTab =
                    state._pageManagers.lastIndexWhere((tab) => tab.isPinned);
                final newPinnedIndex = indexOfLastPinnedTab + 1;

                state._pageManagers.removeAt(index);

                final adjustedPinnedIndex = newPinnedIndex > index
                    ? newPinnedIndex - 1
                    : newPinnedIndex;

                state._pageManagers.insert(adjustedPinnedIndex, pm);
                newIndex = _adjustCurrentIndex(
                  currentIndex: state.currentIndex,
                  tabIndex: index,
                  newIndex: adjustedPinnedIndex,
                );
              }

              pm.isPinned = !pm.isPinned;

              emit(
                state.copyWith(
                  currentIndex: newIndex,
                  pageManagers: [...state._pageManagers],
                ),
              );
            }
          },
          openSecondaryPlugin: (plugin, view) {
            state.currentPageManager
              ..setSecondaryPlugin(plugin)
              ..showSecondaryPlugin();
          },
          closeSecondaryPlugin: () {
            final pageManager = state.currentPageManager;
            pageManager.hideSecondaryPlugin();
          },
          expandSecondaryPlugin: () {
            final pageManager = state.currentPageManager;
            pageManager
              ..hideSecondaryPlugin()
              ..expandSecondaryPlugin();
            _setLatestOpenView();
          },
          switchWorkspace: (workspaceId) {
            navigationHistory.clear();
            _lastOpenedPluginId = null;
            _lastOpenedViewId = null;
            _lastOpenTime = null;
            final current = state.currentPageManager;

            // Close all tabs except current
            final pagesToClose = [
              ...state._pageManagers
                  .where((pm) => !identical(pm, current) && !pm.isPinned),
            ];

            if (pagesToClose.isNotEmpty) {
              var newstate = state;
              for (final pm in pagesToClose) {
                newstate = newstate.closeView(pm.tabId);
              }
              emit(newstate.copyWith(currentIndex: 0));
            }
          },
        );
        if (!switchingWorkspace && recordVisit) {
          _recordVisit(visitedView);
        }
      },
    );
  }

  void _closeTab(String tabId, Emitter<TabsState> emit) {
    if (state.managerForTab(tabId) == null) return;
    final lastTab = state.pages == 1;
    emit(state.closeView(tabId));
    _setLatestOpenView();
    if (lastTab) {
      _lastOpenedPluginId = null;
      _lastOpenedViewId = null;
      _lastOpenTime = null;
      menuSharedState.latestOpenView = null;
      final workspaceId = _homeWorkspaceId;
      if (workspaceId != null) {
        unawaited(openHome(workspaceId: workspaceId));
      }
    }
  }

  void _recordVisit(ViewPB? view) {
    final entry = _historyEntry(state.currentPageManager, view);
    if (entry != null) navigationHistory.record(entry);
  }

  PageHistoryEntry? _historyEntry(PageManager manager, ViewPB? view) {
    final plugin = manager.plugin;
    final notifier = plugin.notifier;
    final currentView = view?.id == plugin.id
        ? view
        : notifier is ViewPluginNotifier
            ? notifier.view
            : null;
    if (currentView != null && currentView.id.isNotEmpty) {
      return PageHistoryEntry(
        tabId: manager.tabId,
        pluginType: plugin.pluginType,
        viewId: currentView.id,
        workspaceRoot:
            currentView.parentViewId.isEmpty && currentView.isWorkspaceFolder
                ? currentView
                : null,
      );
    } else if (const {
      PluginType.blank,
      PluginType.trash,
      PluginType.templates,
      PluginType.extensions,
      PluginType.workflows,
      PluginType.recents,
      PluginType.favorites,
      PluginType.pageLibrary,
    }.contains(plugin.pluginType)) {
      return PageHistoryEntry(
        tabId: manager.tabId,
        pluginType: plugin.pluginType,
      );
    }
    return null;
  }

  Future<void> _navigateHistory(bool forward, Emitter<TabsState> emit) async {
    if (_historyNavigationPending) return;
    final epoch = ++_navigationEpoch;
    _pendingHistoryEpoch = epoch;
    try {
      PageHistoryEntry? entry;
      while ((entry = navigationHistory.peek(forward: forward)) != null) {
        final target = entry!;
        bool matches(PageManager pm) => target.viewId != null
            ? pm.plugin.id == target.viewId
            : pm.plugin.pluginType == target.pluginType;
        final exactTab = state.pageManagers.indexWhere(
          (pm) => pm.tabId == target.tabId && matches(pm),
        );
        final existing =
            exactTab >= 0 ? exactTab : state.pageManagers.indexWhere(matches);
        final notifier =
            existing >= 0 ? state.pageManagers[existing].plugin.notifier : null;
        if (notifier is ViewPluginNotifier &&
            notifier.isDeleted.value != null) {
          navigationHistory.discard(target);
          continue;
        }
        ViewPB? view = target.workspaceRoot;
        if (target.viewId != null && existing < 0 && view == null) {
          view = await _loadHistoryView(target.viewId!);
          if (isClosed || emit.isDone || epoch != _navigationEpoch) return;
          if (view == null) {
            navigationHistory.discard(target);
            continue;
          }
        }
        if (isClosed || emit.isDone || epoch != _navigationEpoch) return;
        final plugin = existing < 0
            ? view != null
                ? _buildHistoryPlugin(view)
                : makePlugin(pluginType: target.pluginType)
            : null;
        navigationHistory.move(forward: forward);
        _lastOpenedPluginId = null;
        _lastOpenedViewId = null;
        _lastOpenTime = null;
        state.currentPageManager.hideSecondaryPlugin();
        emit(
          existing >= 0
              ? state.copyWith(currentIndex: existing)
              : state.openPlugin(plugin: plugin!),
        );
        _setLatestOpenView(view);
        return;
      }
    } catch (error, stackTrace) {
      Log.error('Could not navigate page history: $error', error, stackTrace);
    } finally {
      if (_pendingHistoryEpoch == epoch) _pendingHistoryEpoch = null;
    }
  }

  static Future<ViewPB?> _readHistoryView(String id) async =>
      (await ViewBackendService.getView(id)).fold((view) => view, (_) => null);

  /// Home is the workspace landing page, never a page standing in for it.
  static Future<ViewPB?> _landingHome(String _) async => null;

  static Plugin _pluginForHistory(ViewPB view) => view.plugin();

  void _setLatestOpenView([ViewPB? view]) {
    if (view != null) {
      menuSharedState.latestOpenView = view;
    } else {
      final pageManager = state.currentPageManager;
      final notifier = pageManager.plugin.notifier;
      if (notifier is ViewPluginNotifier &&
          menuSharedState.latestOpenView?.id != notifier.view.id) {
        menuSharedState.latestOpenView = notifier.view;
      }
    }
  }

  int _adjustCurrentIndex({
    required int currentIndex,
    required int tabIndex,
    required int newIndex,
  }) {
    if (tabIndex < currentIndex && newIndex >= currentIndex) {
      return currentIndex - 1; // Tab moved forward, shift currentIndex back
    } else if (tabIndex > currentIndex && newIndex <= currentIndex) {
      return currentIndex + 1; // Tab moved backward, shift currentIndex forward
    } else if (tabIndex == currentIndex) {
      return newIndex; // Tab is the current tab, update to newIndex
    }

    return currentIndex;
  }

  /// Adds a [TabsEvent.openTab] event for the provided [ViewPB]
  void openTab(ViewPB view) =>
      add(TabsEvent.openTab(plugin: view.plugin(), view: view));

  /// Reorders the existing managers; no plugin is reopened or reinitialised.
  /// Indices follow ReorderableListView's insertion-index convention.
  void reorderTab(int oldIndex, int newIndex) =>
      add(TabsEvent.moveTab(oldIndex: oldIndex, newIndex: newIndex));

  /// Adds a [TabsEvent.openPlugin] event for the provided [ViewPB]
  void openPlugin(
    ViewPB view, {
    Map<String, dynamic> arguments = const {},
    bool setLatest = true,
  }) {
    add(
      TabsEvent.openPlugin(
        plugin: view.plugin(arguments: arguments),
        view: view,
        setLatest: setLatest,
      ),
    );
  }
}

class _HomeTabRequest {
  _HomeTabRequest(this.workspaceId, this.isCurrent);

  final String workspaceId;
  final bool Function()? isCurrent;
  final placeholder = BlankPagePlugin();
  late final manager = PageManager(plugin: placeholder);
  final started = Completer<bool>();
}

@freezed
class TabsEvent with _$TabsEvent {
  const factory TabsEvent.navigateHistory({required bool forward}) =
      _NavigateHistory;

  const factory TabsEvent.moveTab({
    @Default(-1) int oldIndex,
    @Default(-1) int newIndex,
  }) = _MoveTab;

  const factory TabsEvent.closeTab(String pluginId) = _CloseTab;

  const factory TabsEvent.closeOtherTabs(String pluginId) = _CloseOtherTabs;

  const factory TabsEvent.closeCurrentTab() = _CloseCurrentTab;

  const factory TabsEvent.selectTab(int index) = _SelectTab;

  const factory TabsEvent.togglePin(String pluginId) = _TogglePin;

  const factory TabsEvent.openTab({
    required Plugin plugin,
    required ViewPB view,
  }) = _OpenTab;

  const factory TabsEvent.openPlugin({
    required Plugin plugin,
    ViewPB? view,
    @Default(true) bool setLatest,
  }) = _OpenPlugin;

  const factory TabsEvent.openSecondaryPlugin({
    required Plugin plugin,
    ViewPB? view,
  }) = _OpenSecondaryPlugin;

  const factory TabsEvent.closeSecondaryPlugin() = _CloseSecondaryPlugin;

  const factory TabsEvent.expandSecondaryPlugin() = _ExpandSecondaryPlugin;

  const factory TabsEvent.switchWorkspace(String workspaceId) =
      _SwitchWorkspace;
}

class TabsState {
  TabsState({
    this.currentIndex = 0,
    List<PageManager>? pageManagers,
  }) : _pageManagers = pageManagers ?? [PageManager()];

  final int currentIndex;
  final List<PageManager> _pageManagers;

  int get pages => _pageManagers.length;

  PageManager get currentPageManager => _pageManagers[currentIndex];

  List<PageManager> get pageManagers => _pageManagers;

  bool get isAllPinned => _pageManagers.every((pm) => pm.isPinned);

  /// This opens a new tab given a [Plugin].
  ///
  /// If the [Plugin.id] is already associated with an open tab,
  /// then it selects that tab.
  ///
  TabsState openView(Plugin plugin, {bool setLatest = true}) {
    final existingIndex = _indexOfPlugin(plugin.id);
    if (existingIndex != -1 &&
        _pageManagers[existingIndex].plugin.runtimeType != plugin.runtimeType) {
      _pageManagers[existingIndex].setPlugin(plugin, setLatest);
      return copyWith(
        currentIndex: existingIndex,
        pageManagers: [..._pageManagers],
      );
    }
    final selectExistingPlugin = _selectPluginIfOpen(plugin.id);

    if (selectExistingPlugin == null) {
      _pageManagers.add(PageManager()..setPlugin(plugin, setLatest));

      return copyWith(
        currentIndex: pages - 1,
        pageManagers: [..._pageManagers],
      );
    }

    _disposeUnopenedPlugin(plugin);
    return selectExistingPlugin;
  }

  TabsState closeView(String pluginId) {
    final target = managerForTab(pluginId);
    if (target == null) return this;
    final remaining = _pageManagers.where((pm) => pm != target).toList();
    if (remaining.isEmpty) {
      target.dispose();
      // The shell always owns a valid page; TabsBloc resolves its Home choice.
      return TabsState();
    }
    final selectedIndex = remaining.indexOf(currentPageManager);

    for (final manager in _pageManagers) {
      if (!remaining.contains(manager)) manager.dispose();
    }

    return copyWith(
      // Closing a background tab must not switch away from the current page.
      currentIndex: selectedIndex >= 0
          ? selectedIndex
          : currentIndex.clamp(0, remaining.length - 1),
      pageManagers: remaining,
    );
  }

  /// UI commands address a tab, while legacy callers may still pass a view ID.
  /// Distinct Home tabs can share a page without closing/pinning each other.
  PageManager? managerForTab(String id) =>
      _pageManagers.firstWhereOrNull((pm) => pm.tabId == id) ??
      _pageManagers.firstWhereOrNull((pm) => pm.plugin.id == id);

  TabsState reorderTab(int oldIndex, int newIndex) {
    if (oldIndex < 0 || oldIndex >= pages || newIndex < 0 || newIndex > pages) {
      return this;
    }
    final manager = _pageManagers[oldIndex];
    final pinnedCount = _pageManagers.where((pm) => pm.isPinned).length;
    final insertionIndex = newIndex > oldIndex ? newIndex - 1 : newIndex;
    // Pinned tabs stay together at the leading edge; dragging never changes
    // whether a tab is pinned.
    final target = insertionIndex.clamp(
      manager.isPinned ? 0 : pinnedCount,
      manager.isPinned ? pinnedCount - 1 : pages - 1,
    );
    if (target == oldIndex) {
      return this;
    }
    final reordered = [..._pageManagers]
      ..removeAt(oldIndex)
      ..insert(target, manager);
    return copyWith(
      currentIndex: reordered.indexOf(currentPageManager),
      pageManagers: reordered,
    );
  }

  /// This opens a plugin in the current selected tab,
  /// due to how Document currently works, only one tab
  /// per plugin can currently be active.
  ///
  /// If the plugin is already open in a tab, then that tab
  /// will become selected.
  ///
  TabsState openPlugin({required Plugin plugin, bool setLatest = true}) {
    final existingIndex = _indexOfPlugin(plugin.id);
    if (existingIndex != -1 &&
        _pageManagers[existingIndex].plugin.runtimeType != plugin.runtimeType) {
      _pageManagers[existingIndex].setPlugin(plugin, setLatest);
      return copyWith(
        currentIndex: existingIndex,
        pageManagers: [..._pageManagers],
      );
    }
    final selectExistingPlugin = _selectPluginIfOpen(plugin.id);

    if (selectExistingPlugin == null) {
      final pageManagers = [..._pageManagers];
      pageManagers[currentIndex].setPlugin(plugin, setLatest);

      return copyWith(pageManagers: pageManagers);
    }

    _disposeUnopenedPlugin(plugin);
    return selectExistingPlugin;
  }

  void _disposeUnopenedPlugin(Plugin candidate) {
    if (_pageManagers.any(
      (manager) =>
          identical(candidate, manager.plugin) ||
          identical(candidate, manager.secondaryNotifier.plugin),
    )) {
      return;
    }
    // ViewPluginNotifier starts a backend subscription in the constructor.
    // A duplicate was never init()ialized, so its late-final blocs cannot be
    // disposed, but the constructor-owned notifier still must be released.
    candidate.notifier?.dispose();
  }

  /// Checks if a [Plugin.id] is already associated with an open tab.
  /// Returns a [TabState] with new index if there is a match.
  ///
  /// If no match it returns null
  ///
  TabsState? _selectPluginIfOpen(String id) {
    final index = _indexOfPlugin(id);

    if (index == -1) {
      return null;
    }

    if (index == currentIndex) {
      return this;
    }

    return copyWith(currentIndex: index);
  }

  int _indexOfPlugin(String id) =>
      _pageManagers.indexWhere((pm) => pm.plugin.id == id);

  TabsState copyWith({
    int? currentIndex,
    List<PageManager>? pageManagers,
  }) =>
      TabsState(
        currentIndex: currentIndex ?? this.currentIndex,
        pageManagers: pageManagers ?? _pageManagers,
      );

  void dispose() {
    for (final manager in pageManagers) {
      manager.dispose();
    }
  }
}
