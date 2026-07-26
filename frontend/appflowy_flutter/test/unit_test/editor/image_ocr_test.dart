import 'dart:ui';

import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_result.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/ocr/ocr_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Windows OCR output', () {
    final engine = WindowsOcrEngine();

    test('normalizes word boxes against the reported frame', () {
      final result = engine.parseWindowsOutput(
        '{"width":200,"height":100,"lines":['
        '{"text":"Hello there","words":['
        '{"text":"Hello","x":20,"y":10,"w":40,"h":20},'
        '{"text":"there","x":70,"y":10,"w":50,"h":20}]}]}',
      );

      expect(result.lines, hasLength(1));
      expect(result.text, 'Hello there');
      expect(result.engine, 'Windows OCR');

      final line = result.lines.single;
      expect(line.words, hasLength(2));
      expect(line.words.first.bounds.left, closeTo(0.1, 1e-9));
      expect(line.words.first.bounds.width, closeTo(0.2, 1e-9));
      // The line box has to wrap every word it owns.
      expect(line.bounds.left, closeTo(0.1, 1e-9));
      expect(line.bounds.right, closeTo(0.6, 1e-9));
      expect(line.bounds.top, closeTo(0.1, 1e-9));
      expect(line.bounds.bottom, closeTo(0.3, 1e-9));
    });

    test('accepts the unwrapped single element PowerShell emits', () {
      final result = engine.parseWindowsOutput(
        '{"width":100,"height":100,"lines":'
        '{"text":"Solo","words":{"text":"Solo","x":0,"y":0,"w":50,"h":10}}}',
      );

      expect(result.lines, hasLength(1));
      expect(result.lines.single.words, hasLength(1));
      expect(result.text, 'Solo');
    });

    test('drops empty lines and reports nothing for an empty frame', () {
      expect(
        engine.parseWindowsOutput('{"width":0,"height":0,"lines":[]}').isEmpty,
        isTrue,
      );
      expect(
        engine
            .parseWindowsOutput(
              '{"width":10,"height":10,"lines":[{"text":"  ","words":[]}]}',
            )
            .isEmpty,
        isTrue,
      );
    });
  });

  group('Tesseract TSV', () {
    final engine = TesseractOcrEngine();

    const header = 'level\tpage_num\tblock_num\tpar_num\tline_num\tword_num\t'
        'left\ttop\twidth\theight\tconf\ttext';

    test('groups words into the lines the engine reported', () {
      final result = engine.parseTsv(
        '$header\n'
        '5\t1\t1\t1\t1\t1\t10\t20\t30\t10\t95\tHello\n'
        '5\t1\t1\t1\t1\t2\t50\t20\t40\t10\t92\tworld\n'
        '5\t1\t1\t1\t2\t1\t10\t40\t60\t10\t88\tSecond\n',
        const Size(100, 100),
      );

      expect(result.lines, hasLength(2));
      expect(result.lines.first.text, 'Hello world');
      expect(result.lines.last.text, 'Second');
      expect(result.text, 'Hello world\nSecond');
      expect(result.lines.first.words.first.bounds.left, closeTo(0.1, 1e-9));
      expect(result.lines.first.words.first.confidence, closeTo(0.95, 1e-9));
    });

    test('skips rows without confidence or text', () {
      final result = engine.parseTsv(
        '$header\n'
        '4\t1\t1\t1\t1\t0\t0\t0\t0\t0\t-1\t\n'
        '5\t1\t1\t1\t1\t1\t10\t20\t30\t10\t90\tKeep\n',
        const Size(100, 100),
      );

      expect(result.lines, hasLength(1));
      expect(result.text, 'Keep');
    });

    test('refuses output whose columns it does not recognise', () {
      expect(
        () => engine.parseTsv('a\tb\tc\n1\t2\t3\n', const Size(100, 100)),
        throwsA(isA<OcrUnavailableException>()),
      );
    });
  });

  group('result helpers', () {
    test('copies only the requested lines, in reading order', () {
      const result = OcrResult(
        engine: 'test',
        lines: [
          OcrLine(text: 'one', bounds: Rect.zero, words: []),
          OcrLine(text: 'two', bounds: Rect.zero, words: []),
          OcrLine(text: 'three', bounds: Rect.zero, words: []),
        ],
      );

      expect(result.textOf({2, 0}), 'one\nthree');
      expect(result.textOf(const <int>[]), '');
      expect(result.textOf({9}), '');
      expect(result.text, 'one\ntwo\nthree');
    });
  });
}
