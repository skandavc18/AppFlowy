import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:appflowy/workflows/application/workflow_schedule.dart';
import 'package:appflowy/workflows/application/workflow_scheduler.dart';
import 'package:appflowy/workflows/application/workflow_services.dart';
import 'package:appflowy/workflows/application/workflow_store.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workflow_test_support.dart';

WorkflowFeedItem _item(String title, int minute) => WorkflowFeedItem(
      title: title,
      link: 'https://example.com/${title.toLowerCase()}',
      publishedAt: DateTime(2026, 3, 1, 12, minute),
    );

int _stamp(DateTime at) => at.millisecondsSinceEpoch ~/ 1000;

void main() {
  late WorkflowStore store;
  late WorkflowRunLog log;
  late FakeWorkflowServices services;
  late WorkflowScheduler scheduler;
  var now = DateTime(2026, 3, 2, 9);

  setUp(() async {
    now = DateTime(2026, 3, 2, 9);
    store = WorkflowStore(files: MemoryWorkflowFiles());
    log = WorkflowRunLog(files: MemoryWorkflowFiles());
    await store.ensureLoaded();
    await log.ensureLoaded();
    services = FakeWorkflowServices();
    scheduler = WorkflowScheduler(
      store: store,
      log: log,
      services: services,
      clock: () => now,
    );
  });

  tearDown(() {
    scheduler.dispose();
    store.dispose();
    log.dispose();
  });

  Future<void> tick() async {
    await scheduler.tick();
    await scheduler.settle();
  }

  test('a feed is first only read, then each new item runs once, oldest first',
      () async {
    final workflow = readyWorkflow(
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.feed)
          .withValue('url', 'https://example.com/feed'),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': '{{trigger.title}}'}),
      ],
    );
    await store.save(workflow);
    services.feed = WorkflowFeed(items: [_item('B', 2), _item('A', 1)]);

    await tick();
    expect(services.notifications, isEmpty, reason: 'no back catalogue');
    expect(store.triggerState(workflow.id).baselined, isTrue);

    services.feed = WorkflowFeed(
      title: 'News',
      items: [_item('D', 4), _item('C', 3), _item('B', 2), _item('A', 1)],
    );
    await tick();
    expect(services.notifications, isEmpty, reason: 'not time to look yet');

    now = now.add(const Duration(minutes: 15));
    await tick();
    expect(services.notifications.map((n) => n.$1), ['C', 'D']);
    expect(log.runs.every((run) => run.cause == WorkflowRunCause.feed), isTrue);

    now = now.add(const Duration(minutes: 15));
    await tick();
    expect(services.notifications, hasLength(2), reason: 'each item once');

    // Pointed somewhere else, it starts afresh instead of firing for all of it.
    await store.save(
      workflow.copyWith(
        trigger:
            workflow.trigger.withValue('url', 'https://other.example/feed'),
      ),
    );
    services.feed = WorkflowFeed(items: [_item('X', 9), _item('Y', 8)]);
    now = now.add(const Duration(minutes: 1));
    await tick();
    expect(services.notifications, hasLength(2));
  });

  test('table rows: new rows wait until typed, changes only when asked',
      () async {
    final workflow = readyWorkflow(
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.databaseRow)
          .withValue('viewId', 'v1')
          .withValue('updates', true),
      steps: [
        step(1, WorkflowStepKind.notify, {
          'title': '{{trigger.fields.Name}} {{trigger.isNew}}',
        }),
      ],
    );
    await store.save(workflow);
    WorkflowRowData row(String id, String name, DateTime modified) =>
        WorkflowRowData(
          id: id,
          cells: {'Name': name},
          modifiedAt: _stamp(modified),
        );
    final old = now.subtract(const Duration(hours: 1));
    services.table = WorkflowRows(
      columns: const ['Name'],
      rows: [row('r1', 'Ada', old)],
    );
    await tick();
    expect(services.notifications, isEmpty);

    now = now.add(const Duration(minutes: 2));
    services.table = WorkflowRows(
      columns: const ['Name'],
      rows: [row('r1', 'Ada', old), row('r2', 'Grace', now)],
    );
    await tick();
    expect(services.notifications, isEmpty, reason: 'still being typed');

    now = now.add(const Duration(minutes: 2));
    await tick();
    expect(services.notifications.map((n) => n.$1), ['Grace true']);

    now = now.add(const Duration(minutes: 2));
    services.table = WorkflowRows(
      columns: const ['Name'],
      rows: [
        row('r1', 'Ada L.', now.subtract(const Duration(minutes: 1))),
        row('r2', 'Grace', now.subtract(const Duration(minutes: 4))),
      ],
    );
    await tick();
    expect(
      services.notifications.map((n) => n.$1),
      ['Grace true', 'Ada L. false'],
    );
  });

  test('new pages inside a page run once each', () async {
    final workflow = readyWorkflow(
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.newPage)
          .withValue('parentId', 'parent'),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': '{{trigger.name}}'}),
      ],
    );
    await store.save(workflow);
    final earlier = now.subtract(const Duration(days: 1));
    services.pages = [
      WorkflowPageInfo(id: 'p1', name: 'Old', createdAt: earlier),
    ];
    await tick();
    now = now.add(const Duration(minutes: 3));
    services.pages = [
      WorkflowPageInfo(id: 'p1', name: 'Old', createdAt: earlier),
      WorkflowPageInfo(
        id: 'p2',
        name: 'Fresh',
        createdAt: now.subtract(const Duration(minutes: 1)),
      ),
    ];
    await tick();
    expect(services.notifications.map((n) => n.$1), ['Fresh']);
    now = now.add(const Duration(minutes: 3));
    await tick();
    expect(services.notifications, hasLength(1));
  });

  test('a missed schedule runs once, then keeps its rhythm', () async {
    final workflow = readyWorkflow(
      trigger:
          WorkflowTrigger.create(WorkflowTriggerKind.schedule).withSchedule(
        const WorkflowSchedule(mode: WorkflowScheduleMode.interval),
      ),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': '{{trigger.time}}'}),
      ],
      enabledAt: DateTime(2026, 3, 2, 7),
    );
    await store.save(workflow);

    await tick();
    expect(services.notifications, hasLength(1));
    expect(store.triggerState(workflow.id).lastScheduled, now);
    expect(scheduler.nextRunOf(workflow), DateTime(2026, 3, 2, 10));

    await tick();
    expect(services.notifications, hasLength(1), reason: 'not due again yet');

    now = DateTime(2026, 3, 2, 10, 0, 15);
    await tick();
    expect(services.notifications.map((n) => n.$1), ['08:00', '10:00']);
    expect(
      store.triggerState(workflow.id).lastScheduled,
      DateTime(2026, 3, 2, 10),
      reason: 'a tick late keeps the hour, so the schedule does not drift',
    );
  });

  test('webhooks are answered by what state the workflow is in', () async {
    final hook = readyWorkflow(
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.webhook),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': '{{trigger.body.name}}'}),
      ],
    );
    final token = hook.trigger.token;
    await store.save(hook);

    expect((await scheduler.handleWebhook(hook.id, 'wrong', {})).status, 404);
    expect((await scheduler.handleWebhook('missing', token, {})).status, 404);

    await store.save(hook.copyWith(enabled: false));
    expect((await scheduler.handleWebhook(hook.id, token, {})).status, 409);

    await store.save(hook);
    await store.updateSettings(const WorkflowSettings(pausedAll: true));
    expect((await scheduler.handleWebhook(hook.id, token, {})).status, 503);

    await store.updateSettings(const WorkflowSettings());
    final answer = await scheduler.handleWebhook(hook.id, token, {
      'body': {'name': 'Ada'},
    });
    expect(answer.status, 202);
    await scheduler.settle();
    expect(services.notifications.single.$1, 'Ada');
    expect(log.runs.single.cause, WorkflowRunCause.webhook);
  });

  test('a test listener takes the next request as a sample, even while off',
      () async {
    final hook = readyWorkflow(
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.webhook),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': 'x'}),
      ],
      enabled: false,
    );
    await store.save(hook);
    final listening = scheduler.waitForWebhookSample(hook.id);
    expect(scheduler.isListeningForSample(hook.id), isTrue);
    final answer = await scheduler.handleWebhook(hook.id, hook.trigger.token, {
      'body': {'x': 1},
    });
    expect(answer.status, 200);
    expect(await listening, {
      'body': {'x': 1},
    });
    await scheduler.settle();
    expect(log.runs, isEmpty);

    final cancelled = scheduler.waitForWebhookSample(hook.id);
    scheduler.cancelWebhookSample(hook.id);
    await expectLater(cancelled, throwsStateError);
  });

  test('nothing starts on its own in another workspace', () async {
    final elsewhere = readyWorkflow(
      name: 'Elsewhere',
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.webhook),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': 'x'}),
      ],
      workspaceId: 'ws2',
    );
    final starts = readyWorkflow(
      name: 'Starts elsewhere',
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.appStart),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': 'y'}),
      ],
      workspaceId: 'ws2',
    );
    await store.save(elsewhere);
    await store.save(starts);
    await tick();
    final answer = await scheduler.handleWebhook(
      elsewhere.id,
      elsewhere.trigger.token,
      {},
    );
    expect(answer.status, 409);
    expect(services.notifications, isEmpty);
  });

  test('app start fires once per launch', () async {
    await store.save(
      readyWorkflow(
        trigger: WorkflowTrigger.create(WorkflowTriggerKind.appStart),
        steps: [
          step(1, WorkflowStepKind.notify, {'title': 'Hello'}),
        ],
      ),
    );
    await tick();
    await tick();
    expect(services.notifications.map((n) => n.$1), ['Hello']);
  });

  test('nothing runs on its own while paused, but Run now still works',
      () async {
    final workflow = readyWorkflow(
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.appStart),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': 'Manual'}),
      ],
      enabled: false,
    );
    await store.save(workflow);
    await store.updateSettings(const WorkflowSettings(pausedAll: true));
    await tick();
    expect(services.notifications, isEmpty);
    final run = await scheduler.runNow(workflow);
    expect(run!.status, WorkflowRunStatus.succeeded);
    expect(run.cause, WorkflowRunCause.manual);
    expect(services.notifications.single.$1, 'Manual');
  });

  test('a parked run resumes when its time comes', () async {
    final workflow = readyWorkflow(
      trigger: const WorkflowTrigger(),
      steps: [
        step(1, WorkflowStepKind.delay, {'amount': 5, 'unit': 'minutes'}),
        step(2, WorkflowStepKind.notify, {'title': 'Resumed'}),
      ],
    );
    await store.save(workflow);
    final parked = await scheduler.runNow(workflow);
    expect(parked!.status, WorkflowRunStatus.waiting);
    await tick();
    expect(services.notifications, isEmpty);
    now = now.add(const Duration(minutes: 6));
    await tick();
    expect(services.notifications.single.$1, 'Resumed');
    expect(log.byId(parked.id)!.status, WorkflowRunStatus.succeeded);
  });
}
