import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_format.dart';
import 'package:appflowy/plugins/collection/views/book/book_note_editor.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_controls.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/plugins/collection/views/book/book_views.dart';
import 'package:appflowy/shared/scrolling/premium_scroll_behavior.dart';
import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_controller.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The book at a glance: how far through it the reader is, what is in it, and
/// everything they kept along the way.
class BookContentsView extends StatefulWidget {
  const BookContentsView({super.key, required this.collection});

  final CollectionViewContext collection;

  @override
  State<BookContentsView> createState() => _BookContentsViewState();
}

class _BookContentsViewState extends State<BookContentsView> {
  late final BookReadingController reading;

  @override
  void initState() {
    super.initState();
    reading = BookReadingController(
      initialState: widget.collection.stateFor(bookStateKey),
      onPersist: (state) =>
          widget.collection.onStateChanged(bookStateKey, state),
    );
    widget.collection.explorer.addListener(_syncChapters);
    _syncChapters();
    reading.addListener(_onChanged);
    unawaited(
      widget.collection.explorer
          .ensureLoaded(widget.collection.collectionView.id),
    );
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_syncChapters);
    reading.removeListener(_onChanged);
    reading.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncChapters() {
    final children = widget.collection.explorer
        .childrenOf(widget.collection.collectionView.id);
    reading.setChapters(bookChaptersFrom(children));
  }

  @override
  Widget build(BuildContext context) {
    final palette = BookReaderPalette.of(context, reading.settings.theme);
    final chapters = reading.chapters;
    return ColoredBox(
      color: palette.canvas,
      child: PremiumScrollScope(
        enabled: true,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(28, 22, 28, 60),
          children: [
            _buildHero(palette),
            const SizedBox(height: 26),
            if (chapters.isEmpty)
              _buildEmpty(palette)
            else ...[
              _sectionLabel(palette, LocaleKeys.collections_book_chapters.tr()),
              const SizedBox(height: 10),
              for (final chapter in chapters)
                chapter.isPart
                    ? _buildPartHeading(palette, chapter)
                    : _buildChapterCard(palette, chapter),
            ],
            if (reading.state.bookmarks.isNotEmpty) ...[
              const SizedBox(height: 26),
              _sectionLabel(
                palette,
                LocaleKeys.collections_book_bookmarks.tr(),
              ),
              const SizedBox(height: 10),
              _buildBookmarks(palette),
            ],
            if (reading.state.notes.isNotEmpty) ...[
              const SizedBox(height: 26),
              _sectionLabel(palette, LocaleKeys.collections_book_notes.tr()),
              const SizedBox(height: 10),
              _buildNotes(palette),
            ],
          ],
        ),
      ),
    );
  }

  Widget _sectionLabel(BookReaderPalette palette, String text) => Text(
        text.toUpperCase(),
        style: TextStyle(
          color: palette.inkFaint,
          fontSize: 10.5,
          letterSpacing: 0.9,
          fontWeight: FontWeight.w600,
        ),
      );

  Widget _buildHero(BookReaderPalette palette) {
    final chapters = reading.chapters;
    final readable = reading.readableChapters;
    final overall = reading.state.overallProgress(chapters);
    final finished = reading.state.finishedCount(chapters);
    final stats = reading.state.stats;
    final started = overall > 0;
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 22, 24, 22),
      decoration: BoxDecoration(
        color: palette.page,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: palette.rule, width: 0.6),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          BookProgressRing(
            value: overall,
            palette: palette,
            child: Text(
              '${(overall * 100).round()}%',
              style: TextStyle(
                color: palette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          const SizedBox(width: 22),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  LocaleKeys.collections_book_finishedCount.tr(
                    args: ['$finished', '${readable.length}'],
                  ),
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  readable.length == 1
                      ? LocaleKeys.collections_book_oneChapter.tr()
                      : LocaleKeys.collections_book_chapterCount.tr(
                          args: ['${readable.length}'],
                        ),
                  style: TextStyle(color: palette.inkMuted, fontSize: 12.5),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 22,
                  runSpacing: 12,
                  children: [
                    _stat(
                      palette,
                      LocaleKeys.collections_book_timeRead.tr(),
                      formatReadingDuration(stats.totalSeconds),
                    ),
                    _stat(
                      palette,
                      LocaleKeys.collections_book_sessions.tr(),
                      '${stats.sessions}',
                    ),
                    _stat(
                      palette,
                      LocaleKeys.collections_book_streak.tr(),
                      LocaleKeys.collections_book_dayCount.tr(
                        args: ['${stats.streakOn(DateTime.now())}'],
                      ),
                    ),
                    _stat(
                      palette,
                      LocaleKeys.collections_book_lastRead.tr(),
                      stats.lastReadAt == null
                          ? LocaleKeys.collections_book_never.tr()
                          : DateFormat.yMMMd().format(stats.lastReadAt!),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 18),
          if (readable.isNotEmpty)
            _HeroButton(
              palette: palette,
              label: started
                  ? LocaleKeys.collections_book_continueReading.tr()
                  : LocaleKeys.collections_book_startReading.tr(),
              onTap: () => widget.collection.onOpenView(BookViewIds.reader),
            ),
        ],
      ),
    );
  }

  Widget _stat(BookReaderPalette palette, String label, String value) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(
              color: palette.inkFaint,
              fontSize: 9.5,
              letterSpacing: 0.7,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              color: palette.ink,
              fontSize: 13.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      );

  Widget _buildEmpty(BookReaderPalette palette) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 48),
        child: Column(
          children: [
            Icon(Icons.menu_book_rounded, size: 36, color: palette.inkFaint),
            const SizedBox(height: 12),
            Text(
              LocaleKeys.collections_book_emptyTitle.tr(),
              style: TextStyle(
                color: palette.ink,
                fontSize: 15,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Text(
                LocaleKeys.collections_book_emptyDescription.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.inkMuted,
                  fontSize: 12.5,
                  height: 1.5,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _buildPartHeading(BookReaderPalette palette, BookChapter chapter) =>
      Padding(
        padding: const EdgeInsets.fromLTRB(2, 20, 0, 8),
        child: Text(
          bookChapterTitle(chapter),
          style: TextStyle(
            color: palette.inkMuted,
            fontSize: 13,
            fontWeight: FontWeight.w600,
            letterSpacing: 0.2,
          ),
        ),
      );

  Widget _buildChapterCard(BookReaderPalette palette, BookChapter chapter) {
    final progress = reading.state.progressFor(chapter.id);
    final finished = reading.state.isFinished(chapter.id);
    final notes = reading.state.notesIn(chapter.id).length;
    final bookmarks = reading.state.bookmarksIn(chapter.id).length;
    return _ChapterCard(
      palette: palette,
      chapter: chapter,
      progress: progress,
      finished: finished,
      notes: notes,
      bookmarks: bookmarks,
      onRead: () {
        reading.openChapter(chapter.id);
        widget.collection.onOpenView(BookViewIds.reader);
      },
      onToggleFinished: () => reading.reportProgress(
        chapter.id,
        finished ? 0 : 1,
      ),
      onOpenInWorkspace: () => widget.collection.onOpen(chapter.view),
    );
  }

  Widget _buildBookmarks(BookReaderPalette palette) {
    final bookmarks = [...reading.state.bookmarks]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      children: [
        for (final bookmark in bookmarks)
          _KeepsakeRow(
            palette: palette,
            icon: Icons.bookmark_rounded,
            title: bookmark.label.isNotEmpty
                ? bookmark.label
                : _chapterName(bookmark.chapterId),
            subtitle: LocaleKeys.collections_book_percentRead.tr(
              args: ['${(bookmark.offset * 100).round()}'],
            ),
            accent: palette.accent,
            onTap: () {
              reading.openChapter(bookmark.chapterId);
              widget.collection.onOpenView(BookViewIds.reader);
            },
            onRemove: () => reading.removeBookmark(bookmark.id),
          ),
      ],
    );
  }

  Widget _buildNotes(BookReaderPalette palette) {
    final notes = [...reading.state.notes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return Column(
      children: [
        for (final note in notes)
          _KeepsakeRow(
            palette: palette,
            icon: Icons.edit_note_rounded,
            title: note.body.trim().isNotEmpty ? note.body : note.quote,
            subtitle: _chapterName(note.chapterId),
            accent: bookNoteColor(note.color, isDark: palette.theme.isDark),
            quote: note.quote.trim().isNotEmpty && note.body.trim().isNotEmpty
                ? note.quote
                : null,
            onTap: () => unawaited(_editNote(palette, note)),
            onRemove: () => reading.removeNote(note.id),
          ),
      ],
    );
  }

  Future<void> _editNote(BookReaderPalette palette, BookNote note) async {
    final draft = await showBookNoteEditor(
      context: context,
      palette: palette,
      note: note,
    );
    if (draft == null) {
      return;
    }
    if (draft.deleted) {
      reading.removeNote(note.id);
      return;
    }
    reading.updateNote(
      note.id,
      quote: draft.quote,
      body: draft.body,
      color: draft.color,
    );
  }

  String _chapterName(String id) {
    for (final chapter in reading.chapters) {
      if (chapter.id == id) {
        return bookChapterTitle(chapter);
      }
    }
    return LocaleKeys.collections_book_untitledChapter.tr();
  }
}

class _ChapterCard extends StatefulWidget {
  const _ChapterCard({
    required this.palette,
    required this.chapter,
    required this.progress,
    required this.finished,
    required this.notes,
    required this.bookmarks,
    required this.onRead,
    required this.onToggleFinished,
    required this.onOpenInWorkspace,
  });

  final BookReaderPalette palette;
  final BookChapter chapter;
  final double progress;
  final bool finished;
  final int notes;
  final int bookmarks;
  final VoidCallback onRead;
  final VoidCallback onToggleFinished;
  final VoidCallback onOpenInWorkspace;

  @override
  State<_ChapterCard> createState() => _ChapterCardState();
}

class _ChapterCardState extends State<_ChapterCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final status = widget.finished
        ? LocaleKeys.collections_book_finished.tr()
        : widget.progress > 0
            ? LocaleKeys.collections_book_reading.tr()
            : LocaleKeys.collections_book_unread.tr();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onRead,
        child: AnimatedContainer(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(16, 13, 12, 13),
          decoration: BoxDecoration(
            color: hovered ? palette.hover : palette.page,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.rule, width: 0.6),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 30,
                child: Text(
                  '${widget.chapter.index + 1}',
                  style: TextStyle(
                    color: palette.inkFaint,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Icon(
                bookChapterIcon(widget.chapter.kind),
                size: 16,
                color: palette.inkMuted,
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      bookChapterTitle(widget.chapter),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Row(
                      children: [
                        Text(
                          status,
                          style: TextStyle(
                            color: widget.finished
                                ? palette.accent
                                : palette.inkFaint,
                            fontSize: 11,
                          ),
                        ),
                        if (widget.bookmarks > 0) ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.bookmark_rounded,
                            size: 11,
                            color: palette.inkFaint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${widget.bookmarks}',
                            style: TextStyle(
                              color: palette.inkFaint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                        if (widget.notes > 0) ...[
                          const SizedBox(width: 10),
                          Icon(
                            Icons.edit_note_rounded,
                            size: 12,
                            color: palette.inkFaint,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${widget.notes}',
                            style: TextStyle(
                              color: palette.inkFaint,
                              fontSize: 11,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              SizedBox(
                width: 92,
                child: BookProgressBar(
                  value: widget.progress,
                  palette: palette,
                  height: 3,
                ),
              ),
              const SizedBox(width: 8),
              AnimatedOpacity(
                duration: BookReaderMetrics.motion,
                opacity: hovered ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !hovered,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      BookControlButton(
                        icon: widget.finished
                            ? Icons.remove_done_rounded
                            : Icons.done_all_rounded,
                        tooltip: widget.finished
                            ? LocaleKeys.collections_book_markUnread.tr()
                            : LocaleKeys.collections_book_markFinished.tr(),
                        palette: palette,
                        onPressed: widget.onToggleFinished,
                      ),
                      BookControlButton(
                        icon: Icons.open_in_new_rounded,
                        tooltip:
                            LocaleKeys.collections_book_openInWorkspace.tr(),
                        palette: palette,
                        onPressed: widget.onOpenInWorkspace,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _KeepsakeRow extends StatefulWidget {
  const _KeepsakeRow({
    required this.palette,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onTap,
    required this.onRemove,
    this.quote,
  });

  final BookReaderPalette palette;
  final IconData icon;
  final String title;
  final String subtitle;
  final Color accent;
  final String? quote;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_KeepsakeRow> createState() => _KeepsakeRowState();
}

class _KeepsakeRowState extends State<_KeepsakeRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          margin: const EdgeInsets.only(bottom: 8),
          padding: const EdgeInsets.fromLTRB(15, 12, 10, 12),
          decoration: BoxDecoration(
            color: hovered ? palette.hover : palette.page,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: palette.rule, width: 0.6),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(widget.icon, size: 16, color: widget.accent),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.ink,
                        fontSize: 13,
                        height: 1.45,
                      ),
                    ),
                    if (widget.quote case final quote?) ...[
                      const SizedBox(height: 4),
                      Text(
                        quote,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.inkMuted,
                          fontSize: 12,
                          height: 1.45,
                          fontStyle: FontStyle.italic,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: TextStyle(color: palette.inkFaint, fontSize: 11),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: BookReaderMetrics.motion,
                opacity: hovered ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !hovered,
                  child: BookControlButton(
                    icon: Icons.close_rounded,
                    tooltip: LocaleKeys.button_delete.tr(),
                    palette: palette,
                    onPressed: widget.onRemove,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _HeroButton extends StatefulWidget {
  const _HeroButton({
    required this.palette,
    required this.label,
    required this.onTap,
  });

  final BookReaderPalette palette;
  final String label;
  final VoidCallback onTap;

  @override
  State<_HeroButton> createState() => _HeroButtonState();
}

class _HeroButtonState extends State<_HeroButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 18),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: hovered
                ? Color.alphaBlend(
                    Colors.black.withValues(alpha: 0.10),
                    palette.accent,
                  )
                : palette.accent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.play_arrow_rounded,
                size: 17,
                color: palette.chrome,
              ),
              const SizedBox(width: 6),
              Text(
                widget.label,
                style: TextStyle(
                  color: palette.chrome,
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
