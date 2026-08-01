import 'dart:async';

import 'package:appflowy/plugins/collection/views/bookmark/bookmark_chrome.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_controller.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// The key a library's settings, filters and reading position are stored
/// under, shared by every bookmark view so they never disagree.
const bookmarkStateKey = 'bookmark';

/// Loads a bookmark library once and hands it to whichever view is showing.
class BookmarkHost extends StatefulWidget {
  const BookmarkHost({
    super.key,
    required this.collection,
    required this.builder,
  });

  final CollectionViewContext collection;
  final Widget Function(
    BuildContext context,
    BookmarkController controller,
    BookmarkTheme theme,
  ) builder;

  @override
  State<BookmarkHost> createState() => _BookmarkHostState();
}

class _BookmarkHostState extends State<BookmarkHost> {
  late final BookmarkController controller;

  @override
  void initState() {
    super.initState();
    controller = BookmarkController(
      initialState: widget.collection.stateFor(bookmarkStateKey),
      onPersist: (state) =>
          widget.collection.onStateChanged(bookmarkStateKey, state),
    );
    // Register the explorer listener and take the first pass before the
    // controller's own listener, or setState runs during initState.
    widget.collection.explorer.addListener(_syncEntries);
    _syncEntries();
    controller.addListener(_onChanged);
    unawaited(_load());
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_syncEntries);
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await widget.collection.explorer
        .ensureLoaded(widget.collection.collectionView.id);
    if (mounted) {
      // A link saved without ever being read has no title; read those once so
      // the library fills itself in rather than showing a wall of addresses.
      unawaited(controller.refreshMissing());
    }
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncEntries() {
    controller.setViews(
      widget.collection.explorer
          .childrenOf(widget.collection.collectionView.id),
    );
  }

  @override
  Widget build(BuildContext context) => widget.builder(
        context,
        controller,
        bookmarkThemeOf(context),
      );
}
