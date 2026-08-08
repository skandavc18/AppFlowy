import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/providers/git/git_controller.dart';
import 'package:appflowy/workspace/application/providers/git/git_diff.dart';
import 'package:appflowy/workspace/application/providers/git/git_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Resolving a conflict, side by side.
///
/// Nothing is overwritten quietly. Both versions are shown as they are, the
/// two ways of keeping one wholesale are one click each, and taking neither
/// leaves the file exactly as git left it so it can be edited by hand.
class GitConflictResolver extends StatefulWidget {
  const GitConflictResolver({
    super.key,
    required this.controller,
    required this.palette,
  });

  final GitController controller;
  final CollectionPalette palette;

  @override
  State<GitConflictResolver> createState() => _GitConflictResolverState();
}

class _GitConflictResolverState extends State<GitConflictResolver> {
  String? path;
  GitConflictedFile? file;
  bool loading = false;

  @override
  void initState() {
    super.initState();
    _selectFirst();
  }

  @override
  void didUpdateWidget(GitConflictResolver oldWidget) {
    super.didUpdateWidget(oldWidget);
    final conflicts = widget.controller.status.conflicted;
    if (path != null && !conflicts.any((change) => change.path == path)) {
      _selectFirst();
    }
  }

  void _selectFirst() {
    final conflicts = widget.controller.status.conflicted;
    if (conflicts.isEmpty) {
      setState(() {
        path = null;
        file = null;
      });
      return;
    }
    unawaited(_select(conflicts.first.path));
  }

  Future<void> _select(String next) async {
    setState(() {
      path = next;
      loading = true;
      file = null;
    });
    final read = await widget.controller.readConflict(next);
    if (mounted) {
      setState(() {
        file = read;
        loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final conflicts = widget.controller.status.conflicted;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          width: 280,
          child: ViewerCard(
            color: palette.surface,
            reactsToPointer: false,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 12, 14, 6),
                  child: Text(
                    LocaleKeys.providers_git_conflicts.tr(),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontVariations: const [FontVariation.weight(620)],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(14, 0, 14, 10),
                  child: Text(
                    LocaleKeys.providers_git_conflictHelp.tr(),
                    style: TextStyle(
                      color: palette.textMuted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 10),
                    itemCount: conflicts.length,
                    itemBuilder: (context, index) {
                      final change = conflicts[index];
                      return _ConflictRow(
                        change: change,
                        palette: palette,
                        selected: change.path == path,
                        onTap: () => unawaited(_select(change.path)),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(child: _body(palette)),
      ],
    );
  }

  Widget _body(CollectionPalette palette) {
    if (loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    final current = file;
    final currentPath = path;
    if (current == null || currentPath == null) {
      return Center(
        child: Text(
          LocaleKeys.providers_git_noChanges.tr(),
          style: TextStyle(color: palette.textMuted, fontSize: 12.5),
        ),
      );
    }

    final mono = codeUiTextStyle(
      color: palette.textPrimary,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ).copyWith(height: 1.55);

    return ViewerCard(
      color: palette.surface,
      reactsToPointer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    currentPath,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 12.5,
                      fontVariations: const [FontVariation.weight(580)],
                    ),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(
                    widget.controller
                        .resolveWith(currentPath, GitConflictSide.ours),
                  ),
                  child: Text(
                    LocaleKeys.providers_git_keepOurs.tr(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(
                    widget.controller
                        .resolveWith(currentPath, GitConflictSide.theirs),
                  ),
                  child: Text(
                    LocaleKeys.providers_git_keepTheirs.tr(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
                TextButton(
                  onPressed: () => unawaited(
                    widget.controller.markResolved([currentPath]),
                  ),
                  child: Text(
                    LocaleKeys.providers_git_resolved.tr(),
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.fromLTRB(0, 0, 0, 16),
              itemCount: current.blocks.length,
              itemBuilder: (context, index) => _ConflictBlockView(
                block: current.blocks[index],
                palette: palette,
                mono: mono,
                onKeep: (ours) => unawaited(
                  _keepBlock(currentPath, current, index, ours: ours),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Keeps one side of a single block, leaving the rest of the file alone.
  Future<void> _keepBlock(
    String currentPath,
    GitConflictedFile current,
    int index, {
    required bool ours,
  }) async {
    final block = current.blocks[index];
    final lines = List<String>.from(current.lines);
    // Find the closing marker from the block's own start line, so a file with
    // several conflicts stays in step even after an earlier one is resolved.
    var end = block.startLine;
    while (end < lines.length && !lines[end].startsWith('>>>>>>>')) {
      end++;
    }
    final chosen = ours ? block.ours : block.theirs;
    lines.replaceRange(
      block.startLine,
      (end + 1).clamp(0, lines.length),
      chosen,
    );

    await widget.controller.writeResolutionOnly(currentPath, lines.join('\n'));
    await _select(currentPath);
  }
}

class _ConflictBlockView extends StatelessWidget {
  const _ConflictBlockView({
    required this.block,
    required this.palette,
    required this.mono,
    required this.onKeep,
  });

  final GitConflictBlock block;
  final CollectionPalette palette;
  final TextStyle mono;
  final void Function(bool ours) onKeep;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final ours = dark ? const Color(0xFF3FB950) : const Color(0xFF1A7F37);
    final theirs = dark ? const Color(0xFF6E9EF8) : const Color(0xFF2C5FCC);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Side(
            label: block.oursLabel.isEmpty
                ? LocaleKeys.providers_git_keepOurs.tr()
                : block.oursLabel,
            lines: block.ours,
            accent: ours,
            palette: palette,
            mono: mono,
            onKeep: () => onKeep(true),
          ),
          const SizedBox(height: 6),
          _Side(
            label: block.theirsLabel.isEmpty
                ? LocaleKeys.providers_git_keepTheirs.tr()
                : block.theirsLabel,
            lines: block.theirs,
            accent: theirs,
            palette: palette,
            mono: mono,
            onKeep: () => onKeep(false),
          ),
        ],
      ),
    );
  }
}

class _Side extends StatelessWidget {
  const _Side({
    required this.label,
    required this.lines,
    required this.accent,
    required this.palette,
    required this.mono,
    required this.onKeep,
  });

  final String label;
  final List<String> lines;
  final Color accent;
  final CollectionPalette palette;
  final TextStyle mono;
  final VoidCallback onKeep;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.07),
          borderRadius: BorderRadius.circular(9),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 7, 6, 5),
              child: Row(
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration:
                        BoxDecoration(color: accent, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: accent,
                        fontSize: 11.5,
                        fontVariations: const [FontVariation.weight(620)],
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: onKeep,
                    style: TextButton.styleFrom(
                      minimumSize: const Size(0, 26),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                    child: Text(
                      LocaleKeys.providers_git_resolved.tr(),
                      style: TextStyle(fontSize: 11.5, color: accent),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 9),
              child: SelectableText(
                lines.isEmpty ? ' ' : lines.join('\n'),
                style: mono,
              ),
            ),
          ],
        ),
      );
}

class _ConflictRow extends StatelessWidget {
  const _ConflictRow({
    required this.change,
    required this.palette,
    required this.selected,
    required this.onTap,
  });

  final GitChange change;
  final CollectionPalette palette;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 7),
            margin: const EdgeInsets.symmetric(vertical: 1),
            decoration: BoxDecoration(
              color: selected ? palette.selected : Colors.transparent,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.merge_type_rounded,
                  size: 14,
                  color: Theme.of(context).colorScheme.error,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    change.path,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textPrimary,
                      fontSize: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
}
