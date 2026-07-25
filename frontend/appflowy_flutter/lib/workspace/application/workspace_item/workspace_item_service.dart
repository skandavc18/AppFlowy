import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_editor_plugins/appflowy_editor_plugins.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flowy_infra/uuid.dart';

abstract interface class WorkspaceItemRepository {
  Future<FlowyResult<ViewPB, FlowyError>> createFolder({
    required String parentViewId,
    required String name,
    ViewSectionPB? section,
  });

  Future<FlowyResult<ViewPB, FlowyError>> createTextFile({
    required String parentViewId,
    required String name,
    String content,
    ViewSectionPB? section,
  });

  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  );

  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews();

  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId);

  Future<FlowyResult<List<ViewPB>, FlowyError>> getAncestors(String viewId);

  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  });

  Future<FlowyResult<ViewPB, FlowyError>> duplicate({
    required ViewPB view,
    required String parentViewId,
  });

  Future<FlowyResult<void, FlowyError>> move({
    required String viewId,
    required String parentViewId,
    String? previousViewId,
  });

  Future<FlowyResult<void, FlowyError>> delete(List<String> viewIds);
}

class WorkspaceItemService implements WorkspaceItemRepository {
  const WorkspaceItemService();

  @override
  Future<FlowyResult<ViewPB, FlowyError>> createFolder({
    required String parentViewId,
    required String name,
    ViewSectionPB? section,
  }) {
    return ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: name,
      section: section,
      extra: const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
    );
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> createTextFile({
    required String parentViewId,
    required String name,
    String content = '',
    ViewSectionPB? section,
  }) {
    final document = Document.blank()
      ..insert(
        [0],
        [
          codeBlockNode(
            language: codeLanguageForName(name),
            delta: Delta()..insert(content),
          ),
        ],
      );
    final data = DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    if (data == null) {
      return Future.value(
        FlowyResult.failure(
          FlowyError(msg: 'Unable to create file document data.'),
        ),
      );
    }

    final metadata = WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.collaborativeText,
      mimeType: _textMimeType(name),
    );
    return ViewBackendService.createView(
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: name,
      section: section,
      initialDataBytes: data,
      extra: metadata.mergeIntoExtra(''),
    );
  }

  Future<FlowyResult<ViewPB, FlowyError>> importBinaryFile({
    required String parentViewId,
    required XFile file,
    required UserProfilePB? userProfile,
    ViewSectionPB? section,
  }) async {
    if (file.path.isEmpty) {
      return FlowyResult.failure(
        FlowyError(msg: 'The selected file is invalid.'),
      );
    }

    final viewId = uuid();
    final isLocalMode =
        (userProfile?.workspaceType ?? WorkspaceTypePB.LocalW) ==
            WorkspaceTypePB.LocalW;
    String? url;
    String? error;
    if (isLocalMode) {
      url = await saveFileToLocalStorage(file.path);
      if (url == null) {
        error = 'Unable to save the file to AppFlowy storage.';
      }
    } else {
      final result = await saveFileToCloudStorage(file.path, viewId);
      url = result.$1;
      error = result.$2;
    }
    if (url == null) {
      return FlowyResult.failure(
        FlowyError(msg: error ?? 'Unable to store the selected file.'),
      );
    }

    final length = await file.length();
    final metadata = WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.binary,
      mimeType: file.mimeType ?? 'application/octet-stream',
      storageUrl: url,
      size: length,
      modifiedAt: DateTime.now(),
    );
    final previewKind = filePreviewKindFromName(file.name);
    final document = Document.blank()
      ..insert(
        [0],
        [
          fileNode(
            url: url,
            type: isLocalMode ? FileUrlType.local : FileUrlType.cloud,
            name: file.name,
          )..attributes[FileBlockKeys.displayMode] =
              previewKind == null ? 'file' : 'preview',
        ],
      );
    final data = DocumentDataPBFromTo.fromDocument(document)?.writeToBuffer();
    if (data == null) {
      await _deleteStoredFile(url);
      return FlowyResult.failure(
        FlowyError(msg: 'Unable to create file preview data.'),
      );
    }

    final result = await ViewBackendService.createView(
      viewId: viewId,
      layoutType: ViewLayoutPB.Document,
      parentViewId: parentViewId,
      name: file.name,
      section: section,
      initialDataBytes: data,
      extra: metadata.mergeIntoExtra(''),
    );
    if (result.isFailure) {
      await _deleteStoredFile(url);
    }
    return result;
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getChildren(
    String parentViewId,
  ) {
    return ViewBackendService.getChildViews(viewId: parentViewId);
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAllViews() async {
    final result = await ViewBackendService.getAllViews();
    return result.fold(
      (views) => FlowyResult.success(views.items),
      FlowyResult.failure,
    );
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> getView(String viewId) {
    return ViewBackendService.getView(viewId);
  }

  @override
  Future<FlowyResult<List<ViewPB>, FlowyError>> getAncestors(
    String viewId,
  ) async {
    final result = await ViewBackendService.getViewAncestors(viewId);
    return result.fold(
      (views) => FlowyResult.success(views.items),
      FlowyResult.failure,
    );
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> rename({
    required String viewId,
    required String name,
  }) {
    return ViewBackendService.updateView(viewId: viewId, name: name);
  }

  @override
  Future<FlowyResult<ViewPB, FlowyError>> duplicate({
    required ViewPB view,
    required String parentViewId,
  }) {
    return ViewBackendService.duplicate(
      view: view,
      parentViewId: parentViewId,
      openAfterDuplicate: false,
      includeChildren: !view.isWorkspaceFile,
      syncAfterDuplicate: true,
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> move({
    required String viewId,
    required String parentViewId,
    String? previousViewId,
  }) {
    return ViewBackendService.moveViewV2(
      viewId: viewId,
      newParentId: parentViewId,
      prevViewId: previousViewId,
    );
  }

  @override
  Future<FlowyResult<void, FlowyError>> delete(List<String> viewIds) {
    return ViewBackendService.deleteViews(viewIds: viewIds);
  }

  Future<void> _deleteStoredFile(String url) async {
    await DocumentEventDeleteFile(DeleteFilePB(url: url)).send();
  }

  String _textMimeType(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'md' || 'markdown' => 'text/markdown',
      'json' => 'application/json',
      'html' || 'htm' => 'text/html',
      'css' => 'text/css',
      'js' => 'text/javascript',
      'yaml' || 'yml' => 'application/yaml',
      _ => 'text/plain',
    };
  }
}
