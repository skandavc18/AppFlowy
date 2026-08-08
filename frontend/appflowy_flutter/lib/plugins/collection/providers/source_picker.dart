import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/google_photos_picker.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/folder_explorer_style.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Chooses what a collection is backed by.
///
/// Two steps, always in the same order: which service, then which album,
/// repository or folder inside it. The workspace itself is the first option
/// and the default, because a collection that holds the workspace's own files
/// is still the common case.
Future<CollectionSource?> showCollectionSourcePicker(
  BuildContext context, {
  required CollectionKind kind,
  CollectionSource? current,
}) =>
    showDialog<CollectionSource>(
      context: context,
      builder: (context) => _SourcePicker(kind: kind, current: current),
    );

class _SourcePicker extends StatefulWidget {
  const _SourcePicker({required this.kind, this.current});

  final CollectionKind kind;
  final CollectionSource? current;

  @override
  State<_SourcePicker> createState() => _SourcePickerState();
}

class _SourcePickerState extends State<_SourcePicker> {
  ProviderConnection? connection;
  ProviderServiceInfo? service;

  List<ProviderNode> containers = const <ProviderNode>[];
  List<ProviderNode> breadcrumbs = const <ProviderNode>[];
  bool loading = false;
  String? error;
  String query = '';

  @override
  void initState() {
    super.initState();
    unawaited(
      ProviderConnections.instance.ensureLoaded().then((_) {
        if (mounted) {
          setState(() {});
        }
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 560),
        child: ViewerCard(
          color: palette.floatingSurface,
          reactsToPointer: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _header(palette),
              Flexible(
                child: connection == null
                    ? _services(palette)
                    : _containersList(palette),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _header(FolderExplorerPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(20, 18, 14, 14),
        child: Row(
          children: [
            if (connection != null)
              _IconButton(
                icon: Icons.arrow_back_rounded,
                palette: palette,
                tooltip: LocaleKeys.providers_back.tr(),
                onPressed: _goBack,
              ),
            if (connection != null) const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    connection == null
                        ? LocaleKeys.providers_chooseSource.tr()
                        : LocaleKeys.providers_chooseItem
                            .tr(args: [_itemNoun()]),
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 15.5,
                      fontVariations: const [FontVariation.weight(640)],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    connection == null
                        ? LocaleKeys.providers_chooseSourceBody.tr()
                        : connection!.accountLabel,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.textMuted, fontSize: 12),
                  ),
                ],
              ),
            ),
            _IconButton(
              icon: Icons.close_rounded,
              palette: palette,
              tooltip: LocaleKeys.button_cancel.tr(),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ],
        ),
      );

  String _itemNoun() => switch (widget.kind) {
        CollectionKind.album => LocaleKeys.providers_noun_album.tr(),
        CollectionKind.repository => LocaleKeys.providers_noun_repository.tr(),
        _ => LocaleKeys.providers_noun_folder.tr(),
      };

  Widget _services(FolderExplorerPalette palette) {
    final connections = ProviderConnections.instance;
    final services = ProviderServices.forKind(widget.kind);

    return ListView(
      shrinkWrap: true,
      padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
      children: [
        for (final info in services)
          if (info.service.isLocal)
            _Row(
              palette: palette,
              icon: info.icon,
              accent: info.accent,
              title: LocaleKeys.providers_thisWorkspace.tr(),
              subtitle: LocaleKeys.providers_thisWorkspaceBody.tr(),
              selected: (widget.current ?? CollectionSource.local).isLocal,
              onTap: () => Navigator.of(context).pop(CollectionSource.local),
            )
          else ...[
            for (final account in connections.forService(info.service))
              _Row(
                palette: palette,
                icon: info.icon,
                accent: info.accent,
                title: info.label,
                subtitle: account.accountLabel,
                selected: widget.current?.connectionId == account.id,
                onTap: () => _openConnection(account, info),
              ),
            _Row(
              palette: palette,
              icon: info.icon,
              accent: info.accent,
              title: connections.isConnected(info.service)
                  ? LocaleKeys.providers_addAnotherAccount
                      .tr(args: [info.label])
                  : LocaleKeys.providers_connectTo.tr(args: [info.label]),
              subtitle: _authNote(info),
              muted: true,
              onTap: () => _connect(info),
            ),
          ],
      ],
    );
  }

  String _authNote(ProviderServiceInfo info) => switch (info.authKind) {
        ProviderAuthKind.selfHostedToken =>
          LocaleKeys.providers_connectSelfHosted.tr(),
        ProviderAuthKind.personalToken =>
          LocaleKeys.providers_connectToken.tr(),
        _ => LocaleKeys.providers_connectBrowser.tr(),
      };

  Widget _containersList(FolderExplorerPalette palette) {
    if (loading) {
      return const SizedBox(
        height: 220,
        child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
      );
    }
    if (error != null) {
      return SizedBox(
        height: 220,
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Text(
              error!,
              textAlign: TextAlign.center,
              style: TextStyle(color: palette.textMuted, fontSize: 12.5),
            ),
          ),
        ),
      );
    }

    final needle = query.trim().toLowerCase();
    final visible = needle.isEmpty
        ? containers
        : [
            for (final node in containers)
              if (node.name.toLowerCase().contains(needle)) node,
          ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 10),
          child: TextField(
            autofocus: true,
            onChanged: (value) => setState(() => query = value),
            style: TextStyle(color: palette.textPrimary, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: LocaleKeys.providers_filter.tr(),
              hintStyle: TextStyle(color: palette.textMuted, fontSize: 13),
              prefixIcon: Icon(
                Icons.search_rounded,
                size: 16,
                color: palette.textMuted,
              ),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 34, minHeight: 30),
              filled: true,
              fillColor: palette.background,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(9),
                borderSide: BorderSide(color: palette.border, width: 1.2),
              ),
            ),
          ),
        ),
        if (breadcrumbs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
            child: Text(
              breadcrumbs.map((node) => node.name).join(' / '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.textMuted, fontSize: 11.5),
            ),
          ),
        Flexible(
          child: visible.isEmpty
              ? SizedBox(
                  height: 180,
                  child: Center(
                    child: Text(
                      LocaleKeys.providers_nothingHere.tr(),
                      style:
                          TextStyle(color: palette.textMuted, fontSize: 12.5),
                    ),
                  ),
                )
              : ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 10),
                  itemCount: visible.length,
                  itemBuilder: (context, index) {
                    final node = visible[index];
                    return _Row(
                      palette: palette,
                      icon: node.kind == ProviderNodeKind.album
                          ? Icons.photo_album_rounded
                          : Icons.folder_rounded,
                      accent: service?.accent ?? palette.textMuted,
                      title: node.name,
                      subtitle: _describe(node),
                      // A folder can be drilled into; picking it is the
                      // separate "use this" action so nothing is bound by
                      // accident on the way past.
                      trailing: node.kind == ProviderNodeKind.folder &&
                              widget.kind != CollectionKind.repository
                          ? _IconButton(
                              icon: Icons.chevron_right_rounded,
                              palette: palette,
                              tooltip: LocaleKeys.providers_openFolder.tr(),
                              onPressed: () => _descend(node),
                            )
                          : null,
                      onTap: () => _pick(node),
                    );
                  },
                ),
        ),
        if (breadcrumbs.isNotEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 14),
            child: _UseThisFolder(
              palette: palette,
              label: LocaleKeys.providers_useThisFolder
                  .tr(args: [breadcrumbs.last.name]),
              onPressed: () => _pick(breadcrumbs.last),
            ),
          ),
      ],
    );
  }

  String _describe(ProviderNode node) {
    final parts = <String>[
      if (node.childCount != null)
        LocaleKeys.providers_itemCount.tr(args: ['${node.childCount}']),
      if ((node.description ?? '').isNotEmpty) node.description!,
      if (node.extra['private'] == true) LocaleKeys.providers_private.tr(),
    ];
    return parts.join(' · ');
  }

  Future<void> _connect(ProviderServiceInfo info) async {
    final connected = await showProviderConnectDialog(context, info: info);
    if (connected != null && mounted) {
      await _openConnection(connected, info);
    } else if (mounted) {
      setState(() {});
    }
  }

  Future<void> _openConnection(
    ProviderConnection account,
    ProviderServiceInfo info,
  ) async {
    // A service that has no listing of its own — Google Photos — hands the
    // choosing to its own interface and comes back with a binding.
    if (info.picksExternally) {
      final picked = await pickGooglePhotosSelection(
        context,
        connection: account,
      );
      if (picked != null && mounted) {
        Navigator.of(context).pop(picked);
      }
      return;
    }

    setState(() {
      connection = account;
      service = info;
      loading = true;
      error = null;
      containers = const <ProviderNode>[];
      breadcrumbs = const <ProviderNode>[];
      query = '';
    });
    await _read(null);
  }

  Future<void> _read(String? parentId) async {
    final account = connection;
    if (account == null) {
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });

    CollectionProvider? provider;
    try {
      // A provider with no remote id bound yet answers with the account's own
      // top level: its albums, its repositories, its drive root.
      provider = ProviderRegistry.create(
        CollectionSource(
          service: account.service,
          connectionId: account.id,
        ),
      );
      if (provider == null) {
        throw const ProviderFailure(ProviderStatus.error);
      }
      await provider.ensureReady();

      final nodes = switch (provider) {
        final AlbumProvider album when parentId == null => await album.albums(),
        final RepositoryProvider repository when parentId == null =>
          await repository.repositories(),
        final FolderProvider folder => await folder.folders(parentId: parentId),
        _ => await provider.listAll(parentId: parentId),
      };

      if (mounted) {
        setState(() {
          containers = nodes;
          loading = false;
        });
      }
    } on ProviderFailure catch (failure) {
      if (mounted) {
        setState(() {
          loading = false;
          error = switch (failure.status) {
            ProviderStatus.offline =>
              LocaleKeys.providers_error_unreachable.tr(),
            ProviderStatus.authExpired =>
              LocaleKeys.providers_error_refused.tr(args: [account.info.label]),
            ProviderStatus.permissionDenied =>
              LocaleKeys.providers_error_scope.tr(args: [account.info.label]),
            _ =>
              LocaleKeys.providers_error_generic.tr(args: [account.info.label]),
          };
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          loading = false;
          error =
              LocaleKeys.providers_error_generic.tr(args: [account.info.label]);
        });
      }
    } finally {
      provider?.dispose();
    }
  }

  Future<void> _descend(ProviderNode node) async {
    setState(() {
      breadcrumbs = [...breadcrumbs, node];
      query = '';
    });
    await _read(node.id);
  }

  void _goBack() {
    if (breadcrumbs.isEmpty) {
      setState(() {
        connection = null;
        service = null;
        containers = const <ProviderNode>[];
        error = null;
      });
      return;
    }
    final trimmed = breadcrumbs.sublist(0, breadcrumbs.length - 1);
    setState(() => breadcrumbs = trimmed);
    unawaited(_read(trimmed.isEmpty ? null : trimmed.last.id));
  }

  void _pick(ProviderNode node) {
    final account = connection;
    if (account == null) {
      return;
    }
    Navigator.of(context).pop(
      CollectionSource(
        service: account.service,
        connectionId: account.id,
        remoteId: node.id,
        remoteName: node.name,
        remoteUrl: node.webUrl ?? '',
        readOnly: node.readOnly,
        lastSyncedAt: DateTime.now(),
        options: {
          if (node.extra['default_branch'] is String &&
              (node.extra['default_branch'] as String).isNotEmpty)
            'branch': node.extra['default_branch'],
        },
      ),
    );
  }
}

class _Row extends StatefulWidget {
  const _Row({
    required this.palette,
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
    required this.onTap,
    this.trailing,
    this.selected = false,
    this.muted = false,
  });

  final FolderExplorerPalette palette;
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final Widget? trailing;
  final bool selected;
  final bool muted;

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
          padding: const EdgeInsets.fromLTRB(10, 9, 8, 9),
          decoration: BoxDecoration(
            color: widget.selected
                ? palette.selected
                : palette.hover.withValues(alpha: hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: widget.accent
                      .withValues(alpha: widget.muted ? 0.07 : 0.12),
                  borderRadius: BorderRadius.circular(9),
                ),
                child: Icon(
                  widget.icon,
                  size: 16,
                  color:
                      widget.accent.withValues(alpha: widget.muted ? 0.75 : 1),
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: palette.textPrimary,
                        fontSize: 13,
                        fontVariations: const [FontVariation.weight(570)],
                      ),
                    ),
                    if (widget.subtitle.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        widget.subtitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textMuted,
                          fontSize: 11.5,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (widget.trailing != null) widget.trailing!,
            ],
          ),
        ),
      ),
    );
  }
}

class _IconButton extends StatelessWidget {
  const _IconButton({
    required this.icon,
    required this.palette,
    required this.tooltip,
    required this.onPressed,
  });

  final IconData icon;
  final FolderExplorerPalette palette;
  final String tooltip;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: IconButton(
          onPressed: onPressed,
          icon: Icon(icon, size: 17, color: palette.textSecondary),
          splashRadius: 16,
          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          padding: EdgeInsets.zero,
        ),
      );
}

class _UseThisFolder extends StatelessWidget {
  const _UseThisFolder({
    required this.palette,
    required this.label,
    required this.onPressed,
  });

  final FolderExplorerPalette palette;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.13),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: accent,
              fontSize: 12.5,
              fontVariations: const [FontVariation.weight(580)],
            ),
          ),
        ),
      ),
    );
  }
}
