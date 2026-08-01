import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_browser_view.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_docs_view.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_graph_view.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_host.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_symbols_view.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_tree_view.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_state.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/material.dart';

abstract final class RepositoryViewIds {
  static const browser = 'repo_browser';
  static const tree = 'repo_tree';
  static const symbols = 'repo_symbols';
  static const graph = 'repo_graph';
  static const docs = 'repo_docs';
}

/// Opens [view] where a repository file can actually be read: the tree, with
/// the source beside it. Opening it as a workspace tab would leave the
/// repository, which is not what clicking a file in a listing means.
///
/// A nested collection keeps its own identity and opens in the workspace.
void openRepoObject(CollectionViewContext collection, ViewPB view) {
  if (view.isCollection || view.isWorkspaceFolder) {
    collection.onOpen(view);
    return;
  }
  final state = RepoState.fromJson(collection.stateFor(repositoryStateKey));
  // `relativePathFor` starts at the repository itself; a repository path is
  // relative to its contents, so the root's own name comes off the front.
  final segments = collection.explorer.relativePathFor(view.id).split('/')
    ..removeAt(0);
  final expanded = {
    ...state.expandedPaths,
    for (var index = 1; index < segments.length; index++)
      segments.take(index).join('/'),
  };
  collection.onStateChanged(
    repositoryStateKey,
    state.copyWith(expandedPaths: expanded, activeFileId: view.id).toJson(),
  );
  collection.onOpenView(RepositoryViewIds.tree);
}

List<CollectionViewDefinition> repositoryCollectionViews() => [
      CollectionViewDefinition(
        id: RepositoryViewIds.browser,
        labelKey: LocaleKeys.collections_repository_browser,
        icon: Icons.dashboard_rounded,
        builder: (context, collection) =>
            RepositoryBrowserView(collection: collection),
      ),
      CollectionViewDefinition(
        id: RepositoryViewIds.tree,
        labelKey: LocaleKeys.collections_repository_tree,
        icon: Icons.account_tree_rounded,
        builder: (context, collection) =>
            RepositoryTreeView(collection: collection),
      ),
      CollectionViewDefinition(
        id: RepositoryViewIds.symbols,
        labelKey: LocaleKeys.collections_repository_symbols,
        icon: Icons.data_object_rounded,
        builder: (context, collection) =>
            RepositorySymbolsView(collection: collection),
      ),
      CollectionViewDefinition(
        id: RepositoryViewIds.graph,
        labelKey: LocaleKeys.collections_repository_graph,
        icon: Icons.hub_rounded,
        builder: (context, collection) =>
            RepositoryGraphView(collection: collection),
      ),
      CollectionViewDefinition(
        id: RepositoryViewIds.docs,
        labelKey: LocaleKeys.collections_repository_docs,
        icon: Icons.menu_book_rounded,
        builder: (context, collection) =>
            RepositoryDocsView(collection: collection),
      ),
    ];
