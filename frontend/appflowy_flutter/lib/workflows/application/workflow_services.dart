import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:appflowy/ai/tools/document_toolkit.dart';
import 'package:appflowy/extensions/application/script_host.dart';
import 'package:appflowy/extensions/dart/built_in/news_extension.dart';
import 'package:appflowy/plugins/database/application/row/row_service.dart';
import 'package:appflowy/plugins/database/domain/field_service.dart';
import 'package:appflowy/plugins/document/application/document_bloc.dart';
import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/shared/calendar/calendar_reminder.dart';
import 'package:appflowy/shared/calendar/reminder_store.dart';
import 'package:appflowy/shared/markdown_to_document.dart';
import 'package:appflowy/startup/tasks/app_widget.dart';
import 'package:appflowy/workspace/application/notification/notification_service.dart';
import 'package:appflowy/workspace/application/table_views/form_entry_service.dart';
import 'package:appflowy/workspace/application/table_views/table_row.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:local_notifier/local_notifier.dart';

import 'workflow_background.dart';
import 'workflow_model.dart';

/// A step that could not do its work, with a sentence saying why.
class WorkflowStepException implements Exception {
  const WorkflowStepException(this.message);

  final String message;

  @override
  String toString() => message;
}

@immutable
class WorkflowHttpRequest {
  const WorkflowHttpRequest({
    required this.method,
    required this.uri,
    this.headers = const {},
    this.body,
  });

  final String method;
  final Uri uri;
  final Map<String, String> headers;
  final String? body;
}

@immutable
class WorkflowHttpResponse {
  const WorkflowHttpResponse({
    required this.status,
    this.headers = const {},
    this.body,
  });

  final int status;
  final Map<String, String> headers;

  /// Decoded JSON when the answer was JSON, otherwise text.
  final Object? body;

  bool get ok => status >= 200 && status < 300;

  Map<String, Object?> toOutput() => {
        'status': status,
        'ok': ok,
        'headers': headers,
        'body': body,
      };
}

/// One row of a table, its cells named by column.
@immutable
class WorkflowRowData {
  const WorkflowRowData({
    required this.id,
    required this.cells,
    this.modifiedAt = 0,
  });

  final String id;
  final Map<String, String> cells;

  /// The backend's change stamp; larger is later.
  final int modifiedAt;
}

@immutable
class WorkflowRows {
  const WorkflowRows({this.columns = const [], this.rows = const []});

  final List<String> columns;
  final List<WorkflowRowData> rows;
}

@immutable
class WorkflowPageInfo {
  const WorkflowPageInfo({
    required this.id,
    required this.name,
    this.createdAt,
    this.layout = '',
  });

  final String id;
  final String name;
  final DateTime? createdAt;
  final String layout;
}

@immutable
class WorkflowFeedItem {
  const WorkflowFeedItem({
    required this.title,
    this.link = '',
    this.summary = '',
    this.image = '',
    this.publishedAt,
  });

  final String title;
  final String link;
  final String summary;
  final String image;
  final DateTime? publishedAt;

  /// What makes an item the same item next time the feed is read.
  String get key => link.isNotEmpty
      ? link
      : '$title|${publishedAt?.toUtc().toIso8601String() ?? ''}';
}

@immutable
class WorkflowFeed {
  const WorkflowFeed({this.title = '', this.items = const []});

  final String title;
  final List<WorkflowFeedItem> items;
}

/// Everything a workflow can reach outside itself. Tests replace it.
abstract class WorkflowServices {
  /// Empty while no workspace is open.
  Future<String> currentWorkspaceId();

  Future<Map<String, Object?>> createPage({
    required String parentId,
    required String title,
    required String markdown,
  });

  Future<Map<String, Object?>> appendToPage({
    required String pageId,
    required String markdown,
  });

  Future<Map<String, Object?>> addRow({
    required String viewId,
    required List<WorkflowPair> values,
  });

  Future<WorkflowRows> readRows(String viewId);

  Future<List<WorkflowPageInfo>> childPages(String parentId);

  /// Shows a desktop notification, or an in-app one where the system cannot.
  Future<void> notify({required String title, required String body});

  Future<Map<String, Object?>> createReminder({
    required String title,
    required String message,
    required DateTime at,
    required bool includeTime,
  });

  Future<WorkflowHttpResponse> send(WorkflowHttpRequest request);

  Future<WorkflowFeed> fetchFeed(String url);

  /// Runs JavaScript in the sandbox with `input` in scope.
  Future<Object?> runScript(String source, Object? input);
}

/// The real thing: pages, tables, reminders and the network.
class AppWorkflowServices implements WorkflowServices {
  AppWorkflowServices({http.Client? client})
      : _client = client ?? http.Client();

  static const requestTimeout = Duration(seconds: 30);
  static const maximumResponseBytes = 4 * 1024 * 1024;

  final http.Client _client;
  final DocumentToolkit _blocks = DocumentToolkit();

  /// Held so the plugin keeps dispatching clicks; it forgets objects nobody
  /// references.
  final Map<String, LocalNotification> _live = {};
  var _notificationCount = 0;

  @override
  Future<String> currentWorkspaceId() async {
    try {
      final result = await FolderEventReadCurrentWorkspace().send();
      return result.fold((workspace) => workspace.id, (_) => '');
    } on Object {
      return '';
    }
  }

  @override
  Future<Map<String, Object?>> createPage({
    required String parentId,
    required String title,
    required String markdown,
  }) async {
    final parent = parentId.isNotEmpty ? parentId : await currentWorkspaceId();
    if (parent.isEmpty) {
      throw const WorkflowStepException('No workspace is open.');
    }
    Uint8List? initial;
    if (markdown.trim().isNotEmpty) {
      final document = customMarkdownToDocument(markdown);
      initial = DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    }
    final result = await ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parent,
      name: title,
      initialDataBytes: initial,
    );
    return result.fold(
      (view) => {'id': view.id, 'name': view.name, 'parentId': parent},
      (error) => throw WorkflowStepException(
        'The page was not created: ${error.msg}',
      ),
    );
  }

  @override
  Future<Map<String, Object?>> appendToPage({
    required String pageId,
    required String markdown,
  }) async {
    final data = await _blocks.open(pageId);
    if (data == null) {
      throw const WorkflowStepException(
        'That page could not be opened. Was it deleted?',
      );
    }
    final nodes = _blocks.parseMarkdown(markdown).root.children;
    if (nodes.isEmpty) {
      throw const WorkflowStepException('There was nothing to add.');
    }
    final written = await _blocks.insert(
      pageId: pageId,
      nodes: nodes,
      parentId: data.pageId,
      previousId: _blocks.lastTopLevelBlockId(data),
    );
    if (written == 0) {
      throw const WorkflowStepException('The page would not take the text.');
    }
    await _refreshOpenEditor(pageId);
    return {'pageId': pageId, 'blocks': written};
  }

  /// An open editor only shows a write made underneath it once it re-reads.
  static Future<void> _refreshOpenEditor(String pageId) async {
    final bloc = DocumentBloc.findOpen(pageId);
    if (bloc == null || bloc.isClosed) {
      return;
    }
    try {
      await bloc.forceReloadDocumentState();
    } on Object catch (error) {
      Log.warn('A page could not be refreshed after a workflow wrote: $error');
    }
  }

  static const _writableColumns = {
    FieldType.RichText,
    FieldType.Number,
    FieldType.Checkbox,
    FieldType.URL,
    FieldType.SingleSelect,
    FieldType.MultiSelect,
    FieldType.DateTime,
    FieldType.Time,
  };

  @override
  Future<Map<String, Object?>> addRow({
    required String viewId,
    required List<WorkflowPair> values,
  }) async {
    final fieldsResult = await FieldBackendService.getFields(viewId: viewId);
    final fields = fieldsResult.fold((list) => list, (_) => null);
    if (fields == null) {
      throw const WorkflowStepException(
        'That table could not be read. Was it deleted?',
      );
    }

    final answers = <String, String>{};
    final written = <String, String>{};
    final skipped = <String>[];
    for (final pair in values) {
      final column = pair.key.trim().toLowerCase();
      if (column.isEmpty) {
        continue;
      }
      final field = fields.firstWhereOrNull(
        (candidate) => candidate.name.trim().toLowerCase() == column,
      );
      if (field == null) {
        skipped.add('${pair.key} (no such column)');
        continue;
      }
      if (!_writableColumns.contains(field.fieldType)) {
        skipped.add('${field.name} (cannot be filled in)');
        continue;
      }
      final value = _cellValue(field, pair.value);
      if (value == null) {
        skipped.add('${field.name} ("${pair.value}" does not fit)');
        continue;
      }
      if (value.isEmpty) {
        continue;
      }
      answers[field.id] = value;
      written[field.name] = value;
    }

    String rowId;
    if (answers.isEmpty) {
      final created = await RowBackendService.createRow(viewId: viewId);
      rowId = created.fold(
        (row) => row.id,
        (error) => throw WorkflowStepException(
          'The row was not added: ${error.msg}',
        ),
      );
    } else {
      try {
        rowId = await FormEntryService(viewId: viewId).create(answers);
      } on FormEntryException catch (error) {
        throw WorkflowStepException(
          'The row was not added (${error.code}).',
        );
      } on Object catch (error) {
        throw WorkflowStepException('The row was not added: $error');
      }
    }
    return {
      'rowId': rowId,
      'viewId': viewId,
      'values': written,
      if (skipped.isNotEmpty) 'skipped': skipped,
    };
  }

  /// What a cell will accept, or null when [raw] cannot go in that column.
  static String? _cellValue(FieldPB field, String raw) {
    final value = raw.trim();
    if (value.isEmpty) {
      return '';
    }
    switch (field.fieldType) {
      case FieldType.Number:
        final number = num.tryParse(value.replaceAll(',', ''));
        return number == null ? null : '$number';
      case FieldType.Checkbox:
        final lower = value.toLowerCase();
        if (const ['true', 'yes', '1', 'on', 'checked', 'done']
            .contains(lower)) {
          return 'Yes';
        }
        if (const ['false', 'no', '0', 'off', 'unchecked'].contains(lower)) {
          return 'No';
        }
        return null;
      case FieldType.DateTime:
        return parseTableDate(value) == null ? null : value;
      case FieldType.SingleSelect:
      case FieldType.MultiSelect:
        final options =
            SingleSelectTypeOptionPB.fromBuffer(field.typeOptionData).options;
        final wanted = field.fieldType == FieldType.SingleSelect
            ? [value]
            : tablePartsOf(value);
        final names = <String>[];
        for (final name in wanted) {
          final match = options.where(
            (option) => option.name.trim().toLowerCase() == name.toLowerCase(),
          );
          if (match.isNotEmpty) {
            names.add(match.first.name);
          }
        }
        if (names.isEmpty) {
          return null;
        }
        return field.fieldType == FieldType.SingleSelect
            ? names.first
            : names.join(',');
      default:
        return value;
    }
  }

  @override
  Future<WorkflowRows> readRows(String viewId) async {
    final fieldsResult = await FieldBackendService.getFields(viewId: viewId);
    final fields = fieldsResult.fold((list) => list, (_) => null);
    if (fields == null) {
      throw const WorkflowStepException(
        'That table could not be read. Was it deleted?',
      );
    }
    final result = await DatabaseEventGetRowsAsText(
      DatabaseViewIdPB(value: viewId),
    ).send();
    final list = result.fold((rows) => rows, (_) => null);
    if (list == null) {
      throw const WorkflowStepException('The rows could not be read.');
    }
    final names = [
      for (final id in list.fieldIds)
        fields.firstWhereOrNull((field) => field.id == id)?.name ?? id,
    ];
    return WorkflowRows(
      columns: names,
      rows: [
        for (final row in list.rows)
          WorkflowRowData(
            id: row.rowId,
            cells: {
              for (var i = 0; i < names.length; i++)
                names[i]: i < row.cells.length ? row.cells[i] : '',
            },
            modifiedAt: row.modifiedAt.toInt(),
          ),
      ],
    );
  }

  @override
  Future<List<WorkflowPageInfo>> childPages(String parentId) async {
    final result = await ViewBackendService.getChildViews(viewId: parentId);
    final views = result.fold((list) => list, (_) => null);
    if (views == null) {
      throw const WorkflowStepException(
        'That page could not be read. Was it deleted?',
      );
    }
    return [
      for (final view in views)
        WorkflowPageInfo(
          id: view.id,
          name: view.name,
          createdAt: view.createTime.toInt() > 0
              ? DateTime.fromMillisecondsSinceEpoch(
                  view.createTime.toInt() * 1000,
                )
              : null,
          layout: view.layout.name,
        ),
    ];
  }

  @override
  Future<void> notify({required String title, required String body}) async {
    final desktop = Platform.isWindows || Platform.isMacOS || Platform.isLinux;
    if (desktop && NotificationService.isReady) {
      try {
        final id = 'appflowy-workflow-${_notificationCount++}';
        final notification = LocalNotification(
          identifier: id,
          title: title,
          body: body,
        );
        notification.onClick = () {
          _live.remove(id);
          unawaited(WorkflowBackground.instance.showWindow());
        };
        notification.onClose = (_) => _live.remove(id);
        _live[id] = notification;
        if (_live.length > 20) {
          _live.remove(_live.keys.first);
        }
        await notification.show();
        return;
      } on Object catch (error) {
        Log.warn('A workflow notification could not be shown: $error');
      }
    }
    final context = AppGlobals.rootNavKey.currentContext;
    if (context == null || !context.mounted) {
      return;
    }
    showToastNotification(
      context: context,
      message: title.isEmpty ? body : title,
      description: title.isEmpty ? null : body,
    );
  }

  @override
  Future<Map<String, Object?>> createReminder({
    required String title,
    required String message,
    required DateTime at,
    required bool includeTime,
  }) async {
    final created = await ReminderStore.instance.create(
      AppReminder(
        id: '',
        title: title,
        message: message,
        scheduledAt: at,
        includeTime: includeTime,
      ),
    );
    if (created == null) {
      throw const WorkflowStepException('The reminder could not be saved.');
    }
    return {
      'id': created.id,
      'title': created.title,
      'scheduledAt': created.scheduledAt.toIso8601String(),
    };
  }

  @override
  Future<WorkflowHttpResponse> send(WorkflowHttpRequest request) async {
    final outgoing = http.Request(request.method, request.uri)
      ..headers.addAll({
        'user-agent': 'AppFlowy-Workflows/1.0',
        ...request.headers,
      });
    final body = request.body;
    if (body != null) {
      outgoing.body = body;
    }
    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(outgoing).timeout(requestTimeout);
    } on TimeoutException {
      throw WorkflowStepException(
        '${request.uri.host} did not answer within '
        '${requestTimeout.inSeconds} seconds.',
      );
    } on Object catch (error) {
      throw WorkflowStepException(
        '${request.uri.host} could not be reached: $error',
      );
    }
    final bytes = <int>[];
    try {
      await for (final chunk in streamed.stream.timeout(requestTimeout)) {
        bytes.addAll(chunk);
        if (bytes.length > maximumResponseBytes) {
          throw WorkflowStepException(
            '${request.uri.host} sent more than '
            '${maximumResponseBytes ~/ (1024 * 1024)} MB.',
          );
        }
      }
    } on TimeoutException {
      throw WorkflowStepException(
        '${request.uri.host} stopped sending its answer.',
      );
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    final type = streamed.headers['content-type'] ?? '';
    Object? decoded = text;
    final trimmed = text.trimLeft();
    if (type.contains('json') ||
        trimmed.startsWith('{') ||
        trimmed.startsWith('[')) {
      try {
        decoded = jsonDecode(text);
      } on FormatException {
        decoded = text;
      }
    }
    return WorkflowHttpResponse(
      status: streamed.statusCode,
      headers: streamed.headers,
      body: decoded,
    );
  }

  @override
  Future<WorkflowFeed> fetchFeed(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        uri.host.isEmpty) {
      throw WorkflowStepException('"$url" is not a feed address.');
    }
    final response = await send(
      WorkflowHttpRequest(
        method: 'GET',
        uri: uri,
        headers: const {
          'accept': 'application/rss+xml, application/atom+xml, '
              'application/xml;q=0.9, text/xml;q=0.9, */*;q=0.5',
        },
      ),
    );
    if (!response.ok) {
      throw WorkflowStepException(
        '${uri.host} answered ${response.status}.',
      );
    }
    final body = response.body;
    try {
      final channel = NewsChannel.parse(body is String ? body : '$body');
      return WorkflowFeed(
        title: channel.title,
        items: [
          for (final item in channel.items)
            WorkflowFeedItem(
              title: item.title,
              link: item.link,
              summary: item.summary,
              image: item.image,
              publishedAt: item.publishedAt,
            ),
        ],
      );
    } on StateError catch (error) {
      throw WorkflowStepException(error.message);
    }
  }

  @override
  Future<Object?> runScript(String source, Object? input) async {
    final outcome = await ScriptHost.instance.run(source: source, input: input);
    if (outcome.isError) {
      throw WorkflowStepException(outcome.error);
    }
    return outcome.value;
  }
}
