import 'dart:io';
import 'dart:math' as math;

import 'package:appflowy/features/page_access_level/logic/page_access_level_bloc.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_palette.dart';
import 'package:appflowy/plugins/document/document_page.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/pdf_preview_view_options.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/collections/book/book_chapter.dart';
import 'package:appflowy/workspace/application/collections/book/book_reading_state.dart';
import 'package:appflowy/workspace/application/view_info/view_info_bloc.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// One chapter, on the same sheet as every other chapter.
///
/// The reader never reimplements a renderer — a page keeps the document
/// editor, a PDF keeps pdfrx, markdown keeps its preview. What is uniform is
/// the sheet, the measure, the reading surface and the way pages turn: every
/// renderer is asked for its content alone and the reading theme is projected
/// onto it, so a PDF chapter and a markdown chapter read as two pages of one
/// book rather than two applications.
class BookChapterStage extends StatefulWidget {
  const BookChapterStage({
    super.key,
    required this.chapter,
    required this.palette,
    required this.settings,
    required this.onProgress,
    required this.onReachedEnd,
  });

  final BookChapter chapter;
  final BookReaderPalette palette;
  final BookReaderSettings settings;
  final ValueChanged<double> onProgress;

  /// Fired once the reader has run out of chapter, so the book can carry on.
  final VoidCallback onReachedEnd;

  @override
  State<BookChapterStage> createState() => _BookChapterStageState();
}

class _BookChapterStageState extends State<BookChapterStage> {
  bool reportedEnd = false;

  @override
  void didUpdateWidget(covariant BookChapterStage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.chapter.id != widget.chapter.id) {
      reportedEnd = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = widget.palette;
    final media = MediaQuery.of(context);

    return Theme(
      data: palette.themeFor(Theme.of(context)),
      child: MediaQuery(
        data: media.copyWith(
          textScaler: TextScaler.linear(widget.settings.fontScale),
        ),
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (notification) {
            _report(notification.metrics);
            return false;
          },
          child: NotificationListener<ScrollNotification>(
            onNotification: (notification) {
              _report(notification.metrics);
              return false;
            },
            child: BookPageSheet(
              palette: palette,
              measure: widget.settings.measure,
              child: _buildRenderer(),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildRenderer() {
    final view = widget.chapter.view;
    if (widget.chapter.kind == BookChapterKind.page) {
      return MultiBlocProvider(
        key: ValueKey('book-page-${view.id}'),
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
          key: ValueKey('book-document-${view.id}'),
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

    final path = view.workspaceItem?.storageUrl;
    if (path == null || path.isEmpty) {
      return _BookChapterUnavailable(palette: widget.palette);
    }
    final file = File(path);

    if (imgExtensionRegex.hasMatch(view.name)) {
      return _BookImagePage(file: file, palette: widget.palette);
    }

    final kind = filePreviewKindFromName(view.name);
    if (kind == FilePreviewKind.pdf) {
      return PdfPreview(
        key: ValueKey('book-pdf-${view.id}'),
        file: file,
        name: view.name,
        bare: true,
        editable: false,
        metadata: _pdfMetadata,
        onMetadataChanged: (_) {},
      );
    }
    if (kind == null) {
      return _BookChapterUnavailable(palette: widget.palette);
    }
    return FilePreview(
      key: ValueKey('book-file-${view.id}'),
      file: file,
      name: view.name,
      kind: kind,
      bare: true,
      editable: false,
      metadata: const {},
      onMetadataChanged: (_) {},
    );
  }

  /// The PDF viewer already knows how to lay pages out and turn them, so the
  /// book's flow is handed straight to it rather than reinvented.
  Map<String, dynamic> get _pdfMetadata => {
        'layoutMode': switch (widget.settings.flow) {
          BookReaderFlow.continuous => PdfPageLayoutMode.continuous.name,
          BookReaderFlow.paged => PdfPageLayoutMode.pageBreak.name,
          BookReaderFlow.horizontal => PdfPageLayoutMode.horizontal.name,
        },
        'pageTransition': switch (widget.settings.transition) {
          BookPageTransition.none => PdfPageTransition.none.name,
          BookPageTransition.fade => PdfPageTransition.fade.name,
          BookPageTransition.slide => PdfPageTransition.slide.name,
          BookPageTransition.curl => PdfPageTransition.flip.name,
        },
        'autoHideToolbar': false,
      };

  void _report(ScrollMetrics metrics) {
    if (metrics.axis != Axis.vertical || !metrics.hasContentDimensions) {
      return;
    }
    final extent = metrics.maxScrollExtent;
    final value = extent <= 0 ? 1.0 : (metrics.pixels / extent).clamp(0.0, 1.0);
    widget.onProgress(value);
    // A chapter that never scrolls is finished the moment it is laid out, so
    // only an overscroll past a real end counts as "read on".
    if (extent > 0 && metrics.pixels > extent + 24 && !reportedEnd) {
      reportedEnd = true;
      widget.onReachedEnd();
    }
  }
}

/// The sheet every chapter is printed on.
class BookPageSheet extends StatelessWidget {
  const BookPageSheet({
    super.key,
    required this.palette,
    required this.measure,
    required this.child,
  });

  final BookReaderPalette palette;
  final BookReaderMeasure measure;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final margin =
            constraints.maxWidth < 640 ? 0.0 : BookReaderMetrics.pageMargin;
        final available = constraints.maxWidth - margin * 2;
        final target = measure.maxWidth;
        final width = target == null ? available : math.min(target, available);
        return Center(
          child: Padding(
            padding: EdgeInsets.symmetric(
              horizontal: margin,
              vertical: margin > 0 ? 12 : 0,
            ),
            child: SizedBox(
              width: math.max(width, 0),
              height: constraints.maxHeight - (margin > 0 ? 24 : 0),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: palette.page,
                  borderRadius:
                      BorderRadius.circular(BookReaderMetrics.pageRadius),
                  boxShadow: margin == 0
                      ? null
                      : [
                          BoxShadow(
                            color: palette.shadow,
                            blurRadius: 22,
                            offset: const Offset(0, 8),
                            spreadRadius: -8,
                          ),
                          BoxShadow(
                            color: palette.shadow.withValues(alpha: 0.5),
                            blurRadius: 2,
                            offset: const Offset(0, 1),
                          ),
                        ],
                ),
                child: ClipRRect(
                  borderRadius:
                      BorderRadius.circular(BookReaderMetrics.pageRadius),
                  child: child,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BookImagePage extends StatelessWidget {
  const _BookImagePage({required this.file, required this.palette});

  final File file;
  final BookReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Center(
        child: Image.file(
          file,
          fit: BoxFit.scaleDown,
          errorBuilder: (context, _, __) =>
              _BookChapterUnavailable(palette: palette),
        ),
      ),
    );
  }
}

class _BookChapterUnavailable extends StatelessWidget {
  const _BookChapterUnavailable({required this.palette});

  final BookReaderPalette palette;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Icon(
        Icons.remove_circle_outline_rounded,
        size: 26,
        color: palette.inkFaint,
      ),
    );
  }
}
