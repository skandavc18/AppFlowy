import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:flutter/foundation.dart';

/// What a collection will hold, and therefore what its Add menu offers.
///
/// A collection is a folder with a purpose, and the purpose is what settles
/// this: an album that offered a presentation, or a bookmark library that
/// offered a spreadsheet, would only be a folder wearing a nicer name. Every
/// add affordance a collection draws reads this, so the answer is the same
/// whether it is asked from the header button, a context menu or a toolbar.
@immutable
class CollectionContentPolicy {
  const CollectionContentPolicy({
    this.fileKinds = const <WorkspaceFileKind>{},
    this.allowsFolders = true,
    this.allowsPages = false,
    this.allowsTables = false,
    this.allowsCollections = false,
    this.allowsLinks = false,
    this.allowsMail = false,
  });

  /// The file types this collection can read. A type appears in the menu as
  /// often as the shared catalogue offers it — authored blank, taken from
  /// disk, or both.
  final Set<WorkspaceFileKind> fileKinds;

  /// Sub-folders, for grouping. An email collection wants one per message.
  final bool allowsFolders;

  /// Pages written in AppFlowy itself.
  final bool allowsPages;

  /// Database tables, in every reading the workspace offers.
  final bool allowsTables;

  /// Nested collections.
  final bool allowsCollections;

  /// Saved web addresses.
  final bool allowsLinks;

  /// Imported `.eml` and `.mbox` mail.
  final bool allowsMail;

  bool accepts(WorkspaceFileKind kind) => fileKinds.contains(kind);

  /// The rows of the shared "New file" menu this collection is willing to
  /// show, in the catalogue's own order so the Create and Upload groups stay
  /// as they are everywhere else.
  List<WorkspaceFileMenuAction> get fileActions => [
        for (final action in workspaceFileMenuActions)
          if (fileKinds.contains(action.kind)) action,
      ];

  /// Whether there is anything at all to add. A type with nothing to offer
  /// should not draw an Add button.
  bool get isEmpty =>
      fileKinds.isEmpty &&
      !allowsFolders &&
      !allowsPages &&
      !allowsTables &&
      !allowsCollections &&
      !allowsLinks &&
      !allowsMail;

  static CollectionContentPolicy of(CollectionKind kind) =>
      collectionContentPolicies[kind]!;
}

/// Every file type the workspace knows, for a collection that is deliberately
/// a home for anything.
const Set<WorkspaceFileKind> _everyFileKind = {
  WorkspaceFileKind.file,
  WorkspaceFileKind.text,
  WorkspaceFileKind.code,
  WorkspaceFileKind.notebook,
  WorkspaceFileKind.markdown,
  WorkspaceFileKind.html,
  WorkspaceFileKind.pdf,
  WorkspaceFileKind.image,
  WorkspaceFileKind.video,
  WorkspaceFileKind.audio,
  WorkspaceFileKind.archive,
  WorkspaceFileKind.word,
  WorkspaceFileKind.excel,
  WorkspaceFileKind.csv,
  WorkspaceFileKind.powerpoint,
};

/// What each collection type holds.
const Map<CollectionKind, CollectionContentPolicy> collectionContentPolicies = {
  // A book is read: anything with pages, in any of the forms a chapter is
  // written or scanned in, plus pages authored here.
  CollectionKind.book: CollectionContentPolicy(
    fileKinds: {
      WorkspaceFileKind.markdown,
      WorkspaceFileKind.html,
      WorkspaceFileKind.pdf,
      WorkspaceFileKind.word,
      WorkspaceFileKind.excel,
      WorkspaceFileKind.powerpoint,
      WorkspaceFileKind.code,
      WorkspaceFileKind.notebook,
      WorkspaceFileKind.image,
      WorkspaceFileKind.video,
      WorkspaceFileKind.audio,
    },
    allowsPages: true,
  ),

  // An album is looked at and listened to. Nothing else belongs on the wall.
  CollectionKind.album: CollectionContentPolicy(
    fileKinds: {
      WorkspaceFileKind.image,
      WorkspaceFileKind.video,
      WorkspaceFileKind.audio,
    },
  ),

  // A repository holds whatever a project is made of — but not a table, which
  // is a database rather than a file on disk.
  CollectionKind.repository: CollectionContentPolicy(
    fileKinds: _everyFileKind,
    allowsPages: true,
    allowsCollections: true,
  ),

  // A folder collection is the plain container: files of any kind, folders
  // inside it, and pages written here. It is what a workspace folder already
  // was, given a purpose — and what a Drive, OneDrive or Box folder maps onto.
  CollectionKind.folder: CollectionContentPolicy(
    fileKinds: _everyFileKind,
    allowsPages: true,
    allowsCollections: true,
  ),

  // A database is tables, plus the two files a table is imported from.
  CollectionKind.database: CollectionContentPolicy(
    fileKinds: {
      WorkspaceFileKind.excel,
      WorkspaceFileKind.csv,
    },
    allowsTables: true,
  ),

  // A bookmark library holds addresses, and nothing that lives on disk.
  CollectionKind.bookmark: CollectionContentPolicy(
    allowsLinks: true,
  ),

  // A mailbox holds messages, notes written about them, and a folder per
  // conversation to keep the two together.
  CollectionKind.email: CollectionContentPolicy(
    allowsPages: true,
    allowsMail: true,
  ),
};
