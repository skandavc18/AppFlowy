import 'dart:io';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/mobile/presentation/database/board/mobile_board_page.dart';
import 'package:appflowy/plugins/database/application/database_controller.dart';
import 'package:appflowy/plugins/database/application/row/row_controller.dart';
import 'package:appflowy/plugins/database/board/application/board_actions_bloc.dart';
import 'package:appflowy/plugins/database/board/group_ext.dart';
import 'package:appflowy/plugins/database/board/presentation/board_style.dart';
import 'package:appflowy/plugins/database/board/presentation/widgets/board_column_header.dart';
import 'package:appflowy/plugins/database/grid/presentation/grid_page.dart';
import 'package:appflowy/plugins/database/tab_bar/desktop/setting_menu.dart';
import 'package:appflowy/plugins/database/tab_bar/tab_bar_view.dart';
import 'package:appflowy/plugins/database/widgets/card/card_bloc.dart';
import 'package:appflowy/plugins/database/widgets/cell/card_cell_style_maps/desktop_board_card_cell_style.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/extension.dart';
import 'package:appflowy/plugins/database/widgets/row/row_detail.dart';
import 'package:appflowy/shared/conditional_listenable_builder.dart';
import 'package:appflowy/shared/flowy_error_page.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_board/appflowy_board.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart' hide Card;
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:universal_platform/universal_platform.dart';

import '../../widgets/card/card.dart';
import '../../widgets/cell/card_cell_builder.dart';
import '../application/board_bloc.dart';
import 'toolbar/board_setting_bar.dart';
import 'widgets/board_focus_scope.dart';
import 'widgets/board_hidden_groups.dart';
import 'widgets/board_shortcut_container.dart';

class BoardPageTabBarBuilderImpl extends DatabaseTabBarItemBuilder {
  final _toggleExtension = ToggleExtensionNotifier();

  @override
  Widget content(
    BuildContext context,
    ViewPB view,
    DatabaseController controller,
    bool shrinkWrap,
    String? initialRowId,
  ) =>
      UniversalPlatform.isDesktop
          ? DesktopBoardPage(
              key: _makeValueKey(controller),
              view: view,
              databaseController: controller,
              shrinkWrap: shrinkWrap,
            )
          : MobileBoardPage(
              key: _makeValueKey(controller),
              view: view,
              databaseController: controller,
            );

  @override
  Widget settingBar(BuildContext context, DatabaseController controller) =>
      BoardSettingBar(
        key: _makeValueKey(controller),
        databaseController: controller,
        toggleExtension: _toggleExtension,
      );

  @override
  Widget settingBarExtension(
    BuildContext context,
    DatabaseController controller,
  ) {
    return DatabaseViewSettingExtension(
      key: _makeValueKey(controller),
      viewId: controller.viewId,
      databaseController: controller,
      toggleExtension: _toggleExtension,
    );
  }

  @override
  void dispose() {
    _toggleExtension.dispose();
    super.dispose();
  }

  ValueKey _makeValueKey(DatabaseController controller) =>
      ValueKey(controller.viewId);
}

class DesktopBoardPage extends StatefulWidget {
  const DesktopBoardPage({
    super.key,
    required this.view,
    required this.databaseController,
    this.onEditStateChanged,
    this.shrinkWrap = false,
  });

  final ViewPB view;

  final DatabaseController databaseController;

  /// Called when edit state changed
  final VoidCallback? onEditStateChanged;

  /// If true, the board will shrink wrap its content
  final bool shrinkWrap;

  @override
  State<DesktopBoardPage> createState() => _DesktopBoardPageState();
}

class _DesktopBoardPageState extends State<DesktopBoardPage> {
  late final AppFlowyBoardController _boardController = AppFlowyBoardController(
    onMoveGroup: (fromGroupId, fromIndex, toGroupId, toIndex) =>
        widget.databaseController.moveGroup(
      fromGroupId: fromGroupId,
      toGroupId: toGroupId,
    ),
    onMoveGroupItem: (groupId, fromIndex, toIndex) {
      final groupControllers = _boardBloc.groupControllers;
      final fromRow = groupControllers[groupId]?.rowAtIndex(fromIndex);
      final toRow = groupControllers[groupId]?.rowAtIndex(toIndex);
      if (fromRow != null) {
        widget.databaseController.moveGroupRow(
          fromRow: fromRow,
          toRow: toRow,
          fromGroupId: groupId,
          toGroupId: groupId,
        );
      }
    },
    onMoveGroupItemToGroup: (fromGroupId, fromIndex, toGroupId, toIndex) {
      final groupControllers = _boardBloc.groupControllers;
      final fromRow = groupControllers[fromGroupId]?.rowAtIndex(fromIndex);
      final toRow = groupControllers[toGroupId]?.rowAtIndex(toIndex);
      if (fromRow != null) {
        widget.databaseController.moveGroupRow(
          fromRow: fromRow,
          toRow: toRow,
          fromGroupId: fromGroupId,
          toGroupId: toGroupId,
        );
      }
    },
    onStartDraggingCard: (groupId, index) {
      final groupControllers = _boardBloc.groupControllers;
      final toRow = groupControllers[groupId]?.rowAtIndex(index);
      if (toRow != null) {
        _focusScope.clear();
      }
    },
  );

  late final _focusScope = BoardFocusScope(
    boardController: _boardController,
  );
  late final BoardBloc _boardBloc;
  late final BoardActionsCubit _boardActionsCubit;
  late final ValueNotifier<DidCreateRowResult?> _didCreateRow;

  @override
  void initState() {
    super.initState();
    _didCreateRow = ValueNotifier(null)..addListener(_handleDidCreateRow);
    _boardBloc = BoardBloc(
      databaseController: widget.databaseController,
      didCreateRow: _didCreateRow,
      boardController: _boardController,
    )..add(const BoardEvent.initial());
    _boardActionsCubit = BoardActionsCubit(
      databaseController: widget.databaseController,
    );
  }

  @override
  void dispose() {
    _focusScope.dispose();
    _boardBloc.close();
    _boardActionsCubit.close();
    _didCreateRow.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider<BoardBloc>.value(value: _boardBloc),
        BlocProvider.value(value: _boardActionsCubit),
      ],
      child: BlocBuilder<BoardBloc, BoardState>(
        builder: (context, state) => state.maybeMap(
          loading: (_) => const Center(
            child: CircularProgressIndicator.adaptive(),
          ),
          error: (err) => Center(child: AppFlowyErrorPage(error: err.error)),
          orElse: () => _BoardContent(
            shrinkWrap: widget.shrinkWrap,
            onEditStateChanged: widget.onEditStateChanged,
            focusScope: _focusScope,
            boardController: _boardController,
            view: widget.view,
          ),
        ),
      ),
    );
  }

  void _handleDidCreateRow() async {
    // work around: wait for the new card to be inserted into the board before enabling edit
    await Future.delayed(const Duration(milliseconds: 50));
    if (_didCreateRow.value != null) {
      final result = _didCreateRow.value!;
      switch (result.action) {
        case DidCreateRowAction.openAsPage:
          _boardActionsCubit.openCard(result.rowMeta);
          break;
        case DidCreateRowAction.startEditing:
          _boardActionsCubit.startEditingRow(
            GroupedRowId(
              groupId: result.groupId,
              rowId: result.rowMeta.id,
            ),
          );
          break;
        default:
          break;
      }
    }
  }
}

class _BoardContent extends StatefulWidget {
  const _BoardContent({
    required this.boardController,
    required this.focusScope,
    required this.view,
    this.onEditStateChanged,
    this.shrinkWrap = false,
  });

  final AppFlowyBoardController boardController;
  final BoardFocusScope focusScope;
  final VoidCallback? onEditStateChanged;
  final bool shrinkWrap;
  final ViewPB view;

  @override
  State<_BoardContent> createState() => _BoardContentState();
}

class _BoardContentState extends State<_BoardContent> {
  final ScrollController scrollController = ScrollController();
  final AppFlowyBoardScrollController scrollManager =
      AppFlowyBoardScrollController();

  late final cellBuilder = CardCellBuilder(
    databaseController: databaseController,
  );

  /// A column is a tinted well with room to breathe, not a bare list.
  ///
  /// The body carries no padding of its own: each card brings the inset with
  /// it so the column's wash can run edge to edge behind them all.
  AppFlowyBoardConfig _configOf(BoardPalette palette) => AppFlowyBoardConfig(
        groupCornerRadius: BoardMetrics.columnRadius,
        groupBackgroundColor: palette.sunken,
        groupMargin:
            const EdgeInsets.symmetric(horizontal: BoardMetrics.columnGap),
        groupBodyPadding: EdgeInsets.zero,
        groupFooterPadding: const EdgeInsets.fromLTRB(
          BoardMetrics.columnInset,
          6,
          BoardMetrics.columnInset,
          8,
        ),
        groupHeaderPadding: const EdgeInsets.fromLTRB(12, 0, 8, 0),
        cardMargin: const EdgeInsets.symmetric(
          horizontal: BoardMetrics.cardGap,
          vertical: BoardMetrics.cardGap,
        ),
        stretchGroupHeight: false,
      );

  /// The wash the column for [columnData] wears, or null when its group has no
  /// colour to lend.
  Color? _washOf(BuildContext context, AppFlowyGroupData columnData) {
    final custom = columnData.customData;
    if (custom is! GroupData) {
      return null;
    }
    final color = custom.group.groupOptionColor(databaseController);
    return color == null
        ? null
        : boardColumnWashColor(
            boardPaletteOf(context),
            color.toColor(context),
          );
  }

  DatabaseController get databaseController =>
      context.read<BoardBloc>().databaseController;

  @override
  void dispose() {
    scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = boardPaletteOf(context);
    final config = _configOf(palette);
    final horizontalPadding =
        context.read<DatabasePluginWidgetBuilderSize?>()?.horizontalPadding ??
            0.0;
    return MultiBlocListener(
      listeners: [
        BlocListener<BoardBloc, BoardState>(
          listener: (context, state) {
            state.maybeMap(
              ready: (value) {
                widget.onEditStateChanged?.call();
              },
              openRowDetail: (value) {
                _openCard(
                  context: context,
                  databaseController:
                      context.read<BoardBloc>().databaseController,
                  rowMeta: value.rowMeta,
                );
              },
              orElse: () {},
            );
          },
        ),
        BlocListener<BoardActionsCubit, BoardActionsState>(
          listener: (context, state) {
            state.maybeMap(
              openCard: (value) {
                _openCard(
                  context: context,
                  databaseController:
                      context.read<BoardBloc>().databaseController,
                  rowMeta: value.rowMeta,
                );
              },
              setFocus: (value) {
                widget.focusScope.focusedGroupedRows = value.groupedRowIds;
              },
              startEditingRow: (value) {
                widget.boardController.enableGroupDragging(false);
                widget.focusScope.clear();
              },
              endEditingRow: (value) {
                widget.boardController.enableGroupDragging(true);
              },
              orElse: () {},
            );
          },
        ),
      ],
      child: FocusScope(
        autofocus: true,
        child: BoardShortcutContainer(
          focusScope: widget.focusScope,
          child: Padding(
            padding: const EdgeInsets.only(top: 8.0),
            child: ValueListenableBuilder(
              valueListenable: databaseController.compactModeNotifier,
              builder: (context, compactMode, _) {
                return ScrollConfiguration(
                  behavior: const BoardScrollBehaviour(),
                  child: BoardColumnSurface(
                    child: AppFlowyBoard(
                      boardScrollController: scrollManager,
                      scrollController: scrollController,
                      shrinkWrap: widget.shrinkWrap,
                      controller: context.read<BoardBloc>().boardController,
                      groupConstraints: BoxConstraints.tightFor(
                        width: compactMode ? 196 : 256,
                      ),
                      config: config,
                      leading: HiddenGroupsColumn(
                        shrinkWrap: widget.shrinkWrap,
                        margin: config.groupHeaderPadding +
                            EdgeInsets.only(
                              left: widget.shrinkWrap ? horizontalPadding : 0.0,
                            ),
                      ),
                      trailing: context
                                  .read<BoardBloc>()
                                  .groupingFieldType
                                  ?.canCreateNewGroup ??
                              false
                          ? BoardTrailing(scrollController: scrollController)
                          : const HSpace(40),
                      headerBuilder: (_, groupData) => BoardColumnWash(
                        color: _washOf(context, groupData),
                        child: BlocProvider.value(
                          value: context.read<BoardBloc>(),
                          child: BoardColumnHeader(
                            databaseController: databaseController,
                            groupData: groupData,
                            margin: config.groupHeaderPadding,
                          ),
                        ),
                      ),
                      footerBuilder: (_, groupData) => BoardColumnWash(
                        color: _washOf(context, groupData),
                        child: MultiBlocProvider(
                          providers: [
                            BlocProvider.value(
                              value: context.read<BoardBloc>(),
                            ),
                            BlocProvider.value(
                              value: context.read<BoardActionsCubit>(),
                            ),
                          ],
                          child: BoardColumnFooter(
                            columnData: groupData,
                            boardConfig: config,
                            scrollManager: scrollManager,
                          ),
                        ),
                      ),
                      cardBuilder: (cardContext, column, columnItem) =>
                          MultiBlocProvider(
                        key: ValueKey(
                          "board_card_${column.id}_${columnItem.id}",
                        ),
                        providers: [
                          BlocProvider<BoardBloc>.value(
                            value: cardContext.read<BoardBloc>(),
                          ),
                          BlocProvider.value(
                            value: cardContext.read<BoardActionsCubit>(),
                          ),
                          BlocProvider(
                            create: (_) => PageAccessLevelBloc(
                              view: widget.view,
                              ignorePageAccessLevel: true,
                            )..add(PageAccessLevelEvent.initial()),
                          ),
                        ],
                        child: BlocBuilder<PageAccessLevelBloc,
                            PageAccessLevelState>(
                          builder: (lockStatusContext, state) {
                            return IgnorePointer(
                              ignoring: !state.isEditable,
                              child: _BoardCard(
                                afGroupData: column,
                                groupItem: columnItem as GroupItem,
                                boardConfig: config,
                                columnWash: _washOf(context, column),
                                notifier: widget.focusScope,
                                cellBuilder: cellBuilder,
                                compactMode: compactMode,
                                onOpenCard: (rowMeta) => _openCard(
                                  context: context,
                                  databaseController: lockStatusContext
                                      .read<BoardBloc>()
                                      .databaseController,
                                  rowMeta: rowMeta,
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

@visibleForTesting
class BoardColumnFooter extends StatefulWidget {
  const BoardColumnFooter({
    super.key,
    required this.columnData,
    required this.boardConfig,
    required this.scrollManager,
  });

  final AppFlowyGroupData columnData;
  final AppFlowyBoardConfig boardConfig;
  final AppFlowyBoardScrollController scrollManager;

  @override
  State<BoardColumnFooter> createState() => _BoardColumnFooterState();
}

class _BoardColumnFooterState extends State<BoardColumnFooter> {
  final TextEditingController _textController = TextEditingController();
  late final FocusNode _focusNode;
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (_focusNode.hasFocus &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _focusNode.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    )..addListener(() {
        if (!_focusNode.hasFocus) {
          setState(() => _isCreating = false);
        }
      });
  }

  @override
  void dispose() {
    _textController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isCreating) {
        _focusNode.requestFocus();
      }
    });
    final palette = boardPaletteOf(context);
    return Padding(
      padding: widget.boardConfig.groupFooterPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // A column with nothing in it says so, rather than trailing off into
          // an empty well.
          if (widget.columnData.items.isEmpty && !_isCreating)
            _EmptyColumnHint(palette: palette),
          AnimatedSize(
            duration: BoardMetrics.settle,
            curve: BoardMetrics.hoverCurve,
            alignment: Alignment.topCenter,
            child: AnimatedSwitcher(
              duration: BoardMetrics.settle,
              child: _isCreating
                  ? _createCardsTextField()
                  : _startCreatingCardsButton(palette),
            ),
          ),
        ],
      ),
    );
  }

  Widget _createCardsTextField() {
    const nada = DoNothingAndStopPropagationIntent();
    return Shortcuts(
      shortcuts: {
        const SingleActivator(LogicalKeyboardKey.arrowUp): nada,
        const SingleActivator(LogicalKeyboardKey.arrowDown): nada,
        const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): nada,
        const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true): nada,
        const SingleActivator(LogicalKeyboardKey.keyE): nada,
        const SingleActivator(LogicalKeyboardKey.keyN): nada,
        const SingleActivator(LogicalKeyboardKey.delete): nada,
        // const SingleActivator(LogicalKeyboardKey.backspace): nada,
        const SingleActivator(LogicalKeyboardKey.enter): nada,
        const SingleActivator(LogicalKeyboardKey.numpadEnter): nada,
        const SingleActivator(LogicalKeyboardKey.comma): nada,
        const SingleActivator(LogicalKeyboardKey.period): nada,
        SingleActivator(
          LogicalKeyboardKey.arrowUp,
          shift: true,
          meta: Platform.isMacOS,
          control: !Platform.isMacOS,
        ): nada,
      },
      child: FlowyTextField(
        hintTextConstraints: const BoxConstraints(maxHeight: 36),
        controller: _textController,
        focusNode: _focusNode,
        onSubmitted: (name) {
          context.read<BoardBloc>().add(
                BoardEvent.createRow(
                  widget.columnData.id,
                  OrderObjectPositionTypePB.End,
                  name,
                  null,
                ),
              );
          widget.scrollManager.scrollToBottom(widget.columnData.id);
          _textController.clear();
          _focusNode.requestFocus();
        },
      ),
    );
  }

  Widget _startCreatingCardsButton(BoardPalette palette) {
    return BlocListener<BoardActionsCubit, BoardActionsState>(
      listener: (context, state) {
        state.maybeWhen(
          startCreateBottomRow: (groupId) {
            if (groupId == widget.columnData.id) {
              setState(() => _isCreating = true);
            }
          },
          orElse: () {},
        );
      },
      child: FlowyTooltip(
        message: LocaleKeys.board_column_addToColumnBottomTooltip.tr(),
        child: _NewCardRow(
          palette: palette,
          onTap: () => context
              .read<BoardActionsCubit>()
              .startCreateBottomRow(widget.columnData.id),
        ),
      ),
    );
  }
}

/// The invitation at the foot of a column.
class _NewCardRow extends StatefulWidget {
  const _NewCardRow({required this.palette, required this.onTap});

  final BoardPalette palette;
  final VoidCallback onTap;

  @override
  State<_NewCardRow> createState() => _NewCardRowState();
}

class _NewCardRowState extends State<_NewCardRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: BoardMetrics.hover,
          curve: BoardMetrics.hoverCurve,
          height: 34,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          decoration: BoxDecoration(
            color: _hovered ? palette.surface : palette.hoverAtRest,
            borderRadius: BorderRadius.circular(BoardMetrics.cardRadius - 4),
            boxShadow: _hovered
                ? palette.cardShadow(prominence: 0.7)
                : const <BoxShadow>[],
          ),
          child: Row(
            children: [
              Icon(Icons.add_rounded, size: 16, color: palette.textMuted),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  LocaleKeys.board_column_createNewCard.tr(),
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: palette.textSecondary,
                  ),
                ),
              ),
              AnimatedOpacity(
                duration: BoardMetrics.hover,
                opacity: _hovered ? 1 : 0,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                  decoration: BoxDecoration(
                    color: palette.raised,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'N',
                    style: TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: palette.textMuted,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What a column shows before anything has been put in it.
class _EmptyColumnHint extends StatelessWidget {
  const _EmptyColumnHint({required this.palette});

  final BoardPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 10, 4, 14),
      child: Column(
        children: [
          Container(
            width: 42,
            height: 34,
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(9),
              boxShadow: palette.cardShadow(prominence: 0.5),
            ),
            alignment: Alignment.center,
            child: Icon(
              Icons.dashboard_customize_outlined,
              size: 16,
              color: palette.textMuted,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            LocaleKeys.board_column_emptyColumn.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 12,
              height: 1.45,
              color: palette.textMuted,
            ),
          ),
        ],
      ),
    );
  }
}

class _BoardCard extends StatefulWidget {
  const _BoardCard({
    required this.afGroupData,
    required this.groupItem,
    required this.boardConfig,
    required this.columnWash,
    required this.cellBuilder,
    required this.notifier,
    required this.compactMode,
    required this.onOpenCard,
  });

  final AppFlowyGroupData afGroupData;
  final GroupItem groupItem;
  final AppFlowyBoardConfig boardConfig;
  final Color? columnWash;
  final CardCellBuilder cellBuilder;
  final BoardFocusScope notifier;
  final bool compactMode;
  final void Function(RowMetaPB) onOpenCard;

  @override
  State<_BoardCard> createState() => _BoardCardState();
}

class _BoardCardState extends State<_BoardCard> {
  bool _isEditing = false;
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final boardBloc = context.read<BoardBloc>();
    final groupData = widget.afGroupData.customData as GroupData;
    final rowCache = boardBloc.rowCache;
    final databaseController = boardBloc.databaseController;
    final rowMeta =
        rowCache.getRow(widget.groupItem.id)?.rowMeta ?? widget.groupItem.row;

    const nada = DoNothingAndStopPropagationIntent();

    return BlocListener<BoardActionsCubit, BoardActionsState>(
      listener: (context, state) {
        state.maybeMap(
          startEditingRow: (value) {
            if (value.groupedRowId.rowId == widget.groupItem.id &&
                value.groupedRowId.groupId == groupData.group.groupId) {
              setState(() => _isEditing = true);
            }
          },
          endEditingRow: (_) {
            if (_isEditing) {
              setState(() => _isEditing = false);
            }
          },
          createRow: (value) {
            if ((_isEditing && value.groupedRowId == null) ||
                (value.groupedRowId?.rowId == widget.groupItem.id &&
                    value.groupedRowId?.groupId == groupData.group.groupId)) {
              context.read<BoardBloc>().add(
                    BoardEvent.createRow(
                      groupData.group.groupId,
                      value.position == CreateBoardCardRelativePosition.before
                          ? OrderObjectPositionTypePB.Before
                          : OrderObjectPositionTypePB.After,
                      null,
                      widget.groupItem.row.id,
                    ),
                  );
            }
          },
          orElse: () {},
        );
      },
      child: Shortcuts(
        shortcuts: {
          const SingleActivator(LogicalKeyboardKey.arrowUp): nada,
          const SingleActivator(LogicalKeyboardKey.arrowDown): nada,
          const SingleActivator(LogicalKeyboardKey.arrowUp, shift: true): nada,
          const SingleActivator(LogicalKeyboardKey.arrowDown, shift: true):
              nada,
          const SingleActivator(LogicalKeyboardKey.keyE): nada,
          const SingleActivator(LogicalKeyboardKey.keyN): nada,
          const SingleActivator(LogicalKeyboardKey.delete): nada,
          // const SingleActivator(LogicalKeyboardKey.backspace): nada,
          const SingleActivator(LogicalKeyboardKey.enter): nada,
          const SingleActivator(LogicalKeyboardKey.numpadEnter): nada,
          const SingleActivator(LogicalKeyboardKey.comma): nada,
          const SingleActivator(LogicalKeyboardKey.period): nada,
          SingleActivator(
            LogicalKeyboardKey.arrowUp,
            shift: true,
            meta: Platform.isMacOS,
            control: !Platform.isMacOS,
          ): nada,
        },
        child: ConditionalListenableBuilder<List<GroupedRowId>>(
          valueListenable: widget.notifier,
          buildWhen: (previous, current) {
            final focusItem = GroupedRowId(
              groupId: groupData.group.groupId,
              rowId: rowMeta.id,
            );
            final previousContainsFocus = previous.contains(focusItem);
            final currentContainsFocus = current.contains(focusItem);

            return previousContainsFocus != currentContainsFocus;
          },
          builder: (context, focusedItems, child) {
            final cardMargin = widget.boardConfig.cardMargin;
            final margin = widget.compactMode
                ? cardMargin - EdgeInsets.symmetric(horizontal: 2)
                : cardMargin;
            final focused = widget.notifier.isFocused(
              GroupedRowId(
                rowId: widget.groupItem.id,
                groupId: groupData.group.groupId,
              ),
            );
            return BoardColumnWash(
              color: widget.columnWash,
              padding: margin +
                  const EdgeInsets.symmetric(
                    horizontal: BoardMetrics.columnInset,
                  ),
              child: MouseRegion(
                opaque: false,
                onEnter: (_) => setState(() => _hovered = true),
                onExit: (_) => setState(() => _hovered = false),
                child: AnimatedScale(
                  duration: BoardMetrics.hover,
                  curve: BoardMetrics.hoverCurve,
                  scale: _hovered ? BoardMetrics.cardGrowth : 1,
                  child: AnimatedContainer(
                    duration: BoardMetrics.hover,
                    curve: BoardMetrics.hoverCurve,
                    clipBehavior: Clip.antiAlias,
                    transform: Matrix4.translationValues(
                      0,
                      _hovered ? -BoardMetrics.cardLift : 0,
                      0,
                    ),
                    decoration: _makeBoxDecoration(context, focused),
                    child: child,
                  ),
                ),
              ),
            );
          },
          child: RowCard(
            fieldController: databaseController.fieldController,
            rowMeta: rowMeta,
            viewId: boardBloc.viewId,
            rowCache: rowCache,
            groupingFieldId: widget.groupItem.fieldInfo.id,
            isEditing: _isEditing,
            cellBuilder: widget.cellBuilder,
            onTap: (context) => widget.onOpenCard(
              context.read<CardBloc>().rowController.rowMeta,
            ),
            onShiftTap: (_) {
              Focus.of(context).requestFocus();
              widget.notifier.toggle(
                GroupedRowId(
                  rowId: widget.groupItem.row.id,
                  groupId: groupData.group.groupId,
                ),
              );
            },
            styleConfiguration: RowCardStyleConfiguration(
              cellStyleMap: desktopBoardCardCellStyleMap(context),
              cardPadding: widget.compactMode
                  ? const EdgeInsets.fromLTRB(10, 8, 10, 9)
                  : const EdgeInsets.fromLTRB(12, 10, 12, 11),
              coverRadius: BoardMetrics.cardRadius,
            ),
            onStartEditing: () =>
                context.read<BoardActionsCubit>().startEditingRow(
                      GroupedRowId(
                        groupId: groupData.group.groupId,
                        rowId: rowMeta.id,
                      ),
                    ),
            onEndEditing: () => context.read<BoardActionsCubit>().endEditing(
                  GroupedRowId(
                    groupId: groupData.group.groupId,
                    rowId: rowMeta.id,
                  ),
                ),
            userProfile: context.read<BoardBloc>().userProfile,
          ),
        ),
      ),
    );
  }

  BoxDecoration _makeBoxDecoration(BuildContext context, bool focused) {
    final palette = boardPaletteOf(context);
    // A card is defined by its shadow, not by an outline; only a focused one
    // draws a ring, and only in the accent.
    return BoxDecoration(
      color: _hovered ? palette.raised : palette.surface,
      borderRadius: BorderRadius.circular(BoardMetrics.cardRadius),
      border: focused
          ? Border.all(color: palette.accent, width: 1.4)
          : Border.all(color: palette.border.withValues(alpha: 0.28)),
      boxShadow: palette.cardShadow(
        prominence: _hovered ? 1 : 0.6,
        lift: _hovered ? BoardMetrics.cardLift : 0,
      ),
    );
  }
}

class BoardTrailing extends StatefulWidget {
  const BoardTrailing({super.key, required this.scrollController});

  final ScrollController scrollController;

  @override
  State<BoardTrailing> createState() => _BoardTrailingState();
}

class _BoardTrailingState extends State<BoardTrailing> {
  final TextEditingController _textController = TextEditingController();
  late final FocusNode _focusNode;

  bool isEditing = false;

  void _cancelAddNewGroup() {
    _textController.clear();
    setState(() => isEditing = false);
  }

  @override
  void initState() {
    super.initState();
    _focusNode = FocusNode(
      onKeyEvent: (node, event) {
        if (_focusNode.hasFocus &&
            event.logicalKey == LogicalKeyboardKey.escape) {
          _cancelAddNewGroup();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
    )..addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _textController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // call after every setState
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (isEditing) {
        _focusNode.requestFocus();
        widget.scrollController.jumpTo(
          widget.scrollController.position.maxScrollExtent,
        );
      }
    });

    return Container(
      padding: const EdgeInsets.only(left: 8.0, top: 12, right: 40),
      alignment: AlignmentDirectional.topStart,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 300),
        child: isEditing
            ? SizedBox(
                width: 256,
                child: Padding(
                  padding: const EdgeInsets.all(8.0),
                  child: TextField(
                    controller: _textController,
                    focusNode: _focusNode,
                    decoration: InputDecoration(
                      suffixIcon: Padding(
                        padding: const EdgeInsets.only(left: 4, bottom: 8.0),
                        child: FlowyIconButton(
                          icon: const FlowySvg(FlowySvgs.close_filled_s),
                          hoverColor: Colors.transparent,
                          onPressed: () => _textController.clear(),
                        ),
                      ),
                      suffixIconConstraints:
                          BoxConstraints.loose(const Size(20, 24)),
                      border: const UnderlineInputBorder(),
                      contentPadding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
                      isDense: true,
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                    onSubmitted: (groupName) => context
                        .read<BoardBloc>()
                        .add(BoardEvent.createGroup(groupName)),
                  ),
                ),
              )
            : FlowyTooltip(
                message: LocaleKeys.board_column_createNewColumn.tr(),
                child: FlowyIconButton(
                  width: 26,
                  icon: const FlowySvg(FlowySvgs.add_s),
                  iconColorOnHover: Theme.of(context).colorScheme.onSurface,
                  onPressed: () => setState(() => isEditing = true),
                ),
              ),
      ),
    );
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _cancelAddNewGroup();
    }
  }
}

void _openCard({
  required BuildContext context,
  required DatabaseController databaseController,
  required RowMetaPB rowMeta,
}) {
  final rowController = RowController(
    rowMeta: rowMeta,
    viewId: databaseController.viewId,
    rowCache: databaseController.rowCache,
  );

  FlowyOverlay.show(
    context: context,
    builder: (_) => BlocProvider.value(
      value: context.read<UserWorkspaceBloc>(),
      child: RowDetailPage(
        databaseController: databaseController,
        rowController: rowController,
        userProfile: context.read<BoardBloc>().userProfile,
      ),
    ),
  );
}
