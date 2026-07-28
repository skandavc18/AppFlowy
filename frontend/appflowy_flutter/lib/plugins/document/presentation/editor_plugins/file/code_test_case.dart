/// Saved inputs and expected answers for a piece of code, the way a coding
/// site poses a problem: the program is fed one case at a time on stdin and
/// what it prints is compared with what it should have printed.
///
/// Cases belong to the code they test, so they travel with the block in a
/// document and with the file in the viewer.
library;

/// One case: what to type in, and what should come back out.
class CodeTestCase {
  const CodeTestCase({
    required this.id,
    required this.name,
    this.input = '',
    this.expectedOutput = '',
  });

  final String id;
  final String name;

  /// Handed to the program on stdin, exactly as written.
  final String input;

  /// What the program is expected to print on stdout.
  final String expectedOutput;

  CodeTestCase copyWith({
    String? name,
    String? input,
    String? expectedOutput,
  }) =>
      CodeTestCase(
        id: id,
        name: name ?? this.name,
        input: input ?? this.input,
        expectedOutput: expectedOutput ?? this.expectedOutput,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'input': input,
        'expected': expectedOutput,
      };

  static CodeTestCase? fromJson(Object? value) {
    if (value is! Map) {
      return null;
    }
    final id = value['id'];
    if (id is! String || id.isEmpty) {
      return null;
    }
    return CodeTestCase(
      id: id,
      name: value['name'] as String? ?? 'Case',
      input: value['input'] as String? ?? '',
      expectedOutput: value['expected'] as String? ?? '',
    );
  }

  @override
  bool operator ==(Object other) =>
      other is CodeTestCase &&
      other.id == id &&
      other.name == name &&
      other.input == input &&
      other.expectedOutput == expectedOutput;

  @override
  int get hashCode => Object.hash(id, name, input, expectedOutput);
}

/// Where one case stands.
enum CodeTestStatus {
  /// Written down but never run.
  pending,

  running,

  /// The program printed exactly what was expected.
  passed,

  /// The program ran, but printed something else.
  failed,

  /// The program did not finish: it crashed, timed out or would not build.
  errored,
}

/// What actually happened when a case was run.
class CodeTestOutcome {
  const CodeTestOutcome({
    required this.status,
    this.output = '',
    this.errorOutput = '',
    this.notice = '',
    this.exitCode = 0,
    this.duration = Duration.zero,
  });

  final CodeTestStatus status;

  /// Everything the program printed on stdout.
  final String output;

  /// Everything the program printed on stderr.
  final String errorOutput;

  /// A message from the runner rather than the program: a missing toolchain,
  /// a failed compile, a timeout.
  final String notice;

  final int exitCode;
  final Duration duration;

  bool get isFinished =>
      status != CodeTestStatus.pending && status != CodeTestStatus.running;
}

/// How a whole run went, shown next to the tests button.
class CodeTestSummary {
  const CodeTestSummary({required this.passed, required this.total});

  final int passed;
  final int total;

  bool get allPassed => total > 0 && passed == total;

  String get label => '$passed/$total';
}

/// Reduces the outcomes of [cases] to a score, or null while nothing has been
/// run yet.
CodeTestSummary? summarizeCodeTests(
  List<CodeTestCase> cases,
  Map<String, CodeTestOutcome> outcomes,
) {
  final finished = [
    for (final testCase in cases)
      if (outcomes[testCase.id]?.isFinished ?? false) outcomes[testCase.id]!,
  ];
  if (finished.isEmpty) {
    return null;
  }
  return CodeTestSummary(
    passed: finished.where((o) => o.status == CodeTestStatus.passed).length,
    total: cases.length,
  );
}

/// Trailing spaces and a missing final newline are not a wrong answer.
///
/// Line endings are levelled too, so a program built on Windows is judged the
/// same as one built anywhere else.
String normalizeCodeTestOutput(String value) {
  final lines =
      value.replaceAll('\r\n', '\n').replaceAll('\r', '\n').split('\n');
  final trimmed = [for (final line in lines) line.trimRight()];
  while (trimmed.isNotEmpty && trimmed.last.isEmpty) {
    trimmed.removeLast();
  }
  return trimmed.join('\n');
}

/// Whether what the program printed counts as the expected answer.
bool codeTestOutputMatches({
  required String actual,
  required String expected,
}) =>
    normalizeCodeTestOutput(actual) == normalizeCodeTestOutput(expected);

/// Reads back cases stored in a document node or in a file's view metadata.
///
/// Anything unreadable is dropped rather than thrown: stored attributes are
/// data, and a malformed entry must not stop the code from opening.
List<CodeTestCase> decodeCodeTestCases(Object? value) {
  if (value is! List) {
    return const [];
  }
  return [
    for (final entry in value)
      if (CodeTestCase.fromJson(entry) case final testCase?) testCase,
  ];
}

List<Map<String, dynamic>> encodeCodeTestCases(List<CodeTestCase> cases) =>
    [for (final testCase in cases) testCase.toJson()];

/// A fresh, empty case named after its position in the list.
CodeTestCase createCodeTestCase(int index) => CodeTestCase(
      id: 'tc_${DateTime.now().microsecondsSinceEpoch.toRadixString(36)}_$index',
      name: 'Case ${index + 1}',
    );
