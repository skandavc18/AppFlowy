import 'dart:async';
import 'dart:io';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/find_and_replace/document_find_content.dart';
import 'package:appflowy/workspace/application/command_palette/workspace_content_search_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-document/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:fixnum/fixnum.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// Replaces I/O only; the actual provider decodes the document/cell/file data.
/// No native dispatch, user data, filesystem access or alternate search engine.
class WorkspaceSearchReads {
  final views = <String, ViewPB>{};
  final documents = <String, DocumentDataPB>{};
  final fields = <String, List<FieldPB>>{};
  final rows = <String, List<RowMetaPB>>{};
  final cells = <(String, String, String), CellPB>{};
  final calls = <String>[];
  final counts = <String, int>{};
  final denied = <String>{};
  final failures = <String>{};
  final preflightViews = <ViewPB>[];
  final forbidden = <String>[];
  final access = ValueNotifier(0);
  final changes = StreamController<String>.broadcast(sync: true);
  final scheduler = DocumentFindReadScheduler();
  final files = WorkspaceSearchFiles();
  final _gates = <String, Completer<void>>{};
  ViewPB? Function(String, int)? viewResult;
  bool allowed = true;
  bool _disposed = false;
  int inFlight = 0;
  int maximumInFlight = 0;

  ViewPB page(
    String id,
    String text, {
    String name = 'Project notes',
    String parent = 'workspace',
    Int64? creator,
    List<Node> blocks = const [],
  }) {
    final view = ViewPB(
      id: id,
      parentViewId: parent,
      name: name,
      layout: ViewLayoutPB.Document,
      createdBy: creator,
    );
    views[id] = view;
    documents[id] = searchDocument(text, blocks: blocks);
    return view;
  }

  ViewPB folder(String id, {String parent = 'workspace'}) {
    final view = ViewPB(
      id: id,
      parentViewId: parent,
      name: 'Folder',
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
    views[id] = view;
    return view;
  }

  ViewPB file(String id, String name, List<int> bytes, {String? source}) {
    final path = source ?? files.path(name);
    files.contents[path] = bytes;
    final view = page(id, '', name: name);
    view.extra = WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.binary,
      storageUrl: path,
    ).mergeIntoExtra('');
    return view;
  }

  DocumentFindReadProvider provider({
    Duration deadline = const Duration(seconds: 3),
    DocumentFindReadScheduler? readScheduler,
  }) =>
      DocumentFindReadProvider(
        scheduler: readScheduler ?? scheduler,
        deadline: deadline,
        accessChanges: access,
        contentChanges: changes.stream,
        fileAccess: files,
        readView: (id) => _read('view:$id', () {
          final override = viewResult;
          return override == null
              ? views[id]
              : override(id, counts['view:$id']!);
        }),
        preflight: (view) {
          preflightViews.add(view);
          return _read('preflight:${view.id}',
              () => allowed && !denied.contains(view.id));
        },
        readDocument: (id) {
          final document = documents[id];
          final snapshot = document == null
              ? null
              : DocumentDataPB.fromBuffer(document.writeToBuffer());
          return _read('document:$id', () => snapshot);
        },
        readViewRows: (id) => _read('rows:$id', () => rows[id]),
        readFields: (id, requested) => _read('fields:$id', () => fields[id]),
        readCell: (id, row, field) => _read('cell:$id:${row.id}:${field.id}',
            () => cells[(id, row.id, field.id)]),
        readRows: (id) async {
          forbidden.add(id);
          throw StateError('Relation-expanding export must not be used');
        },
      );

  Completer<void> hold(String stage, {int occurrence = 1}) =>
      _gates.putIfAbsent('$stage#$occurrence', Completer<void>.new);

  Future<T> _read<T>(String stage, FutureOr<T> Function() value) async {
    calls.add(stage);
    final count = counts.update(stage, (value) => value + 1, ifAbsent: () => 1);
    inFlight++;
    if (inFlight > maximumInFlight) maximumInFlight = inFlight;
    try {
      final gate = _gates['$stage#$count'];
      if (gate != null) await gate.future;
      if (failures.contains(stage)) throw StateError('Private failure details');
      return await value();
    } finally {
      inFlight--;
    }
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    for (final gate in _gates.values) {
      if (!gate.isCompleted) gate.complete();
    }
    access.dispose();
    unawaited(changes.close());
  }
}

DocumentDataPB searchDocument(String text, {List<Node> blocks = const []}) =>
    DocumentDataPBFromTo.fromDocument(
      Document(
        root: Node(
          type: PageBlockKeys.type,
          children: [paragraphNode(text: text), ...blocks],
        ),
      ),
    )!;

class WorkspaceSearchFiles extends DocumentFindFileAccess {
  final root = Platform.isWindows
      ? r'C:\appflowy-search-fixture'
      : '/appflowy-search-fixture';
  final contents = <String, List<int>>{};
  final calls = <String>[];

  String path(String name) => p.join(root, 'files', name);

  @override
  Future<String?> storageRoot() async => root;

  @override
  Future<String?> resolve(String source) async {
    calls.add('resolve');
    return source;
  }

  @override
  Future<String> canonicalPath(String path, {bool directory = false}) async =>
      path;

  @override
  Future<List<int>?> readBytes(String path, int limit) async {
    calls.add('bytes');
    return contents[path]?.take(limit + 1).toList();
  }
}

Future<void> finishContentSearch(
  WidgetTester tester,
  WorkspaceContentSearchController controller,
) async {
  await tester.pump(const Duration(milliseconds: 300));
  for (var i = 0; i < 300 && controller.state.isSearching; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(controller.state.isSearching, isFalse,
      reason: 'Bounded search completion');
}

Future<void> disposeContentSearch(
  WidgetTester tester,
  WorkspaceContentSearchController controller,
  WorkspaceSearchReads reads,
) async {
  controller.dispose();
  reads.dispose();
  await tester.pump();
}
