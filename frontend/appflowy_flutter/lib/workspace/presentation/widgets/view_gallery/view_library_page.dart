import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/features/workspace/logic/workspace_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/table_views/table_view_chrome.dart';
import 'package:appflowy/shared/table_views/table_view_style.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/favorite/favorite_service.dart';
import 'package:appflowy/workspace/application/table_views/gallery_spec.dart';
import 'package:appflowy/workspace/application/table_views/table_query.dart';
import 'package:appflowy/workspace/application/tabs/tabs_bloc.dart';
import 'package:appflowy/workspace/application/view/local_page_store.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_query.dart';
import 'package:appflowy/workspace/application/view_gallery/view_gallery_source.dart';
import 'package:appflowy/workspace/application/workspace_item/folder_gallery_preview.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/presentation/command_palette/navigation_bloc_extension.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/shared_widget.dart'
    show ConfirmPopupStyle;
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/gallery_card_metrics.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/local_page_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_card.dart';
import 'package:appflowy/workspace/presentation/widgets/view_gallery/view_gallery_labels.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart'
    show FieldPB;
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

const _gallerySpacing = 18.0;

/// The widest the title, controls and wall grow before they centre.
const _contentMaxWidth = 1400.0;

String viewLibraryTitle(ViewLibrary library) => switch (library) {
      ViewLibrary.recents => LocaleKeys.viewLibrary_recents.tr(),
      ViewLibrary.favorites => LocaleKeys.viewLibrary_favorites.tr(),
      ViewLibrary.all => LocaleKeys.viewLibrary_library.tr(),
    };

String viewLibraryDescription(ViewLibrary library) => switch (library) {
      ViewLibrary.recents => LocaleKeys.viewLibrary_recentsDescription.tr(),
      ViewLibrary.favorites => LocaleKeys.viewLibrary_favoritesDescription.tr(),
      ViewLibrary.all => LocaleKeys.viewLibrary_libraryDescription.tr(),
    };

IconData viewLibraryIcon(ViewLibrary library) => switch (library) {
      ViewLibrary.recents => Icons.history_rounded,
      ViewLibrary.favorites => Icons.star_rounded,
      ViewLibrary.all => Icons.shelves,
    };

String viewGalleryLayoutLabel(ViewGalleryLayout layout) => switch (layout) {
      ViewGalleryLayout.gallery => LocaleKeys.viewLibrary_layoutGallery.tr(),
      ViewGalleryLayout.thumbnails =>
        LocaleKeys.viewLibrary_layoutThumbnails.tr(),
      ViewGalleryLayout.tiles => LocaleKeys.viewLibrary_layoutTiles.tr(),
      ViewGalleryLayout.list => LocaleKeys.viewLibrary_layoutList.tr(),
      ViewGalleryLayout.details => LocaleKeys.viewLibrary_layoutDetails.tr(),
    };

/// The same glyphs a folder's view menu uses for the same readings.
IconData viewGalleryLayoutIcon(ViewGalleryLayout layout) => switch (layout) {
      ViewGalleryLayout.gallery => Icons.grid_view_rounded,
      ViewGalleryLayout.thumbnails => Icons.view_carousel_rounded,
      ViewGalleryLayout.tiles => Icons.view_module_rounded,
      ViewGalleryLayout.list => Icons.view_list_rounded,
      ViewGalleryLayout.details => Icons.table_rows_rounded,
    };

/// Recents, Favorites or the Library as a page: the same wall, controls and
/// card faces a table's gallery view offers, over pages instead of rows.
class ViewLibraryPage extends StatefulWidget {
  const ViewLibraryPage({
    super.key,
    required this.library,
    this.userProfile,
    this.source,
    this.locations,
    this.specStore,
    this.previews,
    this.pageStore,
    this.favoriteService,
    this.onOpen,
    this.onOpenInNewTab,
    this.now,
  });

  final ViewLibrary library;
  final UserProfilePB? userProfile;

  /// Replaceable sources for isolated hosts; the page owns what it creates.
  final ViewGallerySource? source;
  final ViewGalleryLocations? locations;
  final ViewGallerySpecStore? specStore;
  final FolderGalleryPreviewCache? previews;

  /// Where this page's own cover is kept; null uses the shared store.
  final LocalPageStore? pageStore;
  final FavoriteService? favoriteService;
  final ValueChanged<ViewPB>? onOpen;
  final ValueChanged<ViewPB>? onOpenInNewTab;
  final DateTime Function()? now;

  @override
  State<ViewLibraryPage> createState() => ViewLibraryPageState();
}

class ViewLibraryPageState extends State<ViewLibraryPage> {
  late final ViewGallerySource _source;
  late final bool _ownsSource;
  late final ViewGalleryLocations _locations;
  late final bool _ownsLocations;
  late final ViewGallerySpecStore _store;
  late final FolderGalleryPreviewCache _previews;
  final _header = GlobalKey<TableViewHeaderState>();
  final _scroll = ScrollController();

  ViewGallerySpec _spec = const ViewGallerySpec();
  bool _specChanged = false;
  String _search = '';

  @override
  void initState() {
    super.initState();
    _ownsSource = widget.source == null;
    _source = widget.source ??
        switch (widget.library) {
          ViewLibrary.recents => RecentViewGallerySource(),
          ViewLibrary.favorites => FavoriteViewGallerySource(),
          ViewLibrary.all => AllPagesGallerySource(),
        };
    _ownsLocations = widget.locations == null;
    _locations = widget.locations ?? ViewGalleryLocations();
    _store = widget.specStore ??
        ViewGallerySpecStore(
          switch (widget.library) {
            ViewLibrary.recents => ViewGallerySpecStore.recentsKey,
            ViewLibrary.favorites => ViewGallerySpecStore.favoritesKey,
            ViewLibrary.all => ViewGallerySpecStore.libraryKey,
          },
        );
    _previews = widget.previews ?? FolderGalleryPreviewCache();
    _source.addListener(_onSourceChanged);
    _locations.addListener(_onLocationsChanged);
    unawaited(_readSpec());
    unawaited(_source.load());
    _locations.request(_source.entries);
  }

  Future<void> _readSpec() async {
    final spec = await _store.read();
    // A choice made while the stored one was loading wins.
    if (mounted && !_specChanged) setState(() => _spec = spec);
  }

  void _onSourceChanged() {
    if (!mounted) return;
    _locations.request(_source.entries);
    setState(() {});
  }

  void _onLocationsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _source.removeListener(_onSourceChanged);
    _locations.removeListener(_onLocationsChanged);
    if (_ownsSource) _source.dispose();
    if (_ownsLocations) _locations.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _setSpec(ViewGallerySpec spec) {
    if (spec == _spec) return;
    setState(() {
      _spec = spec;
      _specChanged = true;
    });
    unawaited(_store.write(spec));
  }

  void _setQuery(TableQuery query) {
    setState(() => _search = query.search);
    _setSpec(_spec.withQuery(query));
  }

  ViewGalleryFacts _facts() => ViewGalleryFacts(
        library: widget.library,
        now: widget.now?.call() ?? DateTime.now(),
        locationOf: _locations.nameOf,
      );

  List<FieldPB> _columns(ViewGalleryFacts facts) => [
        FieldPB(
          id: ViewGalleryColumns.name,
          name: LocaleKeys.viewLibrary_column_name.tr(),
        ),
        // Every page's "when" is its last edit, which has its own column.
        if (widget.library != ViewLibrary.all)
          FieldPB(id: ViewGalleryColumns.when, name: facts.whenLabel),
        FieldPB(
          id: ViewGalleryColumns.kind,
          name: LocaleKeys.viewLibrary_column_type.tr(),
        ),
        FieldPB(
          id: ViewGalleryColumns.location,
          name: LocaleKeys.viewLibrary_column_location.tr(),
        ),
        FieldPB(
          id: ViewGalleryColumns.edited,
          name: LocaleKeys.viewLibrary_column_edited.tr(),
        ),
        FieldPB(
          id: ViewGalleryColumns.created,
          name: LocaleKeys.viewLibrary_column_created.tr(),
        ),
        if (widget.library == ViewLibrary.favorites)
          FieldPB(
            id: ViewGalleryColumns.pinned,
            name: LocaleKeys.viewLibrary_column_pinned.tr(),
          ),
      ];

  void _open(ViewPB view) {
    final open = widget.onOpen;
    if (open != null) {
      open(view);
    } else {
      view.navigateTo();
    }
  }

  void _openInNewTab(ViewPB view) {
    final open = widget.onOpenInNewTab;
    if (open != null) {
      open(view);
      return;
    }
    final tabs = context.read<TabsBloc?>() ??
        (getIt.isRegistered<TabsBloc>() ? getIt<TabsBloc>() : null);
    if (tabs != null && !tabs.isClosed) tabs.openTab(view);
  }

  Future<FolderGalleryPreview> _previewOf(ViewPB view) => _previews.previewFor(
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
      );

  /// The controls scroll with the page; bring them back before searching.
  void _openSearch() {
    final header = _header.currentContext;
    if (header != null) unawaited(Scrollable.ensureVisible(header));
    _header.currentState?.openSearch();
  }

  @override
  Widget build(BuildContext context) {
    final palette = tableViewPaletteOf(context);
    final facts = _facts();
    final query = _spec.query(search: _search);
    // The workspace itself is listed as its folder, as it is everywhere else.
    final entries = viewGalleryEntriesWithRoot(
      _source.entries,
      context.watch<UserWorkspaceBloc?>()?.state.currentWorkspace,
    );
    final visible = applyViewGalleryQuery(
      entries,
      query,
      valueOf: facts.valueOf,
      timeOf: facts.timeOf,
    );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            _header.currentState?.closeSearch(),
      },
      child: WorkspaceSurface(
        kind: WorkspaceSurfaceKind.canvas,
        radius: 0,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final width = constraints.maxWidth;
            final inset = width < 360
                ? WorkspaceTokens.space4
                : WorkspaceTokens.pageInset(width);
            // One measure for the title, the controls and the wall. The page
            // scrolls as a whole, so nothing is clipped under the controls.
            final side =
                math.max(inset, (width - _contentMaxWidth) / 2 + inset);
            final available = math.max(0.0, width - side * 2);
            return Scrollbar(
              controller: _scroll,
              child: CustomScrollView(
                key: const ValueKey('view-library-scroll'),
                controller: _scroll,
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildHeader(
                      context,
                      side: side,
                      compact: width < 600,
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(
                      side,
                      WorkspaceTokens.space3,
                      side,
                      TableViewMetrics.space3,
                    ),
                    sliver: SliverToBoxAdapter(
                      child: TableViewHeader(
                        key: _header,
                        palette: palette,
                        title: visible.length == 1
                            ? LocaleKeys.viewLibrary_pageCountOne.tr()
                            : LocaleKeys.viewLibrary_pageCount
                                .tr(args: ['${visible.length}']),
                        subtitle: '',
                        columns: _columns(facts),
                        query: query,
                        onQueryChanged: _setQuery,
                        valuesOf: (column) => viewGalleryValuesOf(
                          entries,
                          column,
                          valueOf: facts.valueOf,
                          timeOf: facts.timeOf,
                        ),
                        naturalOrderLabel: switch (widget.library) {
                          ViewLibrary.recents =>
                            LocaleKeys.viewLibrary_recentOrder.tr(),
                          ViewLibrary.favorites =>
                            LocaleKeys.viewLibrary_favoriteOrder.tr(),
                          ViewLibrary.all =>
                            LocaleKeys.viewLibrary_libraryOrder.tr(),
                        },
                        searchHint: LocaleKeys.viewLibrary_searchHint.tr(),
                        optionsBuilder: _options,
                        actions: [
                          Builder(
                            builder: (context) => TableViewButton(
                              key: const ValueKey('view-library-layout'),
                              palette: palette,
                              icon: viewGalleryLayoutIcon(_spec.layout),
                              tooltip: '${LocaleKeys.viewLibrary_layout.tr()}: '
                                  '${viewGalleryLayoutLabel(_spec.layout)}',
                              onTap: () => unawaited(
                                showAppMenuForWidget<void>(
                                  context: context,
                                  entries: _layoutEntries(),
                                ),
                              ),
                            ),
                          ),
                          if (_spec.layout == ViewGalleryLayout.gallery) ...[
                            const SizedBox(width: TableViewMetrics.controlGap),
                            TableViewButton(
                              key: const ValueKey('view-library-card-size'),
                              palette: palette,
                              icon: Icons.photo_size_select_large_rounded,
                              tooltip: LocaleKeys.gallery_cardSize.tr(),
                              onTap: _cycleScale,
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  ..._buildBody(
                    context,
                    palette,
                    facts,
                    entries,
                    visible,
                    side: side,
                    available: available,
                  ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: WorkspaceTokens.space8),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// The cover (added, changed, resized or removed here and kept on this
  /// device) and the page's own title, like any other page.
  Widget _buildHeader(
    BuildContext context, {
    required double side,
    required bool compact,
  }) =>
      Builder(
        builder: (context) {
          final workspaceId = context
              .watch<UserWorkspaceBloc?>()
              ?.state
              .currentWorkspace
              ?.workspaceId;
          return LocalPageBuilder(
            pageId: localPageId(widget.library.name, workspaceId),
            store: widget.pageStore,
            builder: (context, page) => ViewDecorationActions(
              view: page.view,
              userProfile: widget.userProfile,
              visible: false,
              showIconAction: false,
              coverBackend: page.covers,
              layoutBuilder: (iconActions, coverActions, _) =>
                  WorkspacePageHeader(
                key: const ValueKey('view-library-header'),
                // The side inset already centres the page.
                maxWidth: double.infinity,
                contentInset: side,
                coverView: page.view,
                coverEditable: true,
                coverBackend: page.heights,
                cover: page.cover == null
                    ? null
                    : ViewCoverImage(
                        cover: page.cover!,
                        userProfile: widget.userProfile,
                        width: double.infinity,
                      ),
                coverActions: coverActions,
                identity: _buildTitle(
                  context,
                  compact: compact,
                  iconActions: iconActions,
                ),
              ),
            ),
          );
        },
      );

  Widget _buildTitle(
    BuildContext context, {
    required bool compact,
    Widget? iconActions,
  }) {
    final palette = WorkspacePalette.of(context);
    return WorkspacePageIdentity(
      iconActions: iconActions,
      icon: WorkspaceGlyph(
        viewLibraryIcon(widget.library),
        size: compact ? 30 : 36,
        color: switch (widget.library) {
          ViewLibrary.favorites => const Color(0xFFE0A526),
          _ => palette.accent,
        },
      ),
      title: Text(
        viewLibraryTitle(widget.library),
        style: WorkspaceTypography.style(
          context,
          WorkspaceTextRole.pageTitle,
          compact: compact,
        ),
      ),
      description: Text(viewLibraryDescription(widget.library)),
    );
  }

  List<Widget> _buildBody(
    BuildContext context,
    TableViewPalette palette,
    ViewGalleryFacts facts,
    List<ViewGalleryEntry> all,
    List<ViewGalleryEntry> visible, {
    required double side,
    required double available,
  }) {
    Widget fill(Widget child) => SliverPadding(
          padding: EdgeInsets.symmetric(horizontal: side),
          sliver: SliverFillRemaining(
            hasScrollBody: false,
            child: Padding(
              padding:
                  const EdgeInsets.symmetric(vertical: WorkspaceTokens.space8),
              child: child,
            ),
          ),
        );
    final icon = viewLibraryIcon(widget.library);
    if (_source.isLoading && all.isEmpty) {
      return [
        fill(
          TableViewEmpty(
            palette: palette,
            icon: icon,
            message: LocaleKeys.viewLibrary_loading.tr(),
          ),
        ),
      ];
    }
    if (_source.failed && all.isEmpty) {
      return [
        fill(
          TableViewEmpty(
            palette: palette,
            icon: icon,
            message: LocaleKeys.viewLibrary_couldNotRead.tr(),
            actionLabel: LocaleKeys.tableViews_tryAgain.tr(),
            onAction: () => unawaited(_source.load()),
          ),
        ),
      ];
    }
    if (all.isEmpty) {
      return [
        fill(
          TableViewEmpty(
            key: const ValueKey('view-library-empty'),
            palette: palette,
            icon: icon,
            message: switch (widget.library) {
              ViewLibrary.recents => LocaleKeys.viewLibrary_emptyRecents.tr(),
              ViewLibrary.favorites =>
                LocaleKeys.viewLibrary_emptyFavorites.tr(),
              ViewLibrary.all => LocaleKeys.viewLibrary_emptyLibrary.tr(),
            },
            detail: switch (widget.library) {
              ViewLibrary.recents =>
                LocaleKeys.viewLibrary_emptyRecentsDetail.tr(),
              ViewLibrary.favorites =>
                LocaleKeys.viewLibrary_emptyFavoritesDetail.tr(),
              ViewLibrary.all => LocaleKeys.viewLibrary_emptyLibraryDetail.tr(),
            },
          ),
        ),
      ];
    }
    final query = _spec.query(search: _search);
    if (visible.isEmpty) {
      return [
        fill(
          TableViewEmpty(
            key: const ValueKey('view-library-no-match'),
            palette: palette,
            icon: icon,
            message: LocaleKeys.tableViews_noneMatch.tr(),
            detail: LocaleKeys.tableViews_noneMatchDetail.tr(),
            actionLabel: LocaleKeys.tableViews_clearFilter.tr(),
            onAction: () {
              _header.currentState?.closeSearch();
              _setQuery(
                query.copyWith(search: '', filterColumn: '', filterValue: ''),
              );
            },
          ),
        ),
      ];
    }
    final groups = groupViewGallery(
      visible,
      _spec.groupColumn,
      valueOf: facts.valueOf,
      timeOf: facts.timeOf,
      ungrouped: LocaleKeys.tableViews_ungrouped.tr(),
    );
    final layout = galleryLayoutFor(
      available: available,
      target: _spec.scale.target,
    );
    final growth = (MediaQuery.textScalerOf(context).scale(15) / 15 - 1)
            .clamp(0.0, double.infinity) *
        TableViewMetrics.cardCaptionAllowance;
    final cardHeight = (_spec.face == GalleryCardFace.none
            ? (layout.cardWidth * 0.55).clamp(132.0, 190.0)
            : layout.cardHeight) +
        growth;
    final textScale = MediaQuery.textScalerOf(context).scale(13) / 13;
    final details = _spec.layout == ViewGalleryLayout.details
        ? _detailsColumns(facts, available, textScale)
        : const <ViewGalleryDetailsColumn>[];
    final slivers = <Widget>[
      if (_spec.layout == ViewGalleryLayout.details)
        SliverToBoxAdapter(
          child: ViewGalleryDetailsHeading(
            nameId: ViewGalleryColumns.name,
            nameLabel: LocaleKeys.viewLibrary_column_name.tr(),
            columns: details,
            sortColumn: query.sortColumn,
            descending: query.direction == TableSortDirection.descending,
            onSort: _sortBy,
          ),
        ),
    ];
    for (final group in groups) {
      if (group.label.isNotEmpty) {
        slivers.add(
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.only(
                top: TableViewMetrics.space4,
                bottom: TableViewMetrics.space1,
              ),
              child: TableGroupHeading(
                palette: palette,
                label: group.label,
                count: group.entries.length,
              ),
            ),
          ),
        );
      }
      final entries = group.entries;
      slivers.add(
        switch (_spec.layout) {
          ViewGalleryLayout.gallery => SliverGrid.builder(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: layout.columns,
                mainAxisExtent: cardHeight,
                crossAxisSpacing: _gallerySpacing,
                mainAxisSpacing: _gallerySpacing,
              ),
              itemCount: entries.length,
              itemBuilder: (context, index) => _buildCard(
                entries[index],
                facts,
                coverHeight: math.max(84.0, layout.cardHeight * 0.52),
              ),
            ),
          ViewGalleryLayout.thumbnails =>
            _thumbnailGrid(entries, available: available, scale: textScale),
          ViewGalleryLayout.tiles => _tileGrid(
              entries,
              facts,
              available: available,
              scale: textScale,
            ),
          ViewGalleryLayout.list => SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) => _buildRow(entries[index], facts),
            ),
          ViewGalleryLayout.details => SliverList.builder(
              itemCount: entries.length,
              itemBuilder: (context, index) =>
                  _buildDetailsRow(entries[index], facts, details),
            ),
        },
      );
      slivers.add(
        const SliverToBoxAdapter(
          child: SizedBox(height: TableViewMetrics.space4),
        ),
      );
    }
    return [
      SliverPadding(
        padding: EdgeInsets.symmetric(horizontal: side),
        sliver: SliverMainAxisGroup(slivers: slivers),
      ),
    ];
  }

  Widget _buildCard(
    ViewGalleryEntry entry,
    ViewGalleryFacts facts, {
    required double coverHeight,
  }) =>
      ViewGalleryCard(
        key: ValueKey('view-library-card-${entry.id}'),
        entry: entry,
        face: _spec.face,
        loadPreview: () => _previewOf(entry.view),
        caption: facts.captionOf(entry),
        details: facts.detailsOf(entry),
        userProfile: widget.userProfile,
        coverHeight: coverHeight,
        showPlaceholder: _spec.showCoverPlaceholder,
        onOpen: () => _open(entry.view),
        onMenu: (position) => _showEntryMenu(entry, position),
      );

  Widget _buildRow(ViewGalleryEntry entry, ViewGalleryFacts facts) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: ViewGalleryListRow(
          key: ValueKey('view-library-row-${entry.id}'),
          entry: entry,
          caption: facts.captionOf(entry),
          details: facts.detailsOf(entry),
          onOpen: () => _open(entry.view),
          onMenu: (position) => _showEntryMenu(entry, position),
        ),
      );

  /// A contact sheet, measured exactly as a folder's Thumbnails view is.
  Widget _thumbnailGrid(
    List<ViewGalleryEntry> entries, {
    required double available,
    required double scale,
  }) {
    final metrics = GalleryCardMetrics.thumbnails(
      available: available,
      textScale: scale,
    );
    return SliverPadding(
      // Squares keep their size; what the row does not use stays outside it.
      padding: EdgeInsetsDirectional.only(
        end: math.max(0.0, available - metrics.gridWidth),
      ),
      sliver: SliverGrid.builder(
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: metrics.columns,
          mainAxisExtent: metrics.height,
          crossAxisSpacing: metrics.spacing,
          mainAxisSpacing: metrics.spacing,
        ),
        itemCount: entries.length,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return ViewGalleryThumbnail(
            key: ValueKey('view-library-thumbnail-${entry.id}'),
            entry: entry,
            loadPreview: () => _previewOf(entry.view),
            userProfile: widget.userProfile,
            onOpen: () => _open(entry.view),
            onMenu: (position) => _showEntryMenu(entry, position),
          );
        },
      ),
    );
  }

  /// Explorer-style tiles: as many to a row as keep a name readable.
  Widget _tileGrid(
    List<ViewGalleryEntry> entries,
    ViewGalleryFacts facts, {
    required double available,
    required double scale,
  }) {
    const spacing = 8.0;
    final target = 72 + 200 * scale;
    final columns =
        math.max(1, ((available + spacing) / (target + spacing)).floor());
    final height = math.max(
      64.0,
      18 +
          (13 * 1.4 * scale).ceilToDouble() +
          2 * ((11 * 1.4 * scale).ceilToDouble() + 2),
    );
    return SliverGrid.builder(
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columns,
        mainAxisExtent: height,
        crossAxisSpacing: spacing,
        mainAxisSpacing: spacing,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return ViewGalleryTile(
          key: ValueKey('view-library-tile-${entry.id}'),
          entry: entry,
          caption: facts.captionOf(entry),
          details: facts.detailsOf(entry),
          onOpen: () => _open(entry.view),
          onMenu: (position) => _showEntryMenu(entry, position),
        );
      },
    );
  }

  /// The facts a details table shows after the name, most telling first.
  /// A column only joins while the name keeps room to be read.
  List<ViewGalleryDetailsColumn> _detailsColumns(
    ViewGalleryFacts facts,
    double available,
    double scale,
  ) {
    ViewGalleryDetailsColumn column(String id, String label, double width) =>
        ViewGalleryDetailsColumn(id: id, label: label, width: width * scale);
    final candidates = [
      if (widget.library != ViewLibrary.all)
        column(ViewGalleryColumns.when, facts.whenLabel, 130),
      column(
        ViewGalleryColumns.kind,
        LocaleKeys.viewLibrary_column_type.tr(),
        110,
      ),
      column(
        ViewGalleryColumns.location,
        LocaleKeys.viewLibrary_column_location.tr(),
        160,
      ),
      column(
        ViewGalleryColumns.edited,
        LocaleKeys.viewLibrary_column_edited.tr(),
        130,
      ),
      column(
        ViewGalleryColumns.created,
        LocaleKeys.viewLibrary_column_created.tr(),
        130,
      ),
    ];
    // Row insets, the icon and the menu, and a name wide enough to read.
    var room = available - 16 - 30 - 32 - 200 * scale;
    final columns = <ViewGalleryDetailsColumn>[];
    for (final candidate in candidates) {
      if (candidate.width > room) break;
      columns.add(candidate);
      room -= candidate.width;
    }
    return columns;
  }

  Widget _buildDetailsRow(
    ViewGalleryEntry entry,
    ViewGalleryFacts facts,
    List<ViewGalleryDetailsColumn> columns,
  ) {
    String text(String column) {
      if (ViewGalleryColumns.isTime(column)) {
        final at = facts.timeOf(entry, column);
        return at == null ? '—' : viewGalleryAgo(at, facts.now);
      }
      final value = facts.valueOf(entry, column);
      return value.trim().isEmpty ? '—' : value;
    }

    return ViewGalleryDetailsRow(
      key: ValueKey('view-library-details-${entry.id}'),
      entry: entry,
      cells: [for (final column in columns) (text(column.id), column.width)],
      onOpen: () => _open(entry.view),
      onMenu: (position) => _showEntryMenu(entry, position),
    );
  }

  /// Pressing a column name orders by it; pressing it again reverses it.
  /// Times start newest first, words from A.
  void _sortBy(String column) {
    final query = _spec.query(search: _search);
    _setQuery(
      query.copyWith(
        sortColumn: column,
        direction: query.sortColumn == column
            ? query.direction.flipped
            : ViewGalleryColumns.isTime(column)
                ? TableSortDirection.descending
                : TableSortDirection.ascending,
      ),
    );
  }

  void _cycleScale() {
    const values = GalleryCardScale.values;
    _setSpec(
      _spec.copyWith(
        scale: values[(values.indexOf(_spec.scale) + 1) % values.length],
      ),
    );
  }

  Future<void> _showEntryMenu(ViewGalleryEntry entry, Offset position) async {
    final source = _source;
    await showAppMenu<void>(
      context: context,
      globalPosition: position,
      entries: [
        AppMenuItem(
          label: LocaleKeys.viewLibrary_open.tr(),
          icon: Icons.open_in_new_rounded,
          onSelected: () => _open(entry.view),
        ),
        AppMenuItem(
          label: LocaleKeys.viewLibrary_openInNewTab.tr(),
          icon: Icons.tab_rounded,
          onSelected: () => _openInNewTab(entry.view),
        ),
        const AppMenuSeparator(),
        if (source is FavoriteViewGallerySource)
          AppMenuItem(
            label: entry.pinned
                ? LocaleKeys.viewLibrary_unpin.tr()
                : LocaleKeys.viewLibrary_pin.tr(),
            icon: Icons.push_pin_rounded,
            onSelected: () => unawaited(source.setPinned(entry, !entry.pinned)),
          ),
        if (widget.library == ViewLibrary.all)
          AppMenuItem(
            label: entry.view.isFavorite
                ? LocaleKeys.viewLibrary_removeFromFavorites.tr()
                : LocaleKeys.viewLibrary_addToFavorites.tr(),
            icon: entry.view.isFavorite
                ? Icons.star_border_rounded
                : Icons.star_rounded,
            onSelected: () => unawaited(_toggleFavorite(entry)),
          )
        else
          AppMenuItem(
            label: widget.library == ViewLibrary.recents
                ? LocaleKeys.viewLibrary_removeFromRecents.tr()
                : LocaleKeys.viewLibrary_removeFromFavorites.tr(),
            icon: widget.library == ViewLibrary.recents
                ? Icons.remove_circle_outline_rounded
                : Icons.star_border_rounded,
            onSelected: () => unawaited(source.forget(entry)),
          ),
        const AppMenuSeparator(),
        ..._viewOptions(),
      ],
    );
  }

  Future<void> _toggleFavorite(ViewGalleryEntry entry) async {
    await (widget.favoriteService ?? FavoriteService()).toggleFavorite(
      entry.id,
    );
    if (mounted) await _source.load();
  }

  List<AppMenuEntry> _options() => [
        ..._viewOptions(),
        const AppMenuSeparator(),
        AppMenuItem(
          label: LocaleKeys.viewLibrary_reload.tr(),
          icon: Icons.refresh_rounded,
          onSelected: () {
            _previews.clear();
            unawaited(_source.load());
          },
        ),
        if (_source is RecentViewGallerySource && _source.entries.isNotEmpty)
          AppMenuItem(
            label: LocaleKeys.viewLibrary_clearRecents.tr(),
            icon: Icons.delete_outline_rounded,
            destructive: true,
            onSelected: () => unawaited(_confirmClear()),
          ),
      ];

  List<AppMenuEntry> _layoutEntries() => [
        for (final layout in ViewGalleryLayout.values)
          AppMenuItem(
            label: viewGalleryLayoutLabel(layout),
            icon: viewGalleryLayoutIcon(layout),
            selected: _spec.layout == layout,
            onSelected: () => _setSpec(_spec.copyWith(layout: layout)),
          ),
      ];

  List<AppMenuEntry> _viewOptions() => [
        AppMenuHeader(LocaleKeys.viewLibrary_layout.tr()),
        ..._layoutEntries(),
        const AppMenuSeparator(),
        AppMenuHeader(LocaleKeys.gallery_cardSize.tr()),
        for (final scale in GalleryCardScale.values)
          AppMenuItem(
            label: switch (scale) {
              GalleryCardScale.small => LocaleKeys.gallery_sizeSmall.tr(),
              GalleryCardScale.medium => LocaleKeys.gallery_sizeMedium.tr(),
              GalleryCardScale.large => LocaleKeys.gallery_sizeLarge.tr(),
            },
            icon: Icons.photo_size_select_large_rounded,
            enabled: _spec.layout == ViewGalleryLayout.gallery,
            selected: _spec.scale == scale,
            onSelected: () => _setSpec(_spec.copyWith(scale: scale)),
          ),
        const AppMenuSeparator(),
        AppMenuHeader(LocaleKeys.gallery_preview.tr()),
        for (final face in GalleryCardFace.values)
          AppMenuItem(
            label: switch (face) {
              GalleryCardFace.page => LocaleKeys.gallery_facePage.tr(),
              GalleryCardFace.cover => LocaleKeys.gallery_faceCover.tr(),
              GalleryCardFace.content => LocaleKeys.gallery_faceContent.tr(),
              GalleryCardFace.none => LocaleKeys.gallery_faceNone.tr(),
              GalleryCardFace.portrait => LocaleKeys.gallery_facePortrait.tr(),
            },
            icon: switch (face) {
              GalleryCardFace.page => Icons.sticky_note_2_rounded,
              GalleryCardFace.cover => Icons.image_rounded,
              GalleryCardFace.content => Icons.article_rounded,
              GalleryCardFace.none => Icons.notes_rounded,
              GalleryCardFace.portrait => Icons.crop_portrait_rounded,
            },
            enabled: _spec.layout == ViewGalleryLayout.gallery,
            selected: _spec.face == face,
            onSelected: () => _setSpec(_spec.copyWith(face: face)),
          ),
        AppMenuItem(
          label: LocaleKeys.viewLibrary_coverPlaceholder.tr(),
          icon: Icons.crop_7_5_rounded,
          enabled: _spec.layout == ViewGalleryLayout.gallery &&
              _spec.face == GalleryCardFace.cover,
          selected: _spec.showCoverPlaceholder,
          onSelected: () => _setSpec(
            _spec.copyWith(showCoverPlaceholder: !_spec.showCoverPlaceholder),
          ),
        ),
      ];

  Future<void> _confirmClear() async {
    final source = _source;
    if (source is! RecentViewGallerySource) return;
    await showConfirmDialog(
      context: context,
      title: LocaleKeys.viewLibrary_clearRecentsTitle.tr(),
      description: LocaleKeys.viewLibrary_clearRecentsBody.tr(),
      confirmLabel: LocaleKeys.button_clear.tr(),
      style: ConfirmPopupStyle.cancelAndOk,
      onConfirm: (_) => unawaited(source.clear()),
    );
  }
}
