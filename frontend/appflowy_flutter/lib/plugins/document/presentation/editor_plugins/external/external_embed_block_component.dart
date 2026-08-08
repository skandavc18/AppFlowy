import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/resizable_media.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart' hide Overlay;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

/// A file, folder or album from a connected service, living on a page.
///
/// It stores only what it takes to find the thing again — the service, the
/// connection and the remote id. The bytes are never copied into the document,
/// so an embed stays in step with the service and a page stays small.
class ExternalEmbedKeys {
  const ExternalEmbedKeys._();

  static const String type = 'external_embed';

  static const String service = 'service';
  static const String connection = 'connection';
  static const String nodeId = 'node_id';
  static const String parentId = 'parent_id';
  static const String name = 'name';
  static const String kind = 'kind';
  static const String webUrl = 'web_url';
  static const String mimeType = 'mime_type';

  /// Whatever else the binding needs to find this again — a Google Photos
  /// picking session, for one, without which the embed can never resolve.
  static const String options = 'options';
  static const String height = 'height';
  static const String width = 'width';
}

Node externalEmbedNode({
  required CollectionSource source,
  required ProviderNode node,
}) =>
    Node(
      type: ExternalEmbedKeys.type,
      attributes: {
        ExternalEmbedKeys.service: source.service.name,
        ExternalEmbedKeys.connection: source.connectionId,
        ExternalEmbedKeys.nodeId: node.id,
        ExternalEmbedKeys.parentId: node.parentId ?? source.remoteId,
        ExternalEmbedKeys.name: node.name,
        ExternalEmbedKeys.kind: node.kind.name,
        if (node.webUrl != null) ExternalEmbedKeys.webUrl: node.webUrl,
        if (node.mimeType != null) ExternalEmbedKeys.mimeType: node.mimeType,
        if (source.options.isNotEmpty)
          ExternalEmbedKeys.options: source.options,
      },
    );

class ExternalEmbedBlockComponentBuilder extends BlockComponentBuilder {
  ExternalEmbedBlockComponentBuilder({super.configuration});

  @override
  BlockComponentWidget build(BlockComponentContext blockComponentContext) {
    final node = blockComponentContext.node;
    return ExternalEmbedBlockComponent(
      key: node.key,
      node: node,
      configuration: configuration,
      showActions: showActions(node),
      actionBuilder: (context, state) => actionBuilder(
        blockComponentContext,
        state,
      ),
    );
  }

  @override
  BlockComponentValidate get validate =>
      (node) => node.attributes[ExternalEmbedKeys.nodeId] is String;
}

class ExternalEmbedBlockComponent extends BlockComponentStatefulWidget {
  const ExternalEmbedBlockComponent({
    super.key,
    required super.node,
    super.showActions,
    super.actionBuilder,
    super.configuration = const BlockComponentConfiguration(),
  });

  @override
  State<ExternalEmbedBlockComponent> createState() =>
      _ExternalEmbedBlockComponentState();
}

class _ExternalEmbedBlockComponentState
    extends State<ExternalEmbedBlockComponent> with BlockComponentConfigurable {
  @override
  Node get node => widget.node;

  @override
  BlockComponentConfiguration get configuration => widget.configuration;

  late final EditorState editorState = context.read<EditorState>();
  ProviderController? controller;
  ProviderNode? remote;
  String? path;
  bool loading = true;
  ProviderStatus status = ProviderStatus.loading;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  CollectionSource get _source => CollectionSource(
        service: ProviderService.fromValue(
          node.attributes[ExternalEmbedKeys.service],
        ),
        connectionId: _string(node.attributes[ExternalEmbedKeys.connection]),
        remoteId: _string(node.attributes[ExternalEmbedKeys.parentId]),
        remoteName: _string(node.attributes[ExternalEmbedKeys.name]),
        options: switch (node.attributes[ExternalEmbedKeys.options]) {
          final Map<String, dynamic> stored => stored,
          final Map stored => Map<String, dynamic>.from(stored),
          _ => const <String, dynamic>{},
        },
      );

  Future<void> _load() async {
    final source = _source;
    final id = _string(node.attributes[ExternalEmbedKeys.nodeId]);
    final kind = ProviderNodeKind.values.firstWhere(
      (value) => value.name == node.attributes[ExternalEmbedKeys.kind],
      orElse: () => ProviderNodeKind.other,
    );

    final created = ProviderController(
      collectionId: 'embed-${node.id}',
      source: source,
      // A page embed does not poll: it is read when the page is opened and
      // refreshed when somebody asks, which is what keeps a document with
      // twenty embeds from becoming twenty timers.
      autoRefresh: Duration.zero,
    );
    // Refreshing builds a new model, so the previous one has to let its
    // connection go rather than be left open behind it.
    controller?.dispose();
    controller = created;
    if (!loading) {
      setState(() {
        loading = true;
        status = ProviderStatus.loading;
      });
    }

    try {
      await created.refresh();
      final found = created.nodeById(id);
      final resolved = found ??
          ProviderNode(
            id: id,
            name: _string(node.attributes[ExternalEmbedKeys.name]),
            kind: kind,
            mimeType:
                _stringOrNull(node.attributes[ExternalEmbedKeys.mimeType]),
            webUrl: _stringOrNull(node.attributes[ExternalEmbedKeys.webUrl]),
          );
      remote = resolved;

      if (resolved.isFolder) {
        await created.ensureLoaded(resolved.id);
        if (mounted) {
          setState(() {
            loading = false;
            status = created.status;
          });
        }
        return;
      }

      final file = await created.materialize(resolved);
      if (found != null) {
        unawaited(_rememberResolved(found));
      }
      if (mounted) {
        setState(() {
          path = file;
          loading = false;
          // The model usually knows more than "it did not work": a lapsed
          // Google Photos selection is `notFound`, a withdrawn grant is
          // `authExpired`, and each of those has its own way out.
          status = file != null
              ? ProviderStatus.ready
              : created.status.isFailure
                  ? created.status
                  : ProviderStatus.error;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          status = ProviderStatus.error;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final info = ProviderServices.of(_source.service);
    final storedWidth = node.attributes[ExternalEmbedKeys.width];

    Widget child = ResizableMedia(
      width: storedWidth is num ? storedWidth.toDouble() : double.infinity,
      height: _height,
      minHeight: 160,
      maxHeight: 900,
      alignment: Alignment.centerLeft,
      editable: editorState.editable,
      onResize: (value) => _persistSize(ExternalEmbedKeys.width, value),
      onResizeHeight: (value) => _persistSize(ExternalEmbedKeys.height, value),
      child: Container(
        decoration: BoxDecoration(
          color: palette.surface,
          borderRadius: EditorSurfaceStyle.embedBorderRadius,
          boxShadow: EditorSurfaceStyle.embedShadow(context),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(palette, info),
            Expanded(child: _body(palette)),
          ],
        ),
      ),
    );

    child = Padding(padding: padding, child: child);

    if (widget.showActions && widget.actionBuilder != null) {
      child = BlockComponentActionWrapper(
        node: node,
        actionBuilder: widget.actionBuilder!,
        child: child,
      );
    }
    return child;
  }

  Future<void> _persistSize(String key, double value) async {
    final transaction = editorState.transaction
      ..updateNode(node, {key: value.roundToDouble()});
    await editorState.apply(transaction);
  }

  /// Writes back what the service says this object is now.
  ///
  /// The cached copy is filed under the object's name, so a name that drifts
  /// leaves the copy invisible the next time the service cannot be reached —
  /// which is exactly when it is needed.
  Future<void> _rememberResolved(ProviderNode resolved) async {
    final changes = <String, dynamic>{};
    if (resolved.name.isNotEmpty &&
        resolved.name !=
            _stringOrNull(node.attributes[ExternalEmbedKeys.name])) {
      changes[ExternalEmbedKeys.name] = resolved.name;
    }
    final mime = resolved.mimeType;
    if (mime != null &&
        mime != _stringOrNull(node.attributes[ExternalEmbedKeys.mimeType])) {
      changes[ExternalEmbedKeys.mimeType] = mime;
    }
    // A block that has been deleted has no path left to update.
    if (changes.isEmpty ||
        !mounted ||
        !editorState.editable ||
        node.parent == null) {
      return;
    }
    await editorState.apply(editorState.transaction..updateNode(node, changes));
  }

  double get _height {
    final stored = node.attributes[ExternalEmbedKeys.height];
    if (stored is num) {
      return stored.toDouble().clamp(160, 900);
    }
    final kind = remote?.kind;
    if (kind != null && kind.isContainer) {
      return 340;
    }
    final previewKind = filePreviewKindFromName(
      _string(node.attributes[ExternalEmbedKeys.name]),
    );
    return previewKind == null ? 420 : defaultFilePreviewHeight(previewKind);
  }

  Widget _header(FolderExplorerPalette palette, ProviderServiceInfo info) =>
      Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(info.icon, size: 14, color: info.accent),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _string(node.attributes[ExternalEmbedKeys.name], 'Untitled'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 12.5,
                  fontVariations: const [FontVariation.weight(570)],
                ),
              ),
            ),
            Text(
              info.label,
              style: TextStyle(color: palette.textMuted, fontSize: 11),
            ),
            const SizedBox(width: 6),
            IconButton(
              tooltip: LocaleKeys.providers_sync.tr(),
              onPressed: () => unawaited(_load()),
              icon: const Icon(Icons.refresh_rounded, size: 14),
              color: palette.textMuted,
              splashRadius: 13,
              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
              padding: EdgeInsets.zero,
            ),
            if (_stringOrNull(node.attributes[ExternalEmbedKeys.webUrl]) !=
                null)
              IconButton(
                tooltip: LocaleKeys.providers_openInSource.tr(),
                onPressed: () => unawaited(
                  launchUrl(
                    Uri.parse(
                      _string(node.attributes[ExternalEmbedKeys.webUrl]),
                    ),
                    mode: LaunchMode.externalApplication,
                  ),
                ),
                icon: const Icon(Icons.open_in_new_rounded, size: 14),
                color: palette.textMuted,
                splashRadius: 13,
                constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                padding: EdgeInsets.zero,
              ),
          ],
        ),
      );

  Widget _body(FolderExplorerPalette palette) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final live = controller;
    final node = remote;
    if (live == null || node == null || status.isFailure) {
      return _failure(live);
    }

    if (node.isFolder) {
      // A folder or album embed is the same wall the collection shows, so an
      // album on a page and an album collection are the same thing.
      return ListenableBuilder(
        listenable: live,
        builder: (context, _) => ExternalContentView(
          controller: live,
          palette: CollectionPalette.of(context, CollectionKind.folder),
          layout: node.kind == ProviderNodeKind.album
              ? ExternalLayout.thumbnail
              : ExternalLayout.list,
          parentId: node.id,
        ),
      );
    }

    // Only a file has bytes to wait for; a folder never has a path.
    final file = path;
    if (file == null) {
      return _failure(live);
    }
    return externalFileRenderer(node: node, path: file, palette: palette);
  }

  /// Says which of the several reasons this is, and offers the way out.
  Widget _failure(ProviderController? live) {
    final info = ProviderServices.of(_source.service);
    return ProviderStateView(
      status: status.isFailure ? status : ProviderStatus.error,
      info: info,
      palette: CollectionPalette.of(context, CollectionKind.folder),
      retryAfter: live?.failure?.retryAfter,
      onRetry: () => unawaited(_load()),
      onReconnect: info.needsBrowser ? () => unawaited(_reconnect()) : null,
    );
  }

  Future<void> _reconnect() async {
    final signedIn = await reconnectProviderAccount(
      context,
      info: ProviderServices.of(_source.service),
    );
    if (signedIn && mounted) {
      await _load();
    }
  }

  static String _string(Object? value, [String fallback = '']) =>
      value is String && value.isNotEmpty ? value : fallback;

  static String? _stringOrNull(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
