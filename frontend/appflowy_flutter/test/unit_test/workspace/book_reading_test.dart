import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_controller.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

ViewPB _page(String id, String name) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
    );

ViewPB _file(String id, String name) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: 'C:/books/chapter',
      ).mergeIntoExtra(''),
    );

ViewPB _folder(String id, String name) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

void main() {
  group('book chapters', () {
    test('classify by what the object actually is', () {
      expect(bookChapterKindOf(_page('a', 'Prologue')), BookChapterKind.page);
      expect(
        bookChapterKindOf(_file('b', 'chapter.md')),
        BookChapterKind.markdown,
      );
      expect(bookChapterKindOf(_file('c', 'notes.pdf')), BookChapterKind.pdf);
      expect(bookChapterKindOf(_file('d', 'raw.txt')), BookChapterKind.text);
      expect(bookChapterKindOf(_folder('e', 'Part I')), BookChapterKind.part);
      expect(
        bookChapterKindOf(_file('f', 'cover.png')),
        BookChapterKind.unsupported,
      );
      expect(
        bookChapterKindOf(
          ViewPB(id: 'g', name: 'Table', layout: ViewLayoutPB.Grid),
        ),
        BookChapterKind.unsupported,
      );
    });

    test('a collection inside a book reads as a part', () {
      final nested = ViewPB(
        id: 'n',
        name: 'Appendices',
        layout: ViewLayoutPB.Document,
        extra: CollectionMetadata.newExtra(CollectionKind.book),
      );

      expect(bookChapterKindOf(nested), BookChapterKind.part);
    });

    test('number readable entries in order and skip what cannot be read', () {
      final chapters = bookChaptersFrom([
        _page('one', 'One'),
        _file('art', 'cover.png'),
        _folder('part', 'Part II'),
        _file('two', 'two.md'),
      ]);

      expect(chapters.map((chapter) => chapter.id), ['one', 'part', 'two']);
      expect(chapters[0].index, 0);
      expect(chapters[1].index, -1);
      expect(chapters[2].index, 1);
    });
  });

  group('reading state', () {
    test('round trips through the collection envelope', () {
      final state = BookReadingState(
        chapterId: 'two',
        progress: const {'one': 1, 'two': 0.4},
        bookmarks: [
          BookBookmark(
            id: 'b1',
            chapterId: 'two',
            offset: 0.4,
            label: 'the good bit',
            createdAt: DateTime.fromMillisecondsSinceEpoch(1000),
          ),
        ],
        notes: [
          BookNote(
            id: 'n1',
            chapterId: 'one',
            offset: 0.2,
            quote: 'a line worth keeping',
            body: 'why it matters',
            color: BookNoteColor.blue,
            createdAt: DateTime.fromMillisecondsSinceEpoch(2000),
          ),
        ],
        settings: const BookReaderSettings(
          theme: BookReaderTheme.night,
          fontScale: 1.3,
          measure: BookReaderMeasure.wide,
          transition: BookPageTransition.slide,
          autoAdvance: false,
        ),
        stats: const BookReadingStats(totalSeconds: 640, sessions: 3),
      );

      final restored = BookReadingState.fromJson(state.toJson());

      expect(restored.chapterId, 'two');
      expect(restored.progressFor('one'), 1);
      expect(restored.bookmarks.single.label, 'the good bit');
      expect(restored.notes.single.color, BookNoteColor.blue);
      expect(restored.settings.theme, BookReaderTheme.night);
      expect(restored.settings.fontScale, 1.3);
      expect(restored.settings.autoAdvance, isFalse);
      expect(restored.stats.totalSeconds, 640);
    });

    test('an empty envelope reads as a fresh book', () {
      final state = BookReadingState.fromJson({});

      expect(state.chapterId, isNull);
      expect(state.settings.theme, BookReaderTheme.workspace);
      expect(state.settings.flow, BookReaderFlow.continuous);
      expect(state.overallProgress(const []), 0);
    });

    test('progress never goes backwards', () {
      const state = BookReadingState();

      final read = state.withProgress('one', 0.7);
      final scrolledBack = read.withProgress('one', 0.2);

      expect(read.progressFor('one'), 0.7);
      expect(identical(scrolledBack, read), isTrue);
    });

    test('overall progress weights every chapter equally and ignores parts',
        () {
      final chapters = bookChaptersFrom([
        _page('one', 'One'),
        _folder('part', 'Part'),
        _page('two', 'Two'),
      ]);
      const state = BookReadingState(progress: {'one': 1, 'two': 0.5});

      expect(state.overallProgress(chapters), closeTo(0.75, 0.0001));
      expect(state.finishedCount(chapters), 1);
    });

    test('drops everything belonging to chapters that were removed', () {
      final state = BookReadingState(
        progress: const {'one': 1, 'gone': 0.5},
        bookmarks: [
          BookBookmark(
            id: 'b',
            chapterId: 'gone',
            offset: 0,
            createdAt: DateTime.now(),
          ),
        ],
        notes: [
          BookNote(
            id: 'n',
            chapterId: 'gone',
            offset: 0,
            createdAt: DateTime.now(),
          ),
        ],
      );

      final pruned = state.prunedTo(['one']);

      expect(pruned.progress.keys, ['one']);
      expect(pruned.bookmarks, isEmpty);
      expect(pruned.notes, isEmpty);
      expect(identical(pruned.prunedTo(['one']), pruned), isTrue);
    });

    test('settings are clamped to what the reader can actually show', () {
      const settings = BookReaderSettings();

      expect(
        settings.copyWith(fontScale: 9).fontScale,
        BookReaderSettings.maximumFontScale,
      );
      expect(
        settings.copyWith(fontScale: 0.1).fontScale,
        BookReaderSettings.minimumFontScale,
      );
      expect(
        BookReaderSettings.fromJson({'theme': 'unknown'}).theme,
        BookReaderTheme.workspace,
      );
      expect(
        BookReaderSettings.fromJson({'flow': 'spiral'}).flow,
        BookReaderFlow.continuous,
      );
    });

    test('the reading flow and page turn round trip', () {
      const settings = BookReaderSettings(
        flow: BookReaderFlow.horizontal,
        transition: BookPageTransition.curl,
      );

      final restored = BookReaderSettings.fromJson(settings.toJson());

      expect(restored.flow, BookReaderFlow.horizontal);
      expect(restored.flow.turnsPages, isTrue);
      expect(restored.transition, BookPageTransition.curl);
      expect(BookReaderFlow.continuous.turnsPages, isFalse);
    });
  });

  group('reading statistics', () {
    test('bank time per day and forget history beyond the retention window',
        () {
      final today = DateTime(2026, 7, 30, 21);
      var stats = const BookReadingStats();

      stats = stats.recordSeconds(120, at: today);
      stats = stats.recordSeconds(60, at: today);
      stats = stats.recordSeconds(
        90,
        at: today.subtract(const Duration(days: 200)),
      );

      expect(stats.totalSeconds, 270);
      expect(stats.secondsOn(today), 180);
      stats = stats.recordSeconds(1, at: today);
      expect(
        stats.secondsOn(today.subtract(const Duration(days: 200))),
        0,
      );
    });

    test('a streak survives a day that has not been read yet', () {
      final today = DateTime(2026, 7, 30);
      var stats = const BookReadingStats();
      for (var day = 1; day <= 3; day++) {
        stats = stats.recordSeconds(
          60,
          at: today.subtract(Duration(days: day)),
        );
      }

      expect(stats.streakOn(today), 3);

      stats = stats.recordSeconds(60, at: today);
      expect(stats.streakOn(today), 4);
      expect(
        stats.streakOn(today.add(const Duration(days: 2))),
        0,
      );
    });
  });

  group('reading controller', () {
    late List<Map<String, dynamic>> persisted;

    BookReadingController build([Map<String, dynamic>? initial]) {
      persisted = [];
      return BookReadingController(
        initialState: initial ?? <String, dynamic>{},
        onPersist: persisted.add,
        persistDebounce: const Duration(days: 1),
      );
    }

    test('opens the first chapter and walks the book', () {
      final controller = build()
        ..setChapters(
          bookChaptersFrom([
            _folder('part', 'Part I'),
            _page('one', 'One'),
            _page('two', 'Two'),
          ]),
        );

      expect(controller.currentChapter?.id, 'one');
      expect(controller.previousChapter, isNull);
      expect(controller.goToNextChapter(), isTrue);
      expect(controller.currentChapter?.id, 'two');
      expect(controller.goToNextChapter(), isFalse);
      expect(controller.goToPreviousChapter(), isTrue);
      expect(controller.currentChapter?.id, 'one');

      controller.dispose();
    });

    test('falls back to the first chapter when the stored one is gone', () {
      final controller = build({'chapter': 'missing'})
        ..setChapters(bookChaptersFrom([_page('one', 'One')]));

      expect(controller.currentChapter?.id, 'one');

      controller.dispose();
    });

    test('keeps bookmarks and notes, and flushes them on dispose', () {
      final controller = build()
        ..setChapters(bookChaptersFrom([_page('one', 'One')]));

      final bookmark = controller.addBookmark(chapterId: 'one', offset: 0.42);
      final note = controller.addNote(
        chapterId: 'one',
        offset: 0.42,
        body: 'remember this',
      );
      controller.updateNote(note.id, color: BookNoteColor.green);

      expect(controller.state.bookmarksIn('one').single.id, bookmark.id);
      expect(controller.state.notesIn('one').single.color, BookNoteColor.green);

      controller.removeBookmark(bookmark.id);
      expect(controller.state.bookmarks, isEmpty);

      controller.dispose();
      expect(persisted, isNotEmpty);
      expect(
        BookReadingState.fromJson(persisted.last).notes.single.body,
        'remember this',
      );
    });

    test('reports progress forward only', () {
      final controller = build()
        ..setChapters(bookChaptersFrom([_page('one', 'One')]))
        ..reportProgress('one', 0.6)
        ..reportProgress('one', 0.3);

      expect(controller.state.progressFor('one'), 0.6);

      controller.dispose();
    });

    test('writes settings straight through', () {
      final controller = build()
        ..setChapters(bookChaptersFrom([_page('one', 'One')]));

      controller.toggleContentsRail();
      expect(controller.settings.showContentsRail, isFalse);

      controller.flush();
      expect(
        BookReadingState.fromJson(persisted.last).settings.showContentsRail,
        isFalse,
      );

      controller.dispose();
    });
  });
}
