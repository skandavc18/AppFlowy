import 'dart:async';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/collection/providers/external_repository_view.dart';
import 'package:appflowy/plugins/collection/providers/git/git_panel.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/git/git_controller.dart';
import 'package:appflowy/workspace/application/providers/git/git_repository.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/file_picker/file_picker_service.dart';
import 'package:flutter/material.dart';

/// Where a repository collection's git working tree is kept.
///
/// A collection holds objects the workspace stores; a git working tree is a
/// real folder on disk. Rather than pretend one is the other, a repository
/// collection can name the working tree it belongs to, and every git operation
/// runs there.
const gitWorkingTreeOption = 'git_path';

/// The Source control view of a Repository collection.
class GitCollectionView extends StatefulWidget {
  const GitCollectionView({
    super.key,
    required this.collection,
  });

  final CollectionViewContext collection;

  @override
  State<GitCollectionView> createState() => _GitCollectionViewState();
}

class _GitCollectionViewState extends State<GitCollectionView> {
  GitController? controller;
  String? workingTree;
  bool checking = true;

  @override
  void initState() {
    super.initState();
    unawaited(_bind());
  }

  @override
  void didUpdateWidget(GitCollectionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = widget.collection.collectionView.source
        .option<String>(gitWorkingTreeOption);
    if (next != workingTree) {
      unawaited(_bind());
    }
  }

  Future<void> _bind() async {
    final path = widget.collection.collectionView.source
        .option<String>(gitWorkingTreeOption);
    if (path == null || path.isEmpty) {
      setState(() {
        controller?.dispose();
        controller = null;
        workingTree = null;
        checking = false;
      });
      return;
    }

    // The stored path may be anywhere inside the tree; git itself is asked
    // where the top is rather than the path being trusted.
    final root = await GitRepository.discover(path);
    if (!mounted) {
      return;
    }
    controller?.dispose();
    setState(() {
      workingTree = root;
      controller = root == null ? null : GitController(root);
      checking = false;
    });
  }

  @override
  void dispose() {
    controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = CollectionPalette.of(context, widget.collection.kind);
    if (checking) {
      return const Center(
        child: SizedBox(
          width: 20,
          height: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    final live = controller;
    if (live == null) {
      return _Connect(
        palette: palette,
        hasPath: workingTree == null &&
            (widget.collection.collectionView.source
                        .option<String>(gitWorkingTreeOption) ??
                    '')
                .isNotEmpty,
        onPick: () => unawaited(_pick()),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 18),
      child: GitPanel(controller: live, palette: palette),
    );
  }

  Future<void> _pick() async {
    final picked = await getIt<FilePickerService>().getDirectoryPath();
    if (picked == null || !mounted) {
      return;
    }
    final root = await GitRepository.discover(picked);
    if (!mounted) {
      return;
    }
    if (root == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(LocaleKeys.providers_git_notARepository.tr())),
      );
      return;
    }

    final next = widget.collection.collectionView.source
        .withOption(gitWorkingTreeOption, root);
    ProviderSourceUpdate.of(context)?.call(next);
    setState(() {
      workingTree = root;
      controller?.dispose();
      controller = GitController(root);
    });
  }
}

class _Connect extends StatelessWidget {
  const _Connect({
    required this.palette,
    required this.hasPath,
    required this.onPick,
  });

  final CollectionPalette palette;
  final bool hasPath;
  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) => Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 380),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  color: palette.accentSoft,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(
                  Icons.account_tree_rounded,
                  size: 22,
                  color: palette.accent,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                LocaleKeys.providers_git_connectTitle.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textPrimary,
                  fontSize: 15,
                  fontVariations: const [FontVariation.weight(620)],
                ),
              ),
              const SizedBox(height: 6),
              Text(
                GitRepository.isAvailable
                    ? hasPath
                        ? LocaleKeys.providers_git_notARepository.tr()
                        : LocaleKeys.providers_git_connectBody.tr()
                    : LocaleKeys.providers_git_notInstalled.tr(),
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: palette.textMuted,
                  fontSize: 12.5,
                  height: 1.55,
                ),
              ),
              if (GitRepository.isAvailable) ...[
                const SizedBox(height: 18),
                FilledButton.tonal(
                  onPressed: onPick,
                  child: Text(LocaleKeys.providers_git_chooseFolder.tr()),
                ),
              ],
            ],
          ),
        ),
      );
}
