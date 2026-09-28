import 'dart:async';
import 'dart:math' as math;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_card.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_article_view.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_view.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_article_document.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_reading_session.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a saved page for reading.
Future<void> openBookmarkReader({
  required BuildContext context,
  required BookmarkEntry entry,
  required BookmarkController controller,
  required CollectionViewContext collection,
  bool readOnly = false,
  BookmarkSnapshotStore? snapshots,
  WidgetBuilder? webPageBuilder,
  WidgetBuilder? offlinePreviewBuilder,
  BookmarkReadingSession? readingSession,
}) async {
  if (!context.mounted) return;
  // A dialog does not inherit the source page's providers. Capture the owner
  // and matching bloc now; the guard also runs during the reader's disposal,
  // when ancestor lookups through its own context are no longer safe.
  final explorer = collection.explorer;
  final collectionView = collection.collectionView;
  final inheritedAccess = context.read<PageAccessLevelBloc?>();
  final access =
      inheritedAccess?.view.id == collectionView.id ? inheritedAccess : null;
  bool canEdit() {
    if (!context.mounted) return false;
    final view = explorer.viewForId(collectionView.id) ?? collectionView;
    return !view.isLocked &&
        (access == null || (!access.isClosed && access.state.isEditable));
  }

  // Opening/history is navigation, not an edit to saved bookmark metadata.
  controller.openBookmark(entry.id);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: entry.title,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: BookmarkMetrics.reveal,
    pageBuilder: (context, animation, secondaryAnimation) => ListenableBuilder(
      listenable: explorer,
      builder: (_, __) => StreamBuilder<PageAccessLevelState>(
        stream: access?.stream,
        builder: (_, __) => BookmarkReader(
          entryId: entry.id,
          controller: controller,
          readOnly: readOnly || !canEdit(),
          canEdit: canEdit,
          snapshots: snapshots,
          webPageBuilder: webPageBuilder,
          offlinePreviewBuilder: offlinePreviewBuilder,
          readingSession: readingSession,
        ),
      ),
    ),
    transitionBuilder: (context, animation, secondary, child) => FadeTransition(
      opacity: CurvedAnimation(parent: animation, curve: BookmarkMetrics.curve),
      child: child,
    ),
  );
}

/// The reading view: the offline article, the notes and the tags.
class BookmarkReader extends StatefulWidget {
  const BookmarkReader({
    super.key,
    required this.entryId,
    required this.controller,
    this.standalone = false,
    this.readOnly = false,
    this.canEdit,
    this.snapshots,
    this.webPageBuilder,
    this.offlinePreviewBuilder,
    this.readingSession,
  });

  final String entryId;
  final BookmarkController controller;

  /// Fills the window instead of floating over the library.
  final bool standalone;

  /// Disables bookmark mutations, not navigation or reading a saved copy.
  final bool readOnly;

  /// Rechecks the owner's permission at mutation time, including a final notes
  /// flush during disposal. Capture permission sources before opening a route;
  /// this callback must not look up ancestors through the reader's context.
  /// It only governs AppFlowy metadata, never interaction with a live website.
  final bool Function()? canEdit;

  /// Optional IO/leaf substitutions; normal readers use the existing store,
  /// keyed [BookmarkWebPage] and text-only [BookmarkArticleView].
  final BookmarkSnapshotStore? snapshots;
  final WidgetBuilder? webPageBuilder;
  final WidgetBuilder? offlinePreviewBuilder;

  /// Optional capture handle for host integration and isolated tests.
  /// The caller retains ownership when supplied.
  final BookmarkReadingSession? readingSession;

  @override
  State<BookmarkReader> createState() => _BookmarkReaderState();
}

class _BookmarkReaderState extends State<BookmarkReader> {
  late final TextEditingController _notes;
  final TextEditingController _tagInput = TextEditingController();
  final ScrollController _asideScroll = ScrollController();
  GlobalKey<State<BookmarkWebPage>> _webKey = GlobalKey();
  Timer? _notesDebounce;
  BookmarkSnapshot? _snapshot;
  String? _sourceUrl;
  String? _snapshotPath;
  int _sourceRevision = 0;
  int _snapshotRequest = 0;
  bool _notesDirty = false;
  bool _loadingSnapshot = true;
  bool _showAside = true;
  BookmarkReadingMode _mode = BookmarkReadingMode.live;
  late BookmarkReadingSession _reading;
  BookmarkReaderCapture? _capture;
  String? _offlineText;
  bool _readingBusy = false;
  String? _readingError;
  int _readerRequest = 0;

  BookmarkEntry? get _entry => widget.controller.entryFor(widget.entryId);

  bool get _canEdit => !widget.readOnly && (widget.canEdit?.call() ?? true);

  bool get _canReadOffline =>
      (_snapshot?.hasArticle ?? false) &&
      (_offlineText != null || widget.offlinePreviewBuilder != null);

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: _entry?.metadata.notes ?? '');
    _sourceUrl = _entry?.url;
    _snapshotPath = _entry?.metadata.snapshotPath;
    _reading = widget.readingSession ?? BookmarkReadingSession();
    widget.controller.addListener(_onChanged);
    unawaited(_loadSnapshot());
    unawaited(_markAsReading());
  }

  @override
  void didUpdateWidget(covariant BookmarkReader oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.readingSession, widget.readingSession)) {
      if (oldWidget.readingSession == null) _reading.dispose();
      _reading = widget.readingSession ?? BookmarkReadingSession();
      _capture = null;
      _readerRequest++;
      _readingBusy = false;
      _mode = BookmarkReadingMode.live;
    }
    if (!identical(oldWidget.controller, widget.controller) ||
        oldWidget.entryId != widget.entryId) {
      oldWidget.controller.removeListener(_onChanged);
      _notesDebounce?.cancel();
      _flushNotes(binding: oldWidget);
      _resetSource();
      widget.controller.addListener(_onChanged);
    } else if (!identical(oldWidget.snapshots, widget.snapshots)) {
      unawaited(_loadSnapshot());
    }
  }

  @override
  void dispose() {
    _notesDebounce?.cancel();
    // setNotes publishes synchronously before its async persistence completes.
    // Do not rebuild this reader while it is being unmounted.
    widget.controller.removeListener(_onChanged);
    _flushNotes();
    _notes.dispose();
    _tagInput.dispose();
    _asideScroll.dispose();
    _readerRequest++;
    if (widget.readingSession == null) _reading.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      if (_sourceUrl != _entry?.url) {
        _resetSource();
      } else if (_snapshotPath != _entry?.metadata.snapshotPath) {
        _snapshot = null;
        unawaited(_loadSnapshot());
      }
      setState(() {});
    }
  }

  void _resetSource() {
    _notesDebounce?.cancel();
    // A URL retarget no longer has a safe destination for the old draft. Only
    // a controller/entry rebind can flush it first through its original owner.
    _notesDirty = false;
    _sourceRevision++;
    _sourceUrl = _entry?.url;
    _snapshotPath = _entry?.metadata.snapshotPath;
    _notes.text = _entry?.metadata.notes ?? '';
    _tagInput.clear();
    // Only a different source gets a different browser. Layout/reveal/aside
    // changes never replace this key or move the stage to another subtree.
    _webKey = GlobalKey();
    _snapshot = null;
    _loadingSnapshot = true;
    _mode = BookmarkReadingMode.live;
    _readerRequest++;
    _capture = null;
    _offlineText = null;
    _readingBusy = false;
    _readingError = null;
    unawaited(_loadSnapshot());
    unawaited(_markAsReading());
  }

  Future<void> _markAsReading() async {
    if (!mounted || !_canEdit) return;
    final entry = _entry;
    if (entry != null && entry.metadata.readState == BookmarkReadState.unread) {
      await widget.controller.setReadState(entry, BookmarkReadState.reading);
    }
  }

  Future<bool> _loadSnapshot() async {
    final request = ++_snapshotRequest;
    final controller = widget.controller;
    final entryId = widget.entryId;
    final url = _entry?.url;
    final path = _snapshotPath = _entry?.metadata.snapshotPath;
    final store = widget.snapshots ?? BookmarkSnapshotStore.instance;
    BookmarkSnapshot? snapshot;
    try {
      snapshot = await store.read(path).timeout(bookmarkReaderDeadline);
    } on Object {
      snapshot = null;
    }
    String? offlineText;
    if (snapshot?.articlePath != null && widget.offlinePreviewBuilder == null) {
      try {
        offlineText = await store
            .readArticleText(snapshot!)
            .timeout(bookmarkReaderDeadline);
      } on Object {
        // A missing/malformed old copy is unavailable, never a remote fallback.
      }
    }
    if (mounted &&
        request == _snapshotRequest &&
        identical(controller, widget.controller) &&
        entryId == widget.entryId &&
        url == _entry?.url &&
        path == _entry?.metadata.snapshotPath) {
      setState(() {
        _snapshot = snapshot;
        _offlineText = offlineText;
        _loadingSnapshot = false;
        // A page that cannot be rendered live has only the copy to show.
        if (!canRenderLiveBookmarkPage && _canReadOffline) {
          _mode = BookmarkReadingMode.offline;
        }
      });
      return true;
    }
    return false;
  }

  void _flushNotes({BookmarkReader? binding}) {
    final owner = binding ?? widget;
    // Do not require this reader to be mounted: closing intentionally flushes
    // drafts. The original owner's live guard still has to permit the write.
    if (!_notesDirty || owner.readOnly || !(owner.canEdit?.call() ?? true)) {
      return;
    }
    final target = owner.controller;
    final entry = target.entryFor(owner.entryId);
    if (entry == null || entry.url != _sourceUrl) return;
    // Clearing before publication also prevents a debounce/dispose double
    // flush when persistence has not echoed the new notes yet.
    _notesDirty = false;
    if (_notes.text != entry.metadata.notes) {
      unawaited(target.setNotes(entry, _notes.text));
    }
  }

  void _dismiss() {
    if (!mounted || widget.standalone) return;
    final route = ModalRoute.of(context);
    // A captured callback or a pointer released after a newer popup opened
    // must not pop that popup (or the page under an already-closed reader).
    if (route == null || !route.isCurrent) return;
    unawaited(route.navigator?.maybePop());
  }

  @override
  Widget build(BuildContext context) {
    final theme = bookmarkThemeOf(context);
    final entry = _entry;
    if (entry == null) {
      return const SizedBox.shrink();
    }

    final body = Listener(
      key: const ValueKey('bookmark-reader-panel'),
      // PreviewToolbarRegion is deliberately non-opaque. Only this bounded
      // panel, including its blank padding, should stop an outside click.
      behavior: HitTestBehavior.opaque,
      child: Material(
        type: MaterialType.transparency,
        child: PreviewToolbarRegion(
          enabled: !widget.standalone,
          child: BookmarkPanel(
            color: theme.panel,
            elevation: widget.standalone
                ? ViewerCardElevation.flush
                : ViewerCardElevation.resting,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _header(theme, entry),
                Expanded(child: _readingArea(theme, entry)),
              ],
            ),
          ),
        ),
      ),
    );

    if (widget.standalone) {
      return ColoredBox(color: theme.canvas, child: body);
    }

    // A transparent full-screen Scaffold still hits its Material and prevents
    // the route's barrier from receiving margin clicks. Keep Material inside
    // the panel, with a separate, route-local margin target behind it. Higher
    // popup/menu barriers own their first outside click as usual.
    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          key: const ValueKey('bookmark-reader-dismiss-area'),
          behavior: HitTestBehavior.opaque,
          excludeFromSemantics: true,
          onTap: _dismiss,
          onSecondaryTap: _dismiss,
          onTertiaryTapUp: (_) => _dismiss(),
        ),
        Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: MediaQuery.removeViewInsets(
            context: context,
            removeBottom: true,
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(BookmarkMetrics.space6),
                child: ConstrainedBox(
                  constraints:
                      const BoxConstraints(maxWidth: 1180, maxHeight: 920),
                  child: body,
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _readingArea(BookmarkTheme theme, BookmarkEntry entry) =>
      LayoutBuilder(
        builder: (context, constraints) {
          final asideWidth = math.min(300.0, constraints.maxWidth);
          final docked = constraints.maxWidth >=
              asideWidth + MediaQuery.textScalerOf(context).scale(320);
          return Stack(
            fit: StackFit.expand,
            children: [
              Positioned.fill(
                right: docked && _showAside ? asideWidth : 0,
                child: KeyedSubtree(
                  key: const ValueKey('bookmark-reader-stage'),
                  child: _stage(theme, entry),
                ),
              ),
              Positioned(
                top: 0,
                bottom: 0,
                right: 0,
                width: asideWidth,
                child: Offstage(
                  key: const ValueKey('bookmark-reader-aside'),
                  offstage: !_showAside,
                  child: ExcludeFocus(
                    excluding: !_showAside,
                    child: TickerMode(
                      enabled: _showAside,
                      // On a small host notes overlay the page rather than
                      // squeezing a native surface to zero. Both stay mounted.
                      child: ColoredBox(
                        color: theme.panel,
                        child: _aside(theme, entry),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      );

  Widget _header(BookmarkTheme theme, BookmarkEntry entry) => Padding(
        key: const ValueKey('bookmark-reader-header'),
        padding: const EdgeInsets.fromLTRB(
          BookmarkMetrics.space5,
          BookmarkMetrics.space4,
          BookmarkMetrics.space3,
          BookmarkMetrics.space3,
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  // Icon-only native controls are 28px, plus the source group's
                  // 8px insets. Reserve their real width, not a second flex share.
                  final toolsWidth =
                      28.0 * (canRenderLiveBookmarkPage ? 8 : 7) +
                          BookmarkMetrics.space2 * 2;
                  final stacked = constraints.maxWidth <
                      toolsWidth +
                          BookmarkMetrics.space3 +
                          MediaQuery.textScalerOf(context).scale(220);
                  return Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    runSpacing: BookmarkMetrics.space2,
                    children: [
                      SizedBox(
                        width: stacked
                            ? constraints.maxWidth
                            : constraints.maxWidth -
                                toolsWidth -
                                BookmarkMetrics.space3,
                        child: _identity(theme, entry),
                      ),
                      SizedBox(
                        width: stacked ? constraints.maxWidth : toolsWidth,
                        child: _tools(theme, entry),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(width: BookmarkMetrics.space1),
            BookmarkAction(
              key: const ValueKey('bookmark-reader-close'),
              icon: Icons.close_rounded,
              tooltip: LocaleKeys.collections_bookmark_close.tr(),
              theme: theme,
              onPressed: widget.standalone ? null : _dismiss,
            ),
          ],
        ),
      );

  Widget _identity(BookmarkTheme theme, BookmarkEntry entry) => Row(
        children: [
          // Offline/Reader presentation must not request a remote favicon.
          if (_mode == BookmarkReadingMode.live)
            BookmarkFavicon(entry: entry, theme: theme, size: 22)
          else
            const SizedBox(
                width: 22, child: Icon(Icons.article_outlined, size: 20)),
          const SizedBox(width: BookmarkMetrics.space3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  entry.title,
                  key: const ValueKey('bookmark-reader-title'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.face(
                    fontSize: 16,
                    color: theme.textStrong,
                    axis: BookmarkMetrics.strongWeightAxis,
                    weight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  bookmarkDisplayUrl(entry.url, maxLength: 96),
                  key: const ValueKey('bookmark-reader-url'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.meta,
                ),
              ],
            ),
          ),
        ],
      );

  Widget _tools(BookmarkTheme theme, BookmarkEntry entry) => PreviewToolbar(
        key: const ValueKey('bookmark-reader-tools'),
        keepVisible: widget.controller.isWorkingOn(entry.id) || _readingBusy,
        child: Wrap(
          alignment: WrapAlignment.end,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: BookmarkMetrics.space1,
          children: [
            BookmarkAction(
              icon: entry.metadata.starred
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              tooltip: entry.metadata.starred
                  ? LocaleKeys.collections_bookmark_unstar.tr()
                  : LocaleKeys.collections_bookmark_star.tr(),
              theme: theme,
              active: entry.metadata.starred,
              onPressed: !_canEdit
                  ? null
                  : () {
                      if (!mounted || !_canEdit) return;
                      unawaited(
                        widget.controller
                            .setStarred(entry, !entry.metadata.starred),
                      );
                    },
            ),
            BookmarkAction(
              icon: Icons.link_rounded,
              tooltip: LocaleKeys.collections_bookmark_copyLink.tr(),
              theme: theme,
              onPressed: () =>
                  Clipboard.setData(ClipboardData(text: entry.url)),
            ),
            _sourceToggle(theme, entry),
            BookmarkAction(
              icon: Icons.open_in_new_rounded,
              tooltip: LocaleKeys.collections_bookmark_openInBrowser.tr(),
              theme: theme,
              onPressed: () => _openInBrowser(entry),
            ),
            BookmarkAction(
              key: const ValueKey('bookmark-reader-aside-toggle'),
              icon: _showAside
                  ? Icons.vertical_split_rounded
                  : Icons.notes_rounded,
              tooltip: LocaleKeys.collections_bookmark_notes.tr(),
              theme: theme,
              active: _showAside,
              onPressed: () => setState(() => _showAside = !_showAside),
            ),
          ],
        ),
      );

  /// The live page or the saved copy, plus the download that creates one.
  Widget _sourceToggle(BookmarkTheme theme, BookmarkEntry entry) {
    final working = widget.controller.isWorkingOn(entry.id);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: BookmarkMetrics.space2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (canRenderLiveBookmarkPage)
            BookmarkAction(
              key: const ValueKey('bookmark-reader-live'),
              icon: Icons.language_rounded,
              tooltip: LocaleKeys.collections_bookmark_live.tr(),
              theme: theme,
              active: _mode == BookmarkReadingMode.live,
              onPressed: () => _selectMode(BookmarkReadingMode.live),
            ),
          BookmarkAction(
            key: const ValueKey('bookmark-reader-reader'),
            icon: Icons.chrome_reader_mode_outlined,
            tooltip: BookmarkReaderStrings.reader,
            theme: theme,
            active: _mode == BookmarkReadingMode.reader,
            onPressed: _readingBusy ? null : _openReader,
          ),
          BookmarkAction(
            key: const ValueKey('bookmark-reader-offline'),
            icon: Icons.article_rounded,
            tooltip: _canReadOffline
                ? LocaleKeys.collections_bookmark_offlineCopy.tr()
                : LocaleKeys.collections_bookmark_offlineUnavailable.tr(),
            theme: theme,
            active: _mode == BookmarkReadingMode.offline,
            onPressed: _canReadOffline
                ? () => _selectMode(BookmarkReadingMode.offline)
                : null,
          ),
          BookmarkAction(
            icon: working || _readingBusy
                ? Icons.hourglass_top_rounded
                : Icons.download_rounded,
            tooltip: working
                ? LocaleKeys.collections_bookmark_savingOffline.tr()
                : LocaleKeys.collections_bookmark_saveOffline.tr(),
            theme: theme,
            onPressed: working ||
                    _readingBusy ||
                    !_canEdit ||
                    _mode == BookmarkReadingMode.offline
                ? null
                : () => _takeSnapshot(entry),
          ),
        ],
      ),
    );
  }

  Widget _stage(BookmarkTheme theme, BookmarkEntry entry) {
    if (_loadingSnapshot) {
      return Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: theme.accent),
        ),
      );
    }

    final live = _mode == BookmarkReadingMode.live;
    return Stack(fit: StackFit.expand, children: [
      Offstage(
        key: const ValueKey('bookmark-retained-live'),
        offstage: !live,
        child: ExcludeFocus(
          excluding: !live,
          child: ExcludeSemantics(
            excluding: !live,
            child: IgnorePointer(
              ignoring: !live,
              child: TickerMode(
                enabled: live,
                child: canRenderLiveBookmarkPage
                    ? _livePage(theme, entry)
                    : _noSnapshot(theme, entry),
              ),
            ),
          ),
        ),
      ),
      if (!live) _localPage(theme, entry),
      if (live && _readingError != null)
        Positioned(
          left: 8,
          right: 8,
          bottom: 8,
          child: Material(
            color: theme.panel,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Semantics(
                liveRegion: true,
                child: Text(_readingError!, style: theme.body),
              ),
            ),
          ),
        ),
    ]);
  }

  Widget _localPage(BookmarkTheme theme, BookmarkEntry entry) {
    if (_readingBusy)
      return Center(child: CircularProgressIndicator(color: theme.accent));
    final text = _mode == BookmarkReadingMode.reader
        ? (_capture == null
            ? null
            : bookmarkArticleText(_capture!.article.markdown))
        : _offlineText;
    final previewBuilder = _mode == BookmarkReadingMode.offline
        ? widget.offlinePreviewBuilder
        : null;
    if (_readingError != null || (text == null && previewBuilder == null)) {
      return BookmarkEmptyState(
          theme: theme,
          icon: Icons.article_outlined,
          title: _readingError ?? BookmarkReaderStrings.unavailable);
    }
    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        if (!mounted || !_canEdit) return false;
        final metrics = notification.metrics;
        final current = _entry;
        if (current != null &&
            current.id == entry.id &&
            current.url == entry.url &&
            metrics.maxScrollExtent > 0) {
          unawaited(
            widget.controller.recordProgress(
              current,
              metrics.pixels / metrics.maxScrollExtent,
            ),
          );
        }
        return false;
      },
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          BookmarkMetrics.space2,
          0,
          BookmarkMetrics.space2,
          BookmarkMetrics.space2,
        ),
        child: previewBuilder == null
            ? BookmarkArticleView(
                key: ValueKey(
                    (_mode, _capture?.generation, _snapshot?.articlePath)),
                text: text!)
            : KeyedSubtree(
                key: ValueKey(_snapshot?.articlePath),
                child: Builder(builder: previewBuilder),
              ),
      ),
    );
  }

  Widget _livePage(BookmarkTheme theme, BookmarkEntry entry) => Padding(
        padding: const EdgeInsets.fromLTRB(
          BookmarkMetrics.space2,
          0,
          BookmarkMetrics.space2,
          BookmarkMetrics.space2,
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(BookmarkMetrics.cardRadius - 6),
          child: widget.webPageBuilder == null
              ? BookmarkWebPage(
                  key: _webKey,
                  url: entry.url,
                  theme: theme,
                  active: _mode == BookmarkReadingMode.live,
                  readingSession: _reading,
                  onOpenExternally: (uri) =>
                      launchUrl(uri, mode: LaunchMode.externalApplication),
                )
              : KeyedSubtree(
                  key: ValueKey(_sourceRevision),
                  child: Builder(builder: widget.webPageBuilder!),
                ),
        ),
      );

  Widget _noSnapshot(BookmarkTheme theme, BookmarkEntry entry) {
    final working = widget.controller.isWorkingOn(entry.id);
    return BookmarkEmptyState(
      theme: theme,
      icon: Icons.cloud_download_rounded,
      title: LocaleKeys.collections_bookmark_offlineUnavailable.tr(),
      message:
          LocaleKeys.collections_bookmark_offlineUnavailableDescription.tr(),
      action: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          BookmarkAction(
            icon:
                working ? Icons.hourglass_top_rounded : Icons.download_rounded,
            tooltip: LocaleKeys.collections_bookmark_saveOffline.tr(),
            theme: theme,
            label: LocaleKeys.collections_bookmark_saveOffline.tr(),
            active: true,
            onPressed: working || !_canEdit ? null : () => _takeSnapshot(entry),
          ),
          const SizedBox(width: BookmarkMetrics.space2),
          BookmarkAction(
            icon: Icons.open_in_new_rounded,
            tooltip: LocaleKeys.collections_bookmark_openInBrowser.tr(),
            theme: theme,
            label: LocaleKeys.collections_bookmark_openInBrowser.tr(),
            onPressed: () => _openInBrowser(entry),
          ),
        ],
      ),
    );
  }

  Widget _aside(BookmarkTheme theme, BookmarkEntry entry) {
    final metadata = entry.metadata;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        BookmarkMetrics.space4,
        BookmarkMetrics.space4,
        BookmarkMetrics.space5,
        BookmarkMetrics.space5,
      ),
      child: SingleChildScrollView(
        key: const ValueKey('bookmark-reader-aside-scroll'),
        controller: _asideScroll,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (metadata.description != null) ...[
              Text(metadata.description!, style: theme.body),
              const SizedBox(height: BookmarkMetrics.space5),
            ],
            _sectionLabel(theme, LocaleKeys.collections_bookmark_tags.tr()),
            const SizedBox(height: BookmarkMetrics.space2),
            if (metadata.tags.isNotEmpty) ...[
              Wrap(
                spacing: BookmarkMetrics.space1 + 2,
                runSpacing: BookmarkMetrics.space1 + 2,
                children: [
                  for (final tag in metadata.tags)
                    BookmarkChip(
                      label: tag,
                      theme: theme,
                      onRemove: !_canEdit
                          ? null
                          : () {
                              if (!mounted || !_canEdit) return;
                              unawaited(
                                widget.controller.removeTag(entry, tag),
                              );
                            },
                    ),
                ],
              ),
              const SizedBox(height: BookmarkMetrics.space2),
            ],
            SizedBox(
              height: math.max(
                30,
                MediaQuery.textScalerOf(context)
                        .scale(BookmarkMetrics.bodySize) +
                    14,
              ),
              child: TextField(
                key: const ValueKey('bookmark-reader-tag-input'),
                controller: _tagInput,
                readOnly: !_canEdit,
                cursorColor: theme.accent,
                style: theme.face(
                  fontSize: BookmarkMetrics.bodySize,
                  color: theme.textStrong,
                ),
                onSubmitted: (value) {
                  if (!mounted || !_canEdit) return;
                  unawaited(widget.controller.addTag(entry, value));
                  _tagInput.clear();
                },
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: theme.sunken,
                  hoverColor: theme.sunken,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: BookmarkMetrics.space2 + 2,
                    vertical: 7,
                  ),
                  hintText: LocaleKeys.collections_bookmark_tagHint.tr(),
                  hintStyle: theme.face(
                    fontSize: BookmarkMetrics.bodySize,
                    color: theme.textFaint,
                  ),
                  border: _fieldBorder,
                  enabledBorder: _fieldBorder,
                  focusedBorder: _fieldBorder,
                ),
              ),
            ),
            const SizedBox(height: BookmarkMetrics.space5),
            _sectionLabel(theme, LocaleKeys.collections_bookmark_notes.tr()),
            const SizedBox(height: BookmarkMetrics.space2),
            TextField(
              key: const ValueKey('bookmark-reader-notes'),
              controller: _notes,
              readOnly: !_canEdit,
              maxLines: 8,
              minLines: 4,
              cursorColor: theme.accent,
              style: theme.face(
                fontSize: BookmarkMetrics.bodySize,
                color: theme.textStrong,
                height: 1.5,
              ),
              onChanged: (_) {
                if (!mounted || !_canEdit) return;
                _notesDirty = true;
                _notesDebounce?.cancel();
                _notesDebounce = Timer(
                  const Duration(milliseconds: 600),
                  _flushNotes,
                );
              },
              decoration: InputDecoration(
                filled: true,
                fillColor: theme.sunken,
                hoverColor: theme.sunken,
                contentPadding: const EdgeInsets.all(BookmarkMetrics.space3),
                hintText: LocaleKeys.collections_bookmark_notesHint.tr(),
                hintStyle: theme.face(
                  fontSize: BookmarkMetrics.bodySize,
                  color: theme.textFaint,
                ),
                border: _fieldBorder,
                enabledBorder: _fieldBorder,
                focusedBorder: _fieldBorder,
              ),
            ),
            const SizedBox(height: BookmarkMetrics.space5),
            _sectionLabel(theme, LocaleKeys.collections_bookmark_read.tr()),
            const SizedBox(height: BookmarkMetrics.space2),
            Wrap(
              spacing: BookmarkMetrics.space1 + 2,
              runSpacing: BookmarkMetrics.space1 + 2,
              children: [
                for (final state in BookmarkReadState.values)
                  BookmarkChip(
                    label: _readLabel(state),
                    theme: theme,
                    selected: metadata.readState == state,
                    onTap: !_canEdit
                        ? null
                        : () {
                            if (!mounted || !_canEdit) return;
                            unawaited(
                              widget.controller.setReadState(entry, state),
                            );
                          },
                  ),
              ],
            ),
            const SizedBox(height: BookmarkMetrics.space5),
            _facts(theme, entry),
          ],
        ),
      ),
    );
  }

  Widget _facts(BookmarkTheme theme, BookmarkEntry entry) {
    final metadata = entry.metadata;
    final rows = <(String, String)>[
      if (metadata.author != null) ('Author', metadata.author!),
      if (metadata.siteName != null) ('Site', metadata.siteName!),
      if (metadata.publishedAt != null)
        (
          'Published',
          bookmarkDateLabel(metadata.publishedAt!),
        ),
      if (metadata.addedAt != null)
        ('Saved', bookmarkDateLabel(metadata.addedAt!)),
      if (metadata.readingMinutes != null)
        (
          'Length',
          LocaleKeys.collections_bookmark_minuteRead
              .tr(args: ['${metadata.readingMinutes}']),
        ),
      if (_snapshot != null)
        ('Offline', '${(_snapshot!.bytes / 1024).round()} KB'),
    ];
    if (rows.isEmpty) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final row in rows)
          Padding(
            padding: const EdgeInsets.only(bottom: BookmarkMetrics.space2 - 1),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox(
                  width: 78,
                  child: Text(row.$1, style: theme.meta),
                ),
                Expanded(
                  child: Text(row.$2, style: theme.metaStrong),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _sectionLabel(BookmarkTheme theme, String label) =>
      Text(label.toUpperCase(), style: theme.sectionLabel);

  static String _readLabel(BookmarkReadState state) => switch (state) {
        BookmarkReadState.unread =>
          LocaleKeys.collections_bookmark_unreadLabel.tr(),
        BookmarkReadState.reading =>
          LocaleKeys.collections_bookmark_readingLabel.tr(),
        BookmarkReadState.read =>
          LocaleKeys.collections_bookmark_readLabel.tr(),
      };

  Future<void> _takeSnapshot(BookmarkEntry entry) async {
    if (!mounted ||
        _readingBusy ||
        widget.controller.isWorkingOn(entry.id) ||
        !_canEdit ||
        _entry?.id != entry.id ||
        _entry?.url != entry.url) {
      return;
    }
    final controller = widget.controller;
    final revision = _sourceRevision;
    final mode = _mode;
    if (_mode != BookmarkReadingMode.live &&
        (_capture == null || !_captureIsCurrent(_capture!))) {
      setState(() => _readingError = BookmarkReaderStrings.unavailable);
      return;
    }
    bool stillCurrent() =>
        mounted &&
        _canEdit &&
        revision == _sourceRevision &&
        identical(controller, widget.controller) &&
        _entry?.id == entry.id &&
        _entry?.url == entry.url;
    final capture = _capture != null && _captureIsCurrent(_capture!)
        ? _capture
        : await _readCurrentArticle();
    if (capture == null || !stillCurrent()) return;
    // Reader may show a followed link, but it must not save that document as
    // the original bookmark's offline copy.
    if (capture.url != entry.url || !_captureIsCurrent(capture)) {
      setState(() => _readingError = BookmarkReaderStrings.unavailable);
      return;
    }
    final saved = await controller.saveReaderCapture(
      entry,
      capture,
      store: widget.snapshots,
      isCurrent: () => stillCurrent() && _captureIsCurrent(capture),
    );
    if (!stillCurrent()) return;
    if (!saved) {
      setState(() => _readingError = BookmarkReaderStrings.saveFailed);
      return;
    }
    final loaded = await _loadSnapshot();
    if (loaded &&
        stillCurrent() &&
        _captureIsCurrent(capture) &&
        mode == _mode &&
        _canReadOffline) {
      _selectMode(BookmarkReadingMode.offline);
    }
  }

  void _selectMode(BookmarkReadingMode mode) {
    if (!mounted) return;
    _readerRequest++;
    setState(() {
      _mode = mode;
      _readingBusy = false;
      _readingError = null;
    });
  }

  bool _captureIsCurrent(BookmarkReaderCapture capture) =>
      canRenderLiveBookmarkPage
          ? _reading.isCurrent(capture)
          : capture.url == _entry?.url;

  Future<BookmarkReaderCapture?> _readCurrentArticle() async {
    final request = ++_readerRequest;
    final revision = _sourceRevision;
    final controller = widget.controller;
    final entry = _entry;
    if (entry == null) return null;
    setState(() {
      _readingBusy = true;
      _readingError = null;
    });
    BookmarkReaderCapture? capture;
    try {
      capture = await (canRenderLiveBookmarkPage
              ? _reading.capture()
              : controller.readArticleForReader(entry))
          .timeout(bookmarkReaderDeadline);
    } on Object {
      // A failed/late fallback read must release the controls just like a
      // failed live capture, without an unhandled async UI callback error.
    }
    if (!mounted ||
        request != _readerRequest ||
        revision != _sourceRevision ||
        !identical(controller, widget.controller)) return null;
    setState(() {
      _readingBusy = false;
      _capture = capture;
      _readingError =
          capture == null ? BookmarkReaderStrings.unavailable : null;
    });
    return capture;
  }

  Future<void> _openReader() async {
    if (!mounted || _readingBusy) return;
    // Capture before hiding/suspending the native page; a suspended renderer
    // must not be asked to execute the Reader script.
    if (_capture == null || !_captureIsCurrent(_capture!)) {
      if (_mode != BookmarkReadingMode.live && canRenderLiveBookmarkPage) {
        _selectMode(BookmarkReadingMode.live);
        final ticket = _readerRequest;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || ticket != _readerRequest) return;
      }
      final mode = _mode;
      final revision = _sourceRevision;
      final ticket = _readerRequest + 1;
      final capture = await _readCurrentArticle();
      if (!mounted ||
          ticket != _readerRequest ||
          revision != _sourceRevision ||
          mode != _mode) return;
      if (capture == null) {
        setState(() => _mode = BookmarkReadingMode.reader);
        return;
      }
    }
    _selectMode(BookmarkReadingMode.reader);
  }

  Future<void> _openInBrowser(BookmarkEntry entry) async {
    final uri = Uri.tryParse(entry.url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  OutlineInputBorder get _fieldBorder => OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide.none,
      );
}
