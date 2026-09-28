import 'package:appflowy/shared/find_replace/text_find.dart';
import 'package:appflowy/shared/workspace_design.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/command_palette/workspace_content_search_controller.dart';
import 'package:flutter/material.dart';

/// The same literal matcher as the controller, over original-case plain text.
/// Unlike a regex split, this also styles a match covering the entire string.
TextSpan paletteMatchTextSpan({
  required BuildContext context,
  required String text,
  required String query,
  required TextStyle style,
}) {
  final needle = query.trim();
  final pattern = needle.length > WorkspaceContentSearchLimits.maxQueryLength
      ? null
      : buildFindPattern(needle, const FindOptions());
  if (pattern == null) return TextSpan(text: text, style: style);
  final palette = WorkspacePalette.of(context);
  final highlight = TextStyle(
    backgroundColor: workspaceGlyphAccent(context).withValues(
      alpha: palette.isDark ? 0.20 : 0.12,
    ),
  );
  final spans = <InlineSpan>[];
  var offset = 0;
  for (final match in pattern.allMatches(text).take(128)) {
    if (match.start > offset) {
      spans.add(TextSpan(text: text.substring(offset, match.start)));
    }
    spans.add(
      TextSpan(text: text.substring(match.start, match.end), style: highlight),
    );
    offset = match.end;
  }
  if (offset < text.length) spans.add(TextSpan(text: text.substring(offset)));
  return TextSpan(style: style, children: spans);
}

/// An authorized matching excerpt IS the content-mode preview. It deliberately
/// does not load a cover, create a document editor or mount a database plugin.
class SearchMatchContext extends StatelessWidget {
  const SearchMatchContext({
    super.key,
    required this.query,
    required this.snippet,
  });

  final String query;
  final String snippet;

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        primary: false,
        padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Matching page contents',
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
              ),
            ),
            const SizedBox(height: WorkspaceTokens.space3),
            Text.rich(
              key: const ValueKey('command-palette-match-excerpt'),
              paletteMatchTextSpan(
                context: context,
                text: snippet,
                query: query,
                style:
                    WorkspaceTypography.style(context, WorkspaceTextRole.body),
              ),
            ),
          ],
        ),
      );
}

class WorkspaceContentSearchStatusView extends StatelessWidget {
  const WorkspaceContentSearchStatusView({super.key, required this.state});

  final WorkspaceContentSearchState state;

  @override
  Widget build(BuildContext context) {
    final status = switch (state.status) {
      WorkspaceContentSearchStatus.idle =>
        'Search inside pages in this workspace.',
      WorkspaceContentSearchStatus.waitingForSource =>
        'Waiting for current-workspace pages…',
      WorkspaceContentSearchStatus.debouncing => 'Waiting for typing to pause…',
      WorkspaceContentSearchStatus.scanning =>
        'Scanning page contents · ${state.scannedPages}/${state.candidatePages} pages',
      WorkspaceContentSearchStatus.complete =>
        'Searched ${state.scannedPages} cached pages',
      WorkspaceContentSearchStatus.partial =>
        'Partial coverage · ${state.scannedPages}/${state.candidatePages} pages checked',
      WorkspaceContentSearchStatus.queryTooLong =>
        'Use at most ${WorkspaceContentSearchLimits.maxQueryLength} characters.',
    };
    return Padding(
      padding: const EdgeInsets.only(bottom: WorkspaceTokens.space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Semantics(
            liveRegion: true,
            child: Text(
              status,
              key: const ValueKey('command-palette-content-status'),
              style: WorkspaceTypography.style(
                context,
                WorkspaceTextRole.metadata,
              ),
            ),
          ),
          const SizedBox(height: WorkspaceTokens.space1),
          Text(
            state.timedOut
                ? 'A read timed out. Change the query or toggle Page contents to retry.'
                : 'Local page text, spreadsheet values and safe local text files. '
                    'PDF, Office, media, linked sources and dashboard/canvas configurations '
                    'are not searched.',
            style:
                WorkspaceTypography.style(context, WorkspaceTextRole.caption),
          ),
        ],
      ),
    );
  }
}

class WorkspaceContentSearchEmpty extends StatelessWidget {
  const WorkspaceContentSearchEmpty({super.key, required this.state});

  final WorkspaceContentSearchState state;

  @override
  Widget build(BuildContext context) {
    final message = switch (state.status) {
      WorkspaceContentSearchStatus.idle =>
        'Type a word or phrase to search page contents.',
      WorkspaceContentSearchStatus.waitingForSource =>
        'Page contents are not available yet.',
      WorkspaceContentSearchStatus.debouncing ||
      WorkspaceContentSearchStatus.scanning =>
        'Scanning for matching page contents…',
      WorkspaceContentSearchStatus.partial =>
        'No matches in the scanned content. Coverage is partial.',
      WorkspaceContentSearchStatus.complete =>
        'No matches in the scanned page contents.',
      WorkspaceContentSearchStatus.queryTooLong =>
        'Shorten the query to search page contents.',
    };
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(WorkspaceTokens.space6),
        child: Text(
          message,
          textAlign: TextAlign.center,
          style: WorkspaceTypography.style(context, WorkspaceTextRole.body),
        ),
      ),
    );
  }
}
