import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/blank_file_content.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/dispatch/dispatch.dart';
import 'package:appflowy_backend/protobuf/flowy-document/entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-error/errors.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/workspace.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_result/appflowy_result.dart';
import 'package:cross_file/cross_file.dart';
import 'package:flowy_infra/uuid.dart';
import 'package:path/path.dart' as p;

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
    return createBlankFile(
      parentViewId: parentViewId,
      kind: WorkspaceFileKind.fromName(name) ?? WorkspaceFileKind.text,
      name: name,
      section: section,
      content:
          content.isEmpty ? null : Uint8List.fromList(utf8.encode(content)),
    );
  }

  Future<FlowyResult<ViewPB, FlowyError>> importBinaryFile({
    required String parentViewId,
    required XFile file,
    UserProfilePB? userProfile,
    ViewSectionPB? section,
  }) async {
    if (file.path.isEmpty) {
      return FlowyResult.failure(
        FlowyError(msg: 'The selected file is invalid.'),
      );
    }

    return _createStoredFileView(
      parentViewId: parentViewId,
      localPath: file.path,
      name: file.name,
      mimeType: file.mimeType,
      userProfile: userProfile,
      section: section,
    );
  }

  /// Creates a blank document of [kind] and stores it as a workspace file.
  ///
  /// The bytes live in AppFlowy storage exactly like an imported file, so the
  /// same viewers and editors open it.
  Future<FlowyResult<ViewPB, FlowyError>> createBlankFile({
    required String parentViewId,
    required WorkspaceFileKind kind,
    UserProfilePB? userProfile,
    String? name,
    ViewSectionPB? section,
    Uint8List? content,
  }) async {
    final fileName = _normalizeFileName(
      name ?? kind.defaultFileName,
      kind.fileExtension,
    );

    final Directory stagingDirectory;
    try {
      stagingDirectory = await Directory.systemTemp.createTemp('appflowy_new_');
    } on FileSystemException catch (error) {
      return FlowyResult.failure(FlowyError(msg: error.message));
    }

    try {
      final staged = File(p.join(stagingDirectory.path, fileName));
      await staged.writeAsBytes(
        content ?? blankFileContent(kind),
        flush: true,
      );
      return await _createStoredFileView(
        parentViewId: parentViewId,
        localPath: staged.path,
        name: fileName,
        mimeType: _mimeTypeFor(fileName) ?? kind.mimeType,
        userProfile: userProfile,
        section: section,
      );
    } finally {
      unawaited(
        stagingDirectory
            .delete(recursive: true)
            .catchError((_) => stagingDirectory),
      );
    }
  }

  Future<FlowyResult<ViewPB, FlowyError>> _createStoredFileView({
    required String parentViewId,
    required String localPath,
    required String name,
    required String? mimeType,
    required UserProfilePB? userProfile,
    ViewSectionPB? section,
  }) async {
    final viewId = uuid();
    final profile = userProfile ??
        (await UserBackendService.getCurrentUserProfile())
            .fold((profile) => profile, (_) => null);
    final isLocalMode = (profile?.workspaceType ?? WorkspaceTypePB.LocalW) ==
        WorkspaceTypePB.LocalW;
    String? url;
    String? error;
    if (isLocalMode) {
      url = await saveFileToLocalStorage(localPath);
      if (url == null) {
        error = 'Unable to save the file to AppFlowy storage.';
      }
    } else {
      final result = await saveFileToCloudStorage(localPath, viewId);
      url = result.$1;
      error = result.$2;
    }
    if (url == null) {
      return FlowyResult.failure(
        FlowyError(msg: error ?? 'Unable to store the selected file.'),
      );
    }

    final length = await File(localPath).length();
    final metadata = WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.binary,
      mimeType: mimeType ?? 'application/octet-stream',
      storageUrl: url,
      size: length,
      modifiedAt: DateTime.now(),
    );
    final previewKind = filePreviewKindFromName(name);
    final document = Document.blank()
      ..insert(
        [0],
        [
          fileNode(
            url: url,
            type: isLocalMode ? FileUrlType.local : FileUrlType.cloud,
            name: name,
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
      name: name,
      section: section,
      initialDataBytes: data,
      extra: metadata.mergeIntoExtra(''),
    );
    if (result.isFailure) {
      await _deleteStoredFile(url);
    }
    return result;
  }

  String _normalizeFileName(String name, String extension) {
    final trimmed = name.trim();
    if (trimmed.isEmpty) {
      return 'Untitled.$extension';
    }
    if (p.extension(trimmed).isEmpty) {
      return '$trimmed.$extension';
    }
    return trimmed;
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

  String? _mimeTypeFor(String name) {
    final extension = name.split('.').last.toLowerCase();
    return switch (extension) {
      'md' || 'markdown' => 'text/markdown',
      'json' => 'application/json',
      'html' || 'htm' => 'text/html',
      'css' => 'text/css',
      'js' => 'text/javascript',
      'yaml' || 'yml' => 'application/yaml',
      'txt' || 'log' || 'ini' || 'cfg' || 'conf' => 'text/plain',
      _ => null,
    };
  }
}
