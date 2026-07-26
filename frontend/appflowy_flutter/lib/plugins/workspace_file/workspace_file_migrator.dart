import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/document/application/document_data_pb_extension.dart';
import 'package:appflowy/plugins/document/application/document_service.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_block.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_util.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:path/path.dart' as p;

/// Brings a workspace file created before the standalone viewer up to date.
///
/// Early files stored their text inside a document code block, which is why
/// they used to open as a page with an embed. This lifts that text (or the
/// embedded attachment's url) into AppFlowy storage so every file is a real
/// file with one renderer.
class WorkspaceFileMigrator {
  const WorkspaceFileMigrator({this.documentService});

  final DocumentService? documentService;

  DocumentService get _documents => documentService ?? DocumentService();

  /// Returns the storage url for [view], migrating it when needed.
  Future<String?> resolveStorageUrl(ViewPB view) async {
    final stored = view.workspaceItem?.storageUrl;
    if (stored != null && stored.isNotEmpty) {
      return stored;
    }

    final document = await _readDocument(view.id);
    if (document == null) {
      return null;
    }

    final embedded = _embeddedFileUrl(document);
    if (embedded != null) {
      await _persist(view, embedded, size: null);
      return embedded;
    }

    final name = _fileName(view);
    final url = await _writeToStorage(name, _plainText(document));
    if (url == null) {
      return null;
    }
    await _persist(view, url, size: await File(url).length());
    return url;
  }

  Future<Document?> _readDocument(String viewId) async {
    final result = await _documents.openDocument(documentId: viewId);
    return result.fold(
      (data) => data.toDocument(),
      (error) {
        Log.error('Unable to read the legacy workspace file: $error');
        return null;
      },
    );
  }

  /// Older imports kept their attachment in a file block.
  String? _embeddedFileUrl(Document document) {
    for (final node in document.root.children) {
      if (node.type != FileBlockKeys.type) {
        continue;
      }
      final url = node.attributes[FileBlockKeys.url];
      if (url is String && url.isNotEmpty) {
        return url;
      }
    }
    return null;
  }

  /// Joins every block's text the way the code block editor showed it.
  String _plainText(Document document) {
    final lines = <String>[];
    for (final node in document.root.children) {
      final delta = node.delta;
      if (delta != null) {
        lines.add(delta.toPlainText());
      }
      for (final child in node.children) {
        final childDelta = child.delta;
        if (childDelta != null) {
          lines.add(childDelta.toPlainText());
        }
      }
    }
    return lines.join('\n');
  }

  String _fileName(ViewPB view) {
    final name = view.name.trim();
    if (name.isEmpty) {
      return 'Untitled.txt';
    }
    return p.extension(name).isEmpty ? '$name.txt' : name;
  }

  Future<String?> _writeToStorage(String name, String content) async {
    Directory? staging;
    try {
      staging = await Directory.systemTemp.createTemp('appflowy_migrate_');
      final staged = File(p.join(staging.path, name));
      await staged.writeAsBytes(utf8.encode(content), flush: true);
      return await saveFileToLocalStorage(staged.path);
    } on FileSystemException catch (error) {
      Log.error('Unable to migrate the workspace file: $error');
      return null;
    } finally {
      if (staging != null) {
        try {
          await staging.delete(recursive: true);
        } on FileSystemException catch (_) {
          // A leftover temp folder is harmless.
        }
      }
    }
  }

  Future<void> _persist(ViewPB view, String url, {required int? size}) async {
    final metadata = WorkspaceItemMetadata.file(
      contentKind: WorkspaceFileContentKind.binary,
      mimeType: view.workspaceItem?.mimeType,
      storageUrl: url,
      size: size,
      modifiedAt: DateTime.now(),
    );
    final result = await ViewBackendService.updateView(
      viewId: view.id,
      extra: metadata.mergeIntoExtra(view.extra),
    );
    result.onFailure(
      (error) => Log.error('Unable to store the migrated file url: $error'),
    );
  }
}
