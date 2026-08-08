import 'dart:async';

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:flutter/material.dart';

/// Hosts the one [ProviderController] a collection's views share.
///
/// It plays the same part [AlbumHost] and [RepositoryHost] play for local
/// collections: one model, created once, so switching between the wall, the
/// list and the tree never re-reads the service.
///
/// A local collection is handed straight through — [builder] is called with a
/// null controller and the view falls back to the workspace explorer. That is
/// what keeps a single view file serving both.
class ExternalCollectionHost extends StatefulWidget {
  const ExternalCollectionHost({
    super.key,
    required this.collection,
    required this.builder,
    this.stateKey = 'provider',
  });

  final CollectionViewContext collection;

  /// [controller] is null when the collection lives in the workspace.
  final Widget Function(
    BuildContext context,
    ProviderController? controller,
    CollectionPalette palette,
  ) builder;

  final String stateKey;

  @override
  State<ExternalCollectionHost> createState() => _ExternalCollectionHostState();
}

class _ExternalCollectionHostState extends State<ExternalCollectionHost> {
  ProviderController? controller;

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(ExternalCollectionHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = oldWidget.collection.collectionView.source;
    final next = widget.collection.collectionView.source;
    // Rebinding a collection to a different album, repository or account has
    // to throw the model away; anything less shows the old contents under the
    // new name.
    if (previous.cacheKey != next.cacheKey) {
      controller?.dispose();
      controller = null;
      _bind();
    }
  }

  void _bind() {
    final source = widget.collection.collectionView.source;
    if (source.isLocal) {
      return;
    }

    // The connection list has to be readable before a provider can be built,
    // and it is loaded lazily so that a workspace with no connections costs
    // nothing at startup.
    unawaited(
      ProviderConnections.instance.ensureLoaded().then((_) {
        if (!mounted) {
          return;
        }
        final created = ProviderController(
          collectionId: widget.collection.collectionView.id,
          source: source,
        );
        setState(() => controller = created);
        unawaited(created.load());
      }),
    );
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CollectionPalette.of(context, widget.collection.kind);
    final source = widget.collection.collectionView.source;
    final live = controller;

    if (source.isLocal) {
      return widget.builder(context, null, palette);
    }

    if (live == null) {
      return ProviderStateView(
        status: ProviderStatus.loading,
        info: source.info,
        palette: palette,
      );
    }

    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        // Nothing read yet and something went wrong: the whole panel says so.
        if (live.hasFailed && live.nodes.isEmpty) {
          return ProviderStateView(
            status: live.status,
            info: source.info,
            palette: palette,
            retryAfter: live.failure?.retryAfter,
            onRetry: () => unawaited(live.refresh()),
            onReconnect: () => _reconnect(context),
          );
        }

        if (live.status == ProviderStatus.loading && live.nodes.isEmpty) {
          return ProviderStateView(
            status: ProviderStatus.loading,
            info: source.info,
            palette: palette,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Content already on screen keeps its place; a failed refresh is a
            // strip above it, never a replacement for it.
            if (live.hasFailed)
              ProviderStaleBanner(
                status: live.status,
                info: source.info,
                palette: palette,
                onRetry: () => unawaited(live.refresh(silent: true)),
                onReconnect: () => _reconnect(context),
              ),
            Expanded(child: widget.builder(context, live, palette)),
          ],
        );
      },
    );
  }

  void _reconnect(BuildContext context) {
    // Reconnecting is a settings job: the connection is shared by every
    // collection that uses it, so it is mended in one place.
    ProviderReconnectRequest.of(context)?.call(
      widget.collection.collectionView.source,
    );
  }
}

/// Lets a collection ask whoever is above it to open the reconnect flow,
/// without the collection having to know what that flow is.
class ProviderReconnectRequest extends InheritedWidget {
  const ProviderReconnectRequest({
    super.key,
    required this.onReconnect,
    required super.child,
  });

  final void Function(CollectionSource source) onReconnect;

  static void Function(CollectionSource source)? of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ProviderReconnectRequest>()
          ?.onReconnect;

  @override
  bool updateShouldNotify(ProviderReconnectRequest oldWidget) =>
      onReconnect != oldWidget.onReconnect;
}
