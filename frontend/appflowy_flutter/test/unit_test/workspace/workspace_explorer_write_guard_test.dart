import 'dart:async';

import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item_clipboard.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../util/workspace_explorer_permission_fakes.dart';

void main() {
  late ExplorerPermissionRepository repository;
  late WorkspaceExplorerController controller;
  late bool writable;
  late bool disposed;

  setUp(() async {
    WorkspaceItemClipboard.instance.clear();
    writable = true;
    disposed = false;
    repository = ExplorerPermissionRepository();
    controller = WorkspaceExplorerController(
      root: repository.root,
      repository: repository,
      listenForUpdates: false,
      canWrite: () => writable,
    );
    await controller.initialize();
  });

  tearDown(() {
    if (!disposed) controller.dispose();
    WorkspaceItemClipboard.instance.clear();
  });

  test('read-only blocks every mutation entry but preserves Copy', () async {
    writable = false;
    controller.selection.selectOnly(repository.first.id);
    controller.copySelection();
    final copied = controller.clipboard.data;
    controller.cutSelection();
    expect(controller.clipboard.data, same(copied));
    expect(controller.canPaste, isFalse);
    expect(controller.canMutateSelection, isFalse);

    controller.beginCreate(WorkspaceExplorerDraftKind.folder);
    expect(controller.draft, isNull);
    expect(await controller.commitDraft('Denied'), isFalse);
    controller.beginRename(repository.first.id);
    expect(controller.editingId, isNull);
    expect(await controller.commitRename('Denied'), isFalse);
    expect(await controller.createFolderImmediately(), isNull);
    expect(await controller.createPageImmediately(), isNull);
    for (final source in WorkspaceFileSource.values) {
      final action = WorkspaceFileMenuAction(WorkspaceFileKind.text, source);
      expect(await controller.createFileOfKind(action), isNull);
      expect(await controller.createFileImmediately(action), isNull);
    }
    await controller.duplicateSelection();
    await controller.paste();
    await controller.moveItem(itemId: 'first', parentId: 'folder');
    await controller.deleteSelection();

    expect(repository.writes, isEmpty);
    expect(repository.ancestorRequests, isEmpty);
    expect(controller.errorMessage, isNull);
    expect(controller.selection.ids, {'first'});
  });

  test(
      'restoring write access restores create rename duplicate paste move delete',
      () async {
    writable = false;
    controller.beginCreate(WorkspaceExplorerDraftKind.folder);
    writable = true;
    controller.beginCreate(WorkspaceExplorerDraftKind.folder);
    expect(await controller.commitDraft('New folder'), isTrue);
    controller.beginRename('first');
    expect(await controller.commitRename('Renamed.bin'), isTrue);
    controller.selection.selectOnly('first');
    await controller.duplicateSelection();
    controller.copySelection();
    await controller.paste(parentId: 'folder');
    await controller.moveItem(itemId: 'first', parentId: 'folder');
    controller.selection.selectOnly('second');
    await controller.deleteSelection();

    expect(repository.writes, [
      'createFolder:root',
      'rename:first',
      'duplicate:first:root',
      'duplicate:first:folder',
      'move:first:folder',
      'delete:second',
    ]);
  });

  test('navigation expansion search refresh and copy work while read-only',
      () async {
    writable = false;
    await controller.toggleFolder('folder');
    expect(controller.rows.any((row) => row.item.id == 'nested'), isTrue);
    await controller.search('Nested');
    controller.selectAll();
    expect(controller.selection.ids, {'nested'});
    controller.copySelection();
    expect(controller.clipboard.data!.views.single.id, 'nested');
    await controller.navigateTo('folder');
    await controller.refresh();
    expect(controller.currentFolder.id, 'folder');
    expect(controller.rows.single.item.id, 'nested');
    expect(repository.writes, isEmpty);
  });

  test('standalone controllers keep the existing permissive default', () async {
    final standalone = WorkspaceExplorerController(
      root: repository.root,
      repository: repository,
      listenForUpdates: false,
    );
    try {
      await standalone.initialize();
      expect(standalone.canWrite, isTrue);
      expect(
        await standalone.createFolderImmediately(name: 'Standalone'),
        isNotNull,
      );
    } finally {
      standalone.dispose();
    }
  });

  test('borrowed guards compose with owner and retire independently', () async {
    var hostWritable = false;
    final release = controller.restrictWrites(
      canWrite: () => hostWritable,
      canRename: (id) => id != 'root',
    );
    expect(controller.canWrite, isFalse);
    hostWritable = true;
    expect(controller.canWrite, isTrue);
    controller.beginRename('root');
    expect(controller.editingId, isNull);
    expect(
      await controller.createFolderImmediately(name: 'Member add'),
      isNotNull,
    );
    controller.beginRename('first');
    expect(await controller.commitRename('Child identity'), isTrue);
    writable = false;
    release();
    release();
    expect(controller.canWrite, isFalse, reason: 'Owner gate must survive.');
    writable = true;
    controller.beginRename('root');
    expect(controller.editingId, 'root');
  });

  test('a revoked draft and rename cannot commit and remain hidden', () async {
    controller.beginCreate(WorkspaceExplorerDraftKind.file);
    writable = false;
    expect(controller.draft, isNull);
    expect(await controller.commitDraft('Denied.bin'), isFalse);
    writable = true;
    controller.cancelEditing();
    controller.beginRename('first');
    writable = false;
    expect(controller.editingId, isNull);
    expect(await controller.commitRename('Denied.bin'), isFalse);
    expect(repository.writes, isEmpty);
  });

  test('known locked children and destinations are not offered as writable',
      () async {
    controller.updateView(
      ViewPB.fromBuffer(repository.folder.writeToBuffer())..isLocked = true,
    );
    controller.selection.selectOnly('folder');
    expect(controller.canMutateSelection, isFalse);
    controller.beginRename('folder');
    controller.beginCreate(
      WorkspaceExplorerDraftKind.folder,
      parentId: 'folder',
    );
    await controller.deleteSelection();
    await controller.duplicateSelection();
    await controller.moveItem(itemId: 'first', parentId: 'folder');
    controller.clipboard.copy([repository.first]);
    await controller.paste(parentId: 'folder');
    expect(repository.writes, isEmpty);
    expect(controller.draft, isNull);
    expect(controller.editingId, isNull);
  });

  test('backend rejection of a child still wins over a writable host',
      () async {
    repository.failure = FlowyError(msg: 'Child access denied');
    controller.selection.selectOnly('first');
    await controller.deleteSelection();
    expect(repository.writes, ['delete:first']);
    expect(controller.errorMessage, 'Child access denied');
    expect(controller.viewForId('first'), isNotNull);
  });

  for (final reason in ['revoked', 'navigated', 'retired', 'disposed']) {
    test('move preflight stops when $reason before its reply', () async {
      final release = controller.restrictWrites(
        canWrite: () => true,
        canRename: (_) => true,
      );
      final pending = Completer<List<ViewPB>>();
      repository.nextAncestors = pending;
      final move = controller.moveItem(itemId: 'first', parentId: 'folder');
      expect(repository.ancestorRequests, ['folder']);
      switch (reason) {
        case 'revoked':
          writable = false;
        case 'navigated':
          await controller.navigateTo('folder');
        case 'retired':
          release();
          expect(controller.canWrite, isTrue);
        case 'disposed':
          controller.dispose();
          disposed = true;
      }
      pending.complete([repository.root, repository.folder]);
      await move;
      expect(repository.writes, isEmpty);
    });
  }

  for (final operation in WorkspaceItemClipboardOperation.values) {
    test('${operation.name} paste rechecks after ancestor preflight', () async {
      if (operation == WorkspaceItemClipboardOperation.copy) {
        controller.clipboard.copy([repository.folder]);
      } else {
        controller.clipboard.cut([repository.first]);
      }
      final data = controller.clipboard.data;
      final pending = Completer<List<ViewPB>>();
      repository.nextAncestors = pending;
      final paste = controller.paste(parentId: 'root');
      writable = false;
      pending.complete([repository.root]);
      await paste;
      expect(repository.writes, isEmpty);
      expect(controller.clipboard.data, same(data));
    });
  }

  for (final operation in ['duplicate', 'copy', 'cut']) {
    test('$operation batch stops after an already-dispatched write is revoked',
        () async {
      controller.selection.selectAll(['first', 'second']);
      if (operation == 'copy') controller.copySelection();
      if (operation == 'cut') controller.cutSelection();
      final data = controller.clipboard.data;
      repository.beforeWriteReply = (_) async {
        writable = false;
      };
      if (operation == 'duplicate') {
        await controller.duplicateSelection();
      } else {
        await controller.paste(parentId: 'folder');
      }
      expect(repository.writes, hasLength(1));
      if (operation != 'duplicate') {
        expect(controller.clipboard.data, same(data));
      }
    });
  }

  for (final operation in ['create', 'draft', 'rename', 'delete']) {
    test('$operation ignores a late success after write access is revoked',
        () async {
      final reply = Completer<void>();
      repository.beforeWriteReply = (_) => reply.future;
      Future<Object?> start() async {
        switch (operation) {
          case 'create':
            return controller.createFolderImmediately(name: 'Late');
          case 'draft':
            controller.beginCreate(WorkspaceExplorerDraftKind.folder);
            return controller.commitDraft('Late');
          case 'rename':
            controller.beginRename('first');
            return controller.commitRename('Late');
          default:
            controller.selection.selectOnly('first');
            await controller.deleteSelection();
            return null;
        }
      }

      final pending = start();
      expect(repository.writes, hasLength(1));
      writable = false;
      reply.complete();
      final result = await pending;
      expect(
        result,
        operation == 'draft' || operation == 'rename' ? false : null,
      );
      expect(controller.viewForId('first')!.name, 'First.bin');
      expect(controller.viewForId('created-1'), isNull);
      // This does not claim cancellation/rollback of the request sent earlier.
      expect(repository.writes, hasLength(1));
    });
  }

  for (final immediately in [false, true]) {
    test(
        'upload ($immediately) rechecks permission before consuming picker data',
        () async {
      getIt.pushNewScope();
      final picker = _PendingPicker();
      getIt.registerSingleton<FilePickerService>(picker);
      try {
        const action = WorkspaceFileMenuAction(
          WorkspaceFileKind.text,
          WorkspaceFileSource.upload,
        );
        final pending = immediately
            ? controller.createFileImmediately(action)
            : controller.createFileOfKind(action);
        expect(picker.calls, 1);
        writable = false;
        picker.reply.complete(
          FilePickerResult([
            PlatformFile(
              name: 'never-read.txt',
              size: 4,
              path: r'C:\not-opened\never-read.txt',
            ),
          ]),
        );
        expect(await pending, isNull);
        expect(repository.writes, isEmpty);
      } finally {
        await getIt.popScope();
      }
    });
  }
}

class _PendingPicker extends FilePickerService {
  final reply = Completer<FilePickerResult?>();
  int calls = 0;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
  }) {
    calls++;
    return reply.future;
  }
}
