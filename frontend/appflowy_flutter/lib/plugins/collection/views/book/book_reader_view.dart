import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_workspace_surface.dart';
import 'package:appflowy/plugins/collection/views/book/book_chapter_stage.dart';
import 'package:appflowy/plugins/collection/views/book/book_contents_rail.dart';
import 'package:appflowy/plugins/collection/views/book/book_format.dart';
import 'package:appflowy/plugins/collection/views/book/book_note_editor.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_controls.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_settings_panel.dart';
import 'package:appflowy/plugins/collection/views/book/book_views.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/find_replace/contextual_find.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_controller.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// The long-form reading experience: one chapter at a time on a chosen
/// surface, with the contents, bookmarks and notes beside it.
class BookReaderView extends StatefulWidget {
  const BookReaderView({
    super.key,
    required this.collection,
    this.reading,
    this.fullscreen = false,
    this.chapterBuilder,
  });

  final CollectionViewContext collection;

  /// Borrowed rather than owned, so the fullscreen reader carries on from
  /// exactly where the embedded one left off and neither writes over the
  /// other's position.
  final BookReadingController? reading;

  final bool fullscreen;

  /// Optional native-renderer boundary. The reader still owns its production
  /// chrome, chapter selection and borrowed-controller lifetime.
  final Widget Function(
    BuildContext,
    BookChapter,
    BookReaderPalette,
    BookReaderSettings,
  )? chapterBuilder;

  @override
  State<BookReaderView> createState() => _BookReaderViewState();
}

class _BookReaderViewState extends State<BookReaderView>
    with WidgetsBindingObserver {
  late final BookReadingController reading;
  late final bool ownsReading;
  final FocusNode focusNode = FocusNode(debugLabel: 'book-reader');
  final FocusNode chromeFocusNode =
      FocusNode(debugLabel: 'book-reader-controls');
  final GlobalKey settingsAnchor = GlobalKey();
  late final PageController pageController;
  String? trackedChapterId;
  double liveProgress = 0;
  Timer? immersionTimer;
  bool chromeVisible = true;
  int _menuHolds = 0;
  bool get menuOpen => _menuHolds > 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    ownsReading = widget.reading == null;
    reading = widget.reading ??
        BookReadingController(
          initialState: widget.collection.stateFor(bookStateKey),
          onPersist: (state) =>
              widget.collection.onStateChanged(bookStateKey, state),
        );
    widget.collection.explorer.addListener(_syncChapters);
    _syncChapters();
    trackedChapterId = reading.currentChapter?.id;
    pageController = PageController(initialPage: _indexOfCurrentChapter());
    reading.addListener(_onReadingChanged);
    reading.setActive(true);
    if (widget.fullscreen) {
      _wakeChrome();
    }
    unawaited(
      widget.collection.explorer
          .ensureLoaded(widget.collection.collectionView.id),
    );
  }

  int _indexOfCurrentChapter() {
    final id = reading.currentChapter?.id;
    final index =
        reading.readableChapters.indexWhere((chapter) => chapter.id == id);
    return index < 0 ? 0 : index;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    immersionTimer?.cancel();
    widget.collection.explorer.removeListener(_syncChapters);
    reading.removeListener(_onReadingChanged);
    if (ownsReading) {
      reading.dispose();
    } else {
      // The embedded reader owns it and takes the clock back.
      reading.setActive(false);
    }
    pageController.dispose();
    chromeFocusNode.dispose();
    focusNode.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    reading.setActive(state == AppLifecycleState.resumed);
  }

  void _onReadingChanged() {
    if (!mounted) {
      return;
    }
    final chapterId = reading.currentChapter?.id;
    if (chapterId != trackedChapterId) {
      trackedChapterId = chapterId;
      liveProgress = 0;
      _syncSpreadToChapter();
    }
    setState(() {});
  }

  void _syncSpreadToChapter() {
    if (reading.settings.flow != BookReaderFlow.horizontal ||
        !pageController.hasClients) {
      return;
    }
    final target = _indexOfCurrentChapter();
    if ((pageController.page ?? target.toDouble()).round() == target) {
      return;
    }
    unawaited(
      pageController.animateToPage(
        target,
        duration: BookReaderMetrics.turnMotion,
        curve: BookReaderMetrics.curve,
      ),
    );
  }

  void _syncChapters() {
    final explorer = widget.collection.explorer;
    final children = explorer.childrenOf(widget.collection.collectionView.id);
    reading.setChapters(bookChaptersFrom(children));
  }

  /// The chrome only fades away in fullscreen, and never while it is being
  /// used — an open rail or menu keeps it on screen.
  bool get _chromePinned =>
      !widget.fullscreen ||
      menuOpen ||
      reading.settings.showContentsRail ||
      chromeFocusNode.hasFocus;

  void _wakeChrome() {
    immersionTimer?.cancel();
    if (!chromeVisible && mounted) {
      setState(() => chromeVisible = true);
    } else {
      chromeVisible = true;
    }
    if (_chromePinned) {
      return;
    }
    immersionTimer = Timer(const Duration(milliseconds: 2600), () {
      if (mounted && !_chromePinned) {
        setState(() => chromeVisible = false);
      }
    });
  }

  void _toggleFullscreen() {
    if (widget.fullscreen) {
      unawaited(Navigator.of(context).maybePop());
      return;
    }
    unawaited(_openFullscreen());
  }

  Future<void> _openFullscreen() async {
    reading.setActive(false);
    await showGeneralDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.72),
      transitionDuration: const Duration(milliseconds: 220),
      transitionBuilder: (_, animation, __, child) => FadeTransition(
        opacity: CurvedAnimation(
          parent: animation,
          curve: BookReaderMetrics.curve,
        ),
        child: ScaleTransition(
          scale: Tween(begin: 0.985, end: 1.0).animate(
            CurvedAnimation(
              parent: animation,
              curve: BookReaderMetrics.curve,
            ),
          ),
          child: child,
        ),
      ),
      pageBuilder: (_, __, ___) => _BookFullscreenReader(
        collection: widget.collection,
        reading: reading,
        chapterBuilder: widget.chapterBuilder,
      ),
    );
    if (mounted) {
      reading.setActive(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = BookReaderPalette.of(context, reading.settings.theme);
    final chapter = reading.currentChapter;

    return PreviewToolbarRegion(
      child: ColoredBox(
        color: palette.canvas,
        child: CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.arrowLeft):
                reading.goToPreviousChapter,
            const SingleActivator(LogicalKeyboardKey.arrowRight):
                reading.goToNextChapter,
            const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
            if (widget.fullscreen)
              const SingleActivator(LogicalKeyboardKey.escape):
                  _toggleFullscreen,
          },
          child: Focus(
            focusNode: focusNode,
            autofocus: widget.fullscreen,
            child: MouseRegion(
              opaque: false,
              onHover: widget.fullscreen ? (_) => _wakeChrome() : null,
              child: CollectionWorkspaceSplit(
                railWidth: BookReaderMetrics.railWidth,
                navigationVisible: reading.settings.showContentsRail,
                navigation: Theme(
                  data: palette.themeFor(Theme.of(context)),
                  child: BookContentsRail(
                    reading: reading,
                    palette: palette,
                    onOpenChapter: reading.openChapter,
                    onOpenInWorkspace: widget.collection.onOpen,
                    onEditNote: _editNote,
                  ),
                ),
                compactNavigation: const SizedBox.shrink(),
                headerBuilder: (context, railVisible) => chapter == null
                    ? const SizedBox.shrink()
                    : Focus(
                        focusNode: chromeFocusNode,
                        canRequestFocus: false,
                        skipTraversal: true,
                        onFocusChange: (_) => _wakeChrome(),
                        child: _immersive(
                          _buildChrome(
                            palette,
                            chapter,
                            railVisible: railVisible,
                          ),
                          fromTop: true,
                        ),
                      ),
                child: chapter == null
                    ? _buildEmpty(palette)
                    : _buildReading(palette, chapter),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(BookReaderPalette palette) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            WorkspaceGlyph(
              Icons.menu_book_rounded,
              size: 40,
              color: palette.inkFaint,
            ),
            const SizedBox(height: 14),
            Text(
              LocaleKeys.collections_book_emptyTitle.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.ink,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              LocaleKeys.collections_book_emptyDescription.tr(),
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.inkMuted,
                fontSize: 13,
                height: 1.5,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReading(BookReaderPalette palette, BookChapter chapter) {
    final progress = reading.state.progressFor(chapter.id);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: ColoredBox(
            color: palette.canvas,
            child: reading.settings.flow == BookReaderFlow.horizontal
                ? _buildSpread(palette)
                : _buildSingleLeaf(palette, chapter),
          ),
        ),
        BookProgressBar(value: progress, palette: palette),
        _immersive(
          _buildFooter(palette, chapter, progress),
          fromTop: false,
        ),
      ],
    );
  }

  /// Fullscreen chrome fades without unmounting Tab targets or resizing a
  /// native renderer. Keyboard focus and open popups hold it in place.
  Widget _immersive(Widget child, {required bool fromTop}) {
    if (!widget.fullscreen) {
      return child;
    }
    final visible = chromeVisible || _chromePinned;
    return IgnorePointer(
      ignoring: !visible,
      child: ExcludeSemantics(
        excluding: !visible,
        child: AnimatedOpacity(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          opacity: visible ? 1 : 0,
          child: child,
        ),
      ),
    );
  }

  Widget _buildSingleLeaf(BookReaderPalette palette, BookChapter chapter) {
    return AnimatedSwitcher(
      duration: reading.settings.transition == BookPageTransition.none
          ? Duration.zero
          : BookReaderMetrics.turnMotion,
      switchInCurve: BookReaderMetrics.curve,
      switchOutCurve: BookReaderMetrics.curve,
      transitionBuilder: _buildTransition,
      layoutBuilder: (current, previous) => Stack(
        fit: StackFit.expand,
        children: [...previous, if (current != null) current],
      ),
      child: _buildStage(palette, chapter),
    );
  }

  /// Chapters side by side, swiped through like the leaves of a book.
  Widget _buildSpread(BookReaderPalette palette) {
    final readable = reading.readableChapters;
    return PageView.builder(
      controller: pageController,
      itemCount: readable.length,
      onPageChanged: (index) {
        if (index >= 0 && index < readable.length) {
          reading.openChapter(readable[index].id);
        }
      },
      itemBuilder: (context, index) {
        final chapter = readable[index];
        final stage = _buildStage(palette, chapter);
        if (reading.settings.transition == BookPageTransition.none) {
          return stage;
        }
        return AnimatedBuilder(
          animation: pageController,
          builder: (context, child) => _leafTransform(index, child!),
          child: stage,
        );
      },
    );
  }

  Widget _buildStage(BookReaderPalette palette, BookChapter chapter) {
    if (widget.chapterBuilder != null) {
      return KeyedSubtree(
        key: ValueKey('book-stage-${chapter.id}'),
        child:
            widget.chapterBuilder!(context, chapter, palette, reading.settings),
      );
    }
    return BookChapterStage(
      key: ValueKey('book-stage-${chapter.id}'),
      chapter: chapter,
      palette: palette,
      settings: reading.settings,
      onProgress: (value) => _onProgress(chapter, value),
      onReachedEnd: _onReachedEnd,
    );
  }

  /// How far this page has been carried away from the middle of the view.
  double _pageOffset(int index) {
    if (!pageController.hasClients ||
        pageController.position.hasContentDimensions != true) {
      return (pageController.initialPage - index).toDouble() * -1;
    }
    final page = pageController.page ?? pageController.initialPage.toDouble();
    return (index - page).clamp(-1.0, 1.0);
  }

  Widget _leafTransform(int index, Widget child) {
    final offset = _pageOffset(index);
    if (offset == 0) {
      return child;
    }
    switch (reading.settings.transition) {
      case BookPageTransition.none:
        return child;
      case BookPageTransition.fade:
        return Opacity(
          opacity: (1 - offset.abs()).clamp(0.0, 1.0),
          child: child,
        );
      case BookPageTransition.slide:
        return Transform.translate(
          offset: Offset(-offset * 42, 0),
          child: child,
        );
      case BookPageTransition.curl:
        // A leaf pivots on its spine edge rather than sliding flat, so the
        // page reads as being lifted and laid down.
        final matrix = Matrix4.identity()
          ..setEntry(3, 2, 0.0012)
          ..rotateY(offset * 0.62);
        return Transform(
          alignment: offset > 0 ? Alignment.centerLeft : Alignment.centerRight,
          transform: matrix,
          child: Opacity(
            opacity: (1 - offset.abs() * 0.35).clamp(0.0, 1.0),
            child: child,
          ),
        );
    }
  }

  Widget _buildTransition(Widget child, Animation<double> animation) {
    switch (reading.settings.transition) {
      case BookPageTransition.none:
        return child;
      case BookPageTransition.fade:
        return FadeTransition(opacity: animation, child: child);
      case BookPageTransition.slide:
        return FadeTransition(
          opacity: animation,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0.045, 0),
              end: Offset.zero,
            ).animate(animation),
            child: child,
          ),
        );
      case BookPageTransition.curl:
        return AnimatedBuilder(
          animation: animation,
          builder: (context, leaf) {
            final turn = (1 - animation.value) * 0.7;
            final matrix = Matrix4.identity()
              ..setEntry(3, 2, 0.0012)
              ..rotateY(-turn);
            return Transform(
              alignment: Alignment.centerLeft,
              transform: matrix,
              child: Opacity(opacity: animation.value, child: leaf),
            );
          },
          child: child,
        );
    }
  }

  Widget _buildChrome(
    BookReaderPalette palette,
    BookChapter chapter, {
    required bool railVisible,
  }) {
    final readable = reading.readableChapters;
    final position = readable.indexWhere((entry) => entry.id == chapter.id) + 1;
    final bookmarked = reading.state.bookmarksIn(chapter.id).isNotEmpty;
    return Theme(
      data: palette.themeFor(Theme.of(context)),
      child: CollectionWorkspaceToolbar(
        padding: const EdgeInsets.only(bottom: 8),
        keepVisible: menuOpen,
        identity: railVisible
            ? Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    bookChapterTitle(chapter),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: collectionWorkspaceLabel(
                      context,
                      color: palette.ink,
                      size: 14,
                    ),
                  ),
                  Text(
                    LocaleKeys.collections_book_chapterPosition
                        .tr(args: ['$position', '${readable.length}']),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: collectionWorkspaceLabel(
                      context,
                      color: palette.inkFaint,
                      size: 11,
                    ),
                  ),
                ],
              )
            : CollectionWorkspacePicker(
                label: bookChapterTitle(chapter),
                tooltip: LocaleKeys.collections_book_chapters.tr(),
                icon: Icons.menu_book_rounded,
                entries: [
                  for (final item in readable)
                    AppMenuItem(
                      label: bookChapterTitle(item),
                      selected: item.id == chapter.id,
                      onSelected: () => reading.openChapter(item.id),
                    ),
                  const AppMenuSeparator(),
                  AppMenuItem(
                    label: LocaleKeys.collections_book_toggleContents.tr(),
                    icon: Icons.menu_open_rounded,
                    onSelected: reading.toggleContentsRail,
                  ),
                ],
              ),
        actions: [
          BookControlButton(
            icon: railVisible ? Icons.menu_open_rounded : Icons.menu_rounded,
            tooltip: LocaleKeys.collections_book_toggleContents.tr(),
            palette: palette,
            selected: railVisible,
            onPressed: railVisible
                ? reading.toggleContentsRail
                : () => unawaited(_showContents(palette)),
          ),
          BookControlButton(
            icon: bookmarked
                ? Icons.bookmark_rounded
                : Icons.bookmark_border_rounded,
            tooltip: bookmarked
                ? LocaleKeys.collections_book_removeBookmark.tr()
                : LocaleKeys.collections_book_addBookmark.tr(),
            palette: palette,
            selected: bookmarked,
            onPressed: () => _toggleBookmark(chapter),
          ),
          BookControlButton(
            icon: Icons.edit_note_rounded,
            tooltip: LocaleKeys.collections_book_addNote.tr(),
            palette: palette,
            onPressed: () => unawaited(_editNote(null, chapter: chapter)),
          ),
          KeyedSubtree(
            key: settingsAnchor,
            child: BookControlButton(
              icon: Icons.text_fields_rounded,
              tooltip: LocaleKeys.collections_book_readerSettings.tr(),
              palette: palette,
              onPressed: () => unawaited(_showSettings(palette)),
            ),
          ),
          BookControlButton(
            icon: widget.fullscreen
                ? Icons.fullscreen_exit_rounded
                : Icons.fullscreen_rounded,
            tooltip: widget.fullscreen
                ? LocaleKeys.collections_book_exitFullscreen.tr()
                : LocaleKeys.collections_book_fullscreen.tr(),
            palette: palette,
            onPressed: _toggleFullscreen,
          ),
          const SizedBox(width: 6),
          BookControlButton(
            icon: Icons.chevron_left_rounded,
            tooltip: LocaleKeys.collections_book_previousChapter.tr(),
            palette: palette,
            onPressed: reading.previousChapter == null
                ? null
                : reading.goToPreviousChapter,
          ),
          BookControlButton(
            icon: Icons.chevron_right_rounded,
            tooltip: LocaleKeys.collections_book_nextChapter.tr(),
            palette: palette,
            onPressed:
                reading.nextChapter == null ? null : reading.goToNextChapter,
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(
    BookReaderPalette palette,
    BookChapter chapter,
    double progress,
  ) {
    final overall = reading.state.overallProgress(reading.chapters);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Wrap(
        spacing: 12,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              WorkspaceGlyph(
                bookChapterIcon(chapter.kind),
                size: 14,
                color: palette.inkFaint,
              ),
              const SizedBox(width: 7),
              Flexible(
                child: Text(
                  LocaleKeys.collections_book_percentRead
                      .tr(args: ['${(progress * 100).round()}']),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: collectionWorkspaceLabel(
                    context,
                    color: palette.inkMuted,
                    size: 11.5,
                  ),
                ),
              ),
            ],
          ),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  LocaleKeys.collections_book_finishedCount.tr(
                    args: [
                      '${reading.state.finishedCount(reading.chapters)}',
                      '${reading.readableChapters.length}',
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: collectionWorkspaceLabel(
                    context,
                    color: palette.inkFaint,
                    size: 11.5,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              SizedBox(
                width: 96,
                child: BookProgressBar(
                  value: overall,
                  palette: palette,
                  height: 3,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _showContents(BookReaderPalette palette) async {
    final release = _holdChrome();
    try {
      await showDialog<void>(
        context: context,
        builder: (_) => Dialog(
          backgroundColor: palette.canvas,
          insetPadding: const EdgeInsets.all(24),
          child: SizedBox(
            width: 360,
            height: 520,
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: AnimatedBuilder(
                animation: reading,
                builder: (context, _) => Theme(
                  data: palette.themeFor(Theme.of(context)),
                  child: BookContentsRail(
                    reading: reading,
                    palette: palette,
                    onOpenChapter: reading.openChapter,
                    onOpenInWorkspace: widget.collection.onOpen,
                    onEditNote: _editNote,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    } finally {
      release();
    }
  }

  VoidCallback _holdChrome() {
    final release =
        PreviewToolbarRegion.hold(settingsAnchor.currentContext ?? context);
    setState(() => _menuHolds++);
    _wakeChrome();
    var released = false;
    return () {
      if (released) return;
      released = true;
      release();
      if (mounted) {
        setState(() => _menuHolds--);
        _wakeChrome();
      }
    };
  }

  void _onProgress(BookChapter chapter, double value) {
    liveProgress = value;
    reading.reportProgress(chapter.id, value);
  }

  void _onReachedEnd() {
    if (reading.settings.autoAdvance) {
      reading.goToNextChapter();
    }
  }

  void _toggleBookmark(BookChapter chapter) {
    final existing = reading.state.bookmarksIn(chapter.id);
    if (existing.isNotEmpty) {
      for (final bookmark in existing) {
        reading.removeBookmark(bookmark.id);
      }
      return;
    }
    reading.addBookmark(chapterId: chapter.id, offset: liveProgress);
  }

  Future<void> _editNote(BookNote? note, {BookChapter? chapter}) async {
    final target = chapter ?? reading.currentChapter;
    if (target == null) {
      return;
    }
    final palette = BookReaderPalette.of(context, reading.settings.theme);
    final release = _holdChrome();
    final draft = await showBookNoteEditor(
      context: context,
      palette: palette,
      note: note,
    ).whenComplete(release);
    if (!mounted || draft == null) {
      return;
    }
    if (draft.deleted) {
      if (note != null) {
        reading.removeNote(note.id);
      }
      return;
    }
    if (note == null) {
      reading.addNote(
        chapterId: target.id,
        offset: liveProgress,
        quote: draft.quote,
        body: draft.body,
        color: draft.color,
      );
      return;
    }
    reading.updateNote(
      note.id,
      quote: draft.quote,
      body: draft.body,
      color: draft.color,
    );
  }

  Future<void> _showSettings(BookReaderPalette palette) async {
    final box = settingsAnchor.currentContext?.findRenderObject() as RenderBox?;
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox?;
    if (box == null || overlay == null) {
      return;
    }
    const width = BookReaderSettingsPanel.width;
    final anchor = box.localToGlobal(
      Offset(box.size.width, box.size.height + 8),
      ancestor: overlay,
    );
    final rightEdge = overlay.size.width - width - 12;
    final left =
        rightEdge <= 12 ? 12.0 : (anchor.dx - width).clamp(12.0, rightEdge);
    final release = _holdChrome();
    await showDialog<void>(
      context: context,
      barrierColor: Colors.transparent,
      builder: (dialogContext) => Stack(
        children: [
          Positioned(
            left: left,
            top: anchor.dy,
            child: Material(
              color: Colors.transparent,
              child: AnimatedBuilder(
                animation: reading,
                builder: (context, _) => BookReaderSettingsPanel(
                  settings: reading.settings,
                  palette:
                      BookReaderPalette.of(context, reading.settings.theme),
                  onChanged: reading.updateSettings,
                ),
              ),
            ),
          ),
        ],
      ),
    ).whenComplete(release);
  }
}

/// The reader on its own, filling the window.
class _BookFullscreenReader extends StatelessWidget {
  const _BookFullscreenReader({
    required this.collection,
    required this.reading,
    this.chapterBuilder,
  });

  final CollectionViewContext collection;
  final BookReadingController reading;
  final Widget Function(
    BuildContext,
    BookChapter,
    BookReaderPalette,
    BookReaderSettings,
  )? chapterBuilder;

  @override
  Widget build(BuildContext context) {
    final palette = BookReaderPalette.of(context, reading.settings.theme);
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: ContextualFindScope(
          findInControls: true,
          child: BookReaderView(
            key: ValueKey('book-fullscreen-${collection.collectionView.id}'),
            collection: collection,
            reading: reading,
            chapterBuilder: chapterBuilder,
            fullscreen: true,
          ),
        ),
      ),
    );
  }
}
