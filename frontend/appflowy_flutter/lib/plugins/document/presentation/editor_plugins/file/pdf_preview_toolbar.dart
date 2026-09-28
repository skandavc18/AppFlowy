import 'dart:math' as math;

import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/document_viewer/document_viewer.dart';
import 'package:appflowy/shared/document_viewer/file_action_band.dart';
import 'package:appflowy/shared/find_replace/find_replace.dart';
import 'package:appflowy/shared/preview_toolbar.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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
    this.searchEnabled = true,
    this.searchTapRegionGroupId,
    this.fileActions,
  });

  final String title;
  final int currentPage;
  final int pageCount;
  final double zoom;
  final bool ready;
  final bool showThumbnails;
  final bool showOutline;
  final bool searchVisible;
  final bool searchEnabled;
  final Object? searchTapRegionGroupId;
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

  /// Full-screen file actions. Standalone hosts supply their retained actions
  /// through the existing toolbar builder instead, never a second row.
  final Widget? fileActions;

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
    final host = !isFullscreen && showDocumentTitle
        ? StandaloneFileScope.forName(context, title)
        : null;
    if (host != null) {
      return StandaloneFileHeaderSlot(
        controller: host.chrome,
        controls: StandaloneFileHeader(
          responsiveToolbar: true,
          toolbarBuilder: (context, fileActions) =>
              _buildControls(context, fileActions: fileActions),
          keepActionsVisible: searchVisible,
        ),
      );
    }
    final controls = FileActionBand(
      scrollKey: const ValueKey('pdf-toolbar-scroll'),
      responsive: true,
      padding: EdgeInsets.only(
        top: fileActions == null
            ? 0
            : MediaQuery.textScalerOf(context).scale(10) * 1.2 + 10,
      ),
      builder: (context) => _buildControls(context, fileActions: fileActions),
    );
    if (isFullscreen) {
      return DocumentViewportBar(
        key: const ValueKey('pdf-fullscreen-chrome'),
        background: palette.canvas,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    key: const ValueKey('pdf-fullscreen-title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: palette.textPrimary,
                        ),
                  ),
                ),
                WorkspaceControlButton(
                  key: const ValueKey('pdf-fullscreen-close'),
                  icon: Icons.close_rounded,
                  tooltip: 'Exit full screen (Esc)',
                  onPressed: onFullscreen,
                ),
              ],
            ),
            controls,
          ],
        ),
      );
    }
    return showDocumentTitle
        ? DocumentViewportHeader(
            background: palette.canvas,
            identity: DocumentIdentity(
              title: title,
              icon: Icons.picture_as_pdf_rounded,
              subtitle: subtitle,
            ),
            // Let the shared header measure real tools, not the full-width
            // overflow viewport used by fullscreen/title-less hosts.
            toolbar: Padding(
              padding: EdgeInsets.only(
                top: fileActions == null
                    ? 0
                    : MediaQuery.textScalerOf(context).scale(10) * 1.2 + 10,
              ),
              child: _buildControls(context, fileActions: fileActions),
            ),
          )
        : DocumentViewportBar(
            background: palette.canvas,
            child: PreviewToolbar(child: controls),
          );
  }

  Widget _buildControls(BuildContext context, {Widget? fileActions}) {
    final palette = PdfPreviewPalette.of(context);
    // Real groups wrap at the supplied pane width. No breakpoint hides tools
    // or reparents the focused page field, including at large text scales.
    return Wrap(
      key: const ValueKey('pdf-toolbar-controls'),
      alignment: fileActionRunAlignment(context),
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: 4,
      children: [
        _ToolbarGroup(
          children: [
            WorkspaceControlButton(
              tooltip: showThumbnails
                  ? 'Hide page thumbnails'
                  : 'Show page thumbnails',
              onPressed: ready ? onToggleThumbnails : null,
              selected: showThumbnails,
              icon: Icons.view_sidebar_rounded,
            ),
            WorkspaceControlButton(
              tooltip: showOutline
                  ? 'Hide document outline'
                  : 'Show document outline',
              onPressed: ready ? onToggleOutline : null,
              selected: showOutline,
              icon: Icons.account_tree_rounded,
            ),
          ],
        ),
        const SizedBox(width: 6),
        _ToolbarGroup(
          accented: true,
          children: [
            WorkspaceControlButton(
              tooltip: 'Previous page (Page Up)',
              onPressed: onPreviousPage,
              icon: Icons.keyboard_arrow_up_rounded,
              foregroundColor: palette.accent,
              iconRole: WorkspaceGlyphRole.standard,
            ),
            PdfPageNumberField(
              page: currentPage,
              pageCount: pageCount,
              enabled: ready,
              onSubmitted: onPageSubmitted,
            ),
            WorkspaceControlButton(
              tooltip: 'Next page (Page Down)',
              onPressed: onNextPage,
              icon: Icons.keyboard_arrow_down_rounded,
              foregroundColor: palette.accent,
              iconRole: WorkspaceGlyphRole.standard,
            ),
          ],
        ),
        const SizedBox(width: 6),
        _ToolbarGroup(
          children: [
            WorkspaceControlButton(
              tooltip: 'Zoom out (Ctrl/Cmd −)',
              onPressed: onZoomOut,
              icon: Icons.remove_rounded,
            ),
            _ZoomLabel(zoom: zoom),
            WorkspaceControlButton(
              tooltip: 'Zoom in (Ctrl/Cmd +)',
              onPressed: onZoomIn,
              icon: Icons.add_rounded,
            ),
            DocumentViewportFitButton(
              tooltip: 'Fit whole page',
              glyphName: 'fit-page',
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
        const SizedBox(width: 6),
        _ToolbarGroup(
          children: [
            TapRegion(
              enabled: searchTapRegionGroupId != null,
              groupId: searchTapRegionGroupId,
              child: WorkspaceControlButton(
                tooltip: 'Search document (Ctrl/Cmd F)',
                onPressed: ready && searchEnabled ? onToggleSearch : null,
                selected: searchVisible,
                icon: Icons.search_rounded,
              ),
            ),
            WorkspaceControlButton(
              tooltip: 'Rotate clockwise',
              onPressed: onRotate,
              icon: Icons.rotate_90_degrees_cw_rounded,
            ),
            WorkspaceControlButton(
              tooltip: 'Download PDF',
              onPressed: onDownload,
              icon: Icons.download_rounded,
            ),
            WorkspaceControlButton(
              tooltip: 'Print PDF',
              onPressed: onPrint,
              icon: Icons.print_rounded,
            ),
            if (!isFullscreen)
              WorkspaceControlButton(
                tooltip: 'Open in full screen',
                onPressed: onFullscreen,
                icon: Icons.open_in_full_rounded,
              ),
            if (viewMenu != null) viewMenu!,
            overflow,
            if (fileActions != null) fileActions,
          ],
        ),
      ],
    );
  }
}

class PdfSearchToolbar extends StatefulWidget {
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
    this.onRetryOcr,
    this.onCopyMatch,
    this.onTapOutside,
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

  /// Whether local OCR results supplement the document's native text layer.
  final bool ocrEnabled;
  final VoidCallback? onToggleOcr;
  final VoidCallback? onRetryOcr;
  final VoidCallback? onCopyMatch;

  /// Dismiss without restoring focus: the same click may focus another viewer.
  final TapRegionCallback? onTapOutside;

  /// Replaces the match count while there is something more useful to say,
  /// such as how far the page scan has got.
  final String? statusOverride;

  @override
  State<PdfSearchToolbar> createState() => _PdfSearchToolbarState();
}

class _PdfSearchToolbarState extends State<PdfSearchToolbar> {
  late String _query;

  @override
  void initState() {
    super.initState();
    _query = widget.controller.text;
    widget.controller.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant PdfSearchToolbar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      _query = widget.controller.text;
      widget.controller.addListener(_changed);
    }
  }

  void _changed() {
    final query = widget.controller.text;
    if (_query == query) return; // Selection/IME range changes are not queries.
    _query = query;
    widget.onChanged(query);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    // Ordinary result announcements belong to the shared bar. Only PDF/OCR
    // progress and extraction failures need a supplemental live region.
    final resultLabel = widget.statusOverride;
    return TextFieldTapRegion(
      child: TapRegion(
        groupId: widget.controller,
        onTapOutside: widget.onTapOutside,
        child: DocumentViewportBar(
          background: palette.canvas,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(maxWidth: FindBarMetrics.maxWidth),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  CallbackShortcuts(
                    bindings: {
                      const SingleActivator(
                        LogicalKeyboardKey.enter,
                        shift: true,
                      ): () {
                        widget.onPrevious?.call();
                        widget.focusNode.requestFocus();
                      },
                    },
                    child: FindReplaceBar(
                      key: const ValueKey('pdf-search-field'),
                      findController: widget.controller,
                      findFocusNode: widget.focusNode,
                      options: widget.options,
                      onOptionsChanged: widget.onOptionsChanged ?? (_) {},
                      matchCount: widget.matchCount,
                      currentMatch: widget.currentMatch,
                      onPrevious: widget.onPrevious,
                      onNext: widget.onNext,
                      onClose: widget.onClose,
                      queryInvalid: widget.queryInvalid,
                      busy: widget.isSearching,
                      hintText: 'Search in document…',
                      autofocus: false,
                      // The outer group also contains the PDF's OCR controls.
                      dismissOnTapOutside: false,
                    ),
                  ),
                  Row(
                    children: [
                      Expanded(
                        child: Semantics(
                          container: true,
                          liveRegion: resultLabel != null,
                          label: resultLabel == null
                              ? null
                              : 'PDF search results: $resultLabel',
                          excludeSemantics: resultLabel != null,
                          child: Text(
                            widget.statusOverride ??
                                (widget.controller.text.isEmpty
                                    ? 'Type to search'
                                    : ''),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: palette.textSecondary,
                                      fontSize: 11,
                                    ),
                          ),
                        ),
                      ),
                      if (widget.onToggleOcr != null)
                        WorkspaceControlButton(
                          key: const ValueKey('pdf-search-ocr'),
                          tooltip: widget.ocrEnabled
                              ? 'Stop including scanned pages (local OCR)'
                              : 'Include scanned pages (local OCR)',
                          onPressed: widget.onToggleOcr,
                          selected: widget.ocrEnabled,
                          icon: Icons.document_scanner_rounded,
                        ),
                      if (widget.onRetryOcr != null)
                        WorkspaceControlButton(
                          key: const ValueKey('pdf-search-ocr-retry'),
                          tooltip: 'Retry or resume local OCR',
                          onPressed: widget.onRetryOcr,
                          icon: Icons.refresh_rounded,
                        ),
                      if (widget.onCopyMatch != null)
                        WorkspaceControlButton(
                          key: const ValueKey('pdf-search-copy-match'),
                          tooltip: 'Copy current OCR match',
                          onPressed: widget.onCopyMatch,
                          icon: Icons.content_copy_rounded,
                        ),
                    ],
                  ),
                ],
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
        math.max(1.0, MediaQuery.textScalerOf(context).scale(12) / 12);
    final fieldWidth = (digits * 8.0 + 16).clamp(30.0, 50.0) * scale;
    final face =
        (Theme.of(context).textTheme.bodyMedium ?? const TextStyle()).copyWith(
      color: palette.textPrimary,
      fontSize: 12,
      height: 1,
      fontWeight: FontWeight.w500,
      fontVariations: const [FontVariation.weight(550)],
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final strut =
        StrutStyle.fromTextStyle(face, height: 1, forceStrutHeight: true);

    return Semantics(
      label: 'Current PDF page, ${widget.page} of $count',
      textField: true,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: fieldWidth,
            height: 28 * scale,
            // InputDecorator measures its own container height even under a
            // tight parent. Center that intrinsic field in the navigation
            // slot, not just its baseline inside the smaller decoration.
            child: Center(
              child: TextField(
                key: const ValueKey('pdf-page-number-field'),
                controller: controller,
                focusNode: focusNode,
                enabled: widget.enabled,
                textAlign: TextAlign.center,
                textAlignVertical: TextAlignVertical.center,
                strutStyle: strut,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.go,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                onTap: controller.selectAll,
                onSubmitted: _submit,
                style: face,
                decoration: InputDecoration(
                  isDense: true,
                  isCollapsed: true,
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
          ),
          const SizedBox(width: 5),
          Text(
            '/ $count',
            strutStyle: strut,
            style: face.copyWith(color: palette.textSecondary),
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
  const _ToolbarGroup({required this.children, this.accented = false});

  final List<Widget> children;
  final bool accented;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: Color.alphaBlend(
          palette.accent.withValues(alpha: accented ? 0.13 : 0.045),
          palette.chrome,
        ),
        borderRadius: BorderRadius.circular(PdfPreviewGeometry.toolbarRadius),
        border: Border.all(
          color: palette.accent.withValues(alpha: accented ? 0.22 : 0.08),
        ),
      ),
      child: Wrap(
        alignment: fileActionRunAlignment(context),
        crossAxisAlignment: WrapCrossAlignment.center,
        runSpacing: 1,
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
