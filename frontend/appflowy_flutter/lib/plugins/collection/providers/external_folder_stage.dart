import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/connect_dialog.dart';
import 'package:appflowy/plugins/collection/providers/external_content_view.dart';
import 'package:appflowy/plugins/collection/providers/external_context_menu.dart';
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

  /// The binding the model was actually built against.
  CollectionSource? boundSource;

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
    // A different remote folder is worth throwing the model away for, and so
    // is a change of permission: what the account may do is read once, in
    // `probe`. A layout change must not cost a re-read, which is why only
    // those two are compared — and against what was BOUND, so persisting a
    // change this widget already applied does not read the folder twice.
    final bound = boundSource;
    if (bound == null ||
        bound.cacheKey != widget.source.cacheKey ||
        bound.readOnly != widget.source.readOnly) {
      _rebind(widget.source);
    }
  }

  void _bind() => _rebind(widget.source);

  /// Builds the model against [source].
  ///
  /// Taken explicitly because granting write access persists the new binding
  /// asynchronously: `widget.source` is still the old one at that moment, and
  /// binding to it would leave the folder believing it may not write.
  void _rebind(CollectionSource source) {
    controller?.dispose();
    boundSource = source;
    final created = ProviderController(
      collectionId: widget.collectionId,
      source: source,
    );
    controller = created;
    unawaited(created.load());
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  /// Signs in again, then reads the folder once more.
  Future<void> _reconnect(ProviderController live) async {
    final signedIn = await reconnectProviderAccount(
      context,
      info: widget.source.info,
    );
    if (signedIn && mounted) {
      await live.refresh();
    }
  }

  /// Turns writing on or off for this mount.
  ///
  /// Turning it on asks the service for the permission first; a provider
  /// reads what the account may do once, in `probe`, so the model is built
  /// again afterwards rather than left believing the old answer.
  Future<void> _setWritable(bool writable) async {
    if (!writable) {
      final next = widget.source.copyWith(readOnly: true);
      widget.onSourceChanged(next);
      setState(() => _rebind(next));
      return;
    }

    final granted = await ensureProviderWriteAccess(
      context,
      source: widget.source,
    );
    if (!granted || !mounted) {
      return;
    }
    final next = widget.source.copyWith(readOnly: false);
    widget.onSourceChanged(next);
    setState(() => _rebind(next));
  }

  /// Whether anything in this folder can be changed right now.
  ///
  /// Read from the model rather than from the binding's own flag: a folder
  /// connected before mounts existed is not marked read only, yet its grant
  /// still is, and it needs the same way in.
  bool _canWrite(ProviderController live) =>
      live.capabilities.canUpload || live.capabilities.canCreateFolder;

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
            onReconnect: () => unawaited(_reconnect(live)),
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
                onReconnect: () => unawaited(_reconnect(live)),
              ),
            Expanded(
              child: ExternalContentView(
                controller: live,
                palette: palette,
                layout: layout,
                onAllowChanges: _canWrite(live)
                    ? null
                    : () => unawaited(_setWritable(true)),
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
            Builder(
              builder: (buttonContext) => IconButton(
                tooltip: LocaleKeys.workspaceFolderExplorer_addFile.tr(),
                onPressed: () {
                  final box = buttonContext.findRenderObject() as RenderBox?;
                  if (box == null) {
                    return;
                  }
                  unawaited(
                    showExternalBackgroundMenu(
                      buttonContext,
                      controller: live,
                      containerId: null,
                      position: box.localToGlobal(
                        Offset(0, box.size.height),
                      ),
                      onAllowChanges: _canWrite(live)
                          ? null
                          : () => unawaited(_setWritable(true)),
                    ),
                  );
                },
                icon: const Icon(Icons.add_rounded, size: 17),
                color: palette.textSecondary,
                splashRadius: 15,
                constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                padding: EdgeInsets.zero,
              ),
            ),
            const SizedBox(width: 6),
            if (!_canWrite(live)) ...[
              Icon(Icons.lock_rounded, size: 13, color: palette.textMuted),
              const SizedBox(width: 5),
              Text(
                LocaleKeys.providers_mount_readOnly.tr(),
                style: TextStyle(color: palette.textMuted, fontSize: 11.5),
              ),
              const SizedBox(width: 12),
            ],
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
                onSelected: (value) => switch (value) {
                  0 => widget.onChangeSource?.call(),
                  1 => widget.onDisconnect?.call(),
                  _ => unawaited(_setWritable(!_canWrite(live))),
                },
                itemBuilder: (context) => [
                  PopupMenuItem<int>(
                    value: 2,
                    height: 34,
                    child: _MenuRow(
                      icon: _canWrite(live)
                          ? Icons.lock_rounded
                          : Icons.lock_open_rounded,
                      label: _canWrite(live)
                          ? LocaleKeys.providers_mount_readOnly.tr()
                          : LocaleKeys.providers_mount_allowChanges.tr(),
                    ),
                  ),
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
