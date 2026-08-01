import 'dart:async';

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_controller.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:flutter/material.dart';

/// The key a repository's settings and reading position are stored under,
/// shared by every repository view so they never disagree.
const repositoryStateKey = 'repository';

/// How deep the walker follows nested folders before it stops.
const _maxRepoDepth = 12;

/// Loads a repository's tree once and hands it to whichever view is showing.
class RepositoryHost extends StatefulWidget {
  const RepositoryHost({
    super.key,
    required this.collection,
    required this.builder,
    this.readsSource = false,
  });

  final CollectionViewContext collection;
  final Widget Function(
    BuildContext context,
    RepositoryController controller,
    CollectionPalette palette,
  ) builder;

  /// Whether the view needs every file read up front, which the symbol
  /// explorer and the dependency graph do and a file listing does not.
  final bool readsSource;

  @override
  State<RepositoryHost> createState() => _RepositoryHostState();
}

class _RepositoryHostState extends State<RepositoryHost> {
  late final RepositoryController controller;
  bool walking = false;
  bool walkQueued = false;

  @override
  void initState() {
    super.initState();
    controller = RepositoryController(
      initialState: widget.collection.stateFor(repositoryStateKey),
      onPersist: (state) =>
          widget.collection.onStateChanged(repositoryStateKey, state),
    );
    widget.collection.explorer.addListener(_onExplorerChanged);
    controller.addListener(_onChanged);
    unawaited(_walk());
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_onExplorerChanged);
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _onExplorerChanged() => unawaited(_walk());

  /// Loads every folder in the repository, then flattens it.
  ///
  /// A collection only ever has its own children loaded, so the nested
  /// folders a project is made of have to be asked for one level at a time.
  Future<void> _walk() async {
    if (walking) {
      walkQueued = true;
      return;
    }
    walking = true;
    try {
      do {
        walkQueued = false;
        final explorer = widget.collection.explorer;
        final rootId = widget.collection.collectionView.id;
        var frontier = <String>[rootId];
        var depth = 0;
        while (frontier.isNotEmpty && depth <= _maxRepoDepth) {
          final pending = [
            for (final id in frontier)
              if (!explorer.hasLoaded(id)) id,
          ];
          if (pending.isNotEmpty) {
            await Future.wait(pending.map(explorer.ensureLoaded));
            if (!mounted) {
              return;
            }
          }
          frontier = [
            for (final id in frontier)
              for (final view in explorer.childrenOf(id))
                if (view.isWorkspaceFolder || view.isCollection) view.id,
          ];
          depth += 1;
        }
        if (!mounted) {
          return;
        }
        controller.setEntries(
          buildRepoTree(
            rootId: rootId,
            childrenOf: explorer.childrenOf,
          ),
        );
      } while (walkQueued);
    } finally {
      walking = false;
    }
    if (widget.readsSource && mounted) {
      unawaited(controller.analyseAll());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CollectionPalette.of(context, CollectionKind.repository);
    return widget.builder(context, controller, palette);
  }
}
