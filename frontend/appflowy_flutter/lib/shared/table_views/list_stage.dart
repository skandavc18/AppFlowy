import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/database/widgets/cell_editor/extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/util/field_type_extension.dart';
import 'package:appflowy/workspace/application/table_views/list_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme_extension.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

/// The fixed sizes a list is drawn with.
abstract final class _ListMetrics {
  static const double lineHeight = 36;
  static const double radius = 6;
  static const double inset = 8;
  static const double border = 1.5;
  static const double iconSlot = 20;
  static const double gap = 10;
  static const double stripGap = 14;
  static const double chipMax = 200;
  static const double titleShare = 0.45;
  static const double titleMax = 260;
  static const double buttonSize = 26;
  static const double buttonGap = 6;
}

/// A table read as a list of pages.
///
/// One line per row: the page's icon and name on the left, the properties
/// that matter set quietly on the right, and nothing in between. New pages
/// are named where they will live, on the list itself.
class ListStage extends StatefulWidget {
  const ListStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.editable = true,
    this.source,
    this.onOpenRow,
    this.onAddRow,
    this.onCreateRow,
    this.onRenameRow,
    this.onDuplicateRow,
    this.onDeleteRow,
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final ListSpec spec;
  final ValueChanged<ListSpec> onSpecChanged;
  final String? title;

  /// Whether pages can be added, renamed, duplicated and deleted here.
  final bool editable;

  /// The rows to read. The stage reads [viewId] itself when none is given,
  /// and only disposes a source it made.
  final TableRowSource? source;

  final ValueChanged<String>? onOpenRow;

  /// Adds a page and opens it — the header's plus.
  final Future<String?> Function()? onAddRow;

  /// Adds a page already named. Hands back the row it made, or null.
  final Future<String?> Function(ListNewRow row)? onCreateRow;

  final Future<bool> Function(String rowId, String titleColumn, String title)?
      onRenameRow;
  final Future<bool> Function(String rowId)? onDuplicateRow;
  final Future<bool> Function(String rowId)? onDeleteRow;

  final EdgeInsets padding;

  @override
  State<ListStage> createState() => ListStageState();
}

class ListStageState extends State<ListStage> {
  late final TableRowSource _source =
      widget.source ?? TableRowSource(viewId: widget.viewId);
  final ScrollController _scroll = ScrollController();
  final GlobalKey<TableViewHeaderState> _header =
      GlobalKey<TableViewHeaderState>();
  final TextEditingController _renameText = TextEditingController();
  final FocusNode _renameFocus = FocusNode(debugLabel: 'List rename');

  String _search = '';
  List<TableRowCard> _visible = const [];
  Set<String> _matches = const {};
  List<FieldPB> _optionFields = const [];
  Map<String, Map<String, SelectOptionPB>> _options = const {};

  _ListDraft? _draft;
  final List<_PendingRow> _pending = [];
  final Map<String, _Rename> _renamed = {};
  final Map<String, _Optimistic> _removed = {};
  String? _renaming;
  int _nextPending = 0;

  TableQuery get _query => widget.spec.query(_search);

  bool get _canCreate => widget.editable && widget.onCreateRow != null;

  bool get _grouped => widget.spec.groupColumn.isNotEmpty;

  String get _ungrouped => LocaleKeys.tableViews_ungrouped.tr();

  @override
  void initState() {
    super.initState();
    _source.updateSpec(widget.spec.readSpec);
    _source.addListener(_onSourceChanged);
    _renameFocus.addListener(_onRenameFocus);
    _refine();
    unawaited(_source.load());
  }

  @override
  void didUpdateWidget(ListStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) {
      _source.updateSpec(widget.spec.readSpec);
      setState(_refine);
    }
    if (!_canCreate && _draft != null) {
      _closeDraft();
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onSourceChanged);
    if (widget.source == null) {
      _source.dispose();
    }
    _scroll.dispose();
    _renameFocus
      ..removeListener(_onRenameFocus)
      ..dispose();
    _renameText.dispose();
    _draft?.dispose();
    super.dispose();
  }

  /// Reads the table again — the host calls this when a row changes.
  void reload() => _source.invalidate();

  void _onSourceChanged() {
    if (mounted) {
      setState(() {
        _prune();
        _refine();
      });
    }
  }

  void _refine() {
    final cards = _removed.isEmpty
        ? _source.cards
        : [
            for (final card in _source.cards)
              if (!_removed.containsKey(card.rowId)) card,
          ];
    _visible = applyTableQuery(cards, _query);
    _matches = tableMatchesOf(_visible, _search);
    _syncOptions();
  }

  /// Forgets what the list was showing ahead of the table once the table has
  /// caught up with it.
  void _prune() {
    final revision = _source.revision;
    final titles = {for (final card in _source.cards) card.rowId: card.title};
    _renamed.removeWhere(
      (rowId, rename) => rename.mark
          .isDone(revision, matched: titles[rowId] == rename.title),
    );
    _removed.removeWhere(
      (rowId, mark) =>
          mark.isDone(revision, matched: !titles.containsKey(rowId)),
    );
    _pending.removeWhere(
      (row) =>
          row.mark.isDone(revision, matched: titles.containsKey(row.rowId)),
    );
    final renaming = _renaming;
    if (renaming != null && !titles.containsKey(renaming)) {
      _renaming = null;
    }
  }

  void _syncOptions() {
    final fields = _source.fields;
    if (identical(fields, _optionFields)) {
      return;
    }
    _optionFields = fields;
    final options = <String, Map<String, SelectOptionPB>>{};
    for (final field in fields) {
      final choices = listOptionsOf(field);
      if (choices.isNotEmpty) {
        options[field.id] = {
          for (final option in choices) option.name.toLowerCase(): option,
        };
      }
    }
    _options = options;
  }

  void _setQuery(TableQuery query) {
    final next = widget.spec.withQuery(query);
    setState(() {
      _search = query.search;
      _refine();
    });
    if (next != widget.spec) {
      widget.onSpecChanged(next);
    }
  }

  String _titleOf(TableRowCard card) =>
      _renamed[card.rowId]?.title ?? card.title;

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true): () =>
            _header.currentState?.openSearch(),
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): () =>
            _header.currentState?.openSearch(),
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _header.currentState?.closeSearch(),
      },
      child: Padding(
        padding: widget.padding,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(palette),
            const SizedBox(height: TableViewMetrics.space3),
            Expanded(child: _buildBody(palette)),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(TableViewPalette palette) => TableViewHeader(
        key: _header,
        palette: palette,
        title: widget.title?.trim().isNotEmpty == true
            ? widget.title!
            : LocaleKeys.listView_name.tr(),
        subtitle: LocaleKeys.tableViews_rowCount
            .tr(namedArgs: {'count': '${_visible.length}'}),
        columns: _source.fields,
        query: _query,
        onQueryChanged: _setQuery,
        valuesOf: (fieldId) => tableValuesOf(_source.cards, fieldId),
        onAdd: widget.editable && widget.onAddRow != null ? _addRow : null,
        optionsBuilder: _viewOptions,
        actions: [
          Builder(
            builder: (context) => TableViewButton(
              key: const ValueKey('list-properties-button'),
              palette: palette,
              icon: Icons.tune_rounded,
              tooltip: LocaleKeys.listView_properties.tr(),
              active: widget.spec.hiddenColumns.isNotEmpty ||
                  widget.spec.propertyColumns.isNotEmpty,
              onTap: () => unawaited(_showProperties(context)),
            ),
          ),
        ],
      );

  Widget _buildBody(TableViewPalette palette) {
    if (_source.isLoading && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.view_list_rounded,
        message: LocaleKeys.tableViews_loading.tr(),
      );
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.view_list_rounded,
        message: LocaleKeys.tableViews_couldNotRead.tr(),
        detail: error,
        actionLabel: LocaleKeys.tableViews_tryAgain.tr(),
        onAction: reload,
      );
    }
    if (_visible.isEmpty && _pending.isEmpty && _draft == null) {
      final filtering = _query.isFiltering;
      return TableViewEmpty(
        palette: palette,
        icon: Icons.view_list_rounded,
        message: filtering
            ? LocaleKeys.tableViews_noneMatch.tr()
            : LocaleKeys.listView_empty.tr(),
        detail: filtering
            ? LocaleKeys.tableViews_noneMatchDetail.tr()
            : LocaleKeys.listView_emptyDetail.tr(),
        actionLabel: filtering
            ? LocaleKeys.tableViews_clearFilter.tr()
            : LocaleKeys.listView_newPage.tr(),
        onAction: filtering
            ? () =>
                _setQuery(_query.copyWith(filterColumn: '', filterValue: ''))
            : (_canCreate
                ? () => _startDraft(_grouped ? _ungrouped : '')
                : null),
      );
    }

    final lines = _lines(_groups());
    final index = {for (var i = 0; i < lines.length; i++) lines[i].key: i};
    return Material(
      type: MaterialType.transparency,
      child: Scrollbar(
        controller: _scroll,
        child: ListView.builder(
          controller: _scroll,
          padding: const EdgeInsets.only(bottom: TableViewMetrics.space6),
          itemCount: lines.length,
          // Lines are keyed so a page typed into the list keeps its field,
          // and its focus, while the lines above it come and go.
          findChildIndexCallback: (key) => index[key],
          itemBuilder: (context, at) => KeyedSubtree(
            key: lines[at].key,
            child: _buildLine(palette, lines[at]),
          ),
        ),
      ),
    );
  }

  List<TableRowGroup> _groups() {
    final column = widget.spec.groupColumn;
    final ungrouped = _ungrouped;
    final groups = groupTableRows(_visible, column, ungrouped: ungrouped);
    if (column.isEmpty) {
      return groups;
    }
    final options = _options[column];
    return orderListGroups(
      groups,
      options == null ? const [] : [for (final o in options.values) o.name],
      ungrouped: ungrouped,
    );
  }

  List<_Line> _lines(List<TableRowGroup> groups) {
    final grouped = _grouped;
    final draft = _draft;
    final lines = <_Line>[];
    final covered = <String>{};
    for (final group in groups) {
      final key = grouped ? group.label : '';
      covered.add(key);
      final collapsed = grouped && widget.spec.isCollapsed(group.label);
      if (grouped) {
        lines.add(_HeadingLine(group, collapsed: collapsed));
      }
      if (collapsed) {
        continue;
      }
      if (draft != null && draft.group == key && draft.atTop) {
        lines.add(const _DraftLine());
      }
      for (final card in group.rows) {
        lines.add(_RowLine(card));
      }
      _addTail(lines, key, draft);
      if (grouped) {
        lines.add(_GapLine(key));
      }
    }
    // Something typed under a group with no rows yet still has to show.
    final orphans = <String>{
      for (final row in _pending)
        if (!covered.contains(row.group)) row.group,
      if (draft != null && !covered.contains(draft.group)) draft.group,
    };
    for (final key in orphans) {
      if (grouped) {
        lines.add(
          _HeadingLine(
            TableRowGroup(label: key, rows: const []),
            collapsed: false,
          ),
        );
      }
      _addTail(lines, key, draft?.group == key ? draft : null, top: true);
    }
    return lines;
  }

  void _addTail(
    List<_Line> lines,
    String key,
    _ListDraft? draft, {
    bool top = false,
  }) {
    for (final row in _pending) {
      if (row.group == key) {
        lines.add(_PendingLine(row));
      }
    }
    if (!_canCreate) {
      return;
    }
    final drafting =
        draft != null && draft.group == key && (top || !draft.atTop);
    lines.add(drafting ? const _DraftLine() : _AddLine(key));
  }

  Widget _buildLine(TableViewPalette palette, _Line line) => switch (line) {
        _HeadingLine(:final group, :final collapsed) =>
          _buildHeading(palette, group, collapsed),
        _RowLine(:final card) => Padding(
            padding: const EdgeInsets.only(bottom: 1),
            child: _buildRow(palette, card),
          ),
        _PendingLine(:final row) => _ListPendingLine(
            palette: palette,
            title: row.title,
            showIcon: widget.spec.showIcons,
          ),
        _DraftLine() => _buildDraft(palette),
        _AddLine(:final group) => _ListAddLine(
            key: ValueKey('list-add-button:$group'),
            palette: palette,
            label: LocaleKeys.listView_newPage.tr(),
            onTap: () => _startDraft(group),
          ),
        _GapLine() => const SizedBox(height: TableViewMetrics.space3),
      };

  Widget _buildHeading(
    TableViewPalette palette,
    TableRowGroup group,
    bool collapsed,
  ) {
    final column = widget.spec.groupColumn;
    final plain = group.label == _ungrouped || !_options.containsKey(column);
    return _ListGroupHeading(
      palette: palette,
      label: plain
          ? Text(
              group.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
                color: group.label == _ungrouped
                    ? palette.textMuted
                    : palette.textSecondary,
              ).copyWith(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                fontVariations: const [FontVariation.weight(600)],
              ),
            )
          : _optionPill(palette, column, group.label),
      count: group.rows.length,
      collapsed: collapsed,
      onToggle: () => widget.onSpecChanged(
        widget.spec.toggleGroup(group.label),
      ),
      addTooltip: LocaleKeys.listView_newInGroup
          .tr(namedArgs: {'group': group.label}),
      onAdd: _canCreate
          ? () {
              if (collapsed) {
                widget.onSpecChanged(widget.spec.toggleGroup(group.label));
              }
              _startDraft(group.label, atTop: true);
            }
          : null,
    );
  }

  Widget _buildRow(TableViewPalette palette, TableRowCard card) {
    final canRename = widget.editable && widget.onRenameRow != null;
    return _ListRow(
      key: ValueKey('list-row-tile:${card.rowId}'),
      card: card,
      title: _titleOf(card),
      palette: palette,
      properties: widget.spec.shownOf(card.properties),
      chipFor: (property) => _chipFor(palette, property),
      showIcon: widget.spec.showIcons,
      quiet: _query.isSearching && !_matches.contains(card.rowId),
      editor: _renaming == card.rowId ? _buildRenameField(palette) : null,
      onOpen: widget.onOpenRow == null
          ? null
          : () => widget.onOpenRow!(card.rowId),
      onMenu: (context, position) => _showRowMenu(context, card, position),
      onRename: canRename ? () => _startRename(card) : null,
    );
  }

  Widget _buildRenameField(TableViewPalette palette) => CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.escape): _cancelRename,
        },
        child: TextField(
          key: const ValueKey('list-rename-field'),
          controller: _renameText,
          focusNode: _renameFocus,
          autofocus: true,
          style: _titleStyle(context, palette),
          cursorColor: palette.accent,
          decoration: InputDecoration.collapsed(
            hintText: LocaleKeys.listView_untitled.tr(),
            hintStyle: _titleStyle(context, palette, quiet: true),
          ),
          onSubmitted: (_) => unawaited(_commitRename()),
        ),
      );

  Widget _buildDraft(TableViewPalette palette) {
    final draft = _draft!;
    return _ListDraftLine(
      palette: palette,
      controller: draft.text,
      focusNode: draft.focus,
      showIcon: widget.spec.showIcons,
      hint: LocaleKeys.listView_draftHint.tr(),
      onSubmit: () => unawaited(_commitDraft(keepOpen: true)),
      onCancel: () => _closeDraft(draft),
    );
  }

  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------

  Widget _chipFor(TableViewPalette palette, TableProperty property) {
    final value = property.value.trim();
    final Widget chip = switch (property.kind) {
      TablePropertyKind.badge => _optionPill(
          palette,
          property.fieldId,
          tablePartsOf(value).firstOrNull ?? value,
        ),
      TablePropertyKind.tags => _tags(palette, property),
      TablePropertyKind.person => _people(palette, value),
      TablePropertyKind.checkbox => _checkbox(palette, property),
      TablePropertyKind.progress => _progress(palette, property),
      TablePropertyKind.rating => _rating(palette, property),
      TablePropertyKind.link =>
        _withGlyph(palette, Icons.link_rounded, _hostOf(value)),
      TablePropertyKind.image ||
      TablePropertyKind.files =>
        _withGlyph(palette, Icons.attach_file_rounded, _partsLabel(value)),
      TablePropertyKind.location =>
        _withGlyph(palette, Icons.place_rounded, value),
      TablePropertyKind.relation =>
        _withGlyph(palette, Icons.arrow_outward_rounded, _partsLabel(value)),
      _ => _text(palette, value.replaceAll(RegExp(r'\s*\n+\s*'), ' ')),
    };
    final description = '${property.name}: $value';
    return Tooltip(
      message: description,
      excludeFromSemantics: true,
      waitDuration: const Duration(milliseconds: 500),
      child: Semantics(
        label: description,
        child: ExcludeSemantics(child: chip),
      ),
    );
  }

  TextStyle _chipStyle(TableViewPalette palette, [Color? color]) =>
      WorkspaceTypography.style(
        context,
        WorkspaceTextRole.metadata,
        color: color ?? palette.textSecondary,
      ).copyWith(height: 1.3);

  Widget _text(TableViewPalette palette, String value, [Color? color]) => Text(
        value,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: _chipStyle(palette, color),
      );

  /// A choice drawn in the colour its column gave it, the way the grid draws
  /// it; a value with no colour of its own borrows one.
  Widget _optionPill(TableViewPalette palette, String fieldId, String label) {
    final option = _options[fieldId]?[label.toLowerCase()];
    final theme = Theme.of(context).extension<AFThemeExtension>();
    Color? fill;
    var ink = palette.textPrimary;
    if (option != null && theme != null) {
      try {
        fill = option.color.toColor(context);
        ink = theme.textColor;
      } on Object catch (_) {
        fill = null;
      }
    }
    if (fill == null) {
      final swatch = palette.swatchFor(label);
      fill = swatch.withValues(alpha: palette.isDark ? 0.26 : 0.14);
      ink = palette.isDark
          ? Color.lerp(swatch, Colors.white, 0.45)!
          : Color.lerp(swatch, Colors.black, 0.35)!;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: fill,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        maxLines: 1,
        softWrap: false,
        overflow: TextOverflow.ellipsis,
        style: _chipStyle(palette, ink).copyWith(
          fontWeight: FontWeight.w500,
          fontVariations: const [FontVariation.weight(500)],
        ),
      ),
    );
  }

  Widget _tags(TableViewPalette palette, TableProperty property) {
    final parts = tablePartsOf(property.value);
    final shown = parts.take(2).toList();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < shown.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Flexible(child: _optionPill(palette, property.fieldId, shown[i])),
        ],
        if (parts.length > shown.length) ...[
          const SizedBox(width: 4),
          _text(palette, '+${parts.length - shown.length}', palette.textMuted),
        ],
      ],
    );
  }

  Widget _people(TableViewPalette palette, String value) {
    final parts = tablePartsOf(value);
    final first = parts.firstOrNull ?? value;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        TableAvatar(name: first, palette: palette, size: 18),
        const SizedBox(width: 6),
        Flexible(
          child: _text(
            palette,
            parts.length > 1 ? '$first +${parts.length - 1}' : first,
          ),
        ),
      ],
    );
  }

  Widget _checkbox(TableViewPalette palette, TableProperty property) {
    final checked = const ['yes', 'true', '1', 'checked']
        .contains(property.value.trim().toLowerCase());
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        WorkspaceGlyph.named(
          checked ? 'checkbox' : 'square',
          size: 14,
          color: checked ? palette.accent : palette.textMuted,
        ),
        const SizedBox(width: 4),
        Flexible(child: _text(palette, property.name, palette.textMuted)),
      ],
    );
  }

  Widget _progress(TableViewPalette palette, TableProperty property) {
    final fraction = property.fraction;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (fraction != null) ...[
          SizedBox(
            width: 36,
            height: 4,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: palette.sunken,
                borderRadius: BorderRadius.circular(2),
              ),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: FractionallySizedBox(
                  widthFactor: fraction.clamp(0.0, 1.0),
                  heightFactor: 1,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: palette.accent,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
        ],
        Flexible(child: _text(palette, property.value.trim())),
      ],
    );
  }

  Widget _rating(TableViewPalette palette, TableProperty property) {
    final count = (property.rating ?? 0).clamp(0, 5);
    if (count == 0) {
      return _text(palette, property.value.trim());
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < count; i++)
          WorkspaceGlyph(
            Icons.star_rounded,
            size: 12,
            color: TableViewPalette.swatches[2],
          ),
      ],
    );
  }

  Widget _withGlyph(TableViewPalette palette, IconData icon, String label) =>
      Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          WorkspaceGlyph(icon, size: 13, color: palette.textMuted),
          const SizedBox(width: 4),
          Flexible(child: _text(palette, label)),
        ],
      );

  static String _hostOf(String value) {
    final host = Uri.tryParse(value)?.host ?? '';
    return host.isEmpty ? value : host.replaceFirst(RegExp(r'^www\.'), '');
  }

  static String _partsLabel(String value) {
    final parts = tablePartsOf(value);
    if (parts.isEmpty) {
      return value;
    }
    return parts.length == 1
        ? parts.first
        : '${parts.first} +${parts.length - 1}';
  }

  Future<void> _showProperties(BuildContext context) {
    final title = _source.titleColumn;
    final fields = [
      for (final field in _source.fields)
        if (field.id != title) field,
    ];
    return showAppMenuForWidget<void>(
      context: context,
      width: 280,
      entries: [
        AppMenuHeader(LocaleKeys.listView_properties.tr()),
        AppMenuCustom(
          builder: (_) => _ListPropertiesPanel(
            fields: fields,
            spec: widget.spec,
            onChanged: widget.onSpecChanged,
          ),
        ),
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Menus
  // ---------------------------------------------------------------------------

  List<AppMenuEntry> _viewOptions() {
    final spec = widget.spec;
    return [
      AppMenuItem(
        label: LocaleKeys.listView_showIcons.tr(),
        icon: Icons.emoji_emotions_rounded,
        selected: spec.showIcons,
        onSelected: () =>
            widget.onSpecChanged(spec.copyWith(showIcons: !spec.showIcons)),
      ),
      if (spec.groupColumn.isNotEmpty) ...[
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.listView_expandAll.tr(),
          icon: Icons.unfold_more_rounded,
          enabled: spec.collapsedGroups.isNotEmpty,
          onSelected: () =>
              widget.onSpecChanged(spec.copyWith(collapsedGroups: const [])),
        ),
        AppMenuItem(
          label: LocaleKeys.listView_collapseAll.tr(),
          icon: Icons.unfold_less_rounded,
          onSelected: () => widget.onSpecChanged(
            spec.copyWith(
              collapsedGroups: [for (final group in _groups()) group.label],
            ),
          ),
        ),
      ],
      const AppMenuSeparator(),
      AppMenuItem(
        label: LocaleKeys.tableViews_reload.tr(),
        icon: Icons.refresh_rounded,
        onSelected: reload,
      ),
    ];
  }

  Future<void> _showRowMenu(
    BuildContext context,
    TableRowCard card,
    Offset position,
  ) async {
    final editable = widget.editable;
    final action = await showAppMenu<_RowAction>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: LocaleKeys.listView_open.tr(),
          icon: Icons.open_in_new_rounded,
          enabled: widget.onOpenRow != null,
          value: _RowAction.open,
        ),
        if (editable && widget.onRenameRow != null)
          AppMenuItem(
            label: LocaleKeys.listView_rename.tr(),
            icon: Icons.edit_rounded,
            shortcut: 'F2',
            value: _RowAction.rename,
          ),
        if (editable && widget.onDuplicateRow != null)
          AppMenuItem(
            label: LocaleKeys.listView_duplicate.tr(),
            icon: Icons.content_copy_rounded,
            value: _RowAction.duplicate,
          ),
        AppMenuItem(
          label: LocaleKeys.tableViews_copyTitle.tr(),
          icon: Icons.title_rounded,
          value: _RowAction.copyTitle,
        ),
        if (editable && widget.onDeleteRow != null) ...[
          const AppMenuSeparator(),
          AppMenuItem(
            label: LocaleKeys.listView_delete.tr(),
            icon: Icons.delete_outline_rounded,
            destructive: true,
            value: _RowAction.delete,
          ),
        ],
      ],
    );
    // Acting once the menu has gone means a rename field gets the focus the
    // closing menu would otherwise hand back to the row.
    if (!mounted || action == null) {
      return;
    }
    switch (action) {
      case _RowAction.open:
        widget.onOpenRow?.call(card.rowId);
      case _RowAction.rename:
        _startRename(card);
      case _RowAction.duplicate:
        await widget.onDuplicateRow?.call(card.rowId);
      case _RowAction.copyTitle:
        await Clipboard.setData(ClipboardData(text: _titleOf(card)));
      case _RowAction.delete:
        await _delete(card);
    }
  }

  // ---------------------------------------------------------------------------
  // Adding, renaming and removing pages
  // ---------------------------------------------------------------------------

  void _addRow() {
    final add = widget.onAddRow;
    if (add != null) {
      unawaited(add());
    }
  }

  void _startDraft(String group, {bool atTop = false}) {
    if (!_canCreate) {
      return;
    }
    final current = _draft;
    if (current != null && current.group == group && current.atTop == atTop) {
      current.focus.requestFocus();
      return;
    }
    if (current != null) {
      // Moving to another group keeps what was typed in the last one.
      if (current.text.text.trim().isNotEmpty) {
        unawaited(_commitDraft(keepOpen: false));
      } else {
        _closeDraft(current);
      }
    }
    final draft = _ListDraft(group, atTop: atTop);
    draft.focus.addListener(() => _onDraftFocus(draft));
    setState(() => _draft = draft);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(_draft, draft)) {
        return;
      }
      draft.focus.requestFocus();
      final context = draft.focus.context;
      if (context != null) {
        unawaited(
          Scrollable.ensureVisible(
            context,
            alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
          ),
        );
      }
    });
  }

  void _onDraftFocus(_ListDraft draft) {
    if (draft.focus.hasFocus || draft.closed || !identical(_draft, draft)) {
      return;
    }
    // Clicking away keeps a name that was typed, as Enter would.
    if (draft.text.text.trim().isNotEmpty) {
      unawaited(_commitDraft(keepOpen: false));
    } else {
      _closeDraft(draft);
    }
  }

  void _closeDraft([_ListDraft? which]) {
    final draft = _draft;
    if (draft == null || (which != null && !identical(draft, which))) {
      return;
    }
    draft.closed = true;
    if (mounted) {
      setState(() => _draft = null);
    } else {
      _draft = null;
    }
    // The field is still mounted until the next frame; let it detach first.
    WidgetsBinding.instance.addPostFrameCallback((_) => draft.dispose());
  }

  Future<void> _commitDraft({required bool keepOpen}) async {
    final draft = _draft;
    final create = widget.onCreateRow;
    if (draft == null || create == null) {
      return;
    }
    final title = draft.text.text.trim();
    if (title.isEmpty) {
      if (!keepOpen) {
        _closeDraft(draft);
      }
      return;
    }
    final inGroup = _grouped && draft.group != _ungrouped;
    final request = ListNewRow(
      titleColumn: _source.titleColumn,
      title: title,
      groupColumn: inGroup ? widget.spec.groupColumn : '',
      groupValue: inGroup ? draft.group : '',
    );
    final row = _PendingRow(
      id: _nextPending++,
      title: title,
      group: draft.group,
    );
    setState(() {
      _pending.add(row);
      draft.text.clear();
    });
    if (!keepOpen) {
      _closeDraft(draft);
    }

    final rowId = await create(request);
    if (!mounted) {
      return;
    }
    setState(() {
      if (rowId == null) {
        _pending.remove(row);
        // Hand the words back rather than losing them.
        final open = _draft;
        if (open != null && open.group == row.group && open.text.text.isEmpty) {
          open.text.text = title;
        }
        return;
      }
      row
        ..rowId = rowId
        ..mark.settle(_source.revision);
      _prune();
    });
  }

  void _startRename(TableRowCard card) {
    if (!widget.editable || widget.onRenameRow == null) {
      return;
    }
    final title = _titleOf(card);
    setState(() {
      _renaming = card.rowId;
      _renameText.value = TextEditingValue(
        text: title,
        selection: TextSelection(baseOffset: 0, extentOffset: title.length),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _renaming == card.rowId) {
        _renameFocus.requestFocus();
      }
    });
  }

  void _onRenameFocus() {
    if (!_renameFocus.hasFocus && _renaming != null) {
      unawaited(_commitRename());
    }
  }

  void _cancelRename() {
    if (_renaming != null) {
      setState(() => _renaming = null);
    }
  }

  Future<void> _commitRename() async {
    final rowId = _renaming;
    final rename = widget.onRenameRow;
    if (rowId == null || rename == null) {
      return;
    }
    final title = _renameText.text.trim();
    final card = _source.cards.firstWhereOrNull((card) => card.rowId == rowId);
    setState(() => _renaming = null);
    if (card == null || title == _titleOf(card).trim()) {
      return;
    }
    final pending = _Rename(title);
    setState(() => _renamed[rowId] = pending);
    final done = await rename(rowId, _source.titleColumn, title);
    if (!mounted) {
      return;
    }
    setState(() {
      if (!done) {
        if (identical(_renamed[rowId], pending)) {
          _renamed.remove(rowId);
        }
        return;
      }
      pending.mark.settle(_source.revision);
      _prune();
    });
  }

  Future<void> _delete(TableRowCard card) async {
    final delete = widget.onDeleteRow;
    if (delete == null) {
      return;
    }
    final mark = _Optimistic();
    setState(() {
      _removed[card.rowId] = mark;
      _refine();
    });
    final done = await delete(card.rowId);
    if (!mounted) {
      return;
    }
    setState(() {
      if (!done) {
        if (identical(_removed[card.rowId], mark)) {
          _removed.remove(card.rowId);
        }
      } else {
        mark.settle(_source.revision);
        _prune();
      }
      _refine();
    });
  }
}

enum _RowAction { open, rename, duplicate, copyTitle, delete }

/// A change the list shows before the table has caught up with it.
class _Optimistic {
  int? _settledAt;

  void settle(int revision) => _settledAt = revision;

  /// Whether the table has caught up: it shows the change, or it has been
  /// read twice since the write finished — the first read may have been on
  /// its way before the write landed — and so never will.
  bool isDone(int revision, {required bool matched}) {
    final settledAt = _settledAt;
    if (settledAt == null) {
      return false;
    }
    return matched || revision >= settledAt + 2;
  }
}

class _Rename {
  _Rename(this.title);

  final String title;
  final _Optimistic mark = _Optimistic();
}

class _PendingRow {
  _PendingRow({required this.id, required this.title, required this.group});

  final int id;
  final String title;
  final String group;
  String? rowId;
  final _Optimistic mark = _Optimistic();
}

/// The line a new page is being named on.
class _ListDraft {
  _ListDraft(this.group, {required this.atTop});

  final String group;
  final bool atTop;
  final TextEditingController text = TextEditingController();
  final FocusNode focus = FocusNode(debugLabel: 'List draft');
  bool closed = false;

  void dispose() {
    text.dispose();
    focus.dispose();
  }
}

sealed class _Line {
  const _Line();

  Key get key;
}

final class _HeadingLine extends _Line {
  const _HeadingLine(this.group, {required this.collapsed});

  final TableRowGroup group;
  final bool collapsed;

  @override
  Key get key => ValueKey('list-heading:${group.label}');
}

final class _RowLine extends _Line {
  const _RowLine(this.card);

  final TableRowCard card;

  @override
  Key get key => ValueKey('list-row:${card.rowId}');
}

final class _PendingLine extends _Line {
  const _PendingLine(this.row);

  final _PendingRow row;

  @override
  Key get key => ValueKey('list-pending:${row.id}');
}

final class _DraftLine extends _Line {
  const _DraftLine();

  @override
  Key get key => const ValueKey('list-draft');
}

final class _AddLine extends _Line {
  const _AddLine(this.group);

  final String group;

  @override
  Key get key => ValueKey('list-add:$group');
}

final class _GapLine extends _Line {
  const _GapLine(this.group);

  final String group;

  @override
  Key get key => ValueKey('list-gap:$group');
}

TextStyle _titleStyle(
  BuildContext context,
  TableViewPalette palette, {
  bool quiet = false,
}) =>
    WorkspaceTypography.style(
      context,
      WorkspaceTextRole.body,
      color: quiet ? palette.textMuted : palette.textPrimary,
    ).copyWith(
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation.weight(520)],
      height: 1.35,
    );

/// One page on the list.
class _ListRow extends StatefulWidget {
  const _ListRow({
    super.key,
    required this.card,
    required this.title,
    required this.palette,
    required this.properties,
    required this.chipFor,
    required this.showIcon,
    required this.quiet,
    this.editor,
    this.onOpen,
    this.onMenu,
    this.onRename,
  });

  final TableRowCard card;
  final String title;
  final TableViewPalette palette;
  final List<TableProperty> properties;
  final Widget Function(TableProperty property) chipFor;
  final bool showIcon;
  final bool quiet;

  /// Stands in for the title while the page is being renamed.
  final Widget? editor;

  final VoidCallback? onOpen;
  final Future<void> Function(BuildContext context, Offset position)? onMenu;
  final VoidCallback? onRename;

  @override
  State<_ListRow> createState() => _ListRowState();
}

class _ListRowState extends State<_ListRow> {
  final FocusNode _focusNode = FocusNode(debugLabel: 'List row');
  final GlobalKey _menuAnchor = GlobalKey();
  bool _hovered = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  void _setHovered(bool value) {
    if (_hovered != value) {
      setState(() => _hovered = value);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final editing = widget.editor != null;
    final focused = _focusNode.hasFocus;
    final focus = WorkspacePalette.of(context).focus;

    return Opacity(
      opacity: widget.quiet ? 0.4 : 1,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: !editing,
        onFocusChange: (_) => setState(() {}),
        onKeyEvent: _handleKeyEvent,
        child: PreviewToolbarRegion(
          child: MouseRegion(
            cursor: widget.onOpen == null || editing
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            onEnter: (_) => _setHovered(true),
            onExit: (_) => _setHovered(false),
            child: Builder(
              builder: (context) => GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: editing ? null : widget.onOpen,
                onSecondaryTapUp: widget.onMenu == null || editing
                    ? null
                    : (details) => unawaited(
                          widget.onMenu!(context, details.globalPosition),
                        ),
                child: Semantics(
                  button: widget.onOpen != null && !editing,
                  child: AnimatedContainer(
                    duration:
                        WorkspaceTokens.motion(context, TableViewMetrics.hover),
                    curve: TableViewMetrics.enterCurve,
                    constraints: const BoxConstraints(
                      minHeight: _ListMetrics.lineHeight,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: _ListMetrics.inset,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: _hovered || editing
                          ? palette.hover
                          : palette.hoverAtRest,
                      borderRadius:
                          BorderRadius.circular(_ListMetrics.radius),
                      // Always drawn, so focusing a row never moves it.
                      border: Border.all(
                        width: _ListMetrics.border,
                        color: focused ? focus : focus.withValues(alpha: 0),
                      ),
                    ),
                    child: LayoutBuilder(
                      builder: (context, constraints) =>
                          _buildContent(constraints.maxWidth, focused),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(double width, bool focused) {
    final palette = widget.palette;
    final leading =
        widget.showIcon ? _ListMetrics.iconSlot + _ListMetrics.gap : 0.0;
    final more = widget.onMenu == null
        ? 0.0
        : _ListMetrics.buttonSize + _ListMetrics.buttonGap;
    // The name always keeps a fair share; the properties have what is left
    // and show whole ones only.
    final titleRoom =
        math.min(_ListMetrics.titleMax, width * _ListMetrics.titleShare);
    final budget = math.max(
      0.0,
      width - leading - more - titleRoom - _ListMetrics.stripGap,
    );
    final strip = widget.properties.isNotEmpty && budget >= 24;

    return Row(
      children: [
        if (widget.showIcon) ...[
          _ListPageIcon(icon: widget.card.icon, palette: palette),
          const SizedBox(width: _ListMetrics.gap),
        ],
        Expanded(
          child: widget.editor ??
              Text(
                widget.title.trim().isEmpty
                    ? LocaleKeys.listView_untitled.tr()
                    : widget.title,
                key: const ValueKey('list-row-title'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: _titleStyle(
                  context,
                  palette,
                  quiet: widget.title.trim().isEmpty,
                ),
              ),
        ),
        if (strip) ...[
          const SizedBox(width: _ListMetrics.stripGap),
          ConstrainedBox(
            constraints: BoxConstraints(maxWidth: budget),
            child: _ListPropertyStrip(
              key: const ValueKey('list-row-properties'),
              gap: _ListMetrics.stripGap,
              maxItemWidth: _ListMetrics.chipMax,
              children: [
                for (final property in widget.properties)
                  KeyedSubtree(
                    key: ValueKey(property.fieldId),
                    child: widget.chipFor(property),
                  ),
              ],
            ),
          ),
        ],
        if (widget.onMenu != null) ...[
          const SizedBox(width: _ListMetrics.buttonGap),
          PreviewToolbar(
            keepVisible: focused,
            child: Builder(
              key: _menuAnchor,
              builder: (context) => _ListIconButton(
                key: const ValueKey('list-row-more'),
                palette: palette,
                icon: Icons.more_horiz_rounded,
                tooltip: LocaleKeys.listView_more.tr(),
                onTap: _openMenu,
              ),
            ),
          ),
        ],
      ],
    );
  }

  void _openMenu() {
    final onMenu = widget.onMenu;
    final context = _menuAnchor.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (onMenu == null || context == null || box == null || !box.hasSize) {
      return;
    }
    unawaited(
      onMenu(
        context,
        box.localToGlobal(Offset(box.size.width, box.size.height + 4)),
      ),
    );
  }

  KeyEventResult _handleKeyEvent(FocusNode node, KeyEvent event) {
    if (!node.hasPrimaryFocus || event is! KeyDownEvent) {
      return KeyEventResult.ignored;
    }
    final key = event.logicalKey;
    if ((key == LogicalKeyboardKey.enter || key == LogicalKeyboardKey.space) &&
        widget.onOpen != null) {
      widget.onOpen!();
      return KeyEventResult.handled;
    }
    if (key == LogicalKeyboardKey.f2 && widget.onRename != null) {
      widget.onRename!();
      return KeyEventResult.handled;
    }
    if (widget.onMenu != null &&
        (key == LogicalKeyboardKey.contextMenu ||
            (key == LogicalKeyboardKey.f10 &&
                HardwareKeyboard.instance.isShiftPressed))) {
      _openMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }
}

/// The page's own icon, or a quiet page when it has none.
class _ListPageIcon extends StatelessWidget {
  const _ListPageIcon({required this.icon, required this.palette});

  final String? icon;
  final TableViewPalette palette;

  @override
  Widget build(BuildContext context) {
    final data = EmojiIconData.fromStorageString(icon);
    return SizedBox.square(
      dimension: _ListMetrics.iconSlot,
      child: Center(
        child: data.isNotEmpty
            ? RawEmojiIconWidget(emoji: data, emojiSize: 16)
            : WorkspaceGlyph.named(
                'file-text',
                size: 17,
                color: palette.textMuted,
              ),
      ),
    );
  }
}

class _ListIconButton extends StatelessWidget {
  const _ListIconButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  final TableViewPalette palette;
  final IconData icon;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: _ListMetrics.buttonSize,
        child: IconButton(
          tooltip: tooltip,
          onPressed: onTap,
          style: IconButton.styleFrom(
            padding: EdgeInsets.zero,
            minimumSize: const Size.square(_ListMetrics.buttonSize),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: palette.textSecondary,
            backgroundColor: palette.hoverAtRest,
            hoverColor: palette.hover,
            focusColor: palette.hover,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(_ListMetrics.radius),
            ),
          ),
          icon: WorkspaceGlyph(icon, size: 16, color: palette.textSecondary),
        ),
      );
}

/// The heading of a run of pages that share a value, folded or not.
class _ListGroupHeading extends StatelessWidget {
  const _ListGroupHeading({
    required this.palette,
    required this.label,
    required this.count,
    required this.collapsed,
    required this.onToggle,
    required this.addTooltip,
    this.onAdd,
  });

  final TableViewPalette palette;
  final Widget label;
  final int count;
  final bool collapsed;
  final VoidCallback onToggle;
  final String addTooltip;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final motion = WorkspaceTokens.motion(context, TableViewMetrics.hover);
    return PreviewToolbarRegion(
      child: Padding(
        padding: const EdgeInsets.only(top: TableViewMetrics.space2, bottom: 2),
        child: Row(
          children: [
            Flexible(
              child: Semantics(
                expanded: !collapsed,
                child: InkWell(
                  onTap: onToggle,
                  borderRadius: BorderRadius.circular(_ListMetrics.radius),
                  hoverColor: palette.hover,
                  focusColor: palette.hover,
                  highlightColor: palette.hover,
                  splashFactory: NoSplash.splashFactory,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 4,
                      vertical: 5,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedRotation(
                          turns: collapsed ? 0 : 0.25,
                          duration: motion,
                          curve: TableViewMetrics.enterCurve,
                          child: WorkspaceGlyph(
                            Icons.chevron_right_rounded,
                            size: 16,
                            color: palette.textMuted,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Flexible(child: label),
                        const SizedBox(width: 8),
                        Text(
                          '$count',
                          style: WorkspaceTypography.style(
                            context,
                            WorkspaceTextRole.metadata,
                            color: palette.textMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (onAdd != null) ...[
              const SizedBox(width: 4),
              PreviewToolbar(
                child: _ListIconButton(
                  palette: palette,
                  icon: Icons.add_rounded,
                  tooltip: addTooltip,
                  onTap: onAdd!,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// "New page", at the foot of the list or of a group.
class _ListAddLine extends StatelessWidget {
  const _ListAddLine({
    super.key,
    required this.palette,
    required this.label,
    required this.onTap,
  });

  final TableViewPalette palette;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(_ListMetrics.radius),
        hoverColor: palette.hover,
        focusColor: palette.hover,
        highlightColor: palette.hover,
        splashFactory: NoSplash.splashFactory,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: _ListMetrics.lineHeight),
          padding: const EdgeInsets.symmetric(
            horizontal: _ListMetrics.inset + _ListMetrics.border,
            vertical: 3 + _ListMetrics.border,
          ),
          child: Row(
            children: [
              SizedBox.square(
                dimension: _ListMetrics.iconSlot,
                child: Center(
                  child: WorkspaceGlyph(
                    Icons.add_rounded,
                    size: 16,
                    color: palette.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: _ListMetrics.gap),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(context, palette, quiet: true).copyWith(
                    fontWeight: FontWeight.w400,
                    fontVariations: const [FontVariation.weight(450)],
                  ),
                ),
              ),
            ],
          ),
        ),
      );
}

/// The line a new page is named on. Enter adds it and leaves the line open
/// for the next one; Escape lets it go.
class _ListDraftLine extends StatelessWidget {
  const _ListDraftLine({
    required this.palette,
    required this.controller,
    required this.focusNode,
    required this.showIcon,
    required this.hint,
    required this.onSubmit,
    required this.onCancel,
  });

  final TableViewPalette palette;
  final TextEditingController controller;
  final FocusNode focusNode;
  final bool showIcon;
  final String hint;
  final VoidCallback onSubmit;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: _ListMetrics.lineHeight),
        padding: const EdgeInsets.symmetric(
          horizontal: _ListMetrics.inset + _ListMetrics.border,
          vertical: 3 + _ListMetrics.border,
        ),
        decoration: BoxDecoration(
          color: palette.hover,
          borderRadius: BorderRadius.circular(_ListMetrics.radius),
        ),
        child: Row(
          children: [
            if (showIcon) ...[
              SizedBox.square(
                dimension: _ListMetrics.iconSlot,
                child: Center(
                  child: WorkspaceGlyph.named(
                    'file-text',
                    size: 17,
                    color: palette.textMuted,
                  ),
                ),
              ),
              const SizedBox(width: _ListMetrics.gap),
            ],
            Expanded(
              child: CallbackShortcuts(
                bindings: {
                  const SingleActivator(LogicalKeyboardKey.escape): onCancel,
                },
                child: TextField(
                  key: const ValueKey('list-draft-field'),
                  controller: controller,
                  focusNode: focusNode,
                  autofocus: true,
                  textInputAction: TextInputAction.done,
                  style: _titleStyle(context, palette),
                  cursorColor: palette.accent,
                  decoration: InputDecoration.collapsed(
                    hintText: hint,
                    hintStyle: _titleStyle(context, palette, quiet: true)
                        .copyWith(
                      fontWeight: FontWeight.w400,
                      fontVariations: const [FontVariation.weight(450)],
                    ),
                  ),
                  // Enter keeps the field focused, ready for the next page.
                  onEditingComplete: () {},
                  onSubmitted: (_) => onSubmit(),
                ),
              ),
            ),
          ],
        ),
      );
}

/// A page that has been typed but that the table has not shown yet.
class _ListPendingLine extends StatelessWidget {
  const _ListPendingLine({
    required this.palette,
    required this.title,
    required this.showIcon,
  });

  final TableViewPalette palette;
  final String title;
  final bool showIcon;

  @override
  Widget build(BuildContext context) => Opacity(
        opacity: 0.6,
        child: Container(
          constraints:
              const BoxConstraints(minHeight: _ListMetrics.lineHeight),
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(
            horizontal: _ListMetrics.inset + _ListMetrics.border,
            vertical: 3 + _ListMetrics.border,
          ),
          child: Row(
            children: [
              if (showIcon) ...[
                SizedBox.square(
                  dimension: _ListMetrics.iconSlot,
                  child: Center(
                    child: WorkspaceGlyph.named(
                      'file-text',
                      size: 17,
                      color: palette.textMuted,
                    ),
                  ),
                ),
                const SizedBox(width: _ListMetrics.gap),
              ],
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: _titleStyle(context, palette),
                ),
              ),
            ],
          ),
        ),
      );
}

/// What each line shows, changed in place while the menu stays open.
class _ListPropertiesPanel extends StatefulWidget {
  const _ListPropertiesPanel({
    required this.fields,
    required this.spec,
    required this.onChanged,
  });

  final List<FieldPB> fields;
  final ListSpec spec;
  final ValueChanged<ListSpec> onChanged;

  @override
  State<_ListPropertiesPanel> createState() => _ListPropertiesPanelState();
}

class _ListPropertiesPanelState extends State<_ListPropertiesPanel> {
  late ListSpec _spec = widget.spec;

  void _change(ListSpec next) {
    setState(() => _spec = next);
    widget.onChanged(next);
  }

  @override
  Widget build(BuildContext context) {
    final fields = widget.fields;
    if (fields.isEmpty) {
      return AppMenuRow(
        label: LocaleKeys.listView_noProperties.tr(),
        enabled: false,
      );
    }
    final style = AppMenuStyle.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final field in fields)
          _PanelRow(
            key: ValueKey('list-property:${field.id}'),
            label: field.name.trim().isEmpty ? '—' : field.name,
            iconWidget: WorkspaceGlyph.svg(field.fieldType.svgData),
            labelColor: _spec.isShown(field.id) ? null : style.textMuted,
            trailing: WorkspaceGlyph(
              _spec.isShown(field.id)
                  ? Icons.visibility_rounded
                  : Icons.visibility_off_rounded,
              color: _spec.isShown(field.id) ? null : style.iconMuted,
            ),
            onTap: () => _change(_spec.toggleProperty(field.id)),
          ),
        const AppMenuSeparatorLine(),
        _PanelRow(
          label: LocaleKeys.listView_showAll.tr(),
          icon: Icons.visibility_rounded,
          onTap: () => _change(
            _spec.copyWith(hiddenColumns: const [], propertyColumns: const []),
          ),
        ),
        _PanelRow(
          label: LocaleKeys.listView_hideAll.tr(),
          icon: Icons.visibility_off_rounded,
          onTap: () => _change(
            _spec.copyWith(
              hiddenColumns: [for (final field in fields) field.id],
              propertyColumns: const [],
            ),
          ),
        ),
      ],
    );
  }
}

/// A menu row the keyboard can reach and press, for a panel the menu itself
/// does not drive.
class _PanelRow extends StatefulWidget {
  const _PanelRow({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.iconWidget,
    this.trailing,
    this.labelColor,
  });

  final String label;
  final VoidCallback onTap;
  final IconData? icon;
  final Widget? iconWidget;
  final Widget? trailing;
  final Color? labelColor;

  @override
  State<_PanelRow> createState() => _PanelRowState();
}

class _PanelRowState extends State<_PanelRow> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) => FocusableActionDetector(
        shortcuts: const {
          SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
          SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
        },
        actions: {
          ActivateIntent: CallbackAction<ActivateIntent>(
            onInvoke: (_) {
              widget.onTap();
              return null;
            },
          ),
        },
        onShowFocusHighlight: (value) => setState(() => _focused = value),
        child: AppMenuRow(
          label: widget.label,
          icon: widget.icon,
          iconWidget: widget.iconWidget,
          trailing: widget.trailing,
          labelColor: widget.labelColor,
          highlighted: _focused,
          tracksHover: true,
          onTap: widget.onTap,
        ),
      );
}

/// The properties on the right of a line: whole ones, left to right, for as
/// many as there is room for. The rest are neither painted, hit nor read out.
class _ListPropertyStrip extends MultiChildRenderObjectWidget {
  const _ListPropertyStrip({
    super.key,
    required this.gap,
    required this.maxItemWidth,
    required super.children,
  });

  final double gap;
  final double maxItemWidth;

  @override
  _RenderListPropertyStrip createRenderObject(BuildContext context) =>
      _RenderListPropertyStrip(gap: gap, maxItemWidth: maxItemWidth);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderListPropertyStrip renderObject,
  ) {
    renderObject
      ..gap = gap
      ..maxItemWidth = maxItemWidth;
  }
}

class _StripParentData extends ContainerBoxParentData<RenderBox> {
  bool shown = false;
}

class _RenderListPropertyStrip extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _StripParentData>,
        RenderBoxContainerDefaultsMixin<RenderBox, _StripParentData> {
  _RenderListPropertyStrip({
    required double gap,
    required double maxItemWidth,
  })  : _gap = gap,
        _maxItemWidth = maxItemWidth;

  double _gap;
  double get gap => _gap;
  set gap(double value) {
    if (value == _gap) {
      return;
    }
    _gap = value;
    markNeedsLayout();
  }

  double _maxItemWidth;
  double get maxItemWidth => _maxItemWidth;
  set maxItemWidth(double value) {
    if (value == _maxItemWidth) {
      return;
    }
    _maxItemWidth = value;
    markNeedsLayout();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _StripParentData) {
      child.parentData = _StripParentData();
    }
  }

  BoxConstraints _itemConstraints(BoxConstraints constraints) =>
      BoxConstraints(
        maxWidth: math.min(_maxItemWidth, constraints.maxWidth),
        maxHeight: constraints.maxHeight,
      );

  Size _sizeFor(BoxConstraints constraints, List<Size> sizes, int fit) {
    var width = 0.0;
    var height = 0.0;
    for (var i = 0; i < fit; i++) {
      width += sizes[i].width + (i == 0 ? 0 : _gap);
      height = math.max(height, sizes[i].height);
    }
    return constraints.constrain(Size(width, height));
  }

  int _fit(BoxConstraints constraints, List<Size> sizes) => listStripFit(
        [for (final size in sizes) size.width],
        constraints.maxWidth,
        gap: _gap,
      );

  @override
  Size computeDryLayout(BoxConstraints constraints) {
    final item = _itemConstraints(constraints);
    final sizes = <Size>[];
    var child = firstChild;
    while (child != null) {
      sizes.add(child.getDryLayout(item));
      child = childAfter(child);
    }
    return _sizeFor(constraints, sizes, _fit(constraints, sizes));
  }

  @override
  void performLayout() {
    final item = _itemConstraints(constraints);
    final sizes = <Size>[];
    var child = firstChild;
    while (child != null) {
      child.layout(item, parentUsesSize: true);
      sizes.add(child.size);
      child = childAfter(child);
    }
    final fit = _fit(constraints, sizes);
    size = _sizeFor(constraints, sizes, fit);

    var x = 0.0;
    var index = 0;
    child = firstChild;
    while (child != null) {
      final data = child.parentData! as _StripParentData;
      data.shown = index < fit;
      if (data.shown) {
        data.offset = Offset(x, (size.height - child.size.height) / 2);
        x += child.size.width + _gap;
      } else {
        data.offset = Offset.zero;
      }
      index++;
      child = data.nextSibling;
    }
  }

  @override
  double computeMinIntrinsicWidth(double height) => 0;

  @override
  double computeMaxIntrinsicWidth(double height) {
    var width = 0.0;
    var count = 0;
    var child = firstChild;
    while (child != null) {
      width += math.min(_maxItemWidth, child.getMaxIntrinsicWidth(height));
      count++;
      child = childAfter(child);
    }
    return width + _gap * math.max(0, count - 1);
  }

  @override
  double computeMinIntrinsicHeight(double width) =>
      _tallest((child) => child.getMinIntrinsicHeight(_maxItemWidth));

  @override
  double computeMaxIntrinsicHeight(double width) =>
      _tallest((child) => child.getMaxIntrinsicHeight(_maxItemWidth));

  double _tallest(double Function(RenderBox child) measure) {
    var height = 0.0;
    var child = firstChild;
    while (child != null) {
      height = math.max(height, measure(child));
      child = childAfter(child);
    }
    return height;
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _StripParentData;
      if (data.shown) {
        context.paintChild(child, data.offset + offset);
      }
      child = data.nextSibling;
    }
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    var child = lastChild;
    while (child != null) {
      final data = child.parentData! as _StripParentData;
      if (data.shown) {
        final current = child;
        final hit = result.addWithPaintOffset(
          offset: data.offset,
          position: position,
          hitTest: (result, transformed) =>
              current.hitTest(result, position: transformed),
        );
        if (hit) {
          return true;
        }
      }
      child = data.previousSibling;
    }
    return false;
  }

  @override
  void visitChildrenForSemantics(RenderObjectVisitor visitor) {
    var child = firstChild;
    while (child != null) {
      final data = child.parentData! as _StripParentData;
      if (data.shown) {
        visitor(child);
      }
      child = data.nextSibling;
    }
  }
}
