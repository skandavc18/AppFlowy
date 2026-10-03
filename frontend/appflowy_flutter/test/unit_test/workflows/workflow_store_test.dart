import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_run.dart';
import 'package:appflowy/workflows/application/workflow_run_log.dart';
import 'package:appflowy/workflows/application/workflow_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

import 'workflow_test_support.dart';

void main() {
  late Directory root;

  setUp(() {
    root = Directory.systemTemp.createTempSync('appflowy_workflows_');
  });

  tearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });

  test('workflows and settings are written to disk and read back', () async {
    final store = WorkflowStore(rootOverride: root.path);
    addTearDown(store.dispose);
    await store.ensureLoaded();
    final workflow = readyWorkflow(
      trigger: WorkflowTrigger.create(WorkflowTriggerKind.webhook),
      steps: [
        step(1, WorkflowStepKind.notify, {'title': 'Hi'}),
      ],
    );
    await store.save(workflow);
    await store.updateSettings(
      const WorkflowSettings(keepRunningInBackground: true),
    );
    store.writeStorage('count', 3);
    await store.flush();

    expect(
      File(p.join(root.path, WorkflowStore.workflowsFile)).existsSync(),
      isTrue,
    );
    expect(
      root.listSync().whereType<File>().where((f) => f.path.endsWith('.tmp')),
      isEmpty,
      reason: 'temporary files are renamed into place',
    );

    final again = WorkflowStore(rootOverride: root.path);
    addTearDown(again.dispose);
    await again.ensureLoaded();
    expect(again.workflows.single, workflow);
    expect(again.settings.keepRunningInBackground, isTrue);
    expect(again.readStorage('count'), 3);
  });

  test('an unreadable file is kept aside, never overwritten', () async {
    final file = File(p.join(root.path, WorkflowStore.workflowsFile));
    file.writeAsStringSync('{ this is not json');
    final store = WorkflowStore(rootOverride: root.path);
    addTearDown(store.dispose);
    await store.ensureLoaded();
    expect(store.isLoaded, isTrue);
    expect(store.workflows, isEmpty);
    final kept = root
        .listSync()
        .whereType<File>()
        .where((f) => p.basename(f.path).startsWith('workflows.json.corrupt-'))
        .toList();
    expect(kept, hasLength(1));
    expect(kept.single.readAsStringSync(), '{ this is not json');
  });

  test('the history marks runs the app never finished', () async {
    final files = MemoryWorkflowFiles();
    final started = DateTime(2026, 3, 2, 9);
    WorkflowRun run(String id, WorkflowRunStatus status) => WorkflowRun(
          id: id,
          workflowId: 'w1',
          workflowName: 'W',
          cause: WorkflowRunCause.schedule,
          status: status,
          startedAt: started,
        );
    await files.write(WorkflowRunLog.runsFile, [
      run('a', WorkflowRunStatus.running).toJson(),
      run('b', WorkflowRunStatus.waiting).toJson(),
      run('c', WorkflowRunStatus.waiting).toJson(),
      run('d', WorkflowRunStatus.succeeded).toJson(),
    ]);
    await files.write(WorkflowRunLog.pendingFile, [
      WorkflowContinuation(
        runId: 'c',
        workflowId: 'w1',
        nextStep: 'step2',
        context: const {'trigger': {}},
        resumeAt: started.add(const Duration(hours: 1)),
        cause: WorkflowRunCause.schedule,
      ).toJson(),
    ]);
    final log = WorkflowRunLog(files: files);
    addTearDown(log.dispose);
    await log.ensureLoaded();
    expect(log.byId('a')!.status, WorkflowRunStatus.cancelled);
    expect(log.byId('b')!.status, WorkflowRunStatus.cancelled);
    expect(log.byId('c')!.status, WorkflowRunStatus.waiting);
    expect(log.byId('d')!.status, WorkflowRunStatus.succeeded);
    expect(log.pending.single.runId, 'c');

    await log.cancelParked('w1', message: 'off');
    expect(log.byId('c')!.status, WorkflowRunStatus.cancelled);
    expect(log.pending, isEmpty);
    await log.flush();
    final saved = jsonDecode(files.data[WorkflowRunLog.runsFile]!) as List;
    expect(saved, hasLength(4));
  });

  test('the history keeps the newest runs only', () async {
    final log = WorkflowRunLog(files: MemoryWorkflowFiles());
    addTearDown(log.dispose);
    await log.ensureLoaded();
    for (var i = 0; i < WorkflowRunLog.runLimit + 5; i++) {
      log.record(
        WorkflowRun(
          id: 'run$i',
          workflowId: 'w1',
          workflowName: 'W',
          cause: WorkflowRunCause.manual,
          status: WorkflowRunStatus.succeeded,
          startedAt: DateTime(2026, 3, 2).add(Duration(minutes: i)),
        ),
      );
    }
    expect(log.runs, hasLength(WorkflowRunLog.runLimit));
    expect(log.runs.first.id, 'run${WorkflowRunLog.runLimit + 4}');
  });

  test('stored values are for notes, not documents', () async {
    final store = WorkflowStore(files: MemoryWorkflowFiles());
    addTearDown(store.dispose);
    await store.ensureLoaded();
    for (var i = 0; i < WorkflowStore.storageLimit; i++) {
      store.writeStorage('key$i', i);
    }
    expect(() => store.writeStorage('one more', 1), throwsStateError);
    store.writeStorage('key0', 'replaced');
    expect(store.readStorage('key0'), 'replaced');
    store.writeStorage('key0', null);
    expect(store.readStorage('key0'), isNull);
  });
}
