import 'dart:convert';

import 'package:appflowy/workflows/application/workflow_files.dart';
import 'package:appflowy/workflows/application/workflow_model.dart';
import 'package:appflowy/workflows/application/workflow_services.dart';

/// Keeps workflow files in memory, as JSON text, so a test exercises the same
/// encoding the disk would see without touching it.
class MemoryWorkflowFiles extends WorkflowFiles {
  MemoryWorkflowFiles() : super(rootOverride: '');

  final Map<String, String> data = {};
  int writes = 0;

  @override
  Future<Object?> read(String name) async {
    final text = data[name];
    return text == null ? null : jsonDecode(text);
  }

  @override
  Future<void> write(String name, Object? value) async {
    writes++;
    data[name] = jsonEncode(value);
  }

  @override
  Future<void> settle() async {}
}

/// Records what a workflow asked for and answers from fixtures.
class FakeWorkflowServices implements WorkflowServices {
  String workspaceId = 'ws1';

  final List<Map<String, Object?>> createdPages = [];
  final List<Map<String, Object?>> appended = [];
  final List<Map<String, Object?>> addedRows = [];
  final List<(String, String)> notifications = [];
  final List<Map<String, Object?>> reminders = [];
  final List<WorkflowHttpRequest> requests = [];
  final List<Object?> scriptInputs = [];

  WorkflowHttpResponse Function(WorkflowHttpRequest request)? respond;
  WorkflowFeed feed = const WorkflowFeed();
  WorkflowRows table = const WorkflowRows();
  List<WorkflowPageInfo> pages = const [];
  Object? Function(String source, Object? input)? script;

  @override
  Future<String> currentWorkspaceId() async => workspaceId;

  @override
  Future<Map<String, Object?>> createPage({
    required String parentId,
    required String title,
    required String markdown,
  }) async {
    final page = {
      'id': 'page${createdPages.length + 1}',
      'name': title,
      'parentId': parentId,
      'markdown': markdown,
    };
    createdPages.add(page);
    return {'id': page['id'], 'name': title, 'parentId': parentId};
  }

  @override
  Future<Map<String, Object?>> appendToPage({
    required String pageId,
    required String markdown,
  }) async {
    appended.add({'pageId': pageId, 'markdown': markdown});
    return {'pageId': pageId, 'blocks': 1};
  }

  @override
  Future<Map<String, Object?>> addRow({
    required String viewId,
    required List<WorkflowPair> values,
  }) async {
    final row = {
      'rowId': 'row${addedRows.length + 1}',
      'viewId': viewId,
      'values': {for (final pair in values) pair.key: pair.value},
    };
    addedRows.add(row);
    return row;
  }

  @override
  Future<WorkflowRows> readRows(String viewId) async => table;

  @override
  Future<List<WorkflowPageInfo>> childPages(String parentId) async => pages;

  @override
  Future<void> notify({required String title, required String body}) async {
    notifications.add((title, body));
  }

  @override
  Future<Map<String, Object?>> createReminder({
    required String title,
    required String message,
    required DateTime at,
    required bool includeTime,
  }) async {
    final reminder = {
      'id': 'reminder${reminders.length + 1}',
      'title': title,
      'message': message,
      'scheduledAt': at.toIso8601String(),
      'includeTime': includeTime,
    };
    reminders.add(reminder);
    return reminder;
  }

  @override
  Future<WorkflowHttpResponse> send(WorkflowHttpRequest request) async {
    requests.add(request);
    return respond?.call(request) ??
        const WorkflowHttpResponse(status: 200, body: {'ok': true});
  }

  @override
  Future<WorkflowFeed> fetchFeed(String url) async => feed;

  @override
  Future<Object?> runScript(String source, Object? input) async {
    scriptInputs.add(input);
    final run = script;
    if (run == null) {
      throw const WorkflowStepException('No script host in tests.');
    }
    return run(source, input);
  }
}

/// A workflow that is finished and turned on, with [steps] after [trigger].
Workflow readyWorkflow({
  required WorkflowTrigger trigger,
  required List<WorkflowStep> steps,
  String name = 'Test workflow',
  String workspaceId = 'ws1',
  DateTime? enabledAt,
  bool enabled = true,
}) {
  final created = DateTime(2026, 3, 1, 8);
  return Workflow(
    id: 'wf-${name.hashCode.abs()}',
    name: name,
    createdAt: created,
    updatedAt: created,
    enabled: enabled,
    enabledAt: enabledAt ?? created,
    trigger: trigger,
    steps: steps,
    workspaceId: workspaceId,
    stepCounter: steps.length,
  );
}

WorkflowStep step(
  int number,
  WorkflowStepKind kind, [
  Map<String, Object?> config = const {},
]) {
  var result = WorkflowStep.create('step$number', kind);
  for (final entry in config.entries) {
    result = result.withValue(entry.key, entry.value);
  }
  return result;
}
