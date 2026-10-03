import 'package:appflowy/workflows/application/workflow_format.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:flutter_test/flutter_test.dart';

WorkflowStep _formatter(String operation, Map<String, Object?> options) {
  var step = WorkflowStep.create('step1', WorkflowStepKind.formatter)
      .withValue('operation', operation);
  for (final entry in options.entries) {
    step = step.withValue(entry.key, entry.value);
  }
  return step;
}

void main() {
  final context = <String, Object?>{
    'trigger': {
      'name': 'Ada',
      'amount': '1,250.50',
      'tags': ['Invoice', 'paid'],
      'body': {'price': 42, 'empty': '  '},
      'when': '2026-03-02T09:30:00',
    },
    'step1': {'output': 7},
  };

  group('templates', () {
    test('fill text, writing structures as JSON', () {
      expect(
        renderWorkflowText('Hi {{trigger.name}} {{ trigger.tags }}', context),
        'Hi Ada ["Invoice","paid"]',
      );
      expect(renderWorkflowText('{{trigger.missing}}!', context), '!');
    });

    test('a value that is only a template keeps its type', () {
      expect(renderWorkflowValue('{{trigger.body.price}}', context), 42);
      expect(renderWorkflowValue(' {{step1.output}} ', context), 7);
      expect(renderWorkflowValue('n={{step1.output}}', context), 'n=7');
    });

    test('field paths reach into maps and the first list entry', () {
      expect(
        workflowFieldPaths({
          'a': 1,
          'b': {'c': 2},
          'items': [
            {'title': 'x'},
          ],
        }),
        ['a', 'b.c', 'items', 'items.0.title'],
      );
    });

    test('previews are shortened', () {
      final preview = previewWorkflowValue({
        'long': 'x' * 1000,
        'list': List.generate(30, (index) => index),
      }) as Map;
      expect((preview['long'] as String).length, 401);
      expect((preview['list'] as List).length, 21);
    });
  });

  group('conditions', () {
    bool holds(String left, WorkflowOperator operator, [String right = '']) =>
        evaluateWorkflowCondition(
          WorkflowCondition(left: left, operator: operator, right: right),
          context,
        );

    test('compare numbers as numbers and words without case', () {
      expect(
        holds('{{trigger.body.price}}', WorkflowOperator.equals, '42.0'),
        isTrue,
      );
      expect(
        holds('{{trigger.amount}}', WorkflowOperator.greaterThan, '1000'),
        isTrue,
      );
      expect(
        holds('{{trigger.amount}}', WorkflowOperator.lessThan, '1000'),
        isFalse,
      );
      expect(holds('{{trigger.name}}', WorkflowOperator.equals, 'ada'), isTrue);
      expect(
        holds('{{trigger.name}}', WorkflowOperator.startsWith, 'A'),
        isTrue,
      );
      expect(
        holds('{{trigger.name}}', WorkflowOperator.endsWith, 'DA'),
        isTrue,
      );
    });

    test('contains looks inside lists and text', () {
      expect(
        holds('{{trigger.tags}}', WorkflowOperator.contains, 'invoice'),
        isTrue,
      );
      expect(
        holds('{{trigger.tags}}', WorkflowOperator.notContains, 'due'),
        isTrue,
      );
      expect(holds('Hello world', WorkflowOperator.contains, 'WORLD'), isTrue);
    });

    test('empty means missing, blank or empty', () {
      expect(holds('{{trigger.body.empty}}', WorkflowOperator.isEmpty), isTrue);
      expect(holds('{{trigger.missing}}', WorkflowOperator.isEmpty), isTrue);
      expect(holds('{{trigger.name}}', WorkflowOperator.isNotEmpty), isTrue);
    });

    test('dates compare as dates', () {
      expect(
        holds('{{trigger.when}}', WorkflowOperator.greaterThan, '2026-03-01'),
        isTrue,
      );
    });
  });

  group('formatter', () {
    Object? run(String operation, [Map<String, Object?> options = const {}]) =>
        runWorkflowFormatter(_formatter(operation, options), context);

    test('text operations', () {
      expect(
        run('titleCase', {'input': 'hello wORLD'}),
        'Hello World',
      );
      expect(
        run('replace', {'input': 'a-b-c', 'find': '-', 'replaceWith': '+'}),
        'a+b+c',
      );
      expect(run('truncate', {'input': 'abcdef', 'length': '3'}), 'abc…');
      expect(run('split', {'input': 'a, b ,c'}), ['a', 'b', 'c']);
      expect(
        run('split', {'input': 'a|b|c', 'separator': '|', 'index': 'last'}),
        'c',
      );
      expect(
        run('extractEmail', {'input': 'Mail ada@example.com now'}),
        'ada@example.com',
      );
      expect(
        run('extractUrl', {'input': 'See https://a.io/x?y=1.'}),
        'https://a.io/x?y=1.',
      );
      expect(
        run('stripHtml', {'input': '<p>Hi &amp; <b>bye</b></p>'}),
        'Hi & bye',
      );
      expect(run('wordCount', {'input': ' one two  three '}), 3);
      expect(
        run(
          'defaultValue',
          {'input': '{{trigger.missing}}', 'fallback': 'none'},
        ),
        'none',
      );
      expect(run('urlEncode', {'input': 'a b&c'}), 'a+b%26c');
    });

    test('number operations', () {
      expect(run('extractNumber', {'input': 'Total: 1,234.5 USD'}), 1234.5);
      expect(
        run('math', {'input': '10', 'operator': '/', 'operand': '4'}),
        2.5,
      );
      expect(run('round', {'input': '2.346', 'decimals': '2'}), 2.35);
      expect(run('round', {'input': '2.5'}), 3);
      expect(
        () => run('math', {'input': '1', 'operator': '/', 'operand': '0'}),
        throwsA(isA<WorkflowFormatException>()),
      );
    });

    test('date operations', () {
      expect(
        run(
          'formatDate',
          {'input': '{{trigger.when}}', 'pattern': 'yyyy/MM/dd HH:mm'},
        ),
        '2026/03/02 09:30',
      );
      expect(
        run(
          'addTime',
          {'input': '{{trigger.when}}', 'amount': '1', 'unit': 'months'},
        ),
        DateTime(2026, 4, 2, 9, 30).toIso8601String(),
      );
      expect(
        () => run('formatDate', {'input': 'not a date'}),
        throwsA(isA<WorkflowFormatException>()),
      );
    });

    test('JSON is read into a structure', () {
      expect(run('parseJson', {'input': '{"a": [1, 2]}'}), {
        'a': [1, 2],
      });
      expect(
        () => run('parseJson', {'input': '{oops'}),
        throwsA(isA<WorkflowFormatException>()),
      );
    });
  });
}
