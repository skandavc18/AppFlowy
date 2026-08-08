import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

enum WorkspaceExplorerItemKind {
  folder,
  file,
  document,
  database;
}

@immutable
class WorkspaceExplorerItem {
  const WorkspaceExplorerItem({
    required this.id,
    required this.parentId,
    required this.name,
    required this.kind,
    required this.metadata,
    required this.hasChildren,
    required this.lastEdited,
    this.collection,
    this.bookmark,
    this.readsFromService = false,
  });

  factory WorkspaceExplorerItem.fromView(ViewPB view) {
    final metadata = view.workspaceItem;
    final kind = switch ((metadata?.kind, view.layout)) {
      (WorkspaceItemKind.folder, _) => WorkspaceExplorerItemKind.folder,
      (WorkspaceItemKind.file, _) => WorkspaceExplorerItemKind.file,
      (_, ViewLayoutPB.Document) => WorkspaceExplorerItemKind.document,
      _ => WorkspaceExplorerItemKind.database,
    };
    final backendLastEdited = view.lastEdited.toInt();
    return WorkspaceExplorerItem(
      id: view.id,
      parentId: view.parentViewId,
      name: view.name,
      kind: kind,
      metadata: metadata,
      collection: view.collection,
      bookmark: view.bookmark,
      readsFromService: view.source.isRemote,
      hasChildren: view.childViews.isNotEmpty,
      lastEdited: backendLastEdited > 0
          ? DateTime.fromMillisecondsSinceEpoch(backendLastEdited * 1000)
          : metadata?.modifiedAt,
    );
  }

  final String id;
  final String parentId;
  final String name;
  final WorkspaceExplorerItemKind kind;
  final WorkspaceItemMetadata? metadata;

  /// Set when this container is a collection rather than a plain folder.
  final CollectionMetadata? collection;

  /// Set when this item is a saved link rather than a file on disk.
  final BookmarkMetadata? bookmark;

  /// Whether this container's contents live in a service rather than here.
  final bool readsFromService;
  final bool hasChildren;
  final DateTime? lastEdited;

  bool get isFolder => kind == WorkspaceExplorerItemKind.folder;
  bool get isFile => kind == WorkspaceExplorerItemKind.file;
  bool get isCollection => collection != null;
  bool get isBookmark => bookmark != null;

  /// Whether browsing into this shows what it holds.
  ///
  /// A collection has a purpose of its own and a bound folder's contents are
  /// somewhere else entirely, so both open as themselves instead.
  bool get isBrowsable => isFolder && !isCollection && !readsFromService;
}

@immutable
class WorkspaceExplorerRow {
  const WorkspaceExplorerRow({
    required this.item,
    required this.depth,
    required this.isExpanded,
    required this.isLoading,
  });

  final WorkspaceExplorerItem item;
  final int depth;
  final bool isExpanded;
  final bool isLoading;
}

enum WorkspaceExplorerDraftKind {
  file,
  folder;
}

@immutable
class WorkspaceExplorerDraft {
  const WorkspaceExplorerDraft({
    required this.kind,
    required this.parentId,
    required this.suggestedName,
  });

  final WorkspaceExplorerDraftKind kind;
  final String parentId;
  final String suggestedName;
}
