import 'dart:async';

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// The key an album's settings, stars and selection are stored under, shared
/// by every album view so they never disagree.
const albumStateKey = 'album';

/// Loads an album's media once and hands it to whichever view is showing.
///
/// Every album view needs the same three things — the controller, the palette
/// and media kept in step with the workspace — so the plumbing lives here
/// rather than in six places.
class AlbumHost extends StatefulWidget {
  const AlbumHost({
    super.key,
    required this.collection,
    required this.builder,
    this.needsDates = true,
  });

  final CollectionViewContext collection;
  final Widget Function(
    BuildContext context,
    AlbumController controller,
    CollectionPalette palette,
  ) builder;

  /// Whether the view sorts or groups by capture date, which means every
  /// header has to be read before the order settles.
  final bool needsDates;

  @override
  State<AlbumHost> createState() => _AlbumHostState();
}

class _AlbumHostState extends State<AlbumHost> {
  late final AlbumController controller;

  @override
  void initState() {
    super.initState();
    controller = AlbumController(
      initialState: widget.collection.stateFor(albumStateKey),
      onPersist: (state) =>
          widget.collection.onStateChanged(albumStateKey, state),
    );
    widget.collection.explorer.addListener(_syncItems);
    _syncItems();
    controller.addListener(_onChanged);
    unawaited(
      widget.collection.explorer
          .ensureLoaded(widget.collection.collectionView.id),
    );
    if (widget.needsDates) {
      unawaited(controller.ensureAllMetadata());
    }
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_syncItems);
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  void _syncItems() {
    final children = widget.collection.explorer
        .childrenOf(widget.collection.collectionView.id);
    final before = controller.items.length;
    controller.setItems(albumMediaFrom(children));
    if (widget.needsDates && controller.items.length != before) {
      unawaited(controller.ensureAllMetadata());
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = CollectionPalette.of(context, CollectionKind.album);
    return widget.builder(context, controller, palette);
  }
}
