import 'dart:async';

import 'package:appflowy/plugins/trash/application/trash_listener.dart';
import 'package:appflowy/plugins/trash/application/trash_service.dart';
import 'package:appflowy/workspace/application/command_palette/palette_scope.dart';
import 'package:appflowy/workspace/application/command_palette/search_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:bloc/bloc.dart';
import 'package:flutter/foundation.dart';
import 'package:freezed_annotation/freezed_annotation.dart';

part 'command_palette_bloc.freezed.dart';

class Debouncer {
  Debouncer({required this.delay});

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void dispose() {
    _timer?.cancel();
  }

  void cancel() {
    _timer?.cancel();
  }
}

class CommandPaletteBloc
    extends Bloc<CommandPaletteEvent, CommandPaletteState> {
  CommandPaletteBloc({
    Future<FlowyResult<SearchResponseStream, FlowyError>> Function(String)?
        search,
    Future<List<ViewPB>?> Function()? readCachedViews,
    bool listenToTrash = true,
  })  : _search = search ?? SearchBackendService.performSearch,
        _readCachedViews = readCachedViews ?? _nativeCachedViews,
        super(CommandPaletteState.initial()) {
    on<_SearchChanged>(_onSearchChanged);
    on<_PerformSearch>(_onPerformSearch);
    on<_NewSearchStream>(_onNewSearchStream);
    on<_ResultsChanged>(_onResultsChanged);
    on<_TrashChanged>(_onTrashChanged);
    on<_WorkspaceChanged>(_onWorkspaceChanged);
    on<_ClearSearch>(_onClearSearch);
    on<_GoingToAskAI>(_onGoingToAskAI);
    on<_AskedAI>(_onAskedAI);
    on<_RefreshCachedViews>(_onRefreshCachedViews);
    on<_UpdateCachedViews>(_onUpdateCachedViews);

    if (listenToTrash) _initTrash();
    _refreshCachedViews();
  }

  final Debouncer _searchDebouncer = Debouncer(
    delay: const Duration(milliseconds: 300),
  );
  final TrashService _trashService = TrashService();
  final TrashListener _trashListener = TrashListener();
  String? _activeQuery;
  bool _contentSearchEnabled = false;
  int _searchGeneration = 0;
  int _viewGeneration = 0;
  final _streamGenerations = Expando<int>();
  final _viewGenerations = Expando<int>();
  final _eventGenerations = Expando<int>();
  final Future<FlowyResult<SearchResponseStream, FlowyError>> Function(String)
      _search;
  final Future<List<ViewPB>?> Function() _readCachedViews;
  String? _pendingQuery;

  static Future<List<ViewPB>?> _nativeCachedViews() async =>
      (await ViewBackendService.getAllViews()).toNullable()?.items;

  /// Invalidate at input dispatch, not 300 ms later. A stream callback or a
  /// queued performSearch must never publish against newer text in the field.
  @override
  void add(CommandPaletteEvent event) {
    if (event is _SearchChanged ||
        event is _PerformSearch ||
        event is _ClearSearch ||
        event is _WorkspaceChanged) {
      _cancelMetadataSearch();
      _pendingQuery = event is _SearchChanged
          ? event.search
          : event is _PerformSearch
              ? event.search
              : null;
    }
    if (event is _WorkspaceChanged) _viewGeneration++;
    if (event is _SearchChanged || event is _PerformSearch) {
      _eventGenerations[event] = _searchGeneration;
    }
    super.add(event);
  }

  /// The desktop modal owns this mode; no persistent/generated search state
  /// or draft is changed. Late metadata streams must not leak into local mode.
  void setContentSearchEnabled(bool enabled) {
    if (isClosed || _contentSearchEnabled == enabled) return;
    _contentSearchEnabled = enabled;
    _cancelMetadataSearch();
  }

  void _cancelMetadataSearch() {
    _searchGeneration++;
    _searchDebouncer.cancel();
    _activeQuery = null;
    unawaited(state.searchResponseStream?.dispose());
  }

  @override
  Future<void> close() {
    _searchGeneration++;
    _viewGeneration++;
    _trashListener.close();
    _searchDebouncer.dispose();
    state.searchResponseStream?.dispose();
    return super.close();
  }

  Future<void> _initTrash() async {
    _trashListener.start(
      trashUpdated: (trashOrFailed) {
        if (!isClosed) {
          add(
            CommandPaletteEvent.trashChanged(
              trash: trashOrFailed.toNullable(),
            ),
          );
        }
      },
    );

    final trashOrFailure = await _trashService.readTrash();
    trashOrFailure.fold(
      (trash) {
        if (!isClosed) {
          add(CommandPaletteEvent.trashChanged(trash: trash.items));
        }
      },
      (error) => debugPrint('Failed to load trash: $error'),
    );
  }

  /// Also acknowledges unchanged snapshots to modal-local access indexes.
  Future<List<ViewPB>?> reloadCachedViews() => _refreshCachedViews();

  Future<List<ViewPB>?> _refreshCachedViews() async {
    /// Sometimes non-existent views appear in the search results
    /// and the icon data for the search results is empty
    /// Fetching all views can temporarily resolve these issues
    final generation = ++_viewGeneration;
    List<ViewPB>? views;
    try {
      views = await _readCachedViews();
    } on Object {
      return null;
    }
    if (views == null || isClosed || generation != _viewGeneration) {
      return null;
    }
    final event = CommandPaletteEvent.updateCachedViews(views: views);
    _viewGenerations[event] = generation;
    add(event);
    return views;
  }

  FutureOr<void> _onRefreshCachedViews(
    _RefreshCachedViews event,
    Emitter<CommandPaletteState> emit,
  ) {
    _refreshCachedViews();
  }

  void _onUpdateCachedViews(
    _UpdateCachedViews event,
    Emitter<CommandPaletteState> emit,
  ) {
    final generation = _viewGenerations[event];
    if (generation != null && generation != _viewGeneration) return;
    final cachedViews = <String, ViewPB>{};
    for (final view in event.views) {
      cachedViews[view.id] = view;
    }
    emit(state.copyWith(cachedViews: cachedViews));
  }

  void _onSearchChanged(
    _SearchChanged event,
    Emitter<CommandPaletteState> emit,
  ) {
    if (_contentSearchEnabled ||
        _eventGenerations[event] != _searchGeneration) {
      return;
    }
    emit(
      state.copyWith(
        query: event.search,
        searchId: null,
        searchResponseStream: null,
        searching: event.search.trim().isNotEmpty,
        serverResponseItems: [],
        localResponseItems: [],
        combinedResponseItems: {},
        resultSummaries: [],
        generatingAIOverview: false,
      ),
    );
    final generation = _searchGeneration;
    // A command query or a question never reaches the backend, so there is
    // nothing to wait for — filtering the commands as fast as they are typed.
    if (isPaletteLocalQuery(event.search)) {
      _searchDebouncer.cancel();
      _activeQuery = null;
      add(CommandPaletteEvent.performSearch(search: event.search));
    } else {
      _searchDebouncer.run(
        () {
          if (!isClosed && generation == _searchGeneration) {
            add(CommandPaletteEvent.performSearch(search: event.search));
          }
        },
      );
    }
  }

  FutureOr<void> _onPerformSearch(
    _PerformSearch event,
    Emitter<CommandPaletteState> emit,
  ) async {
    if (_contentSearchEnabled ||
        _eventGenerations[event] != _searchGeneration) {
      return;
    }
    final generation = _searchGeneration;
    _pendingQuery = event.search;
    final isCommandQuery = isPaletteLocalQuery(event.search);
    if (event.search.trim().isEmpty ||
        isCommandQuery ||
        event.search.length > 256) {
      emit(
        state.copyWith(
          query: event.search.isEmpty ? null : event.search,
          searchId: null,
          searchResponseStream: null,
          serverResponseItems: [],
          localResponseItems: [],
          combinedResponseItems: {},
          resultSummaries: [],
          searching: false,
          generatingAIOverview: false,
        ),
      );
    } else {
      emit(
        state.copyWith(
          query: event.search,
          searching: true,
          searchId: null,
          searchResponseStream: null,
          serverResponseItems: [],
          localResponseItems: [],
          combinedResponseItems: {},
          resultSummaries: [],
        ),
      );
      _activeQuery = event.search;

      bool current() =>
          !isClosed &&
          !emit.isDone &&
          !_contentSearchEnabled &&
          generation == _searchGeneration &&
          _activeQuery == event.search;
      try {
        final result = await _search(event.search.trim());
        result.fold(
          (stream) {
            if (current()) {
              _streamGenerations[stream] = generation;
              add(CommandPaletteEvent.newSearchStream(stream: stream));
            } else {
              unawaited(stream.dispose());
            }
          },
          (_) {
            if (current()) {
              emit(
                state.copyWith(
                  searching: false,
                  generatingAIOverview: false,
                ),
              );
            }
          },
        );
      } on Object {
        if (current()) {
          emit(state.copyWith(searching: false, generatingAIOverview: false));
        }
      }
    }
  }

  void _onNewSearchStream(
    _NewSearchStream event,
    Emitter<CommandPaletteState> emit,
  ) {
    if (_contentSearchEnabled ||
        _streamGenerations[event.stream] != _searchGeneration ||
        _activeQuery == null) {
      unawaited(event.stream.dispose());
      return;
    }
    state.searchResponseStream?.dispose();
    emit(
      state.copyWith(
        searchId: event.stream.searchId,
        searchResponseStream: event.stream,
      ),
    );
    final generation = _streamGenerations[event.stream]!;
    event.stream.listen(
      onLocalItems: (items, searchId) => _handleResultsUpdate(
        generation: generation,
        searchId: searchId,
        localItems: items,
      ),
      onServerItems: (items, searchId, searching, generatingAIOverview) =>
          _handleResultsUpdate(
        generation: generation,
        searchId: searchId,
        summaries: [], // when got server search result, summaries should be empty
        serverItems: items,
        searching: searching,
        generatingAIOverview: generatingAIOverview,
      ),
      onSummaries: (summaries, searchId, searching, generatingAIOverview) =>
          _handleResultsUpdate(
        generation: generation,
        searchId: searchId,
        summaries: summaries,
        searching: searching,
        generatingAIOverview: generatingAIOverview,
      ),
      onFinished: (searchId) => _handleResultsUpdate(
        generation: generation,
        searchId: searchId,
        searching: false,
      ),
    );
  }

  void _handleResultsUpdate({
    required int generation,
    required String searchId,
    List<SearchResponseItemPB>? serverItems,
    List<LocalSearchResponseItemPB>? localItems,
    List<SearchSummaryPB>? summaries,
    bool searching = true,
    bool generatingAIOverview = false,
  }) {
    if (generation == _searchGeneration && _isActiveSearch(searchId)) {
      final event = CommandPaletteEvent.resultsChanged(
        searchId: searchId,
        serverItems: serverItems,
        localItems: localItems,
        summaries: summaries,
        searching: searching,
        generatingAIOverview: generatingAIOverview,
      );
      _eventGenerations[event] = generation;
      add(event);
    }
  }

  FutureOr<void> _onResultsChanged(
    _ResultsChanged event,
    Emitter<CommandPaletteState> emit,
  ) async {
    if (!_isActiveSearch(event.searchId) ||
        _eventGenerations[event] != _searchGeneration) {
      return;
    }

    final combinedItems = <String, SearchResultItem>{};
    for (final item in event.serverItems ?? state.serverResponseItems) {
      combinedItems[item.id] = SearchResultItem(
        id: item.id,
        icon: item.icon,
        displayName: item.displayName,
        content: item.content,
        workspaceId: item.workspaceId,
      );
    }

    for (final item in event.localItems ?? state.localResponseItems) {
      combinedItems.putIfAbsent(
        item.id,
        () => SearchResultItem(
          id: item.id,
          icon: item.icon,
          displayName: item.displayName,
          content: '',
          workspaceId: item.workspaceId,
        ),
      );
    }

    emit(
      state.copyWith(
        serverResponseItems: event.serverItems ?? state.serverResponseItems,
        localResponseItems: event.localItems ?? state.localResponseItems,
        resultSummaries: event.summaries ?? state.resultSummaries,
        combinedResponseItems: combinedItems,
        searching: event.searching,
        generatingAIOverview: event.generatingAIOverview,
      ),
    );
  }

  FutureOr<void> _onTrashChanged(
    _TrashChanged event,
    Emitter<CommandPaletteState> emit,
  ) async {
    if (event.trash != null) {
      emit(state.copyWith(trash: event.trash!));
    } else {
      final trashOrFailure = await _trashService.readTrash();
      trashOrFailure.fold((trash) {
        emit(state.copyWith(trash: trash.items));
      }, (error) {
        // Optionally handle error; otherwise, we simply do nothing.
      });
    }
  }

  FutureOr<void> _onWorkspaceChanged(
    _WorkspaceChanged event,
    Emitter<CommandPaletteState> emit,
  ) {
    emit(
      state.copyWith(
        query: '',
        cachedViews: {},
        searchId: null,
        searchResponseStream: null,
        serverResponseItems: [],
        localResponseItems: [],
        combinedResponseItems: {},
        resultSummaries: [],
        searching: false,
        generatingAIOverview: false,
      ),
    );
    _refreshCachedViews();
  }

  FutureOr<void> _onClearSearch(
    _ClearSearch event,
    Emitter<CommandPaletteState> emit,
  ) {
    emit(commandPaletteStateAfterClear(state));
  }

  FutureOr<void> _onGoingToAskAI(
    _GoingToAskAI event,
    Emitter<CommandPaletteState> emit,
  ) {
    emit(state.copyWith(askAI: true, askAISources: event.sources));
  }

  FutureOr<void> _onAskedAI(
    _AskedAI event,
    Emitter<CommandPaletteState> emit,
  ) {
    emit(state.copyWith(askAI: false, askAISources: null));
  }

  bool _isActiveSearch(String searchId) =>
      !isClosed &&
      !_contentSearchEnabled &&
      _activeQuery != null &&
      _activeQuery == _pendingQuery &&
      state.searchId == searchId;
}

@freezed
class CommandPaletteEvent with _$CommandPaletteEvent {
  const factory CommandPaletteEvent.searchChanged({required String search}) =
      _SearchChanged;
  const factory CommandPaletteEvent.performSearch({required String search}) =
      _PerformSearch;
  const factory CommandPaletteEvent.newSearchStream({
    required SearchResponseStream stream,
  }) = _NewSearchStream;
  const factory CommandPaletteEvent.resultsChanged({
    required String searchId,
    required bool searching,
    required bool generatingAIOverview,
    List<SearchResponseItemPB>? serverItems,
    List<LocalSearchResponseItemPB>? localItems,
    List<SearchSummaryPB>? summaries,
  }) = _ResultsChanged;

  const factory CommandPaletteEvent.trashChanged({
    @Default(null) List<TrashPB>? trash,
  }) = _TrashChanged;
  const factory CommandPaletteEvent.workspaceChanged({
    @Default(null) String? workspaceId,
  }) = _WorkspaceChanged;
  const factory CommandPaletteEvent.clearSearch() = _ClearSearch;
  const factory CommandPaletteEvent.goingToAskAI({
    @Default(null) List<SearchSourcePB>? sources,
  }) = _GoingToAskAI;
  const factory CommandPaletteEvent.askedAI() = _AskedAI;
  const factory CommandPaletteEvent.refreshCachedViews() = _RefreshCachedViews;
  const factory CommandPaletteEvent.updateCachedViews({
    required List<ViewPB> views,
  }) = _UpdateCachedViews;
}

class SearchResultItem {
  const SearchResultItem({
    required this.id,
    required this.icon,
    required this.content,
    required this.displayName,
    this.workspaceId,
  });

  final String id;
  final String content;
  final ResultIconPB icon;
  final String displayName;
  final String? workspaceId;
}

CommandPaletteState commandPaletteStateAfterClear(CommandPaletteState state) {
  return CommandPaletteState.initial().copyWith(
    cachedViews: state.cachedViews,
    trash: state.trash,
  );
}

List<SearchResultItem> includeWorkspaceFolderSearchResults({
  required Iterable<SearchResultItem> searchResults,
  required Map<String, ViewPB> cachedViews,
  required String query,
  Iterable<String> excludedViewIds = const [],
}) {
  final resultsById = {
    for (final item in searchResults) item.id: item,
  };
  final normalizedQuery = query.trim().toLowerCase();
  if (normalizedQuery.isEmpty) {
    return resultsById.values.toList(growable: false);
  }

  final excluded = excludedViewIds.toSet();
  for (final view in cachedViews.values) {
    if (!view.isWorkspaceFolder ||
        excluded.contains(view.id) ||
        !view.name.toLowerCase().contains(normalizedQuery)) {
      continue;
    }
    resultsById.putIfAbsent(
      view.id,
      () => SearchResultItem(
        id: view.id,
        icon: ResultIconPB(),
        content: '',
        displayName: view.name,
      ),
    );
  }
  return resultsById.values.toList(growable: false);
}

@freezed
class CommandPaletteState with _$CommandPaletteState {
  const CommandPaletteState._();
  const factory CommandPaletteState({
    @Default(null) String? query,
    @Default([]) List<SearchResponseItemPB> serverResponseItems,
    @Default([]) List<LocalSearchResponseItemPB> localResponseItems,
    @Default({}) Map<String, SearchResultItem> combinedResponseItems,
    @Default({}) Map<String, ViewPB> cachedViews,
    @Default([]) List<SearchSummaryPB> resultSummaries,
    @Default(null) SearchResponseStream? searchResponseStream,
    required bool searching,
    required bool generatingAIOverview,
    @Default(false) bool askAI,
    @Default(null) List<SearchSourcePB>? askAISources,
    @Default([]) List<TrashPB> trash,
    @Default(null) String? searchId,
  }) = _CommandPaletteState;

  factory CommandPaletteState.initial() => const CommandPaletteState(
        searching: false,
        generatingAIOverview: false,
      );
}
