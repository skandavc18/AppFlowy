import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_schedule.dart';
import 'package:flutter_test/flutter_test.dart';

import 'workflow_test_support.dart';

void main() {
  group('Workflow', () {
    test('survives JSON with every kind of trigger and step', () {
      for (final kind in WorkflowTriggerKind.values) {
        final workflow = Workflow.create(
          name: 'All ${kind.name}',
          workspaceId: 'ws1',
          trigger: WorkflowTrigger.create(kind),
          steps: [
            for (var i = 0; i < WorkflowStepKind.values.length; i++)
              WorkflowStep.create('step${i + 1}', WorkflowStepKind.values[i])
                  .withLabel('Step $i'),
          ],
        )
            .copyWith(
          enabled: true,
          enabledAt: DateTime.utc(2026, 3, 2, 9).toLocal(),
          stepCounter: WorkflowStepKind.values.length,
        )
            .withSample('trigger', {
          'title': 'x',
          'items': [1, 2],
        });
        final restored = Workflow.fromJson(workflow.toJson());
        expect(restored, workflow, reason: kind.name);
      }
    });

    test('step ids are never reused, even after a step is removed', () {
      var workflow = Workflow.create(name: 'Ids');
      final first = WorkflowStep.create(
        workflow.nextStepId(),
        WorkflowStepKind.notify,
      );
      workflow = workflow.insertStep(0, first);
      final second = WorkflowStep.create(
        workflow.nextStepId(),
        WorkflowStepKind.delay,
      );
      workflow = workflow.insertStep(1, second);
      expect([first.id, second.id], ['step1', 'step2']);
      workflow = workflow.removeStep('step2');
      expect(workflow.nextStepId(), 'step3');
      final restored = Workflow.fromJson(workflow.toJson())!;
      expect(restored.nextStepId(), 'step3');
    });

    test('removing a step drops its sample; moving keeps the rest', () {
      var workflow = readyWorkflow(
        trigger: const WorkflowTrigger(),
        steps: [
          step(1, WorkflowStepKind.notify, {'title': 'a'}),
          step(2, WorkflowStepKind.notify, {'title': 'b'}),
          step(3, WorkflowStepKind.notify, {'title': 'c'}),
        ],
      ).withSample('step2', {'title': 'b'});
      workflow = workflow.moveStep('step3', -2);
      expect(
        workflow.steps.map((step) => step.id),
        ['step3', 'step1', 'step2'],
      );
      expect(workflow.moveStep('step3', -1), same(workflow));
      workflow = workflow.removeStep('step2');
      expect(workflow.samples.containsKey('step2'), isFalse);
    });

    test('is complete only when the trigger and every step are set up', () {
      final notify = step(1, WorkflowStepKind.notify, {'title': 'Hi'});
      expect(
        readyWorkflow(trigger: const WorkflowTrigger(), steps: [notify])
            .isComplete,
        isTrue,
      );
      expect(
        readyWorkflow(trigger: const WorkflowTrigger(), steps: const [])
            .isComplete,
        isFalse,
      );
      expect(
        readyWorkflow(
          trigger: WorkflowTrigger.create(WorkflowTriggerKind.feed),
          steps: [notify],
        ).isComplete,
        isFalse,
      );
      expect(
        readyWorkflow(
          trigger: WorkflowTrigger.create(WorkflowTriggerKind.feed)
              .withValue('url', 'https://example.com/feed.xml'),
          steps: [notify],
        ).isComplete,
        isTrue,
      );
      expect(
        readyWorkflow(
          trigger: const WorkflowTrigger(),
          steps: [step(1, WorkflowStepKind.addRow)],
        ).isComplete,
        isFalse,
      );
      expect(
        readyWorkflow(
          trigger:
              WorkflowTrigger.create(WorkflowTriggerKind.schedule).withSchedule(
            const WorkflowSchedule(
              mode: WorkflowScheduleMode.weekly,
              weekdays: {},
            ),
          ),
          steps: [notify],
        ).isComplete,
        isFalse,
      );
      expect(
        step(1, WorkflowStepKind.httpRequest, {'url': '{{trigger.url}}'})
            .isConfigured,
        isFalse,
      );
      expect(
        step(
          1,
          WorkflowStepKind.httpRequest,
          {'url': 'https://api.example.com/{{trigger.id}}'},
        ).isConfigured,
        isTrue,
      );
    });

    test('a webhook gets a long random token of its own', () {
      final a = WorkflowTrigger.create(WorkflowTriggerKind.webhook).token;
      final b = WorkflowTrigger.create(WorkflowTriggerKind.webhook).token;
      expect(a.length, 32);
      expect(a, isNot(b));
    });

    test('what a polling trigger watches is its signature', () {
      final feed = WorkflowTrigger.create(WorkflowTriggerKind.feed)
          .withValue('url', 'https://a.example/feed');
      expect(
        feed.withValue('poll', 60).signature,
        feed.signature,
        reason: 'how often it looks does not change what it has seen',
      );
      expect(
        feed.withValue('url', 'https://b.example/feed').signature,
        isNot(feed.signature),
      );
      final rows = WorkflowTrigger.create(WorkflowTriggerKind.databaseRow)
          .withValue('viewId', 'v1');
      expect(
        rows.withValue('updates', true).signature,
        isNot(rows.signature),
      );
    });

    test('reads leniently and skips what it cannot understand', () {
      final workflow = Workflow.fromJson({
        'id': 'w1',
        'name': 'Lenient',
        'trigger': {'kind': 'somethingNew'},
        'steps': [
          {
            'id': 'step1',
            'kind': 'notify',
            'config': {'title': 'ok'},
          },
          {'id': 'step2', 'kind': 'teleport'},
          {'kind': 'notify'},
          'garbage',
        ],
      })!;
      expect(workflow.trigger.kind, WorkflowTriggerKind.manual);
      expect(workflow.steps.map((step) => step.id), ['step1']);
      expect(Workflow.fromJson({'name': 'no id'}), isNull);
    });

    test('a delay never parks a run longer than thirty days', () {
      expect(
        step(1, WorkflowStepKind.delay, {'amount': 90, 'unit': 'days'}).delay,
        WorkflowStep.maximumDelay,
      );
      expect(
        step(1, WorkflowStepKind.delay, {'amount': 5, 'unit': 'minutes'}).delay,
        const Duration(minutes: 5),
      );
    });
  });
}
