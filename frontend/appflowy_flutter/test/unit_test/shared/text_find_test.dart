import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('finding text in a file', () {
    test('a plain query is taken literally', () {
      const options = FindOptions();
      expect(findMatches('a.b acb', 'a.b', options), hasLength(1));
      expect(findMatches('a.b acb', 'a.b', options).single.start, 0);
    });

    test('an expression is only read as one when it is asked for', () {
      const literal = FindOptions();
      const expression = FindOptions(useRegex: true);
      expect(findMatches('a.b acb', 'a.b', literal), hasLength(1));
      expect(findMatches('a.b acb', 'a.b', expression), hasLength(2));
    });

    test('case is ignored until it is asked for', () {
      expect(findMatches('Cat cat', 'cat', const FindOptions()), hasLength(2));
      expect(
        findMatches('Cat cat', 'cat', const FindOptions(caseSensitive: true)),
        hasLength(1),
      );
    });

    test('whole word does not match inside a longer word', () {
      const options = FindOptions(wholeWord: true);
      expect(findMatches('cat cataract', 'cat', options), hasLength(1));
      expect(findMatches('cat cataract', 'cat', options).single.start, 0);
    });

    test('whole word still matches a query wrapped in punctuation', () {
      // A boundary either side would refuse this outright, which is why the
      // rule is written with lookarounds and only where a word really ends.
      const options = FindOptions(wholeWord: true);
      expect(findMatches('use --flag now', '--flag', options), hasLength(1));
      expect(findMatches('call() again', 'call()', options), hasLength(1));
    });

    test('an unfinished expression finds nothing rather than throwing', () {
      const options = FindOptions(useRegex: true);
      expect(isFindQueryValid('a(', options), isFalse);
      expect(findMatches('aaa', 'a(', options), isEmpty);
      expect(isFindQueryValid('a(', const FindOptions()), isTrue);
    });

    test('a pattern that matches nothing at all is discarded', () {
      // `a*` matches the empty string between every pair of characters; a
      // result at every offset is noise, not a search.
      expect(
        findMatches('bbb', 'a*', const FindOptions(useRegex: true)),
        isEmpty,
      );
    });

    test('an empty query has no matches', () {
      expect(findMatches('anything', '', const FindOptions()), isEmpty);
    });
  });

  group('replacing what was found', () {
    test('a replacement stays literal outside expression mode', () {
      expect(
        replaceAllMatches('cost 5', '5', r'$1 \1', const FindOptions()),
        r'cost $1 \1',
      );
    });

    test('an expression replacement can name its groups', () {
      const options = FindOptions(useRegex: true);
      expect(
        replaceAllMatches('Doe, John', r'(\w+), (\w+)', r'$2 $1', options),
        'John Doe',
      );
      expect(
        replaceAllMatches('Doe, John', r'(\w+), (\w+)', r'\2 \1', options),
        'John Doe',
      );
    });

    test('a doubled marker writes the marker itself', () {
      const options = FindOptions(useRegex: true);
      expect(replaceAllMatches('x', 'x', r'$$', options), r'$');
      expect(replaceAllMatches('x', 'x', r'$&!', options), 'x!');
    });

    test('a group that does not exist is left alone', () {
      const options = FindOptions(useRegex: true);
      expect(replaceAllMatches('x', 'x', r'$7', options), r'$7');
    });

    test('every match is replaced in one pass', () {
      expect(
        replaceAllMatches('a a a', 'a', 'b', const FindOptions()),
        'b b b',
      );
    });
  });

  group('walking between matches', () {
    final matches = findMatches('a a a', 'a', const FindOptions());

    test('forward takes the first match at or after the caret', () {
      expect(matchIndexFrom(matches, 0), 0);
      expect(matchIndexFrom(matches, 1), 1);
      expect(matchIndexFrom(matches, 3), 2);
    });

    test('forward wraps to the top when the caret is past the last match', () {
      expect(matchIndexFrom(matches, 99), 0);
    });

    test('backward takes the last match before the caret and wraps', () {
      expect(matchIndexFrom(matches, 3, forward: false), 1);
      expect(matchIndexFrom(matches, 0, forward: false), 2);
    });

    test('there is nowhere to go when nothing matched', () {
      expect(matchIndexFrom(const [], 0), isNull);
    });
  });

  group('marking matches in styled text', () {
    test('the text itself is untouched', () {
      const source = TextSpan(
        children: [
          TextSpan(text: 'final '),
          TextSpan(text: 'answer'),
          TextSpan(text: ' = answer;'),
        ],
      );
      final highlighted = applyFindHighlights(
        source,
        ranges: const [
          TextRange(start: 6, end: 12),
          TextRange(start: 15, end: 21),
        ],
        matchStyle: const TextStyle(backgroundColor: Color(0x33FF0000)),
      );
      expect(highlighted.toPlainText(), source.toPlainText());
    });

    test('a match inside one run is split out and painted', () {
      const source = TextSpan(text: 'the cat sat');
      final highlighted = applyFindHighlights(
        source,
        ranges: const [TextRange(start: 4, end: 7)],
        matchStyle: const TextStyle(backgroundColor: Color(0x33FF0000)),
      );
      final children = highlighted.children!.cast<TextSpan>();
      expect(children.map((span) => span.text), ['the ', 'cat', ' sat']);
      expect(children[1].style?.backgroundColor, const Color(0x33FF0000));
      expect(children[0].style?.backgroundColor, isNull);
    });

    test('the match being read is painted differently from the rest', () {
      const source = TextSpan(text: 'aa aa');
      final highlighted = applyFindHighlights(
        source,
        ranges: const [
          TextRange(start: 0, end: 2),
          TextRange(start: 3, end: 5),
        ],
        current: const TextRange(start: 3, end: 5),
        matchStyle: const TextStyle(backgroundColor: Color(0x11000000)),
        currentStyle: const TextStyle(backgroundColor: Color(0x99000000)),
      );
      final children = highlighted.children!.cast<TextSpan>();
      expect(children.first.style?.backgroundColor, const Color(0x11000000));
      expect(children.last.style?.backgroundColor, const Color(0x99000000));
    });

    test('nothing found leaves the span as it was', () {
      const source = TextSpan(text: 'unchanged');
      expect(
        identical(
          applyFindHighlights(
            source,
            ranges: const [],
            matchStyle: const TextStyle(),
          ),
          source,
        ),
        isTrue,
      );
    });
  });

  group('searching a rendered document', () {
    test('the expression handed to the renderer honours the switches', () {
      expect(
        buildWebViewFindCommand('a.b', const FindOptions()),
        contains(r'a\\.b'),
      );
      expect(
        buildWebViewFindCommand('a', const FindOptions()),
        contains('"gmi"'),
      );
      expect(
        buildWebViewFindCommand('a', const FindOptions(caseSensitive: true)),
        contains('"gm"'),
      );
    });

    test('what the renderer reports is read back', () {
      final result = WebViewFindResult.fromJavaScript({
        'count': 4,
        'index': 2,
      });
      expect(result.count, 4);
      expect(result.index, 2);
      expect(result.invalid, isFalse);
      expect(
        WebViewFindResult.fromJavaScript({'invalid': true}).invalid,
        isTrue,
      );
      expect(WebViewFindResult.fromJavaScript(null).count, 0);
    });
  });

  group('a find bar over a piece of text', () {
    test('it counts, walks and wraps', () {
      final session = TextFindSession()..setText('a a a');
      session.findController.text = 'a';
      expect(session.matches, hasLength(3));
      expect(session.displayIndex, 1);
      session.next();
      expect(session.displayIndex, 2);
      session
        ..next()
        ..next();
      expect(session.displayIndex, 1);
      session.previous();
      expect(session.displayIndex, 3);
      session.dispose();
    });

    test('it opens on the match beside the caret', () {
      final session = TextFindSession()..setText('a a a', caret: 4);
      session.findController.text = 'a';
      expect(session.displayIndex, 3);
      session.dispose();
    });

    test('replacing hands back the rewritten text', () {
      final session = TextFindSession()..setText('a a');
      session.findController.text = 'a';
      session.replaceController.text = 'b';
      expect(session.replaceCurrent(), 'b a');
      expect(session.replaceAll(), 'b b');
      session.dispose();
    });

    test('replacing steps on to the next match', () {
      final session = TextFindSession()..setText('a a a');
      session.findController.text = 'a';
      session.replaceController.text = 'b';
      final once = session.replaceCurrent()!;
      session.setText(once, keepPosition: false);
      expect(session.matches, hasLength(2));
      expect(session.matches.first.start, 2);
      expect(session.displayIndex, 1);
      session.dispose();
    });

    test('a replacement that still matches does not trap the search', () {
      final session = TextFindSession()..setText('a a');
      session.findController.text = 'a';
      session.replaceController.text = 'aa';
      final once = session.replaceCurrent()!;
      expect(once, 'aa a');
      session.setText(once, keepPosition: false);
      // The caret sits past what was just written, so the search moves on to
      // the untouched word instead of replacing itself for ever.
      expect(session.currentMatch!.start, 3);
      session.dispose();
    });

    test('an option change is reflected at once', () {
      final session = TextFindSession()..setText('Cat cat');
      session.findController.text = 'cat';
      expect(session.matches, hasLength(2));
      session.options = const FindOptions(caseSensitive: true);
      expect(session.matches, hasLength(1));
      session.dispose();
    });
  });
}
