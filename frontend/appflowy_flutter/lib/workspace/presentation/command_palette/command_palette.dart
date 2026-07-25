import 'dart:math' as math;

import 'package:appflowy/features/workspace/application/workspace_cover_codec.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy/workspace/application/command_palette/command_palette_filter.dart';
import 'package:appflowy/workspace/application/sidebar/space/space_bloc.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/automatic_view_cover.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/recent_views_list.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_field.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_filter_bar.dart';
import 'package:appflowy/workspace/presentation/command_palette/widgets/search_results_list.dart';
import 'package:appflowy/workspace/presentation/home/menu/menu_shared_state.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pbenum.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/gestures.dart';
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
        builder: (_) => MultiBlocProvider(
          providers: [
            BlocProvider.value(value: commandBloc),
            if (workspaceBloc != null) BlocProvider.value(value: workspaceBloc),
            if (spaceBloc != null) BlocProvider.value(value: spaceBloc),
          ],
          child: CommandPaletteModal(shortcutBuilder: _buildShortcut),
        ),
      ).then((_) {
        _isOpen = false;
        _toggleNotifier.value = _toggleNotifier.value.copyWith(isOpen: false);
      });
    } else if (!_toggleNotifier.value.isOpen && _isOpen) {
      FlowyOverlay.pop(context);
      _isOpen = false;
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

  @override
  Widget build(BuildContext context) {
    final workspaceState = context.read<UserWorkspaceBloc?>()?.state;
    final showAskingAI =
        workspaceState?.userProfile.workspaceType == WorkspaceTypePB.ServerW;
    return BlocListener<CommandPaletteBloc, CommandPaletteState>(
      listener: (_, state) {
        if (state.askAI && context.mounted) {
          if (Navigator.canPop(context)) FlowyOverlay.pop(context);
          final currentWorkspace = workspaceState?.workspaces;
          final spaceBloc = context.read<SpaceBloc?>();
          if (currentWorkspace != null && spaceBloc != null) {
            spaceBloc.add(
              SpaceEvent.createPage(
                name: '',
                layout: ViewLayoutPB.Chat,
                index: 0,
                openAfterCreate: true,
              ),
            );
          }
        }
      },
      child: BlocBuilder<CommandPaletteBloc, CommandPaletteState>(
        builder: (context, state) {
          final theme = AppFlowyTheme.of(context);
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
          final spaces =
              context.read<SpaceBloc?>()?.state.spaces ?? const <ViewPB>[];
          final spaceXl = theme.spacing.xl;
          final viewportSize = MediaQuery.sizeOf(context);
          final dialogWidth = math.min(
            960.0,
            math.min(
              viewportSize.width - 80,
              (viewportSize.height - 96) * 4 / 3,
            ),
          );
          final dialogHeight = dialogWidth * 3 / 4;
          return FlowyDialog(
            backgroundColor: EditorSurfaceStyle.canvasBackgroundFor(
              Theme.of(context).brightness,
              theme.surfaceColorScheme.layer01,
              isPaper: PaperTheme.isEnabled(context),
            ),
            width: dialogWidth,
            elevation: 1,
            shadowColor: Theme.of(context).shadowColor,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(17),
              side: BorderSide(
                color: theme.borderColorScheme.primary,
                width: 0.5,
              ),
            ),
            alignment: Alignment.center,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 40,
              vertical: 48,
            ),
            constraints: BoxConstraints.tightFor(
              width: dialogWidth,
              height: dialogHeight,
            ),
            expandHeight: false,
            child: widget.shortcutBuilder(
              // Change mainAxisSize to max so Expanded works correctly.
              Padding(
                padding: EdgeInsets.fromLTRB(spaceXl, spaceXl, spaceXl, 0),
                child: Column(
                  children: [
                    SearchField(query: state.query, isLoading: searching),
                    SearchFilterBar(
                      filter: filter,
                      spaces: spaces,
                      onChanged: (value) => setState(() => filter = value),
                    ),
                    if (noQuery)
                      Flexible(
                        child: RecentViewsList(
                          onSelected: () => FlowyOverlay.pop(context),
                          filter: filter,
                          cachedViews: cachedViews,
                          currentUserId: currentUserId,
                          currentWorkspaceId: currentWorkspace?.workspaceId,
                          currentWorkspaceName: currentWorkspace?.name,
                          currentWorkspaceIcon: currentWorkspace?.icon,
                          currentWorkspaceCover: currentWorkspaceCover,
                        ),
                      ),
                    if (hasResult && hasQuery)
                      Flexible(
                        child: SearchResultList(
                          cachedViews: cachedViews,
                          resultItems: resultItems,
                          resultSummaries: state.resultSummaries,
                          currentWorkspaceId: currentWorkspace?.workspaceId,
                          currentWorkspaceName: currentWorkspace?.name,
                          currentWorkspaceIcon: currentWorkspace?.icon,
                          currentWorkspaceCover: currentWorkspaceCover,
                        ),
                      )
                    // When there are no results and the query is not empty and not loading,
                    // show the no results message, centered in the available space.
                    else if (hasQuery && !searching) ...[
                      if (showAskingAI) SearchAskAiEntrance(),
                      Expanded(
                        child: const NoSearchResultsHint(),
                      ),
                    ],
                    if (hasQuery && searching && !hasResult)
                      // Show a loading indicator when searching
                      Expanded(
                        child: Center(
                          child: Center(
                            child: CircularProgressIndicator.adaptive(),
                          ),
                        ),
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
    final theme = AppFlowyTheme.of(context),
        textColor = theme.textColorScheme.secondary;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          FlowySvg(
            FlowySvgs.m_home_search_icon_m,
            color: theme.iconColorScheme.secondary,
            size: Size.square(24),
          ),
          const VSpace(8),
          Text(
            LocaleKeys.search_noResultForSearching.tr(),
            style: theme.textStyle.body.enhanced(color: textColor),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const VSpace(4),
          RichText(
            textAlign: TextAlign.center,
            text: TextSpan(
              text: LocaleKeys.search_noResultForSearchingHintWithoutTrash.tr(),
              style: theme.textStyle.caption.standard(color: textColor),
              children: [
                TextSpan(
                  text: LocaleKeys.trash_text.tr(),
                  style: theme.textStyle.caption.underline(color: textColor),
                  recognizer: TapGestureRecognizer()
                    ..onTap = () {
                      FlowyOverlay.pop(context);
                      getIt<MenuSharedState>().latestOpenView = null;
                      getIt<TabsBloc>().add(
                        TabsEvent.openPlugin(
                          plugin: makePlugin(pluginType: PluginType.trash),
                        ),
                      );
                    },
                ),
              ],
            ),
          ),
        ],
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
