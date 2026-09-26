import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_find_session.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

// Intentionally UNRUN in the restricted implementation session.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late OcrFindSession session;
  setUp(() => session = OcrFindSession());
  tearDown(() => session.dispose());

  test('case-insensitive by default; next/previous select actual words', () {
    session.setResult(_result());
    session.findController.text = 'world';
    expect(session.options.caseSensitive, isFalse);
    expect(session.matches, hasLength(2));
    expect(session.selected, {1});
    expect(session.currentText, 'WORLD');
    expect(
      session.boundsOf(session.selected),
      [_result().lines[0].words[1].bounds],
    );
    session.next();
    expect(session.displayIndex, 2);
    expect(session.selectedText, 'worldwide');
    expect(session.selected, {3});
    session.next();
    expect(session.displayIndex, 1);
    session.previous();
    expect(session.displayIndex, 2);
  });

  test('query before recognition is rerun when the result arrives', () {
    session.findController.text = 'HELLO';
    expect(session.matches, isEmpty);
    expect(session.displayIndex, 0);
    session.setResult(_result());
    expect(session.query, 'HELLO');
    expect(session.matches, hasLength(2));
    expect(session.selectedText, 'Hello');
  });

  test('a phrase crosses OCR lines and keeps original copy line breaks', () {
    session.setResult(_result());
    session.findController.text = 'WORLD hello';
    expect(session.matches, hasLength(1));
    expect(session.selected, {1, 2});
    expect(session.selectedText, 'WORLD\nhello');
    expect(session.boundsOf(session.selected), hasLength(2));
  });

  test('case, whole-word, literal metacharacters, regex and UTF-16 offsets',
      () {
    session.setResult(_result());
    session.findController.text = 'world';
    session.options = const FindOptions(wholeWord: true);
    expect(session.matches, hasLength(1));
    session.options = const FindOptions(wholeWord: true, caseSensitive: true);
    expect(session.matches, isEmpty);
    session.options = const FindOptions();
    session.findController.text = '[v1].*';
    expect(session.selectedText, '[v1].*');
    session.findController.text = '🙂';
    expect(
      session.currentMatch!.range.end - session.currentMatch!.range.start,
      2,
    );
    session.options = const FindOptions(useRegex: true);
    session.findController.text = r'world\w*';
    expect(session.matches, hasLength(2));
  });

  test('whole-word punctuation follows the shared conditional boundaries', () {
    session.setResult(
      OcrResult(
        engine: 'test',
        lines: [
          OcrLine.fromWords([
            const OcrWord(text: 'a--flag', bounds: Rect.zero),
            const OcrWord(text: '--flag', bounds: Rect.zero),
          ]),
        ],
      ),
    );
    session.options = const FindOptions(wholeWord: true);
    session.findController.text = '--flag';
    expect(
      session.matches.length,
      findMatches(session.text, '--flag', session.options).length,
    );
  });

  test('query selection/caret changes do not jump back to the first match', () {
    session.setResult(_result());
    session.findController.text = 'hello';
    session.next();
    session.findController.selection =
        const TextSelection(baseOffset: 1, extentOffset: 4);
    expect(session.displayIndex, 2);
    expect(session.selectedText, 'hello');
  });

  test('invalid, zero-width, empty and whitespace queries clear matches', () {
    session.setResult(_result());
    session.options = const FindOptions(useRegex: true);
    session.findController.text = '[';
    expect(session.invalid, isTrue);
    expect(session.displayIndex, 0);
    for (final query in ['(?=hello)', '', '   ']) {
      session.findController.text = query;
      expect(session.invalid, isFalse);
      expect(session.matches, isEmpty);
      expect(session.selected, isEmpty);
    }
  });

  test('same text with new geometry replaces bounds; pending clears old hits',
      () {
    session.setResult(_result());
    session.findController.text = 'Hello';
    final old = session.boundsOf(session.selected);
    session.setResult(_result(shift: .2));
    expect(session.boundsOf(session.selected), isNot(old));
    expect(session.boundsOf(session.selected).single.left, closeTo(.3, 1e-9));
    session.setResult(null);
    expect(session.query, 'Hello');
    expect(session.words, isEmpty);
    expect(session.matches, isEmpty);
    expect(session.selectedText, isEmpty);
    session.setResult(_result());
    expect(session.matches, hasLength(2));
  });

  test('selection is deduplicated in reading order and never expands a line',
      () {
    session.setResult(_result());
    session.selectWords([3, 1, 1, -1, 400]);
    expect(session.selectedText, 'WORLD\nworldwide');
    session.selectWords([1, 1, 2], additive: true);
    expect(session.selectedText, 'hello worldwide');
    session.selectAll();
    expect(session.selectedText, session.text);
    session.selectWords([]);
    expect(session.selectedText, isEmpty);
  });

  test('bad bounds never make invisible words full-photo highlights', () {
    final clipped = normalizedOcrBounds(const Rect.fromLTWH(-.1, .8, .4, .5));
    expect(clipped.left, 0);
    expect(clipped.top, .8);
    expect(clipped.right, closeTo(.3, 1e-9));
    expect(clipped.bottom, 1);
    for (final bounds in [
      Rect.zero,
      const Rect.fromLTWH(2, 2, .1, .1),
      const Rect.fromLTWH(double.nan, 0, 1, 1),
      const Rect.fromLTWH(0, 0, double.infinity, 1),
    ]) {
      expect(normalizedOcrBounds(bounds), Rect.zero);
    }
    session.setResult(
      const OcrResult(
        engine: 'test',
        lines: [
          OcrLine(text: 'Readable', bounds: Rect.zero, words: []),
        ],
      ),
    );
    session.findController.text = 'read';
    expect(session.currentText, 'Readable');
    expect(session.boundsOf(session.selected), isEmpty);
  });

  test('published selections and results cannot be mutated by a painter', () {
    session.setResult(_result());
    session.findController.text = 'hello';
    expect(() => session.selected.add(5), throwsUnsupportedError);
    expect(() => session.matches.clear(), throwsUnsupportedError);
    expect(() => session.words.clear(), throwsUnsupportedError);
    expect(
      () => session.matches.first.wordIndices.clear(),
      throwsUnsupportedError,
    );
  });

  test(
      'native spacing and contiguous-language words remain searchable/copyable',
      () {
    session.setResult(
      OcrResult(
        engine: 'test',
        lines: [
          OcrLine.fromWords(
            const [
              OcrWord(text: 'Hello', bounds: Rect.zero),
              OcrWord(text: 'world', bounds: Rect.zero),
            ],
            text: 'Hello   world',
          ),
          OcrLine.fromWords(
            const [
              OcrWord(text: '你好', bounds: Rect.zero),
              OcrWord(text: '世界', bounds: Rect.zero),
            ],
            text: '你好世界',
          ),
        ],
      ),
    );
    session.findController.text = 'hello world';
    expect(session.selectedText, 'Hello   world');
    session.findController.text = '你好世界';
    expect(session.matches, hasLength(1));
    expect(session.selectedText, '你好世界');
    expect(session.selected, {2, 3});
  });

  test('disposed session drops indexed text and ignores late updates', () {
    session.setResult(_result());
    session.findController.text = 'hello';
    session.dispose();
    session.setResult(_result());
    session.next();
    session.selectAll();
    expect(session.words, isEmpty);
    expect(session.matches, isEmpty);
    expect(session.selectedText, isEmpty);
    expect(session.currentMatch, isNull);
    expect(session.displayIndex, 0);
  });
}

OcrResult _result({double shift = 0}) => OcrResult(
      engine: 'Test local OCR',
      lines: [
        OcrLine.fromWords([
          OcrWord(
            text: 'Hello',
            bounds: Rect.fromLTWH(.1 + shift, .1, .15, .1),
          ),
          const OcrWord(text: 'WORLD', bounds: Rect.fromLTWH(.5, .1, .25, .1)),
        ]),
        OcrLine.fromWords(const [
          OcrWord(text: 'hello', bounds: Rect.fromLTWH(.1, .4, .15, .1)),
          OcrWord(text: 'worldwide', bounds: Rect.fromLTWH(.5, .4, .3, .1)),
        ]),
        OcrLine.fromWords(const [
          OcrWord(text: '[v1].*', bounds: Rect.fromLTWH(.1, .7, .2, .1)),
          OcrWord(text: '🙂', bounds: Rect.fromLTWH(.5, .7, .1, .1)),
        ]),
      ],
    );
