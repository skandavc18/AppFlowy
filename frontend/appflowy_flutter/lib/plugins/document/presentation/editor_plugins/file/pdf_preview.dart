import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/image_ocr_overlay.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/shared/viewer_card.dart';
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
const _chromeFadeDuration = Duration(milliseconds: 170);

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
    this.fullscreen = false,
    this.sourceDocumentRef,
    this.scrollController,
  });

  final File file;
  final String name;
  final Map<String, dynamic> metadata;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;
  final bool editable;
  final PdfPreviewMenuBuilder? menuBuilder;
  final bool fullscreen;
  final PdfDocumentRef? sourceDocumentRef;
  final PdfPreviewScrollController? scrollController;

  @override
  State<PdfPreview> createState() => _PdfPreviewState();
}

class _PdfPreviewState extends State<PdfPreview> with TickerProviderStateMixin {
  late final PdfDocumentRef documentRef =
      widget.sourceDocumentRef ?? PdfDocumentRefFile(widget.file.path);
  final viewerController = PdfViewerController();
  late final PdfTextSearcher textSearcher = PdfTextSearcher(viewerController);
  final searchController = TextEditingController();
  final searchFocusNode = FocusNode();
  final viewerFocusNode = FocusNode(debugLabel: 'PDF viewer');
  late final Listenable searchListenable =
      Listenable.merge([textSearcher, searchController]);
  late final PdfPreviewScrollPhysics wheelScrollPhysics;

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
  late final AnimationController pageTransitionController =
      AnimationController(vsync: this, duration: _flipHalfDuration);
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

  bool autoHideToolbar = true;
  bool chromeVisible = true;
  bool toolbarHovered = false;
  Timer? chromeHideTimer;
  DateTime chromeLastKeptAlive = DateTime.fromMillisecondsSinceEpoch(0);

  bool ocrInProgress = false;

  bool get canPrint =>
      viewerReady && document?.permissions?.allowsPrinting != false;

  bool get hasTextSelection =>
      selection?.any((range) => range.isNotEmpty) ?? false;

  @override
  void initState() {
    super.initState();
    layoutMode = PdfPageLayoutMode.fromName(metadata[_layoutModeMetadataKey]);
    pageTransition =
        PdfPageTransition.fromName(metadata[_pageTransitionMetadataKey]);
    autoHideToolbar = metadata[_autoHideToolbarMetadataKey] as bool? ?? true;
    wheelScrollPhysics = PdfPreviewScrollPhysics(vsync: this)
      ..attach(viewerController);
    viewerController.addListener(_handleViewerMoved);
    _attachScrollController(widget.scrollController);
  }

  @override
  void didUpdateWidget(covariant PdfPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.scrollController != widget.scrollController) {
      oldWidget.scrollController?.detach(_handleResolvedPointerSignal);
      _attachScrollController(widget.scrollController);
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    devicePixelRatio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    final behavior = ScrollConfiguration.of(context);
    final reducedMotion = MediaQuery.maybeOf(context)?.disableAnimations ??
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations;
    wheelScrollPhysics.configure(
      config: behavior is PremiumScrollBehavior
          ? behavior.config
          : const PremiumScrollPhysicsConfig(),
      kineticEnabled: behavior is PremiumScrollBehavior
          ? behavior.kineticEnabled
          : !reducedMotion,
    );
  }

  @override
  void dispose() {
    widget.scrollController?.detach(_handleResolvedPointerSignal);
    scrollThumbHideTimer?.cancel();
    chromeHideTimer?.cancel();
    pageTurnWheelResetTimer?.cancel();
    pageTurnBusyWatchdog?.cancel();
    viewerController.removeListener(_handleViewerMoved);
    scrollThumbVisible.dispose();
    pageTransitionController.dispose();
    pageRaster.dispose();
    thumbnailScrollController.dispose();
    outlineScrollController.dispose();
    wheelScrollPhysics.dispose();
    textSearcher.dispose();
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
    final child = Theme(
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
                  children: [
                    DocumentViewportHeader(identity: _documentIdentity()),
                    Expanded(
                      child: LayoutBuilder(
                        builder: (context, constraints) =>
                            _buildViewerBody(constraints.maxWidth >= 720),
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
      icon: Icons.picture_as_pdf_outlined,
      subtitle: pages,
    );
  }

  Map<ShortcutActivator, VoidCallback> get _shortcutBindings => {
        const SingleActivator(LogicalKeyboardKey.keyF, control: true):
            _openSearch,
        const SingleActivator(LogicalKeyboardKey.keyF, meta: true): _openSearch,
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
          showDocumentTitle: false,
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
          onToggleSearch: _toggleSearch,
          onRotate: viewerReady ? _rotate : null,
          onDownload: _download,
          onPrint: canPrint ? _print : null,
          onFullscreen: _toggleFullscreen,
          viewMenu: PdfViewOptionsMenu(
            preset: PdfViewPreset.resolve(layoutMode, pageTransition),
            autoHideToolbar: autoHideToolbar,
            enabled: viewerReady,
            onPresetChanged: _setViewPreset,
            onAutoHideToolbarChanged: _setAutoHideToolbar,
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

  /// The vertical room the floating chrome occupies, including its margins.
  double get _chromeHeight =>
      PdfPreviewGeometry.toolbarHeight +
      14 +
      (searchVisible ? PdfPreviewGeometry.searchHeight + 6 : 0);

  /// The toolbar and the search bar float over the canvas so they can slide
  /// away once the reader stops interacting with the document.
  Widget _buildChrome() {
    final visible = chromeVisible || !autoHideToolbar;
    return IgnorePointer(
      ignoring: !visible,
      child: AnimatedSlide(
        duration: _chromeFadeDuration,
        curve: Curves.easeOutCubic,
        offset: visible ? Offset.zero : const Offset(0, -0.7),
        child: AnimatedOpacity(
          duration: _chromeFadeDuration,
          curve: Curves.easeOutCubic,
          opacity: visible ? 1 : 0,
          child: MouseRegion(
            opaque: false,
            onEnter: (_) => _setToolbarHovered(true),
            onExit: (_) => _setToolbarHovered(false),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildToolbar(),
                AnimatedSize(
                  duration: const Duration(milliseconds: 200),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: searchVisible
                      ? AnimatedBuilder(
                          animation: searchListenable,
                          builder: (_, __) => PdfSearchToolbar(
                            controller: searchController,
                            focusNode: searchFocusNode,
                            currentMatch: textSearcher.currentIndex == null
                                ? 0
                                : textSearcher.currentIndex! + 1,
                            matchCount: textSearcher.matches.length,
                            searchProgress: textSearcher.searchProgress,
                            isSearching: textSearcher.isSearching,
                            onChanged: _search,
                            onPrevious: textSearcher.hasMatches
                                ? _previousSearchMatch
                                : null,
                            onNext: textSearcher.hasMatches
                                ? _nextSearchMatch
                                : null,
                            onClose: _closeSearch,
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

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
            controller: viewerController,
            params: _viewerParams(),
          ),
        ),
      ),
    );

    final scene = pageTurnScene;
    final stage = Stack(
      children: [
        Positioned.fill(
          child: AnimatedPadding(
            duration: _chromeFadeDuration,
            curve: Curves.easeOutCubic,
            // The chrome always sits above the pages. Letting it float over
            // them hid whatever was at the top of the document.
            padding: EdgeInsets.only(top: _chromeHeight),
            child: Stack(
              children: [
                Positioned.fill(child: _wrapPageTransition(viewer)),
                // The turning leaf is a sibling of the viewer, never a wrapper
                // around it, so pdfrx is never re-parented mid animation.
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
          ),
        ),
        Positioned(top: 0, left: 0, right: 0, child: _buildChrome()),
      ],
    );

    if (dockSidebar) {
      return Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: sidebarMode == PdfSidebarMode.none ? 0 : 214,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            child: sidebarMode == PdfSidebarMode.none
                ? const SizedBox.shrink()
                : SizedBox(width: 214, child: _buildSidebar()),
          ),
          Expanded(child: stage),
        ],
      );
    }

    final sidebarVisible = sidebarMode != PdfSidebarMode.none;
    return Stack(
      children: [
        Positioned.fill(child: stage),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !sidebarVisible,
            child: AnimatedOpacity(
              duration: const Duration(milliseconds: 200),
              opacity: sidebarVisible ? 1 : 0,
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
          width: 224,
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
    if (!pageTransition.curlsPaper || !viewerReady || quarterTurns != 0) {
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
      loadingBannerBuilder: (_, __, ___) => const _PdfLoadingSkeleton(),
      errorBannerBuilder: (_, error, __, ___) =>
          _PdfCanvasError(message: error.toString()),
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
        textSearcher.pageTextMatchPaintCallback,
        _paintHighlights,
      ],
    );
  }

  PdfPageLayout _layoutPages(List<PdfPage> pages, PdfViewerParams params) =>
      buildPdfPageLayout(pages, params, layoutMode);

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
    return SizedBox.square(
      dimension: 30,
      child: PopupMenuButton<_PdfOverflowAction>(
        key: const ValueKey('pdf-overflow-menu'),
        tooltip: 'More actions',
        enabled: viewerReady || widget.menuBuilder != null,
        onSelected: _handleOverflowAction,
        color: palette.chrome,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(minWidth: 210),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border),
        ),
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 200),
          fixedSize: const WidgetStatePropertyAll(Size.square(30)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              return palette.controlHover;
            }
            return Colors.transparent;
          }),
          splashFactory: NoSplash.splashFactory,
        ),
        padding: EdgeInsets.zero,
        iconSize: 18,
        iconColor: palette.icon,
        icon: const Icon(Icons.more_horiz_rounded),
        itemBuilder: (_) => [
          _popupItem(
            _PdfOverflowAction.copyText,
            Icons.content_copy_outlined,
            'Copy selected text',
            enabled: hasTextSelection,
          ),
          _popupItem(
            _PdfOverflowAction.scanText,
            Icons.document_scanner_outlined,
            ocrInProgress ? 'Scanning page…' : 'Scan text on this page (OCR)',
            enabled: viewerReady && !ocrInProgress,
          ),
          _popupItem(
            _PdfOverflowAction.highlight,
            Icons.highlight_alt_rounded,
            'Highlight selection',
            enabled: widget.editable && hasTextSelection,
          ),
          const PopupMenuDivider(height: 9),
          _popupItem(
            _PdfOverflowAction.fitWidth,
            Icons.fit_screen_outlined,
            'Fit to width',
            enabled: viewerReady,
          ),
          _popupItem(
            _PdfOverflowAction.fitPage,
            Icons.fullscreen_exit_rounded,
            'Fit whole page',
            enabled: viewerReady,
          ),
          _popupItem(
            _PdfOverflowAction.actualSize,
            Icons.filter_1_outlined,
            'Actual size',
            enabled: viewerReady,
          ),
          _popupItem(
            _PdfOverflowAction.rotate,
            Icons.rotate_90_degrees_cw_outlined,
            'Rotate clockwise',
            enabled: viewerReady,
          ),
          const PopupMenuDivider(height: 9),
          _popupItem(
            _PdfOverflowAction.download,
            Icons.download_outlined,
            'Download PDF',
          ),
          _popupItem(
            _PdfOverflowAction.print,
            Icons.print_outlined,
            canPrint ? 'Print PDF' : 'Printing is restricted',
            enabled: canPrint,
          ),
          if (widget.menuBuilder != null) ...[
            const PopupMenuDivider(height: 9),
            PdfPreviewMenuSection(builder: widget.menuBuilder!),
          ],
        ],
      ),
    );
  }

  PopupMenuItem<_PdfOverflowAction> _popupItem(
    _PdfOverflowAction value,
    IconData icon,
    String label, {
    bool enabled = true,
  }) {
    final palette = PdfPreviewPalette.of(context);
    return PopupMenuItem(
      value: value,
      enabled: enabled,
      height: 38,
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: enabled ? palette.icon : palette.iconDisabled,
          ),
          const SizedBox(width: 10),
          Text(
            label,
            style: TextStyle(
              color: enabled ? palette.textPrimary : palette.textSecondary,
              fontFamily: 'Inter',
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
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

  void _onViewerReady(PdfDocument document, PdfViewerController controller) {
    if (!mounted) {
      return;
    }
    setState(() {
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
    if (searchController.text.isNotEmpty) {
      textSearcher.startTextSearch(
        searchController.text,
        searchImmediately: true,
      );
    }
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
    final delta = layoutMode.isHorizontal && event.scrollDelta.dx == 0
        ? Offset(event.scrollDelta.dy, 0)
        : event.scrollDelta;

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
      _accumulatePageTurn(
        layoutMode.isHorizontal
            ? -event.localPanDelta.dx
            : -event.localPanDelta.dy,
      );
      return;
    }

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
    if (!viewerReady || pageCount == 0 || pageTurnInProgress) {
      return;
    }
    final target = page.clamp(1, pageCount);
    wheelScrollPhysics.stop();
    _revealChrome();
    _setPageTurnBusy(true);
    try {
      switch (pageTransition) {
        case PdfPageTransition.none:
          await _moveViewToPage(target, Duration.zero);
          break;
        case PdfPageTransition.slide:
          await _moveViewToPage(target, const Duration(milliseconds: 300));
          break;
        case PdfPageTransition.fade:
          if (!await _animatePageTransitionTo(0.5, Curves.easeInCubic)) {
            return;
          }
          await _moveViewToPage(target, Duration.zero);
          if (!mounted) {
            return;
          }
          await _animatePageTransitionTo(1, Curves.easeOutCubic);
          if (mounted) {
            pageTransitionController.value = 0;
          }
          break;
        case PdfPageTransition.flip:
          if (!await _runPageCurl(target)) {
            // Nothing to rasterise yet, so fall back to a plain move rather
            // than showing no feedback at all.
            await _moveViewToPage(target, const Duration(milliseconds: 300));
          }
          break;
      }
    } finally {
      _setPageTurnBusy(false);
      if (mounted && !searchFocusNode.hasFocus) {
        viewerFocusNode.requestFocus();
      }
    }
  }

  /// Navigation is gated on this flag, so it must never be able to stick.
  /// A watchdog releases it even if an awaited animation is swallowed.
  void _setPageTurnBusy(bool busy) {
    pageTurnBusyWatchdog?.cancel();
    pageTurnInProgress = busy;
    if (!busy) {
      return;
    }
    pageTurnBusyWatchdog = Timer(_pageTurnWatchdog, () {
      pageTurnInProgress = false;
    });
  }

  /// pdfrx animates every move on a single internal controller: starting a new
  /// move cancels the previous one, and a cancelled ticker future never
  /// completes. Waiting on one without a deadline deadlocks the viewer.
  Future<void> _awaitViewerMove(Future<void> move, Duration duration) =>
      move.timeout(
        duration + const Duration(milliseconds: 500),
        onTimeout: () {},
      );

  Future<bool> _animatePageTransitionTo(double target, Curve curve) async {
    try {
      await pageTransitionController
          .animateTo(target, duration: _fadeHalfDuration, curve: curve)
          .orCancel;
    } on TickerCanceled {
      return false;
    }
    return mounted;
  }

  // --- Page turn -----------------------------------------------------------

  /// Rasterises what the turn needs, peels the leaf, then commits the page.
  Future<bool> _runPageCurl(int target) async {
    // Rendering runs on pdfium's worker, so it gets a deadline of its own.
    await _rasterisePagesFor(target).timeout(
      _pageRasterDeadline,
      onTimeout: () {},
    );
    if (!mounted) {
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
      _clearPageTurnScene();
      return true;
    }
    await _commitPageTurn(target);
    return true;
  }

  /// Swaps the live viewer to [target] and keeps the painted leaf up for one
  /// more frame so pdfrx has the new page on screen before it disappears.
  Future<void> _commitPageTurn(int target) async {
    if (!mounted) {
      return;
    }
    await _moveViewToPage(target, Duration.zero);
    if (!mounted) {
      return;
    }
    await WidgetsBinding.instance.endOfFrame;
    _clearPageTurnScene();
    unawaited(_rasterisePagesFor(target));
  }

  void _clearPageTurnScene() {
    turnDragOrigin = null;
    turnDragTarget = null;
    if (mounted && pageTurnScene != null) {
      setState(() => pageTurnScene = null);
    }
    pageTransitionController.value = 0;
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
    final width = _rasterWidth();
    if (width <= 0) {
      return;
    }
    await pageRaster.prefetch(doc, _pagesForTurn(target), targetWidth: width);
  }

  /// Warms the neighbours so an interactive drag can start on the first frame.
  void _prefetchTurnPages() {
    if (!pageTransition.curlsPaper || !viewerReady) {
      return;
    }
    final doc = document;
    if (doc == null) {
      return;
    }
    final width = _rasterWidth();
    if (width <= 0) {
      return;
    }
    final pages = <int>{
      ..._pagesForTurn(_forwardPage),
      ..._pagesForTurn(_backwardPage),
    };
    unawaited(pageRaster.prefetch(doc, pages, targetWidth: width));
  }

  double _rasterWidth() {
    try {
      final rect = viewerController.layout.pageLayouts[currentPage - 1];
      return PdfPageRasterCache.rasterWidthFor(
        onScreenWidth: rect.width * viewerController.currentZoom,
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

    final minWidth = leafRect.width * devicePixelRatio;
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
          image: revealed,
          rect: leafRect,
          outerOnRight: forward,
        ),
        if (companion != null && companionRect != null)
          PageTurnStaticPage(
            image: companion,
            rect: companionRect,
            outerOnRight: !forward,
          ),
      ],
      leafFront: front,
      leafBack: back,
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
    if (pageTurnScene != null || pageTurnInProgress || !viewerReady) {
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
    pageTransitionController.value = 0;
    setState(() => pageTurnScene = scene);
  }

  void _handleTurnDragUpdate(DragUpdateDetails details) {
    final origin = turnDragOrigin;
    final scene = pageTurnScene;
    if (origin == null || scene == null) {
      return;
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
    turnDragOrigin = null;
    final from = pageTransitionController.value;
    final remaining = commit ? 1 - from : from;
    final duration = Duration(
      milliseconds: (pageTurnDuration.inMilliseconds * remaining)
          .clamp(90, pageTurnDuration.inMilliseconds)
          .round(),
    );
    _setPageTurnBusy(true);
    try {
      await pageTransitionController
          .animateTo(
            commit ? 1 : 0,
            duration: duration,
            curve: Curves.easeOutCubic,
          )
          .orCancel;
    } on TickerCanceled {
      _clearPageTurnScene();
      return;
    } finally {
      _setPageTurnBusy(false);
    }
    if (commit) {
      await _commitPageTurn(target);
    } else {
      _clearPageTurnScene();
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
    setState(() => quarterTurns = (quarterTurns + 1) % 4);
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
      !viewerReady ||
      searchVisible ||
      toolbarHovered ||
      sidebarMode != PdfSidebarMode.none;

  void _handleChromeHover(PointerHoverEvent event) {
    final now = DateTime.now();
    if (chromeVisible &&
        now.difference(chromeLastKeptAlive) < _chromeRevealThrottle) {
      return;
    }
    chromeLastKeptAlive = now;
    _revealChrome();
  }

  void _revealChrome() {
    if (!chromeVisible) {
      setState(() => chromeVisible = true);
    }
    _scheduleChromeHide();
  }

  void _scheduleChromeHide() {
    chromeHideTimer?.cancel();
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
    if (toolbarHovered == value) {
      return;
    }
    setState(() => toolbarHovered = value);
    if (value) {
      chromeHideTimer?.cancel();
    } else {
      _scheduleChromeHide();
    }
  }

  void _setAutoHideToolbar(bool value) {
    if (autoHideToolbar == value) {
      return;
    }
    setState(() {
      autoHideToolbar = value;
      if (!value) {
        chromeVisible = true;
      }
    });
    _save(_autoHideToolbarMetadataKey, value);
    if (value) {
      _scheduleChromeHide();
    } else {
      chromeHideTimer?.cancel();
    }
  }

  /// Applies a reading mode: the layout and the animation that goes with it.
  void _setViewPreset(PdfViewPreset preset) {
    _setPageTransition(preset.transition);
    _setLayoutMode(preset.layoutMode);
  }

  void _setLayoutMode(PdfPageLayoutMode mode) {
    if (mode == layoutMode) {
      return;
    }
    wheelScrollPhysics.stop();
    pageTurnWheelTravel = 0;
    setState(() => layoutMode = mode);
    _save(_layoutModeMetadataKey, mode.name);
    // pdfrx caches the page rectangles, so a new layout function only takes
    // effect once the viewer is told to lay out again.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !viewerController.isReady) {
        return;
      }
      viewerController.relayout();
      WidgetsBinding.instance.addPostFrameCallback((_) => _applyLayoutView());
    });
  }

  /// Frames whatever the new layout treats as one unit, so every mode change
  /// lands on a view that actually shows what changed.
  void _applyLayoutView() {
    if (!mounted || !viewerController.isReady) {
      return;
    }
    if (layoutMode == PdfPageLayoutMode.facing) {
      final spread = _spreadRectFor(currentPage);
      if (spread != null) {
        wheelScrollPhysics.stop();
        unawaited(
          viewerController.goTo(
            viewerController.calcMatrixForArea(
              rect: spread,
              anchor: PdfPageAnchor.all,
            ),
            duration: Duration.zero,
          ),
        );
        return;
      }
    }
    _fitPage();
  }

  /// Side by side reading frames the pair, every other layout frames the page.
  Future<void> _moveViewToPage(int target, Duration duration) async {
    if (layoutMode == PdfPageLayoutMode.facing) {
      final spread = _spreadRectFor(target);
      if (spread != null) {
        await _awaitViewerMove(
          viewerController.goTo(
            viewerController.calcMatrixForArea(
              rect: spread,
              anchor: PdfPageAnchor.all,
            ),
            duration: duration,
          ),
          duration,
        );
        return;
      }
    }
    await _awaitViewerMove(
      viewerController.goToPage(pageNumber: target, duration: duration),
      duration,
    );
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

  void _setPageTransition(PdfPageTransition transition) {
    if (transition == pageTransition) {
      return;
    }
    pageTransitionController.value = 0;
    pageTurnWheelTravel = 0;
    setState(() {
      pageTransition = transition;
      pageTurnScene = null;
    });
    _save(_pageTransitionMetadataKey, transition.name);
    _prefetchTurnPages();
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
      final bytes = await _renderPagePng(document.pages[pageNumber - 1]);
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

  Future<Uint8List> _renderPagePng(PdfPage page) async {
    // OCR engines read small print far better at roughly 200 DPI, but the
    // bitmap still has to stay within what the engines accept.
    final scale = math
        .min(3200 / page.width, 3200 / page.height)
        .clamp(1.0, 3.0)
        .toDouble();
    final rendered = await page.render(
      fullWidth: page.width * scale,
      fullHeight: page.height * scale,
      backgroundColor: const Color(0xFFFFFFFF),
    );
    if (rendered == null) {
      throw StateError('the page could not be rendered');
    }

    ui.Image image;
    try {
      image = await rendered.createImage();
    } finally {
      rendered.dispose();
    }

    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (data == null) {
        throw StateError('the page image could not be encoded');
      }
      return data.buffer.asUint8List();
    } finally {
      image.dispose();
    }
  }

  void _toggleSearch() => searchVisible ? _closeSearch() : _openSearch();

  void _openSearch() {
    if (!searchVisible) {
      setState(() => searchVisible = true);
    }
    _revealChrome();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        searchFocusNode.requestFocus();
        searchController.selection = TextSelection(
          baseOffset: 0,
          extentOffset: searchController.text.length,
        );
      }
    });
  }

  void _closeSearch() {
    if (!searchVisible) {
      return;
    }
    textSearcher.resetTextSearch();
    searchController.clear();
    setState(() => searchVisible = false);
    viewerFocusNode.requestFocus();
    _scheduleChromeHide();
  }

  void _search(String query) {
    textSearcher.startTextSearch(query);
  }

  void _nextSearchMatch() {
    unawaited(_moveToSearchMatch(forward: true));
  }

  void _previousSearchMatch() {
    unawaited(_moveToSearchMatch(forward: false));
  }

  Future<void> _moveToSearchMatch({required bool forward}) async {
    if (textSearcher.matches.isEmpty) {
      return;
    }
    wheelScrollPhysics.stop();
    final result = forward
        ? await textSearcher.goToNextMatch()
        : await textSearcher.goToPrevMatch();
    if (result != -1) {
      return;
    }
    await textSearcher.goToMatchOfIndex(
      forward ? 0 : textSearcher.matches.length - 1,
    );
  }

  void _handleEscape() {
    if (searchVisible) {
      _closeSearch();
    } else if (sidebarMode != PdfSidebarMode.none) {
      _closeSidebar();
    } else if (widget.fullscreen) {
      unawaited(Navigator.of(context).maybePop());
    }
  }

  void _toggleFullscreen() {
    if (widget.fullscreen) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    unawaited(
      showGeneralDialog<void>(
        context: context,
        barrierColor: Colors.black.withValues(alpha: 0.68),
        transitionBuilder: (_, animation, __, child) => FadeTransition(
          opacity: CurvedAnimation(
            parent: animation,
            curve: Curves.easeOutCubic,
          ),
          child: ScaleTransition(
            scale: Tween(begin: 0.985, end: 1.0).animate(animation),
            child: child,
          ),
        ),
        pageBuilder: (_, __, ___) => _PdfFullscreenView(
          file: widget.file,
          name: widget.name,
          metadata: metadata,
          editable: widget.editable,
          sourceDocumentRef: documentRef,
          onMetadataChanged: widget.onMetadataChanged,
        ),
      ),
    );
  }

  Future<void> _download() async {
    try {
      final saved = await saveMediaBytes(
        bytes: await widget.file.readAsBytes(),
        name: widget.name,
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
    if (!canPrint) {
      return;
    }
    try {
      await Printing.layoutPdf(
        name: widget.name,
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
    if (!widget.editable || selected == null || selected.isEmpty) {
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

@visibleForTesting
class PdfPreviewMenuSection<T> extends PopupMenuEntry<T> {
  const PdfPreviewMenuSection({
    super.key,
    required this.builder,
    this.estimatedHeight = 188,
  });

  final PdfPreviewMenuBuilder builder;
  final double estimatedHeight;

  @override
  double get height => estimatedHeight;

  @override
  bool represents(T? value) => false;

  @override
  State<PdfPreviewMenuSection<T>> createState() => _PdfMenuSectionState<T>();
}

class _PdfMenuSectionState<T> extends State<PdfPreviewMenuSection<T>> {
  @override
  Widget build(BuildContext context) {
    return widget.builder(
      context,
      () => Navigator.of(context).pop(),
    );
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
  const _PdfCanvasError({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 28, color: palette.icon),
            const SizedBox(height: 10),
            Text(
              'Unable to render this PDF',
              style: TextStyle(
                color: palette.textPrimary,
                fontFamily: 'Inter',
                fontSize: 13,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              message,
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
  });

  final File file;
  final String name;
  final Map<String, dynamic> metadata;
  final bool editable;
  final PdfDocumentRef sourceDocumentRef;
  final ValueChanged<Map<String, dynamic>> onMetadataChanged;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: ViewerCard(
            color: palette.canvas,
            elevation: ViewerCardElevation.raised,
            child: PdfPreview(
              key: ValueKey('fullscreen-${file.path}'),
              file: file,
              name: name,
              metadata: metadata,
              editable: editable,
              fullscreen: true,
              sourceDocumentRef: sourceDocumentRef,
              onMetadataChanged: onMetadataChanged,
            ),
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
