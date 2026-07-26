import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'pdf_preview_theme.dart';

/// How the pages of a PDF are arranged on the canvas.
enum PdfPageLayoutMode {
  /// One column, pages flowing into each other. The classic reading mode.
  continuous('Continuous scroll', Icons.view_day_outlined),

  /// One column with a full break between pages; scrolling turns a page at a
  /// time instead of sliding through the seam.
  pageBreak('Page break scroll', Icons.auto_stories_outlined),

  /// One row, pages laid out left to right.
  horizontal('Horizontal scroll', Icons.view_carousel_outlined),

  /// Two pages side by side, starting with pages one and two.
  facing('Side by side', Icons.menu_book_outlined);

  const PdfPageLayoutMode(this.label, this.icon);

  final String label;
  final IconData icon;

  bool get isHorizontal => this == PdfPageLayoutMode.horizontal;

  /// Page turning replaces free scrolling while the whole page is visible.
  bool get turnsPages => this == PdfPageLayoutMode.pageBreak;

  static PdfPageLayoutMode fromName(Object? value) => values.firstWhere(
        (mode) => mode.name == value,
        orElse: () => PdfPageLayoutMode.continuous,
      );
}

/// The animation played when the viewer moves to another page.
enum PdfPageTransition {
  none('None', Icons.block_outlined),
  slide('Slide', Icons.swipe_up_alt_outlined),
  fade('Fade', Icons.gradient_outlined),
  flip('Page turn', Icons.auto_stories_outlined);

  const PdfPageTransition(this.label, this.icon);

  final String label;
  final IconData icon;

  /// [fade] hides the canvas, swaps the page underneath and comes back. The
  /// page turn instead paints its own curling leaf, so it is not part of this.
  bool get swapsAtMidpoint => this == PdfPageTransition.fade;

  /// [flip] peels a real sheet of paper, which needs both pages rasterised
  /// first and enables dragging a page over from the outer edge.
  bool get curlsPaper => this == PdfPageTransition.flip;

  static PdfPageTransition fromName(Object? value) => values.firstWhere(
        (transition) => transition.name == value,
        orElse: () => PdfPageTransition.slide,
      );
}

/// A reading mode: a page layout together with the animation that suits it.
///
/// The two are not independent. A page turn needs a layout that moves one page
/// (or one spread) at a time, and a continuously scrolling document never
/// changes page, so it has nothing to animate. Offering both lists separately
/// let the reader pick pairs that quietly did nothing, so they are chosen
/// together.
enum PdfViewPreset {
  continuous(
    'Continuous scroll',
    'Pages flow into each other',
    Icons.view_day_outlined,
    PdfPageLayoutMode.continuous,
    PdfPageTransition.none,
  ),
  horizontal(
    'Horizontal scroll',
    'Pages run left to right',
    Icons.view_carousel_outlined,
    PdfPageLayoutMode.horizontal,
    PdfPageTransition.none,
  ),
  singlePage(
    'Single page',
    'One page at a time, sliding',
    Icons.crop_portrait_rounded,
    PdfPageLayoutMode.pageBreak,
    PdfPageTransition.slide,
  ),
  singlePageFade(
    'Single page, fading',
    'One page at a time, crossfading',
    Icons.gradient_outlined,
    PdfPageLayoutMode.pageBreak,
    PdfPageTransition.fade,
  ),
  singlePageTurn(
    'Single page, page turn',
    'One page at a time, peeling like paper',
    Icons.auto_stories_outlined,
    PdfPageLayoutMode.pageBreak,
    PdfPageTransition.flip,
  ),
  spread(
    'Two pages',
    'Facing pages, a spread at a time',
    Icons.import_contacts_outlined,
    PdfPageLayoutMode.facing,
    PdfPageTransition.slide,
  ),
  book(
    'Book',
    'Facing pages with a real page turn',
    Icons.menu_book_outlined,
    PdfPageLayoutMode.facing,
    PdfPageTransition.flip,
  );

  const PdfViewPreset(
    this.label,
    this.description,
    this.icon,
    this.layoutMode,
    this.transition,
  );

  final String label;
  final String description;
  final IconData icon;
  final PdfPageLayoutMode layoutMode;
  final PdfPageTransition transition;

  /// The preset matching a stored layout and animation pair.
  ///
  /// Falls back to the first preset that uses the same layout, so documents
  /// saved before presets existed still open as something sensible.
  static PdfViewPreset resolve(
    PdfPageLayoutMode layoutMode,
    PdfPageTransition transition,
  ) {
    return values.firstWhere(
      (preset) =>
          preset.layoutMode == layoutMode && preset.transition == transition,
      orElse: () => values.firstWhere(
        (preset) => preset.layoutMode == layoutMode,
        orElse: () => PdfViewPreset.continuous,
      ),
    );
  }
}

/// Lays the pages out for [mode], mirroring pdfrx's own vertical layout for
/// [PdfPageLayoutMode.continuous].
PdfPageLayout buildPdfPageLayout(
  List<PdfPage> pages,
  PdfViewerParams params,
  PdfPageLayoutMode mode,
) =>
    buildPdfPageLayoutForSizes(
      [for (final page in pages) Size(page.width, page.height)],
      params.margin,
      mode,
    );

/// The geometry behind [buildPdfPageLayout], free of any pdfrx page object.
@visibleForTesting
PdfPageLayout buildPdfPageLayoutForSizes(
  List<Size> pages,
  double margin,
  PdfPageLayoutMode mode,
) {
  switch (mode) {
    case PdfPageLayoutMode.continuous:
      return _verticalLayout(pages, margin, margin);
    case PdfPageLayoutMode.pageBreak:
      // A visible gutter is what makes the break read as a break.
      return _verticalLayout(pages, margin, margin * 3.5);
    case PdfPageLayoutMode.horizontal:
      return _horizontalLayout(pages, margin);
    case PdfPageLayoutMode.facing:
      return _facingLayout(pages, margin);
  }
}

PdfPageLayout _verticalLayout(
  List<Size> pages,
  double margin,
  double gap,
) {
  final width =
      pages.fold(0.0, (w, page) => math.max(w, page.width)) + margin * 2;
  final layouts = <Rect>[];
  var y = margin;
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    layouts.add(
      Rect.fromLTWH((width - page.width) / 2, y, page.width, page.height),
    );
    y += page.height + (i == pages.length - 1 ? margin : gap);
  }
  return PdfPageLayout(
    pageLayouts: layouts,
    documentSize: Size(width, y),
  );
}

PdfPageLayout _horizontalLayout(List<Size> pages, double margin) {
  final height =
      pages.fold(0.0, (h, page) => math.max(h, page.height)) + margin * 2;
  final layouts = <Rect>[];
  var x = margin;
  for (final page in pages) {
    layouts.add(
      Rect.fromLTWH(x, (height - page.height) / 2, page.width, page.height),
    );
    x += page.width + margin;
  }
  return PdfPageLayout(
    pageLayouts: layouts,
    documentSize: Size(x, height),
  );
}

PdfPageLayout _facingLayout(List<Size> pages, double margin) {
  // Pages pair from the very first one: 1 facing 2, 3 facing 4, and so on. A
  // trailing page with no partner left stands on its own.
  final rows = <List<int>>[];
  for (var index = 0; index < pages.length; index += 2) {
    rows.add([
      index,
      if (index + 1 < pages.length) index + 1,
    ]);
  }

  final spreadGap = margin / 2;
  var widest = 0.0;
  for (final row in rows) {
    final width = row.fold(0.0, (w, index) => w + pages[index].width) +
        (row.length - 1) * spreadGap;
    widest = math.max(widest, width);
  }

  final documentWidth = widest + margin * 2;
  final layouts = List<Rect>.filled(pages.length, Rect.zero);
  var y = margin;
  for (final row in rows) {
    final rowWidth = row.fold(0.0, (w, index) => w + pages[index].width) +
        (row.length - 1) * spreadGap;
    final rowHeight =
        row.fold(0.0, (h, index) => math.max(h, pages[index].height));
    var x = (documentWidth - rowWidth) / 2;
    for (final index in row) {
      final page = pages[index];
      layouts[index] = Rect.fromLTWH(
        x,
        y + (rowHeight - page.height) / 2,
        page.width,
        page.height,
      );
      x += page.width + spreadGap;
    }
    y += rowHeight + margin;
  }

  return PdfPageLayout(
    pageLayouts: layouts,
    documentSize: Size(documentWidth, y),
  );
}

/// The page facing [pageNumber] in [PdfPageLayoutMode.facing], or null when a
/// trailing page has no partner left.
int? facingPartnerPage(int pageNumber, int pageCount) {
  if (pageNumber < 1 || pageNumber > pageCount) {
    return null;
  }
  final partner = pageNumber.isOdd ? pageNumber + 1 : pageNumber - 1;
  return partner >= 1 && partner <= pageCount ? partner : null;
}

/// The first page of the spread [pageNumber] belongs to.
int facingSpreadStart(int pageNumber) {
  if (pageNumber <= 1) {
    return 1;
  }
  return pageNumber.isOdd ? pageNumber : pageNumber - 1;
}

/// The first page of the next spread, so page turns move a whole spread.
///
/// Stays on the current spread when there is no next one, so the last pair
/// does not creep forward one page at a time.
int nextFacingPage(int pageNumber, int pageCount) {
  if (pageCount <= 0) {
    return 1;
  }
  final start = facingSpreadStart(pageNumber);
  final next = start + 2;
  return next <= pageCount ? next : start;
}

/// The first page of the previous spread.
int previousFacingPage(int pageNumber) =>
    math.max(facingSpreadStart(pageNumber) - 2, 1);

/// The toolbar control that owns the reading mode and toolbar auto-hide.
class PdfViewOptionsMenu extends StatelessWidget {
  const PdfViewOptionsMenu({
    super.key,
    required this.preset,
    required this.autoHideToolbar,
    required this.enabled,
    required this.onPresetChanged,
    required this.onAutoHideToolbarChanged,
  });

  final PdfViewPreset preset;
  final bool autoHideToolbar;
  final bool enabled;
  final ValueChanged<PdfViewPreset> onPresetChanged;
  final ValueChanged<bool> onAutoHideToolbarChanged;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return SizedBox.square(
      dimension: 30,
      child: PopupMenuButton<_PdfViewOption>(
        key: const ValueKey('pdf-view-options-menu'),
        tooltip: 'Reading mode',
        enabled: enabled,
        onSelected: _handle,
        color: palette.chrome,
        surfaceTintColor: Colors.transparent,
        constraints: const BoxConstraints(minWidth: 262),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: palette.border),
        ),
        style: ButtonStyle(
          animationDuration: const Duration(milliseconds: 200),
          fixedSize: const WidgetStatePropertyAll(Size.square(30)),
          padding: const WidgetStatePropertyAll(EdgeInsets.zero),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
          ),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.hovered) ||
                states.contains(WidgetState.focused) ||
                states.contains(WidgetState.pressed)) {
              return palette.controlHover;
            }
            return Colors.transparent;
          }),
          splashFactory: NoSplash.splashFactory,
        ),
        padding: EdgeInsets.zero,
        iconSize: 18,
        iconColor: palette.icon,
        icon: Icon(preset.icon),
        itemBuilder: (_) => [
          _label(context, 'READING MODE'),
          for (final value in PdfViewPreset.values)
            _choice(
              context,
              _PdfViewOption.preset(value),
              value.icon,
              value.label,
              description: value.description,
              selected: value == preset,
            ),
          const PopupMenuDivider(height: 9),
          _choice(
            context,
            const _PdfViewOption.autoHide(),
            Icons.visibility_off_outlined,
            'Hide toolbar when idle',
            selected: autoHideToolbar,
          ),
        ],
      ),
    );
  }

  void _handle(_PdfViewOption option) {
    final value = option.preset;
    if (value != null) {
      onPresetChanged(value);
      return;
    }
    onAutoHideToolbarChanged(!autoHideToolbar);
  }

  PopupMenuEntry<_PdfViewOption> _label(BuildContext context, String text) {
    final palette = PdfPreviewPalette.of(context);
    return PopupMenuItem<_PdfViewOption>(
      enabled: false,
      height: 26,
      child: Text(
        text,
        style: TextStyle(
          color: palette.textSecondary,
          fontFamily: 'Geist Mono',
          fontFamilyFallback: const ['RobotoMono', 'monospace'],
          fontSize: 9.5,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.8,
        ),
      ),
    );
  }

  PopupMenuEntry<_PdfViewOption> _choice(
    BuildContext context,
    _PdfViewOption value,
    IconData icon,
    String label, {
    required bool selected,
    String? description,
  }) {
    final palette = PdfPreviewPalette.of(context);
    return PopupMenuItem<_PdfViewOption>(
      value: value,
      height: description == null ? 38 : 46,
      child: Row(
        children: [
          Icon(
            icon,
            size: 17,
            color: selected ? palette.accent : palette.icon,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: palette.textPrimary,
                    fontFamily: 'Inter',
                    fontSize: 12,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
                if (description != null)
                  Text(
                    description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: palette.textSecondary,
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      height: 15 / 10.5,
                    ),
                  ),
              ],
            ),
          ),
          if (selected)
            Icon(Icons.check_rounded, size: 15, color: palette.accent),
        ],
      ),
    );
  }
}

@immutable
class _PdfViewOption {
  const _PdfViewOption.preset(PdfViewPreset value) : preset = value;

  const _PdfViewOption.autoHide() : preset = null;

  final PdfViewPreset? preset;

  @override
  bool operator ==(Object other) =>
      other is _PdfViewOption && other.preset == preset;

  @override
  int get hashCode => preset.hashCode;
}
