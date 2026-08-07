import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_document.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_kernel.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/notebook/notebook_markup.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const String _sampleNotebook = '''
{
 "cells": [
  {
   "cell_type": "markdown",
   "id": "intro",
   "metadata": {},
   "source": [
    "# Title\\n",
    "\\n",
    "<div class=\\"alert alert-success\\">\\n",
    "Jupyter notebooks combine code, output and text.\\n",
    "</div>"
   ]
  },
  {
   "cell_type": "code",
   "id": "first",
   "execution_count": 3,
   "metadata": {"tags": ["keep"]},
   "outputs": [
    {"output_type": "stream", "name": "stdout", "text": ["hello\\n", "world\\n"]},
    {
     "output_type": "execute_result",
     "execution_count": 3,
     "metadata": {},
     "data": {"text/plain": ["42"], "text/html": ["<b>42</b>"]}
    }
   ],
   "source": ["print('hello')\\n", "print('world')\\n", "42"]
  },
  {
   "cell_type": "code",
   "id": "second",
   "execution_count": null,
   "metadata": {},
   "outputs": [
    {
     "output_type": "error",
     "ename": "ValueError",
     "evalue": "bad",
     "traceback": ["\\u001b[0;31mValueError\\u001b[0m: bad"]
    }
   ],
   "source": ["raise ValueError('bad')"]
  }
 ],
 "metadata": {
  "kernelspec": {"display_name": "Python 3", "language": "python", "name": "python3"},
  "language_info": {"name": "python", "version": "3.12.1"},
  "authors": ["someone"]
 },
 "nbformat": 4,
 "nbformat_minor": 5
}
''';

void main() {
  group('reading a notebook', () {
    test('reads every cell with its type and source', () {
      final notebook = NotebookDocument.parse(_sampleNotebook);

      expect(notebook.cells.length, 3);
      expect(notebook.cells.first.type, NotebookCellType.markdown);
      expect(notebook.cells.first.source, contains('alert alert-success'));
      expect(notebook.cells[1].type, NotebookCellType.code);
      expect(
        notebook.cells[1].source,
        "print('hello')\nprint('world')\n42",
      );
      expect(notebook.cells[1].executionCount, 3);
      expect(notebook.cells[2].executionCount, isNull);
    });

    test('reads the language and the kernel name', () {
      final notebook = NotebookDocument.parse(_sampleNotebook);

      expect(notebook.language, 'python');
      expect(notebook.kernelName, 'Python 3');
      expect(notebook.codeCellCount, 2);
    });

    test('falls back to the kernel spec when there is no language info', () {
      final notebook = NotebookDocument.parse(
        '{"cells": [], "metadata": {"kernelspec": {"name": "python3"}}}',
      );

      expect(notebook.language, 'python');
    });

    test('reads printed text, rich results and failures', () {
      final cell = NotebookDocument.parse(_sampleNotebook).cells[1];

      expect(cell.outputs.length, 2);
      expect(cell.outputs.first.kind, NotebookOutputKind.stream);
      expect(cell.outputs.first.text, 'hello\nworld\n');
      expect(cell.outputs[1].kind, NotebookOutputKind.result);
      expect(cell.outputs[1].plainText, '42');
      expect(cell.outputs[1].html, '<b>42</b>');

      final failure = NotebookDocument.parse(_sampleNotebook).cells[2];
      expect(failure.outputs.single.isError, isTrue);
      expect(failure.outputs.single.errorName, 'ValueError');
      // The colour codes a terminal would interpret are not text to read.
      expect(failure.outputs.single.errorText, 'ValueError: bad');
    });

    test('refuses a file that is not a notebook', () {
      expect(
        () => NotebookDocument.parse('not json at all'),
        throwsA(isA<NotebookFormatException>()),
      );
      expect(
        () => NotebookDocument.parse('{"nbformat": 4}'),
        throwsA(isA<NotebookFormatException>()),
      );
    });
  });

  group('writing a notebook', () {
    test('a round trip keeps the cells, the outputs and the metadata', () {
      final original = NotebookDocument.parse(_sampleNotebook);
      final rewritten = NotebookDocument.parse(original.encode());

      expect(rewritten.cells.length, original.cells.length);
      for (var index = 0; index < rewritten.cells.length; index++) {
        expect(rewritten.cells[index].id, original.cells[index].id);
        expect(rewritten.cells[index].type, original.cells[index].type);
        expect(rewritten.cells[index].source, original.cells[index].source);
        expect(
          rewritten.cells[index].outputs.length,
          original.cells[index].outputs.length,
        );
      }
      expect(rewritten.cells[1].metadata['tags'], ['keep']);
      // Metadata AppFlowy has no use for still belongs to the file.
      expect(rewritten.metadata['authors'], ['someone']);
      expect(rewritten.nbformatMinor, 5);
    });

    test('stores text line by line, the way nbformat asks', () {
      expect(splitNotebookLines('a\nb\n'), ['a\n', 'b\n']);
      expect(splitNotebookLines('a\nb'), ['a\n', 'b']);
      expect(splitNotebookLines(''), isEmpty);
      expect(joinNotebookText(const ['a\n', 'b']), 'a\nb');
      expect(joinNotebookText('plain'), 'plain');
    });

    test('a blank notebook opens with one empty code cell', () {
      final notebook = NotebookDocument.blank();

      expect(notebook.cells.single.type, NotebookCellType.code);
      expect(notebook.cells.single.source, isEmpty);
      expect(notebook.language, 'python');
      expect(NotebookDocument.parse(notebook.encode()).cells.length, 1);
    });

    test('an image output keeps its base64 as one blob', () {
      final notebook = NotebookDocument(
        cells: [
          NotebookCell(
            id: 'a',
            type: NotebookCellType.code,
            source: 'plot()',
            outputs: const [
              NotebookOutput(
                kind: NotebookOutputKind.display,
                data: {'image/png': 'iVBORw0KGgo='},
              ),
            ],
          ),
        ],
      );

      final rewritten = NotebookDocument.parse(notebook.encode());
      expect(rewritten.cells.single.outputs.single.image?.key, 'image/png');
      expect(
        rewritten.cells.single.outputs.single.image?.value,
        'iVBORw0KGgo=',
      );
    });
  });

  group('editing cells', () {
    test('cells are inserted, moved and removed by index', () {
      var notebook = NotebookDocument.parse(_sampleNotebook);
      final added = NotebookCell.blank(NotebookCellType.markdown);

      notebook = notebook.withCellInserted(1, added);
      expect(notebook.cells[1].id, added.id);

      notebook = notebook.withCellMoved(1, -1);
      expect(notebook.cells.first.id, added.id);

      notebook = notebook.withCellRemoved(0);
      expect(notebook.indexOfCell(added.id), -1);
      expect(notebook.cells.length, 3);
    });

    test('moving past either end changes nothing', () {
      final notebook = NotebookDocument.parse(_sampleNotebook);

      expect(notebook.withCellMoved(0, -1).cells.first.id, 'intro');
      expect(notebook.withCellMoved(2, 1).cells.last.id, 'second');
    });

    test('printed text accumulates into one output', () {
      const first = NotebookOutput(
        kind: NotebookOutputKind.stream,
        name: 'stdout',
        text: 'one\n',
      );

      expect(first.appendText('two\n').text, 'one\ntwo\n');
    });

    test('every new cell gets an id of its own', () {
      final ids = {
        for (var index = 0; index < 50; index++) newNotebookCellId()
      };

      expect(ids.length, 50);
    });
  });

  group('running cells', () {
    test('only Python notebooks can be run here', () {
      expect(NotebookKernel.supportsLanguage('python'), isTrue);
      expect(NotebookKernel.supportsLanguage('Python 3'), isTrue);
      expect(NotebookKernel.supportsLanguage('r'), isFalse);
      expect(NotebookKernel.supportsLanguage('julia'), isFalse);
    });

    test('a notebook in another language says so instead of failing', () {
      final kernel = NotebookKernel(language: 'r', workingDirectory: '.');
      addTearDown(kernel.dispose);

      expect(kernel.canRun, isFalse);
      expect(kernel.blockedReason, contains('r'));
      expect(kernel.state, NotebookKernelState.stopped);
    });
  });

  group('lifting maths out of markdown', () {
    test('takes inline and display maths, leaving a placeholder', () {
      final extracted = extractNotebookMath(r'Let $x^2$ and $$\int_0^1 f$$.');

      expect(extracted.expressions, [r'x^2', r'\int_0^1 f']);
      expect(extracted.text.contains(r'x^2'), isFalse);
      expect(notebookMathPattern.allMatches(extracted.text).length, 2);
    });

    test('a dollar sign inside code is a prompt, not an equation', () {
      const source = 'Run `\$PATH` first.\n\n```sh\n\$ echo \$HOME\n```\n';
      final extracted = extractNotebookMath(source);

      expect(extracted.expressions, isEmpty);
      expect(extracted.text, source);
    });

    test('reads the TeX delimiters as well', () {
      final extracted = extractNotebookMath(r'\(a+b\) and \[c+d\]');

      expect(extracted.expressions, ['a+b', 'c+d']);
    });

    test('a lone dollar sign is left where it is', () {
      final extracted = extractNotebookMath(r'It costs $5 to enter.');

      expect(extracted.expressions, isEmpty);
      expect(extracted.text, r'It costs $5 to enter.');
    });
  });

  group('rendering a prose cell', () {
    testWidgets('HTML written inside markdown is drawn, not printed',
        (tester) async {
      await tester.pumpWidget(
        _themedApp(
          child: Builder(
            builder: (context) => SingleChildScrollView(
              child: NotebookMarkup(
                source: '# Heading\n\n'
                    '<div class="alert alert-success">\n'
                    'Notebooks combine code and text.\n'
                    '</div>\n',
                palette: CodeBlockPalette.resolve(context),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Notebooks combine code and text'), findsOne);
      expect(find.textContaining('<div'), findsNothing);
      expect(find.textContaining('alert-success'), findsNothing);
    });

    testWidgets('a table becomes a table', (tester) async {
      await tester.pumpWidget(
        _themedApp(
          child: Builder(
            builder: (context) => SingleChildScrollView(
              child: NotebookMarkup(
                source: '<table><tr><th>Name</th></tr>'
                    '<tr><td>Ada</td></tr></table>',
                isHtml: true,
                palette: CodeBlockPalette.resolve(context),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.byType(Table), findsOne);
      expect(find.textContaining('Ada'), findsOne);
      expect(find.textContaining('<td>'), findsNothing);
    });

    testWidgets('a script tag is dropped rather than shown', (tester) async {
      await tester.pumpWidget(
        _themedApp(
          child: Builder(
            builder: (context) => SingleChildScrollView(
              child: NotebookMarkup(
                source: '<p>Safe</p><script>alert(1)</script>',
                isHtml: true,
                palette: CodeBlockPalette.resolve(context),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      expect(find.textContaining('Safe'), findsOne);
      expect(find.textContaining('alert(1)'), findsNothing);
    });
  });

  group('decoding attachments', () {
    test('reads a base64 data uri', () {
      final bytes = decodeDataUri('data:image/png;base64,aGk=');

      expect(bytes, isNotNull);
      expect(String.fromCharCodes(bytes!), 'hi');
    });

    test('reads base64 that was wrapped over several lines', () {
      expect(decodeBase64('aG\nkg\ndGhlcmU='), isNotNull);
      expect(decodeBase64('   '), isNull);
      expect(decodeBase64('not base64!!'), isNull);
    });
  });
}

Widget _themedApp({
  required Widget child,
  Brightness brightness = Brightness.light,
}) {
  final defaultTheme = AppFlowyDefaultTheme();
  final baseAppFlowyTheme = brightness == Brightness.dark
      ? defaultTheme.dark()
      : defaultTheme.light();
  final materialTheme = DesktopAppearance().getThemeData(
    AppTheme.fallback,
    brightness,
    defaultFontFamily,
    builtInCodeFontFamily,
  );
  final palette = materialTheme.extension<PremiumThemeExtension>()!;
  return MaterialApp(
    theme: materialTheme,
    home: AppFlowyTheme(
      data: PremiumTheme.appFlowyTheme(
        base: baseAppFlowyTheme,
        palette: palette,
        brightness: brightness,
      ),
      child: Scaffold(body: child),
    ),
  );
}
