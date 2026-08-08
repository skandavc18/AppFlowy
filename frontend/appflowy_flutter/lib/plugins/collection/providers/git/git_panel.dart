import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/git/git_conflict_view.dart';
import 'package:appflowy/plugins/collection/providers/git/git_diff_view.dart';
import 'package:appflowy/shared/viewer_card.dart';
import 'package:appflowy/workspace/application/providers/git/git_controller.dart';
import 'package:appflowy/workspace/application/providers/git/git_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Working with a repository: what changed, what it changed to, and the
/// operations that move it on.
///
/// Nothing here composes a command line and nothing here is a terminal. Each
/// control is one named operation, and the ones that can lose work explain
/// themselves and ask first.
class GitPanel extends StatefulWidget {
  const GitPanel({
    super.key,
    required this.controller,
    required this.palette,
  });

  final GitController controller;
  final CollectionPalette palette;

  @override
  State<GitPanel> createState() => _GitPanelState();
}

class _GitPanelState extends State<GitPanel> {
  final TextEditingController message = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
    unawaited(widget.controller.refresh());
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    message.dispose();
    super.dispose();
  }

  void _onChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final palette = widget.palette;

    if (!controller.isAvailable) {
      return _Notice(
        palette: palette,
        icon: Icons.info_outline_rounded,
        message: LocaleKeys.providers_git_notInstalled.tr(),
      );
    }
    if (controller.loading) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final status = controller.status;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Toolbar(controller: controller, palette: palette),
        if (controller.notice.isNotEmpty)
          _Notice(
            palette: palette,
            icon: controller.noticeIsFailure
                ? Icons.error_outline_rounded
                : Icons.check_circle_outline_rounded,
            message: controller.notice,
            failure: controller.noticeIsFailure,
          ),
        if (status.isMidOperation)
          _OperationBar(controller: controller, palette: palette),
        Expanded(
          child: status.hasConflicts
              ? GitConflictResolver(
                  controller: controller,
                  palette: palette,
                )
              : Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    SizedBox(
                      width: 320,
                      child: _ChangesPane(
                        controller: controller,
                        palette: palette,
                        message: message,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ViewerCard(
                        color: palette.surface,
                        reactsToPointer: false,
                        child: GitDiffView(
                          files: controller.diff,
                          palette: palette,
                        ),
                      ),
                    ),
                  ],
                ),
        ),
      ],
    );
  }
}

class _Toolbar extends StatelessWidget {
  const _Toolbar({required this.controller, required this.palette});

  final GitController controller;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 4, 12),
      child: Row(
        children: [
          GitBranchSelector(controller: controller, palette: palette),
          const SizedBox(width: 12),
          if (status.behind > 0)
            _Meta(
              palette: palette,
              icon: Icons.arrow_downward_rounded,
              label: LocaleKeys.providers_git_behind
                  .tr(args: ['${status.behind}']),
            ),
          if (status.ahead > 0) ...[
            const SizedBox(width: 8),
            _Meta(
              palette: palette,
              icon: Icons.arrow_upward_rounded,
              label:
                  LocaleKeys.providers_git_ahead.tr(args: ['${status.ahead}']),
            ),
          ],
          const Spacer(),
          _Action(
            palette: palette,
            icon: Icons.sync_rounded,
            label: LocaleKeys.providers_git_fetch.tr(),
            enabled: !controller.busy,
            onPressed: () => unawaited(controller.fetch()),
          ),
          _Action(
            palette: palette,
            icon: Icons.arrow_downward_rounded,
            label: LocaleKeys.providers_git_pull.tr(),
            enabled: !controller.busy,
            onPressed: () => unawaited(controller.pull()),
          ),
          _Action(
            palette: palette,
            icon: Icons.arrow_upward_rounded,
            label: LocaleKeys.providers_git_push.tr(),
            enabled: !controller.busy,
            primary: status.canPush,
            onPressed: () => unawaited(controller.push()),
          ),
          _Action(
            palette: palette,
            icon: Icons.inventory_2_rounded,
            label: LocaleKeys.providers_git_stash.tr(),
            enabled: !controller.busy && !status.isClean,
            onPressed: () => unawaited(controller.createStash()),
          ),
        ],
      ),
    );
  }
}

/// `main ▾` — the whole branch interface in one control.
class GitBranchSelector extends StatelessWidget {
  const GitBranchSelector({
    super.key,
    required this.controller,
    required this.palette,
  });

  final GitController controller;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    final current = status.branch.isEmpty
        ? (status.isDetached
            ? LocaleKeys.providers_git_inProgress.tr(args: ['detached'])
            : '—')
        : status.branch;

    return PopupMenuButton<_BranchAction>(
      tooltip: LocaleKeys.providers_git_checkout.tr(),
      position: PopupMenuPosition.under,
      onSelected: (action) => _handle(context, action),
      itemBuilder: (context) => [
        for (final branch in controller.localBranches)
          PopupMenuItem<_BranchAction>(
            value: _BranchAction.checkout(branch.name),
            height: 34,
            child: Row(
              children: [
                Icon(
                  branch.isCurrent
                      ? Icons.check_rounded
                      : Icons.account_tree_rounded,
                  size: 14,
                  color: branch.isCurrent ? palette.accent : palette.textMuted,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    branch.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12.5),
                  ),
                ),
              ],
            ),
          ),
        const PopupMenuDivider(),
        PopupMenuItem<_BranchAction>(
          value: const _BranchAction.create(),
          height: 32,
          child: _MenuRow(
            icon: Icons.add_rounded,
            label: LocaleKeys.providers_git_newBranch.tr(),
          ),
        ),
        PopupMenuItem<_BranchAction>(
          value: const _BranchAction.rename(),
          height: 32,
          child: _MenuRow(
            icon: Icons.drive_file_rename_outline_rounded,
            label: LocaleKeys.providers_git_renameBranch.tr(),
          ),
        ),
        PopupMenuItem<_BranchAction>(
          value: const _BranchAction.delete(),
          height: 32,
          child: _MenuRow(
            icon: Icons.delete_outline_rounded,
            label: LocaleKeys.providers_git_deleteBranch.tr(),
          ),
        ),
        const PopupMenuDivider(),
        PopupMenuItem<_BranchAction>(
          value: const _BranchAction.merge(),
          height: 32,
          child: _MenuRow(
            icon: Icons.merge_rounded,
            label: LocaleKeys.providers_git_merge.tr(),
          ),
        ),
        PopupMenuItem<_BranchAction>(
          value: const _BranchAction.rebase(),
          height: 32,
          child: _MenuRow(
            icon: Icons.low_priority_rounded,
            label: LocaleKeys.providers_git_rebase.tr(),
          ),
        ),
      ],
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: palette.hover,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.account_tree_rounded, size: 13, color: palette.accent),
            const SizedBox(width: 6),
            Text(
              current,
              style: TextStyle(
                color: palette.textPrimary,
                fontSize: 12,
                fontVariations: const [FontVariation.weight(570)],
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 15, color: palette.textMuted),
          ],
        ),
      ),
    );
  }

  Future<void> _handle(BuildContext context, _BranchAction action) async {
    switch (action.kind) {
      case _BranchActionKind.checkout:
        await controller.checkout(action.branch);

      case _BranchActionKind.create:
        final name = await _askForName(
          context,
          title: LocaleKeys.providers_git_newBranch.tr(),
        );
        if (name != null) {
          await controller.createBranch(name);
        }

      case _BranchActionKind.rename:
        final from = controller.status.branch;
        final name = await _askForName(
          context,
          title: LocaleKeys.providers_git_renameBranch.tr(),
          initial: from,
        );
        if (name != null && name != from) {
          await controller.renameBranch(from, name);
        }

      case _BranchActionKind.delete:
        final branch = await _pickBranch(
          context,
          title: LocaleKeys.providers_git_deleteBranch.tr(),
          exclude: controller.status.branch,
        );
        if (branch == null || !context.mounted) {
          return;
        }
        final confirmed = await confirmDestructive(
          context,
          palette: palette,
          title: LocaleKeys.providers_git_confirmDeleteBranchTitle
              .tr(args: [branch]),
          body: LocaleKeys.providers_git_confirmDeleteBranchBody.tr(),
          action: LocaleKeys.providers_git_deleteBranch.tr(),
        );
        if (confirmed) {
          await controller.deleteBranch(branch);
        }

      case _BranchActionKind.merge:
        final branch = await _pickBranch(
          context,
          title: LocaleKeys.providers_git_merge.tr(),
          exclude: controller.status.branch,
        );
        if (branch == null || !context.mounted) {
          return;
        }
        final confirmed = await confirmDestructive(
          context,
          palette: palette,
          title: LocaleKeys.providers_git_confirmMergeTitle
              .tr(args: [branch, controller.status.branch]),
          body: LocaleKeys.providers_git_confirmMergeBody
              .tr(args: [branch, controller.status.branch]),
          action: LocaleKeys.providers_git_merge.tr(),
          destructive: false,
        );
        if (confirmed) {
          await controller.merge(branch);
        }

      case _BranchActionKind.rebase:
        final branch = await _pickBranch(
          context,
          title: LocaleKeys.providers_git_rebase.tr(),
          exclude: controller.status.branch,
        );
        if (branch == null || !context.mounted) {
          return;
        }
        final confirmed = await confirmDestructive(
          context,
          palette: palette,
          title: LocaleKeys.providers_git_confirmRebaseTitle
              .tr(args: [controller.status.branch, branch]),
          body: LocaleKeys.providers_git_confirmRebaseBody
              .tr(args: [controller.status.branch, branch]),
          action: LocaleKeys.providers_git_rebase.tr(),
        );
        if (confirmed) {
          await controller.rebase(branch);
        }
    }
  }

  Future<String?> _pickBranch(
    BuildContext context, {
    required String title,
    String exclude = '',
  }) =>
      showDialog<String>(
        context: context,
        builder: (context) => SimpleDialog(
          title: Text(title, style: const TextStyle(fontSize: 15)),
          children: [
            for (final branch in controller.branches)
              if (branch.name != exclude)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(branch.name),
                  child: Row(
                    children: [
                      Icon(
                        branch.isRemote
                            ? Icons.cloud_outlined
                            : Icons.account_tree_rounded,
                        size: 14,
                        color: palette.textMuted,
                      ),
                      const SizedBox(width: 8),
                      Text(branch.name, style: const TextStyle(fontSize: 13)),
                    ],
                  ),
                ),
          ],
        ),
      );
}

Future<String?> _askForName(
  BuildContext context, {
  required String title,
  String initial = '',
}) {
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      content: TextField(
        controller: controller,
        autofocus: true,
        onSubmitted: (value) => Navigator.of(context).pop(value.trim()),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(controller.text.trim()),
          child: Text(LocaleKeys.button_confirm.tr()),
        ),
      ],
    ),
  ).then((value) {
    controller.dispose();
    return value == null || value.isEmpty ? null : value;
  });
}

/// Says what will happen, names the branch it happens to, and waits.
///
/// Every operation that can lose work goes through this. Nothing destructive is
/// ever a side effect of something else.
Future<bool> confirmDestructive(
  BuildContext context, {
  required CollectionPalette palette,
  required String title,
  required String body,
  required String action,
  bool destructive = true,
}) async {
  final answer = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title, style: const TextStyle(fontSize: 15)),
      content: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: Text(body, style: const TextStyle(fontSize: 13, height: 1.55)),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(LocaleKeys.button_cancel.tr()),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(
            action,
            style: TextStyle(
              color: destructive
                  ? Theme.of(context).colorScheme.error
                  : Theme.of(context).colorScheme.primary,
            ),
          ),
        ),
      ],
    ),
  );
  return answer ?? false;
}

class _ChangesPane extends StatelessWidget {
  const _ChangesPane({
    required this.controller,
    required this.palette,
    required this.message,
  });

  final GitController controller;
  final CollectionPalette palette;
  final TextEditingController message;

  @override
  Widget build(BuildContext context) {
    final status = controller.status;
    return ViewerCard(
      color: palette.surface,
      reactsToPointer: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 8, 8),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    LocaleKeys.providers_git_changes.tr(),
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontSize: 12,
                      fontVariations: const [FontVariation.weight(620)],
                    ),
                  ),
                ),
                if (!status.isClean)
                  TextButton(
                    onPressed: () => unawaited(controller.stageAll()),
                    child: Text(
                      LocaleKeys.providers_git_stageAll.tr(),
                      style: const TextStyle(fontSize: 11.5),
                    ),
                  ),
              ],
            ),
          ),
          Expanded(
            child: status.isClean
                ? Center(
                    child: Text(
                      LocaleKeys.providers_git_noChanges.tr(),
                      style:
                          TextStyle(color: palette.textMuted, fontSize: 12.5),
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
                    children: [
                      if (status.staged.isNotEmpty) ...[
                        _SectionLabel(
                          label: LocaleKeys.providers_git_staged.tr(),
                          palette: palette,
                        ),
                        for (final change in status.staged)
                          _ChangeRow(
                            change: change,
                            controller: controller,
                            palette: palette,
                            staged: true,
                          ),
                      ],
                      if (status.unstaged.isNotEmpty) ...[
                        _SectionLabel(
                          label: LocaleKeys.providers_git_unstaged.tr(),
                          palette: palette,
                        ),
                        for (final change in status.unstaged)
                          _ChangeRow(
                            change: change,
                            controller: controller,
                            palette: palette,
                            staged: false,
                          ),
                      ],
                    ],
                  ),
          ),
          _CommitBox(
            controller: controller,
            palette: palette,
            message: message,
          ),
        ],
      ),
    );
  }
}

class _CommitBox extends StatefulWidget {
  const _CommitBox({
    required this.controller,
    required this.palette,
    required this.message,
  });

  final GitController controller;
  final CollectionPalette palette;
  final TextEditingController message;

  @override
  State<_CommitBox> createState() => _CommitBoxState();
}

class _CommitBoxState extends State<_CommitBox> {
  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final canCommit = widget.controller.status.hasStaged &&
        widget.message.text.trim().isNotEmpty &&
        !widget.controller.busy;

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: widget.message,
            minLines: 2,
            maxLines: 4,
            onChanged: (_) => setState(() {}),
            style: TextStyle(color: palette.textPrimary, fontSize: 12.5),
            decoration: InputDecoration(
              isDense: true,
              hintText: LocaleKeys.providers_git_commitMessage.tr(),
              hintStyle: TextStyle(color: palette.textMuted, fontSize: 12.5),
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
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _Action(
                  palette: palette,
                  icon: Icons.check_rounded,
                  label: LocaleKeys.providers_git_commit.tr(),
                  primary: true,
                  expand: true,
                  enabled: canCommit,
                  onPressed: () async {
                    final committed =
                        await widget.controller.commit(widget.message.text);
                    if (committed && mounted) {
                      widget.message.clear();
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 6),
              _Action(
                palette: palette,
                icon: Icons.arrow_upward_rounded,
                label: LocaleKeys.providers_git_commitAndPush.tr(),
                enabled: canCommit,
                onPressed: () async {
                  final committed =
                      await widget.controller.commit(widget.message.text);
                  if (!committed || !mounted) {
                    return;
                  }
                  widget.message.clear();
                  setState(() {});
                  await widget.controller.push();
                },
              ),
            ],
          ),
          if (!widget.controller.status.hasStaged &&
              !widget.controller.status.isClean)
            Padding(
              padding: const EdgeInsets.only(top: 6),
              child: Text(
                LocaleKeys.providers_git_noneStaged.tr(),
                style: TextStyle(color: palette.textMuted, fontSize: 11),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChangeRow extends StatefulWidget {
  const _ChangeRow({
    required this.change,
    required this.controller,
    required this.palette,
    required this.staged,
  });

  final GitChange change;
  final GitController controller;
  final CollectionPalette palette;
  final bool staged;

  @override
  State<_ChangeRow> createState() => _ChangeRowState();
}

class _ChangeRowState extends State<_ChangeRow> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final change = widget.change;
    final selected = widget.controller.selectedPath == change.path;
    final hue = change.isConflicted
        ? Theme.of(context).colorScheme.error
        : change.isAdded
            ? const Color(0xFF1A7F37)
            : change.isDeleted
                ? const Color(0xFFCF222E)
                : palette.textMuted;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: () => unawaited(widget.controller.select(change.path)),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
          margin: const EdgeInsets.symmetric(vertical: 1),
          decoration: BoxDecoration(
            color: selected
                ? palette.selected
                : palette.hover.withValues(alpha: hovered ? 1 : 0),
            borderRadius: BorderRadius.circular(7),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 14,
                child: Text(
                  change.isUntracked
                      ? 'A'
                      : change.isConflicted
                          ? '!'
                          : widget.staged
                              ? change.indexStatus
                              : change.workTreeStatus,
                  style: TextStyle(
                    color: hue,
                    fontSize: 11.5,
                    fontVariations: const [FontVariation.weight(680)],
                  ),
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: change.name,
                        style: TextStyle(color: palette.textPrimary),
                      ),
                      if (change.path.contains('/'))
                        TextSpan(
                          text:
                              '  ${change.path.substring(0, change.path.lastIndexOf('/'))}',
                          style: TextStyle(color: palette.textMuted),
                        ),
                    ],
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 140),
                opacity: hovered ? 1 : 0,
                child: IconButton(
                  tooltip: widget.staged
                      ? LocaleKeys.providers_git_unstageAll.tr()
                      : LocaleKeys.providers_git_stageAll.tr(),
                  onPressed: () => unawaited(
                    widget.staged
                        ? widget.controller.unstage([change.path])
                        : widget.controller.stage([change.path]),
                  ),
                  icon: Icon(
                    widget.staged ? Icons.remove_rounded : Icons.add_rounded,
                    size: 14,
                  ),
                  color: palette.textSecondary,
                  splashRadius: 12,
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  padding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _OperationBar extends StatelessWidget {
  const _OperationBar({required this.controller, required this.palette});

  final GitController controller;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
        decoration: BoxDecoration(
          color: palette.accentSoft,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          children: [
            Icon(Icons.timelapse_rounded, size: 15, color: palette.accent),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                LocaleKeys.providers_git_inProgress
                    .tr(args: [controller.status.operation]),
                style: TextStyle(color: palette.textSecondary, fontSize: 12.5),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(controller.continueOperation()),
              child: Text(
                LocaleKeys.providers_git_continueOperation.tr(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
            TextButton(
              onPressed: () => unawaited(controller.abort()),
              child: Text(
                LocaleKeys.providers_git_abort.tr(),
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ],
        ),
      );
}

class _Notice extends StatelessWidget {
  const _Notice({
    required this.palette,
    required this.icon,
    required this.message,
    this.failure = false,
  });

  final CollectionPalette palette;
  final IconData icon;
  final String message;
  final bool failure;

  @override
  Widget build(BuildContext context) {
    final accent =
        failure ? Theme.of(context).colorScheme.error : palette.textMuted;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.09),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(icon, size: 15, color: accent),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: palette.textSecondary,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, required this.palette});

  final String label;
  final CollectionPalette palette;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
        child: Text(
          label.toUpperCase(),
          style: TextStyle(
            color: palette.textMuted,
            fontSize: 10,
            letterSpacing: 0.6,
            fontVariations: const [FontVariation.weight(640)],
          ),
        ),
      );
}

class _MenuRow extends StatelessWidget {
  const _MenuRow({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Icon(icon, size: 14),
          const SizedBox(width: 8),
          Text(label, style: const TextStyle(fontSize: 12.5)),
        ],
      );
}

class _Meta extends StatelessWidget {
  const _Meta({
    required this.palette,
    required this.icon,
    required this.label,
  });

  final CollectionPalette palette;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: palette.textMuted),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(color: palette.textMuted, fontSize: 11.5),
          ),
        ],
      );
}

class _Action extends StatefulWidget {
  const _Action({
    required this.palette,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.enabled = true,
    this.primary = false,
    this.expand = false,
  });

  final CollectionPalette palette;
  final IconData icon;
  final String label;
  final VoidCallback onPressed;
  final bool enabled;
  final bool primary;
  final bool expand;

  @override
  State<_Action> createState() => _ActionState();
}

class _ActionState extends State<_Action> {
  bool hovered = false;

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final enabled = widget.enabled;
    final ink = widget.primary ? palette.accent : palette.textSecondary;

    return MouseRegion(
      cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
      onEnter: (_) => setState(() => hovered = true),
      onExit: (_) => setState(() => hovered = false),
      child: GestureDetector(
        onTap: enabled ? widget.onPressed : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOutCubic,
          margin: const EdgeInsets.symmetric(horizontal: 2),
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          alignment: widget.expand ? Alignment.center : null,
          decoration: BoxDecoration(
            color: widget.primary
                ? palette.accent
                    .withValues(alpha: enabled ? (hovered ? 0.2 : 0.13) : 0.06)
                : palette.hover.withValues(alpha: hovered && enabled ? 1 : 0),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            mainAxisSize: widget.expand ? MainAxisSize.max : MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                widget.icon,
                size: 13,
                color: ink.withValues(alpha: enabled ? 1 : 0.4),
              ),
              const SizedBox(width: 5),
              Text(
                widget.label,
                style: TextStyle(
                  color: ink.withValues(alpha: enabled ? 1 : 0.4),
                  fontSize: 11.5,
                  fontVariations: const [FontVariation.weight(570)],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

enum _BranchActionKind { checkout, create, rename, delete, merge, rebase }

@immutable
class _BranchAction {
  const _BranchAction.checkout(this.branch) : kind = _BranchActionKind.checkout;
  const _BranchAction.create()
      : kind = _BranchActionKind.create,
        branch = '';
  const _BranchAction.rename()
      : kind = _BranchActionKind.rename,
        branch = '';
  const _BranchAction.delete()
      : kind = _BranchActionKind.delete,
        branch = '';
  const _BranchAction.merge()
      : kind = _BranchActionKind.merge,
        branch = '';
  const _BranchAction.rebase()
      : kind = _BranchActionKind.rebase,
        branch = '';

  final _BranchActionKind kind;
  final String branch;
}
