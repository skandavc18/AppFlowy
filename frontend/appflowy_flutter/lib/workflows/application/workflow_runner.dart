import 'dart:async';
import 'dart:convert';

import 'package:appflowy/shared/calendar/reminder_parser.dart';
import 'package:intl/intl.dart';

import 'workflow_format.dart';
import 'workflow_model.dart';
import 'workflow_run.dart';
import 'workflow_run_log.dart';
import 'workflow_services.dart';
import 'workflow_store.dart';

sealed class _StepOutcome {
  const _StepOutcome();
}

class _Produced extends _StepOutcome {
  const _Produced(this.output);

  final Object? output;
}

class _Stopped extends _StepOutcome {
  const _Stopped(this.reason);

  final String reason;
}

class _Parked extends _StepOutcome {
  const _Parked(this.resumeAt);

  final DateTime resumeAt;
}

/// What testing a single step produced.
class WorkflowStepTest {
  const WorkflowStepTest.passed(this.output)
      : error = '',
        stopped = false;

  const WorkflowStepTest.stopped(this.error)
      : output = null,
        stopped = true;

  const WorkflowStepTest.failed(this.error)
      : output = null,
        stopped = false;

  final Object? output;
  final String error;

  /// A filter that did not let the sample through. Not a failure.
  final bool stopped;

  bool get isError => error.isNotEmpty && !stopped;
}

/// Carries a run through its steps, one after another.
class WorkflowRunner {
  WorkflowRunner({
    required this.services,
    required this.store,
    required this.log,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// No single step may hold a run longer than this.
  static const stepTimeout = Duration(minutes: 3);

  /// A list kept by a storage step stops growing here; the oldest entries go.
  static const storageListLimit = 100;

  final WorkflowServices services;
  final WorkflowStore store;
  final WorkflowRunLog log;
  final DateTime Function() _clock;

  WorkflowContext buildContext(
    Workflow workflow,
    Object? trigger, {
    required String runId,
    required DateTime startedAt,
  }) {
    final context = <String, Object?>{
      'trigger': trigger,
      'storage': store.storage,
      'workflow': {'id': workflow.id, 'name': workflow.name},
      'run': {'id': runId, 'startedAt': startedAt.toIso8601String()},
    };
    _refreshClock(context);
    return context;
  }

  void _refreshClock(WorkflowContext context) {
    final now = _clock();
    context['now'] = now.toIso8601String();
    context['today'] = DateFormat('yyyy-MM-dd').format(now);
    context['time'] = DateFormat('HH:mm').format(now);
  }

  /// Runs [workflow] from its first step.
  Future<WorkflowRun> start(
    Workflow workflow, {
    required WorkflowRunCause cause,
    Object? trigger,
  }) {
    final now = _clock();
    final runId = newWorkflowId();
    final payload = workflowJsonSafe(trigger);
    final context =
        buildContext(workflow, payload, runId: runId, startedAt: now);
    final run = WorkflowRun(
      id: runId,
      workflowId: workflow.id,
      workflowName: workflow.name,
      cause: cause,
      status: WorkflowRunStatus.running,
      startedAt: now,
      trigger: previewWorkflowValue(payload),
    );
    log.record(run);
    return _execute(workflow, run, context, 0);
  }

  /// Carries on a run a delay step parked.
  Future<WorkflowRun> resume(
    Workflow workflow,
    WorkflowContinuation continuation,
  ) async {
    await log.unpark(continuation.runId);
    final now = _clock();
    final known = log.byId(continuation.runId);
    var run = (known ??
            WorkflowRun(
              id: continuation.runId,
              workflowId: workflow.id,
              workflowName: workflow.name,
              cause: continuation.cause,
              status: WorkflowRunStatus.running,
              startedAt: now,
            ))
        .copyWith(status: WorkflowRunStatus.running, clearResumeAt: true);
    final index = workflow.indexOfStep(continuation.nextStep);
    if (index < 0) {
      run = run.copyWith(
        status: WorkflowRunStatus.cancelled,
        finishedAt: now,
        message: 'The step this run was waiting for was removed.',
      );
      log.record(run);
      return run;
    }
    final context = Map<String, Object?>.from(continuation.context)
      ..['storage'] = store.storage;
    log.record(run);
    return _execute(workflow, run, context, index);
  }

  Future<WorkflowRun> _execute(
    Workflow workflow,
    WorkflowRun initial,
    WorkflowContext context,
    int from,
  ) async {
    var run = initial;
    final results = [...run.steps];
    for (var index = from; index < workflow.steps.length; index++) {
      final step = workflow.steps[index];
      final watch = Stopwatch()..start();
      _refreshClock(context);
      try {
        final outcome = await _runStep(step, context, testing: false).timeout(
          stepTimeout,
          onTimeout: () => throw WorkflowStepException(
            'It did not finish within ${stepTimeout.inMinutes} minutes.',
          ),
        );
        final elapsed = watch.elapsedMilliseconds;
        switch (outcome) {
          case _Produced(:final output):
            final safe = workflowJsonSafe(output);
            context[step.id] = safe;
            results.add(
              WorkflowStepResult(
                stepId: step.id,
                kind: step.kind,
                label: step.label,
                status: WorkflowStepStatus.succeeded,
                output: previewWorkflowValue(safe),
                durationMs: elapsed,
              ),
            );
            run = run.copyWith(steps: [...results]);
            log.record(run);
          case _Stopped(:final reason):
            results.add(
              WorkflowStepResult(
                stepId: step.id,
                kind: step.kind,
                label: step.label,
                status: WorkflowStepStatus.filtered,
                message: reason,
                durationMs: elapsed,
              ),
            );
            run = run.copyWith(
              status: WorkflowRunStatus.filtered,
              finishedAt: _clock(),
              message: reason,
              steps: [...results],
            );
            log.record(run);
            return run;
          case _Parked(:final resumeAt):
            final resumeText = resumeAt.toIso8601String();
            context[step.id] = {'resumeAt': resumeText};
            results.add(
              WorkflowStepResult(
                stepId: step.id,
                kind: step.kind,
                label: step.label,
                status: WorkflowStepStatus.waiting,
                output: {'resumeAt': resumeText},
                durationMs: elapsed,
              ),
            );
            if (index + 1 >= workflow.steps.length) {
              // Waiting with nothing after it changes nothing.
              continue;
            }
            final saved = workflowJsonSafe(context);
            await log.park(
              WorkflowContinuation(
                runId: run.id,
                workflowId: workflow.id,
                nextStep: workflow.steps[index + 1].id,
                context: saved is Map
                    ? Map<String, Object?>.from(saved)
                    : <String, Object?>{},
                resumeAt: resumeAt,
                cause: run.cause,
              ),
            );
            run = run.copyWith(
              status: WorkflowRunStatus.waiting,
              resumeAt: resumeAt,
              steps: [...results],
            );
            log.record(run);
            return run;
        }
      } on Object catch (error) {
        final message = _describe(error);
        results.add(
          WorkflowStepResult(
            stepId: step.id,
            kind: step.kind,
            label: step.label,
            status: WorkflowStepStatus.failed,
            message: message,
            durationMs: watch.elapsedMilliseconds,
          ),
        );
        run = run.copyWith(
          status: WorkflowRunStatus.failed,
          finishedAt: _clock(),
          message: message,
          steps: [...results],
        );
        log.record(run);
        return run;
      }
    }
    run = run.copyWith(
      status: WorkflowRunStatus.succeeded,
      finishedAt: _clock(),
      steps: [...results],
      clearResumeAt: true,
    );
    log.record(run);
    return run;
  }

  static String _describe(Object error) {
    final text = switch (error) {
      WorkflowStepException(:final message) => message,
      WorkflowFormatException(:final message) => message,
      StateError(:final message) => message,
      FormatException(:final message) => message,
      _ => '$error',
    };
    return text.length > 600 ? '${text.substring(0, 600)}…' : text;
  }

  /// Runs one step against sample data, for the editor's Test button.
  ///
  /// ⚠️ A test does the work for real — the page is created, the request is
  /// sent. Only a delay is not waited out.
  Future<WorkflowStepTest> testStep(
    Workflow workflow,
    WorkflowStep step,
  ) async {
    final now = _clock();
    final context = buildContext(
      workflow,
      workflow.samples[Workflow.triggerSampleKey] ?? const <String, Object?>{},
      runId: 'test',
      startedAt: now,
    );
    for (final earlier in workflow.steps) {
      if (earlier.id == step.id) {
        break;
      }
      context[earlier.id] = workflow.samples[earlier.id];
    }
    try {
      final outcome =
          await _runStep(step, context, testing: true).timeout(stepTimeout);
      return switch (outcome) {
        _Produced(:final output) =>
          WorkflowStepTest.passed(workflowJsonSafe(output)),
        _Stopped(:final reason) => WorkflowStepTest.stopped(reason),
        _Parked(:final resumeAt) => WorkflowStepTest.passed(
            {'resumeAt': resumeAt.toIso8601String()},
          ),
      };
    } on TimeoutException {
      return const WorkflowStepTest.failed('The step took too long.');
    } on Object catch (error) {
      return WorkflowStepTest.failed(_describe(error));
    }
  }

  Future<_StepOutcome> _runStep(
    WorkflowStep step,
    WorkflowContext context, {
    required bool testing,
  }) async {
    String text(String key) => renderWorkflowText(step.text(key), context);

    switch (step.kind) {
      case WorkflowStepKind.httpRequest:
        return _Produced(await _request(step, context));

      case WorkflowStepKind.createPage:
        final title = text('title').trim();
        return _Produced(
          await services.createPage(
            parentId: text('parentId').trim(),
            title: title.isEmpty ? 'Untitled' : _oneLine(title),
            markdown: text('content'),
          ),
        );

      case WorkflowStepKind.appendToPage:
        final pageId = text('pageId').trim();
        if (pageId.isEmpty) {
          throw const WorkflowStepException('Choose a page to add to.');
        }
        final content = text('content');
        if (content.trim().isEmpty) {
          throw const WorkflowStepException('There was nothing to add.');
        }
        return _Produced(
          await services.appendToPage(pageId: pageId, markdown: content),
        );

      case WorkflowStepKind.addRow:
        final viewId = step.text('viewId').trim();
        if (viewId.isEmpty) {
          throw const WorkflowStepException('Choose a table to add to.');
        }
        return _Produced(
          await services.addRow(
            viewId: viewId,
            values: [
              for (final pair in step.pairs('values'))
                if (pair.key.trim().isNotEmpty)
                  WorkflowPair(
                    pair.key,
                    renderWorkflowText(pair.value, context),
                  ),
            ],
          ),
        );

      case WorkflowStepKind.notify:
        final title = _oneLine(text('title').trim());
        final body = text('body').trim();
        if (title.isEmpty && body.isEmpty) {
          throw const WorkflowStepException('The notification is empty.');
        }
        await services.notify(title: title, body: body);
        return _Produced({'title': title, 'body': body});

      case WorkflowStepKind.reminder:
        final title = _oneLine(text('title').trim());
        if (title.isEmpty) {
          throw const WorkflowStepException('The reminder needs a title.');
        }
        final when = text('when').trim();
        final at = _readWhen(when);
        if (at == null) {
          throw WorkflowStepException(
            'Could not read "$when" as a time. '
            'Try "tomorrow 9am" or "in 2 hours".',
          );
        }
        return _Produced(
          await services.createReminder(
            title: title,
            message: text('message').trim(),
            at: at.$1,
            includeTime: at.$2,
          ),
        );

      case WorkflowStepKind.filter:
        final conditions = step.conditions;
        if (conditions.isEmpty) {
          return const _Produced({'passed': true});
        }
        final all = step.flag('all', fallback: true);
        final failing = <WorkflowCondition>[];
        for (final condition in conditions) {
          if (evaluateWorkflowCondition(condition, context)) {
            if (!all) {
              return const _Produced({'passed': true});
            }
          } else {
            failing.add(condition);
          }
        }
        if (all && failing.isEmpty) {
          return const _Produced({'passed': true});
        }
        return _Stopped(
          _explainFilter(
            all ? failing.first : conditions.first,
            context,
            all: all,
          ),
        );

      case WorkflowStepKind.delay:
        final resumeAt = _clock().add(step.delay);
        if (testing) {
          return _Produced({'resumeAt': resumeAt.toIso8601String()});
        }
        return _Parked(resumeAt);

      case WorkflowStepKind.formatter:
        return _Produced({'output': runWorkflowFormatter(step, context)});

      case WorkflowStepKind.code:
        final value = await services.runScript(
          step.text('code'),
          workflowJsonSafe(context),
        );
        if (value is Map) {
          return _Produced(Map<String, Object?>.from(value));
        }
        return _Produced({'output': value});

      case WorkflowStepKind.storage:
        return _Produced(_storage(step, context));
    }
  }

  String _explainFilter(
    WorkflowCondition condition,
    WorkflowContext context, {
    required bool all,
  }) {
    final left = workflowText(renderWorkflowValue(condition.left, context));
    final shown = left.length > 80 ? '${left.substring(0, 80)}…' : left;
    final right = condition.operator.needsValue
        ? ' "${renderWorkflowText(condition.right, context)}"'
        : '';
    final prefix = all ? 'Stopped by the filter' : 'No filter condition held';
    return '$prefix: "$shown" ${condition.operator.name}$right.';
  }

  Map<String, Object?> _storage(WorkflowStep step, WorkflowContext context) {
    final key = renderWorkflowText(step.text('key'), context).trim();
    if (key.isEmpty) {
      throw const WorkflowStepException('The value needs a name.');
    }
    final operation = step.text('operation');
    final input = renderWorkflowValue(step.text('value'), context);
    Object? next;
    switch (operation) {
      case 'get':
        next = store.readStorage(key);
        return {'key': key, 'value': next};
      case 'remove':
        store.writeStorage(key, null);
        next = null;
      case 'increment':
        final current = workflowNumber(store.readStorage(key)) ?? 0;
        final by = workflowText(input).trim().isEmpty
            ? 1
            : workflowNumber(input) ??
                (throw WorkflowStepException(
                  '"${workflowText(input)}" is not a number.',
                ));
        next = current + by;
        store.writeStorage(key, next);
      case 'append':
        final current = store.readStorage(key);
        final list = [
          if (current is List) ...current else if (current != null) current,
          workflowJsonSafe(input),
        ];
        next = list.length > storageListLimit
            ? list.sublist(list.length - storageListLimit)
            : list;
        store.writeStorage(key, next);
      default:
        next = workflowJsonSafe(input);
        store.writeStorage(key, next);
    }
    context['storage'] = store.storage;
    return {'key': key, 'value': next};
  }

  /// A moment from ISO text, an epoch, or ordinary words.
  (DateTime, bool)? _readWhen(String when) {
    if (when.isEmpty) {
      return null;
    }
    final direct = DateTime.tryParse(when);
    if (direct != null) {
      final hasTime = when.contains('T') || when.contains(':');
      return (direct.toLocal(), hasTime);
    }
    final parsed = parseReminderText(when, now: _clock());
    final at = parsed.when;
    if (at == null) {
      return null;
    }
    return (at, parsed.hasTime);
  }

  Future<Map<String, Object?>> _request(
    WorkflowStep step,
    WorkflowContext context,
  ) async {
    final method = step.text('method').trim().toUpperCase();
    final verb =
        const ['GET', 'POST', 'PUT', 'PATCH', 'DELETE'].contains(method)
            ? method
            : 'GET';
    final address = renderWorkflowText(step.text('url'), context).trim();
    var uri = Uri.tryParse(address);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw WorkflowStepException('"$address" is not a web address.');
    }

    final query = <String, String>{
      for (final pair in step.pairs('query'))
        if (renderWorkflowText(pair.key, context).trim().isNotEmpty)
          renderWorkflowText(pair.key, context).trim():
              renderWorkflowText(pair.value, context),
    };
    if (query.isNotEmpty) {
      uri = uri.replace(queryParameters: {...uri.queryParameters, ...query});
    }

    final headers = <String, String>{};
    for (final pair in step.pairs('headers')) {
      final name = renderWorkflowText(pair.key, context).trim();
      if (name.isEmpty) {
        continue;
      }
      final value = renderWorkflowText(pair.value, context);
      if (name.contains(RegExp(r'[\r\n:]')) ||
          value.contains(RegExp(r'[\r\n]'))) {
        throw WorkflowStepException('The header "$name" is not valid.');
      }
      headers[name.toLowerCase()] = value;
    }

    String? body;
    if (verb != 'GET') {
      switch (step.text('bodyKind')) {
        case 'form':
          final fields = <String, String>{
            for (final pair in step.pairs('fields'))
              if (pair.key.trim().isNotEmpty)
                renderWorkflowText(pair.key, context).trim():
                    renderWorkflowText(pair.value, context),
          };
          if (fields.isNotEmpty) {
            body = Uri(queryParameters: fields).query;
            headers.putIfAbsent(
              'content-type',
              () => 'application/x-www-form-urlencoded',
            );
          }
        case 'raw':
          final raw = renderWorkflowText(step.text('body'), context);
          if (raw.isNotEmpty) {
            body = raw;
            final trimmed = raw.trimLeft();
            headers.putIfAbsent(
              'content-type',
              () => trimmed.startsWith('{') || trimmed.startsWith('[')
                  ? 'application/json'
                  : 'text/plain; charset=utf-8',
            );
          }
        case 'none':
          break;
        default:
          final fields = <String, Object?>{
            for (final pair in step.pairs('fields'))
              if (pair.key.trim().isNotEmpty)
                renderWorkflowText(pair.key, context).trim():
                    workflowJsonSafe(renderWorkflowValue(pair.value, context)),
          };
          if (fields.isNotEmpty) {
            body = jsonEncode(fields);
            headers.putIfAbsent('content-type', () => 'application/json');
          }
      }
    }

    final response = await services.send(
      WorkflowHttpRequest(method: verb, uri: uri, headers: headers, body: body),
    );
    if (!response.ok && step.flag('failOnError', fallback: true)) {
      final detail = workflowText(response.body).trim();
      final short =
          detail.length > 200 ? '${detail.substring(0, 200)}…' : detail;
      throw WorkflowStepException(
        '${uri.host} answered ${response.status}'
        '${short.isEmpty ? '' : ': $short'}',
      );
    }
    return response.toOutput();
  }

  static String _oneLine(String text) =>
      text.replaceAll(RegExp(r'\s*[\r\n]+\s*'), ' ').trim();
}
