import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/provider_text_field.dart';
import 'package:appflowy/shared/viewer_card.dart';
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

/// What was chosen out of a service, ready to be embedded.
@immutable
class ExternalPick {
  const ExternalPick({required this.source, required this.node});

  final CollectionSource source;
  final ProviderNode node;
}

/// Picks one file, folder or album out of a connected service.
///
/// The same browser the collection binder uses, except it lists files as well
/// as containers, because a page embeds a thing rather than a place.
Future<ExternalPick?> showExternalPicker(
  BuildContext context, {
  required ProviderServiceInfo info,
  bool containersOnly = false,
}) =>
    showDialog<ExternalPick>(
      context: context,
      builder: (context) =>
          _ExternalPicker(info: info, containersOnly: containersOnly),
    );

class _ExternalPicker extends StatefulWidget {
  const _ExternalPicker({required this.info, required this.containersOnly});

  final ProviderServiceInfo info;
  final bool containersOnly;

  @override
  State<_ExternalPicker> createState() => _ExternalPickerState();
}

class _ExternalPickerState extends State<_ExternalPicker> {
  ProviderConnection? connection;
  CollectionProvider? provider;

  List<ProviderNode> nodes = const <ProviderNode>[];
  final List<ProviderNode> trail = <ProviderNode>[];
  bool loading = true;
  String? error;
  String query = '';

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  @override
  void dispose() {
    provider?.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    await ProviderConnections.instance.ensureLoaded();
    final accounts =
        ProviderConnections.instance.forService(widget.info.service);
    if (!mounted) {
      return;
    }
    if (accounts.isEmpty) {
      setState(() {
        loading = false;
        error = LocaleKeys.providers_embed_notConnected
            .tr(args: [widget.info.label]);
      });
      return;
    }
    connection = accounts.first;
    await _read(null);
  }

  Future<void> _read(String? parentId) async {
    setState(() {
      loading = true;
      error = null;
    });

    final account = connection;
    if (account == null) {
      return;
    }
    try {
      provider ??= ProviderRegistry.create(
        CollectionSource(service: account.service, connectionId: account.id),
      );
      final live = provider;
      if (live == null) {
        throw const ProviderFailure(ProviderStatus.error);
      }
      await live.ensureReady();
      final page = await live.list(parentId: parentId);
      if (mounted) {
        setState(() {
          nodes = page.nodes;
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
              LocaleKeys.providers_error_refused.tr(args: [widget.info.label]),
            _ =>
              LocaleKeys.providers_error_generic.tr(args: [widget.info.label]),
          };
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    final needle = query.trim().toLowerCase();
    final visible = [
      for (final node in nodes)
        if ((needle.isEmpty || node.name.toLowerCase().contains(needle)) &&
            (!widget.containersOnly || node.isFolder))
          node,
    ];

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
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 10, 10),
                child: Row(
                  children: [
                    if (trail.isNotEmpty)
                      IconButton(
                        onPressed: _goUp,
                        icon: const Icon(Icons.arrow_back_rounded, size: 17),
                        color: palette.textSecondary,
                        splashRadius: 15,
                      ),
                    Expanded(
                      child: Text(
                        trail.isEmpty
                            ? LocaleKeys.providers_embed_pick
                                .tr(args: [widget.info.label])
                            : trail.last.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontSize: 15,
                          fontVariations: const [FontVariation.weight(620)],
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.close_rounded, size: 17),
                      color: palette.textSecondary,
                      splashRadius: 15,
                    ),
                  ],
                ),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 6, 20, 20),
                  child: Column(
                    children: [
                      Text(
                        error!,
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(color: palette.textMuted, fontSize: 12.5),
                      ),
                      const SizedBox(height: 12),
                      FilledButton.tonal(
                        onPressed: () async {
                          await showProviderConnectDialog(
                            context,
                            info: widget.info,
                          );
                          if (mounted) {
                            await _start();
                          }
                        },
                        child: Text(
                          LocaleKeys.providers_connectTo
                              .tr(args: [widget.info.label]),
                        ),
                      ),
                    ],
                  ),
                )
              else if (loading)
                const SizedBox(
                  height: 200,
                  child: Center(
                    child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                )
              else ...[
                Padding(
                  padding: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                  child: TextEntryShortcuts(
                    child: TextField(
                      autofocus: true,
                      onChanged: (value) => setState(() => query = value),
                      style:
                          TextStyle(color: palette.textPrimary, fontSize: 13),
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: LocaleKeys.providers_filter.tr(),
                        hintStyle:
                            TextStyle(color: palette.textMuted, fontSize: 13),
                        filled: true,
                        fillColor: palette.background,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 10,
                        ),
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
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                ),
                Flexible(
                  child: visible.isEmpty
                      ? SizedBox(
                          height: 160,
                          child: Center(
                            child: Text(
                              LocaleKeys.providers_nothingHere.tr(),
                              style: TextStyle(
                                color: palette.textMuted,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        )
                      : ListView.builder(
                          shrinkWrap: true,
                          padding: const EdgeInsets.fromLTRB(10, 0, 10, 6),
                          itemCount: visible.length,
                          itemBuilder: (context, index) => _PickerRow(
                            node: visible[index],
                            palette: palette,
                            accent: widget.info.accent,
                            onTap: () => _choose(visible[index]),
                            onOpen: visible[index].isFolder
                                ? () => _descend(visible[index])
                                : null,
                          ),
                        ),
                ),
                if (!widget.containersOnly)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 14),
                    child: Text(
                      LocaleKeys.providers_embed_pickHint.tr(),
                      style: TextStyle(
                        color: palette.textMuted,
                        fontSize: 11,
                        height: 1.45,
                      ),
                    ),
                  ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _choose(ProviderNode node) {
    final account = connection;
    if (account == null) {
      return;
    }
    Navigator.of(context).pop(
      ExternalPick(
        source: CollectionSource(
          service: account.service,
          connectionId: account.id,
          remoteId: node.isFolder ? node.id : (node.parentId ?? ''),
          remoteName: node.name,
        ),
        node: node,
      ),
    );
  }

  Future<void> _descend(ProviderNode node) async {
    setState(() {
      trail.add(node);
      query = '';
    });
    await _read(node.id);
  }

  void _goUp() {
    if (trail.isEmpty) {
      return;
    }
    final next = trail.sublist(0, trail.length - 1);
    setState(() {
      trail
        ..clear()
        ..addAll(next);
    });
    unawaited(_read(next.isEmpty ? null : next.last.id));
  }
}

class _PickerRow extends StatefulWidget {
  const _PickerRow({
    required this.node,
    required this.palette,
    required this.accent,
    required this.onTap,
    this.onOpen,
  });

  final ProviderNode node;
  final FolderExplorerPalette palette;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onOpen;

  @override
  State<_PickerRow> createState() => _PickerRowState();
}

class _PickerRowState extends State<_PickerRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final node = widget.node;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          padding: const EdgeInsets.fromLTRB(10, 8, 6, 8),
          decoration: BoxDecoration(
            color: palette.hover.withValues(alpha: hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              Icon(
                providerNodeGlyph(node),
                size: 16,
                color: node.isFolder ? widget.accent : palette.textMuted,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  node.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: palette.textPrimary, fontSize: 13),
                ),
              ),
              if (widget.onOpen != null)
                IconButton(
                  tooltip: LocaleKeys.providers_openFolder.tr(),
                  onPressed: widget.onOpen,
                  icon: const Icon(Icons.chevron_right_rounded, size: 17),
                  color: palette.textMuted,
                  splashRadius: 14,
                  constraints:
                      const BoxConstraints(minWidth: 26, minHeight: 26),
                  padding: EdgeInsets.zero,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
