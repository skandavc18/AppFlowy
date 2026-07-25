import 'dart:async';

import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_transfer_service.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late _FakeWorkspaceItemRepository repository;
  late ViewPB root;
  late ViewPB folder;
  late ViewPB file;
  late WorkspaceExplorerController controller;

  setUp(() {
    WorkspaceItemClipboard.instance.clear();
    repository = _FakeWorkspaceItemRepository();
    root = _folder('root', '', 'Project');
    folder = _folder('folder', root.id, 'Sources');
    file = _file('readme', root.id, 'README.md');
    repository.children[root.id] = [folder, file];
    repository.children[folder.id] = [
      _file('main', folder.id, 'main.dart'),
    ];
    repository.allViews = [
      root,
      folder,
      file,
      ...repository.children[folder.id]!,
    ];
    repository.ancestors[folder.id] = [root];
    controller = WorkspaceExplorerController(
      root: root,
      repository: repository,
      listenForUpdates: false,
    );
  });

  tearDown(() {
    controller.dispose();
  });

  test('loads only the current folder until a branch is expanded', () async {
    await controller.initialize();

    expect(repository.childRequests, ['root']);
    expect(controller.rows.map((row) => row.item.id), ['folder', 'readme']);
    expect(repository.allViewsRequests, 0);

    await controller.toggleFolder(folder.id);

    expect(repository.childRequests, ['root', 'folder']);
    expect(
      controller.rows.map((row) => row.item.id),
      ['folder', 'main', 'readme'],
    );
    expect(controller.rows[1].depth, 1);
  });

  test('allows the explorer root title to be renamed inline', () async {
    await controller.initialize();

    controller.beginRename(root.id);
    expect(controller.editingId, root.id);

    expect(await controller.commitRename('Knowledge HQ'), isTrue);
    expect(controller.editingId, isNull);
    expect(controller.root.name, 'Knowledge HQ');
  });

  test('search loads the flat index and restores normal expansion', () async {
    await controller.initialize();
    await controller.toggleFolder(folder.id);

    await controller.search('main');
    expect(repository.allViewsRequests, 1);
    expect(
      controller.rows.map((row) => row.item.id),
      ['folder', 'main'],
    );

    await controller.search('');
    expect(
      controller.rows.map((row) => row.item.id),
      ['folder', 'main', 'readme'],
    );
  });

  test('reuses the workspace index while refining a search', () async {
    await controller.initialize();

    await controller.search('main');
    await controller.search('readme');

    expect(repository.allViewsRequests, 1);
    expect(controller.rows.map((row) => row.item.id), ['readme']);
  });

  test('search is scoped to the current folder', () async {
    final outside = _file('outside', root.id, 'main-copy.dart');
    repository.children[root.id] = [folder, file, outside];
    repository.allViews.add(outside);
    await controller.initialize();
    await controller.navigateTo(folder.id);

    await controller.search('main');

    expect(controller.rows.map((row) => row.item.id), ['main']);
    expect(
      controller.rows.any((row) => row.item.id == controller.currentFolder.id),
      isFalse,
    );
  });

  test('search select all excludes contextual ancestor folders', () async {
    await controller.initialize();

    await controller.search('main');
    controller.selectAll();

    expect(controller.rows.map((row) => row.item.id), ['folder', 'main']);
    expect(controller.selection.ids, {'main'});
  });

  test('fresh search data takes precedence over cached views', () async {
    await controller.initialize();
    final renamedFile = ViewPB.fromBuffer(file.writeToBuffer())
      ..name = 'GUIDE.md';
    repository.allViews = [
      root,
      folder,
      renamedFile,
      ...repository.children[folder.id]!,
    ];

    await controller.search('guide');

    expect(controller.rows.map((row) => row.item.id), ['readme']);
    expect(controller.rows.single.item.name, 'GUIDE.md');
  });

  test('builds complete breadcrumbs for a nested folder', () async {
    final nested = _folder('nested', folder.id, 'Generated');
    repository.children[folder.id] = [nested];
    repository.children[nested.id] = [];

    await controller.initialize();
    await controller.toggleFolder(folder.id);
    await controller.navigateTo(nested.id);

    expect(
      controller.breadcrumbs.map((item) => item.id),
      ['root', 'folder', 'nested'],
    );
  });

  test('passes insertion position when reordering', () async {
    await controller.initialize();
    repository.ancestors[root.id] = [];

    await controller.moveItem(
      itemId: file.id,
      parentId: root.id,
      previousViewId: folder.id,
    );

    expect(repository.lastMove, (file.id, root.id, folder.id));
  });

  test('deleting an active search result rebuilds search rows', () async {
    await controller.initialize();
    await controller.search('readme');
    controller.selectRow(file.id, toggle: false, range: false);

    await controller.deleteSelection();

    expect(controller.rows, isEmpty);
    expect(controller.viewForId(file.id), isNull);
    expect(repository.allViewsRequests, 2);
  });

  test('duplicates a nested item beside its original', () async {
    await controller.initialize();
    await controller.toggleFolder(folder.id);
    controller.selectRow('main', toggle: false, range: false);

    await controller.duplicateSelection();

    expect(repository.duplicateCalls, [('main', 'folder')]);
  });

  test('preserves visual order when pasting multiple cut items', () async {
    final util = _file('util', folder.id, 'util.dart');
    repository.children[folder.id] = [
      repository.allViews.firstWhere((view) => view.id == 'main'),
      util,
    ];
    repository.allViews.add(util);
    await controller.initialize();
    await controller.toggleFolder(folder.id);
    controller.selectRow('main', toggle: false, range: false);
    controller.selectRow('util', toggle: true, range: false);
    controller.cutSelection();
    repository.childRequests.clear();

    await controller.paste(parentId: root.id);

    expect(
      repository.moveCalls,
      [
        ('main', 'root', null),
        ('util', 'root', 'main'),
      ],
    );
    expect(repository.childRequests, containsAll(['folder', 'root']));
  });

  test('rejects copying a folder into its descendant', () async {
    final nested = _folder('nested', folder.id, 'Nested');
    repository.children[folder.id] = [nested];
    repository.children[nested.id] = [];
    repository.allViews.add(nested);
    repository.ancestors[nested.id] = [root, folder, nested];
    await controller.initialize();
    await controller.toggleFolder(folder.id);
    controller.selectRow(folder.id, toggle: false, range: false);
    controller.copySelection();

    await controller.paste(parentId: nested.id);

    expect(repository.duplicateCalls, isEmpty);
    expect(controller.errorMessage, isNotNull);
  });

  test('preflights every copied item before duplicating any item', () async {
    final nested = _folder('nested', folder.id, 'Nested');
    repository.children[root.id] = [file, folder];
    repository.children[folder.id] = [nested];
    repository.children[nested.id] = [];
    repository.allViews = [root, file, folder, nested];
    repository.ancestors[nested.id] = [root, folder, nested];
    await controller.initialize();
    controller.selectRow(file.id, toggle: false, range: false);
    controller.selectRow(folder.id, toggle: true, range: false);
    controller.copySelection();

    await controller.paste(parentId: nested.id);

    expect(repository.duplicateCalls, isEmpty);
    expect(controller.errorMessage, isNotNull);
  });

  test('rejects copying a page into one of its subpages', () async {
    final page = _page('page', root.id, 'Page');
    final subpage = _page('subpage', page.id, 'Subpage');
    repository.children[root.id] = [page];
    repository.children[page.id] = [subpage];
    repository.children[subpage.id] = [];
    repository.allViews = [root, page, subpage];
    repository.ancestors[subpage.id] = [root, page, subpage];
    await controller.initialize();
    controller.selectRow(page.id, toggle: false, range: false);
    controller.copySelection();

    await controller.paste(parentId: subpage.id);

    expect(repository.duplicateCalls, isEmpty);
    expect(controller.errorMessage, isNotNull);
  });

  test('navigation invalidates an in-flight search', () async {
    final searchCompleter = Completer<List<ViewPB>>();
    repository.allViewsCompleter = searchCompleter;
    await controller.initialize();

    final pendingSearch = controller.search('readme');
    await Future<void>.delayed(Duration.zero);
    await controller.navigateTo(folder.id);
    searchCompleter.complete(repository.allViews);
    await pendingSearch;

    expect(controller.query, isEmpty);
    expect(controller.currentFolder.id, folder.id);
    expect(controller.rows.map((row) => row.item.id), ['main']);
  });

  test('calculates reorder predecessors without the dragged item', () async {
    final third = _file('third', root.id, 'third.txt');
    repository.children[root.id] = [folder, file, third];
    repository.allViews.add(third);
    await controller.initialize();

    expect(
      controller.previousSiblingId(third.id, excludingId: file.id),
      folder.id,
    );
  });

  test('forced refresh keeps the newest in-flight response', () async {
    await controller.initialize();
    final staleResponse = Completer<List<ViewPB>>();
    final freshResponse = Completer<List<ViewPB>>();
    repository.childResponseCompleters[root.id] = [
      staleResponse,
      freshResponse,
    ];
    final freshFile = _file('fresh', root.id, 'fresh.txt');

    final firstRefresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    final secondRefresh = controller.refresh();
    await Future<void>.delayed(Duration.zero);
    freshResponse.complete([freshFile]);
    await secondRefresh;
    staleResponse.complete([file]);
    await firstRefresh;

    expect(controller.rows.map((row) => row.item.id), ['fresh']);
  });

  test('transfer service rejects moving a folder into its descendant',
      () async {
    final nested = _folder('nested', folder.id, 'Nested');
    repository.children[folder.id] = [nested];
    repository.children[nested.id] = [];
    repository.allViews = [root, folder, nested, file];
    final service = WorkspaceItemTransferService(repository: repository);

    final result = await service.moveTo(
      views: [folder],
      destinationId: nested.id,
    );

    expect(result.isFailure, isTrue);
    expect(repository.moveCalls, isEmpty);
  });

  test('transfer service copies to a selected folder', () async {
    repository.allViews = [root, folder, file];
    final service = WorkspaceItemTransferService(repository: repository);

    final result = await service.copyTo(
      views: [file],
      destinationId: folder.id,
    );

    expect(result.isSuccess, isTrue);
    expect(repository.duplicateCalls, [(file.id, folder.id)]);
  });

  test('pasting a cut sidebar item moves it and clears the clipboard',
      () async {
    repository.allViews = [root, folder, file];
    WorkspaceItemClipboard.instance.cut([file]);
    final service = WorkspaceItemTransferService(repository: repository);

    final result = await service.pasteTo(destinationId: folder.id);

    expect(result.isSuccess, isTrue);
    expect(repository.moveCalls, [(file.id, folder.id, null)]);
    expect(WorkspaceItemClipboard.instance.hasData, isFalse);
  });

  test('transfer service rejects destinations in another space', () async {
    final firstSpace = ViewPB(
      id: 'space-a',
      parentViewId: 'workspace',
      name: 'First space',
      extra: '{"is_space":true}',
    );
    final secondSpace = ViewPB(
      id: 'space-b',
      parentViewId: 'workspace',
      name: 'Second space',
      extra: '{"is_space":true}',
    );
    final source = _page('source', firstSpace.id, 'Published page');
    final destination = _folder('destination', secondSpace.id, 'Archive');
    repository.allViews = [
      firstSpace,
      secondSpace,
      source,
      destination,
    ];
    final service = WorkspaceItemTransferService(repository: repository);

    final moveResult = await service.moveTo(
      views: [source],
      destinationId: destination.id,
    );
    final copyResult = await service.copyTo(
      views: [source],
      destinationId: destination.id,
    );

    expect(moveResult.isFailure, isTrue);
    expect(copyResult.isFailure, isTrue);
    expect(repository.moveCalls, isEmpty);
    expect(repository.duplicateCalls, isEmpty);
    expect(
      workspaceTransferScopeId(view: source, allViews: repository.allViews),
      firstSpace.id,
    );
  });
}

ViewPB _folder(String id, String parentId, String name) => ViewPB(
      id: id,
      parentViewId: parentId,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );

ViewPB _file(String id, String parentId, String name) => ViewPB(
      id: id,
      parentViewId: parentId,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: const WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.collaborativeText,
      ).mergeIntoExtra(''),
    );

ViewPB _page(String id, String parentId, String name) => ViewPB(
      id: id,
      parentViewId: parentId,
      name: name,
      layout: ViewLayoutPB.Document,
    );

class _FakeWorkspaceItemRepository implements WorkspaceItemRepository {
  final Map<String, List<ViewPB>> children = {};
  final Map<String, List<ViewPB>> ancestors = {};
  final List<String> childRequests = [];
  List<ViewPB> allViews = [];
  int allViewsRequests = 0;
  (String, String, String?)? lastMove;
  final List<(String, String, String?)> moveCalls = [];
  final List<(String, String)> duplicateCalls = [];
  int duplicateCount = 0;
  Completer<List<ViewPB>>? allViewsCompleter;
  final Map<String, List<Completer<List<ViewPB>>>> childResponseCompleters = {};

  @override
  Future<FlowyResult<ViewPB, FlowyError>> createFolder({
    required String parentViewId,
    required String name,
    ViewSectionPB? section,
  }) async {
    return FlowyResult.success(_folder(name, parentViewId, name));
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> createTextFile({
    required String parentViewId,
    required String name,
    String content = '',
    ViewSectionPB? section,
  }) async {
    return FlowyResult.success(_file(name, parentViewId, name));
  }

  @override
  Future<FlowyResult<void, FlowyError>> delete(List<String> viewIds) async {
    final deleted = viewIds.toSet();
    var foundDescendant = true;
    while (foundDescendant) {
      foundDescendant = false;
      for (final view in allViews) {
        if (deleted.contains(view.parentViewId) && deleted.add(view.id)) {
          foundDescendant = true;
        }
      }
    }
    allViews.removeWhere((view) => deleted.contains(view.id));
    for (final entries in children.values) {
      entries.removeWhere((view) => deleted.contains(view.id));
    }
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> duplicate({
    required ViewPB view,
    required String parentViewId,
  }) async {
    duplicateCalls.add((view.id, parentViewId));
    final duplicate = ViewPB.fromBuffer(view.writeToBuffer())
      ..id = 'duplicate-${++duplicateCount}'
      ..parentViewId = parentViewId;
    allViews.add(duplicate);
    children.putIfAbsent(parentViewId, () => []).add(duplicate);
    return FlowyResult.success(duplicate);
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async {
    allViewsRequests++;
    final completer = allViewsCompleter;
    return FlowyResult.success(
      completer == null ? allViews : await completer.future,
    );
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAncestors(
    String viewId,
  ) async {
    return FlowyResult.success(ancestors[viewId] ?? []);
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) async {
    childRequests.add(parentViewId);
    final completers = childResponseCompleters[parentViewId];
    final views = completers != null && completers.isNotEmpty
        ? await completers.removeAt(0).future
        : children[parentViewId] ?? [];
    return FlowyResult.success(views);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId) async {
    ViewPB? view;
    for (final candidate in allViews) {
      if (candidate.id == viewId) {
        view = candidate;
        break;
      }
    }
    return view == null
        ? FlowyResult.failure(FlowyError(msg: 'Not found'))
        : FlowyResult.success(view);
  }

  @override
  Future<FlowyResult<void, FlowyError>> move({
    required String viewId,
    required String parentViewId,
    String? previousViewId,
  }) async {
    lastMove = (viewId, parentViewId, previousViewId);
    moveCalls.add(lastMove!);
    final view = allViews.firstWhere((view) => view.id == viewId);
    children[view.parentViewId]?.removeWhere((child) => child.id == viewId);
    final target = children.putIfAbsent(parentViewId, () => []);
    final previousIndex = previousViewId == null
        ? -1
        : target.indexWhere((child) => child.id == previousViewId);
    final insertIndex = previousIndex < 0 ? 0 : previousIndex + 1;
    view.parentViewId = parentViewId;
    target.insert(insertIndex, view);
    return FlowyResult.success(null);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) async {
    final view = allViews.firstWhere((view) => view.id == viewId);
    return FlowyResult.success(view..name = name);
  }
}
