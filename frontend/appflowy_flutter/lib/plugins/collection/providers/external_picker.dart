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

/// Several objects chosen out of one account.
@immutable
class ExternalSelection {
  const ExternalSelection({required this.source, required this.nodes});

  final CollectionSource source;
  final List<ProviderNode> nodes;
}

/// Picks one file, folder or album out of a connected service.
///
/// The same browser the collection binder uses, except it lists files as well
/// as containers, because a page embeds a thing rather than a place.
Future<ExternalPick?> showExternalPicker(
  BuildContext context, {
  required ProviderServiceInfo info,
  bool containersOnly = false,
}) async {
  final chosen = await showDialog<ExternalSelection>(
    context: context,
    builder: (context) => _ExternalPicker(
      info: info,
      containersOnly: containersOnly,
      multiple: false,
    ),
  );
  if (chosen == null || chosen.nodes.isEmpty) {
    return null;
  }
  return ExternalPick(source: chosen.source, node: chosen.nodes.first);
}

/// Picks any number of files out of a connected service.
Future<ExternalSelection?> showExternalFilePicker(
  BuildContext context, {
  required ProviderServiceInfo info,
}) =>
    showDialog<ExternalSelection>(
      context: context,
      builder: (context) => _ExternalPicker(
        info: info,
        containersOnly: false,
        multiple: true,
      ),
    );

/// Picks one out of a list already in hand.
///
/// For a service that does its own choosing: the picking is over by the time
/// this opens, so there is nothing to browse — only which of them to use.
Future<ProviderNode?> showExternalNodePicker(
  BuildContext context, {
  required ProviderServiceInfo info,
  required List<ProviderNode> nodes,
}) =>
    showDialog<ProviderNode>(
      context: context,
      builder: (context) => _ExternalNodePicker(info: info, nodes: nodes),
    );

class _ExternalNodePicker extends StatelessWidget {
  const _ExternalNodePicker({required this.info, required this.nodes});

  final ProviderServiceInfo info;
  final List<ProviderNode> nodes;

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460, maxHeight: 520),
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
                    Expanded(
                      child: Text(
                        LocaleKeys.providers_embed_pick.tr(args: [info.label]),
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
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 14),
                  itemCount: nodes.length,
                  itemBuilder: (context, index) => _PickerRow(
                    node: nodes[index],
                    palette: palette,
                    accent: info.accent,
                    onTap: () => Navigator.of(context).pop(nodes[index]),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ExternalPicker extends StatefulWidget {
  const _ExternalPicker({
    required this.info,
    required this.containersOnly,
    required this.multiple,
  });

  final ProviderServiceInfo info;
  final bool containersOnly;

  /// Whether several files can be gathered before the dialog closes.
  final bool multiple;

  @override
  State<_ExternalPicker> createState() => _ExternalPickerState();
}

class _ExternalPickerState extends State<_ExternalPicker> {
  ProviderConnection? connection;
  CollectionProvider? provider;

  List<ProviderNode> nodes = const <ProviderNode>[];
  final List<ProviderNode> trail = <ProviderNode>[];

  /// Gathered across folders, so a selection survives browsing into one.
  final Map<String, ProviderNode> gathered = <String, ProviderNode>{};

  /// The folder made a moment ago, marked so it can be found in a long list.
  String? justCreated;

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
                    if (_offersNewFolder)
                      IconButton(
                        onPressed: () => unawaited(_createFolder()),
                        tooltip: LocaleKeys.providers_newFolder.tr(),
                        icon: const Icon(
                          Icons.create_new_folder_rounded,
                          size: 17,
                        ),
                        color: palette.textSecondary,
                        splashRadius: 15,
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
                            selected: gathered.containsKey(visible[index].id) ||
                                visible[index].id == justCreated,
                            selectable:
                                widget.multiple && !visible[index].isFolder,
                            onTap: () => _choose(visible[index]),
                            onOpen: visible[index].isFolder
                                ? () => _descend(visible[index])
                                : null,
                          ),
                        ),
                ),
                if (widget.multiple)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            gathered.isEmpty
                                ? LocaleKeys.providers_import_pickHint.tr()
                                : LocaleKeys.providers_import_chosen
                                    .tr(args: ['${gathered.length}']),
                            style: TextStyle(
                              color: palette.textMuted,
                              fontSize: 11.5,
                              height: 1.45,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        FilledButton(
                          onPressed: gathered.isEmpty ? null : _confirm,
                          child: Text(LocaleKeys.providers_import_add.tr()),
                        ),
                      ],
                    ),
                  )
                else if (!widget.containersOnly)
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
    if (widget.multiple && !node.isFolder) {
      setState(() {
        if (gathered.remove(node.id) == null) {
          gathered[node.id] = node;
        }
      });
      return;
    }
    if (widget.multiple) {
      unawaited(_descend(node));
      return;
    }
    Navigator.of(context).pop(
      ExternalSelection(
        source: CollectionSource(
          service: account.service,
          connectionId: account.id,
          remoteId: node.isFolder ? node.id : (node.parentId ?? ''),
          remoteName: node.name,
        ),
        nodes: [node],
      ),
    );
  }

  void _confirm() {
    final account = connection;
    if (account == null || gathered.isEmpty) {
      return;
    }
    Navigator.of(context).pop(
      ExternalSelection(
        source: CollectionSource(
          service: account.service,
          connectionId: account.id,
        ),
        nodes: gathered.values.toList(),
      ),
    );
  }

  Future<void> _descend(ProviderNode node) async {
    setState(() {
      trail.add(node);
      query = '';
      justCreated = null;
    });
    await _read(node.id);
  }

  /// Whether somewhere is being chosen, which is the only time making a folder
  /// is worth offering. It is shown even when the account cannot write yet —
  /// asking for that permission is what the button does first.
  bool get _offersNewFolder =>
      widget.containersOnly && error == null && !loading && provider != null;

  /// The folder being looked at, or null at the top of the account.
  String? get _here => trail.isEmpty ? null : trail.last.id;

  Future<void> _createFolder() async {
    final account = connection;
    if (provider == null || account == null) {
      return;
    }

    if (!provider!.capabilities.canCreateFolder) {
      // Signed in to look, not to write. Asking is better than a button that
      // could only ever fail.
      final granted = await ensureProviderWriteAccess(
        context,
        source: CollectionSource(
          service: account.service,
          connectionId: account.id,
        ),
      );
      if (!granted || !mounted) {
        return;
      }
      // What an account may do is read once, in probe(), so the provider has
      // to be built again rather than refreshed.
      provider?.dispose();
      provider = null;
      await _read(_here);
      if (!mounted || provider == null) {
        return;
      }
    }

    final live = provider;
    if (live == null || !live.capabilities.canCreateFolder) {
      return;
    }

    final name = await showDialog<String>(
      context: context,
      builder: (context) => _FolderNameDialog(
        parentName: trail.isEmpty ? widget.info.label : trail.last.name,
        atRoot: trail.isEmpty,
      ),
    );
    if (name == null || name.isEmpty || !mounted) {
      return;
    }

    setState(() {
      loading = true;
      error = null;
    });
    try {
      final created = await live.createFolder(name, parentId: _here);
      if (!mounted) {
        return;
      }
      // A filter left over from looking for somewhere to put it would hide the
      // very folder that was just made.
      setState(() => query = '');
      await _read(_here);
      if (mounted) {
        setState(() => justCreated = created.id);
      }
    } on Object catch (failure) {
      if (mounted) {
        setState(() {
          loading = false;
          error = failure is ProviderFailure &&
                  failure.status == ProviderStatus.permissionDenied
              ? LocaleKeys.providers_error_refused.tr(args: [widget.info.label])
              : LocaleKeys.providers_newFolderFailed.tr();
        });
      }
    }
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
      justCreated = null;
    });
    unawaited(_read(next.isEmpty ? null : next.last.id));
  }
}

/// Asks what a new folder should be called.
///
/// Owns its controller and disposes it in `dispose`; handing one to
/// `showDialog(...).whenComplete(dispose)` reads a disposed field during the
/// closing animation and takes the window down with it.
class _FolderNameDialog extends StatefulWidget {
  const _FolderNameDialog({required this.parentName, required this.atRoot});

  final String parentName;
  final bool atRoot;

  @override
  State<_FolderNameDialog> createState() => _FolderNameDialogState();
}

class _FolderNameDialogState extends State<_FolderNameDialog> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final name = _name.text.trim();
    if (name.isEmpty) {
      return;
    }
    Navigator.of(context).pop(name);
  }

  @override
  Widget build(BuildContext context) {
    final palette = FolderExplorerPalette.of(context);
    return AlertDialog(
      backgroundColor: palette.floatingSurface,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      title: Text(
        LocaleKeys.providers_newFolderTitle.tr(),
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          color: palette.textPrimary,
        ),
      ),
      content: SizedBox(
        width: 360,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.atRoot
                  ? LocaleKeys.providers_newFolderAtRoot
                      .tr(args: [widget.parentName])
                  : LocaleKeys.providers_newFolderIn
                      .tr(args: [widget.parentName]),
              style: TextStyle(
                fontSize: 12.5,
                height: 1.4,
                color: palette.textSecondary,
              ),
            ),
            const SizedBox(height: 16),
            ProviderTextField(
              label: LocaleKeys.providers_newFolderLabel.tr(),
              controller: _name,
              palette: palette,
              autofocus: true,
              onSubmitted: (_) => _submit(),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: _submit,
          child: Text(LocaleKeys.button_create.tr()),
        ),
      ],
    );
  }
}

class _PickerRow extends StatefulWidget {
  const _PickerRow({
    required this.node,
    required this.palette,
    required this.accent,
    required this.onTap,
    this.onOpen,
    this.selected = false,
    this.selectable = false,
  });

  final ProviderNode node;
  final FolderExplorerPalette palette;
  final Color accent;
  final VoidCallback onTap;
  final VoidCallback? onOpen;
  final bool selected;
  final bool selectable;

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
            color: widget.selected
                ? widget.accent.withValues(alpha: 0.14)
                : palette.hover.withValues(alpha: hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            children: [
              if (widget.selectable) ...[
                Icon(
                  widget.selected
                      ? Icons.check_circle_rounded
                      : Icons.radio_button_unchecked_rounded,
                  size: 16,
                  color: widget.selected ? widget.accent : palette.textMuted,
                ),
                const SizedBox(width: 9),
              ],
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
