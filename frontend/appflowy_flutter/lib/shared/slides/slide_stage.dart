import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/slides/slide_deck.dart';
import 'package:appflowy/shared/slides/slide_query.dart';
import 'package:appflowy/shared/slides/slide_style.dart';
import 'package:appflowy/workspace/application/slides/slide_model.dart';
import 'package:appflowy/workspace/application/slides/slide_source.dart';
import 'package:appflowy/workspace/application/slides/slide_spec.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// A table read one row at a time, with the chrome every other viewer in the
/// application wears: a quiet header, a floating toolbar, and no borders.
class SlideStage extends StatefulWidget {
  const SlideStage({
    super.key,
    required this.viewId,
    required this.spec,
    required this.onSpecChanged,
    this.title,
    this.onOpenRow,
    this.onEditRow,
    this.onAddRow,
    this.padding = EdgeInsets.zero,
    this.showHeader = true,
    this.fullscreen = false,
    this.source,
  });

  final String viewId;
  final SlideSpec spec;
  final ValueChanged<SlideSpec> onSpecChanged;
  final String? title;

  /// Opening a slide's row, when the host can do that.
  final ValueChanged<String>? onOpenRow;

  /// Editing a slide's row in place, when the host can do that.
  final ValueChanged<String>? onEditRow;

  /// Adding a row to the table, when the host can do that. Hands back the row
  /// it made, so the deck can carry the reader to it.
  final Future<String?> Function()? onAddRow;

  final EdgeInsets padding;
  final bool showHeader;

  /// Whether this is the window-filling copy of the deck.
  final bool fullscreen;

  /// A source to read from instead of opening one. Shared with the fullscreen
  /// copy so the reader keeps their place across it.
  final SlideSource? source;

  @override
  State<SlideStage> createState() => SlideStageState();
}

class SlideStageState extends State<SlideStage> {
  late final bool _ownsSource = widget.source == null;
  late SlideSource _source =
      widget.source ?? SlideSource(viewId: widget.viewId);
  final SlideDeckController _deck = SlideDeckController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode(debugLabel: 'SlideSearch');

  SlideQuery _query = const SlideQuery();
  List<SlideCardData> _visible = const [];
  Set<String> _matches = const {};
  int _index = 0;
  bool _searchOpen = false;
  Timer? _indexTimer;

  /// A row that has just been made and is being waited for.
  String? _awaited;

  @override
  void initState() {
    super.initState();
    _source
      ..updateSpec(widget.spec)
      ..addListener(_onSourceChanged);
    _index = widget.spec.index;
    if (_ownsSource) {
      unawaited(_source.load());
    }
    _refine();
  }

  @override
  void didUpdateWidget(SlideStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.viewId != widget.viewId && _ownsSource) {
      _source.removeListener(_onSourceChanged);
      _source.dispose();
      _source = SlideSource(viewId: widget.viewId)
        ..updateSpec(widget.spec)
        ..addListener(_onSourceChanged);
      unawaited(_source.load());
    } else if (oldWidget.spec != widget.spec) {
      _source.updateSpec(widget.spec);
    }
  }

  @override
  void dispose() {
    _indexTimer?.cancel();
    _source.removeListener(_onSourceChanged);
    if (_ownsSource) {
      _source.dispose();
    }
    _deck.dispose();
    _search.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  /// Reads the table again — the host calls this when a row changes.
  void reload() => _source.invalidate();

  void _onSourceChanged() {
    if (!mounted) {
      return;
    }
    setState(() {
      _refine();
      _catchUpWithNewRow();
    });
  }

  /// A row made from the deck only becomes a slide once the table has been
  /// read again, which is when it is worth moving to.
  void _catchUpWithNewRow() {
    final awaited = _awaited;
    if (awaited == null) {
      return;
    }
    final at = _visible.indexWhere((card) => card.rowId == awaited);
    if (at < 0) {
      return;
    }
    _awaited = null;
    _index = at;
    WidgetsBinding.instance.addPostFrameCallback((_) => _deck.goTo(at));
  }

  /// Works out which slides are shown, in what order, and what a search hit.
  void _refine() {
    _visible = applySlideQuery(_source.cards, _query);
    _matches = slideMatchesOf(_visible, _query.search);
    if (_index >= _visible.length) {
      _index = _visible.isEmpty ? 0 : _visible.length - 1;
    }
  }

  void _setQuery(SlideQuery query) {
    setState(() {
      _query = query;
      _refine();
      // A search should carry the reader to what they were looking for.
      if (query.isSearching && _matches.isNotEmpty) {
        final at = _visible.indexWhere((card) => _matches.contains(card.rowId));
        if (at >= 0) {
          _index = at;
          WidgetsBinding.instance.addPostFrameCallback((_) => _deck.goTo(at));
        }
      }
    });
  }

  void _onIndexChanged(int index) {
    _index = index;
    // Every step would otherwise be a folder write; the place is only worth
    // keeping once the reader has settled on it.
    _indexTimer?.cancel();
    _indexTimer = Timer(const Duration(milliseconds: 900), () {
      if (!mounted || widget.spec.index == index) {
        return;
      }
      widget.onSpecChanged(widget.spec.copyWith(index: index));
    });
  }

  // ------------------------------------------------------------------ layout

  @override
  Widget build(BuildContext context) {
    final palette = slidePaletteOf(context);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.escape): _closeSearch,
      },
      child: ColoredBox(
        color: widget.fullscreen ? palette.canvas : Colors.transparent,
        child: Padding(
          padding: widget.padding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (widget.showHeader) ...[
                _buildHeader(palette),
                const SizedBox(height: 6),
              ],
              Expanded(child: _buildBody(palette)),
              const SizedBox(height: 12),
              _buildRail(palette),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody(SlidePalette palette) {
    if (_source.isLoading && _source.cards.isEmpty) {
      return _buildNotice(palette, LocaleKeys.slides_loading.tr());
    }
    final error = _source.error;
    if (error != null && error.isNotEmpty && _source.cards.isEmpty) {
      return _buildNotice(palette, error, onTap: reload);
    }
    if (_visible.isEmpty) {
      return _buildNotice(
        palette,
        _query.isFiltering
            ? LocaleKeys.slides_noneMatch.tr()
            : LocaleKeys.slides_addFirst.tr(),
        onTap: _query.isFiltering ? _clearFilter : _addRow,
      );
    }

    return SlideDeck(
      controller: _deck,
      cards: _visible,
      palette: palette,
      flow: widget.spec.flow,
      wrap: widget.spec.wrap,
      index: _index,
      highlighted: _query.isSearching ? _matches : null,
      onIndexChanged: _onIndexChanged,
      onOpen: widget.onOpenRow == null
          ? null
          : (card) => widget.onOpenRow!(card.rowId),
      onEdit: widget.onEditRow == null
          ? null
          : (card) => widget.onEditRow!(card.rowId),
      onContextMenu: _showSlideMenu,
      onBackgroundContextMenu: (position) => _showDeckMenu(anchor: position),
    );
  }

  Widget _buildNotice(
    SlidePalette palette,
    String message, {
    VoidCallback? onTap,
  }) {
    final actionable = onTap != null;
    return Center(
      child: MouseRegion(
        cursor: actionable ? SystemMouseCursors.click : MouseCursor.defer,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            decoration: BoxDecoration(
              color: palette.surface,
              borderRadius: BorderRadius.circular(12),
              boxShadow: palette.chromeShadow,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: TextStyle(
                    fontSize: 13,
                    color: actionable ? palette.accent : palette.textMuted,
                  ),
                ),
                if (actionable) ...[
                  const SizedBox(width: 6),
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 16,
                    color: palette.accent,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRail(SlidePalette palette) {
    if (_visible.length <= 1) {
      return const SizedBox(height: 4);
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SlideControlButton(
          palette: palette,
          icon: Icons.chevron_left_rounded,
          tooltip: LocaleKeys.slides_previous.tr(),
          onTap: _deck.previous,
        ),
        const SizedBox(width: 14),
        SlideRail(
          count: _visible.length,
          index: _index,
          palette: palette,
          onSelected: (at) => _deck.goTo(at),
        ),
        const SizedBox(width: 14),
        SlideControlButton(
          palette: palette,
          icon: Icons.chevron_right_rounded,
          tooltip: LocaleKeys.slides_next.tr(),
          onTap: _deck.next,
        ),
      ],
    );
  }

  Widget _buildHeader(SlidePalette palette) {
    final title = widget.title?.trim();
    return SizedBox(
      height: SlideMetrics.headerHeight,
      child: Row(
        children: [
          Expanded(
            child: Row(
              children: [
                Flexible(
                  child: Text(
                    title == null || title.isEmpty
                        ? LocaleKeys.slides_name.tr()
                        : title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      letterSpacing: -0.2,
                      color: palette.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  LocaleKeys.slides_slideCount.tr(
                    namedArgs: {'count': '${_visible.length}'},
                  ),
                  style: TextStyle(fontSize: 12, color: palette.textMuted),
                ),
              ],
            ),
          ),
          if (_searchOpen) ...[
            _buildSearchField(palette),
            const SizedBox(width: SlideMetrics.controlGap),
          ] else
            SlideControlButton(
              palette: palette,
              icon: Icons.search_rounded,
              tooltip: LocaleKeys.slides_search.tr(),
              onTap: _openSearch,
            ),
          const SizedBox(width: SlideMetrics.controlGap),
          SlideControlButton(
            palette: palette,
            icon: Icons.swap_vert_rounded,
            tooltip: LocaleKeys.slides_sort.tr(),
            active: _query.isSorting,
            onTap: () => _showSortMenu(palette),
          ),
          const SizedBox(width: SlideMetrics.controlGap),
          SlideControlButton(
            palette: palette,
            icon: Icons.filter_alt_rounded,
            tooltip: LocaleKeys.slides_filter.tr(),
            active: _query.isFiltering,
            onTap: () => _showFilterMenu(palette),
          ),
          const SizedBox(width: SlideMetrics.controlGap),
          SlideControlButton(
            palette: palette,
            icon: widget.spec.flow == SlideFlow.coverFlow
                ? Icons.view_carousel_rounded
                : Icons.view_agenda_rounded,
            tooltip: widget.spec.flow == SlideFlow.coverFlow
                ? LocaleKeys.slides_flowCoverFlow.tr()
                : LocaleKeys.slides_flowDeck.tr(),
            active: widget.spec.flow == SlideFlow.coverFlow,
            onTap: _toggleFlow,
          ),
          const SizedBox(width: SlideMetrics.controlGap),
          SlideControlButton(
            palette: palette,
            icon: widget.fullscreen
                ? Icons.close_fullscreen_rounded
                : Icons.open_in_full_rounded,
            tooltip: widget.fullscreen
                ? LocaleKeys.slides_exitFullscreen.tr()
                : LocaleKeys.slides_fullscreen.tr(),
            onTap: _toggleFullscreen,
          ),
          const SizedBox(width: SlideMetrics.controlGap),
          SlideControlButton(
            palette: palette,
            icon: Icons.add_rounded,
            tooltip: LocaleKeys.slides_addSlide.tr(),
            onTap: _addRow,
          ),
          const SizedBox(width: SlideMetrics.controlGap),
          Builder(
            builder: (context) => SlideControlButton(
              palette: palette,
              icon: Icons.more_horiz_rounded,
              tooltip: LocaleKeys.slides_options.tr(),
              onTap: () => _showDeckMenu(context: context),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField(SlidePalette palette) => SizedBox(
        width: SlideMetrics.searchWidth,
        height: SlideMetrics.controlSize,
        child: TextField(
          controller: _search,
          focusNode: _searchFocus,
          autofocus: true,
          style: TextStyle(fontSize: 13, color: palette.textPrimary),
          onChanged: (value) => _setQuery(_query.copyWith(search: value)),
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: palette.raised,
            hintText: LocaleKeys.slides_searchHint.tr(),
            hintStyle: TextStyle(fontSize: 13, color: palette.textMuted),
            prefixIcon:
                Icon(Icons.search_rounded, size: 15, color: palette.textMuted),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 32, minHeight: 32),
            suffixIcon: IconButton(
              icon:
                  Icon(Icons.close_rounded, size: 14, color: palette.textMuted),
              splashRadius: 12,
              onPressed: _closeSearch,
            ),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SlideMetrics.controlRadius),
              borderSide: BorderSide.none,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SlideMetrics.controlRadius),
              borderSide: BorderSide.none,
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(SlideMetrics.controlRadius),
              borderSide: BorderSide(color: palette.accent, width: 1.2),
            ),
          ),
        ),
      );

  // ------------------------------------------------------------------ menus

  void _openSearch() {
    setState(() => _searchOpen = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _closeSearch() {
    if (!_searchOpen) {
      return;
    }
    _search.clear();
    setState(() => _searchOpen = false);
    _setQuery(_query.copyWith(search: ''));
  }

  void _clearFilter() =>
      _setQuery(_query.copyWith(filterColumn: '', filterValue: ''));

  /// Adds a row, then carries the reader to the slide it became.
  void _addRow() {
    final add = widget.onAddRow;
    if (add == null) {
      return;
    }
    unawaited(
      add().then((rowId) {
        if (mounted && rowId != null) {
          setState(() {
            _awaited = rowId;
            _catchUpWithNewRow();
          });
        }
      }),
    );
  }

  void _toggleFlow() {
    final next = widget.spec.flow == SlideFlow.coverFlow
        ? SlideFlow.deck
        : SlideFlow.coverFlow;
    widget.onSpecChanged(widget.spec.copyWith(flow: next));
  }

  Future<void> _showSortMenu(SlidePalette palette) async {
    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.slides_sortBy.tr()),
        AppMenuItem(
          label: LocaleKeys.slides_tableOrder.tr(),
          icon: Icons.list_rounded,
          selected: !_query.isSorting,
          onSelected: () => _setQuery(_query.copyWith(sortColumn: '')),
        ),
        for (final field in _source.columns)
          AppMenuItem(
            label: field.name,
            icon: _query.sortColumn == field.id
                ? (_query.direction == SlideSortDirection.ascending
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded)
                : Icons.sort_rounded,
            selected: _query.sortColumn == field.id,
            onSelected: () => _setQuery(
              _query.copyWith(
                sortColumn: field.id,
                direction: _query.sortColumn == field.id
                    ? _query.direction.flipped
                    : SlideSortDirection.ascending,
              ),
            ),
          ),
      ],
    );
  }

  Future<void> _showFilterMenu(SlidePalette palette) async {
    await showAppMenuForWidget<void>(
      context: context,
      entries: [
        AppMenuHeader(LocaleKeys.slides_filterBy.tr()),
        AppMenuItem(
          label: LocaleKeys.slides_everything.tr(),
          icon: Icons.all_inclusive_rounded,
          selected: !_query.isFiltering,
          onSelected: _clearFilter,
        ),
        for (final field in _source.columns)
          AppMenuItem(
            label: field.name,
            icon: Icons.filter_alt_rounded,
            selected: _query.filterColumn == field.id,
            submenu: _filterValuesOf(field),
          ),
      ],
    );
  }

  List<AppMenuEntry> _filterValuesOf(FieldPB field) {
    final values = slideValuesOf(_source.cards, field.id).take(40).toList();
    return [
      AppMenuItem(
        label: LocaleKeys.slides_hasAnything.tr(),
        icon: Icons.check_circle_outline_rounded,
        selected: _query.filterColumn == field.id && _query.filterValue.isEmpty,
        onSelected: () => _setQuery(
          _query.copyWith(filterColumn: field.id, filterValue: ''),
        ),
      ),
      if (values.isNotEmpty) const AppMenuSeparator(),
      for (final value in values)
        AppMenuItem(
          label: value,
          selected: _query.filterColumn == field.id &&
              _query.filterValue.toLowerCase() == value.toLowerCase(),
          onSelected: () => _setQuery(
            _query.copyWith(filterColumn: field.id, filterValue: value),
          ),
        ),
    ];
  }

  Future<void> _showSlideMenu(SlideCardData card, Offset position) async {
    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: LocaleKeys.slides_openRow.tr(),
          icon: Icons.open_in_new_rounded,
          enabled: widget.onOpenRow != null,
          onSelected: () => widget.onOpenRow?.call(card.rowId),
        ),
        AppMenuItem(
          label: LocaleKeys.slides_quickEdit.tr(),
          icon: Icons.edit_rounded,
          enabled: widget.onEditRow != null,
          onSelected: () => widget.onEditRow?.call(card.rowId),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.slides_copyTitle.tr(),
          icon: Icons.copy_rounded,
          onSelected: () =>
              unawaited(Clipboard.setData(ClipboardData(text: card.title))),
        ),
        const AppMenuSeparator(),
        ..._deckEntries(),
      ],
    );
  }

  Future<void> _showDeckMenu({
    BuildContext? context,
    Offset? anchor,
  }) async {
    final host = context ?? this.context;
    if (anchor != null) {
      await showAppMenu<void>(
        context: host,
        globalPosition: anchor,
        entries: _deckEntries(),
      );
      return;
    }
    await showAppMenuForWidget<void>(context: host, entries: _deckEntries());
  }

  List<AppMenuEntry> _deckEntries() => [
        AppMenuHeader(LocaleKeys.slides_options.tr()),
        AppMenuItem(
          label: LocaleKeys.slides_addSlide.tr(),
          icon: Icons.add_rounded,
          enabled: widget.onAddRow != null,
          onSelected: _addRow,
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.slides_flowDeck.tr(),
          icon: Icons.view_agenda_rounded,
          selected: widget.spec.flow == SlideFlow.deck,
          onSelected: () =>
              widget.onSpecChanged(widget.spec.copyWith(flow: SlideFlow.deck)),
        ),
        AppMenuItem(
          label: LocaleKeys.slides_flowCoverFlow.tr(),
          icon: Icons.view_carousel_rounded,
          selected: widget.spec.flow == SlideFlow.coverFlow,
          onSelected: () => widget
              .onSpecChanged(widget.spec.copyWith(flow: SlideFlow.coverFlow)),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.slides_wrap.tr(),
          icon: Icons.repeat_rounded,
          selected: widget.spec.wrap,
          onSelected: () => widget
              .onSpecChanged(widget.spec.copyWith(wrap: !widget.spec.wrap)),
        ),
        AppMenuItem(
          label: LocaleKeys.slides_showEmpty.tr(),
          icon: Icons.more_horiz_rounded,
          selected: widget.spec.showEmptyProperties,
          onSelected: () => widget.onSpecChanged(
            widget.spec.copyWith(
              showEmptyProperties: !widget.spec.showEmptyProperties,
            ),
          ),
        ),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.slides_reload.tr(),
          icon: Icons.refresh_rounded,
          onSelected: reload,
        ),
      ];

  Future<void> _toggleFullscreen() async {
    if (widget.fullscreen) {
      await Navigator.of(context).maybePop();
      return;
    }
    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      transitionDuration: SlideMetrics.change,
      pageBuilder: (dialogContext, animation, _) => FadeTransition(
        opacity: animation,
        child: Material(
          color: slidePaletteOf(dialogContext).canvas,
          child: SlideStage(
            viewId: widget.viewId,
            spec: widget.spec,
            onSpecChanged: widget.onSpecChanged,
            title: widget.title,
            onOpenRow: widget.onOpenRow,
            onEditRow: widget.onEditRow,
            onAddRow: widget.onAddRow,
            padding: const EdgeInsets.fromLTRB(28, 18, 28, 22),
            fullscreen: true,
            // Sharing the source is what keeps the reader's place, and saves
            // reading the whole table a second time.
            source: _source,
          ),
        ),
      ),
    );
  }
}

/// One of the small round buttons the deck's chrome is made of.
class SlideControlButton extends StatefulWidget {
  const SlideControlButton({
    super.key,
    required this.palette,
    required this.icon,
    required this.onTap,
    this.tooltip,
    this.active = false,
  });

  final SlidePalette palette;
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;
  final bool active;

  @override
  State<SlideControlButton> createState() => _SlideControlButtonState();
}

class _SlideControlButtonState extends State<SlideControlButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    // Fading from a transparent black would pass through grey; the hover
    // colour at zero alpha keeps the tween in one hue.
    final resting = widget.active
        ? palette.accent.withValues(alpha: 0.14)
        : palette.hover.withValues(alpha: 0);
    final button = MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: SlideMetrics.hover,
          curve: SlideMetrics.enterCurve,
          width: SlideMetrics.controlSize,
          height: SlideMetrics.controlSize,
          decoration: BoxDecoration(
            color: _hovered && !widget.active ? palette.hover : resting,
            borderRadius: BorderRadius.circular(SlideMetrics.controlRadius),
          ),
          child: Icon(
            widget.icon,
            size: 17,
            color: widget.active ? palette.accent : palette.textSecondary,
          ),
        ),
      ),
    );

    final tooltip = widget.tooltip;
    if (tooltip == null || tooltip.isEmpty) {
      return button;
    }
    return Tooltip(
      message: tooltip,
      waitDuration: SlideMetrics.hover,
      child: button,
    );
  }
}
