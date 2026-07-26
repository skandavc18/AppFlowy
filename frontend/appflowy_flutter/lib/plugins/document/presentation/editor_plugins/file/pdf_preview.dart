import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/core/helpers/url_launcher.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:printing/printing.dart';

import 'pdf_preview_sidebar.dart';
import 'pdf_preview_scroll_physics.dart';
import 'pdf_preview_theme.dart';
import 'pdf_preview_toolbar.dart';

/// Keeps the PDF scroll thumb on screen only while the document is moving.
const _scrollThumbIdleDelay = Duration(milliseconds: 700);
const _scrollThumbFadeDuration = Duration(milliseconds: 160);

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

  bool get canPrint =>
      viewerReady && document?.permissions?.allowsPrinting != false;

  @override
  void initState() {
    super.initState();
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
    viewerController.removeListener(_handleViewerMoved);
    scrollThumbVisible.dispose();
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
            child: ColoredBox(
              color: palette.canvas,
              child: Column(
                children: [
                  DocumentViewportHeader(identity: _documentIdentity()),
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

  Widget _buildViewerBody(bool dockSidebar) {
    final viewer = RepaintBoundary(
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: viewerFocusNode.requestFocus,
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
          Expanded(child: viewer),
        ],
      );
    }

    final sidebarVisible = sidebarMode != PdfSidebarMode.none;
    return Stack(
      children: [
        Positioned.fill(child: viewer),
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

  Widget _buildSidebar() => PdfPreviewSidebar(
        mode: sidebarMode == PdfSidebarMode.none
            ? PdfSidebarMode.thumbnails
            : sidebarMode,
        document: document,
        currentPage: currentPage,
        outline: outline,
        outlineLoading: outlineLoading,
        onPageSelected: _goToPage,
        onDestinationSelected: (destination) {
          unawaited(viewerController.goToDest(destination));
        },
        onClose: _closeSidebar,
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
      maxImageBytesCachedOnMemory: 96 * 1024 * 1024,
      horizontalCacheExtent: 0.65,
      verticalCacheExtent: 1.25,
      enableTextSelection: true,
      scrollByMouseWheel: 0,
      onInteractionStart: (_) => wheelScrollPhysics.stop(),
      matchTextColor: palette.searchMatch,
      activeMatchTextColor: palette.activeSearchMatch,
      pageDropShadow: BoxShadow(
        color: palette.pageShadow,
        blurRadius: 14,
        spreadRadius: 1,
        offset: const Offset(0, 5),
      ),
      onPageChanged: (page) {
        if (page != null && page != currentPage && mounted) {
          setState(() => currentPage = page);
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
      pageOverlaysBuilder: (_, __, ___) => [
        IgnorePointer(
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(4),
              border: Border.all(
                color: palette.border.withValues(alpha: 0.62),
              ),
            ),
          ),
        ),
      ],
      pagePaintCallbacks: [
        textSearcher.pageTextMatchPaintCallback,
        _paintHighlights,
      ],
    );
  }

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
            _PdfOverflowAction.highlight,
            Icons.highlight_alt_rounded,
            'Highlight selection',
            enabled: widget.editable && selection?.isNotEmpty == true,
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

    wheelScrollPhysics.scroll(event.scrollDelta, kind: event.kind);
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
    wheelScrollPhysics.beginTrackpadPan(event);
  }

  void _handlePointerPanZoomUpdate(PointerPanZoomUpdateEvent event) {
    if (!viewerController.isReady) {
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
    wheelScrollPhysics.endTrackpadPan(event);
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

  void _goToPage(int page) {
    if (!viewerReady || pageCount == 0) {
      return;
    }
    wheelScrollPhysics.stop();
    final target = page.clamp(1, pageCount);
    unawaited(viewerController.goToPage(pageNumber: target));
    viewerFocusNode.requestFocus();
  }

  void _previousPage() => _goToPage(currentPage - 1);

  void _nextPage() => _goToPage(currentPage + 1);

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
  }

  void _closeSidebar() {
    if (sidebarMode != PdfSidebarMode.none) {
      setState(() => sidebarMode = PdfSidebarMode.none);
    }
  }

  void _toggleSearch() => searchVisible ? _closeSearch() : _openSearch();

  void _openSearch() {
    if (!searchVisible) {
      setState(() => searchVisible = true);
    }
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
            border: Border.all(color: palette.border),
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
                      border: Border.all(color: palette.border),
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
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: palette.canvas,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: palette.border),
              boxShadow: [
                BoxShadow(
                  color: palette.chromeShadow,
                  blurRadius: 26,
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(18),
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
      ),
    );
  }
}

enum _PdfOverflowAction {
  highlight,
  fitWidth,
  fitPage,
  actualSize,
  rotate,
  download,
  print,
}
