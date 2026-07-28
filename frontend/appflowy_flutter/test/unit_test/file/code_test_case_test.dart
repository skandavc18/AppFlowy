import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_test_case.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('judging output', () {
    test('trailing spaces and a missing final newline are not a failure', () {
      expect(
        codeTestOutputMatches(actual: '3   \n', expected: '3'),
        isTrue,
      );
      expect(
        codeTestOutputMatches(actual: '1\n2\n\n\n', expected: '1\n2'),
        isTrue,
      );
    });

    test('a program built on Windows is judged the same', () {
      expect(
        codeTestOutputMatches(actual: 'a\r\nb\r\n', expected: 'a\nb\n'),
        isTrue,
      );
    });

    test('different values are a wrong answer', () {
      expect(codeTestOutputMatches(actual: '3', expected: '4'), isFalse);
      // Blank lines inside the answer still count.
      expect(
        codeTestOutputMatches(actual: 'a\nb', expected: 'a\n\nb'),
        isFalse,
      );
      // Leading whitespace is part of the answer.
      expect(codeTestOutputMatches(actual: '  3', expected: '3'), isFalse);
    });

    test('nothing printed matches nothing expected', () {
      expect(codeTestOutputMatches(actual: '\n\n', expected: ''), isTrue);
    });
  });

  group('storing cases', () {
    test('a case survives a round trip through stored attributes', () {
      final cases = [
        const CodeTestCase(
          id: 'a',
          name: 'Case 1',
          input: '2 3',
          expectedOutput: '5',
        ),
        const CodeTestCase(id: 'b', name: 'Case 2'),
      ];
      expect(decodeCodeTestCases(encodeCodeTestCases(cases)), cases);
    });

    test('unreadable entries are dropped instead of thrown', () {
      // Stored attributes are data: one bad entry must not stop the code from
      // opening.
      final decoded = decodeCodeTestCases([
        {'id': 'a', 'name': 'Case 1', 'input': '1', 'expected': '1'},
        'not a case',
        {'name': 'no id'},
        42,
      ]);
      expect(decoded, hasLength(1));
      expect(decoded.single.id, 'a');
    });

    test('anything but a list reads as no cases at all', () {
      expect(decodeCodeTestCases(null), isEmpty);
      expect(decodeCodeTestCases('cases'), isEmpty);
    });

    test('a new case is named after its position', () {
      expect(createCodeTestCase(0).name, 'Case 1');
      expect(createCodeTestCase(2).name, 'Case 3');
      expect(createCodeTestCase(0).id, isNot(createCodeTestCase(1).id));
    });
  });

  group('summarizing a run', () {
    final cases = [
      const CodeTestCase(id: 'a', name: 'Case 1'),
      const CodeTestCase(id: 'b', name: 'Case 2'),
    ];

    test('nothing run yet has nothing to report', () {
      expect(summarizeCodeTests(cases, const {}), isNull);
      expect(
        summarizeCodeTests(cases, {
          'a': const CodeTestOutcome(status: CodeTestStatus.running),
        }),
        isNull,
      );
    });

    test('the score counts every case, not just the finished ones', () {
      final summary = summarizeCodeTests(cases, {
        'a': const CodeTestOutcome(status: CodeTestStatus.passed),
      })!;
      expect(summary.label, '1/2');
      expect(summary.allPassed, isFalse);
    });

    test('everything passing reads as a pass', () {
      final summary = summarizeCodeTests(cases, {
        'a': const CodeTestOutcome(status: CodeTestStatus.passed),
        'b': const CodeTestOutcome(status: CodeTestStatus.passed),
      })!;
      expect(summary.label, '2/2');
      expect(summary.allPassed, isTrue);
    });

    test('an error is not a pass', () {
      final summary = summarizeCodeTests(cases, {
        'a': const CodeTestOutcome(status: CodeTestStatus.passed),
        'b': const CodeTestOutcome(status: CodeTestStatus.errored),
      })!;
      expect(summary.label, '1/2');
      expect(summary.allPassed, isFalse);
    });
  });
}
