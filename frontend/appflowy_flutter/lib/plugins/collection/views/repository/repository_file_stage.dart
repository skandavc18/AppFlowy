import 'dart:async';
import 'dart:io';

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/repository/repository_style.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/sandboxed_code_runner.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/collections/repository/repo_file_fetcher.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One repository file, shown with the renderer it already has.
///
/// Nothing here reimplements a viewer: source keeps the code editor and its
/// highlighting, markdown keeps its preview, a PDF keeps pdfrx and a page
/// keeps the document editor. What the repository adds is the surface around
/// them, so a project reads as one thing rather than five.
///
/// When the repository was listed rather than taken whole, this is also where
/// a file's bytes are asked for: opening it fetches that one file and nothing
/// else.
class RepoFileStage extends StatefulWidget {
  const RepoFileStage({
    super.key,
    required this.entry,
    required this.theme,
    this.editable = false,
    this.editingSource = false,
    this.onEditingSourceChanged,
    this.fetcher,
  });

  final RepoEntry entry;
  final RepoTheme theme;

  /// Whether writing to the file is allowed. Source opens ready to type;
  /// rendered kinds need [editingSource] as well.
  final bool editable;

  /// Whether a rendered kind is showing its source for editing.
  final bool editingSource;
  final ValueChanged<Map<String, dynamic>>? onEditingSourceChanged;

  /// Fetches the file when the repository keeps its contents remote. Null when
  /// the whole project is already on disk.
  final RepoFileFetcher? fetcher;

  /// Whether this file can be written to at all.
  ///
  /// A file kept in the cloud is read through a URL, and a page is edited in
  /// its own editor rather than as source.
  static bool supportsEditing(RepoEntry entry) =>
      entry.isLocalFile && entry.kind != RepoEntryKind.page;

  /// Whether editing this file means switching it out of a rendered preview.
  static bool needsSourceToggle(RepoEntry entry) {
    final kind = filePreviewKindFromName(entry.name);
    return kind != null && kind.supportsSourceEditing;
  }

  @override
  State<RepoFileStage> createState() => _RepoFileStageState();
}

class _RepoFileStageState extends State<RepoFileStage> {
  bool fetching = false;
  bool unavailable = false;

  @override
  void initState() {
    super.initState();
    _ensureFetched();
  }

  @override
  void didUpdateWidget(covariant RepoFileStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.entry.id != widget.entry.id) {
      unavailable = false;
      _ensureFetched();
    }
  }

  /// Both callers are followed by a build, so the flags are set directly and
  /// only the answer that arrives later needs [setState].
  void _ensureFetched() {
    final fetcher = widget.fetcher;
    final entry = widget.entry;
    fetching = false;
    if (fetcher == null ||
        entry.kind == RepoEntryKind.page ||
        fetcher.hasLocal(entry)) {
      return;
    }
    if (!fetcher.canFetch(entry)) {
      unavailable = true;
      return;
    }
    fetching = true;
    unawaited(
      fetcher.ensureLocal(entry).then((path) {
        if (!mounted) {
          return;
        }
        setState(() {
          fetching = false;
          unavailable = path == null;
        });
      }),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entry = widget.entry;
    final theme = widget.theme;
    final view = entry.view;

    if (entry.kind == RepoEntryKind.page) {
      return MultiBlocProvider(
        key: ValueKey('repo-page-${view.id}'),
        providers: [
          BlocProvider<ViewInfoBloc>(
            create: (_) =>
                ViewInfoBloc(view: view)..add(const ViewInfoEvent.started()),
          ),
          BlocProvider<PageAccessLevelBloc>(
            create: (_) => PageAccessLevelBloc(view: view)
              ..add(const PageAccessLevelEvent.initial()),
          ),
        ],
        child: DocumentPage(
          key: ValueKey('repo-document-${view.id}'),
          view: view,
          onDeleted: () {},
          tabs: const [
            PickerTabType.emoji,
            PickerTabType.icon,
            PickerTabType.custom,
          ],
        ),
      );
    }

    if (fetching) {
      return _RepoFileFetching(theme: theme);
    }
    if (unavailable || !entry.isLocalFile) {
      return _RepoFileUnavailable(theme: theme);
    }
    final file = File(entry.storageUrl);

    if (imgExtensionRegex.hasMatch(entry.name)) {
      return _RepoImageStage(file: file, theme: theme);
    }

    final kind = filePreviewKindFromName(entry.name);
    if (kind == FilePreviewKind.pdf) {
      return PdfPreview(
        key: ValueKey('repo-pdf-${view.id}'),
        file: file,
        name: entry.name,
        bare: true,
        editable: widget.editable,
        metadata: const {},
        onMetadataChanged: (_) {},
      );
    }
    if (kind == null) {
      return _RepoFileUnavailable(theme: theme);
    }
    return FilePreview(
      // Switching between the preview and the source must rebuild the
      // renderer, not reuse it with a stale mode.
      key: ValueKey('repo-file-${view.id}-${widget.editingSource}'),
      file: file,
      name: entry.name,
      kind: kind,
      bare: true,
      editable: widget.editable,
      metadata: {if (widget.editingSource) filePreviewEditModeKey: true},
      onMetadataChanged: widget.onEditingSourceChanged ?? (_) {},
    );
  }
}

class _RepoFileFetching extends StatelessWidget {
  const _RepoFileFetching({required this.theme});

  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2),
          ),
          const SizedBox(height: 12),
          Text(
            LocaleKeys.collections_repository_fetchingFile.tr(),
            style: theme.rowLabel.copyWith(color: theme.textFaint),
          ),
        ],
      ),
    );
  }
}

class _RepoImageStage extends StatelessWidget {
  const _RepoImageStage({required this.file, required this.theme});

  final File file;
  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: theme.sunken,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: InteractiveViewer(
            maxScale: 6,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(RepoMetrics.controlRadius),
              child: Image.file(
                file,
                fit: BoxFit.scaleDown,
                errorBuilder: (_, __, ___) => _RepoFileUnavailable(
                  theme: theme,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RepoFileUnavailable extends StatelessWidget {
  const _RepoFileUnavailable({required this.theme});

  final RepoTheme theme;

  @override
  Widget build(BuildContext context) {
    return RepoEmptyState(
      theme: theme,
      icon: Icons.help_outline_rounded,
      title: LocaleKeys.collections_repository_unreadable.tr(),
      description: LocaleKeys.collections_repository_selectFileDescription.tr(),
    );
  }
}

/// A run of source around one declaration, so a symbol can be read without
/// opening its file.
class RepoSourceExcerpt extends StatelessWidget {
  const RepoSourceExcerpt({
    super.key,
    required this.source,
    required this.line,
    required this.theme,
    this.contextLines = 4,
  });

  final String source;

  /// 1-based line the excerpt is centred on.
  final int line;
  final RepoTheme theme;

  /// How many lines to show either side.
  final int contextLines;

  @override
  Widget build(BuildContext context) {
    final lines = source.split('\n');
    final start = (line - 1 - contextLines).clamp(0, lines.length);
    final end = (line + contextLines).clamp(0, lines.length);
    final gutterWidth = '$end'.length * 8.0 + 10;
    return Container(
      decoration: BoxDecoration(
        color: theme.sunken,
        borderRadius: BorderRadius.circular(RepoMetrics.panelRadius),
      ),
      clipBehavior: Clip.antiAlias,
      padding: const EdgeInsets.symmetric(vertical: RepoMetrics.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var index = start; index < end; index++)
            _ExcerptLine(
              theme: theme,
              number: index + 1,
              text: lines[index],
              gutterWidth: gutterWidth,
              highlighted: index == line - 1,
            ),
        ],
      ),
    );
  }
}

class _ExcerptLine extends StatelessWidget {
  const _ExcerptLine({
    required this.theme,
    required this.number,
    required this.text,
    required this.gutterWidth,
    required this.highlighted,
  });

  final RepoTheme theme;
  final int number;
  final String text;
  final double gutterWidth;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        if (highlighted)
          Positioned.fill(
            child: ColoredBox(color: theme.accent.withValues(alpha: 0.09)),
          ),
        if (highlighted)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            child: Container(width: 2, color: theme.accent),
          ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 1),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                width: gutterWidth,
                child: Text(
                  '$number',
                  textAlign: TextAlign.right,
                  style: codeUiTextStyle(
                    color: highlighted ? theme.accent : theme.textFaint,
                    fontSize: RepoMetrics.codeSize - 1,
                    fontWeight: FontWeight.w400,
                  ).copyWith(height: RepoMetrics.codeLineHeight),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  text.replaceAll('\t', '    '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: codeUiTextStyle(
                    color: highlighted ? theme.textStrong : theme.textBody,
                    fontSize: RepoMetrics.codeSize,
                    fontWeight: FontWeight.w400,
                  ).copyWith(height: RepoMetrics.codeLineHeight),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
