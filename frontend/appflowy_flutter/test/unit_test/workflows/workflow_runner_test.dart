import 'dart:convert';

import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:appflowy/workflows/application/workflow_runner.dart';
import 'package:appflowy/workflows/application/workflow_services.dart';
import 'package:appflowy/workflows/application/workflow_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workflow_test_support.dart';

void main() {
  late WorkflowStore store;
  late WorkflowRunLog log;
  late FakeWorkflowServices services;
  late WorkflowRunner runner;
  var now = DateTime(2026, 3, 2, 9);

  setUp(() async {
    now = DateTime(2026, 3, 2, 9);
    store = WorkflowStore(files: MemoryWorkflowFiles());
    log = WorkflowRunLog(files: MemoryWorkflowFiles());
    await store.ensureLoaded();
    await log.ensureLoaded();
    services = FakeWorkflowServices();
    runner = WorkflowRunner(
      services: services,
      store: store,
      log: log,
      clock: () => now,
    );
  });

  tearDown(() {
    store.dispose();
    log.dispose();
  });

  test('runs each step in order, handing data along', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.formatter, {
          'operation': 'uppercase',
          'input': '{{trigger.name}}',
        }),
        step(2, WorkflowStepKind.createPage, {
          'title': '{{step1.output}} notes',
          'content': '# {{today}}',
        }),
        step(3, WorkflowStepKind.notify, {
          'title': 'Made {{step2.name}}',
          'body': 'id {{step2.id}}',
        }),
      ],
    );
    final run = await runner.start(
      workflow,
      cause: WorkflowRunCause.manual,
      trigger: {'name': 'Ada'},
    );

    expect(run.status, WorkflowRunStatus.succeeded);
    expect(run.steps.map((result) => result.status), [
      WorkflowStepStatus.succeeded,
      WorkflowStepStatus.succeeded,
      WorkflowStepStatus.succeeded,
    ]);
    expect(services.createdPages.single['name'], 'ADA notes');
    expect(services.createdPages.single['markdown'], '# 2026-03-02');
    expect(services.notifications.single, ('Made ADA notes', 'id page1'));
    expect(log.runsFor(workflow.id).single.id, run.id);
    expect(log.byId(run.id)!.trigger, {'name': 'Ada'});
  });

  test('a filter that does not hold stops the run, not as a failure', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.filter, {
          'conditions': const [
            WorkflowCondition(
              left: '{{trigger.amount}}',
              operator: WorkflowOperator.greaterThan,
              right: '100',
            ),
          ],
        }),
        step(2, WorkflowStepKind.notify, {'title': 'Big order'}),
      ],
    );
    final small = await runner.start(
      workflow,
      cause: WorkflowRunCause.webhook,
      trigger: {'amount': 50},
    );
    expect(small.status, WorkflowRunStatus.filtered);
    expect(small.steps.single.status, WorkflowStepStatus.filtered);
    expect(services.notifications, isEmpty);

    final large = await runner.start(
      workflow,
      cause: WorkflowRunCause.webhook,
      trigger: {'amount': 500},
    );
    expect(large.status, WorkflowRunStatus.succeeded);
    expect(services.notifications.single.$1, 'Big order');
  });

  test('a failing step fails the run with its reason and stops there',
      () async {
    services.respond = (_) => const WorkflowHttpResponse(
          status: 500,
          body: {'error': 'boom'},
        );
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.httpRequest, {
          'url': 'https://api.example.com/items',
        }),
        step(2, WorkflowStepKind.notify, {'title': 'never'}),
      ],
    );
    final run = await runner.start(workflow, cause: WorkflowRunCause.manual);
    expect(run.status, WorkflowRunStatus.failed);
    expect(run.message, contains('500'));
    expect(run.message, contains('boom'));
    expect(run.steps.single.status, WorkflowStepStatus.failed);
    expect(services.notifications, isEmpty);

    // Asked not to, an error answer is just data for the next step.
    final tolerant = workflow.replaceStep(
      workflow.steps.first.withValue('failOnError', false),
    );
    final second = await runner.start(tolerant, cause: WorkflowRunCause.manual);
    expect(second.status, WorkflowRunStatus.succeeded);
  });

  test('a request sends typed JSON, query parameters and headers', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.httpRequest, {
          'method': 'POST',
          'url': 'https://api.example.com/hook?a=1',
          'query': const [WorkflowPair('b', '{{trigger.name}}')],
          'headers': const [WorkflowPair('X-Token', 'abc')],
          'fields': const [
            WorkflowPair('count', '{{trigger.count}}'),
            WorkflowPair('text', 'Hi {{trigger.name}}'),
          ],
        }),
      ],
    );
    final run = await runner.start(
      workflow,
      cause: WorkflowRunCause.manual,
      trigger: {'name': 'Ada', 'count': 3},
    );
    expect(run.status, WorkflowRunStatus.succeeded);
    final request = services.requests.single;
    expect(request.method, 'POST');
    expect(request.uri.queryParameters, {'a': '1', 'b': 'Ada'});
    expect(request.headers['x-token'], 'abc');
    expect(request.headers['content-type'], 'application/json');
    expect(jsonDecode(request.body!), {'count': 3, 'text': 'Hi Ada'});
  });

  test('a header that would split the request is refused', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.httpRequest, {
          'url': 'https://api.example.com',
          'headers': const [WorkflowPair('X-Bad', '{{trigger.value}}')],
        }),
      ],
    );
    final run = await runner.start(
      workflow,
      cause: WorkflowRunCause.manual,
      trigger: {'value': 'a\r\nInjected: yes'},
    );
    expect(run.status, WorkflowRunStatus.failed);
    expect(services.requests, isEmpty);
  });

  test('a delay parks the run, and resuming finishes it', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.delay, {'amount': 10, 'unit': 'minutes'}),
        step(2, WorkflowStepKind.notify, {'title': 'Later, {{trigger.name}}'}),
      ],
    );
    final parked = await runner.start(
      workflow,
      cause: WorkflowRunCause.schedule,
      trigger: {'name': 'Ada'},
    );
    expect(parked.status, WorkflowRunStatus.waiting);
    expect(parked.resumeAt, DateTime(2026, 3, 2, 9, 10));
    expect(services.notifications, isEmpty);
    final continuation = log.pending.single;
    expect(continuation.nextStep, 'step2');
    expect(log.dueContinuations(now), isEmpty);

    now = DateTime(2026, 3, 2, 9, 11);
    expect(log.dueContinuations(now), [continuation]);
    final finished = await runner.resume(workflow, continuation);
    expect(finished.id, parked.id);
    expect(finished.status, WorkflowRunStatus.succeeded);
    expect(finished.steps.map((result) => result.status), [
      WorkflowStepStatus.waiting,
      WorkflowStepStatus.succeeded,
    ]);
    expect(services.notifications.single.$1, 'Later, Ada');
    expect(log.pending, isEmpty);
    expect(log.runsFor(workflow.id), hasLength(1));
  });

  test('a run waiting for a removed step is cancelled', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.delay),
        step(2, WorkflowStepKind.notify, {'title': 'x'}),
      ],
    );
    await runner.start(workflow, cause: WorkflowRunCause.manual);
    final continuation = log.pending.single;
    final edited = workflow.removeStep('step2');
    final run = await runner.resume(edited, continuation);
    expect(run.status, WorkflowRunStatus.cancelled);
    expect(services.notifications, isEmpty);
  });

  test('stored values carry over between runs', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.storage, {
          'operation': 'increment',
          'key': 'count',
          'value': '',
        }),
        step(2, WorkflowStepKind.storage, {
          'operation': 'append',
          'key': 'names',
          'value': '{{trigger.name}}',
        }),
        step(3, WorkflowStepKind.notify, {
          'title': 'Run {{storage.count}}',
        }),
      ],
    );
    await runner.start(
      workflow,
      cause: WorkflowRunCause.manual,
      trigger: {'name': 'Ada'},
    );
    await runner.start(
      workflow,
      cause: WorkflowRunCause.manual,
      trigger: {'name': 'Grace'},
    );
    expect(store.readStorage('count'), 2);
    expect(store.readStorage('names'), ['Ada', 'Grace']);
    expect(services.notifications.map((n) => n.$1), ['Run 1', 'Run 2']);
  });

  test('a reminder reads ordinary words and ISO dates', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.reminder, {
          'title': 'Call {{trigger.name}}',
          'when': '{{trigger.when}}',
        }),
      ],
    );
    final run = await runner.start(
      workflow,
      cause: WorkflowRunCause.manual,
      trigger: {'name': 'Ada', 'when': '2026-03-05T14:00:00'},
    );
    expect(run.status, WorkflowRunStatus.succeeded);
    expect(services.reminders.single['title'], 'Call Ada');
    expect(
      services.reminders.single['scheduledAt'],
      DateTime(2026, 3, 5, 14).toIso8601String(),
    );

    final unreadable = workflow.replaceStep(
      workflow.steps.first.withValue('when', 'banana'),
    );
    final failed = await runner.start(
      unreadable,
      cause: WorkflowRunCause.manual,
      trigger: {'name': 'Ada'},
    );
    expect(failed.status, WorkflowRunStatus.failed);
    expect(failed.message, contains('banana'));
  });

  test('a code step hands the script the run so far', () async {
    services.script = (source, input) => {
          'greeting': 'Hello ${((input as Map)['trigger'] as Map)['name']}',
        };
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.code),
        step(2, WorkflowStepKind.notify, {'title': '{{step1.greeting}}'}),
      ],
    );
    await runner.start(
      workflow,
      cause: WorkflowRunCause.manual,
      trigger: {'name': 'Ada'},
    );
    expect(services.notifications.single.$1, 'Hello Ada');
  });

  test('testing a step uses samples and never parks a run', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.delay),
        step(2, WorkflowStepKind.createPage, {'title': 'For {{trigger.name}}'}),
      ],
    ).withSample(Workflow.triggerSampleKey, {'name': 'Ada'});

    final waited = await runner.testStep(workflow, workflow.steps.first);
    expect(waited.isError, isFalse);
    expect((waited.output as Map)['resumeAt'], isNotNull);
    expect(log.pending, isEmpty);

    final made = await runner.testStep(workflow, workflow.steps.last);
    expect(made.isError, isFalse);
    expect(services.createdPages.single['name'], 'For Ada');
    expect(log.runs, isEmpty, reason: 'tests are not runs');
  });
}
