import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('repeated replacement moves past replacement text that still matches',
      () {
    var text = 'cat cat';
    final find = SurfaceFindController(
      search: (q, o) => searchSurfaceEntries(
          [SurfaceFindEntry('text', text, replaceable: true)], q, o),
      canReplace: () => true,
      applyReplacements: (edits) => text = edits.single.after,
    );
    addTearDown(find.dispose);
    find.open(replace: true);
    find.setQuery('cat');
    find.replacementController.text = 'cats';
    find.replaceCurrent();
    expect(text, 'cats cat');
    expect(find.current!.range.start, 5);
    find.replaceCurrent();
    expect(text, 'cats cats');
    expect(find.currentIndex, 0);
  });

  test('occurrences, options, invalid regex and navigation share one pattern',
      () {
    final find = SurfaceFindController(
      search: (query, options) => searchSurfaceEntries(
        const [SurfaceFindEntry('text', 'Cat cat scatter cat')],
        query,
        options,
      ),
    );
    addTearDown(find.dispose);
    find.open();
    find.setQuery('cat');
    expect(find.matches, hasLength(4));
    find.setOptions(const FindOptions(wholeWord: true));
    expect(find.matches, hasLength(3));
    find.step(-1);
    expect(find.current!.range.start, 16);
    find.step(1);
    expect(find.currentIndex, 0);
    find.setOptions(const FindOptions(caseSensitive: true, wholeWord: true));
    expect(find.matches, hasLength(2));
    find.setOptions(const FindOptions(useRegex: true));
    find.setQuery('[');
    expect(find.queryInvalid, isTrue);
    expect(find.matches, isEmpty);
    find.setQuery(r'(?=cat)');
    expect(find.matches, isEmpty,
        reason: 'Zero-width hits have no word to show.');
    find.close();
    expect(find.isOpen, isFalse);
    expect(find.matches, isEmpty);
  });

  test('live refresh retains the selected occurrence by field and offset', () {
    var entries = const [SurfaceFindEntry('a', 'find find')];
    final find = SurfaceFindController(
      search: (query, options) => searchSurfaceEntries(entries, query, options),
    );
    addTearDown(find.dispose);
    find.open();
    find.setQuery('find');
    find.step(1);
    entries = const [
      SurfaceFindEntry('earlier', 'find'),
      SurfaceFindEntry('a', 'find find streaming find'),
    ];
    find.refresh();
    expect(find.current!.id, 'a');
    expect(find.current!.range.start, 5);
    expect(find.currentIndex, 2);
    entries = const [];
    find.refresh();
    expect(find.current, isNull);
    expect(() => find.step(1), returnsNormally);
  });

  test('replace batches only editable text, expands captures, rechecks access',
      () {
    var writable = true;
    var entries = const [
      SurfaceFindEntry('own', 'cat cat', replaceable: true),
      SurfaceFindEntry('linked', 'cat'),
    ];
    final batches = <List<SurfaceFindReplacement>>[];
    final find = SurfaceFindController(
      search: (query, options) => searchSurfaceEntries(entries, query, options),
      canReplace: () => writable,
      applyReplacements: (edits) {
        batches.add(edits);
        entries = [
          for (final entry in entries)
            SurfaceFindEntry(
              entry.id,
              edits.where((edit) => edit.id == entry.id).firstOrNull?.after ??
                  entry.text,
              replaceable: entry.replaceable,
            ),
        ];
      },
    );
    addTearDown(find.dispose);
    find.open(replace: true);
    find.setOptions(const FindOptions(useRegex: true));
    find.setQuery('(cat)');
    find.replacementController.text = r'$1s';
    find.replaceAll();
    expect(batches, hasLength(1));
    expect(batches.single.single.before, 'cat cat');
    expect(entries.first.text, 'cats cats');
    expect(entries.last.text, 'cat');
    writable = false;
    find.replaceAll();
    expect(batches, hasLength(1));
    expect(find.supportsReplace, isFalse);
  });

  test('single replacement refuses a stale selected field', () {
    var text = 'needle';
    var writes = 0;
    final find = SurfaceFindController(
      search: (query, options) => searchSurfaceEntries(
        [SurfaceFindEntry('own', text, replaceable: true)],
        query,
        options,
      ),
      canReplace: () => true,
      applyReplacements: (_) => writes++,
    );
    addTearDown(find.dispose);
    find.open();
    find.setQuery('needle');
    text = 'needle changed';
    find.replacementController.text = 'replacement';
    find.replaceCurrent();
    expect(writes, 0);
    expect(find.current!.entry.text, text);
  });
}
