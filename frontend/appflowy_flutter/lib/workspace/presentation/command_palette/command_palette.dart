import 'dart:async';

import 'package:appflowy/ai/providers/ai_provider_store.dart';
import 'package:appflowy/ai/tools/tool_approval_dialog.dart';
import 'package:appflowy/ai/tools/tool_registry.dart';
import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/shared/floating_modal.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/command_palette/palette_ai.dart';
import 'package:appflowy/workspace/application/command_palette/palette_ai_engines.dart';
import 'package:appflowy/workspace/application/command_palette/palette_command.dart';
import 'package:appflowy/workspace/application/command_palette/palette_scope.dart';
import 'package:appflowy/workspace/application/command_palette/palette_setting.dart';
import 'package:appflowy/workspace/application/command_palette/workspace_content_search_controller.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/palette_commands.dart';
import 'package:appflowy/workspace/presentation/command_palette/palette_settings.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/command_results_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/content_search_widgets.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_ai_panel.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_option_picker.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_scope_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/palette_setting_cell.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/recent_views_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_layout.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/shared/sidebar_setting.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-search/result.pb.dart';
import 'package:collection/collection.dart';
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
      final route = _CommandPaletteRoute(
        context: context,
        themes: themes,
        reduceMotion: () {
          if (!mounted) return true;
          final media = MediaQuery.maybeOf(context);
          return media?.disableAnimations == true ||
              media?.accessibleNavigation == true;
        },
        barrierColor: FloatingModal.barrierColor(context),
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

/// Only the popup moves; the page behind dims and softens but stays mounted
/// with its focus tree. Both accessibility flags suppress entry AND reverse
/// motion.
class _CommandPaletteRoute extends DialogRoute<void>
    with FloatingModalBarrier<void> {
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
    return FloatingModalEntrance(
      animation: animation,
      enabled: !reduced,
      offset: const Offset(0, 8),
      child: child,
    );
  }

  final bool Function() reduceMotion;
  @override
  Duration get transitionDuration =>
      reduceMotion() ? Duration.zero : FloatingModal.enterDuration;
  @override
  Duration get reverseTransitionDuration =>
      reduceMotion() ? Duration.zero : FloatingModal.exitDuration;

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

  /// The part of the palette chosen with its tabs. A prefix typed into the
  /// box (`>` or `?`) narrows it further without changing this.
  PaletteScope _scope = PaletteScope.all;

  /// The setting whose long list of choices is open, and what was typed
  /// before it was, to put back afterwards.
  String? _pickerSettingId;
  String _pickerReturnDraft = '';

  /// The pages the next question to the assistant goes with.
  List<PaletteAISource> _aiSources = const [];

  final _fieldFocus = FocusNode(debugLabel: 'command palette search');
  late final TextEditingController _fieldController;
  final _resultsFocus = FocusNode(
    debugLabel: 'command palette results',
    skipTraversal: true,
    canRequestFocus: false,
  );
  late final AIToolApproval _approval;
  int _conversationTurns = 0;

  /// How many settings a plain search shows beside the pages it found.
  static const _inlineSettingLimit = 3;

  PaletteAIConversation get _conversation => paletteAIConversation;

  @override
  void initState() {
    super.initState();
    PaletteSettingSources.refresh();
    PaletteSettingSources.changes.addListener(_settingsChanged);
    _conversationTurns = _conversation.turns.length;
    _conversation.addListener(_conversationChanged);
    // Tool questions asked while the palette is open must appear above it,
    // not behind it on the app's own navigator.
    _approval = (tool, arguments) => askToRunTool(
          tool,
          arguments,
          context: mounted ? context : null,
        );
    paletteAIApproval = _approval;
    _paletteBloc = context.read<CommandPaletteBloc>();
    _workspaceBloc = context.read<UserWorkspaceBloc?>();
    _draft = widget.initialQuery ?? _paletteBloc.state.query ?? '';
    _fieldController = TextEditingController(text: _draft);
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
    // A list of choices, a conversation, or a scope that is not about pages
    // is filtered right here; the workspace is not searched for it.
    if (_pickerSettingId != null || !_scope.searchesPages) return;
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

  /// Narrows the palette to [scope], keeping what was typed so it can be
  /// looked for there too — "dark" then Settings finds the appearance row.
  void _setScope(PaletteScope scope) {
    if (_closing || !mounted) return;
    final leavingConversation = _scope == PaletteScope.ai;
    final parsed = parsePaletteQuery(_draft);
    setState(() {
      _scope = scope;
      _pickerSettingId = null;
      // A prefix only meant "go there"; the tab says it now.
      if (parsed.fromPrefix) _replaceDraft(parsed.text);
      // A half-typed follow-up is not a search.
      if (leavingConversation) _replaceDraft('');
      if (scope == PaletteScope.ai && _aiSources.isEmpty) {
        _aiSources = _initialAISources(withSearchResults: false);
      }
    });
    if (scope.searchesPages && !_paletteBloc.isClosed) {
      _searchTitles(_paletteBloc.state);
      _contentSearch.search(
        _draft,
        enabled: filter.pageContents,
        filter: filter,
      );
      if (!filter.pageContents &&
          (_paletteBloc.state.query ?? '') != _draft) {
        _paletteBloc.add(
          _draft.isEmpty
              ? const CommandPaletteEvent.clearSearch()
              : CommandPaletteEvent.searchChanged(search: _draft),
        );
      }
    }
    _focusField();
  }

  void _focusField() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_closing) _fieldFocus.requestFocus();
    });
  }

  /// Puts [text] in the box as though it had been typed there, with the caret
  /// at its end. Nothing is searched for: callers decide that.
  void _replaceDraft(String text) {
    _draft = text;
    if (_fieldController.text != text) {
      _fieldController.value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    }
  }

  /// Down from the box goes to the first thing listed, past the tabs and
  /// filters in between.
  void _focusFirstResult() {
    final first = _resultsFocus.traversalDescendants.firstOrNull;
    if (first != null) {
      first.requestFocus();
    } else {
      _fieldFocus.nextFocus();
    }
  }

  /// The page open behind the palette, when it is one the assistant can read.
  ViewPB? get _openDocument {
    if (!getIt.isRegistered<MenuSharedState>()) return null;
    final view = getIt<MenuSharedState>().latestOpenView;
    if (view == null || view.layout != ViewLayoutPB.Document) return null;
    if (_paletteBloc.state.trash.any((item) => item.id == view.id)) {
      return null;
    }
    return view;
  }

  /// The page open behind the palette, then — when the question came from a
  /// search — the pages that search found.
  List<PaletteAISource> _initialAISources({required bool withSearchResults}) {
    final sources = <PaletteAISource>[];
    final open = _openDocument;
    if (open != null) {
      sources.add(
        PaletteAISource(
          id: open.id,
          title: open.nameOrDefault,
          isCurrentPage: true,
        ),
      );
    }
    if (withSearchResults) {
      final views = _paletteBloc.state.cachedViews;
      for (final item in _titleSearch.results) {
        if (sources.length >= paletteAISourceLimit - 1) break;
        final view = views[item.id];
        if (view == null ||
            view.layout != ViewLayoutPB.Document ||
            sources.any((source) => source.id == view.id)) {
          continue;
        }
        sources.add(PaletteAISource(id: view.id, title: view.nameOrDefault));
      }
    }
    return sources;
  }

  /// Turns the palette into a conversation and, when there is a question,
  /// asks it. From a search, the pages it found go along with it.
  void _askAI(String question) {
    if (_closing || !mounted) return;
    final text = question.trim();
    final fromSearch = _scope != PaletteScope.ai;
    final sources = fromSearch
        ? _initialAISources(withSearchResults: true)
        : _aiSources;
    setState(() {
      _scope = PaletteScope.ai;
      _pickerSettingId = null;
      _replaceDraft('');
      _aiSources = sources;
    });
    if (fromSearch && !_paletteBloc.isClosed) {
      _paletteBloc.add(const CommandPaletteEvent.clearSearch());
    }
    if (text.isNotEmpty) {
      unawaited(_conversation.ask(text, sources: sources));
    }
    _focusField();
  }

  void _openPicker(PaletteSetting setting) {
    if (_closing || !mounted || setting.control is! PaletteChoice) return;
    setState(() {
      _pickerSettingId = setting.id;
      _pickerReturnDraft = _draft;
      _replaceDraft('');
    });
    _focusField();
  }

  void _closePicker() {
    if (!mounted) return;
    setState(() {
      _pickerSettingId = null;
      _replaceDraft(_pickerReturnDraft);
    });
    _focusField();
  }

  void _pick(PaletteChoice choice, PaletteSettingOption option) {
    runPaletteSettingChange(() => choice.onSelected(option));
    _closePicker();
  }

  /// Opens Settings at [page]. The palette closes first, because Settings
  /// opens on the app's own navigator, under this route.
  void _openSettingsPage(SettingsPage page) {
    final workspaceBloc = _workspaceBloc;
    _dismiss();
    final host = AppGlobals.rootNavKey.currentContext;
    if (host == null || workspaceBloc == null) return;
    showSettingsDialog(host, userWorkspaceBloc: workspaceBloc, initPage: page);
  }

  void _openPage(String viewId) {
    final view = _paletteBloc.state.cachedViews[viewId];
    _dismiss();
    view == null ? viewId.navigateTo() : view.navigateTo();
  }

  Future<void> _insertAnswer(ViewPB page, String markdown) async {
    final written = await PaletteAIDocuments.append(page.id, markdown);
    showToastNotification(
      message: written
          ? LocaleKeys.commandPalette_ai_inserted.tr(args: [page.nameOrDefault])
          : LocaleKeys.commandPalette_ai_insertFailed.tr(),
      type: written ? ToastificationType.success : ToastificationType.error,
    );
  }

  /// A page named after the question, holding the answer.
  Future<void> _saveAnswer(PaletteAITurn turn) async {
    final target = paletteCreationTarget(context);
    if (target == null) return;
    final view = await PaletteAIDocuments.createPage(
      parentViewId: target.parentViewId,
      section: target.section,
      name: _titleFor(turn.question),
      markdown: turn.answer.trim(),
    );
    if (view == null) {
      showToastNotification(
        message: LocaleKeys.commandPalette_ai_saveFailed.tr(),
        type: ToastificationType.error,
      );
      return;
    }
    _dismiss();
    getIt<TabsBloc>().openPlugin(view);
  }

  /// Carries the conversation on in a chat page of its own.
  Future<void> _continueInChat() async {
    final target = paletteCreationTarget(context);
    final exchanges = _conversation.exchanges;
    if (target == null || exchanges.isEmpty) return;
    final created = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Chat,
      parentViewId: target.parentViewId,
      section: target.section,
      name: _titleFor(exchanges.first.question),
    );
    final chat = created.fold((view) => view, (_) => null);
    if (chat == null) {
      showToastNotification(
        message: LocaleKeys.commandPalette_command_createFailed.tr(),
        type: ToastificationType.error,
      );
      return;
    }
    await PaletteAIDocuments.seedChat(chat.id, exchanges);
    _dismiss();
    getIt<TabsBloc>().openPlugin(chat);
  }

  static String _titleFor(String question) {
    final line = question.trim().split('\n').first.trim();
    return line.length > 60 ? '${line.substring(0, 57)}…' : line;
  }

  Widget _buildConversation(List<PaletteSetting> settings) {
    final open = _openDocument;
    final modelSetting =
        settings.firstWhereOrNull((setting) => setting.id == 'ai_model');
    return PaletteAIPanel(
      key: const ValueKey('command-palette-ai-panel'),
      conversation: _conversation,
      sources: _aiSources,
      modelLabel: paletteAIModelLabel(),
      hasCurrentPage: open != null,
      onAsk: _askAI,
      onRemoveSource: (source) => setState(
        () => _aiSources = [
          for (final kept in _aiSources)
            if (kept.id != source.id) kept,
        ],
      ),
      onOpenSource: _openPage,
      onSetUp: () => _openSettingsPage(SettingsPage.ai),
      onPickModel: () {
        if (modelSetting != null) _openPicker(modelSetting);
      },
      onNewConversation: () async {
        await _conversation.clear();
        if (mounted) setState(() {});
        _focusField();
      },
      onSaveAsPage: _saveAnswer,
      onInsert: open == null ? null : (markdown) => _insertAnswer(open, markdown),
      insertTargetName: open?.nameOrDefault ?? '',
      onContinueInChat: CustomAIProviderStore.instance.activeSelection == null
          ? null
          : () => unawaited(_continueInChat()),
    );
  }

  void _settingsChanged() {
    if (mounted && !_closing) setState(() {});
  }

  /// Only a question asked or a conversation cleared changes the palette
  /// around the panel; the panel follows the answer itself.
  void _conversationChanged() {
    final turns = _conversation.turns.length;
    if (turns == _conversationTurns) return;
    _conversationTurns = turns;
    if (mounted && !_closing) setState(() {});
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
    _fieldFocus.dispose();
    _fieldController.dispose();
    _resultsFocus.dispose();
    PaletteSettingSources.changes.removeListener(_settingsChanged);
    _conversation.removeListener(_conversationChanged);
    // An answer still being written may ask to run a tool after the palette
    // has gone; ask from the app itself then.
    if (identical(paletteAIApproval, _approval)) {
      paletteAIApproval = askToRunTool;
    }
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
          PaletteCommandContext(
            query: query,
            argument: paletteCommandArgument(command, query) ?? '',
            dismiss: _dismiss,
            askAI: _askAI,
          ),
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
        // Asked right here, in the palette, rather than on a page of its own.
        _askAI(parsePaletteQuery(_draft, selected: _scope).text);
      },
      child: BlocBuilder<CommandPaletteBloc, CommandPaletteState>(
        builder: (context, state) {
          final palette = WorkspacePalette.of(context);
          final rawQuery = _draft;
          final appSettings = buildPaletteSettings(context);
          final extensionSettings = buildPaletteExtensionSettings();
          final pickerSetting = _pickerSettingId == null
              ? null
              : [...appSettings, ...extensionSettings]
                  .firstWhereOrNull((setting) => setting.id == _pickerSettingId);
          final pickerControl = pickerSetting?.control;
          final picker = pickerSetting != null && pickerControl is PaletteChoice
              ? (setting: pickerSetting, choice: pickerControl)
              : null;
          final inPicker = picker != null;
          final parsed = parsePaletteQuery(rawQuery, selected: _scope);
          final scope = parsed.scope;
          final text = parsed.text;
          final inCommandMode = !inPicker && scope == PaletteScope.commands;
          final searchesPages = !inPicker && scope.searchesPages;
          final inContentMode = filter.pageContents && searchesPages;
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
          final resultItems = !searchesPages
              ? const <SearchResultItem>[]
              : searchableItems
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
          // One stray letter matches half of everything, which is noise beside
          // the pages somebody was actually looking for.
          final inlineMatches = scope == PaletteScope.all &&
              !inPicker &&
              !inContentMode &&
              text.length >= 2;
          final matchedCommands = inPicker
              ? const <PaletteCommand>[]
              : switch (scope) {
                  PaletteScope.commands =>
                    rankPaletteCommands(commands, text, limit: 500),
                  PaletteScope.extensions => rankPaletteCommands(
                      [
                        for (final command in commands)
                          if (command.group == PaletteCommandGroup.extensions)
                            command,
                      ],
                      text,
                      limit: 200,
                    ),
                  PaletteScope.all when inlineMatches => rankPaletteCommands(
                      commands,
                      rawQuery,
                      limit: paletteInlineCommandLimit,
                    ),
                  _ => const <PaletteCommand>[],
                };
          final matchedSettings = inPicker
              ? const <PaletteSetting>[]
              : switch (scope) {
                  PaletteScope.settings =>
                    rankPaletteSettings(appSettings, text, limit: 200),
                  PaletteScope.extensions => rankPaletteSettings(
                      [
                        ...extensionSettings,
                        for (final setting in appSettings)
                          if (setting.section ==
                              PaletteSettingSection.extensions)
                            setting,
                      ],
                      text,
                      limit: 200,
                    ),
                  PaletteScope.all when inlineMatches => rankPaletteSettings(
                      [...appSettings, ...extensionSettings],
                      text,
                      limit: _inlineSettingLimit,
                    ),
                  _ => const <PaletteSetting>[],
                };
          final hasCommands = matchedCommands.isNotEmpty;
          final hasSettings = matchedSettings.isNotEmpty;
          final commandRunQuery =
              scope == PaletteScope.all ? rawQuery : text;
          // A command handed what was typed ("new page Ideas") is the answer
          // Enter gives, ahead of any page whose title happens to match.
          final commandTakesQuery = scope == PaletteScope.all &&
              hasCommands &&
              paletteCommandArgument(matchedCommands.first, rawQuery) != null;
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
          void openFirstResult() {
            final id = resultItems.first.id;
            final allowed = inContentMode
                ? _contentSearch.canUseResult(id, _draft)
                : _titleSearch.canUseResult(id, _draft);
            if (!allowed || ModalRoute.of(context)?.isCurrent == false) return;
            final view = cachedViews[id];
            if (view == null) return;
            _dismiss();
            view.navigateTo();
          }

          void activateFirstSetting() => activatePaletteSetting(
                matchedSettings.first,
                onOpenPicker: _openPicker,
              );

          void runFirstCommand() =>
              _runCommand(matchedCommands.first, commandRunQuery);

          final pickedOptions = picker != null
              ? rankPaletteOptions(picker.choice.options, text)
              : const <PaletteSettingOption>[];
          final VoidCallback? onSubmit;
          if (picker != null) {
            onSubmit = pickedOptions.isEmpty
                ? null
                : () => _pick(picker.choice, pickedOptions.first);
          } else {
            onSubmit = switch (scope) {
              PaletteScope.ai => text.isEmpty ? null : () => _askAI(text),
              PaletteScope.commands => hasCommands ? runFirstCommand : null,
              PaletteScope.settings =>
                hasSettings ? activateFirstSetting : null,
              PaletteScope.extensions => hasSettings
                  ? activateFirstSetting
                  : hasCommands
                      ? runFirstCommand
                      : null,
              PaletteScope.all || PaletteScope.pages => commandTakesQuery
                  ? runFirstCommand
                  : hasResult
                      ? openFirstResult
                      : hasCommands
                          ? runFirstCommand
                          : hasSettings
                              ? activateFirstSetting
                              // Nothing here answers it; perhaps the
                              // assistant can.
                              : scope == PaletteScope.all &&
                                      hasQuery &&
                                      !searching &&
                                      !inContentMode
                                  ? () => _askAI(text)
                                  : null,
            };
          }

          final Widget body;
          if (picker != null) {
            body = PaletteOptionPicker(
              setting: picker.setting,
              options: pickedOptions,
              selectedId: picker.choice.selectedId,
              onPicked: (option) => _pick(picker.choice, option),
              onBack: _closePicker,
            );
          } else {
            body = switch (scope) {
              PaletteScope.ai => _buildConversation(
                  [...appSettings, ...extensionSettings],
                ),
              PaletteScope.commands => CommandPalettePanel(
                  commands: matchedCommands,
                  onRun: (command) => _runCommand(command, commandRunQuery),
                  query: commandRunQuery,
                ),
              PaletteScope.settings => PaletteSettingsPanel(
                  key: const ValueKey('command-palette-settings-panel'),
                  settings: matchedSettings,
                  grouped: text.isEmpty,
                  onOpenPicker: _openPicker,
                  onOpenSettings: _openSettingsPage,
                  empty: _PaletteEmptyHint(
                    icon: Icons.tune_rounded,
                    text: LocaleKeys.commandPalette_setting_noResults.tr(),
                  ),
                ),
              PaletteScope.extensions => PaletteSettingsPanel(
                  key: const ValueKey('command-palette-extensions-panel'),
                  settings: matchedSettings,
                  grouped: false,
                  sectionLabel:
                      LocaleKeys.commandPalette_extension_installed.tr(),
                  onOpenPicker: _openPicker,
                  onOpenSettings: _openSettingsPage,
                  footer: hasCommands
                      ? CommandResultsList(
                          commands: matchedCommands,
                          onRun: (command) =>
                              _runCommand(command, commandRunQuery),
                          grouped: false,
                          sectionLabel:
                              LocaleKeys.commandPalette_extension_commands.tr(),
                          query: commandRunQuery,
                        )
                      : null,
                  empty: _PaletteEmptyHint(
                    icon: Icons.extension_outlined,
                    text: LocaleKeys.commandPalette_extension_none.tr(),
                  ),
                ),
              PaletteScope.all || PaletteScope.pages => inContentMode
                  ? hasResult
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
                        )
                  : noQuery
                      ? RecentViewsList(
                          onSelected: _dismiss,
                          filter: filter,
                          cachedViews: cachedViews,
                          currentUserId: currentUserId,
                          currentWorkspaceId: currentWorkspace?.workspaceId,
                          currentWorkspaceName: currentWorkspace?.name,
                          currentWorkspaceIcon: currentWorkspace?.icon,
                          currentWorkspaceCover: currentWorkspaceCover,
                        )
                      : hasResult || hasCommands || hasSettings
                          ? SearchResultList(
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
                              settings: matchedSettings,
                              onOpenSettingPicker: _openPicker,
                              onOpenSettingsPage: _openSettingsPage,
                              highlightFirstCommand: commandTakesQuery,
                              currentWorkspaceId: currentWorkspace?.workspaceId,
                              currentWorkspaceName: currentWorkspace?.name,
                              currentWorkspaceIcon: currentWorkspace?.icon,
                              currentWorkspaceCover: currentWorkspaceCover,
                            )
                          // Nothing found and nothing still on its way: say
                          // so, centred in the space, and offer the assistant.
                          : !searching && !_titleSearch.timedOut
                              ? Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    SearchAskAiEntrance(),
                                    const Expanded(
                                      child: NoSearchResultsHint(),
                                    ),
                                  ],
                                )
                              : searching
                                  ? const Center(
                                      child:
                                          CircularProgressIndicator.adaptive(),
                                    )
                                  : const SizedBox.shrink(),
            };
          }

          final hintMode = inPicker
              ? PaletteHintMode.picker
              : switch (scope) {
                  PaletteScope.commands => PaletteHintMode.commands,
                  PaletteScope.settings ||
                  PaletteScope.extensions =>
                    PaletteHintMode.settings,
                  PaletteScope.ai => PaletteHintMode.ai,
                  _ => PaletteHintMode.search,
                };
          final fieldHint = picker != null
              ? LocaleKeys.commandPalette_setting_pickerHint
                  .tr(args: [picker.setting.title])
              : scope == PaletteScope.ai
                  ? (_conversation.isEmpty
                      ? paletteScopeHint(PaletteScope.ai)
                      : LocaleKeys.commandPalette_ai_followUp.tr())
                  : _scope == PaletteScope.all
                      ? null
                      : paletteScopeHint(_scope);
          final leadingIcon = picker != null
              ? picker.setting.icon
              : scope == PaletteScope.all || scope == PaletteScope.pages
                  ? null
                  : paletteScopeIcon(scope);

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
                            controller: _fieldController,
                            focusNode: _fieldFocus,
                            isLoading: searching,
                            selectAllOnOpen: widget.initialQuery == null,
                            onChanged: _queryChanged,
                            onSubmit: onSubmit,
                            hintText: fieldHint,
                            leadingIcon: leadingIcon,
                            badge: picker != null
                                ? PaletteScopeBadge(
                                    label: picker.setting.title,
                                    icon: picker.setting.icon,
                                    onClear: _closePicker,
                                  )
                                : null,
                            onArrowDown: _focusFirstResult,
                            onTab: () {
                              if (inPicker ||
                                  !(scope == PaletteScope.all ||
                                      scope == PaletteScope.pages) ||
                                  inContentMode ||
                                  text.isEmpty) {
                                return false;
                              }
                              _askAI(text);
                              return true;
                            },
                            onBackspaceWhenEmpty: inPicker
                                ? _closePicker
                                : _scope != PaletteScope.all
                                    ? () => _setScope(PaletteScope.all)
                                    : null,
                            onEscape: inPicker
                                ? () {
                                    _closePicker();
                                    return true;
                                  }
                                : null,
                          ),
                          PaletteScopeBar(
                            scope: inPicker ? _scope : scope,
                            onChanged: _setScope,
                          ),
                          if (searchesPages && !inCommandMode)
                            SearchFilterBar(
                              filter: filter,
                              spaces: spaces,
                              onChanged: _filterChanged,
                            )
                          else
                            const VSpace(WorkspaceTokens.space3),
                          if (inContentMode)
                            WorkspaceContentSearchStatusView(
                              state: contentState,
                            ),
                          if (searchesPages &&
                              !inContentMode &&
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
                  Expanded(
                    child: Focus(
                      focusNode: _resultsFocus,
                      canRequestFocus: false,
                      skipTraversal: true,
                      child: body,
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
                            mode: hintMode,
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

/// What an empty scope says, centred where its list would be.
class _PaletteEmptyHint extends StatelessWidget {
  const _PaletteEmptyHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = WorkspacePalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(WorkspaceTokens.space6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph(icon, size: 24, color: palette.secondaryText),
            const VSpace(WorkspaceTokens.space2),
            Text(
              text,
              textAlign: TextAlign.center,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.body,
                color: palette.secondaryText,
              ),
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
