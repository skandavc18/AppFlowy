import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_chapter_stage.dart';
import 'package:appflowy/plugins/collection/views/book/book_contents_rail.dart';
import 'package:appflowy/plugins/collection/views/book/book_format.dart';
import 'package:appflowy/plugins/collection/views/book/book_note_editor.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_controls.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_settings_panel.dart';
import 'package:appflowy/plugins/collection/views/book/book_views.dart';
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
  });

  final CollectionViewContext collection;

  /// Borrowed rather than owned, so the fullscreen reader carries on from
  /// exactly where the embedded one left off and neither writes over the
  /// other's position.
  final BookReadingController? reading;

  final bool fullscreen;

  @override
  State<BookReaderView> createState() => _BookReaderViewState();
}

class _BookReaderViewState extends State<BookReaderView>
    with WidgetsBindingObserver {
  late final BookReadingController reading;
  late final bool ownsReading;
  final FocusNode focusNode = FocusNode(debugLabel: 'book-reader');
  final GlobalKey settingsAnchor = GlobalKey();
  late final PageController pageController;
  String? trackedChapterId;
  double liveProgress = 0;
  Timer? immersionTimer;
  bool chromeVisible = true;
  bool menuOpen = false;

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
      !widget.fullscreen || menuOpen || reading.settings.showContentsRail;

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

    return ColoredBox(
      color: palette.canvas,
      child: CallbackShortcuts(
        bindings: {
          const SingleActivator(LogicalKeyboardKey.arrowLeft):
              reading.goToPreviousChapter,
          const SingleActivator(LogicalKeyboardKey.arrowRight):
              reading.goToNextChapter,
          const SingleActivator(LogicalKeyboardKey.f11): _toggleFullscreen,
          if (widget.fullscreen)
            const SingleActivator(LogicalKeyboardKey.escape): _toggleFullscreen,
        },
        child: Focus(
          focusNode: focusNode,
          autofocus: widget.fullscreen,
          child: MouseRegion(
            opaque: false,
            onHover: widget.fullscreen ? (_) => _wakeChrome() : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                AnimatedContainer(
                  duration: BookReaderMetrics.railMotion,
                  curve: BookReaderMetrics.curve,
                  width: reading.settings.showContentsRail
                      ? BookReaderMetrics.railWidth
                      : BookReaderMetrics.railCollapsedWidth,
                  child: reading.settings.showContentsRail
                      ? BookContentsRail(
                          reading: reading,
                          palette: palette,
                          onOpenChapter: reading.openChapter,
                          onOpenInWorkspace: widget.collection.onOpen,
                          onEditNote: _editNote,
                        )
                      : const SizedBox.shrink(),
                ),
                Expanded(
                  child: chapter == null
                      ? _buildEmpty(palette)
                      : _buildReading(palette, chapter),
                ),
              ],
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
            Icon(Icons.menu_book_rounded, size: 40, color: palette.inkFaint),
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
        _immersive(_buildChrome(palette, chapter), fromTop: true),
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

  /// In fullscreen the chrome slides away once the reader settles, so nothing
  /// but the page is left on screen.
  Widget _immersive(Widget child, {required bool fromTop}) {
    if (!widget.fullscreen) {
      return child;
    }
    final visible = chromeVisible || _chromePinned;
    return AnimatedSize(
      duration: BookReaderMetrics.motion,
      curve: BookReaderMetrics.curve,
      alignment: fromTop ? Alignment.bottomCenter : Alignment.topCenter,
      child: AnimatedOpacity(
        duration: BookReaderMetrics.motion,
        curve: BookReaderMetrics.curve,
        opacity: visible ? 1 : 0,
        child: visible ? child : const SizedBox(width: double.infinity),
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

  Widget _buildChrome(BookReaderPalette palette, BookChapter chapter) {
    final readable = reading.readableChapters;
    final position = readable.indexWhere((entry) => entry.id == chapter.id) + 1;
    final bookmarked = reading.state.bookmarksIn(chapter.id).isNotEmpty;
    return Container(
      height: BookReaderMetrics.chromeHeight,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: palette.chrome,
        border: Border(bottom: BorderSide(color: palette.rule, width: 0.6)),
      ),
      child: Row(
        children: [
          BookControlButton(
            icon: reading.settings.showContentsRail
                ? Icons.menu_open_rounded
                : Icons.menu_rounded,
            tooltip: LocaleKeys.collections_book_toggleContents.tr(),
            palette: palette,
            selected: reading.settings.showContentsRail,
            onPressed: reading.toggleContentsRail,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  bookChapterTitle(chapter),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  LocaleKeys.collections_book_chapterPosition.tr(
                    args: ['$position', '${readable.length}'],
                  ),
                  style: TextStyle(color: palette.inkFaint, fontSize: 11),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
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
    return Container(
      height: BookReaderMetrics.footerHeight,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      color: palette.chrome,
      child: Row(
        children: [
          Icon(
            bookChapterIcon(chapter.kind),
            size: 14,
            color: palette.inkFaint,
          ),
          const SizedBox(width: 7),
          Text(
            LocaleKeys.collections_book_percentRead.tr(
              args: ['${(progress * 100).round()}'],
            ),
            style: TextStyle(color: palette.inkMuted, fontSize: 11.5),
          ),
          const Spacer(),
          Text(
            LocaleKeys.collections_book_finishedCount.tr(
              args: [
                '${reading.state.finishedCount(reading.chapters)}',
                '${reading.readableChapters.length}',
              ],
            ),
            style: TextStyle(color: palette.inkFaint, fontSize: 11.5),
          ),
          const SizedBox(width: 12),
          SizedBox(
            width: 96,
            child: BookProgressBar(value: overall, palette: palette, height: 3),
          ),
        ],
      ),
    );
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
    menuOpen = true;
    final draft = await showBookNoteEditor(
      context: context,
      palette: palette,
      note: note,
    );
    menuOpen = false;
    _wakeChrome();
    if (draft == null) {
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
    menuOpen = true;
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
    );
    menuOpen = false;
    _wakeChrome();
  }
}

/// The reader on its own, filling the window.
class _BookFullscreenReader extends StatelessWidget {
  const _BookFullscreenReader({
    required this.collection,
    required this.reading,
  });

  final CollectionViewContext collection;
  final BookReadingController reading;

  @override
  Widget build(BuildContext context) {
    final palette = BookReaderPalette.of(context, reading.settings.theme);
    return Scaffold(
      backgroundColor: palette.canvas,
      body: SafeArea(
        child: BookReaderView(
          key: ValueKey('book-fullscreen-${collection.collectionView.id}'),
          collection: collection,
          reading: reading,
          fullscreen: true,
        ),
      ),
    );
  }
}
