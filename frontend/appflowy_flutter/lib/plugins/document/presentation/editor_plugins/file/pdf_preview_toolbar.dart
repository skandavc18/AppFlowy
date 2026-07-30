import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'file_preview_toolbar.dart';
import 'pdf_preview_theme.dart';

abstract final class PdfPreviewGeometry {
  static const toolbarHeight = 42.0;
  static const searchHeight = 40.0;
  static const toolbarRadius = 10.0;
  static const buttonSize = 28.0;
  static const iconSize = 16.0;
  static const blurSigma = 8.0;
}

class PdfPreviewToolbar extends StatelessWidget {
  const PdfPreviewToolbar({
    super.key,
    required this.title,
    required this.currentPage,
    required this.pageCount,
    required this.zoom,
    required this.ready,
    required this.showThumbnails,
    required this.showOutline,
    required this.searchVisible,
    required this.isFullscreen,
    required this.onToggleThumbnails,
    required this.onToggleOutline,
    required this.onPreviousPage,
    required this.onNextPage,
    required this.onPageSubmitted,
    required this.onZoomOut,
    required this.onZoomIn,
    required this.onFitWidth,
    required this.onFitPage,
    required this.onToggleSearch,
    required this.onRotate,
    required this.onDownload,
    required this.onPrint,
    required this.onFullscreen,
    required this.overflow,
    this.viewMenu,
    this.showDocumentTitle = true,
  });

  final String title;
  final int currentPage;
  final int pageCount;
  final double zoom;
  final bool ready;
  final bool showThumbnails;
  final bool showOutline;
  final bool searchVisible;
  final bool isFullscreen;
  final VoidCallback onToggleThumbnails;
  final VoidCallback onToggleOutline;
  final VoidCallback? onPreviousPage;
  final VoidCallback? onNextPage;
  final ValueChanged<int> onPageSubmitted;
  final VoidCallback? onZoomOut;
  final VoidCallback? onZoomIn;
  final VoidCallback? onFitWidth;
  final VoidCallback? onFitPage;
  final VoidCallback onToggleSearch;
  final VoidCallback? onRotate;
  final VoidCallback? onDownload;
  final VoidCallback? onPrint;
  final VoidCallback onFullscreen;
  final Widget overflow;

  /// Page layout, page animation and toolbar auto-hide live here.
  final Widget? viewMenu;

  /// Hidden when the shared document header already names the file.
  final bool showDocumentTitle;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final showTitle = showDocumentTitle && constraints.maxWidth >= 900;
        final showOutlineButton = constraints.maxWidth >= 520;
        final showZoom = constraints.maxWidth >= 650;
        final showDocumentActions = constraints.maxWidth >= 860;
        final radius = BorderRadius.circular(PdfPreviewGeometry.toolbarRadius);

        return Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 6),
          child: DecoratedBox(
            decoration: BoxDecoration(
              borderRadius: radius,
              boxShadow: [
                BoxShadow(
                  color: palette.chromeShadow.withValues(alpha: 0.12),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                  spreadRadius: -4,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: radius,
              child: BackdropFilter(
                filter: ImageFilter.blur(
                  sigmaX: PdfPreviewGeometry.blurSigma,
                  sigmaY: PdfPreviewGeometry.blurSigma,
                ),
                child: Container(
                  height: PdfPreviewGeometry.toolbarHeight,
                  padding: const EdgeInsets.symmetric(horizontal: 5),
                  decoration: BoxDecoration(
                    color: palette.chrome,
                    border: Border.all(color: palette.border, width: 0.5),
                    borderRadius: radius,
                  ),
                  child: Row(
                    children: [
                      _ToolbarGroup(
                        children: [
                          FilePreviewToolbarButton(
                            tooltip: showThumbnails
                                ? 'Hide page thumbnails'
                                : 'Show page thumbnails',
                            onPressed: onToggleThumbnails,
                            selected: showThumbnails,
                            icon: Icons.view_sidebar_rounded,
                          ),
                          if (showOutlineButton)
                            FilePreviewToolbarButton(
                              tooltip: showOutline
                                  ? 'Hide document outline'
                                  : 'Show document outline',
                              onPressed: onToggleOutline,
                              selected: showOutline,
                              icon: Icons.account_tree_rounded,
                            ),
                        ],
                      ),
                      if (showTitle) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.picture_as_pdf_rounded,
                          size: 15,
                          color: palette.icon,
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 190),
                            child: Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontFamily: 'Inter',
                                fontSize: 12.5,
                                fontWeight: FontWeight.w500,
                                letterSpacing: -0.1,
                              ).copyWith(color: palette.textPrimary),
                            ),
                          ),
                        ),
                      ],
                      const Spacer(),
                      _ToolbarGroup(
                        children: [
                          FilePreviewToolbarButton(
                            tooltip: 'Previous page (Page Up)',
                            onPressed: onPreviousPage,
                            icon: Icons.keyboard_arrow_up_rounded,
                          ),
                          PdfPageNumberField(
                            page: currentPage,
                            pageCount: pageCount,
                            enabled: ready,
                            onSubmitted: onPageSubmitted,
                          ),
                          FilePreviewToolbarButton(
                            tooltip: 'Next page (Page Down)',
                            onPressed: onNextPage,
                            icon: Icons.keyboard_arrow_down_rounded,
                          ),
                        ],
                      ),
                      if (showZoom) ...[
                        const SizedBox(width: 8),
                        _ToolbarGroup(
                          children: [
                            FilePreviewToolbarButton(
                              tooltip: 'Zoom out (Ctrl/Cmd −)',
                              onPressed: onZoomOut,
                              icon: Icons.remove_rounded,
                            ),
                            _ZoomLabel(zoom: zoom),
                            FilePreviewToolbarButton(
                              tooltip: 'Zoom in (Ctrl/Cmd +)',
                              onPressed: onZoomIn,
                              icon: Icons.add_rounded,
                            ),
                            FilePreviewToolbarButton(
                              tooltip: 'Fit to width',
                              onPressed: onFitWidth,
                              icon: Icons.fit_screen_rounded,
                            ),
                            FilePreviewToolbarButton(
                              tooltip: 'Fit whole page',
                              onPressed: onFitPage,
                              icon: Icons.fullscreen_exit_rounded,
                            ),
                          ],
                        ),
                      ],
                      const SizedBox(width: 8),
                      _ToolbarGroup(
                        children: [
                          FilePreviewToolbarButton(
                            tooltip: 'Search document (Ctrl/Cmd F)',
                            onPressed: onToggleSearch,
                            selected: searchVisible,
                            icon: Icons.search_rounded,
                          ),
                          if (showDocumentActions) ...[
                            FilePreviewToolbarButton(
                              tooltip: 'Rotate clockwise',
                              onPressed: onRotate,
                              icon: Icons.rotate_90_degrees_cw_rounded,
                            ),
                            FilePreviewToolbarButton(
                              tooltip: 'Download PDF',
                              onPressed: onDownload,
                              icon: Icons.download_rounded,
                            ),
                            FilePreviewToolbarButton(
                              tooltip: 'Print PDF',
                              onPressed: onPrint,
                              icon: Icons.print_rounded,
                            ),
                          ],
                          FilePreviewToolbarButton(
                            tooltip: isFullscreen
                                ? 'Exit full screen (Esc)'
                                : 'Open in full screen',
                            onPressed: onFullscreen,
                            icon: isFullscreen
                                ? Icons.close_fullscreen_rounded
                                : Icons.open_in_full_rounded,
                          ),
                          if (viewMenu != null) viewMenu!,
                          overflow,
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class PdfSearchToolbar extends StatelessWidget {
  const PdfSearchToolbar({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.currentMatch,
    required this.matchCount,
    required this.searchProgress,
    required this.isSearching,
    required this.onChanged,
    required this.onPrevious,
    required this.onNext,
    required this.onClose,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final int currentMatch;
  final int matchCount;
  final double? searchProgress;
  final bool isSearching;
  final ValueChanged<String> onChanged;
  final VoidCallback? onPrevious;
  final VoidCallback? onNext;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    final resultLabel = controller.text.isEmpty
        ? 'Type to search'
        : matchCount == 0
            ? isSearching
                ? 'Searching…'
                : 'No results'
            : '$currentMatch of $matchCount';

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
      child: Container(
        height: PdfPreviewGeometry.searchHeight,
        padding: const EdgeInsets.only(left: 10, right: 4),
        decoration: BoxDecoration(
          color: palette.chrome,
          borderRadius: BorderRadius.circular(PdfPreviewGeometry.toolbarRadius),
          border: Border.all(color: palette.border, width: 0.5),
          boxShadow: [
            BoxShadow(
              color: palette.chromeShadow.withValues(alpha: 0.1),
              blurRadius: 8,
              offset: const Offset(0, 3),
              spreadRadius: -3,
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(
              Icons.search_rounded,
              size: PdfPreviewGeometry.iconSize,
              color: palette.icon,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: const ValueKey('pdf-search-field'),
                controller: controller,
                focusNode: focusNode,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: (_) => onNext?.call(),
                style: TextStyle(
                  color: palette.textPrimary,
                  fontFamily: 'Inter',
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
                decoration: InputDecoration(
                  isDense: true,
                  border: InputBorder.none,
                  hintText: 'Search in document…',
                  hintStyle: TextStyle(
                    color: palette.textSecondary,
                    fontFamily: 'Inter',
                    fontSize: 13,
                  ),
                ),
              ),
            ),
            if (isSearching)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: SizedBox.square(
                  dimension: 14,
                  child: CircularProgressIndicator(
                    value: searchProgress,
                    strokeWidth: 1.5,
                    color: palette.accent,
                  ),
                ),
              ),
            Semantics(
              container: true,
              liveRegion: true,
              label: 'PDF search results: $resultLabel',
              excludeSemantics: true,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 7),
                child: Text(
                  resultLabel,
                  style: TextStyle(
                    color: palette.textSecondary,
                    fontFamily: 'Geist Mono',
                    fontFamilyFallback: const ['RobotoMono', 'monospace'],
                    fontSize: 10.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ),
            ),
            FilePreviewToolbarButton(
              tooltip: 'Previous match (Shift Enter)',
              onPressed: onPrevious,
              icon: Icons.keyboard_arrow_up_rounded,
            ),
            FilePreviewToolbarButton(
              tooltip: 'Next match (Enter)',
              onPressed: onNext,
              icon: Icons.keyboard_arrow_down_rounded,
            ),
            FilePreviewToolbarButton(
              tooltip: 'Close search (Esc)',
              onPressed: onClose,
              icon: Icons.close_rounded,
            ),
          ],
        ),
      ),
    );
  }
}

class PdfPageNumberField extends StatefulWidget {
  const PdfPageNumberField({
    super.key,
    required this.page,
    required this.pageCount,
    required this.enabled,
    required this.onSubmitted,
  });

  final int page;
  final int pageCount;
  final bool enabled;
  final ValueChanged<int> onSubmitted;

  @override
  State<PdfPageNumberField> createState() => _PdfPageNumberFieldState();
}

class _PdfPageNumberFieldState extends State<PdfPageNumberField> {
  late final TextEditingController controller =
      TextEditingController(text: '${widget.page}');
  final focusNode = FocusNode();

  @override
  void didUpdateWidget(covariant PdfPageNumberField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!focusNode.hasFocus && oldWidget.page != widget.page) {
      controller.text = '${widget.page}';
    }
  }

  @override
  void dispose() {
    controller.dispose();
    focusNode.dispose();
    super.dispose();
  }

  void _submit(String value) {
    final page = parsePdfPageNumber(value, widget.pageCount);
    if (page != null) {
      widget.onSubmitted(page);
      controller.text = '$page';
    } else {
      controller.text = '${widget.page}';
    }
    focusNode.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    final count = widget.pageCount > 0 ? widget.pageCount : 1;
    final digits = count.toString().length;
    final fieldWidth = (digits * 8.0 + 16).clamp(30.0, 50.0);

    return Semantics(
      label: 'Current PDF page, ${widget.page} of $count',
      textField: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: fieldWidth,
            height: 26,
            child: TextField(
              key: const ValueKey('pdf-page-number-field'),
              controller: controller,
              focusNode: focusNode,
              enabled: widget.enabled,
              textAlign: TextAlign.center,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.go,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              onTap: controller.selectAll,
              onSubmitted: _submit,
              style: TextStyle(
                color: palette.textPrimary,
                fontFamily: 'Geist Mono',
                fontFamilyFallback: const ['RobotoMono', 'monospace'],
                fontSize: 11,
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 6),
                filled: true,
                fillColor: palette.control,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: palette.border, width: 0.5),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: palette.accent),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: palette.border, width: 0.5),
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '/ $count',
            style: TextStyle(
              color: palette.textSecondary,
              fontFamily: 'Geist Mono',
              fontFamilyFallback: const ['RobotoMono', 'monospace'],
              fontSize: 10.5,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(width: 3),
        ],
      ),
    );
  }
}

@visibleForTesting
int? parsePdfPageNumber(String value, int pageCount) {
  final parsed = int.tryParse(value.trim());
  if (parsed == null || pageCount < 1) {
    return null;
  }
  return parsed.clamp(1, pageCount);
}

class _ToolbarGroup extends StatelessWidget {
  const _ToolbarGroup({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 1,
        children: children,
      ),
    );
  }
}

class _ZoomLabel extends StatelessWidget {
  const _ZoomLabel({required this.zoom});

  final double zoom;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return SizedBox(
      width: 40,
      child: Text(
        '${(zoom * 100).round()}%',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: palette.textSecondary,
          fontFamily: 'Geist Mono',
          fontFamilyFallback: const ['RobotoMono', 'monospace'],
          fontSize: 10.5,
          fontWeight: FontWeight.w500,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }
}

extension on TextEditingController {
  void selectAll() {
    selection = TextSelection(baseOffset: 0, extentOffset: text.length);
  }
}
