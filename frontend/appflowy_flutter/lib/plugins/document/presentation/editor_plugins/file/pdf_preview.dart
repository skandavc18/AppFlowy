import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_action_buttons.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/document_viewer/standalone_file_page.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import 'pdf_page_raster_cache.dart';
import 'pdf_page_turn.dart';
import 'pdf_ocr_search.dart';
import 'pdf_password_dialog.dart';
import 'pdf_preview_sidebar.dart';
import 'pdf_preview_scroll_physics.dart';
import 'pdf_preview_theme.dart';
import 'pdf_preview_toolbar.dart';
import 'pdf_preview_view_options.dart';

/// Keeps the PDF scroll thumb on screen only while the document is moving.
const _scrollThumbIdleDelay = Duration(milliseconds: 700);
const _scrollThumbFadeDuration = Duration(milliseconds: 160);

/// The toolbar steps out of the way once the reader settles down.
const _chromeIdleDelay = Duration(seconds: 3);
const _chromeRevealThrottle = Duration(milliseconds: 300);

/// Half of a mid-point page transition. A flip needs the extra time to read as
/// paper swinging on a spine; a fade only needs to get out of the way.
const _flipHalfDuration = Duration(milliseconds: 260);
const _fadeHalfDuration = Duration(milliseconds: 150);

/// How much wheel travel turns a page in [PdfPageLayoutMode.pageBreak].
const _pageTurnWheelThreshold = 48.0;
const _pageTurnWheelResetDelay = Duration(milliseconds: 260);

/// The grab strip on each outer edge that peels a page interactively.
const _pageTurnHandleWidth = 84.0;

/// Past this much of a drag the page keeps going on release.
const _pageTurnCommitFraction = 0.42;
const _pageTurnCommitVelocity = 420.0;

/// Deadlines. Navigation is gated on a busy flag, so every await it depends on
/// needs a way out.
const _pageTurnWatchdog = Duration(seconds: 4);
const _pageRasterDeadline = Duration(seconds: 3);

/// Metadata keys persisted with the block.
const _layoutModeMetadataKey = 'layoutMode';
const _pageTransitionMetadataKey = 'pageTransition';
const _autoHideToolbarMetadataKey = 'autoHideToolbar';

typedef PdfPreviewMenuBuilder = Widget Function(
  BuildContext menuContext,
  VoidCallback closeMenu,
);

class PdfPreviewScrollController {
  void Function(PointerSignalEvent event)? _handler;
  void Function(PointerPanZoomStartEvent event)? _panZoomStartHandler;
  void Function(PointerPanZoomUpdateEvent event)? _panZoomUpdateHandler;
  void Function(PointerPanZoomEndEvent event)? _panZoomEndHandler;

  void handlePointerSignal(PointerSignalEvent event) {
    _handler?.call(event);
  }

  void handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _panZoomStartHandler?.call(event);
  }

  void handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    _panZoomUpdateHandler?.call(event);
  }

  void handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    _panZoomEndHandler?.call(event);
  }

  void attach(
    void Function(PointerSignalEvent event) handler, {
    void Function(PointerPanZoomStartEvent event)? onPointerPanZoomStart,
    void Function(PointerPanZoomUpdateEvent event)? onPointerPanZoomUpdate,
    void Function(PointerPanZoomEndEvent event)? onPointerPanZoomEnd,
  }) {
    _handler = handler;
    _panZoomStartHandler = onPointerPanZoomStart;
    _panZoomUpdateHandler = onPointerPanZoomUpdate;
    _panZoomEndHandler = onPointerPanZoomEnd;
  }

  void detach(void Function(PointerSignalEvent event) handler) {
    if (_handler == handler) {
      _handler = null;
      _panZoomStartHandler = null;
      _panZoomUpdateHandler = null;
      _panZoomEndHandler = null;
    }
  }
}

class PdfPreview extends StatefulWidget {
  const PdfPreview({
    super.key,
    required this.file,
    required this.name,
    required this.metadata,
    required this.onMetadataChanged,
    required this.editable,
    this.menuBuilder,
    this.fileActions,
    this.fullscreen = false,
    this.sourceDocumentRef,
    this.scrollController,
    this.bare = false,
    this.mediaActions = const MediaActionService(),
    this.ocrIndexFactory,
    this.canReadFile,
    this.canEditFile,
  });

  final File file;
  final String name;
  final Map<String, dynamic> metadata;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final bool editable;
  final PdfPreviewMenuBuilder? menuBuilder;
  final Widget? fileActions;
  final bool fullscreen;
  final PdfDocumentRef? sourceDocumentRef;
  final PdfPreviewScrollController? scrollController;
  final MediaActionService mediaActions;

  /// Live originating-file guards, also carried across the fullscreen route.
  final bool Function()? canReadFile;
  final bool Function()? canEditFile;

  /// Test boundary only. Normal viewers use the local, native OCR service.
  @visibleForTesting
  final PdfOcrSearchIndex Function()? ocrIndexFactory;

  /// Renders pages without persistent chrome for a host such as the book
  /// reader. Local Find appears only when requested and uses this same viewer.
  final bool bare;

  @override
  State<PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<PdfPreview> with TickerProviderStateMixin {
  late PdfDocumentRef documentRef = widget.sourceDocumentRef ?? _fileRef();

  /// Whether a password has been asked for, and whether one was given.
  bool passwordAsked = false;
  bool passwordAccepted = false;

  /// Bumped to open the document again after a refused password.
  int passwordAttempt = 0;

  PdfDocumentRef _fileRef() => PdfDocumentRefFile(
        widget.file.path,
        passwordProvider: _askForPassword,
      );

  final viewerController = PdfViewerController();
  final textSearcher = _PdfPreviewTextSearch();
  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();
  FindOptions searchOptions = const FindOptions();
  bool _disposing = false;
  int _findFocusRequest = 0;
  int _queryRevision = 0;
  int _ocrRequestRevision = 0;

  /// Set while a regular expression is being typed and does not compile yet.
  bool searchPatternInvalid = false;

  /// OCR supplements (never replaces) the document's native text matches.
  /// Automatic OCR reads only text-less pages, after a completed empty search.
  bool ocrSearchEnabled = false;
  bool _autoOcrAttempted = false;
  bool _autoOcrOptOut = false;
  bool _ocrAllPages = false;
  bool _ocrScanRequested = false;
  PdfOcrSearchIndex? ocrIndex;
  List<PdfOcrMatch> ocrMatches = const [];
  List<_PdfSearchHit> _searchMatches = const [];
  int _searchMatchIndex = -1;
  int _searchStartPage = 1;
  final viewerFocusNode = FocusNode(debugLabel: 'PDF viewer');
  late final Listenable searchListenable =
      Listenable.merge([textSearcher, searchController]);
  late final PdfPreviewScrollPhysics wheelScrollPhysics;
  StandaloneFilePageScroll? _filePage;
  bool _pagePinching = false;

  late Map<String, dynamic> metadata =
      Map<String, dynamic>.from(widget.metadata);
  final highlights = <int, List<PdfTextRanges>>{};
  List<PdfTextRanges>? selection;
  PdfDocument? document;
  List<PdfOutlineNode>? outline;
  bool outlineLoading = false;
  bool viewerReady = false;
  bool searchVisible = false;
  int currentPage = 1;
  int pageCount = 0;
  int quarterTurns = 0;
  double trackpadScale = 1;
  PdfSidebarMode sidebarMode = PdfSidebarMode.none;
  final scrollThumbVisible = ValueNotifier<bool>(false);
  Timer? scrollThumbHideTimer;

  /// The sidebar owns its own scrolling: without these the embed guard hands
  /// every wheel notch to the document canvas instead.
  final sidebarKey = GlobalKey();
  final thumbnailScrollController = ScrollController();
  final outlineScrollController = ScrollController();
  bool sidebarPanActive = false;
  bool pagedPanActive = false;

  PdfPageLayoutMode layoutMode = PdfPageLayoutMode.continuous;
  PdfPageTransition pageTransition = PdfPageTransition.slide;
  AnimationController? _pageTransitionController;
  AnimationController get pageTransitionController =>
      _pageTransitionController ??=
          AnimationController(vsync: this, duration: _flipHalfDuration);
  int _pageTurnGeneration = 0;
  int? _dragGeneration;
  bool _reducedMotion = false;
  Map<String, dynamic>? _hostMetadata;
  bool pageTurnInProgress = false;
  Timer? pageTurnBusyWatchdog;
  double pageTurnWheelTravel = 0;
  Timer? pageTurnWheelResetTimer;

  /// Page bitmaps are prepared before a turn starts so the animation never
  /// waits on pdfium.
  final pageRaster = PdfPageRasterCache();
  PageTurnScene? pageTurnScene;
  double devicePixelRatio = 1;

  /// Live state of a finger-driven turn.
  double? turnDragOrigin;
  bool turnDragForward = true;
  int? turnDragTarget;

  bool autoHideToolbar = false;
  bool chromeVisible = true;
  bool toolbarHovered = false;
  int openToolbarMenus = 0;
  Timer? chromeHideTimer;
  DateTime chromeLastKeptAlive = DateTime.fromMillisecondsSinceEpoch(0);

  bool ocrInProgress = false;

  bool get canPrint =>
      viewerReady && document?.permissions?.allowsPrinting != false;

  bool get hasTextSelection =>
      selection?.any((range) => range.isNotEmpty) ?? false;

  bool get _canSearch {
    if (_disposing ||
        !(widget.canReadFile?.call() ?? true) ||
        !viewerReady ||
        !viewerController.isReady ||
        document == null ||
        pageCount == 0 ||
        !identical(documentRef.resolveListenable().document, document)) {
      return false;
    }
    final host = StandaloneFileScope.forName(context, widget.name);
    return host == null || (host.available && host.canRead());
  }

  _PdfSearchHit? get _currentSearchHit =>
      _searchMatchIndex >= 0 && _searchMatchIndex < _searchMatches.length
          ? _searchMatches[_searchMatchIndex]
          : null;

  @override
  void initState() {
    super.initState();
    layoutMode = PdfPageLayoutMode.fromName(metadata[_layoutModeMetadataKey]);
    pageTransition =
        PdfPageTransition.fromName(metadata[_pageTransitionMetadataKey]);
    autoHideToolbar = metadata[_autoHideToolbarMetadataKey] as bool? ?? false;
    wheelScrollPhysics = PdfPreviewScrollPhysics(vsync: this)
      ..attach(viewerController)
      ..consumePageDelta = _consumeFilePageDelta;
    viewerController.addListener(_handleViewerMoved);
    textSearcher.addListener(_onTextSearchChanged);
    _attachScrollController(widget.scrollController);
  }

  @override
  void didUpdateWidget(covariant PdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.detach(_handleResolvedPointerSignal);
      _attachScrollController(widget.scrollController);
    }
    if (oldWidget.file.path != widget.file.path ||
        oldWidget.sourceDocumentRef != widget.sourceDocumentRef) {
      documentRef = widget.sourceDocumentRef ?? _fileRef();
      metadata = Map<String, dynamic>.from(widget.metadata);
      passwordAsked = false;
      passwordAccepted = false;
      _resetSearchDocument();
      _readViewSettings(widget.metadata);
    } else if (!mapEquals(oldWidget.metadata, widget.metadata)) {
      // BookChapterStage publishes its reader settings through metadata. They
      // are live presentation settings, not a reason to reopen the PDF.
      _readViewSettings(widget.metadata);
    }
    if (oldWidget.bare != widget.bare) {
      _cancelPageTurn();
      _scheduleLayoutView();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final behavior = ScrollConfiguration.of(context);
    final media = MediaQuery.maybeOf(context);
    final reducedMotion = (media?.disableAnimations ??
            WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
                .disableAnimations) ||
        (media?.accessibleNavigation ?? false);
    if (devicePixelRatio != ratio || _reducedMotion != reducedMotion) {
      _cancelPageTurn();
      devicePixelRatio = ratio;
      _reducedMotion = reducedMotion;
    }
    wheelScrollPhysics.configure(
      config: behavior is PremiumScrollBehavior
          ? behavior.config
          : const PremiumScrollPhysicsConfig(),
      kineticEnabled: !reducedMotion &&
          (behavior is! PremiumScrollBehavior || behavior.kineticEnabled),
    );
    final host = StandaloneFileScope.forName(context, widget.name);
    final incoming = host?.metadata;
    _filePage = host == null || widget.fullscreen || widget.bare
        ? null
        : StandaloneFilePageScroll.maybeOf(context);
    if (incoming != null && !mapEquals(_hostMetadata, incoming)) {
      _hostMetadata = Map<String, dynamic>.from(incoming);
      _readViewSettings(incoming);
    }
    if (searchVisible && host != null && (!host.available || !host.canRead())) {
      _closeSearch(restoreFocus: false);
    }
  }

  @override
  void dispose() {
    _disposing = true;
    ++_pageTurnGeneration;
    ++_findFocusRequest;
    ++_queryRevision;
    ++_ocrRequestRevision;
    widget.scrollController?.detach(_handleResolvedPointerSignal);
    scrollThumbHideTimer?.cancel();
    chromeHideTimer?.cancel();
    pageTurnWheelResetTimer?.cancel();
    pageTurnBusyWatchdog?.cancel();
    viewerController.removeListener(_handleViewerMoved);
    scrollThumbVisible.dispose();
    _pageTransitionController?.dispose();
    _disposeSceneImages(pageTurnScene);
    pageRaster.dispose();
    thumbnailScrollController.dispose();
    outlineScrollController.dispose();
    wheelScrollPhysics.dispose();
    textSearcher
      ..removeListener(_onTextSearchChanged)
      ..dispose();
    ocrIndex
      ?..removeListener(_onScanned)
      ..dispose();
    searchController.dispose();
    searchFocusNode.dispose();
    viewerFocusNode.dispose();
    super.dispose();
  }

  /// Reveals the scroll thumb while the viewer transform changes and hides it
  /// again once the document settles.
  void _handleViewerMoved() {
    scrollThumbHideTimer?.cancel();
    scrollThumbHideTimer = Timer(_scrollThumbIdleDelay, () {
      if (mounted) {
        scrollThumbVisible.value = false;
      }
    });
    if (scrollThumbVisible.value) {
      return;
    }
    final phase = SchedulerBinding.instance.schedulerPhase;
    if (phase == SchedulerPhase.persistentCallbacks ||
        phase == SchedulerPhase.midFrameMicrotasks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          scrollThumbVisible.value = true;
        }
      });
      return;
    }
    scrollThumbVisible.value = true;
  }

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    final materialTheme = Theme.of(context);
    final content = Theme(
      data: materialTheme.copyWith(
        hoverColor: palette.controlHover,
        focusColor: palette.controlHover,
        highlightColor: Colors.transparent,
        splashColor: Colors.transparent,
        popupMenuTheme: materialTheme.popupMenuTheme.copyWith(
          color: palette.chrome,
          surfaceTintColor: Colors.transparent,
        ),
      ),
      child: CallbackShortcuts(
        bindings: _shortcutBindings,
        child: Focus(
          focusNode: viewerFocusNode,
          autofocus: widget.fullscreen,
          child: Semantics(
            label: '${widget.name}, PDF viewer',
            container: true,
            child: MouseRegion(
              opaque: false,
              onHover: _handleChromeHover,
              child: ColoredBox(
                color: palette.canvas,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _buildChrome(),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) => _buildViewerBody(
                          !widget.bare && constraints.maxWidth >= 720,
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
    // Always wrap the same subtree, even while loading or in bare mode. Only
    // eligibility changes; opening find must never remount the native viewer.
    final child = ContextualFindRegion(
      onFind: _openSearch,
      onDismiss: () => _closeSearch(restoreFocus: false),
      findOpen: searchVisible,
      findFocusNode: searchFocusNode,
      enabled: _canSearch,
      isActive: () => _canSearch,
      // The bare chapter is the reader's active content. Let it win the
      // selected-content fallback over collection search, without autofocus
      // or bypassing the router's editable-field/modal/visibility checks.
      isSelected: widget.bare ? () => _canSearch : null,
      debugLabel: 'PDF ${widget.name}',
      child: content,
    );
    return widget.scrollController == null
        ? PremiumScrollExclusion(
            child: PdfEmbedScrollGuard(
              onPointerSignal: _handleResolvedPointerSignal,
              onPointerPanZoomStart: _handlePointerPanZoomStart,
              onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
              onPointerPanZoomEnd: _handlePointerPanZoomEnd,
              child: child,
            ),
          )
        : child;
  }

  /// The same identity every other document type shows in its header.
  DocumentIdentity _documentIdentity() {
    final pages = pageCount > 0
        ? 'PDF  ·  $pageCount ${pageCount == 1 ? 'page' : 'pages'}'
        : 'PDF';
    return DocumentIdentity(
      title: widget.name,
      icon: Icons.picture_as_pdf_rounded,
      subtitle: pages,
    );
  }

  Map<ShortcutActivator, VoidCallback> get _shortcutBindings => {
        // The early shared router handles hover. Keep a local fallback for
        // fields inside this PDF, but never consume find in an unreadable
        // viewer that cannot actually show its search UI.
        if (_canSearch) ...{
          const SingleActivator(LogicalKeyboardKey.keyF, control: true):
              _openSearch,
          const SingleActivator(LogicalKeyboardKey.keyF, meta: true):
              _openSearch,
        },
        const SingleActivator(LogicalKeyboardKey.equal, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.equal, meta: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.add, control: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.add, meta: true): _zoomIn,
        const SingleActivator(LogicalKeyboardKey.minus, control: true):
            _zoomOut,
        const SingleActivator(LogicalKeyboardKey.minus, meta: true): _zoomOut,
        const SingleActivator(LogicalKeyboardKey.digit0, control: true):
            _fitPage,
        const SingleActivator(LogicalKeyboardKey.digit0, meta: true): _fitPage,
        const SingleActivator(LogicalKeyboardKey.pageUp): _previousPage,
        const SingleActivator(LogicalKeyboardKey.pageDown): _nextPage,
        const SingleActivator(LogicalKeyboardKey.home): _firstPage,
        const SingleActivator(LogicalKeyboardKey.end): _lastPage,
        const SingleActivator(LogicalKeyboardKey.escape): _handleEscape,
        // Space is the reader's page turn, but only while nothing is being
        // typed into the search field.
        if (!searchVisible) ...{
          const SingleActivator(LogicalKeyboardKey.space): _nextPage,
          const SingleActivator(LogicalKeyboardKey.space, shift: true):
              _previousPage,
        },
      };

  Widget _buildToolbar() {
    Widget toolbar(double zoom) => PdfPreviewToolbar(
          title: widget.name,
          subtitle: _documentIdentity().subtitle,
          currentPage: currentPage,
          pageCount: pageCount,
          zoom: zoom,
          ready: viewerReady,
          showThumbnails: sidebarMode == PdfSidebarMode.thumbnails,
          showOutline: sidebarMode == PdfSidebarMode.outline,
          searchVisible: searchVisible,
          isFullscreen: widget.fullscreen,
          onToggleThumbnails: () => _toggleSidebar(PdfSidebarMode.thumbnails),
          onToggleOutline: () => _toggleSidebar(PdfSidebarMode.outline),
          onPreviousPage: viewerReady && currentPage > 1 ? _previousPage : null,
          onNextPage: viewerReady && currentPage < pageCount ? _nextPage : null,
          onPageSubmitted: _goToPage,
          onZoomOut: viewerReady ? _zoomOut : null,
          onZoomIn: viewerReady ? _zoomIn : null,
          onFitWidth: viewerReady ? _fitWidth : null,
          onFitPage: viewerReady ? _fitPage : null,
          onActualSize: viewerReady ? _actualSize : null,
          onToggleSearch: _toggleSearch,
          searchEnabled: _canSearch,
          searchTapRegionGroupId: searchController,
          onRotate: viewerReady ? _rotate : null,
          onDownload: _download,
          onPrint: canPrint ? _print : null,
          onFullscreen: _toggleFullscreen,
          onMenuVisibilityChanged: _setToolbarMenuVisible,
          fileActions: widget.fullscreen
              ? Shortcuts(
                  shortcuts: const {
                    SingleActivator(LogicalKeyboardKey.space): ActivateIntent(),
                    SingleActivator(LogicalKeyboardKey.enter): ActivateIntent(),
                  },
                  child: MediaActionButtons(
                    source: MediaActionSource(
                      source: widget.file.path,
                      name: widget.name,
                    ),
                    actions: widget.mediaActions,
                    decorated: false,
                  ),
                )
              : widget.fileActions,
          viewMenu: PdfViewOptionsMenu(
            preset: PdfViewPreset.resolve(layoutMode, pageTransition),
            autoHideToolbar: autoHideToolbar,
            enabled: viewerReady,
            onPresetChanged: _setViewPreset,
            // Keep old metadata, but file options must remain discoverable.
            onAutoHideToolbarChanged: null,
            onMenuVisibilityChanged: _setToolbarMenuVisible,
          ),
          overflow: _buildOverflowMenu(),
        );

    if (!viewerReady) {
      return toolbar(1);
    }
    return AnimatedBuilder(
      animation: viewerController,
      builder: (_, __) => toolbar(viewerController.currentZoom),
    );
  }

  bool get _hasSearchMatches => _searchMatches.isNotEmpty;

  double? get _scanProgress {
    final index = ocrIndex;
    if (index == null || index.totalPages == 0) {
      return null;
    }
    return index.scannedPages / index.totalPages;
  }

  /// What the search bar says while the pages are being read, instead of the
  /// match count it has nothing to count yet.
  String? get _searchStatusOverride {
    if (searchController.text.isEmpty || searchPatternInvalid) return null;
    if (!viewerReady) return 'Loading PDF…';
    final count = _hasSearchMatches
        ? '${_searchMatchIndex + 1} of ${_searchMatches.length} · '
        : '';
    if (textSearcher.failure case final failure?) {
      return '$count$failure';
    }
    if (textSearcher.isSearching) {
      return '${_searchMatches.length} matches so far · '
          'Searching all $pageCount pages '
          '(${textSearcher.searchedPages}/$pageCount)';
    }
    final index = ocrIndex;
    if (!ocrSearchEnabled || index == null) {
      return null;
    }
    if (index.isScanning) {
      final progress = LocaleKeys.findAndReplace_scanningPages.tr(
        args: ['${index.scannedPages}', '${index.totalPages}'],
      );
      return '$count$progress';
    }
    if (index.failure case final failure?) {
      return '${count}OCR: $failure';
    }
    if (!index.isComplete && !textSearcher.isSearching) {
      return '${count}Scan paused. Resume to search the remaining pages.';
    }
    return null;
  }

  /// File identity and options stay visible, including fullscreen. Preserve
  /// legacy auto-hide metadata without allowing it to hide the only exit.
  Widget _buildChrome() {
    if (widget.bare) {
      return _buildSearchBar();
    }
    return MediaActionReveal(
      visible: true,
      child: MouseRegion(
        opaque: false,
        onEnter: (_) => _setToolbarHovered(true),
        onExit: (_) => _setToolbarHovered(false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildToolbar(),
            _buildSearchBar(),
          ],
        ),
      ),
    );
  }

  // The shared bar animates its entrance. Reserve its full height immediately
  // instead of also animating the native PDF viewport beneath it. Even a
  // hidden AnimatedSize can restart on a width change, and a zero-duration
  // restart dirties its own layout in Flutter 3.27.
  Widget _buildSearchBar() => searchVisible
      ? AnimatedBuilder(
          animation: searchListenable,
          builder: (_, __) => PdfSearchToolbar(
            controller: searchController,
            focusNode: searchFocusNode,
            currentMatch: _searchMatchIndex + 1,
            matchCount: _searchMatches.length,
            searchProgress: textSearcher.isSearching
                ? textSearcher.searchProgress
                : _scanProgress,
            isSearching: textSearcher.isSearching ||
                (ocrSearchEnabled && (ocrIndex?.isScanning ?? false)),
            options: searchOptions,
            onOptionsChanged: _setSearchOptions,
            queryInvalid: searchPatternInvalid,
            ocrEnabled: ocrSearchEnabled,
            onToggleOcr: _toggleOcrSearch,
            onRetryOcr: ocrSearchEnabled &&
                    ocrIndex != null &&
                    !ocrIndex!.isScanning &&
                    !ocrIndex!.isComplete &&
                    searchController.text.isNotEmpty &&
                    !searchPatternInvalid
                ? _retryOcrSearch
                : null,
            onCopyMatch: _currentSearchHit?.isOcr == true &&
                    document?.permissions?.allowsCopying != false
                ? _copyOcrMatch
                : null,
            statusOverride: _searchStatusOverride,
            onChanged: _search,
            onPrevious: _hasSearchMatches ? _previousSearchMatch : null,
            onNext: _hasSearchMatches ? _nextSearchMatch : null,
            onClose: _closeSearch,
            onTapOutside: (_) => _closeSearch(restoreFocus: false),
          ),
        )
      : const SizedBox.shrink();

  Widget _buildViewerBody(bool dockSidebar) {
    final viewer = RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: _handleCanvasTap,
        onDoubleTapDown: _handleDoubleTap,
        child: RotatedBox(
          quarterTurns: quarterTurns,
          child: PdfViewer(
            documentRef,
            key: ValueKey('pdf-$passwordAttempt-${widget.file.path}'),
            controller: viewerController,
            params: _viewerParams(),
          ),
        ),
      ),
    );

    final scene = pageTurnScene;
    final stage = TapRegion(
      // Claim focus after outside text fields have unfocused: a raw Listener
      // runs before TapRegionSurface and its request can be overwritten there.
      // This region deliberately does NOT join the search bar's group: a
      // canvas press still dismisses find, and pdfrx keeps its selection arena.
      behavior: HitTestBehavior.translucent,
      onTapInside: (_) => _handleCanvasTap(),
      child: Stack(
        children: [
          Positioned.fill(child: _wrapPageTransition(viewer)),
          // The turning leaf is a sibling of the viewer, never a
          // wrapper around it, so pdfrx is never re-parented mid
          // animation.
          if (scene != null)
            Positioned.fill(
              child: IgnorePointer(
                child: RepaintBoundary(
                  child: AnimatedBuilder(
                    animation: pageTransitionController,
                    builder: (_, __) => CustomPaint(
                      painter: PageTurnPainter(
                        scene: scene,
                        progress: pageTransitionController.value,
                      ),
                      size: Size.infinite,
                    ),
                  ),
                ),
              ),
            ),
          ..._buildPageTurnHandles(),
        ],
      ),
    );

    final sidebarVisible = !widget.bare && sidebarMode != PdfSidebarMode.none;
    return Stack(
      children: [
        Positioned.fill(
          // Keep the renderer at the same depth across sidebar breakpoints.
          // Replacing a Row with a Stack would reopen the loaded PDF.
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                curve: Curves.easeOutCubic,
                width: dockSidebar && sidebarVisible ? 214 : 0,
              ),
              Expanded(child: stage),
            ],
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: dockSidebar || !sidebarVisible,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: !dockSidebar && sidebarVisible ? 1 : 0,
              child: GestureDetector(
                key: const ValueKey('pdf-sidebar-scrim'),
                behavior: HitTestBehavior.opaque,
                onTap: _closeSidebar,
                child: ColoredBox(
                  color: Colors.black.withValues(alpha: 0.28),
                ),
              ),
            ),
          ),
        ),
        AnimatedPositioned(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
          left: sidebarVisible ? 0 : -236,
          top: 0,
          bottom: 0,
          width: dockSidebar ? 214 : 224,
          child: _buildSidebar(),
        ),
      ],
    );
  }

  /// Kept structurally constant so switching transition styles never rebuilds
  /// the pdfrx viewer (which would drop the loaded document). Only the fade
  /// touches the live canvas; the page turn paints its own leaf beside it.
  Widget _wrapPageTransition(Widget viewer) {
    return AnimatedBuilder(
      animation: pageTransitionController,
      builder: (context, child) {
        final progress = pageTransitionController.value;
        final fading = pageTransition == PdfPageTransition.fade &&
            progress > 0 &&
            progress < 1;
        final opacity = fading ? 1 - math.sin(progress * math.pi) : 1.0;
        return Opacity(opacity: opacity.clamp(0.0, 1.0), child: child);
      },
      child: viewer,
    );
  }

  /// Grab zones on the outer corners of the spread. Dragging inwards peels the
  /// page and the curl follows the pointer.
  List<Widget> _buildPageTurnHandles() {
    if (_reducedMotion ||
        !pageTransition.curlsPaper ||
        !viewerReady ||
        quarterTurns != 0) {
      return const [];
    }
    return [
      Positioned(
        left: 0,
        top: 0,
        bottom: 0,
        width: _pageTurnHandleWidth,
        child: _pageTurnHandle(forward: false),
      ),
      Positioned(
        right: 0,
        top: 0,
        bottom: 0,
        width: _pageTurnHandleWidth,
        child: _pageTurnHandle(forward: true),
      ),
    ];
  }

  Widget _pageTurnHandle({required bool forward}) => MouseRegion(
        opaque: false,
        cursor: SystemMouseCursors.grab,
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onHorizontalDragStart: (details) =>
              _handleTurnDragStart(details, forward: forward),
          onHorizontalDragUpdate: _handleTurnDragUpdate,
          onHorizontalDragEnd: _handleTurnDragEnd,
          onHorizontalDragCancel: _handleTurnDragCancel,
        ),
      );

  Widget _buildSidebar() => KeyedSubtree(
        key: sidebarKey,
        child: PdfPreviewSidebar(
          mode: sidebarMode == PdfSidebarMode.none
              ? PdfSidebarMode.thumbnails
              : sidebarMode,
          document: document,
          currentPage: currentPage,
          outline: outline,
          outlineLoading: outlineLoading,
          thumbnailScrollController: thumbnailScrollController,
          outlineScrollController: outlineScrollController,
          onPageSelected: _goToPage,
          onDestinationSelected: (destination) {
            unawaited(viewerController.goToDest(destination));
          },
          onClose: _closeSidebar,
        ),
      );

  PdfViewerParams _viewerParams() {
    final palette = PdfPreviewPalette.of(context);
    return PdfViewerParams(
      margin: widget.fullscreen ? 30 : 20,
      backgroundColor: palette.canvas,
      minScale: 0.15,
      useAlternativeFitScaleAsMinScale: false,
      onePassRenderingScaleThreshold: 240 / 72,
      getPageRenderingScale: _getPageRenderingScale,
      layoutPages: _layoutPages,
      maxImageBytesCachedOnMemory: 96 * 1024 * 1024,
      horizontalCacheExtent: layoutMode.isHorizontal ? 1.25 : 0.65,
      verticalCacheExtent: layoutMode.isHorizontal ? 0.65 : 1.25,
      enableTextSelection: true,
      selectableRegionInjector: _selectableRegion,
      scrollByMouseWheel: 0,
      onInteractionStart: (_) => wheelScrollPhysics.stop(),
      matchTextColor: palette.searchMatch,
      activeMatchTextColor: palette.activeSearchMatch,
      pageDropShadow: BoxShadow(
        color: palette.pageShadow,
        blurRadius: 18,
        spreadRadius: -2,
        offset: const Offset(0, 6),
      ),
      onPageChanged: (page) {
        if (page != null && page != currentPage && mounted) {
          setState(() => currentPage = page);
          _prefetchTurnPages();
        }
      },
      onTextSelectionChange: (value) {
        if (mounted) {
          setState(() => selection = value);
        }
      },
      onViewerReady: _onViewerReady,
      onDocumentChanged: _onDocumentChanged,
      loadingBannerBuilder: (_, __, ___) => const _PdfLoadingSkeleton(),
      errorBannerBuilder: (_, error, __, ___) => _PdfCanvasError(
        message: error.toString(),
        locked: passwordAsked && !passwordAccepted,
        onUnlock: passwordAsked && !passwordAccepted ? _retryPassword : null,
      ),
      linkHandlerParams: PdfLinkHandlerParams(onLinkTap: _handleLink),
      viewerOverlayBuilder: (_, __, ___) => quarterTurns == 0
          ? [
              PdfViewerScrollThumb(
                controller: viewerController,
                orientation: layoutMode.isHorizontal
                    ? ScrollbarOrientation.bottom
                    : ScrollbarOrientation.right,
                thumbSize: const Size(34, 46),
                margin: 8,
                thumbBuilder: (_, size, page, __) => _PdfScrollThumb(
                  size: size,
                  page: page ?? currentPage,
                  visible: scrollThumbVisible,
                ),
              ),
            ]
          : const [],
      // A page is defined by its own drop shadow, never by an outline drawn
      // over the document.
      pagePaintCallbacks: [
        _paintTextMatches,
        _paintOcrMatches,
        _paintHighlights,
      ],
    );
  }

  PdfPageLayout _layoutPages(List<PdfPage> pages, PdfViewerParams params) =>
      buildPdfPageLayout(pages, params, layoutMode);

  Widget _selectableRegion(BuildContext context, Widget child) =>
      CallbackShortcuts(
        // pdfrx's own Focus consumes Page Up/Down before an outer shortcut can
        // see them. Insert below it, keeping native SelectionArea and Ctrl+C.
        bindings: _shortcutBindings,
        child: SelectionArea(child: child),
      );

  double _getPageRenderingScale(
    BuildContext context,
    PdfPage page,
    PdfViewerController controller,
    double estimatedScale,
  ) {
    final maxDimensionScale = math.min(4200 / page.width, 4200 / page.height);
    return math.min(estimatedScale, maxDimensionScale);
  }

  Widget _buildOverflowMenu() {
    final palette = PdfPreviewPalette.of(context);
    return AppMenuIconButton(
      key: const ValueKey('pdf-overflow-menu'),
      icon: Icons.more_horiz_rounded,
      tooltip: 'More actions',
      size: 30,
      iconSize: 18,
      radius: 6,
      iconColor: palette.icon,
      enabled: viewerReady || widget.menuBuilder != null,
      onVisibilityChanged: _setToolbarMenuVisible,
      entries: _overflowEntries,
    );
  }

  List<AppMenuEntry> _overflowEntries() {
    AppMenuItem item(
      _PdfOverflowAction value,
      IconData icon,
      String label, {
      bool enabled = true,
    }) =>
        AppMenuItem(
          label: label,
          icon: icon,
          enabled: enabled,
          onSelected: () => _handleOverflowAction(value),
        );

    return [
      AppMenuItem(
        label: sidebarMode == PdfSidebarMode.outline
            ? 'Hide document outline'
            : 'Show document outline',
        icon: Icons.account_tree_rounded,
        selected: sidebarMode == PdfSidebarMode.outline,
        onSelected: () => _toggleSidebar(PdfSidebarMode.outline),
      ),
      const AppMenuSeparator(),
      item(
        _PdfOverflowAction.copyText,
        Icons.content_copy_rounded,
        'Copy selected text',
        enabled: hasTextSelection,
      ),
      item(
        _PdfOverflowAction.scanText,
        Icons.document_scanner_rounded,
        ocrInProgress ? 'Scanning page…' : 'Scan text on this page (OCR)',
        enabled: viewerReady && !ocrInProgress,
      ),
      item(
        _PdfOverflowAction.highlight,
        Icons.highlight_alt_rounded,
        'Highlight selection',
        enabled: widget.editable && hasTextSelection,
      ),
      const AppMenuSeparator(),
      item(
        _PdfOverflowAction.fitWidth,
        Icons.fit_screen_rounded,
        'Fit to width',
        enabled: viewerReady,
      ),
      item(
        _PdfOverflowAction.fitPage,
        Icons.fullscreen_exit_rounded,
        'Fit whole page',
        enabled: viewerReady,
      ),
      item(
        _PdfOverflowAction.actualSize,
        Icons.filter_1_rounded,
        'Actual size',
        enabled: viewerReady,
      ),
      item(
        _PdfOverflowAction.rotate,
        Icons.rotate_90_degrees_cw_rounded,
        'Rotate clockwise',
        enabled: viewerReady,
      ),
      const AppMenuSeparator(),
      item(
        _PdfOverflowAction.download,
        Icons.download_rounded,
        'Download PDF',
      ),
      item(
        _PdfOverflowAction.print,
        Icons.print_rounded,
        canPrint ? 'Print PDF' : 'Printing is restricted',
        enabled: canPrint,
      ),
      if (widget.menuBuilder != null) ...[
        const AppMenuSeparator(),
        AppMenuCustom(
          builder: (menuContext) => widget.menuBuilder!(
            menuContext,
            () => AppMenuScope.maybeOf(menuContext)?.close(),
          ),
        ),
      ],
    ];
  }

  void _handleOverflowAction(_PdfOverflowAction action) {
    switch (action) {
      case _PdfOverflowAction.copyText:
        unawaited(_copySelectedText());
        break;
      case _PdfOverflowAction.scanText:
        unawaited(_scanPageText());
        break;
      case _PdfOverflowAction.highlight:
        _highlightSelection();
        break;
      case _PdfOverflowAction.fitWidth:
        _fitWidth();
        break;
      case _PdfOverflowAction.fitPage:
        _fitPage();
        break;
      case _PdfOverflowAction.actualSize:
        _actualSize();
        break;
      case _PdfOverflowAction.rotate:
        _rotate();
        break;
      case _PdfOverflowAction.download:
        unawaited(_download());
        break;
      case _PdfOverflowAction.print:
        unawaited(_print());
        break;
    }
  }

  /// Supplies the password for an encrypted document.
  ///
  /// pdfrx calls this until it is given one that works or is given null, so
  /// returning null on cancel is what stops it asking again and again.
  Future<String?> _askForPassword() async {
    if (!mounted) {
      return null;
    }
    final retry = passwordAsked;
    passwordAsked = true;
    final entered = await showPdfPasswordDialog(
      context,
      name: widget.name,
      retry: retry,
    );
    if (entered == null || entered.isEmpty) {
      return null;
    }
    passwordAccepted = true;
    return entered;
  }

  /// Opens the document again so the password can be entered a second time.
  void _retryPassword() {
    setState(() {
      passwordAsked = false;
      passwordAccepted = false;
      passwordAttempt++;
      documentRef = widget.sourceDocumentRef ?? _fileRef();
    });
  }

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted ||
        _disposing ||
        !identical(documentRef.resolveListenable().document, document)) {
      return;
    }
    setState(() {
      if (!identical(this.document, document)) _resetSearchDocument();
      this.document = document;
      pageCount = document.pages.length;
      currentPage = controller.pageNumber ?? 1;
      viewerReady = true;
      outlineLoading = true;
    });
    unawaited(_loadOutline(document));
    unawaited(_restoreHighlights(document));
    _scheduleChromeHide();
    _prefetchTurnPages();
    if (searchVisible && searchController.text.isNotEmpty) {
      _search(searchController.text, immediately: true);
    }
  }

  void _onDocumentChanged(PdfDocument? value) {
    if (!mounted ||
        _disposing ||
        identical(value, document) ||
        !identical(value, documentRef.resolveListenable().document)) {
      return;
    }
    setState(_resetSearchDocument);
  }

  /// Text caches and OCR results belong to a loaded handle, not a page number
  /// or filename. Retain the query/options while a replacement PDF is loading.
  void _resetSearchDocument() {
    _cancelPageTurn(stopViewer: false);
    pageRaster.clear();
    viewerReady = false;
    document = null;
    pageCount = 0;
    currentPage = 1;
    outline = null;
    selection = null;
    highlights.clear();
    ++_findFocusRequest;
    ++_queryRevision;
    ++_ocrRequestRevision;
    textSearcher.forgetDocument();
    ocrIndex
      ?..removeListener(_onScanned)
      ..dispose();
    ocrIndex = null;
    ocrMatches = const [];
    _searchMatches = const [];
    _searchMatchIndex = -1;
    ocrSearchEnabled = false;
    _autoOcrAttempted = false;
    _autoOcrOptOut = false;
    _ocrAllPages = false;
    _ocrScanRequested = false;
  }

  Future<void> _loadOutline(PdfDocument document) async {
    List<PdfOutlineNode> loaded = const [];
    try {
      loaded = await document.loadOutline();
    } on Object {
      loaded = const [];
    }
    if (!mounted || this.document != document) {
      return;
    }
    setState(() {
      outline = loaded;
      outlineLoading = false;
    });
  }

  void _handleLink(PdfLink link) {
    wheelScrollPhysics.stop();
    final destination = link.dest;
    if (destination != null) {
      unawaited(viewerController.goToDest(destination));
      return;
    }
    final url = link.url;
    if (url != null) {
      unawaited(afLaunchUrlString(url.toString(), context: context));
    }
  }

  void _handleResolvedPointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent || !viewerController.isReady) {
      return;
    }
    _pagePinching = false;

    // The side panel is a scroll surface of its own; the embed guard claims
    // wheel signals for the whole preview, so hand them back here.
    if (_pointerOverSidebar(event.position)) {
      _scrollSidebarBy(event.scrollDelta.dy);
      return;
    }

    _revealChrome();

    final keyboard = HardwareKeyboard.instance;
    if (keyboard.isControlPressed || keyboard.isMetaPressed) {
      wheelScrollPhysics.stop();
      final anchor = viewerController.globalToDocument(event.position) ??
          viewerController.centerPosition;
      final factor = math.exp(-event.scrollDelta.dy * 0.0022);
      final target = (viewerController.currentZoom * factor).clamp(
        viewerController.minScale,
        viewerController.params.maxScale,
      );
      unawaited(viewerController.setZoom(anchor, target));
      return;
    }

    // A vertical wheel is the only wheel most mice have; in a horizontal
    // layout it has to move the document sideways to be of any use.
    final pageDelta = _consumeNavigationHeader(event.scrollDelta);
    if (pageDelta == Offset.zero) return;
    final delta = layoutMode.isHorizontal && pageDelta.dx == 0
        ? Offset(pageDelta.dy, 0)
        : pageDelta;

    if (_pagedNavigation) {
      final travel = layoutMode.isHorizontal ? delta.dx : delta.dy;
      // Scroll inside a page that is too big to fit, then turn once its edge
      // is reached.
      if (_wholePageIsVisible || _atPageBoundary(travel)) {
        _accumulatePageTurn(travel);
        return;
      }
    }

    wheelScrollPhysics.scroll(delta, kind: event.kind);
  }

  /// Page turns do not pass through the matrix consumption callback. Retire
  /// the header before accumulating a turn, leaving the existing pager/curl
  /// owner untouched. Reverse reveals only at the first page's real boundary,
  /// never merely because a later page happens to fit in the viewport.
  Offset _consumeNavigationHeader(Offset delta) {
    final page = _filePage;
    if (page == null ||
        !delta.isFinite ||
        _pagePinching ||
        quarterTurns != 0 ||
        !_pagedNavigation ||
        HardwareKeyboard.instance.isShiftPressed ||
        delta.dy.abs() <= delta.dx.abs()) {
      return delta;
    }
    if (delta.dy > 0 || (currentPage == 1 && _wholePageIsVisible)) {
      final header = StandaloneFilePageScroll.move(page.outer, delta.dy);
      if (header != 0) wheelScrollPhysics.stop();
      return Offset(delta.dx, delta.dy - header);
    }
    return delta;
  }

  Offset _consumeFilePageDelta(Offset delta, Offset Function(Offset) body) {
    final page = _filePage;
    if (page == null ||
        _disposing ||
        !mounted ||
        _pagePinching ||
        quarterTurns != 0 ||
        layoutMode != PdfPageLayoutMode.continuous ||
        delta.dx.abs() > delta.dy.abs()) return body(delta);
    var horizontal = 0.0;
    final consumed = page.consume(-delta.dy, (remaining) {
      final actual = body(Offset(delta.dx, -remaining));
      horizontal = actual.dx;
      return -actual.dy;
    });
    return Offset(horizontal, -consumed);
  }

  bool _pointerOverSidebar(Offset globalPosition) {
    if (sidebarMode == PdfSidebarMode.none) {
      return false;
    }
    final renderObject = sidebarKey.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || !renderObject.hasSize) {
      return false;
    }
    final local = renderObject.globalToLocal(globalPosition);
    return local.dx >= 0 &&
        local.dy >= 0 &&
        local.dx <= renderObject.size.width &&
        local.dy <= renderObject.size.height;
  }

  ScrollPosition? get _sidebarScrollPosition {
    final controller = sidebarMode == PdfSidebarMode.outline
        ? outlineScrollController
        : thumbnailScrollController;
    if (!controller.hasClients || controller.positions.isEmpty) {
      return null;
    }
    return controller.positions.last;
  }

  void _scrollSidebarBy(double delta) {
    final position = _sidebarScrollPosition;
    if (position == null || !position.hasContentDimensions || delta == 0) {
      return;
    }
    final target = (position.pixels + delta).clamp(
      position.minScrollExtent,
      position.maxScrollExtent,
    );
    if ((target - position.pixels).abs() < 0.01) {
      return;
    }
    position.jumpTo(target);
  }

  /// Scrolling moves a page at a time only where the layout is built around
  /// whole pages. Continuous and horizontal reading keep free scrolling no
  /// matter which page turn animation is selected — an animation is never
  /// worth taking the scroll wheel away.
  bool get _pagedNavigation =>
      layoutMode.turnsPages || layoutMode == PdfPageLayoutMode.facing;

  /// True while the current page is fully on screen, which is when a wheel
  /// notch should turn the page instead of nudging the canvas.
  bool get _wholePageIsVisible {
    if (!viewerController.isReady || pageCount == 0) {
      return false;
    }
    try {
      final pageRect = viewerController.layout.pageLayouts[currentPage - 1];
      final view = viewerController.viewSize;
      if (pageRect.isEmpty || view.isEmpty) {
        return false;
      }
      final fitScale = math.min(
        view.width / pageRect.width,
        view.height / pageRect.height,
      );
      return viewerController.currentZoom <= fitScale * 1.05;
    } on Object {
      return false;
    }
  }

  /// True once the document cannot travel any further inside the current page
  /// in the direction of [travel].
  bool _atPageBoundary(double travel) {
    if (!viewerController.isReady || pageCount == 0 || travel == 0) {
      return false;
    }
    try {
      final pageRect = viewerController.layout.pageLayouts[currentPage - 1];
      final visible = viewerController.visibleRect;
      const slack = 2.0;
      if (layoutMode.isHorizontal) {
        return travel > 0
            ? visible.right >= pageRect.right - slack
            : visible.left <= pageRect.left + slack;
      }
      return travel > 0
          ? visible.bottom >= pageRect.bottom - slack
          : visible.top <= pageRect.top + slack;
    } on Object {
      return false;
    }
  }

  void _accumulatePageTurn(double delta) {
    pageTurnWheelResetTimer?.cancel();
    pageTurnWheelResetTimer = Timer(
      _pageTurnWheelResetDelay,
      () => pageTurnWheelTravel = 0,
    );
    if (pageTurnInProgress) {
      return;
    }
    pageTurnWheelTravel += delta;
    if (pageTurnWheelTravel.abs() < _pageTurnWheelThreshold) {
      return;
    }
    final forward = pageTurnWheelTravel > 0;
    pageTurnWheelTravel = 0;
    if (forward && currentPage >= pageCount) {
      return;
    }
    if (!forward && currentPage <= 1) {
      return;
    }
    _goToPage(forward ? _forwardPage : _backwardPage);
  }

  void _attachScrollController(PdfPreviewScrollController? controller) {
    controller?.attach(
      _handleResolvedPointerSignal,
      onPointerPanZoomStart: _handlePointerPanZoomStart,
      onPointerPanZoomUpdate: _handlePointerPanZoomUpdate,
      onPointerPanZoomEnd: _handlePointerPanZoomEnd,
    );
  }

  void _handlePointerPanZoomStart(PointerPanZoomStartEvent event) {
    _pagePinching = false;
    trackpadScale = 1;
    sidebarPanActive = _pointerOverSidebar(event.position);
    if (sidebarPanActive) {
      return;
    }
    _revealChrome();
    pagedPanActive = _pagedNavigation && _wholePageIsVisible;
    if (pagedPanActive) {
      return;
    }
    wheelScrollPhysics.beginTrackpadPan(event);
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (sidebarPanActive) {
      _scrollSidebarBy(-event.localPanDelta.dy);
      return;
    }
    if (!viewerController.isReady) {
      return;
    }
    if (pagedPanActive) {
      if ((event.scale - 1).abs() <= .001 && event.rotation == 0) {
        final delta = _consumeNavigationHeader(-event.localPanDelta);
        _accumulatePageTurn(layoutMode.isHorizontal ? delta.dx : delta.dy);
        return;
      }
      // A stream which becomes a pinch leaves paging and keeps native zoom.
      pagedPanActive = false;
      wheelScrollPhysics.stop();
    }

    _pagePinching |= (event.scale - 1).abs() > 0.001;
    wheelScrollPhysics.updateTrackpadPan(event);
    final previousScale = trackpadScale;
    trackpadScale = event.scale;
    if (previousScale > 0 && trackpadScale > 0) {
      wheelScrollPhysics.scaleBy(
        event.position,
        trackpadScale / previousScale,
      );
    }
  }

  void _handlePointerPanZoomEnd(PointerPanZoomEndEvent event) {
    trackpadScale = 1;
    if (sidebarPanActive) {
      sidebarPanActive = false;
      return;
    }
    if (pagedPanActive) {
      pagedPanActive = false;
      pageTurnWheelTravel = 0;
      return;
    }
    wheelScrollPhysics.endTrackpadPan(event);
  }

  void _handleCanvasTap() {
    _revealChrome();
    viewerFocusNode.requestFocus();
  }

  void _handleDoubleTap(TapDownDetails details) {
    if (!viewerReady) {
      return;
    }
    wheelScrollPhysics.stop();
    final fitScale =
        viewerController.alternativeFitScale ?? viewerController.minScale;
    final current = viewerController.currentZoom;
    final target = current > fitScale * 1.55
        ? fitScale
        : math.min(current * 1.8, viewerController.params.maxScale);
    final anchor = viewerController.globalToDocument(details.globalPosition) ??
        viewerController.centerPosition;
    unawaited(viewerController.setZoom(anchor, target));
  }

  void _goToPage(int page) => unawaited(_navigateToPage(page));

  /// Page navigation runs through the chosen [PdfPageTransition]: [slide] lets
  /// pdfrx animate its own matrix, while [fade] and [flip] swap the page while
  /// the canvas is hidden behind the animation.
  Future<void> _navigateToPage(int page) async {
    if (!_turnIsCurrent(_pageTurnGeneration) ||
        pageCount == 0 ||
        pageTurnInProgress) {
      return;
    }
    final target = page.clamp(1, pageCount);
    wheelScrollPhysics.stop();
    _revealChrome();
    final generation = ++_pageTurnGeneration;
    _setPageTurnBusy(true, generation);
    try {
      switch (_reducedMotion ? PdfPageTransition.none : pageTransition) {
        case PdfPageTransition.none:
          await _moveViewToPage(target, Duration.zero);
          break;
        case PdfPageTransition.slide:
          await _moveViewToPage(target, const Duration(milliseconds: 300));
          break;
        case PdfPageTransition.fade:
          if (!await _animatePageTransitionTo(
            0.5,
            Curves.easeInCubic,
            generation,
          )) {
            return;
          }
          await _moveViewToPage(target, Duration.zero);
          if (!_turnIsCurrent(generation)) {
            return;
          }
          await _animatePageTransitionTo(1, Curves.easeOutCubic, generation);
          if (_turnIsCurrent(generation)) {
            pageTransitionController.value = 0;
          }
          break;
        case PdfPageTransition.flip:
          if (!await _runPageCurl(target, generation) &&
              _turnIsCurrent(generation)) {
            // Nothing to rasterise yet, so fall back to a plain move rather
            // than showing no feedback at all.
            await _moveViewToPage(target, const Duration(milliseconds: 300));
          }
          break;
      }
    } finally {
      // A cancelled turn must not unlock a newer turn or steal its focus.
      _setPageTurnBusy(false, generation);
    }
  }

  /// Navigation is gated on this flag, so it must never be able to stick.
  /// A watchdog releases it even if an awaited animation is swallowed.
  void _setPageTurnBusy(bool busy, int generation) {
    if (!mounted || _disposing || generation != _pageTurnGeneration) return;
    pageTurnBusyWatchdog?.cancel();
    pageTurnInProgress = busy;
    if (!busy) {
      return;
    }
    pageTurnBusyWatchdog = Timer(_pageTurnWatchdog, () {
      if (_turnIsCurrent(generation)) setState(_cancelPageTurn);
    });
  }

  bool _turnIsCurrent(int generation) =>
      mounted &&
      !_disposing &&
      generation == _pageTurnGeneration &&
      viewerReady &&
      viewerController.isReady &&
      identical(documentRef.resolveListenable().document, document);

  /// Invalidates every suspended render, fade midpoint and curl commit. Merely
  /// clearing the busy flag lets an old await navigate a replacement document.
  /// Call inside an existing state update/lifecycle callback when repainting.
  void _cancelPageTurn({bool stopViewer = true}) {
    ++_pageTurnGeneration;
    pageTurnBusyWatchdog?.cancel();
    pageTurnWheelResetTimer?.cancel();
    pageTurnInProgress = false;
    pageTurnWheelTravel = 0;
    turnDragOrigin = null;
    turnDragTarget = null;
    _dragGeneration = null;
    _disposeSceneImages(pageTurnScene);
    pageTurnScene = null;
    _pageTransitionController?.value = 0;
    wheelScrollPhysics.stop();
    if (stopViewer && viewerReady && viewerController.isReady) {
      // pdfrx owns slide motion. A zero-duration move to its current matrix
      // cancels that ticker too, rather than letting it finish in a new mode.
      unawaited(
        viewerController.goTo(
          viewerController.value,
          duration: Duration.zero,
        ),
      );
    }
  }

  /// Bound a native move independently of the raster deadline. Cancellation
  /// and commit eligibility are guarded by the caller's generation, not time.
  Future<void> _awaitViewerMove(Future<void> move, Duration duration) =>
      move.timeout(
        duration + const Duration(milliseconds: 500),
        onTimeout: () {},
      );

  Future<bool> _animatePageTransitionTo(
    double target,
    Curve curve,
    int generation,
  ) async {
    try {
      await pageTransitionController
          .animateTo(target, duration: _fadeHalfDuration, curve: curve)
          .orCancel;
    } on TickerCanceled {
      return false;
    }
    return _turnIsCurrent(generation);
  }

  // --- Page turn -----------------------------------------------------------

  /// Rasterises what the turn needs, peels the leaf, then commits the page.
  Future<bool> _runPageCurl(int target, int generation) async {
    // Rendering runs on pdfium's worker, so it gets a deadline of its own.
    await _rasterisePagesFor(target).timeout(
      _pageRasterDeadline,
      onTimeout: () {},
    );
    if (!_turnIsCurrent(generation)) {
      return true;
    }
    final scene = _buildPageTurnScene(target, leadFromBottom: true);
    if (scene == null) {
      return false;
    }
    pageTransitionController.value = 0;
    setState(() => pageTurnScene = scene);
    try {
      await pageTransitionController
          .animateTo(
            1,
            duration: pageTurnDuration,
            curve: Curves.easeInOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      if (_turnIsCurrent(generation)) _clearPageTurnScene();
      return true;
    }
    if (_turnIsCurrent(generation)) await _commitPageTurn(target, generation);
    return true;
  }

  /// Swaps the live viewer to [target] and keeps the painted leaf up for one
  /// more frame so pdfrx has the new page on screen before it disappears.
  Future<void> _commitPageTurn(int target, int generation) async {
    if (!_turnIsCurrent(generation)) {
      return;
    }
    await _moveViewToPage(target, Duration.zero);
    if (!_turnIsCurrent(generation)) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    if (!_turnIsCurrent(generation)) return;
    _clearPageTurnScene();
    unawaited(_rasterisePagesFor(target));
  }

  void _clearPageTurnScene() {
    turnDragOrigin = null;
    turnDragTarget = null;
    _dragGeneration = null;
    if (mounted && pageTurnScene != null) {
      setState(() {
        _disposeSceneImages(pageTurnScene);
        pageTurnScene = null;
      });
    }
    pageTransitionController.value = 0;
  }

  void _disposeSceneImages(PageTurnScene? scene) {
    if (scene == null) return;
    scene.leafFront.dispose();
    scene.leafBack?.dispose();
    for (final page in scene.underlays) {
      page.image.dispose();
    }
  }

  /// Every page the turn between [currentPage] and [target] can show.
  List<int> _pagesForTurn(int target) {
    final pages = <int>{currentPage, target};
    if (layoutMode == PdfPageLayoutMode.facing) {
      final here = facingPartnerPage(currentPage, pageCount);
      final there = facingPartnerPage(target, pageCount);
      if (here != null) pages.add(here);
      if (there != null) pages.add(there);
    }
    return pages.where((page) => page >= 1 && page <= pageCount).toList();
  }

  Future<void> _rasterisePagesFor(int target) async {
    final doc = document;
    if (doc == null || !viewerController.isReady) {
      return;
    }
    final pages = _pagesForTurn(target);
    final width = _rasterWidth(pages);
    if (width <= 0) {
      return;
    }
    await _prefetchRaster(doc, pages, width);
  }

  /// Warms the neighbours so an interactive drag can start on the first frame.
  void _prefetchTurnPages() {
    if (_reducedMotion || !pageTransition.curlsPaper || !viewerReady) {
      return;
    }
    final doc = document;
    if (doc == null) {
      return;
    }
    final pages = <int>{
      ..._pagesForTurn(_forwardPage),
      ..._pagesForTurn(_backwardPage),
    };
    final width = _rasterWidth(pages);
    if (width <= 0) return;
    unawaited(_prefetchRaster(doc, pages, width));
  }

  Future<void> _prefetchRaster(
    PdfDocument expected,
    Iterable<int> pages,
    double width,
  ) async {
    // Retain the loaded handle while pdfium is rendering it. A replaced ref
    // must not release the native document under an in-flight page render.
    final ref = documentRef;
    await ref.resolveListenable().useDocument<void>(
      (loaded) async {
        if (!mounted ||
            _disposing ||
            !identical(document, expected) ||
            !identical(loaded, expected)) {
          return;
        }
        await pageRaster.prefetch(loaded, pages, targetWidth: width);
      },
      ensureLoaded: false,
    );
  }

  double _rasterWidth(Iterable<int> pages) {
    try {
      final layouts = viewerController.layout.pageLayouts;
      final width = pages.fold<double>(
        0,
        (width, page) => math.max(width, layouts[page - 1].width),
      );
      return PdfPageRasterCache.rasterWidthFor(
        onScreenWidth: width * viewerController.currentZoom,
        devicePixelRatio: devicePixelRatio,
      );
    } on Object {
      return 0;
    }
  }

  /// Turns the current on-screen geometry into a scene the painter can draw.
  ///
  /// Returns null when a page is still missing from the raster cache, when the
  /// canvas is rotated, or when the viewer has not settled: the caller then
  /// falls back to a plain move.
  PageTurnScene? _buildPageTurnScene(
    int target, {
    required bool leadFromBottom,
  }) {
    if (!viewerReady || quarterTurns != 0 || target == currentPage) {
      return null;
    }
    final Rect leafRect;
    final int leafPage;
    final int backPage;
    final int revealedPage;
    final int? companionPage;
    final Rect? companionRect;
    final double? spine;
    final forward = target > currentPage;

    try {
      final layouts = viewerController.layout.pageLayouts;
      final partner = layoutMode == PdfPageLayoutMode.facing
          ? facingPartnerPage(currentPage, pageCount)
          : null;

      if (partner != null) {
        // A real spread: the outer edge of one page lifts and the whole leaf
        // swings around the gutter between the two.
        final left = math.min(currentPage, partner);
        final right = math.max(currentPage, partner);
        final destination = target;
        final destinationPartner =
            facingPartnerPage(destination, pageCount) ?? destination;
        final destinationLeft = math.min(destination, destinationPartner);
        final destinationRight = math.max(destination, destinationPartner);

        leafPage = forward ? right : left;
        backPage = forward ? destinationLeft : destinationRight;
        revealedPage = forward ? destinationRight : destinationLeft;
        companionPage = forward ? left : right;
        leafRect = _documentRectToStage(layouts[leafPage - 1]);
        companionRect = _documentRectToStage(layouts[companionPage - 1]);
        spine = forward
            ? (leafRect.left + companionRect.right) / 2
            : (leafRect.right + companionRect.left) / 2;
      } else {
        leafPage = currentPage;
        backPage = -1;
        revealedPage = target;
        companionPage = null;
        companionRect = null;
        spine = null;
        leafRect = _documentRectToStage(layouts[currentPage - 1]);
      }
    } on Object {
      return null;
    }

    if (leafRect.width < 8 || leafRect.height < 8) {
      return null;
    }

    final minWidth = PdfPageRasterCache.rasterWidthFor(
      onScreenWidth: leafRect.width,
      devicePixelRatio: devicePixelRatio,
    );
    final front = pageRaster.peek(leafPage, minWidth: minWidth);
    final revealed = pageRaster.peek(revealedPage, minWidth: minWidth);
    if (front == null || revealed == null) {
      return null;
    }
    final back =
        backPage > 0 ? pageRaster.peek(backPage, minWidth: minWidth) : null;
    if (backPage > 0 && back == null) {
      return null;
    }
    final companion = companionPage == null
        ? null
        : pageRaster.peek(companionPage, minWidth: minWidth);
    if (companionPage != null && (companion == null || companionRect == null)) {
      return null;
    }

    final palette = PdfPreviewPalette.of(context);
    return PageTurnScene(
      background: palette.canvas,
      paper: const Color(0xFFFBF9F5),
      paperEdge: const Color(0xFF9A9287),
      underlays: [
        // The page uncovered by the leaf sits in the leaf's own slot.
        PageTurnStaticPage(
          image: revealed.clone(),
          rect: leafRect,
          outerOnRight: forward,
        ),
        if (companion != null && companionRect != null)
          PageTurnStaticPage(
            image: companion.clone(),
            rect: companionRect,
            outerOnRight: !forward,
          ),
      ],
      // Cache upgrades/eviction can run during the final commit frame. Own
      // lightweight handles until the scene is removed, not the cache's ones.
      leafFront: front.clone(),
      leafBack: back?.clone(),
      leafRect: leafRect,
      pivotOnLeft: forward,
      leadFromBottom: leadFromBottom,
      fadeLeafAtEnd: companionPage == null,
      spineCenter: spine,
    );
  }

  /// Document coordinates to the stage box the leaf is painted in.
  Rect _documentRectToStage(Rect rect) {
    final matrix = viewerController.value;
    final zoom = viewerController.currentZoom;
    final translation = matrix.getTranslation();
    return Rect.fromLTWH(
      rect.left * zoom + translation.x,
      rect.top * zoom + translation.y,
      rect.width * zoom,
      rect.height * zoom,
    );
  }

  void _handleTurnDragStart(
    DragStartDetails details, {
    required bool forward,
  }) {
    if (_reducedMotion ||
        pageTurnScene != null ||
        pageTurnInProgress ||
        !viewerReady) {
      return;
    }
    final target = forward ? _forwardPage : _backwardPage;
    if (target == currentPage) {
      return;
    }
    final box = context.findRenderObject();
    final height = box is RenderBox && box.hasSize ? box.size.height : 0.0;
    final scene = _buildPageTurnScene(
      target,
      leadFromBottom: height <= 0 || details.localPosition.dy > height / 2,
    );
    if (scene == null) {
      _prefetchTurnPages();
      return;
    }
    wheelScrollPhysics.stop();
    _revealChrome();
    turnDragOrigin = details.globalPosition.dx;
    turnDragForward = forward;
    turnDragTarget = target;
    _dragGeneration = ++_pageTurnGeneration;
    _setPageTurnBusy(true, _dragGeneration!);
    pageTransitionController.value = 0;
    setState(() => pageTurnScene = scene);
  }

  void _handleTurnDragUpdate(DragUpdateDetails details) {
    final origin = turnDragOrigin;
    final scene = pageTurnScene;
    if (origin == null || scene == null) {
      return;
    }
    if (_dragGeneration case final generation?) {
      _setPageTurnBusy(true, generation);
    }
    final travelled = turnDragForward
        ? origin - details.globalPosition.dx
        : details.globalPosition.dx - origin;
    final distance = math.max(scene.leafRect.width, 1.0);
    pageTransitionController.value = (travelled / distance).clamp(0.0, 1.0);
  }

  void _handleTurnDragEnd(DragEndDetails details) {
    final target = turnDragTarget;
    if (target == null || pageTurnScene == null) {
      return;
    }
    final velocity =
        details.velocity.pixelsPerSecond.dx * (turnDragForward ? -1 : 1);
    final progress = pageTransitionController.value;
    final commit = progress >= _pageTurnCommitFraction ||
        velocity > _pageTurnCommitVelocity;
    unawaited(_settlePageTurn(target: target, commit: commit));
  }

  void _handleTurnDragCancel() {
    if (pageTurnScene == null || turnDragTarget == null) {
      return;
    }
    unawaited(_settlePageTurn(target: turnDragTarget!, commit: false));
  }

  Future<void> _settlePageTurn({
    required int target,
    required bool commit,
  }) async {
    final generation = _dragGeneration;
    if (generation == null || !_turnIsCurrent(generation)) return;
    turnDragOrigin = null;
    final from = pageTransitionController.value;
    final remaining = commit ? 1 - from : from;
    final duration = Duration(
      milliseconds: (pageTurnDuration.inMilliseconds * remaining)
          .clamp(90, pageTurnDuration.inMilliseconds)
          .round(),
    );
    _setPageTurnBusy(true, generation);
    try {
      await pageTransitionController
          .animateTo(
            commit ? 1 : 0,
            duration: duration,
            curve: Curves.easeOutCubic,
          )
          .orCancel;
      if (!_turnIsCurrent(generation)) return;
      if (commit) {
        await _commitPageTurn(target, generation);
      } else {
        _clearPageTurnScene();
      }
    } on TickerCanceled {
      if (_turnIsCurrent(generation)) _clearPageTurnScene();
    } finally {
      _setPageTurnBusy(false, generation);
    }
  }

  /// Side by side reading advances a spread at a time; every other layout
  /// advances one page.
  int get _forwardPage => layoutMode == PdfPageLayoutMode.facing
      ? nextFacingPage(currentPage, pageCount)
      : currentPage + 1;

  int get _backwardPage => layoutMode == PdfPageLayoutMode.facing
      ? previousFacingPage(currentPage)
      : currentPage - 1;

  void _previousPage() => _goToPage(_backwardPage);

  void _nextPage() => _goToPage(_forwardPage);

  void _firstPage() => _goToPage(1);

  void _lastPage() => _goToPage(pageCount);

  void _zoomIn() {
    if (viewerReady) {
      wheelScrollPhysics.stop();
      unawaited(viewerController.zoomUp());
    }
  }

  void _zoomOut() {
    if (viewerReady) {
      wheelScrollPhysics.stop();
      unawaited(viewerController.zoomDown());
    }
  }

  void _fitWidth() {
    if (!viewerReady) {
      return;
    }
    wheelScrollPhysics.stop();
    unawaited(
      viewerController.goTo(
        viewerController.calcMatrixFitWidthForPage(
          pageNumber: currentPage,
        ),
      ),
    );
  }

  void _fitPage() {
    if (!viewerReady) {
      return;
    }
    wheelScrollPhysics.stop();
    unawaited(
      viewerController.goTo(
        viewerController.calcMatrixForFit(pageNumber: currentPage),
      ),
    );
  }

  void _actualSize() {
    if (viewerReady) {
      wheelScrollPhysics.stop();
      unawaited(
        viewerController.setZoom(viewerController.centerPosition, 1),
      );
    }
  }

  void _rotate() {
    if (!viewerReady) {
      return;
    }
    wheelScrollPhysics.stop();
    setState(() {
      _cancelPageTurn();
      quarterTurns = (quarterTurns + 1) % 4;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && viewerController.isReady) {
        _fitPage();
      }
    });
  }

  void _toggleSidebar(PdfSidebarMode mode) {
    setState(() {
      sidebarMode = sidebarMode == mode ? PdfSidebarMode.none : mode;
    });
    _revealChrome();
  }

  void _closeSidebar() {
    if (sidebarMode != PdfSidebarMode.none) {
      setState(() => sidebarMode = PdfSidebarMode.none);
      _scheduleChromeHide();
    }
  }

  /// The chrome is pinned whenever hiding it would take away something the
  /// reader is in the middle of using.
  bool get _chromePinned =>
      !widget.fullscreen ||
      widget.bare ||
      !viewerReady ||
      searchVisible ||
      toolbarHovered ||
      openToolbarMenus > 0 ||
      sidebarMode != PdfSidebarMode.none;

  void _setToolbarMenuVisible(bool visible) {
    if (!mounted || !widget.fullscreen) return;
    setState(() {
      openToolbarMenus = math.max(0, openToolbarMenus + (visible ? 1 : -1));
      if (visible) chromeVisible = true;
    });
    // AppMenu holds the embedded preview region itself. Fullscreen's opt-in
    // three-second timer is separate and must not hide the menu's anchor.
    if (visible) {
      chromeHideTimer?.cancel();
    } else {
      _scheduleChromeHide();
    }
  }

  void _handleChromeHover(PointerHoverEvent event) {
    if (!widget.fullscreen || widget.bare) return;
    final now = DateTime.now();
    if (chromeVisible &&
        now.difference(chromeLastKeptAlive) < _chromeRevealThrottle) {
      return;
    }
    chromeLastKeptAlive = now;
    _revealChrome();
  }

  void _revealChrome() {
    if (!widget.fullscreen || widget.bare) return;
    if (!chromeVisible) {
      setState(() => chromeVisible = true);
    }
    _scheduleChromeHide();
  }

  void _scheduleChromeHide() {
    chromeHideTimer?.cancel();
    // Persistent file options supersede the old immersive preference. Do not
    // rewrite a stored choice or run a timer for an invisible state change.
    if (!widget.bare) return;
    if (!autoHideToolbar || _chromePinned) {
      return;
    }
    chromeHideTimer = Timer(_chromeIdleDelay, () {
      if (!mounted || !autoHideToolbar || _chromePinned || !chromeVisible) {
        return;
      }
      setState(() => chromeVisible = false);
    });
  }

  void _setToolbarHovered(bool value) {
    if (!widget.fullscreen || toolbarHovered == value) {
      return;
    }
    setState(() => toolbarHovered = value);
    if (value) {
      chromeHideTimer?.cancel();
    } else {
      _scheduleChromeHide();
    }
  }

  /// Applies a reading mode: the layout and the animation that goes with it.
  void _setViewPreset(PdfViewPreset preset) {
    if (!(widget.canReadFile?.call() ?? true)) return;
    if (layoutMode == preset.layoutMode &&
        pageTransition == preset.transition) {
      return;
    }
    setState(
      () => _readViewSettings({
        ...metadata,
        _layoutModeMetadataKey: preset.layoutMode.name,
        _pageTransitionMetadataKey: preset.transition.name,
      }),
    );
    // One atomic metadata snapshot, never an intermediate layout/animation
    // pair and a second serialized backend write for the same selection.
    widget.onMetadataChanged(Map<String, dynamic>.from(metadata));
  }

  void _readViewSettings(Map<String, dynamic> value) {
    final mode = PdfPageLayoutMode.fromName(value[_layoutModeMetadataKey]);
    final transition =
        PdfPageTransition.fromName(value[_pageTransitionMetadataKey]);
    final layoutChanged = mode != layoutMode;
    final turnChanged = transition != pageTransition;
    if (layoutChanged || turnChanged) _cancelPageTurn();
    metadata = Map<String, dynamic>.from(value);
    layoutMode = mode;
    pageTransition = transition;
    autoHideToolbar = value[_autoHideToolbarMetadataKey] as bool? ?? false;
    if (!autoHideToolbar) {
      chromeHideTimer?.cancel();
      chromeVisible = true;
    }
    if (layoutChanged) {
      _scheduleLayoutView();
    } else if (turnChanged) {
      _prefetchTurnPages();
    }
  }

  void _scheduleLayoutView() {
    final generation = _pageTurnGeneration;
    final page = currentPage;
    // pdfrx caches the page rectangles, so a new layout function only takes
    // effect once the viewer is told to lay out again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_turnIsCurrent(generation)) return;
      viewerController.relayout();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_turnIsCurrent(generation)) return;
        _applyLayoutView(page);
        _prefetchTurnPages();
      });
    });
  }

  /// Frames whatever the new layout treats as one unit, so every mode change
  /// lands on a view that actually shows what changed.
  void _applyLayoutView(int page) {
    if (!mounted || !viewerController.isReady) {
      return;
    }
    // A preset change should be visible immediately, not start another slide
    // while its new geometry is settling.
    unawaited(
      _moveViewToPage(page.clamp(1, pageCount), Duration.zero, fitPage: true),
    );
  }

  /// Side by side reading frames the pair, every other layout frames the page.
  Future<void> _moveViewToPage(
    int target,
    Duration duration, {
    bool fitPage = false,
  }) async {
    final generation = _pageTurnGeneration;
    if (!_turnIsCurrent(generation)) return;
    final spread =
        layoutMode == PdfPageLayoutMode.facing ? _spreadRectFor(target) : null;
    final matrix = spread != null
        ? viewerController.calcMatrixForArea(
            rect: spread,
            anchor: PdfPageAnchor.all,
          )
        : viewerController.calcMatrixForPage(
            pageNumber: target,
            anchor: fitPage
                ? PdfPageAnchor.all
                : target == pageCount
                    ? viewerController.params.pageAnchorEnd
                    : null,
          );
    await _awaitViewerMove(
      // pdfrx goToPage commits its page number even when goTo was cancelled.
      // Use its matrix navigation, then commit only our still-current request.
      viewerController.goTo(matrix, duration: duration),
      duration,
    );
    if (_turnIsCurrent(generation)) {
      viewerController.setCurrentPageNumber(target);
    }
  }

  /// The given page together with the page it faces.
  Rect? _spreadRectFor(int pageNumber) {
    try {
      final layouts = viewerController.layout.pageLayouts;
      final index = pageNumber - 1;
      if (index < 0 || index >= layouts.length) {
        return null;
      }
      var rect = layouts[index];
      final partner = facingPartnerPage(pageNumber, layouts.length);
      if (partner != null) {
        rect = rect.expandToInclude(layouts[partner - 1]);
      }
      return rect.inflate(viewerController.params.margin);
    } on Object {
      return null;
    }
  }

  Future<void> _copySelectedText() async {
    final ranges = selection;
    if (ranges == null) {
      return;
    }
    final text = ranges
        .where((range) => range.isNotEmpty)
        .map((range) => range.text)
        .join('\n')
        .trim();
    if (text.isEmpty) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: text));
      if (mounted) {
        _showMessage('Selected text copied');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Unable to copy the text: $error');
      }
    }
  }

  /// Scanned pages carry no text layer, so the page is rendered and handed to
  /// the same text scanner the image blocks use.
  Future<void> _scanPageText() async {
    final document = this.document;
    if (document == null || ocrInProgress || document.pages.isEmpty) {
      return;
    }
    final pageNumber = currentPage.clamp(1, document.pages.length);
    setState(() => ocrInProgress = true);

    File? temporary;
    try {
      final bytes = await renderPdfPagePng(document.pages[pageNumber - 1]);
      final directory = await getTemporaryDirectory();
      temporary = File(
        p.join(
          directory.path,
          'appflowy-pdf-ocr-${DateTime.now().microsecondsSinceEpoch}.png',
        ),
      );
      await temporary.writeAsBytes(bytes, flush: true);
      if (!mounted) {
        return;
      }
      await showImageOcrOverlay(
        context,
        source: ImageEditorSource(
          url: temporary.path,
          type: CustomImageType.local,
        ),
        name: '${widget.name} · page $pageNumber',
      );
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Unable to scan this page: $error');
      }
    } finally {
      final file = temporary;
      if (file != null) {
        unawaited(file.delete().catchError((_) => file));
      }
      if (mounted) {
        setState(() => ocrInProgress = false);
      }
    }
  }

  void _toggleSearch() => searchVisible ? _closeSearch() : _openSearch();

  void _openSearch() {
    if (!_canSearch) return;
    final request = ++_findFocusRequest;
    if (!searchVisible) {
      setState(() => searchVisible = true);
      _ocrScanRequested = ocrSearchEnabled && ocrIndex?.failure == null;
    }
    _revealChrome();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted &&
          searchVisible &&
          _canSearch &&
          request == _findFocusRequest) {
        searchFocusNode.requestFocus();
        searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: searchController.text.length,
        );
      }
    });
  }

  void _closeSearch({bool restoreFocus = true}) {
    if (!searchVisible) {
      return;
    }
    ++_findFocusRequest;
    ++_queryRevision;
    ++_ocrRequestRevision;
    _ocrScanRequested = false;
    setState(() {
      searchVisible = false;
      searchPatternInvalid = false;
      ocrMatches = const [];
      _searchMatches = const [];
      _searchMatchIndex = -1;
    });
    textSearcher.resetTextSearch();
    searchController.clear();
    ocrIndex?.cancel();
    _invalidateSearch();
    if (restoreFocus && viewerReady) viewerFocusNode.requestFocus();
    _scheduleChromeHide();
  }

  void _search(String query, {bool immediately = false}) {
    ++_queryRevision;
    _searchStartPage = currentPage;
    _searchMatches = const [];
    _searchMatchIndex = -1;
    ocrMatches = const [];
    RegExp? pattern;
    try {
      pattern = buildFindPattern(query, searchOptions);
      searchPatternInvalid = false;
    } on FormatException {
      searchPatternInvalid = true;
    }
    if (pattern == null || !_canSearch || !searchVisible) {
      ++_ocrRequestRevision;
      textSearcher.resetTextSearch();
      ocrIndex?.cancel();
      _ocrScanRequested = ocrSearchEnabled && ocrIndex?.failure == null;
      setState(() {});
      _invalidateSearch();
      return;
    }
    // Always search native text, including in OCR mode. A new query must not
    // hide the normal text in a document with both scanned and textual pages.
    textSearcher.startTextSearch(
      document!,
      documentRef,
      pattern,
      immediately: immediately,
    );
    _searchScannedText(query);
  }

  void _setSearchOptions(FindOptions options) {
    setState(() => searchOptions = options);
    _search(searchController.text);
  }

  void _toggleOcrSearch() {
    if (!_canSearch) return;
    setState(() {
      ocrSearchEnabled = !ocrSearchEnabled;
      _ocrScanRequested = ocrSearchEnabled;
      _autoOcrAttempted = true;
      _autoOcrOptOut = !ocrSearchEnabled;
      // Explicit OCR also covers image content on pages with a text layer.
      _ocrAllPages = true;
    });
    if (!ocrSearchEnabled) {
      ++_ocrRequestRevision;
      ocrIndex?.cancel();
    }
    _searchScannedText(searchController.text);
    _maybeStartOcr();
  }

  void _onTextSearchChanged() {
    if (!mounted || _disposing || !searchVisible || !_canSearch) return;
    _refreshSearchMatches();
    if (!textSearcher.completed ||
        searchPatternInvalid ||
        searchController.text.isEmpty) {
      return;
    }
    if (!ocrSearchEnabled &&
        !_autoOcrAttempted &&
        !_autoOcrOptOut &&
        textSearcher.matches.isEmpty &&
        textSearcher.emptyPages.isNotEmpty) {
      _autoOcrAttempted = true;
      _ocrAllPages = false;
      _ocrScanRequested = true;
      setState(() => ocrSearchEnabled = true);
    }
    _maybeStartOcr();
  }

  void _retryOcrSearch() {
    _ocrScanRequested = true;
    _maybeStartOcr();
  }

  void _maybeStartOcr() {
    if (!_canSearch ||
        !searchVisible ||
        !ocrSearchEnabled ||
        !_ocrScanRequested ||
        searchController.text.isEmpty ||
        searchPatternInvalid ||
        textSearcher.isSearching ||
        (!_ocrAllPages && !textSearcher.completed)) {
      return;
    }
    // Set this before notifying listeners. Typing/rebuilding never queues a
    // second scan, and a failed scan requires an explicit retry.
    _ocrScanRequested = false;
    var index = ocrIndex;
    if (index == null) {
      index = widget.ocrIndexFactory?.call() ?? PdfOcrSearchIndex();
      index.addListener(_onScanned);
      ocrIndex = index;
    }
    if (index.isScanning) return;
    unawaited(
      _scanDocument(
        index,
        document!,
        documentRef,
        currentPage,
        _ocrAllPages ? null : textSearcher.emptyPages.toList(),
        _ocrRequestRevision,
      ),
    );
    _searchScannedText(searchController.text);
  }

  Future<void> _scanDocument(
    PdfOcrSearchIndex index,
    PdfDocument expected,
    PdfDocumentRef ref,
    int startPage,
    List<int>? pages,
    int request,
  ) async {
    // Hold the loaded handle for the scan; never reload/read the original file
    // as a side effect of typing, closing find, or navigating away.
    await ref.resolveListenable().useDocument<void>(
      (loaded) async {
        if (!mounted ||
            _disposing ||
            !searchVisible ||
            !ocrSearchEnabled ||
            request != _ocrRequestRevision ||
            !_canSearch ||
            searchController.text.isEmpty ||
            searchPatternInvalid ||
            !identical(document, expected) ||
            !identical(loaded, expected) ||
            !identical(ocrIndex, index)) {
          return;
        }
        await index.scan(loaded, startPage: startPage, pageNumbers: pages);
      },
      ensureLoaded: false,
    );
  }

  void _onScanned() => _searchScannedText(searchController.text);

  void _searchScannedText(String query) {
    if (!mounted || _disposing || !searchVisible || !_canSearch) return;
    ocrMatches = ocrSearchEnabled && !searchPatternInvalid && query.isNotEmpty
        ? ocrIndex?.search(query, searchOptions) ?? const []
        : const [];
    _refreshSearchMatches();
  }

  void _refreshSearchMatches() {
    final previous = _currentSearchHit;
    final native = textSearcher.matches;
    final matches = [
      ...native,
      for (final match in ocrMatches)
        if (!native.any((hit) => hit.duplicatesOcr(match)))
          _PdfSearchHit.fromOcr(match),
    ]..sort(_PdfSearchHit.compare);
    var selected = previous == null
        ? -1
        : matches.indexWhere((match) => match.sameOccurrence(previous));
    if (selected < 0 && matches.isNotEmpty) {
      selected =
          matches.indexWhere((hit) => hit.pageNumber >= _searchStartPage);
      // Earlier pages arrive first. Do not jump away from the page where Find
      // opened before its matches have even been read. Explicit navigation
      // still selects immediately and is preserved by sameOccurrence above.
      if (selected < 0 && !textSearcher.isSearching) selected = 0;
    }
    setState(() {
      _searchMatches = matches;
      _searchMatchIndex = selected;
    });
    _invalidateSearch();
    if (selected >= 0 &&
        (previous == null || !matches[selected].sameOccurrence(previous))) {
      final revision = _queryRevision;
      final hit = matches[selected];
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted &&
            revision == _queryRevision &&
            searchVisible &&
            _currentSearchHit?.sameOccurrence(hit) == true &&
            _canSearch) {
          _revealSearchHit(hit);
        }
      });
    }
  }

  void _invalidateSearch() {
    if (!_disposing &&
        viewerReady &&
        viewerController.isReady &&
        identical(documentRef.resolveListenable().document, document)) {
      viewerController.invalidate();
    }
  }

  void _nextSearchMatch() => _moveToSearchMatch(forward: true);

  void _previousSearchMatch() => _moveToSearchMatch(forward: false);

  void _moveToSearchMatch({required bool forward}) {
    if (!_canSearch || _searchMatches.isEmpty) return;
    setState(
      () => _searchMatchIndex = _searchMatchIndex < 0
          ? (forward ? 0 : _searchMatches.length - 1)
          : (_searchMatchIndex + (forward ? 1 : -1) + _searchMatches.length) %
              _searchMatches.length,
    );
    _invalidateSearch();
    _revealSearchHit(_currentSearchHit!);
  }

  void _revealSearchHit(_PdfSearchHit hit) {
    if (!_canSearch || !searchVisible) return;
    setState(_cancelPageTurn);
    final pageRect = viewerController.layout.pageLayouts[hit.pageNumber - 1];
    final rect = hit.rectsIn(pageRect).reduce((a, b) => a.expandToInclude(b));
    // Minimal edge reveal can leave only a sliver of this page visible.
    // pdfrx then discards the requested page number and reports its neighbour
    // again. Center the actual occurrence, retaining zoom unless it must fit,
    // and commit synchronously so no old reveal can outlive its query/owner.
    viewerController.value = viewerController.calcMatrixForRect(
      rect,
      zoomMax: viewerController.currentZoom,
      margin: 24,
    );
    viewerController.setCurrentPageNumber(hit.pageNumber);
  }

  Future<void> _copyOcrMatch() async {
    final hit = _currentSearchHit;
    if (!_canSearch ||
        hit == null ||
        !hit.isOcr ||
        hit.text.isEmpty ||
        document?.permissions?.allowsCopying == false) {
      return;
    }
    try {
      await Clipboard.setData(ClipboardData(text: hit.text));
      if (mounted) _showMessage('Selected text copied');
    } on Object catch (error) {
      if (mounted) _showMessage('Unable to copy the text: $error');
    }
  }

  void _paintTextMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) =>
      _paintSearchMatches(canvas, pageRect, page, isOcr: false);

  void _paintOcrMatches(ui.Canvas canvas, Rect pageRect, PdfPage page) =>
      _paintSearchMatches(canvas, pageRect, page, isOcr: true);

  /// Find highlights are ephemeral. They never enter the persisted selection
  /// highlights, including when OCR is used in a read-only PDF.
  void _paintSearchMatches(
    ui.Canvas canvas,
    Rect pageRect,
    PdfPage page, {
    required bool isOcr,
  }) {
    if (!searchVisible || _searchMatches.isEmpty) return;
    final palette = PdfPreviewPalette.of(context);
    for (var index = 0; index < _searchMatches.length; index++) {
      final match = _searchMatches[index];
      if (match.pageNumber != page.pageNumber || match.isOcr != isOcr) {
        continue;
      }
      final paint = Paint()
        ..color = index == _searchMatchIndex
            ? palette.activeSearchMatch
            : palette.searchMatch;
      for (final rect in match.rectsIn(pageRect)) {
        canvas.drawRect(rect, paint);
      }
    }
  }

  void _handleEscape() {
    if (!mounted || ModalRoute.of(context)?.isCurrent == false) return;
    if (searchVisible) {
      _closeSearch();
    } else if (sidebarMode != PdfSidebarMode.none) {
      _closeSidebar();
    } else if (widget.fullscreen) {
      _closeFullscreen();
    }
  }

  void _closeFullscreen() {
    if (!mounted || !widget.fullscreen) return;
    final route = ModalRoute.of(context);
    if (route?.isCurrent == true && route!.navigator!.canPop()) {
      route.navigator!.pop();
    }
  }

  void _toggleFullscreen() {
    if (widget.fullscreen) {
      _closeFullscreen();
      return;
    }
    final host = StandaloneFileScope.forName(context, widget.name);
    if (!(widget.canReadFile?.call() ?? true)) return;
    if (host != null && !host.canRead()) return;
    final name = host?.displayName ?? widget.name;
    final reducedMotion = MediaQuery.disableAnimationsOf(context) ||
        MediaQuery.accessibleNavigationOf(context);
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.68),
        transitionDuration:
            reducedMotion ? Duration.zero : const Duration(milliseconds: 200),
        transitionBuilder: (_, animation, __, child) => reducedMotion
            ? child
            : FadeTransition(
                opacity:
                    animation.drive(CurveTween(curve: Curves.easeOutCubic)),
                child: ScaleTransition(
                  scale: Tween(begin: 0.985, end: 1.0).animate(animation),
                  child: child,
                ),
              ),
        pageBuilder: (_, __, ___) => _PdfFullscreenView(
          file: widget.file,
          name: name,
          metadata: metadata,
          editable: widget.editable,
          sourceDocumentRef: documentRef,
          onMetadataChanged: widget.onMetadataChanged,
          mediaActions: widget.mediaActions,
          ocrIndexFactory: widget.ocrIndexFactory,
          canReadFile: widget.canReadFile,
          canEditFile: widget.canEditFile,
        ),
      ),
    );
  }

  Future<void> _download() async {
    if (!mounted || !(widget.canReadFile?.call() ?? true)) return;
    final host = StandaloneFileScope.forName(context, widget.name);
    if (host != null && !host.canRead()) return;
    final name = host?.displayName ?? widget.name;
    try {
      final saved = await saveMediaBytes(
        bytes: await widget.file.readAsBytes(),
        name: name,
      );
      if (saved && mounted) {
        _showMessage('PDF saved');
      }
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Unable to save PDF: $error');
      }
    }
  }

  Future<void> _print() async {
    if (!canPrint || !(widget.canReadFile?.call() ?? true)) {
      return;
    }
    final host = StandaloneFileScope.forName(context, widget.name);
    if (host != null && !host.canRead()) return;
    try {
      await Printing.layoutPdf(
        name: host?.displayName ?? widget.name,
        onLayout: (_) => widget.file.readAsBytes(),
      );
    } on Object catch (error) {
      if (mounted) {
        _showMessage('Unable to print PDF: $error');
      }
    }
  }

  void _showMessage(String message) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    messenger
      ?..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          duration: const Duration(seconds: 2),
        ),
      );
  }

  void _highlightSelection() {
    final selected = selection;
    if (!widget.editable ||
        !(widget.canEditFile?.call() ?? true) ||
        selected == null ||
        selected.isEmpty) {
      return;
    }
    for (final ranges in selected) {
      highlights.putIfAbsent(ranges.pageNumber, () => []).add(ranges);
    }
    final stored = <Map<String, dynamic>>[
      ...?metadata['highlights'] as List?,
      for (final ranges in selected)
        for (final range in ranges.ranges)
          {
            'page': ranges.pageNumber,
            'start': range.start,
            'end': range.end,
          },
    ];
    _save('highlights', stored);
    viewerController.invalidate();
  }

  Future<void> _restoreHighlights(PdfDocument document) async {
    final stored = metadata['highlights'];
    highlights.clear();
    if (stored is! List) {
      return;
    }
    for (final raw in stored.whereType<Map>()) {
      if (!mounted || !identical(this.document, document)) return;
      final page = raw['page'];
      final start = raw['start'];
      final end = raw['end'];
      if (page is! int || start is! int || end is! int) {
        continue;
      }
      if (page < 1 || page > document.pages.length) {
        continue;
      }
      final text = await document.pages[page - 1].loadText();
      if (!mounted || !identical(this.document, document)) return;
      if (start >= 0 && end > start && end <= text.fullText.length) {
        highlights.putIfAbsent(page, () => []).add(
              PdfTextRanges(
                pageText: text,
                ranges: [PdfTextRange(start: start, end: end)],
              ),
            );
      }
    }
    if (mounted && viewerController.isReady) {
      viewerController.invalidate();
    }
  }

  void _paintHighlights(Canvas canvas, Rect pageRect, PdfPage page) {
    final paint = Paint()..color = const Color(0x73F2C94C);
    for (final ranges in highlights[page.pageNumber] ?? const []) {
      for (final range in ranges.ranges) {
        final textRange = range.toTextRangeWithFragments(ranges.pageText);
        if (textRange != null) {
          canvas.drawRect(
            textRange.bounds.toRectInPageRect(page: page, pageRect: pageRect),
            paint,
          );
        }
      }
    }
  }

  void _save(String key, Object value) {
    setState(() => metadata = {...metadata, key: value});
    widget.onMetadataChanged(metadata);
  }
}

/// pdfrx 1.0.103's interactive searcher publishes before choosing its current
/// match, retains obsolete results during debounce, and can publish a cancelled
/// empty page after loadText. Keep native PdfPageText.allMatches, but own the
/// session, document-scoped cache, pending/error state and cancellation here.
class _PdfPreviewTextSearch extends ChangeNotifier {
  PdfDocument? _document;
  final _text = <int, Future<PdfPageText>>{};
  Timer? _debounce;
  int _generation = 0;
  bool _disposed = false;
  bool isSearching = false;
  bool completed = false;
  double? searchProgress;
  int searchedPages = 0;
  String? failure;
  List<_PdfSearchHit> matches = const [];
  Set<int> emptyPages = {};

  void startTextSearch(
    PdfDocument document,
    PdfDocumentRef ref,
    RegExp pattern, {
    bool immediately = false,
  }) {
    if (_disposed) return;
    _debounce?.cancel();
    final generation = ++_generation;
    if (!identical(_document, document)) {
      _document = document;
      _text.clear();
    }
    matches = const [];
    emptyPages = {};
    failure = null;
    completed = false;
    isSearching = true; // Includes debounce and the first pending page.
    searchProgress = null;
    searchedPages = 0;
    notifyListeners();
    void run() => unawaited(_search(document, ref, pattern, generation));
    if (immediately) {
      run();
    } else {
      _debounce = Timer(const Duration(milliseconds: 350), run);
    }
  }

  Future<void> _search(
    PdfDocument document,
    PdfDocumentRef ref,
    RegExp pattern,
    int generation,
  ) async {
    bool current() =>
        !_disposed &&
        generation == _generation &&
        identical(_document, document) &&
        identical(ref.resolveListenable().document, document);
    if (!current()) return;
    try {
      await ref.resolveListenable().useDocument<void>(
        (loaded) async {
          if (!current() || !identical(loaded, document)) return;
          final found = <_PdfSearchHit>[];
          for (final page in document.pages) {
            if (!current()) return;
            final text = await (_text[page.pageNumber] ??= page.loadText());
            if (!current()) return;
            if (text.fullText.trim().isEmpty) emptyPages.add(page.pageNumber);
            // A RegExp carries case/whole-word/literal/multiline options itself.
            await for (final match in text.allMatches(pattern)) {
              if (!current()) return;
              found.add(_PdfSearchHit.fromNative(match, text, page));
            }
            // Empty streams do not enter the loop above. Check cancellation
            // again before publishing even an empty page's result.
            if (!current()) return;
            matches = List.unmodifiable(found);
            searchedPages++;
            searchProgress = searchedPages / document.pages.length;
            notifyListeners();
          }
          if (!current()) return;
          isSearching = false;
          completed = true;
          notifyListeners();
        },
        ensureLoaded: false,
      );
    } on Object {
      if (!current()) return;
      _text.clear(); // Do not cache failed loadText futures across a retry.
      isSearching = false;
      failure = 'Text search could not finish. Try the query again.';
      notifyListeners();
    }
  }

  void resetTextSearch() {
    if (_disposed) return;
    ++_generation;
    _debounce?.cancel();
    matches = const [];
    emptyPages = {};
    isSearching = false;
    completed = false;
    failure = null;
    searchProgress = null;
    searchedPages = 0;
    notifyListeners();
  }

  void forgetDocument() {
    _document = null;
    _text.clear();
    resetTextSearch();
  }

  @override
  void dispose() {
    _disposed = true;
    ++_generation;
    _debounce?.cancel();
    _text.clear();
    _document = null;
    matches = const [];
    super.dispose();
  }
}

class _PdfSearchHit {
  const _PdfSearchHit({
    required this.pageNumber,
    required this.start,
    required this.text,
    required this.rects,
    required this.isOcr,
  });

  factory _PdfSearchHit.fromNative(
    PdfTextRangeWithFragments match,
    PdfPageText text,
    PdfPage page,
  ) {
    final start = match.fragments.first.index + match.start;
    final end = match.fragments.last.index + match.end;
    final bounds = match.bounds.toRect(page: page);
    return _PdfSearchHit(
      pageNumber: page.pageNumber,
      start: start,
      text: text.fullText.substring(start, end),
      rects: [
        Rect.fromLTRB(
          bounds.left / page.width,
          bounds.top / page.height,
          bounds.right / page.width,
          bounds.bottom / page.height,
        ),
      ],
      isOcr: false,
    );
  }

  factory _PdfSearchHit.fromOcr(PdfOcrMatch match) => _PdfSearchHit(
        pageNumber: match.pageNumber,
        start: match.start,
        text: match.text,
        rects: match.rects,
        isOcr: true,
      );

  final int pageNumber;
  final int start;
  final String text;
  final List<Rect> rects;
  final bool isOcr;

  bool sameOccurrence(_PdfSearchHit other) =>
      pageNumber == other.pageNumber &&
      start == other.start &&
      isOcr == other.isOcr &&
      text == other.text;

  bool duplicatesOcr(PdfOcrMatch other) {
    if (pageNumber != other.pageNumber ||
        text.toLowerCase() != other.text.toLowerCase()) {
      return false;
    }
    return rects.any(
      (rect) => other.rects.any((scanned) {
        final overlap = rect.intersect(scanned);
        return !overlap.isEmpty &&
            overlap.width * overlap.height >=
                math.min(
                      rect.width * rect.height,
                      scanned.width * scanned.height,
                    ) *
                    0.5;
      }),
    );
  }

  Iterable<Rect> rectsIn(Rect page) => rects.map(
        (rect) => Rect.fromLTWH(
          page.left + rect.left * page.width,
          page.top + rect.top * page.height,
          rect.width * page.width,
          rect.height * page.height,
        ),
      );

  static int compare(_PdfSearchHit a, _PdfSearchHit b) {
    var order = a.pageNumber.compareTo(b.pageNumber);
    if (order == 0) order = a.rects.first.top.compareTo(b.rects.first.top);
    if (order == 0) order = a.rects.first.left.compareTo(b.rects.first.left);
    if (order == 0) order = a.start.compareTo(b.start);
    return order;
  }
}

class _PdfScrollThumb extends StatefulWidget {
  const _PdfScrollThumb({
    required this.size,
    required this.page,
    required this.visible,
  });

  final Size size;
  final int page;
  final ValueListenable<bool> visible;

  @override
  State<_PdfScrollThumb> createState() => _PdfScrollThumbState();
}

class _PdfScrollThumbState extends State<_PdfScrollThumb> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return MouseRegion(
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: ValueListenableBuilder<bool>(
        valueListenable: widget.visible,
        builder: (context, visible, child) => AnimatedOpacity(
          opacity: visible || hovered ? 1 : 0,
          duration: _scrollThumbFadeDuration,
          curve: Curves.easeOutCubic,
          child: child,
        ),
        child: Container(
          width: widget.size.width,
          height: widget.size.height,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: palette.chrome,
            borderRadius: BorderRadius.circular(9),
            boxShadow: [
              BoxShadow(
                color: palette.chromeShadow,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Text(
            '${widget.page}',
            style: TextStyle(
              color: palette.textSecondary,
              fontFamily: 'Geist Mono',
              fontFamilyFallback: const ['RobotoMono', 'monospace'],
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ),
      ),
    );
  }
}

class _PdfLoadingSkeleton extends StatefulWidget {
  const _PdfLoadingSkeleton();

  @override
  State<_PdfLoadingSkeleton> createState() => _PdfLoadingSkeletonState();
}

class _PdfLoadingSkeletonState extends State<_PdfLoadingSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Semantics(
      label: 'Loading PDF document',
      liveRegion: true,
      child: AnimatedBuilder(
        animation: animation,
        builder: (_, __) => Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 410),
              child: AspectRatio(
                aspectRatio: 0.74,
                child: Opacity(
                  opacity: 0.52 + animation.value * 0.28,
                  child: Container(
                    padding: const EdgeInsets.fromLTRB(30, 36, 30, 24),
                    decoration: BoxDecoration(
                      color: palette.control,
                      borderRadius: BorderRadius.circular(7),
                      boxShadow: [
                        BoxShadow(
                          color: palette.pageShadow,
                          blurRadius: 18,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _SkeletonLine(widthFactor: 0.58, palette: palette),
                        const SizedBox(height: 20),
                        _SkeletonLine(widthFactor: 1, palette: palette),
                        const SizedBox(height: 9),
                        _SkeletonLine(widthFactor: 0.92, palette: palette),
                        const SizedBox(height: 9),
                        _SkeletonLine(widthFactor: 0.76, palette: palette),
                        const Spacer(),
                        Align(
                          child: SizedBox.square(
                            dimension: 18,
                            child: CircularProgressIndicator(
                              strokeWidth: 1.5,
                              color: palette.accent,
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
        ),
      ),
    );
  }
}

class _SkeletonLine extends StatelessWidget {
  const _SkeletonLine({required this.widthFactor, required this.palette});

  final double widthFactor;
  final PdfPreviewPalette palette;

  @override
  Widget build(BuildContext context) {
    return FractionallySizedBox(
      widthFactor: widthFactor,
      child: Container(
        height: 8,
        decoration: BoxDecoration(
          color: palette.border,
          borderRadius: BorderRadius.circular(99),
        ),
      ),
    );
  }
}

class _PdfCanvasError extends StatelessWidget {
  const _PdfCanvasError({
    required this.message,
    this.locked = false,
    this.onUnlock,
  });

  final String message;

  /// Whether the document is simply locked rather than broken.
  final bool locked;
  final VoidCallback? onUnlock;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              locked ? Icons.lock_rounded : Icons.error_outline_rounded,
              size: 28,
              color: palette.icon,
            ),
            const SizedBox(height: 10),
            Text(
              locked
                  ? LocaleKeys.document_plugins_pdf_locked.tr()
                  : 'Unable to render this PDF',
              style: TextStyle(
                color: palette.textPrimary,
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              locked
                  ? LocaleKeys.document_plugins_pdf_lockedBody.tr()
                  : message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontFamily: 'Inter',
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
            if (onUnlock != null) ...[
              const SizedBox(height: 14),
              FilledButton.tonal(
                onPressed: onUnlock,
                child: Text(LocaleKeys.document_plugins_pdf_unlock.tr()),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PdfFullscreenView extends StatelessWidget {
  const _PdfFullscreenView({
    required this.file,
    required this.name,
    required this.metadata,
    required this.editable,
    required this.sourceDocumentRef,
    required this.onMetadataChanged,
    required this.mediaActions,
    this.ocrIndexFactory,
    this.canReadFile,
    this.canEditFile,
  });

  final File file;
  final String name;
  final Map<String, dynamic> metadata;
  final bool editable;
  final PdfDocumentRef sourceDocumentRef;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final MediaActionService mediaActions;
  final PdfOcrSearchIndex Function()? ocrIndexFactory;
  final bool Function()? canReadFile;
  final bool Function()? canEditFile;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: ContextualFindScope(
          findInControls: true,
          child: PdfPreview(
            key: ValueKey('fullscreen-${file.path}'),
            file: file,
            name: name,
            metadata: metadata,
            editable: editable,
            fullscreen: true,
            sourceDocumentRef: sourceDocumentRef,
            onMetadataChanged: onMetadataChanged,
            mediaActions: mediaActions,
            ocrIndexFactory: ocrIndexFactory,
            canReadFile: canReadFile,
            canEditFile: canEditFile,
          ),
        ),
      ),
    );
  }
}

enum _PdfOverflowAction {
  copyText,
  scanText,
  highlight,
  fitWidth,
  fitPage,
  actualSize,
  rotate,
  download,
  print,
}
