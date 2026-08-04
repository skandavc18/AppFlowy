import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/feed_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A table read as a column of posts.
///
/// The same rows a grid lists become something to read rather than to scan:
/// one measure wide, newest first, with the writing given room and the facts
/// kept underneath it.
class FeedStage extends StatefulWidget {
  const FeedStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.onOpenRow,
    this.onAddRow,
    this.padding = EdgeInsets.zero,
  });

  final String viewId;
  final FeedSpec spec;
  final ValueChanged<FeedSpec> onSpecChanged;
  final String? title;

  final ValueChanged<String>? onOpenRow;
  final Future<String?> Function()? onAddRow;

  final EdgeInsets padding;

  @override
  State<FeedStage> createState() => FeedStageState();
}

class FeedStageState extends State<FeedStage> {
  late final TableRowSource _source = TableRowSource(viewId: widget.viewId);
  final ScrollController _scroll = ScrollController();
  final GlobalKey<TableViewHeaderState> _header =
      GlobalKey<TableViewHeaderState>();

  TableQuery _query = const TableQuery();
  List<TableRowCard> _visible = const [];
  Set<String> _matches = const {};

  @override
  void initState() {
    super.initState();
    _source
      ..updateSpec(widget.spec.readSpec)
      ..addListener(_onSourceChanged);
    unawaited(_source.load());
  }

  @override
  void didUpdateWidget(FeedStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.spec != widget.spec) {
      _source.updateSpec(widget.spec.readSpec);
      setState(_refine);
    }
  }

  @override
  void dispose() {
    _source.removeListener(_onSourceChanged);
    _source.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Reads the table again — the host calls this when a row changes.
  void reload() => _source.invalidate();

  void _onSourceChanged() {
    if (mounted) {
      setState(_refine);
    }
  }

  void _refine() {
    var cards = applyTableQuery(_source.cards, _query);
    // Without an order of its own a feed reads newest first, which is what
    // makes it a feed rather than a list.
    if (!_query.isSorting) {
      cards = [...cards]..sort((a, b) {
          final left = a.lastModified;
          final right = b.lastModified;
          if (left == null && right == null) {
            return 0;
          }
          if (left == null) {
            return 1;
          }
          if (right == null) {
            return -1;
          }
          return widget.spec.newestFirst
              ? right.compareTo(left)
              : left.compareTo(right);
        });
    }
    _visible = cards;
    _matches = tableMatchesOf(_visible, _query.search);
  }

  void _setQuery(TableQuery query) => setState(() {
        _query = query;
        _refine();
      });

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
            : LocaleKeys.feed_name.tr(),
        subtitle: LocaleKeys.feed_postCount
            .tr(namedArgs: {'count': '${_visible.length}'}),
        columns: _source.fields,
        query: _query,
        onQueryChanged: _setQuery,
        valuesOf: (fieldId) => tableValuesOf(_source.cards, fieldId),
        onAdd: widget.onAddRow == null ? null : _addRow,
        optionsBuilder: _options,
        actions: [
          TableViewButton(
            palette: palette,
            icon: widget.spec.newestFirst
                ? Icons.arrow_downward_rounded
                : Icons.arrow_upward_rounded,
            tooltip: widget.spec.newestFirst
                ? LocaleKeys.feed_newest.tr()
                : LocaleKeys.feed_oldest.tr(),
            onTap: () => widget.onSpecChanged(
              widget.spec.copyWith(newestFirst: !widget.spec.newestFirst),
            ),
          ),
          const SizedBox(width: TableViewMetrics.controlGap),
          TableViewButton(
            palette: palette,
            icon: widget.spec.width == FeedWidth.wide
                ? Icons.unfold_less_rounded
                : Icons.unfold_more_rounded,
            tooltip: LocaleKeys.feed_density.tr(),
            onTap: () => widget.onSpecChanged(
              widget.spec.copyWith(width: widget.spec.width.flipped),
            ),
          ),
        ],
      );

  Widget _buildBody(TableViewPalette palette) {
    if (_source.isLoading && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.article_rounded,
        message: LocaleKeys.tableViews_loading.tr(),
      );
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.article_rounded,
        message: LocaleKeys.tableViews_couldNotRead.tr(),
        detail: error,
        actionLabel: LocaleKeys.tableViews_tryAgain.tr(),
        onAction: reload,
      );
    }
    if (_visible.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.article_rounded,
        message: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatch.tr()
            : LocaleKeys.feed_empty.tr(),
        detail: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatchDetail.tr()
            : LocaleKeys.feed_emptyDetail.tr(),
        actionLabel: _query.isFiltering
            ? LocaleKeys.tableViews_clearFilter.tr()
            : LocaleKeys.feed_addFirst.tr(),
        onAction: _query.isFiltering
            ? () =>
                _setQuery(_query.copyWith(filterColumn: '', filterValue: ''))
            : (widget.onAddRow == null ? null : _addRow),
      );
    }

    final groups = groupTableRows(
      _visible,
      _query.groupColumn,
      ungrouped: LocaleKeys.tableViews_ungrouped.tr(),
    );

    return Scrollbar(
      controller: _scroll,
      child: ListView.builder(
        controller: _scroll,
        padding: const EdgeInsets.only(bottom: TableViewMetrics.space6),
        itemCount: groups.length,
        itemBuilder: (context, at) => _buildGroup(palette, groups[at]),
      ),
    );
  }

  Widget _buildGroup(TableViewPalette palette, TableRowGroup group) {
    return Center(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: widget.spec.width.pixels),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (group.label.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(
                  top: TableViewMetrics.space4,
                  bottom: TableViewMetrics.space1,
                ),
                child: TableGroupHeading(
                  palette: palette,
                  label: group.label,
                  count: group.rows.length,
                ),
              ),
            for (final card in group.rows)
              Padding(
                padding: const EdgeInsets.only(
                  bottom: TableViewMetrics.space4,
                ),
                child: _FeedPost(
                  key: ValueKey(card.rowId),
                  card: card,
                  palette: palette,
                  bodyColumn: widget.spec.bodyColumn,
                  authorColumn: widget.spec.authorColumn,
                  quiet: _query.isSearching && !_matches.contains(card.rowId),
                  onOpen: widget.onOpenRow == null
                      ? null
                      : () => widget.onOpenRow!(card.rowId),
                  onContextMenu: (position) => _showRowMenu(card, position),
                ),
              ),
          ],
        ),
      ),
    );
  }

  void _addRow() {
    final add = widget.onAddRow;
    if (add == null) {
      return;
    }
    unawaited(add());
  }

  List<AppMenuEntry> _options() => [
        AppMenuHeader(LocaleKeys.tableViews_options.tr()),
        AppMenuItem(
          label: LocaleKeys.feed_newest.tr(),
          icon: Icons.arrow_downward_rounded,
          selected: widget.spec.newestFirst,
          onSelected: () =>
              widget.onSpecChanged(widget.spec.copyWith(newestFirst: true)),
        ),
        AppMenuItem(
          label: LocaleKeys.feed_oldest.tr(),
          icon: Icons.arrow_upward_rounded,
          selected: !widget.spec.newestFirst,
          onSelected: () =>
              widget.onSpecChanged(widget.spec.copyWith(newestFirst: false)),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.feed_densityComfortable.tr(),
          icon: Icons.unfold_less_rounded,
          selected: widget.spec.width == FeedWidth.comfortable,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(width: FeedWidth.comfortable),
          ),
        ),
        AppMenuItem(
          label: LocaleKeys.feed_densityWide.tr(),
          icon: Icons.unfold_more_rounded,
          selected: widget.spec.width == FeedWidth.wide,
          onSelected: () =>
              widget.onSpecChanged(widget.spec.copyWith(width: FeedWidth.wide)),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.tableViews_reload.tr(),
          icon: Icons.refresh_rounded,
          onSelected: reload,
        ),
      ];

  Future<void> _showRowMenu(TableRowCard card, Offset position) async {
    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: LocaleKeys.tableViews_openRow.tr(),
          icon: Icons.open_in_new_rounded,
          enabled: widget.onOpenRow != null,
          onSelected: () => widget.onOpenRow?.call(card.rowId),
        ),
        AppMenuItem(
          label: LocaleKeys.tableViews_copyTitle.tr(),
          icon: Icons.copy_rounded,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: card.title))),
        ),
        const AppMenuSeparator(),
        ..._options(),
      ],
    );
  }
}

/// One row, written out as a post.
class _FeedPost extends StatefulWidget {
  const _FeedPost({
    super.key,
    required this.card,
    required this.palette,
    required this.bodyColumn,
    required this.authorColumn,
    required this.quiet,
    this.onOpen,
    this.onContextMenu,
  });

  final TableRowCard card;
  final TableViewPalette palette;
  final String bodyColumn;
  final String authorColumn;
  final bool quiet;
  final VoidCallback? onOpen;
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  State<_FeedPost> createState() => _FeedPostState();
}

class _FeedPostState extends State<_FeedPost> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final card = widget.card;
    final lift = _hovered ? TableViewMetrics.hoverLift : 0.0;
    final body = _bodyOf(card);
    final author = _authorOf(card);
    final rest = card.filled
        .where(
          (property) =>
              property.fieldId != body?.fieldId &&
              property.fieldId != author?.fieldId,
        )
        .toList();

    return Opacity(
      opacity: widget.quiet ? 0.4 : 1,
      child: MouseRegion(
        opaque: false,
        cursor: widget.onOpen == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          onTap: widget.onOpen,
          onSecondaryTapUp: widget.onContextMenu == null
              ? null
              : (details) => widget.onContextMenu!(details.globalPosition),
          child: AnimatedContainer(
            duration: TableViewMetrics.hover,
            curve: TableViewMetrics.enterCurve,
            transform: Matrix4.translationValues(0, -lift, 0),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
              boxShadow: palette.cardShadow(lift: lift),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(TableViewMetrics.cardRadius),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (card.coverUrl != null)
                    SizedBox(
                      height: TableViewMetrics.coverHeight,
                      child: TablePicture(
                        url: card.coverUrl!,
                        palette: palette,
                      ),
                    ),
                  Padding(
                    padding: const EdgeInsets.all(TableViewMetrics.space5),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _buildByline(palette, card, author),
                        const SizedBox(height: TableViewMetrics.space3),
                        Text(
                          card.title.trim().isEmpty ? '—' : card.title,
                          style: TextStyle(
                            fontSize: 19,
                            height: 1.3,
                            letterSpacing: -0.3,
                            fontWeight: FontWeight.w600,
                            color: palette.textPrimary,
                          ),
                        ),
                        if (body != null) ...[
                          const SizedBox(height: TableViewMetrics.space3),
                          Text(
                            body.value,
                            maxLines: 6,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 14.5,
                              height: 1.62,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                        if (rest.isNotEmpty) ...[
                          const SizedBox(height: TableViewMetrics.space4),
                          _buildFacts(palette, rest),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildByline(
    TableViewPalette palette,
    TableRowCard card,
    TableProperty? author,
  ) {
    final name = author == null ? '' : tablePartsOf(author.value).firstOrNull;
    final when = card.lastModified;
    return Row(
      children: [
        if (card.icon != null) ...[
          Text(card.icon!, style: const TextStyle(fontSize: 17, height: 1)),
          const SizedBox(width: 9),
        ] else if (name != null && name.isNotEmpty) ...[
          TableAvatar(name: name, palette: palette, size: 24),
          const SizedBox(width: 9),
        ],
        if (name != null && name.isNotEmpty)
          Text(
            name,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w600,
              color: palette.textSecondary,
            ),
          ),
        if (name != null && name.isNotEmpty && when != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Text(
              '·',
              style: TextStyle(fontSize: 12.5, color: palette.textMuted),
            ),
          ),
        if (when != null)
          Text(
            feedAgoOf(when),
            style: TextStyle(fontSize: 12, color: palette.textMuted),
          ),
        const Spacer(),
        if (card.accent.isNotEmpty)
          TablePill(
            label: card.accent,
            colour: palette.swatchFor(card.accent),
            palette: palette,
            dense: true,
          ),
      ],
    );
  }

  Widget _buildFacts(TableViewPalette palette, List<TableProperty> facts) {
    final wide = facts.where((property) => property.isWide).toList();
    final short = facts.where((property) => !property.isWide).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final property in wide) ...[
          TablePropertyView(property: property, palette: palette, live: true),
          const SizedBox(height: TableViewMetrics.space4),
        ],
        if (short.isNotEmpty)
          Wrap(
            spacing: TableViewMetrics.space6,
            runSpacing: TableViewMetrics.space3,
            children: [
              for (final property in short)
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 220),
                  child: TablePropertyView(
                    property: property,
                    palette: palette,
                    compact: true,
                  ),
                ),
            ],
          ),
      ],
    );
  }

  /// The longest piece of prose the row holds stands in for its body.
  TableProperty? _bodyOf(TableRowCard card) {
    if (widget.bodyColumn.isNotEmpty) {
      return card.propertyOf(widget.bodyColumn);
    }
    TableProperty? longest;
    for (final property in card.filled) {
      if (property.kind != TablePropertyKind.excerpt) {
        continue;
      }
      if (longest == null || property.value.length > longest.value.length) {
        longest = property;
      }
    }
    return longest;
  }

  TableProperty? _authorOf(TableRowCard card) {
    if (widget.authorColumn.isNotEmpty) {
      return card.propertyOf(widget.authorColumn);
    }
    for (final property in card.filled) {
      if (property.kind == TablePropertyKind.person) {
        return property;
      }
    }
    return null;
  }
}

extension _FirstOrNull<E> on List<E> {
  E? get firstOrNull => isEmpty ? null : first;
}
