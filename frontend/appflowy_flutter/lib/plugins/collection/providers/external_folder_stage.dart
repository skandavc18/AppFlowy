import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/provider_chrome.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// A folder that lives in a service, drawn the way this workspace draws its
/// own folders.
///
/// Used by both a Folder collection and a plain workspace folder, so a Google
/// Drive folder reads the same wherever it was connected from. The layout
/// choice rides in the binding's own options, which is why it survives closing
/// the folder without needing a view switcher above it.
class ExternalFolderStage extends StatefulWidget {
  const ExternalFolderStage({
    super.key,
    required this.collectionId,
    required this.source,
    required this.onSourceChanged,
    this.onChangeSource,
    this.onDisconnect,
    this.kind = CollectionKind.folder,
  });

  final String collectionId;
  final CollectionSource source;

  /// Persists a change to the binding — the layout, or a new remote folder.
  final ValueChanged<CollectionSource> onSourceChanged;

  final VoidCallback? onChangeSource;
  final VoidCallback? onDisconnect;
  final CollectionKind kind;

  @override
  State<ExternalFolderStage> createState() => _ExternalFolderStageState();
}

class _ExternalFolderStageState extends State<ExternalFolderStage> {
  ProviderController? controller;

  ExternalLayout get layout {
    final stored = widget.source.option<String>('layout');
    return ExternalLayout.values.firstWhere(
      (value) => value.name == stored,
      orElse: () => ExternalLayout.gallery,
    );
  }

  @override
  void initState() {
    super.initState();
    _bind();
  }

  @override
  void didUpdateWidget(ExternalFolderStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only a different remote folder is worth throwing the model away for; a
    // layout change must not cost a re-read.
    if (oldWidget.source.cacheKey != widget.source.cacheKey) {
      controller?.dispose();
      controller = null;
      _bind();
    }
  }

  void _bind() {
    final created = ProviderController(
      collectionId: widget.collectionId,
      source: widget.source,
    );
    controller = created;
    unawaited(created.load());
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CollectionPalette.of(context, widget.kind);
    final live = controller;
    if (live == null) {
      return const SizedBox.shrink();
    }

    return ListenableBuilder(
      listenable: live,
      builder: (context, _) {
        if (live.hasFailed && live.nodes.isEmpty) {
          return ProviderStateView(
            status: live.status,
            info: widget.source.info,
            palette: palette,
            retryAfter: live.failure?.retryAfter,
            onRetry: () => unawaited(live.refresh()),
            onReconnect: widget.onChangeSource,
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(palette, live),
            if (live.hasFailed)
              ProviderStaleBanner(
                status: live.status,
                info: widget.source.info,
                palette: palette,
                onRetry: () => unawaited(live.refresh(silent: true)),
                onReconnect: widget.onChangeSource,
              ),
            Expanded(
              child: ExternalContentView(
                controller: live,
                palette: palette,
                layout: layout,
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _header(CollectionPalette palette, ProviderController live) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 0, 20, 12),
        child: Row(
          children: [
            ProviderBadge(
              source: widget.source,
              palette: palette,
              detail: live.originLabel,
              onTap: widget.onChangeSource,
            ),
            const Spacer(),
            for (final option in ExternalLayout.values) ...[
              _LayoutButton(
                palette: palette,
                option: option,
                selected: option == layout,
                onTap: () => widget.onSourceChanged(
                  widget.source.withOption('layout', option.name),
                ),
              ),
              const SizedBox(width: 2),
            ],
            const SizedBox(width: 8),
            ProviderSyncStrip(
              palette: palette,
              status: live.status,
              lastSyncedAt: live.lastSyncedAt,
              canSync: live.capabilities.canSync,
              onSync: () => unawaited(live.resync()),
            ),
            if (widget.onChangeSource != null ||
                widget.onDisconnect != null) ...[
              const SizedBox(width: 4),
              PopupMenuButton<int>(
                tooltip: LocaleKeys.providers_changeSource.tr(),
                position: PopupMenuPosition.under,
                onSelected: (value) => value == 0
                    ? widget.onChangeSource?.call()
                    : widget.onDisconnect?.call(),
                itemBuilder: (context) => [
                  if (widget.onChangeSource != null)
                    PopupMenuItem<int>(
                      value: 0,
                      height: 34,
                      child: _MenuRow(
                        icon: Icons.swap_horiz_rounded,
                        label: LocaleKeys.providers_changeSource.tr(),
                      ),
                    ),
                  if (widget.onDisconnect != null)
                    PopupMenuItem<int>(
                      value: 1,
                      height: 34,
                      child: _MenuRow(
                        icon: Icons.link_off_rounded,
                        label: LocaleKeys.providers_disconnectFolder.tr(),
                      ),
                    ),
                ],
                child: Icon(
                  Icons.more_horiz_rounded,
                  size: 17,
                  color: palette.textMuted,
                ),
              ),
            ],
          ],
        ),
      );
}

class _LayoutButton extends StatefulWidget {
  const _LayoutButton({
    required this.palette,
    required this.option,
    required this.selected,
    required this.onTap,
  });

  final CollectionPalette palette;
  final ExternalLayout option;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_LayoutButton> createState() => _LayoutButtonState();
}

class _LayoutButtonState extends State<_LayoutButton> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    return Tooltip(
      message: widget.option.label,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => hovered = true),
        onExit: (_) => setState(() => hovered = false),
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: widget.selected
                  ? palette.accentSoft
                  : palette.hover.withValues(alpha: hovered ? 1 : 0),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(
              widget.option.icon,
              size: 15,
              color: widget.selected ? palette.accent : palette.textMuted,
            ),
          ),
        ),
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 15),
          const SizedBox(width: 9),
          Text(label, style: const TextStyle(fontSize: 12.5)),
        ],
      );
}
