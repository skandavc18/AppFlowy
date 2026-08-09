import 'dart:async';

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_metadata.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
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
  ProviderController? provider;

  CollectionSource get source => widget.collection.collectionView.source;

  @override
  void initState() {
    super.initState();
    controller = AlbumController(
      initialState: widget.collection.stateFor(albumStateKey),
      onPersist: (state) =>
          widget.collection.onStateChanged(albumStateKey, state),
    );
    controller.addListener(_onChanged);

    if (source.isRemote) {
      _bindProvider();
      return;
    }
    widget.collection.explorer.addListener(_syncItems);
    _syncItems();
    unawaited(
      widget.collection.explorer
          .ensureLoaded(widget.collection.collectionView.id),
    );
    if (widget.needsDates) {
      unawaited(controller.ensureAllMetadata());
    }
  }

  @override
  void didUpdateWidget(AlbumHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.collection.collectionView.source;
    if (previous.cacheKey != source.cacheKey) {
      provider?.removeListener(_syncProviderItems);
      provider?.dispose();
      provider = null;
      if (source.isRemote) {
        _bindProvider();
      }
    }
  }

  @override
  void dispose() {
    widget.collection.explorer.removeListener(_syncItems);
    provider?.removeListener(_syncProviderItems);
    provider?.dispose();
    controller.removeListener(_onChanged);
    controller.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  /// A hosted album feeds the same views as a workspace one.
  ///
  /// The provider's own listing already carries every shape, date and
  /// coordinate the wall, the timeline and the places plot read, so nothing
  /// here is a second album implementation — only a second source of items.
  void _bindProvider() {
    unawaited(
      ProviderConnections.instance.ensureLoaded().then((_) {
        if (!mounted || !source.isRemote) {
          return;
        }
        final created = ProviderController(
          collectionId: widget.collection.collectionView.id,
          source: source,
        );
        provider = created;
        created.addListener(_syncProviderItems);
        setState(() {});
        unawaited(created.load());
      }),
    );
  }

  void _syncProviderItems() {
    final live = provider;
    if (!mounted || live == null) {
      return;
    }
    final items = live.itemsFor(null);
    for (final item in items) {
      controller.metadata.seed(item.id, albumMetadataOfProviderNode(item.node));
    }
    controller.setItems(albumMediaFromProvider(items));
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
    final live = provider;
    if (source.isRemote &&
        (live == null || (live.isBusy && live.nodes.isEmpty))) {
      return ProviderStateView(
        status: live?.status ?? ProviderStatus.loading,
        info: source.info,
        palette: palette,
      );
    }
    if (live != null && live.hasFailed && live.nodes.isEmpty) {
      return ProviderStateView(
        status: live.status,
        info: source.info,
        palette: palette,
        onRetry: () => unawaited(live.refresh()),
      );
    }
    return widget.builder(context, controller, palette);
  }
}
