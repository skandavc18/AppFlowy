import 'dart:convert';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/block_align.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import 'spreadsheet_controller.dart';
import 'spreadsheet_grid.dart';
import 'spreadsheet_io.dart';
import 'spreadsheet_menus.dart';
import 'spreadsheet_model.dart';
import 'spreadsheet_table_conversion.dart';
import 'spreadsheet_theme.dart';
import 'spreadsheet_toolbar.dart';

class SpreadsheetBlockKeys {
  const SpreadsheetBlockKeys._();

  static const String type = 'spreadsheet';

  /// The serialised [SpreadsheetData].
  static const String data = 'data';
  static const String title = 'title';
  static const String width = 'width';
  static const String height = 'height';
  static const String collapsed = 'collapsed';
}

Node spreadsheetNode({
  SpreadsheetData? data,
  String? title,
  double width = SpreadsheetMetrics.defaultBlockWidth,
  double height = SpreadsheetMetrics.defaultBlockHeight,
}) {
  return Node(
    type: SpreadsheetBlockKeys.type,
    attributes: {
      SpreadsheetBlockKeys.data: (data ?? SpreadsheetData.empty()).toJson(),
      if (title != null) SpreadsheetBlockKeys.title: title,
      SpreadsheetBlockKeys.width: width,
      SpreadsheetBlockKeys.height: height,
    },
  );
}

class SpreadsheetBlockComponentBuilder extends BlockComponentBuilder {
  SpreadsheetBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return SpreadsheetBlockComponent(
      key: node.key,
      node: node,
      showActions: showActions(node),
      configuration: configuration,
      actionBuilder: (_, state) => actionBuilder(blockComponentContext, state),
    );
  }

  @override
  BlockComponentValidate get validate => (node) => node.children.isEmpty;
}

class SpreadsheetBlockComponent extends BlockComponentStatefulWidget {
  const SpreadsheetBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.actionTrailingBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<SpreadsheetBlockComponent> createState() =>
      SpreadsheetBlockComponentState();
}

class SpreadsheetBlockComponentState extends State<SpreadsheetBlockComponent>
    with BlockComponentConfigurable, SelectableMixin {
  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  @override
  Node get node => widget.node;

  late EditorState editorState =
      Provider.of<EditorState>(context, listen: false);
  final GlobalKey _blockKey = GlobalKey(debugLabel: SpreadsheetBlockKeys.type);

  late SpreadsheetController _controller;
  String _lastWritten = '';
  bool _findVisible = false;
  bool _hovered = false;

  RenderBox? get _renderBox => context.findRenderObject() as RenderBox?;

  bool get _editable => editorState.editable;

  @override
  void initState() {
    super.initState();
    _controller = _createController();
  }

  @override
  void didUpdateWidget(covariant SpreadsheetBlockComponent oldWidget) {
    super.didUpdateWidget(oldWidget);
    final incoming = jsonEncode(_readData());
    if (incoming != _lastWritten) {
      final previous = _controller;
      _controller = _createController();
      previous.dispose();
    }
  }

  @override
  void dispose() {
    _controller
      ..flushPersist()
      ..dispose();
    super.dispose();
  }

  Map<String, dynamic> _readData() {
    final raw = node.attributes[SpreadsheetBlockKeys.data];
    if (raw is Map) {
      return Map<String, dynamic>.from(raw);
    }
    return SpreadsheetData.empty().toJson();
  }

  SpreadsheetController _createController() {
    final json = _readData();
    _lastWritten = jsonEncode(json);
    return SpreadsheetController(
      data: SpreadsheetData.fromJson(json),
      editable: _editable,
      onChanged: _persist,
    );
  }

  Future<void> _persist(SpreadsheetData data) async {
    if (!mounted || !editorState.editable) {
      return;
    }
    final json = data.toJson();
    final encoded = jsonEncode(json);
    if (encoded == _lastWritten) {
      return;
    }
    _lastWritten = encoded;
    await _updateAttributes({SpreadsheetBlockKeys.data: json});
  }

  Future<void> _updateAttributes(Map<String, Object?> attributes) {
    if (node.parent == null) {
      return Future.value();
    }
    final transaction = editorState.transaction..updateNode(node, attributes);
    return editorState.apply(transaction);
  }

  double get _width =>
      (node.attributes[SpreadsheetBlockKeys.width] as num?)?.toDouble() ??
      SpreadsheetMetrics.defaultBlockWidth;

  double get _height =>
      (node.attributes[SpreadsheetBlockKeys.height] as num?)?.toDouble() ??
      SpreadsheetMetrics.defaultBlockHeight;

  bool get _collapsed =>
      node.attributes[SpreadsheetBlockKeys.collapsed] == true;

  String get _title {
    final stored = node.attributes[SpreadsheetBlockKeys.title];
    if (stored is String && stored.trim().isNotEmpty) {
      return stored;
    }
    return LocaleKeys.spreadsheet_name.tr();
  }

  @override
  Widget build(BuildContext context) {
    Widget child = _buildSheet(context);

    child = Padding(
      padding: padding,
      child: RepaintBoundary(key: _blockKey, child: child),
    );

    child = BlockSelectionContainer(
      node: node,
      delegate: this,
      listenable: editorState.selectionNotifier,
      remoteSelection: editorState.remoteSelections,
      blockColor: editorState.editorStyle.selectionColor,
      supportTypes: const [BlockSelectionType.block],
      child: child,
    );

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        actionTrailingBuilder: widget.actionTrailingBuilder,
        child: child,
      );
    }
    return child;
  }

  Widget _buildSheet(BuildContext context) {
    final palette = SpreadsheetPalette.of(context);
    final alignment = blockEmbedAlignment(node);
    return Align(
      alignment: alignment,
      child: ResizableMedia(
        width: _width,
        minWidth: SpreadsheetMetrics.minBlockWidth,
        height: _collapsed ? null : _height,
        minHeight: SpreadsheetMetrics.minBlockHeight,
        maxHeight: SpreadsheetMetrics.maxBlockHeight,
        alignment: alignment,
        editable: _editable,
        onResize: (value) =>
            _updateAttributes({SpreadsheetBlockKeys.width: value}),
        onResizeHeight: _collapsed
            ? null
            : (value) =>
                _updateAttributes({SpreadsheetBlockKeys.height: value}),
        child: _buildBody(palette),
      ),
    );
  }

  /// No card: the sheet sits flush on the page like a database grid, with
  /// hairlines rather than a frame doing the structural work.
  Widget _buildBody(SpreadsheetPalette palette) {
    // The editor owns Backspace, Enter and the arrow keys for the whole
    // document. Clearing the selection while the sheet holds focus is what
    // lets those keys reach the grid instead of deleting the block.
    return FocusScope(
      skipTraversal: true,
      onFocusChange: (hasFocus) {
        if (hasFocus && keepEditorFocusNotifier.value == 0) {
          editorState.selection = null;
        }
      },
      child: Focus(
        canRequestFocus: false,
        skipTraversal: true,
        onKeyEvent: _onBlockKey,
        child: MouseRegion(
          opaque: false,
          onEnter: (_) => _setHovered(true),
          onExit: (_) => _setHovered(false),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ListenableBuilder(
                listenable: _controller,
                builder: (context, _) => _buildHeader(palette),
              ),
              if (!_collapsed) ...[
                if (_findVisible)
                  ListenableBuilder(
                    listenable: _controller,
                    builder: (context, _) => SpreadsheetFindBar(
                      controller: _controller,
                      editable: _editable,
                      onClose: () => setState(() => _findVisible = false),
                    ),
                  ),
                Expanded(
                  child: SpreadsheetGrid(
                    controller: _controller,
                    editable: _editable,
                    baseTextStyle:
                        editorState.editorStyle.textStyleConfiguration.text,
                    placeholder: LocaleKeys.spreadsheet_startTyping.tr(),
                    addRowLabel: LocaleKeys.spreadsheet_menu_newRow.tr(),
                    onRequestFind: () => setState(() => _findVisible = true),
                  ),
                ),
                ListenableBuilder(
                  listenable: _controller,
                  builder: (context, _) => SpreadsheetFooter(
                    controller: _controller,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _setHovered(bool value) {
    if (_hovered != value && mounted) {
      setState(() => _hovered = value);
    }
  }

  /// Focus can sit on a control inside the block that has no use for Backspace
  /// — a toolbar button, the footer, whatever a closed popover handed it back
  /// to. Left alone the key reaches the editor, which reads it as "delete the
  /// selected block" and takes the whole sheet with it.
  KeyEventResult _onBlockKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if (key != LogicalKeyboardKey.backspace &&
        key != LogicalKeyboardKey.delete) {
      return KeyEventResult.ignored;
    }
    final focus = FocusManager.instance.primaryFocus;
    if (focus?.context?.findAncestorWidgetOfExactType<EditableText>() != null) {
      return KeyEventResult.ignored;
    }
    editorState.selection = null;
    return KeyEventResult.skipRemainingHandlers;
  }

  /// The block's controls, right-aligned above the grid. There is no title:
  /// the sheet identifies itself by its content, like a database view.
  Widget _buildHeader(SpreadsheetPalette palette) {
    final showControls = _hovered || _findVisible;
    return SizedBox(
      height: SpreadsheetMetrics.blockHeaderHeight,
      child: Row(
        children: [
          // Collapsed, the grid is hidden, so the header has to say what the
          // block is.
          if (_collapsed)
            Text(
              '${_controller.data.rowCount} × '
              '${_controller.data.columnCount}',
              style: TextStyle(fontSize: 11.5, color: palette.textMuted),
            ),
          const Spacer(),
          AnimatedOpacity(
            duration: AppFlowyMotion.fast,
            curve: AppFlowyMotion.standardCurve,
            opacity: showControls || _collapsed ? 1 : 0,
            child: IgnorePointer(
              ignoring: !showControls && !_collapsed,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SpreadsheetToolbarButton(
                    icon: Icons.search_rounded,
                    tooltip: LocaleKeys.spreadsheet_toolbar_find.tr(),
                    active: _findVisible,
                    onPressed: _toggleFind,
                  ),
                  SpreadsheetAnchoredButton(
                    icon: Icons.filter_list_rounded,
                    tooltip: LocaleKeys.spreadsheet_toolbar_data.tr(),
                    active: _controller.data.filters.isNotEmpty ||
                        _controller.data.sort != null,
                    onOpen: _openDataMenu,
                  ),
                  if (_editable)
                    SpreadsheetAnchoredButton(
                      icon: Icons.add_rounded,
                      tooltip: LocaleKeys.spreadsheet_toolbar_insert.tr(),
                      onOpen: _openInsertMenu,
                    ),
                  SpreadsheetAnchoredButton(
                    icon: Icons.more_horiz_rounded,
                    tooltip: LocaleKeys.spreadsheet_toolbar_more.tr(),
                    onOpen: _openMoreMenu,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _toggleFind() {
    setState(() => _findVisible = !_findVisible);
    if (!_findVisible) {
      _controller.setSearch('');
    }
  }

  // -------------------------------------------------------------------
  // Header menus
  // -------------------------------------------------------------------

  /// Sorting, filtering and column typing — everything that changes what the
  /// grid shows rather than what it holds.
  void _openDataMenu(Offset position) {
    final column = _controller.selection.left;
    showSpreadsheetMenu(
      context: context,
      position: position,
      alignRight: true,
      width: 246,
      entries: [
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_sortAscending.tr(),
          icon: Icons.arrow_upward_rounded,
          enabled: _editable,
          selected: _controller.data.sort?.column == column &&
              _controller.data.sort?.direction == SortDirection.ascending,
          onSelected: () =>
              _controller.sortByColumn(column, SortDirection.ascending),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_sortDescending.tr(),
          icon: Icons.arrow_downward_rounded,
          enabled: _editable,
          selected: _controller.data.sort?.column == column &&
              _controller.data.sort?.direction == SortDirection.descending,
          onSelected: () =>
              _controller.sortByColumn(column, SortDirection.descending),
        ),
        const SpreadsheetMenuEntry.divider(),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_filter.tr(),
          icon: Icons.filter_alt_rounded,
          selected: _controller.filterFor(column).isNotEmpty,
          onSelected: () => showSpreadsheetFilterPrompt(
            context: context,
            controller: _controller,
            column: column,
          ),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_clearFilters.tr(),
          icon: Icons.filter_alt_off_rounded,
          enabled: _editable && _controller.data.filters.isNotEmpty,
          onSelected: _controller.clearFilters,
        ),
        const SpreadsheetMenuEntry.divider(),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_detectTypes.tr(),
          icon: Icons.auto_fix_high_rounded,
          enabled: _editable,
          onSelected: _controller.applyAutomaticColumnTypes,
        ),
      ],
    );
  }

  void _openInsertMenu(Offset position) {
    final selection = _controller.selection;
    showSpreadsheetMenu(
      context: context,
      position: position,
      alignRight: true,
      width: 228,
      entries: [
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_insertRowAbove.tr(),
          icon: Icons.vertical_align_top_rounded,
          onSelected: () => _controller.insertRowsAt(selection.top, 1),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_insertRowBelow.tr(),
          icon: Icons.vertical_align_bottom_rounded,
          onSelected: () => _controller.insertRowsAt(selection.bottom + 1, 1),
        ),
        const SpreadsheetMenuEntry.divider(),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_insertColumnLeft.tr(),
          icon: Icons.keyboard_tab_rounded,
          onSelected: () => _controller.insertColumnsAt(selection.left, 1),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_insertColumnRight.tr(),
          icon: Icons.keyboard_tab_rounded,
          onSelected: () => _controller.insertColumnsAt(selection.right + 1, 1),
        ),
        const SpreadsheetMenuEntry.divider(),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_deleteRow.tr(),
          icon: Icons.remove_circle_outline_rounded,
          enabled: _controller.data.rowCount > 1,
          destructive: true,
          onSelected: () =>
              _controller.deleteRowsAt(selection.top, selection.rowCount),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_deleteColumn.tr(),
          icon: Icons.remove_circle_outline_rounded,
          enabled: _controller.data.columnCount > 1,
          destructive: true,
          onSelected: () => _controller.deleteColumnsAt(
            selection.left,
            selection.columnCount,
          ),
        ),
      ],
    );
  }

  /// Everything about the block itself: how it is shown, where its data goes
  /// and what it can become.
  void _openMoreMenu(Offset position) {
    final hasHidden = List.generate(
      _controller.data.columnCount,
      (index) => index,
    ).any(_controller.data.isColumnHidden);

    showSpreadsheetMenu(
      context: context,
      position: position,
      alignRight: true,
      width: 262,
      entries: [
        SpreadsheetMenuEntry(
          label: _collapsed
              ? LocaleKeys.spreadsheet_toolbar_expand.tr()
              : LocaleKeys.spreadsheet_toolbar_collapse.tr(),
          icon: _collapsed
              ? Icons.unfold_more_rounded
              : Icons.unfold_less_rounded,
          onSelected: () =>
              _updateAttributes({SpreadsheetBlockKeys.collapsed: !_collapsed}),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_headerRow.tr(),
          icon: Icons.table_rows_rounded,
          enabled: _editable,
          selected: _controller.data.showHeader,
          onSelected: () =>
              _controller.setShowHeader(!_controller.data.showHeader),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_showAllColumns.tr(),
          icon: Icons.visibility_rounded,
          enabled: _editable && hasHidden,
          onSelected: _controller.showAllColumns,
        ),
        const SpreadsheetMenuEntry.divider(),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_data_convertToDatabase.tr(),
          icon: Icons.grid_view_rounded,
          enabled: _editable,
          onSelected: _convertToDatabase,
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_data_convertToTable.tr(),
          icon: Icons.table_view_rounded,
          enabled: _editable,
          onSelected: _convertToSimpleTable,
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_data_saveToWorkspace.tr(),
          icon: Icons.drive_file_move_rounded,
          onSelected: _saveToWorkspace,
        ),
        const SpreadsheetMenuEntry.divider(),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_data_importDelimited.tr(),
          icon: Icons.upload_file_rounded,
          enabled: _editable,
          onSelected: () => _import(spreadsheetDelimitedExtensions),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_data_importExcel.tr(),
          icon: Icons.table_chart_rounded,
          enabled: _editable,
          onSelected: () => _import(spreadsheetWorkbookExtensions),
        ),
        const SpreadsheetMenuEntry.divider(),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_menu_copyAsMarkdown.tr(),
          icon: Icons.data_object_rounded,
          onSelected: _controller.copyAsMarkdown,
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_data_exportCsv.tr(),
          icon: Icons.download_rounded,
          onSelected: () => _runIo(
            () => exportSpreadsheetAsCsv(
              _controller.data,
              name: '${_fileStem()}.csv',
            ),
          ),
        ),
        SpreadsheetMenuEntry(
          label: LocaleKeys.spreadsheet_data_exportExcel.tr(),
          icon: Icons.download_for_offline_rounded,
          onSelected: () => _runIo(
            () => exportSpreadsheetAsXlsx(
              _controller.data,
              name: '${_fileStem()}.xlsx',
            ),
          ),
        ),
      ],
    );
  }

  String _fileStem() {
    final title = _title.trim();
    final safe = title.replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');
    return safe.isEmpty ? 'sheet' : safe;
  }

  Future<void> _import(List<String> extensions) async {
    final result = await importSpreadsheetFromFile(
      headerRow: _controller.data.showHeader,
      extensions: extensions,
    );
    if (!mounted) {
      return;
    }
    if (result.data != null) {
      _controller.replaceData(result.data!);
      _controller.flushPersist();
    }
    _report(result);
  }

  Future<void> _runIo(Future<SpreadsheetIoResult> Function() action) async {
    final result = await action();
    if (mounted) {
      _report(result);
    }
  }

  Future<void> _saveToWorkspace() async {
    final documentId = context.read<DocumentBloc?>()?.documentId ?? '';
    await _runIo(
      () => saveSpreadsheetToWorkspace(
        data: _controller.data,
        parentViewId: documentId,
        name: '${_fileStem()}.xlsx',
      ),
    );
  }

  Future<void> _convertToDatabase() async {
    final documentId = context.read<DocumentBloc?>()?.documentId ?? '';
    await _runIo(
      () => convertSpreadsheetToDatabase(
        data: _controller.data,
        parentViewId: documentId,
        name: _fileStem(),
      ),
    );
  }

  void _report(SpreadsheetIoResult result) {
    if (!result.hasMessage) {
      return;
    }
    if (result.failed) {
      showToastNotification(
        message: result.message!,
        type: ToastificationType.error,
      );
    } else {
      showToastNotification(message: result.message!);
    }
  }

  Future<void> _convertToSimpleTable() async {
    final table = simpleTableFromSpreadsheet(_controller.data);
    final path = node.path;
    final transaction = editorState.transaction
      ..insertNode(path, table)
      ..deleteNode(node);
    await editorState.apply(transaction);
  }

  // -------------------------------------------------------------------
  // SelectableMixin
  // -------------------------------------------------------------------

  @override
  Position start() => Position(path: node.path);

  @override
  Position end() => Position(path: node.path, offset: 1);

  @override
  Position getPositionInOffset(Offset start) => end();

  @override
  bool get shouldCursorBlink => false;

  @override
  CursorStyle get cursorStyle => CursorStyle.cover;

  @override
  Rect getBlockRect({bool shiftWithBaseOffset = false}) {
    final box = _blockKey.currentContext?.findRenderObject();
    if (box is RenderBox) {
      return padding.topLeft & box.size;
    }
    return Rect.zero;
  }

  @override
  Rect? getCursorRectInPosition(
    Position position, {
    bool shiftWithBaseOffset = false,
  }) {
    final rects = getRectsInSelection(Selection.collapsed(position));
    return rects.isEmpty ? null : rects.first;
  }

  @override
  List<Rect> getRectsInSelection(
    Selection selection, {
    bool shiftWithBaseOffset = false,
  }) {
    final box = _renderBox;
    if (box == null) {
      return [];
    }
    return [Offset.zero & box.size];
  }

  @override
  Selection getSelectionInRange(Offset start, Offset end) =>
      Selection.single(path: node.path, startOffset: 0, endOffset: 1);

  @override
  Offset localToGlobal(Offset offset, {bool shiftWithBaseOffset = false}) =>
      _renderBox?.localToGlobal(offset) ?? offset;
}
