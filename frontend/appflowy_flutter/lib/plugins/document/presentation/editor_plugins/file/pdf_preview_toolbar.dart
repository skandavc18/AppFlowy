import 'dart:math' as math;

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:easy_localization/easy_localization.dart';
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
    this.subtitle,
    this.onActualSize,
    this.onMenuVisibilityChanged,
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
  final VoidCallback? onActualSize;
  final VoidCallback onToggleSearch;
  final VoidCallback? onRotate;
  final VoidCallback? onDownload;
  final VoidCallback? onPrint;
  final VoidCallback onFullscreen;
  final Widget overflow;

  /// Fullscreen hosts also have an independent idle timer to keep alive.
  final ValueChanged<bool>? onMenuVisibilityChanged;

  /// Page layout, page animation and toolbar auto-hide live here.
  final Widget? viewMenu;

  /// Hidden when the shared document header already names the file.
  final bool showDocumentTitle;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    final controls = LayoutBuilder(
      builder: (context, constraints) {
        final textScale =
            math.max(1.0, MediaQuery.textScalerOf(context).scale(12) / 12);
        final available = constraints.maxWidth / textScale;
        final showOutlineButton = available >= 500;
        final showZoom = available >= 640;
        final showDocumentActions = available >= 720;

        return SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            // Keep every essential action reachable even in a split pane.
            width: math.max(constraints.maxWidth, 340 * textScale),
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
                  const DocumentViewportSeparator(),
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
                      const SizedBox(width: 4),
                      DocumentViewportFitButton(
                        tooltip: 'Fit whole page',
                        onPressed: onFitPage,
                        options: AppMenuIconButton(
                          key: const ValueKey('pdf-fit-options'),
                          icon: Icons.keyboard_arrow_down_rounded,
                          tooltip: 'Fit options',
                          size: 24,
                          iconSize: 15,
                          radius: 7,
                          iconColor: palette.icon,
                          enabled: ready,
                          onVisibilityChanged: onMenuVisibilityChanged,
                          entries: () => [
                            AppMenuItem(
                              label: 'Fit whole page',
                              icon: Icons.crop_free_rounded,
                              shortcut: 'Ctrl/Cmd 0',
                              enabled: onFitPage != null,
                              onSelected: onFitPage,
                            ),
                            AppMenuItem(
                              label: 'Fit to width',
                              icon: Icons.width_wide_rounded,
                              enabled: onFitWidth != null,
                              onSelected: onFitWidth,
                            ),
                            if (onActualSize != null) ...[
                              const AppMenuSeparator(),
                              AppMenuItem(
                                label: 'Actual size',
                                shortcut: '100%',
                                onSelected: onActualSize,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
                const DocumentViewportSeparator(),
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
        );
      },
    );
    return showDocumentTitle
        ? DocumentViewportHeader(
            background: palette.canvas,
            identity: DocumentIdentity(
              title: title,
              icon: Icons.picture_as_pdf_rounded,
              subtitle: subtitle,
            ),
            toolbar: controls,
          )
        : DocumentViewportBar(
            background: palette.canvas,
            child: PreviewToolbar(child: controls),
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
    this.options = const FindOptions(),
    this.onOptionsChanged,
    this.queryInvalid = false,
    this.ocrEnabled = false,
    this.onToggleOcr,
    this.statusOverride,
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
  final FindOptions options;
  final ValueChanged<FindOptions>? onOptionsChanged;
  final bool queryInvalid;

  /// Whether the search is reading the pages themselves rather than the
  /// document's text layer.
  final bool ocrEnabled;
  final VoidCallback? onToggleOcr;

  /// Replaces the match count while there is something more useful to say,
  /// such as how far the page scan has got.
  final String? statusOverride;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    final resultLabel = statusOverride ??
        (controller.text.isEmpty
            ? 'Type to search'
            : queryInvalid
                ? LocaleKeys.findAndReplace_invalidRegex.tr()
                : matchCount == 0
                    ? isSearching
                        ? 'Searching…'
                        : 'No results'
                    : '$currentMatch of $matchCount');

    return DocumentViewportBar(
      background: palette.canvas,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final scale =
              math.max(1.0, MediaQuery.textScalerOf(context).scale(13) / 13);
          final available = constraints.maxWidth;
          final stacked = available < 720 * scale;
          final toolsWidth = stacked ? available : 400 * scale;
          return Wrap(
            spacing: 12,
            runSpacing: 4,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              SizedBox(
                width: stacked ? available : available - toolsWidth - 12,
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
                        onSubmitted: (_) {
                          onNext?.call();
                          focusNode.requestFocus();
                        },
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: palette.textPrimary,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                        decoration: InputDecoration(
                          isDense: true,
                          border: InputBorder.none,
                          filled: false,
                          hoverColor: Colors.transparent,
                          hintText: 'Search in document…',
                          hintStyle: TextStyle(
                            color: palette.textSecondary,
                            fontFamily: 'Inter',
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(
                width: toolsWidth,
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: SizedBox(
                    width: math.max(toolsWidth, 320 * scale),
                    child: Row(
                      children: [
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
                        if (onOptionsChanged != null) ...[
                          _PdfSearchToggle(
                            palette: palette,
                            label: 'Aa',
                            tooltip:
                                LocaleKeys.findAndReplace_caseSensitive.tr(),
                            selected: options.caseSensitive,
                            onPressed: () => onOptionsChanged!(
                              options.copyWith(
                                caseSensitive: !options.caseSensitive,
                              ),
                            ),
                          ),
                          _PdfSearchToggle(
                            palette: palette,
                            label: 'ab',
                            underlined: true,
                            tooltip: LocaleKeys.findAndReplace_wholeWord.tr(),
                            selected: options.wholeWord,
                            onPressed: () => onOptionsChanged!(
                              options.copyWith(wholeWord: !options.wholeWord),
                            ),
                          ),
                          _PdfSearchToggle(
                            palette: palette,
                            label: '.*',
                            tooltip: LocaleKeys.findAndReplace_useRegex.tr(),
                            selected: options.useRegex,
                            onPressed: () => onOptionsChanged!(
                              options.copyWith(useRegex: !options.useRegex),
                            ),
                          ),
                        ],
                        Expanded(
                          child: Semantics(
                            container: true,
                            liveRegion: true,
                            label: 'PDF search results: $resultLabel',
                            excludeSemantics: true,
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 7),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxWidth: 176),
                                child: Text(
                                  resultLabel,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: queryInvalid
                                        ? palette.accent
                                        : palette.textSecondary,
                                    fontFamily: 'Geist Mono',
                                    fontFamilyFallback: const [
                                      'RobotoMono',
                                      'monospace',
                                    ],
                                    fontSize: 10.5,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (onToggleOcr != null)
                          FilePreviewToolbarButton(
                            tooltip:
                                LocaleKeys.findAndReplace_scanPagesTooltip.tr(),
                            onPressed: onToggleOcr,
                            selected: ocrEnabled,
                            icon: Icons.document_scanner_rounded,
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
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PdfSearchToggle extends StatelessWidget {
  const _PdfSearchToggle({
    required this.palette,
    required this.label,
    required this.tooltip,
    required this.selected,
    required this.onPressed,
    this.underlined = false,
  });

  final PdfPreviewPalette palette;
  final String label;
  final String tooltip;
  final bool selected;
  final VoidCallback onPressed;
  final bool underlined;

  @override
  Widget build(BuildContext context) {
    final color = selected ? palette.accent : palette.icon;
    return Tooltip(
      message: tooltip,
      waitDuration: const Duration(milliseconds: 400),
      child: SizedBox.square(
        dimension: PdfPreviewGeometry.buttonSize,
        child: Material(
          color: selected
              ? palette.accent.withValues(alpha: 0.16)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            onTap: onPressed,
            borderRadius: BorderRadius.circular(6),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  height: 1,
                  fontWeight: FontWeight.w600,
                  color: color,
                  decoration: underlined
                      ? TextDecoration.underline
                      : TextDecoration.none,
                  decorationColor: color,
                ),
              ),
            ),
          ),
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
    final scale =
        math.max(1.0, MediaQuery.textScalerOf(context).scale(11) / 11);
    final fieldWidth = (digits * 8.0 + 16).clamp(30.0, 50.0) * scale;

    return Semantics(
      label: 'Current PDF page, ${widget.page} of $count',
      textField: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: fieldWidth,
            height: 28 * scale,
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
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: palette.textPrimary,
                fontSize: 12,
                fontWeight: FontWeight.w500,
                fontVariations: const [FontVariation.weight(550)],
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
                filled: true,
                fillColor: palette.control,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: palette.accent),
                ),
                disabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          const SizedBox(width: 5),
          Text(
            '/ $count',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: palette.textSecondary,
              fontSize: 12,
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
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 32),
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
      width:
          48 * math.max(1.0, MediaQuery.textScalerOf(context).scale(12) / 12),
      child: Text(
        '${(zoom * 100).round()}%',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
          color: palette.textSecondary,
          fontSize: 12,
          fontWeight: FontWeight.w500,
          fontVariations: const [FontVariation.weight(550)],
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
