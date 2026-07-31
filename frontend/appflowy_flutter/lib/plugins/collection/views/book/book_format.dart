import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

String bookThemeLabel(BookReaderTheme theme) => switch (theme) {
      BookReaderTheme.workspace =>
        LocaleKeys.collections_book_themes_workspace.tr(),
      BookReaderTheme.paper => LocaleKeys.collections_book_themes_paper.tr(),
      BookReaderTheme.sepia => LocaleKeys.collections_book_themes_sepia.tr(),
      BookReaderTheme.light => LocaleKeys.collections_book_themes_light.tr(),
      BookReaderTheme.dark => LocaleKeys.collections_book_themes_dark.tr(),
      BookReaderTheme.night => LocaleKeys.collections_book_themes_night.tr(),
    };

String bookFlowLabel(BookReaderFlow flow) => switch (flow) {
      BookReaderFlow.continuous =>
        LocaleKeys.collections_book_flows_continuous.tr(),
      BookReaderFlow.paged => LocaleKeys.collections_book_flows_paged.tr(),
      BookReaderFlow.horizontal =>
        LocaleKeys.collections_book_flows_horizontal.tr(),
    };

String bookMeasureLabel(BookReaderMeasure measure) => switch (measure) {
      BookReaderMeasure.narrow =>
        LocaleKeys.collections_book_measures_narrow.tr(),
      BookReaderMeasure.comfortable =>
        LocaleKeys.collections_book_measures_comfortable.tr(),
      BookReaderMeasure.wide => LocaleKeys.collections_book_measures_wide.tr(),
      BookReaderMeasure.full => LocaleKeys.collections_book_measures_full.tr(),
    };

String bookTransitionLabel(BookPageTransition transition) =>
    switch (transition) {
      BookPageTransition.none =>
        LocaleKeys.collections_book_transitions_none.tr(),
      BookPageTransition.fade =>
        LocaleKeys.collections_book_transitions_fade.tr(),
      BookPageTransition.slide =>
        LocaleKeys.collections_book_transitions_slide.tr(),
      BookPageTransition.curl =>
        LocaleKeys.collections_book_transitions_curl.tr(),
    };

String bookChapterTitle(BookChapter chapter) => chapter.name.trim().isEmpty
    ? LocaleKeys.collections_book_untitledChapter.tr()
    : chapter.name;

IconData bookChapterIcon(BookChapterKind kind) => switch (kind) {
      BookChapterKind.page => Icons.article_rounded,
      BookChapterKind.markdown => Icons.notes_rounded,
      BookChapterKind.html => Icons.language_rounded,
      BookChapterKind.pdf => Icons.picture_as_pdf_rounded,
      BookChapterKind.text => Icons.subject_rounded,
      BookChapterKind.code => Icons.code_rounded,
      BookChapterKind.part => Icons.folder_rounded,
      BookChapterKind.unsupported => Icons.help_outline_rounded,
    };

/// Reading time as a person would say it: "12 min", "3 h 40 min".
String formatReadingDuration(int seconds) {
  if (seconds < 60) {
    return '${seconds}s';
  }
  final minutes = seconds ~/ 60;
  if (minutes < 60) {
    return '$minutes min';
  }
  final hours = minutes ~/ 60;
  final remainder = minutes % 60;
  return remainder == 0 ? '$hours h' : '$hours h $remainder min';
}

Color bookNoteColor(BookNoteColor color, {required bool isDark}) =>
    switch (color) {
      BookNoteColor.yellow =>
        isDark ? const Color(0xFFC9A227) : const Color(0xFFE8B931),
      BookNoteColor.green =>
        isDark ? const Color(0xFF5FA771) : const Color(0xFF62B87A),
      BookNoteColor.blue =>
        isDark ? const Color(0xFF5C8DD6) : const Color(0xFF5B9BE0),
      BookNoteColor.pink =>
        isDark ? const Color(0xFFC66C90) : const Color(0xFFE1799E),
      BookNoteColor.purple =>
        isDark ? const Color(0xFF9070C9) : const Color(0xFFA07FDB),
    };

/// The tint a highlighted passage is washed with on the reading surface.
Color bookNoteWash(BookNoteColor color, BookReaderPalette palette) =>
    Color.alphaBlend(
      bookNoteColor(color, isDark: palette.theme.isDark)
          .withValues(alpha: palette.theme.isDark ? 0.20 : 0.16),
      palette.page,
    );
