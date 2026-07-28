import 'dart:io';

import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

import 'archive_document.dart';

/// One archive entry dressed as a workspace item.
///
/// The folder gallery draws cards from a [ViewPB] and a
/// [WorkspaceExplorerItem]; giving an archive entry the same shape means the
/// inside of a zip is rendered by exactly the same cards as a folder, with no
/// second implementation to keep in step.
@immutable
class ArchiveEntryView {
  const ArchiveEntryView({
    required this.entry,
    required this.view,
    required this.item,
  });

  final ArchiveEntry entry;
  final ViewPB view;
  final WorkspaceExplorerItem item;
}

/// Builds workspace items for the contents of an archive.
///
/// File entries are unpacked into a working directory so every preview — the
/// picture thumbnail, the first PDF page, the opening lines of a note — reads
/// the real bytes, exactly as it does for a stored workspace file.
class ArchiveViewFactory {
  ArchiveViewFactory({
    required this.archiveId,
    required this.workingDirectory,
  });

  /// How much of one archive is unpacked for previews before the rest is left
  /// on paper only.
  static const int extractionBudgetBytes = 256 * 1024 * 1024;

  final String archiveId;
  final Directory workingDirectory;

  final Map<String, String> _extracted = {};
  int _extractedBytes = 0;

  String viewIdFor(String path) =>
      path.isEmpty ? archiveId : '$archiveId::$path';

  /// The view that stands for the archive itself, or a folder inside it.
  ViewPB folderView({
    required String path,
    required String name,
    DateTime? modified,
  }) {
    return _view(
      id: viewIdFor(path),
      parentId: viewIdFor(archiveParentPath(path)),
      name: name,
      metadata: const WorkspaceItemMetadata.folder(),
    );
  }

  /// The workspace item for one entry, unpacking it when a preview needs it.
  Future<ArchiveEntryView> viewFor(
    ArchiveDocument document,
    ArchiveEntry entry,
  ) async {
    if (entry.isDirectory) {
      final view = folderView(path: entry.path, name: entry.name);
      return ArchiveEntryView(
        entry: entry,
        view: view,
        item: WorkspaceExplorerItem.fromView(view),
      );
    }

    final view = _view(
      id: viewIdFor(entry.path),
      parentId: viewIdFor(entry.parentPath),
      name: entry.name,
      metadata: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: await extract(document, entry),
        size: entry.size,
        modifiedAt: entry.modified,
      ),
    );
    return ArchiveEntryView(
      entry: entry,
      view: view,
      item: WorkspaceExplorerItem.fromView(view),
    );
  }

  Future<List<ArchiveEntryView>> childrenOf(
    ArchiveDocument document,
    String path,
  ) async {
    final views = <ArchiveEntryView>[];
    for (final entry in document.childrenOf(path)) {
      views.add(await viewFor(document, entry));
    }
    return views;
  }

  /// Unpacks one entry and returns where it landed, or null when the archive
  /// has already used up its unpacking budget.
  Future<String?> extract(ArchiveDocument document, ArchiveEntry entry) async {
    final cached = _extracted[entry.path];
    if (cached != null) {
      return cached;
    }
    if (_extractedBytes + entry.size > extractionBudgetBytes) {
      return null;
    }
    try {
      final destination = File(
        p.join(workingDirectory.path, p.joinAll(entry.path.split('/'))),
      );
      await destination.parent.create(recursive: true);
      await destination.writeAsBytes(document.readBytes(entry.path),
          flush: true);
      _extractedBytes += entry.size;
      _extracted[entry.path] = destination.path;
      return destination.path;
    } catch (error, stackTrace) {
      Log.warn('Unable to unpack ${entry.path}: $error\n$stackTrace');
      return null;
    }
  }

  /// Forgets an unpacked copy so the next preview reads the new bytes.
  void invalidate(String path) => _extracted.remove(path);

  void clear() => _extracted.clear();

  ViewPB _view({
    required String id,
    required String parentId,
    required String name,
    required WorkspaceItemMetadata metadata,
  }) {
    return ViewPB(
      id: id,
      parentViewId: parentId,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: metadata.mergeIntoExtra(''),
    );
  }
}
