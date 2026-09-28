import 'package:appflowy/plugins/document/presentation/editor_plugins/file/csv_find.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_find.dart';
import 'package:appflowy/shared/find_replace/surface_find.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('CSV entries preserve the already-displayed cells and row/column order',
      () {
    final entries = csvFindEntries(const [
      ['First', 'Second', ''],
      ['"one', 'two"', ' last '],
      ['a\tb', ''],
    ]).toList();
    expect(entries.map((entry) => entry.text),
        ['First', 'Second', '', '"one', 'two"', ' last ', 'a\tb', '']);
    expect(entries[5].id, (row: 1, column: 2));
    expect(entries.every((entry) => !entry.replaceable), isTrue);
    expect(searchSurfaceEntries(entries, ' last ', const FindOptions()),
        hasLength(1));
    expect(
        searchSurfaceEntries(entries, 'one,two', const FindOptions()), isEmpty);
  });

  test('read-only local Find checks live access on open, refresh and F3', () {
    var readable = true;
    final find = LocalFileFindController(
      canRead: () => readable,
      search: (query, options) => readable
          ? searchSurfaceEntries(
              const [SurfaceFindEntry('body', 'private needle')],
              query,
              options)
          : const [],
    );
    addTearDown(find.dispose);
    find.open(replace: true);
    find.setQuery('needle');
    expect(find.matches, hasLength(1));
    expect(find.supportsReplace, isFalse);
    expect(find.showReplace, isFalse);
    find.replacementController.text = 'changed';
    find.replaceAll();
    expect(find.current!.entry.text, 'private needle');

    readable = false; // No widget rebuild is needed for this access check.
    expect(find.matches, isEmpty);
    expect(find.current, isNull);
    find.step(1);
    expect(find.isOpen, isFalse);
    find.open();
    expect(find.isOpen, isFalse);
    readable = true;
    find.open();
    expect(find.matches, hasLength(1));
    readable = false;
    find.refresh();
    expect(find.isOpen, isFalse);
  });

  test('notebook output indexing follows displayed MIME precedence', () {
    final html = _fields(const NotebookOutput(
      kind: NotebookOutputKind.display,
      data: {
        'text/html': '<p>Visible <b>needle</b> &amp; text</p>',
        'text/plain': 'hidden plain fallback',
        'application/json': '{"hidden":"serialized secret"}',
      },
      metadata: {'hidden': 'output metadata secret'},
    ));
    expect(html.single.entry.text, 'Visible needle & text');
    expect(html.single.id, notebookOutputFindId('cell', 2, 'markup'));
    for (final hidden in ['fallback', 'serialized secret', 'metadata secret']) {
      expect(html.expand((field) => field.search(hidden, const FindOptions())),
          isEmpty);
    }

    for (final data in [
      {'image/png': 'YQ==', 'text/plain': 'hidden bitmap fallback'},
      {'image/svg+xml': '<svg>hidden SVG</svg>', 'text/plain': 'hidden SVG'},
    ]) {
      expect(
          _fields(NotebookOutput(kind: NotebookOutputKind.display, data: data)),
          isEmpty);
    }
    // An invalid bitmap really falls through to text in the existing viewer.
    expect(
      _fields(const NotebookOutput(
        kind: NotebookOutputKind.display,
        data: {'image/png': '!!', 'text/plain': 'actual fallback'},
      )).single.entry.text,
      'actual fallback',
    );
  });

  test('notebook markup projection omits hidden content and media attributes',
      () {
    final fields = _fields(const NotebookOutput(
      kind: NotebookOutputKind.display,
      data: {
        'text/html': '<p>Public <a href="attribute-secret">link</a></p>'
            '<script>script-secret</script><style>style-secret</style>'
            '<iframe>frame-secret</iframe><input value="input-secret">'
            '<textarea>textarea-secret</textarea>'
            '<img src="attachment:blob-secret" alt="alt-secret">'
            '<details><summary>Summary</summary><p>folded-secret</p></details>',
      },
    ));
    final text = fields.single.entry.text;
    expect(text, contains('Public link'));
    expect(text, contains('Summary'));
    for (final hidden in [
      'attribute-secret',
      'script-secret',
      'style-secret',
      'frame-secret',
      'input-secret',
      'textarea-secret',
      'blob-secret',
      'alt-secret',
      'folded-secret',
    ]) {
      expect(text, isNot(contains(hidden)));
    }
  });

  test('stream trimming and error fields match their native text widgets', () {
    expect(
      _fields(const NotebookOutput(
        kind: NotebookOutputKind.stream,
        text: '  visible\nline\n  ',
      )).single.entry.text,
      '  visible\nline',
    );
    final error = _fields(const NotebookOutput(
      kind: NotebookOutputKind.error,
      errorName: 'ValueError',
      errorValue: 'needle',
      traceback: ['\x1b[31mneedle\x1b[0m\n'],
    ));
    expect(error.map((field) => field.entry.text),
        ['ValueError: needle', 'needle']);
    expect(error.map((field) => field.id.part), ['error', 'traceback']);
    expect(error.every((field) => !field.entry.replaceable), isTrue);
  });

  test('off-screen markdown/code/table projection needs no widgets or fonts',
      () {
    expect(
      notebookMarkupFindParagraphs(
        '**Bold** and `code`.\n\n```python\nvalue = 42\n```\n',
        isHtml: false,
      ),
      ['Bold and code.', 'value = 42'],
    );
    expect(
      notebookMarkupFindParagraphs(
        '<ol start="3"><li>first</li><li>second<br>end</li></ol>'
        '<table><tr><th>Title</th></tr><tr><td>Value</td></tr></table>',
        isHtml: true,
      ),
      ['3.', 'first', '4.', 'second\nend', 'Title', 'Value'],
    );
  });

  test('paragraph search uses native boundaries and distinct stable offsets',
      () {
    final field = NotebookFindField(
      notebookOutputFindId('cell', 0, 'markup'),
      ['needle', 'needle'],
    );
    final matches = field.search('needle', const FindOptions()).toList();
    expect(matches.map((hit) => hit.range.start), [0, 7]);
    expect(matches.map((hit) => hit.range.end), [6, 13]);
    expect(matches.last.range.input, 'needle\nneedle');
    expect(matches.last.range.group(0), 'needle');
    expect(field.search(r'needle\s+needle', const FindOptions(useRegex: true)),
        isEmpty);
    expect(field.search('[', const FindOptions(useRegex: true)), isEmpty);

    final find = SurfaceFindController(
      search: (query, options) => field.search(query, options).toList(),
    );
    addTearDown(find.dispose);
    find.open();
    find.setQuery('needle');
    find.step(1);
    find.refresh();
    expect(find.currentIndex, 1);
    expect(find.occurrenceFor(field.id), 1);
  });
}

List<NotebookFindField> _fields(NotebookOutput output) =>
    notebookOutputFindFields('cell', 2, output);
