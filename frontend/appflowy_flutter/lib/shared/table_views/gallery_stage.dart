import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A table hung on a wall.
///
/// Not a file browser with bigger icons: every row is a piece of work, shown
/// at the size it deserves, with the facts that matter kept under it.
class GalleryStage extends StatefulWidget {
  const GalleryStage({
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
  final GallerySpec spec;
  final ValueChanged<GallerySpec> onSpecChanged;
  final String? title;

  final ValueChanged<String>? onOpenRow;
  final Future<String?> Function()? onAddRow;

  final EdgeInsets padding;

  @override
  State<GalleryStage> createState() => GalleryStageState();
}

class GalleryStageState extends State<GalleryStage> {
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
  void didUpdateWidget(GalleryStage oldWidget) {
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
    _visible = applyTableQuery(_source.cards, _query);
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
            : LocaleKeys.gallery_name.tr(),
        subtitle: LocaleKeys.tableViews_rowCount
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
            icon: Icons.photo_size_select_large_rounded,
            tooltip: LocaleKeys.gallery_cardSize.tr(),
            onTap: _cycleScale,
          ),
        ],
      );

  Widget _buildBody(TableViewPalette palette) {
    if (_source.isLoading && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.grid_view_rounded,
        message: LocaleKeys.tableViews_loading.tr(),
      );
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty && _source.cards.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.grid_view_rounded,
        message: LocaleKeys.tableViews_couldNotRead.tr(),
        detail: error,
        actionLabel: LocaleKeys.tableViews_tryAgain.tr(),
        onAction: reload,
      );
    }
    if (_visible.isEmpty) {
      return TableViewEmpty(
        palette: palette,
        icon: Icons.grid_view_rounded,
        message: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatch.tr()
            : LocaleKeys.gallery_empty.tr(),
        detail: _query.isFiltering
            ? LocaleKeys.tableViews_noneMatchDetail.tr()
            : LocaleKeys.gallery_emptyDetail.tr(),
        actionLabel: _query.isFiltering
            ? LocaleKeys.tableViews_clearFilter.tr()
            : LocaleKeys.tableViews_addRow.tr(),
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

    return LayoutBuilder(
      builder: (context, constraints) {
        final layout = galleryLayoutFor(
          available: constraints.maxWidth,
          target: widget.spec.scale.target,
        );
        return Scrollbar(
          controller: _scroll,
          child: ListView.builder(
            controller: _scroll,
            padding: const EdgeInsets.only(bottom: TableViewMetrics.space6),
            itemCount: groups.length,
            itemBuilder: (context, at) =>
                _buildGroup(palette, groups[at], layout),
          ),
        );
      },
    );
  }

  Widget _buildGroup(
    TableViewPalette palette,
    TableRowGroup group,
    GalleryLayout layout,
  ) {
    return Column(
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
        Wrap(
          spacing: 18,
          runSpacing: 18,
          children: [
            for (final card in group.rows)
              SizedBox(
                width: layout.cardWidth,
                height: layout.cardHeight,
                child: _GalleryCard(
                  key: ValueKey(card.rowId),
                  card: card,
                  palette: palette,
                  face: widget.spec.face,
                  coverHeight: layout.coverHeight,
                  showPlaceholder: widget.spec.showCoverPlaceholder,
                  quiet: _query.isSearching && !_matches.contains(card.rowId),
                  onOpen: widget.onOpenRow == null
                      ? null
                      : () => widget.onOpenRow!(card.rowId),
                  onContextMenu: (position) => _showRowMenu(card, position),
                ),
              ),
          ],
        ),
        const SizedBox(height: TableViewMetrics.space4),
      ],
    );
  }

  void _cycleScale() {
    final values = GalleryCardScale.values;
    final next =
        values[(values.indexOf(widget.spec.scale) + 1) % values.length];
    widget.onSpecChanged(widget.spec.copyWith(scale: next));
  }

  void _addRow() {
    final add = widget.onAddRow;
    if (add == null) {
      return;
    }
    unawaited(add());
  }

  List<AppMenuEntry> _options() => [
        AppMenuHeader(LocaleKeys.gallery_cardSize.tr()),
        for (final scale in GalleryCardScale.values)
          AppMenuItem(
            label: _scaleLabel(scale),
            icon: Icons.photo_size_select_large_rounded,
            selected: widget.spec.scale == scale,
            onSelected: () =>
                widget.onSpecChanged(widget.spec.copyWith(scale: scale)),
          ),
        const AppMenuSeparator(),
        AppMenuHeader(LocaleKeys.gallery_preview.tr()),
        for (final face in GalleryCardFace.values)
          AppMenuItem(
            label: _faceLabel(face),
            icon: _faceIcon(face),
            selected: widget.spec.face == face,
            onSelected: () =>
                widget.onSpecChanged(widget.spec.copyWith(face: face)),
          ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.tableViews_reload.tr(),
          icon: Icons.refresh_rounded,
          onSelected: reload,
        ),
      ];

  static String _scaleLabel(GalleryCardScale scale) => switch (scale) {
        GalleryCardScale.small => LocaleKeys.gallery_sizeSmall.tr(),
        GalleryCardScale.medium => LocaleKeys.gallery_sizeMedium.tr(),
        GalleryCardScale.large => LocaleKeys.gallery_sizeLarge.tr(),
      };

  static String _faceLabel(GalleryCardFace face) => switch (face) {
        GalleryCardFace.cover => LocaleKeys.gallery_faceCover.tr(),
        GalleryCardFace.content => LocaleKeys.gallery_faceContent.tr(),
        GalleryCardFace.none => LocaleKeys.gallery_faceNone.tr(),
        GalleryCardFace.portrait => LocaleKeys.gallery_facePortrait.tr(),
      };

  static IconData _faceIcon(GalleryCardFace face) => switch (face) {
        GalleryCardFace.cover => Icons.image_rounded,
        GalleryCardFace.content => Icons.article_rounded,
        GalleryCardFace.none => Icons.notes_rounded,
        GalleryCardFace.portrait => Icons.crop_portrait_rounded,
      };

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

/// One row, hung as a card.
class _GalleryCard extends StatefulWidget {
  const _GalleryCard({
    super.key,
    required this.card,
    required this.palette,
    required this.face,
    required this.coverHeight,
    required this.showPlaceholder,
    required this.quiet,
    this.onOpen,
    this.onContextMenu,
  });

  final TableRowCard card;
  final TableViewPalette palette;
  final GalleryCardFace face;
  final double coverHeight;
  final bool showPlaceholder;
  final bool quiet;
  final VoidCallback? onOpen;
  final void Function(Offset globalPosition)? onContextMenu;

  @override
  State<_GalleryCard> createState() => _GalleryCardState();
}

class _GalleryCardState extends State<_GalleryCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final card = widget.card;
    final lift = _hovered ? TableViewMetrics.hoverLift : 0.0;

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
              child: widget.face == GalleryCardFace.portrait
                  ? _buildPortrait(palette, card)
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _buildCover(palette, card),
                        Expanded(child: _buildBody(palette, card)),
                      ],
                    ),
            ),
          ),
        ),
      ),
    );
  }

  /// The cover fills the card, with the writing laid over its foot.
  Widget _buildPortrait(TableViewPalette palette, TableRowCard card) {
    final cover = card.cover;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null)
          AnimatedScale(
            duration: TableViewMetrics.change,
            curve: TableViewMetrics.settleCurve,
            scale: _hovered ? 1.04 : 1,
            child: TableCoverView(cover: cover, palette: palette),
          ),
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0x00000000), Color(0xB3000000)],
                stops: [0.45, 1],
              ),
            ),
          ),
        ),
        Positioned(
          left: TableViewMetrics.space4,
          right: TableViewMetrics.space4,
          bottom: TableViewMetrics.space4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (card.icon != null)
                Text(
                  card.icon!,
                  style: const TextStyle(fontSize: 22, height: 1.3),
                ),
              Text(
                card.title.trim().isEmpty ? '—' : card.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 16,
                  height: 1.3,
                  letterSpacing: -0.2,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCover(TableViewPalette palette, TableRowCard card) {
    if (widget.face == GalleryCardFace.none) {
      return const SizedBox(height: 4);
    }
    final height = widget.coverHeight;
    if (widget.face == GalleryCardFace.content) {
      return _PagePreview(
        documentId: card.documentId,
        palette: palette,
        height: height,
      );
    }
    final cover = card.cover;
    if (cover == null && !widget.showPlaceholder) {
      return const SizedBox(height: 4);
    }
    if (cover == null) {
      return SizedBox(height: height);
    }

    return SizedBox(
      height: height,
      child: Stack(
        fit: StackFit.expand,
        children: [
          AnimatedScale(
            duration: TableViewMetrics.change,
            curve: TableViewMetrics.settleCurve,
            scale: _hovered ? 1.04 : 1,
            // The same cover the row's own page shows, so a card and its page
            // are recognisably the same row.
            child: TableCoverView(cover: cover, palette: palette),
          ),
          if (card.icon != null)
            Center(
              child: Text(
                card.icon!,
                style: TextStyle(fontSize: height * 0.23, height: 1),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildBody(TableViewPalette palette, TableRowCard card) {
    final facts = card.filled
        .where((property) => property.kind != TablePropertyKind.image)
        .take(3)
        .toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        TableViewMetrics.space4,
        TableViewMetrics.space4,
        TableViewMetrics.space4,
        TableViewMetrics.space3,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (card.icon != null && widget.face != GalleryCardFace.cover)
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Text(
                    card.icon!,
                    style: const TextStyle(fontSize: 16, height: 1.2),
                  ),
                ),
              Expanded(
                child: Text(
                  card.title.trim().isEmpty ? '—' : card.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.32,
                    letterSpacing: -0.2,
                    fontWeight: FontWeight.w600,
                    color: palette.textPrimary,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: TableViewMetrics.space2),
          Expanded(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Only whole rows are shown. A card that clipped one halfway
                // reads as broken rather than as abbreviated.
                final room = (constraints.maxHeight / _factHeight).floor();
                if (room < 1) {
                  return const SizedBox.shrink();
                }
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    for (final property in facts.take(room))
                      SizedBox(
                        height: _factHeight,
                        child: Align(
                          alignment: Alignment.centerLeft,
                          child: TablePropertyView(
                            property: property,
                            palette: palette,
                            showLabel: false,
                            compact: true,
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
          if (card.lastModified != null)
            Text(
              _agoOf(card.lastModified!),
              style: TextStyle(fontSize: 11, color: palette.textMuted),
            ),
        ],
      ),
    );
  }

  /// The room one property takes on a card, its own gap included.
  static const double _factHeight = 29;

  static String _agoOf(DateTime when) {
    final gap = DateTime.now().difference(when);
    if (gap.inHours < 1) {
      return gap.inMinutes < 1 ? 'just now' : '${gap.inMinutes}m ago';
    }
    if (gap.inDays < 1) {
      return '${gap.inHours}h ago';
    }
    if (gap.inDays < 30) {
      return '${gap.inDays}d ago';
    }
    return '${when.year}-${when.month.toString().padLeft(2, '0')}-'
        '${when.day.toString().padLeft(2, '0')}';
  }
}

/// The first few lines of a row's own page, standing in for a cover.
///
/// Read once per row and remembered, because a wall of cards would otherwise
/// ask the backend for the same page every time it scrolled past.
class _PagePreview extends StatefulWidget {
  const _PagePreview({
    required this.documentId,
    required this.palette,
    required this.height,
  });

  final String documentId;
  final TableViewPalette palette;
  final double height;

  @override
  State<_PagePreview> createState() => _PagePreviewState();
}

class _PagePreviewState extends State<_PagePreview> {
  static final Map<String, String> _read = {};

  String? _text;

  @override
  void initState() {
    super.initState();
    _adopt();
  }

  @override
  void didUpdateWidget(_PagePreview old) {
    super.didUpdateWidget(old);
    if (old.documentId != widget.documentId) {
      _adopt();
    }
  }

  void _adopt() {
    _text = _read[widget.documentId];
    if (_text == null && widget.documentId.isNotEmpty) {
      unawaited(_load());
    }
  }

  Future<void> _load() async {
    final text = await DocumentEventGetDocumentText(
      OpenDocumentPayloadPB(documentId: widget.documentId),
    ).send().fold((data) => data.text, (_) => '');
    _read[widget.documentId] = text;
    if (mounted) {
      setState(() => _text = text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final text = _text?.trim() ?? '';
    return Container(
      height: widget.height,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
      color: palette.sunken.withValues(alpha: 0.6),
      child: text.isEmpty
          ? Align(
              alignment: Alignment.topLeft,
              child: Text(
                LocaleKeys.gallery_pageEmpty.tr(),
                style: TextStyle(fontSize: 12, color: palette.textMuted),
              ),
            )
          : Text(
              text,
              maxLines: 6,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontSize: 11.5,
                height: 1.5,
                color: palette.textSecondary,
              ),
            ),
    );
  }
}
