import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/table_views/row_page_preview.dart';
import 'package:appflowy/shared/table_views/row_page_text.dart';
import 'package:appflowy/shared/table_views/table_property_view.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/table_views/table_row_source.dart';
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

  /// Reads the pages again as well, for when somebody asks outright.
  void _readAgain() {
    RowPageText.forget();
    reload();
  }

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
    final textScale = MediaQuery.textScalerOf(context).scale(15) / 15;
    final captionGrowth = (textScale - 1).clamp(0.0, double.infinity) *
        TableViewMetrics.cardCaptionAllowance;
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
                height: layout.cardHeight + captionGrowth,
                child: TableGalleryCard(
                  key: ValueKey(card.rowId),
                  card: card,
                  palette: palette,
                  face: widget.spec.face,
                  coverHeight: layout.cardHeight * 0.60,
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
          onSelected: _readAgain,
        ),
      ];

  static String _scaleLabel(GalleryCardScale scale) => switch (scale) {
        GalleryCardScale.small => LocaleKeys.gallery_sizeSmall.tr(),
        GalleryCardScale.medium => LocaleKeys.gallery_sizeMedium.tr(),
        GalleryCardScale.large => LocaleKeys.gallery_sizeLarge.tr(),
      };

  static String _faceLabel(GalleryCardFace face) => switch (face) {
        GalleryCardFace.page => LocaleKeys.gallery_facePage.tr(),
        GalleryCardFace.cover => LocaleKeys.gallery_faceCover.tr(),
        GalleryCardFace.content => LocaleKeys.gallery_faceContent.tr(),
        GalleryCardFace.none => LocaleKeys.gallery_faceNone.tr(),
        GalleryCardFace.portrait => LocaleKeys.gallery_facePortrait.tr(),
      };

  static IconData _faceIcon(GalleryCardFace face) => switch (face) {
        GalleryCardFace.page => Icons.sticky_note_2_rounded,
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

/// Presentation of one row, shared by the gallery stage and lightweight hosts.
/// The supplied model owns the facts; the card never changes its read policy.
class TableGalleryCard extends StatefulWidget {
  const TableGalleryCard({
    super.key,
    required this.card,
    required this.palette,
    required this.face,
    required this.coverHeight,
    required this.showPlaceholder,
    required this.quiet,
    this.selected = false,
    this.onOpen,
    this.onContextMenu,
  });

  final TableRowCard card;
  final TableViewPalette palette;
  final GalleryCardFace face;
  final double coverHeight;
  final bool showPlaceholder;
  final bool quiet;
  final bool selected;
  final VoidCallback? onOpen;
  final Future<void> Function(Offset globalPosition)? onContextMenu;

  @override
  State<TableGalleryCard> createState() => _TableGalleryCardState();
}

class _TableGalleryCardState extends State<TableGalleryCard> {
  final _focusNode = FocusNode(debugLabel: 'Table gallery card');
  final _menuAnchor = GlobalKey();

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final card = widget.card;

    return Opacity(
      opacity: widget.quiet ? 0.4 : 1,
      child: Focus(
        focusNode: _focusNode,
        canRequestFocus: widget.onOpen != null,
        onFocusChange: (_) => setState(() {}),
        onKeyEvent: _handleKeyEvent,
        child: PreviewToolbarRegion(
          child: MouseRegion(
            cursor: widget.onOpen == null
                ? MouseCursor.defer
                : SystemMouseCursors.click,
            child: WorkspaceSurface(
              child: Semantics(
                button: widget.onOpen != null,
                selected: widget.selected,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Builder(
                      builder: (context) => GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onOpen,
                        onSecondaryTapUp: widget.onContextMenu == null
                            ? null
                            : (details) => unawaited(
                                  _showMenu(context, details.globalPosition),
                                ),
                        child: switch (widget.face) {
                          GalleryCardFace.portrait =>
                            _buildPortrait(palette, card),
                          GalleryCardFace.page => _buildPage(palette, card),
                          _ => _buildStandard(palette, card),
                        },
                      ),
                    ),
                    if (widget.onContextMenu != null)
                      PositionedDirectional(
                        top: WorkspaceTokens.space2,
                        end: WorkspaceTokens.space2,
                        child: PreviewToolbar(
                          keepVisible: widget.selected || _focusNode.hasFocus,
                          child: Builder(
                            key: _menuAnchor,
                            builder: _buildOverflow,
                          ),
                        ),
                      ),
                    // A nullable Container foreground changes subtree depth.
                    // Paint the focus/selection ring in a permanent sibling
                    // instead, leaving the page renderer and actions mounted.
                    Positioned.fill(
                      child: IgnorePointer(
                        child: DecoratedBox(
                          key: const ValueKey('table-gallery-selection'),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(
                              WorkspaceTokens.cardRadius,
                            ),
                            border: widget.selected || _focusNode.hasFocus
                                ? Border.all(
                                    color: WorkspacePalette.of(context).focus,
                                    width: 1.5,
                                  )
                                : null,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandard(TableViewPalette palette, TableRowCard card) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Font-size multiples miss rounded line metrics and fallback glyphs.
        // Measure the actual caption before assigning the preview its share.
        final captionMinimum =
            _captionMinimumHeight(context, card, constraints.maxWidth);
        final previewRoom = (constraints.maxHeight - captionMinimum)
            .clamp(0.0, double.infinity);
        final height = widget.coverHeight.clamp(0.0, previewRoom).toDouble();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildCover(palette, card, height),
            Expanded(
              child: LayoutBuilder(
                builder: (context, captionConstraints) => SingleChildScrollView(
                  key: const ValueKey('table-gallery-caption-scroll'),
                  primary: false,
                  // Normally there is no scroll extent. A very short host or
                  // extreme text scale must not clip the title or real date.
                  child: SizedBox(
                    height: math.max(
                      captionMinimum,
                      captionConstraints.maxHeight,
                    ),
                    child: _buildBody(palette, card),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  double _captionMinimumHeight(
    BuildContext context,
    TableRowCard card,
    double width,
  ) {
    final bodyWidth = math.max(0.0, width - WorkspaceTokens.space4 * 2);
    final icon = card.icon;
    final hasIcon = icon != null && icon.isNotEmpty;
    final iconSize = hasIcon
        ? _measureCaptionText(
            context,
            icon,
            const TextStyle(fontSize: 16, height: 1.2),
          )
        : Size.zero;
    final titleSize = _measureCaptionText(
      context,
      card.title.trim().isEmpty ? '—' : card.title,
      WorkspaceTypography.style(context, WorkspaceTextRole.cardTitle),
      maxWidth: math.max(0.0, bodyWidth - (hasIcon ? iconSize.width + 8 : 0)),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
    final modified = card.lastModified;
    final dateHeight = modified == null
        ? 0.0
        : _measureCaptionText(
            context,
            _agoOf(modified),
            WorkspaceTypography.style(context, WorkspaceTextRole.metadata),
            maxWidth: bodyWidth,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ).height;
    return (WorkspaceTokens.space3 * 2 +
            math.max(titleSize.height, hasIcon ? iconSize.height + 1 : 0.0) +
            WorkspaceTokens.space2 +
            dateHeight)
        .ceilToDouble();
  }

  Size _measureCaptionText(
    BuildContext context,
    String text,
    TextStyle style, {
    double maxWidth = double.infinity,
    int? maxLines,
    TextOverflow? overflow,
  }) {
    // Match Text's inherited style, accessibility and paragraph settings,
    // including non-linear scaling of the title, icon and metadata separately.
    final defaults = DefaultTextStyle.of(context);
    var effectiveStyle = defaults.style.merge(style);
    if (MediaQuery.boldTextOf(context)) {
      effectiveStyle =
          effectiveStyle.merge(const TextStyle(fontWeight: FontWeight.bold));
    }
    final effectiveOverflow =
        overflow ?? effectiveStyle.overflow ?? defaults.overflow;
    final painter = TextPainter(
      text: TextSpan(text: text, style: effectiveStyle),
      textAlign: defaults.textAlign ?? TextAlign.start,
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      locale: Localizations.maybeLocaleOf(context),
      maxLines: maxLines ?? defaults.maxLines,
      ellipsis: effectiveOverflow == TextOverflow.ellipsis ? '…' : null,
      textWidthBasis: defaults.textWidthBasis,
      textHeightBehavior: defaults.textHeightBehavior ??
          DefaultTextHeightBehavior.maybeOf(context),
    );
    try {
      painter.layout(
        maxWidth:
            defaults.softWrap || effectiveOverflow == TextOverflow.ellipsis
                ? maxWidth
                : double.infinity,
      );
      return painter.size;
    } finally {
      painter.dispose();
    }
  }

  Widget _buildOverflow(BuildContext context) {
    final label = LocaleKeys.workspaceFolderExplorer_more.tr();
    return Shortcuts(
      shortcuts: const {
        SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
        SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
      },
      child: Tooltip(
        message: label,
        excludeFromSemantics: true,
        child: IconButton(
          key: const ValueKey('table-gallery-more'),
          style: WorkspaceChrome.controlStyle(context).copyWith(
            minimumSize: const WidgetStatePropertyAll(Size.square(40)),
            tapTargetSize: MaterialTapTargetSize.padded,
            visualDensity: VisualDensity.standard,
            backgroundColor: WidgetStatePropertyAll(
              WorkspacePalette.of(context).elevatedSurface,
            ),
          ),
          onPressed: _openMenu,
          icon: Semantics(
            label: label,
            child: const Icon(Icons.more_horiz_rounded, size: 18),
          ),
        ),
      ),
    );
  }

  void _openMenu() {
    final context = _menuAnchor.currentContext;
    final box = context?.findRenderObject() as RenderBox?;
    if (context != null && box != null && box.hasSize) {
      unawaited(
        _showMenu(
          context,
          box.localToGlobal(Offset(box.size.width, box.size.height + 5)),
        ),
      );
    }
  }

  Future<void> _showMenu(BuildContext context, Offset position) async {
    final show = widget.onContextMenu;
    if (show == null) return;
    // The stage opens its menu from a context outside this card. Hold the
    // originating region here until that existing menu completes or cancels.
    final release = PreviewToolbarRegion.hold(context);
    try {
      await show(position);
    } finally {
      release();
    }
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
    if (widget.onContextMenu != null &&
        (key == LogicalKeyboardKey.contextMenu ||
            (key == LogicalKeyboardKey.f10 &&
                HardwareKeyboard.instance.isShiftPressed))) {
      _openMenu();
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _buildTitle(
    TableRowCard card, {
    Color? color,
  }) {
    final title = card.title.trim().isEmpty ? '—' : card.title;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (card.icon?.isNotEmpty ?? false)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8, top: 1),
            child: Text(
              card.icon!,
              style: const TextStyle(fontSize: 16, height: 1.2),
            ),
          ),
        Expanded(
          child: Tooltip(
            message: title,
            excludeFromSemantics: true,
            child: Text(
              title,
              key: const ValueKey('table-gallery-title'),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.cardTitle,
                color: color,
              ),
            ),
          ),
        ),
      ],
    );
  }

  /// The row's own page, with its name written underneath.
  Widget _buildPage(TableViewPalette palette, TableRowCard card) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: _PagePreview(
            documentId: card.documentId,
            palette: palette,
            height: null,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: WorkspaceTokens.space4,
            vertical: WorkspaceTokens.space3,
          ),
          child: _buildTitle(card),
        ),
      ],
    );
  }

  /// Only a real cover needs contrast behind its title. A missing cover is
  /// still an ordinary warm surface, not a manufactured dark gradient.
  Widget _buildPortrait(TableViewPalette palette, TableRowCard card) {
    final cover = card.cover;
    return Stack(
      fit: StackFit.expand,
      children: [
        if (cover != null) TableCoverView(cover: cover, palette: palette),
        PositionedDirectional(
          start: 0,
          end: 0,
          bottom: 0,
          child: ColoredBox(
            color: cover == null ? palette.surface : const Color(0xCC000000),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: WorkspaceTokens.space4,
                vertical: WorkspaceTokens.space3,
              ),
              child: _buildTitle(
                card,
                color: cover == null ? null : Colors.white,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCover(
    TableViewPalette palette,
    TableRowCard card,
    double height,
  ) {
    if (widget.face == GalleryCardFace.none) {
      return const SizedBox.shrink();
    }
    if (widget.face == GalleryCardFace.content) {
      return _PagePreview(
        documentId: card.documentId,
        palette: palette,
        height: height,
      );
    }
    final cover = card.cover;
    if (cover == null && !widget.showPlaceholder) {
      return const SizedBox.shrink();
    }
    return SizedBox(
      height: height,
      // Retain the user's actual colour/gradient/asset/picture choice. Hover
      // never zooms, replaces or recreates the cover or the page renderer.
      child:
          cover == null ? null : TableCoverView(cover: cover, palette: palette),
    );
  }

  Widget _buildBody(TableViewPalette palette, TableRowCard card) {
    final facts = card.filled
        .where((property) => property.kind != TablePropertyKind.image)
        .toList();
    final details = [
      for (final property in facts) '${property.name}: ${property.value}',
      if (card.lastModified case final modified?)
        DateFormat.yMMMd().add_jm().format(modified),
    ].join('\n');

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: WorkspaceTokens.space4,
        vertical: WorkspaceTokens.space3,
      ),
      child: Tooltip(
        message: details,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildTitle(card),
            const SizedBox(height: WorkspaceTokens.space2),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final factHeight =
                      (MediaQuery.textScalerOf(context).scale(12) * 1.4 + 8)
                          .clamp(29.0, double.infinity);
                  final room =
                      (constraints.maxHeight / factHeight).floor().clamp(0, 3);
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      for (final property in facts.take(room))
                        SizedBox(
                          height: factHeight,
                          child: ClipRect(
                            child: OverflowBox(
                              alignment: AlignmentDirectional.centerStart,
                              minHeight: 0,
                              maxHeight: double.infinity,
                              child: TablePropertyView(
                                property: property,
                                palette: palette,
                                showLabel: false,
                                compact: true,
                              ),
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
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: WorkspaceTypography.style(
                  context,
                  WorkspaceTextRole.metadata,
                ),
              ),
          ],
        ),
      ),
    );
  }

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
class _PagePreview extends StatelessWidget {
  const _PagePreview({
    required this.documentId,
    required this.palette,
    required this.height,
  });

  final String documentId;
  final TableViewPalette palette;

  /// Null fills whatever room the card gives it.
  final double? height;

  @override
  Widget build(BuildContext context) => Container(
        height: height,
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        color: palette.sunken.withValues(alpha: 0.6),
        child: RowPagePreview(
          documentId: documentId,
          scale: 0.6,
          emptyBuilder: (context) => Align(
            alignment: Alignment.topLeft,
            child: Text(
              LocaleKeys.gallery_pageEmpty.tr(),
              style: TextStyle(fontSize: 12, color: palette.textMuted),
            ),
          ),
          textBuilder: (context, text) => Align(
            alignment: Alignment.topLeft,
            child: Text(
              text ?? '',
              maxLines: height == null ? null : 6,
              overflow: TextOverflow.fade,
              style: TextStyle(
                fontSize: 12,
                height: 1.55,
                color: palette.textSecondary,
              ),
            ),
          ),
        ),
      );
}
