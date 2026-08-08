import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/code_block_chrome.dart';
import 'package:appflowy/workspace/application/providers/git/git_diff.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// The colours a diff is read in.
///
/// Derived from the palette rather than fixed, so a diff sits on the same
/// surface as everything else in paper, light and dark, and the two hues stay
/// legible against it instead of being the usual saturated green and red.
@immutable
class GitDiffPalette {
  const GitDiffPalette._({
    required this.addition,
    required this.deletion,
    required this.additionInk,
    required this.deletionInk,
    required this.gutter,
    required this.gutterInk,
    required this.hunk,
    required this.hunkInk,
    required this.text,
    required this.surface,
  });

  factory GitDiffPalette.of(BuildContext context, CollectionPalette palette) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final green = dark ? const Color(0xFF3FB950) : const Color(0xFF1A7F37);
    final red = dark ? const Color(0xFFF85149) : const Color(0xFFCF222E);
    return GitDiffPalette._(
      addition: green.withValues(alpha: dark ? 0.14 : 0.10),
      deletion: red.withValues(alpha: dark ? 0.14 : 0.09),
      additionInk: green,
      deletionInk: red,
      gutter: palette.surface,
      gutterInk: palette.textMuted,
      hunk: palette.accent.withValues(alpha: dark ? 0.13 : 0.09),
      hunkInk: palette.accent,
      text: palette.textPrimary,
      surface: palette.surface,
    );
  }

  final Color addition;
  final Color deletion;
  final Color additionInk;
  final Color deletionInk;
  final Color gutter;
  final Color gutterInk;
  final Color hunk;
  final Color hunkInk;
  final Color text;
  final Color surface;
}

/// One file's diff, rendered in the application's own code face.
///
/// It deliberately reuses [codeUiTextStyle] — the same face and size the code
/// viewer and the terminal use — so a diff and the file it came from are set
/// identically and nothing reads as a different application.
class GitDiffView extends StatelessWidget {
  const GitDiffView({
    super.key,
    required this.files,
    required this.palette,
    this.showFileHeaders = true,
  });

  final List<GitFileDiff> files;
  final CollectionPalette palette;
  final bool showFileHeaders;

  @override
  Widget build(BuildContext context) {
    if (files.isEmpty) {
      return Center(
        child: Text(
          LocaleKeys.providers_git_noDiff.tr(),
          style: TextStyle(color: palette.textMuted, fontSize: 12.5),
        ),
      );
    }

    final diffPalette = GitDiffPalette.of(context, palette);
    final mono = codeUiTextStyle(
      color: diffPalette.text,
      fontSize: 12,
      fontWeight: FontWeight.w400,
    ).copyWith(height: 1.55);

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 18),
      itemCount: files.length,
      itemBuilder: (context, index) => _FileDiff(
        file: files[index],
        palette: palette,
        diffPalette: diffPalette,
        mono: mono,
        showHeader: showFileHeaders,
      ),
    );
  }
}

class _FileDiff extends StatelessWidget {
  const _FileDiff({
    required this.file,
    required this.palette,
    required this.diffPalette,
    required this.mono,
    required this.showHeader,
  });

  final GitFileDiff file;
  final CollectionPalette palette;
  final GitDiffPalette diffPalette;
  final TextStyle mono;
  final bool showHeader;

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 10, 14, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text.rich(
                      TextSpan(
                        children: [
                          if (file.directory.isNotEmpty)
                            TextSpan(
                              text: '${file.directory}/',
                              style: TextStyle(color: palette.textMuted),
                            ),
                          TextSpan(
                            text: file.name,
                            style: TextStyle(
                              color: palette.textPrimary,
                              fontVariations: const [FontVariation.weight(600)],
                            ),
                          ),
                        ],
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 12.5),
                    ),
                  ),
                  _Count(
                    label: LocaleKeys.providers_git_linesAdded
                        .tr(args: ['${file.additions}']),
                    color: diffPalette.additionInk,
                  ),
                  const SizedBox(width: 8),
                  _Count(
                    label: LocaleKeys.providers_git_linesRemoved
                        .tr(args: ['${file.deletions}']),
                    color: diffPalette.deletionInk,
                  ),
                ],
              ),
            ),
          if (file.isBinary)
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 4, 14, 14),
              child: Text(
                LocaleKeys.providers_git_binaryFile.tr(),
                style: TextStyle(color: palette.textMuted, fontSize: 12),
              ),
            )
          else
            for (final hunk in file.hunks)
              for (final line in hunk.lines)
                _DiffLine(
                  line: line,
                  diffPalette: diffPalette,
                  mono: mono,
                ),
        ],
      );
}

class _DiffLine extends StatelessWidget {
  const _DiffLine({
    required this.line,
    required this.diffPalette,
    required this.mono,
  });

  final GitDiffLine line;
  final GitDiffPalette diffPalette;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) {
    final background = switch (line.kind) {
      GitDiffLineKind.addition => diffPalette.addition,
      GitDiffLineKind.deletion => diffPalette.deletion,
      GitDiffLineKind.hunkHeader => diffPalette.hunk,
      _ => Colors.transparent,
    };
    final ink = switch (line.kind) {
      GitDiffLineKind.hunkHeader => diffPalette.hunkInk,
      GitDiffLineKind.note => diffPalette.gutterInk,
      _ => diffPalette.text,
    };
    final marker = switch (line.kind) {
      GitDiffLineKind.addition => '+',
      GitDiffLineKind.deletion => '-',
      _ => ' ',
    };

    return ColoredBox(
      color: background,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Both line numbers, the way every code host shows them: the old on
          // the left, the new beside it, so a moved line is obvious.
          _Gutter(
            value: line.oldLineNumber,
            diffPalette: diffPalette,
            mono: mono,
          ),
          _Gutter(
            value: line.newLineNumber,
            diffPalette: diffPalette,
            mono: mono,
          ),
          SizedBox(
            width: 14,
            child: Text(
              marker,
              style: mono.copyWith(color: ink.withValues(alpha: 0.7)),
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: SelectableText(
                line.text.isEmpty ? ' ' : line.text,
                style: mono.copyWith(color: ink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _Gutter extends StatelessWidget {
  const _Gutter({
    required this.value,
    required this.diffPalette,
    required this.mono,
  });

  final int? value;
  final GitDiffPalette diffPalette;
  final TextStyle mono;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: 44,
        child: Padding(
          padding: const EdgeInsets.only(right: 8),
          child: Text(
            value == null ? '' : '$value',
            textAlign: TextAlign.right,
            style: mono.copyWith(
              color: diffPalette.gutterInk.withValues(alpha: 0.7),
            ),
          ),
        ),
      );
}

class _Count extends StatelessWidget {
  const _Count({required this.label, required this.color});

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) => Text(
        label,
        style: TextStyle(
          color: color,
          fontSize: 11.5,
          fontVariations: const [FontVariation.weight(600)],
        ),
      );
}
