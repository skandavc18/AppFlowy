import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/external_file_stage.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
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
  static const String height = 'height';
  static const String width = 'width';
}

Node externalEmbedNode({
  required ProviderService service,
  required String connectionId,
  required ProviderNode node,
}) =>
    Node(
      type: ExternalEmbedKeys.type,
      attributes: {
        ExternalEmbedKeys.service: service.name,
        ExternalEmbedKeys.connection: connectionId,
        ExternalEmbedKeys.nodeId: node.id,
        if (node.parentId != null) ExternalEmbedKeys.parentId: node.parentId,
        ExternalEmbedKeys.name: node.name,
        ExternalEmbedKeys.kind: node.kind.name,
        if (node.webUrl != null) ExternalEmbedKeys.webUrl: node.webUrl,
        if (node.mimeType != null) ExternalEmbedKeys.mimeType: node.mimeType,
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
    controller = created;

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
      if (mounted) {
        setState(() {
          path = file;
          loading = false;
          status = file == null ? ProviderStatus.error : ProviderStatus.ready;
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

    Widget child = Container(
      constraints: const BoxConstraints(minHeight: 120),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: EditorSurfaceStyle.embedBorderRadius,
        boxShadow: EditorSurfaceStyle.embedShadow(context),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(palette, info),
          SizedBox(
            height: _height,
            child: _body(palette),
          ),
        ],
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
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Text(
            LocaleKeys.providers_cannotOpen.tr(),
            textAlign: TextAlign.center,
            style: TextStyle(color: palette.textMuted, fontSize: 12.5),
          ),
        ),
      );
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

    final file = path;
    if (file == null) {
      return Center(
        child: Text(
          LocaleKeys.providers_cannotOpen.tr(),
          style: TextStyle(color: palette.textMuted, fontSize: 12.5),
        ),
      );
    }
    return externalFileRenderer(node: node, path: file, palette: palette);
  }

  static String _string(Object? value, [String fallback = '']) =>
      value is String && value.isNotEmpty ? value : fallback;

  static String? _stringOrNull(Object? value) =>
      value is String && value.isNotEmpty ? value : null;
}
