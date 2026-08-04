import 'dart:async';

import 'package:appflowy/plugins/collection/views/database/database_chrome.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/database/database_collection_controller.dart';
import 'package:flutter/material.dart';

/// The key a collection's open table and pane layout are stored under, shared
/// by every database view so they never disagree.
const databaseStateKey = 'database';

/// Loads a database collection once and hands it to whichever view is showing.
class DatabaseHost extends StatefulWidget {
  const DatabaseHost({
    super.key,
    required this.collection,
    required this.builder,
  });

  final CollectionViewContext collection;
  final Widget Function(
    BuildContext context,
    DatabaseCollectionController controller,
    DatabaseTheme theme,
  ) builder;

  @override
  State<DatabaseHost> createState() => _DatabaseHostState();
}

class _DatabaseHostState extends State<DatabaseHost> {
  late final DatabaseCollectionController controller;

  @override
  void initState() {
    super.initState();
    controller = DatabaseCollectionController(
      initialState: widget.collection.stateFor(databaseStateKey),
      onPersist: (state) =>
          widget.collection.onStateChanged(databaseStateKey, state),
    );
    // Register the explorer listener and take the first pass before the
    // controller's own listener, or setState runs during initState.
    widget.collection.explorer.addListener(_syncTables);
    _syncTables();
    controller.addListener(_onChanged);
    unawaited(
      widget.collection.explorer
          .ensureLoaded(widget.collection.collectionView.id),
    );
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_syncTables);
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncTables() {
    controller.setViews(
      widget.collection.explorer
          .childrenOf(widget.collection.collectionView.id),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        controller,
        databaseThemeOf(context),
      );
}
