import 'dart:async';
import 'dart:io';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_card.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_web_view.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_snapshot.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens a saved page for reading.
Future<void> openBookmarkReader({
  required BuildContext context,
  required BookmarkEntry entry,
  required BookmarkController controller,
  required CollectionViewContext collection,
}) async {
  controller.openBookmark(entry.id);
  await showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierLabel: entry.title,
    barrierColor: Colors.black.withValues(alpha: 0.52),
    transitionDuration: BookmarkMetrics.reveal,
    pageBuilder: (context, animation, secondaryAnimation) => BookmarkReader(
      entryId: entry.id,
      controller: controller,
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
  });

  final String entryId;
  final BookmarkController controller;

  /// Fills the window instead of floating over the library.
  final bool standalone;

  @override
  State<BookmarkReader> createState() => _BookmarkReaderState();
}

class _BookmarkReaderState extends State<BookmarkReader> {
  late final TextEditingController _notes;
  final TextEditingController _tagInput = TextEditingController();
  final GlobalKey<State<BookmarkWebPage>> _webKey = GlobalKey();
  Timer? _notesDebounce;
  BookmarkSnapshot? _snapshot;
  bool _loadingSnapshot = true;
  bool _showAside = true;
  bool _readOffline = false;

  BookmarkEntry? get _entry => widget.controller.entryFor(widget.entryId);

  bool get _canReadOffline => _snapshot?.hasArticle ?? false;

  @override
  void initState() {
    super.initState();
    _notes = TextEditingController(text: _entry?.metadata.notes ?? '');
    widget.controller.addListener(_onChanged);
    unawaited(_loadSnapshot());
    unawaited(_markAsReading());
  }

  @override
  void dispose() {
    _notesDebounce?.cancel();
    _flushNotes();
    widget.controller.removeListener(_onChanged);
    _notes.dispose();
    _tagInput.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  Future<void> _markAsReading() async {
    final entry = _entry;
    if (entry != null && entry.metadata.readState == BookmarkReadState.unread) {
      await widget.controller.setReadState(entry, BookmarkReadState.reading);
    }
  }

  Future<void> _loadSnapshot() async {
    final snapshot = await BookmarkSnapshotStore.instance
        .read(_entry?.metadata.snapshotPath);
    if (mounted) {
      setState(() {
        _snapshot = snapshot;
        _loadingSnapshot = false;
        // A page that cannot be rendered live has only the copy to show.
        if (!canRenderLiveBookmarkPage && (snapshot?.hasArticle ?? false)) {
          _readOffline = true;
        }
      });
    }
  }

  void _flushNotes() {
    final entry = _entry;
    if (entry != null && _notes.text != entry.metadata.notes) {
      unawaited(widget.controller.setNotes(entry, _notes.text));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = bookmarkThemeOf(context);
    final entry = _entry;
    if (entry == null) {
      return const SizedBox.shrink();
    }

    final body = BookmarkPanel(
      color: theme.panel,
      elevation: widget.standalone
          ? ViewerCardElevation.flush
          : ViewerCardElevation.resting,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(theme, entry),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _stage(theme, entry)),
                if (_showAside)
                  SizedBox(
                    width: 300,
                    child: _aside(theme, entry),
                  ),
              ],
            ),
          ),
        ],
      ),
    );

    if (widget.standalone) {
      return ColoredBox(color: theme.canvas, child: body);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(BookmarkMetrics.space6),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1180, maxHeight: 920),
            child: body,
          ),
        ),
      ),
    );
  }

  Widget _header(BookmarkTheme theme, BookmarkEntry entry) => Padding(
        padding: const EdgeInsets.fromLTRB(
          BookmarkMetrics.space5,
          BookmarkMetrics.space4,
          BookmarkMetrics.space3,
          BookmarkMetrics.space3,
        ),
        child: Row(
          children: [
            BookmarkFavicon(entry: entry, theme: theme, size: 22),
            const SizedBox(width: BookmarkMetrics.space3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    entry.title,
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
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.meta,
                  ),
                ],
              ),
            ),
            BookmarkAction(
              icon: entry.metadata.starred
                  ? Icons.star_rounded
                  : Icons.star_outline_rounded,
              tooltip: entry.metadata.starred
                  ? LocaleKeys.collections_bookmark_unstar.tr()
                  : LocaleKeys.collections_bookmark_star.tr(),
              theme: theme,
              active: entry.metadata.starred,
              onPressed: () =>
                  widget.controller.setStarred(entry, !entry.metadata.starred),
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
              icon: _showAside
                  ? Icons.vertical_split_rounded
                  : Icons.notes_rounded,
              tooltip: LocaleKeys.collections_bookmark_notes.tr(),
              theme: theme,
              active: _showAside,
              onPressed: () => setState(() => _showAside = !_showAside),
            ),
            BookmarkAction(
              icon: Icons.close_rounded,
              tooltip: LocaleKeys.collections_bookmark_close.tr(),
              theme: theme,
              onPressed: widget.standalone
                  ? null
                  : () => Navigator.of(context).maybePop(),
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
              icon: Icons.language_rounded,
              tooltip: LocaleKeys.collections_bookmark_live.tr(),
              theme: theme,
              active: !_readOffline,
              onPressed: () => setState(() => _readOffline = false),
            ),
          BookmarkAction(
            icon: Icons.article_rounded,
            tooltip: _canReadOffline
                ? LocaleKeys.collections_bookmark_offlineCopy.tr()
                : LocaleKeys.collections_bookmark_offlineUnavailable.tr(),
            theme: theme,
            active: _readOffline,
            onPressed: _canReadOffline
                ? () => setState(() => _readOffline = true)
                : null,
          ),
          BookmarkAction(
            icon:
                working ? Icons.hourglass_top_rounded : Icons.download_rounded,
            tooltip: working
                ? LocaleKeys.collections_bookmark_savingOffline.tr()
                : LocaleKeys.collections_bookmark_saveOffline.tr(),
            theme: theme,
            onPressed: working ? null : () => _takeSnapshot(entry),
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

    final articlePath = _snapshot?.articlePath;
    if (!_readOffline || articlePath == null) {
      return canRenderLiveBookmarkPage
          ? _livePage(theme, entry)
          : _noSnapshot(theme, entry);
    }

    return NotificationListener<ScrollNotification>(
      onNotification: (notification) {
        final metrics = notification.metrics;
        if (metrics.maxScrollExtent > 0) {
          unawaited(
            widget.controller.recordProgress(
              entry,
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
        child: FilePreview(
          key: ValueKey(articlePath),
          file: File(articlePath),
          name: BookmarkSnapshotStore.articleFileName,
          kind: FilePreviewKind.markdown,
          metadata: const {},
          onMetadataChanged: (_) {},
          editable: false,
          bare: true,
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
          child: BookmarkWebPage(
            key: _webKey,
            url: entry.url,
            theme: theme,
            onOpenExternally: (uri) =>
                launchUrl(uri, mode: LaunchMode.externalApplication),
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
            onPressed: working ? null : () => _takeSnapshot(entry),
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
                      onRemove: () => widget.controller.removeTag(entry, tag),
                    ),
                ],
              ),
              const SizedBox(height: BookmarkMetrics.space2),
            ],
            SizedBox(
              height: 30,
              child: TextField(
                controller: _tagInput,
                cursorColor: theme.accent,
                style: theme.face(
                  fontSize: BookmarkMetrics.bodySize,
                  color: theme.textStrong,
                ),
                onSubmitted: (value) {
                  widget.controller.addTag(entry, value);
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
              controller: _notes,
              maxLines: 8,
              minLines: 4,
              cursorColor: theme.accent,
              style: theme.face(
                fontSize: BookmarkMetrics.bodySize,
                color: theme.textStrong,
                height: 1.5,
              ),
              onChanged: (_) {
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
                    onTap: () => widget.controller.setReadState(entry, state),
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
    await widget.controller.refresh(entry, snapshot: true);
    await _loadSnapshot();
    if (mounted && _canReadOffline) {
      setState(() => _readOffline = true);
    }
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
