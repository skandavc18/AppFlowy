import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_format.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_controller.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

enum _RailTab { chapters, bookmarks, notes }

/// The book beside the book: contents, the spots that were kept, and the
/// notes that were made.
class BookContentsRail extends StatefulWidget {
  const BookContentsRail({
    super.key,
    required this.reading,
    required this.palette,
    required this.onOpenChapter,
    required this.onOpenInWorkspace,
    required this.onEditNote,
  });

  final BookReadingController reading;
  final BookReaderPalette palette;
  final ValueChanged<String> onOpenChapter;
  final ValueChanged<ViewPB> onOpenInWorkspace;
  final Future<void> Function(BookNote note, {BookChapter? chapter}) onEditNote;

  @override
  State<BookContentsRail> createState() => _BookContentsRailState();
}

class _BookContentsRailState extends State<BookContentsRail> {
  _RailTab tab = _RailTab.chapters;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: palette.chrome,
        border: Border(right: BorderSide(color: palette.rule, width: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildTabs(palette),
          Expanded(
            child: switch (tab) {
              _RailTab.chapters => _buildChapters(palette),
              _RailTab.bookmarks => _buildBookmarks(palette),
              _RailTab.notes => _buildNotes(palette),
            },
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(BookReaderPalette palette) {
    return Container(
      height: BookReaderMetrics.chromeHeight,
      padding: const EdgeInsets.fromLTRB(10, 11, 10, 11),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.rule, width: 0.6)),
      ),
      child: Row(
        children: [
          for (final value in _RailTab.values)
            Expanded(
              child: Padding(
                padding:
                    EdgeInsets.only(right: value == _RailTab.notes ? 0 : 6),
                child: _RailTabButton(
                  palette: palette,
                  label: switch (value) {
                    _RailTab.chapters =>
                      LocaleKeys.collections_book_chapters.tr(),
                    _RailTab.bookmarks =>
                      LocaleKeys.collections_book_bookmarks.tr(),
                    _RailTab.notes => LocaleKeys.collections_book_notes.tr(),
                  },
                  selected: tab == value,
                  onTap: () => setState(() => tab = value),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildChapters(BookReaderPalette palette) {
    final chapters = widget.reading.chapters;
    if (chapters.isEmpty) {
      return _empty(palette, LocaleKeys.collections_book_emptyTitle.tr());
    }
    final current = widget.reading.currentChapter?.id;
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: chapters.length,
      itemBuilder: (context, index) {
        final chapter = chapters[index];
        if (chapter.isPart) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 14, 6),
            child: Text(
              bookChapterTitle(chapter).toUpperCase(),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.inkFaint,
                fontSize: 10,
                letterSpacing: 0.8,
                fontWeight: FontWeight.w600,
              ),
            ),
          );
        }
        return _ChapterRow(
          palette: palette,
          chapter: chapter,
          number: chapter.index + 1,
          progress: widget.reading.state.progressFor(chapter.id),
          bookmarked: widget.reading.state.bookmarksIn(chapter.id).isNotEmpty,
          noteCount: widget.reading.state.notesIn(chapter.id).length,
          selected: chapter.id == current,
          onTap: () => widget.onOpenChapter(chapter.id),
          onOpenInWorkspace: () => widget.onOpenInWorkspace(chapter.view),
        );
      },
    );
  }

  Widget _buildBookmarks(BookReaderPalette palette) {
    final bookmarks = [...widget.reading.state.bookmarks]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (bookmarks.isEmpty) {
      return _empty(palette, LocaleKeys.collections_book_noBookmarks.tr());
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: bookmarks.length,
      itemBuilder: (context, index) {
        final bookmark = bookmarks[index];
        final chapter = _chapterOf(bookmark.chapterId);
        return _RailEntry(
          palette: palette,
          icon: Icons.bookmark_rounded,
          iconColor: palette.accent,
          title: bookmark.label.isNotEmpty
              ? bookmark.label
              : chapter == null
                  ? LocaleKeys.collections_book_untitledChapter.tr()
                  : bookChapterTitle(chapter),
          subtitle: LocaleKeys.collections_book_percentRead.tr(
            args: ['${(bookmark.offset * 100).round()}'],
          ),
          onTap: () => widget.onOpenChapter(bookmark.chapterId),
          onRemove: () => widget.reading.removeBookmark(bookmark.id),
        );
      },
    );
  }

  Widget _buildNotes(BookReaderPalette palette) {
    final notes = [...widget.reading.state.notes]
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
    if (notes.isEmpty) {
      return _empty(palette, LocaleKeys.collections_book_noNotes.tr());
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: notes.length,
      itemBuilder: (context, index) {
        final note = notes[index];
        final chapter = _chapterOf(note.chapterId);
        return _NoteCard(
          palette: palette,
          note: note,
          chapterName: chapter == null
              ? LocaleKeys.collections_book_untitledChapter.tr()
              : bookChapterTitle(chapter),
          onTap: () {
            widget.onOpenChapter(note.chapterId);
            widget.onEditNote(note, chapter: chapter);
          },
          onRemove: () => widget.reading.removeNote(note.id),
        );
      },
    );
  }

  BookChapter? _chapterOf(String id) {
    for (final chapter in widget.reading.chapters) {
      if (chapter.id == id) {
        return chapter;
      }
    }
    return null;
  }

  Widget _empty(BookReaderPalette palette, String message) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 30, 20, 20),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: TextStyle(color: palette.inkFaint, fontSize: 12, height: 1.5),
        ),
      );
}

class _RailTabButton extends StatelessWidget {
  const _RailTabButton({
    required this.palette,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final BookReaderPalette palette;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: selected
                ? palette.selected
                : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: selected ? palette.ink : palette.inkMuted,
              fontSize: 11.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterRow extends StatefulWidget {
  const _ChapterRow({
    required this.palette,
    required this.chapter,
    required this.number,
    required this.progress,
    required this.bookmarked,
    required this.noteCount,
    required this.selected,
    required this.onTap,
    required this.onOpenInWorkspace,
  });

  final BookReaderPalette palette;
  final BookChapter chapter;
  final int number;
  final double progress;
  final bool bookmarked;
  final int noteCount;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onOpenInWorkspace;

  @override
  State<_ChapterRow> createState() => _ChapterRowState();
}

class _ChapterRowState extends State<_ChapterRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final finished = widget.progress >= BookReadingState.finishedThreshold;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onDoubleTap: widget.onOpenInWorkspace,
        child: AnimatedContainer(
          duration: BookReaderMetrics.motion,
          curve: BookReaderMetrics.curve,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.selected
                : hovered
                    ? palette.hover
                    : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  SizedBox(
                    width: 22,
                    child: Text(
                      '${widget.number}',
                      style: TextStyle(
                        color:
                            widget.selected ? palette.accent : palette.inkFaint,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bookChapterTitle(widget.chapter),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.selected ? palette.ink : palette.inkMuted,
                        fontSize: 12.5,
                        height: 1.35,
                        fontWeight:
                            widget.selected ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ),
                  if (widget.bookmarked)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Icon(
                        Icons.bookmark_rounded,
                        size: 12,
                        color: palette.accent,
                      ),
                    ),
                  if (widget.noteCount > 0)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Text(
                        '${widget.noteCount}',
                        style: TextStyle(
                          color: palette.inkFaint,
                          fontSize: 10.5,
                        ),
                      ),
                    ),
                  if (finished)
                    Padding(
                      padding: const EdgeInsets.only(left: 5),
                      child: Icon(
                        Icons.check_circle_rounded,
                        size: 12,
                        color: palette.accent.withValues(alpha: 0.75),
                      ),
                    ),
                ],
              ),
              if (widget.progress > 0 && !finished) ...[
                const SizedBox(height: 6),
                Padding(
                  padding: const EdgeInsets.only(left: 22),
                  child: SizedBox(
                    height: 2,
                    child: LayoutBuilder(
                      builder: (context, constraints) => Stack(
                        children: [
                          Positioned.fill(
                            child: ColoredBox(
                              color: palette.rule.withValues(alpha: 0.5),
                            ),
                          ),
                          Container(
                            width: constraints.maxWidth * widget.progress,
                            color: palette.accent.withValues(alpha: 0.8),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RailEntry extends StatefulWidget {
  const _RailEntry({
    required this.palette,
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onRemove,
  });

  final BookReaderPalette palette;
  final IconData icon;
  final Color iconColor;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_RailEntry> createState() => _RailEntryState();
}

class _RailEntryState extends State<_RailEntry> {
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            color: hovered ? palette.hover : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(widget.icon, size: 14, color: widget.iconColor),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: palette.ink, fontSize: 12.5),
                    ),
                    Text(
                      widget.subtitle,
                      style: TextStyle(color: palette.inkFaint, fontSize: 10.5),
                    ),
                  ],
                ),
              ),
              AnimatedOpacity(
                duration: BookReaderMetrics.motion,
                opacity: hovered ? 1 : 0,
                child: IgnorePointer(
                  ignoring: !hovered,
                  child: GestureDetector(
                    onTap: widget.onRemove,
                    child: SizedBox(
                      width: 24,
                      height: 24,
                      child: Icon(
                        Icons.close_rounded,
                        size: 14,
                        color: palette.inkFaint,
                      ),
                    ),
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

class _NoteCard extends StatefulWidget {
  const _NoteCard({
    required this.palette,
    required this.note,
    required this.chapterName,
    required this.onTap,
    required this.onRemove,
  });

  final BookReaderPalette palette;
  final BookNote note;
  final String chapterName;
  final VoidCallback onTap;
  final VoidCallback onRemove;

  @override
  State<_NoteCard> createState() => _NoteCardState();
}

class _NoteCardState extends State<_NoteCard> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final note = widget.note;
    final accent = bookNoteColor(note.color, isDark: palette.theme.isDark);
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
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          padding: const EdgeInsets.fromLTRB(11, 9, 8, 10),
          decoration: BoxDecoration(
            color: hovered ? palette.hover : palette.hover.withValues(alpha: 0),
            borderRadius: BorderRadius.circular(9),
            border: Border(left: BorderSide(color: accent, width: 2.5)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.chapterName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.inkFaint,
                        fontSize: 10.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  AnimatedOpacity(
                    duration: BookReaderMetrics.motion,
                    opacity: hovered ? 1 : 0,
                    child: IgnorePointer(
                      ignoring: !hovered,
                      child: GestureDetector(
                        onTap: widget.onRemove,
                        child: Icon(
                          Icons.close_rounded,
                          size: 13,
                          color: palette.inkFaint,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (note.quote.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  note.quote,
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.ink,
                    fontSize: 12,
                    height: 1.45,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
              if (note.body.trim().isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(
                  note.body,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: palette.inkMuted,
                    fontSize: 12,
                    height: 1.45,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
