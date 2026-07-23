import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import 'file_preview_toolbar.dart';
import 'pdf_preview_theme.dart';

enum PdfSidebarMode { none, thumbnails, outline }

class PdfPreviewSidebar extends StatelessWidget {
  const PdfPreviewSidebar({
    super.key,
    required this.mode,
    required this.document,
    required this.currentPage,
    required this.outline,
    required this.outlineLoading,
    required this.onPageSelected,
    required this.onDestinationSelected,
    required this.onClose,
  });

  final PdfSidebarMode mode;
  final PdfDocument? document;
  final int currentPage;
  final List<PdfOutlineNode>? outline;
  final bool outlineLoading;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<PdfDest> onDestinationSelected;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    final isThumbnails = mode == PdfSidebarMode.thumbnails;
    return Material(
      color: palette.sidebar,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: Border(right: BorderSide(color: palette.border)),
        ),
        child: Column(
          children: [
            SizedBox(
              height: 40,
              child: Padding(
                padding: const EdgeInsets.only(left: 12, right: 5),
                child: Row(
                  children: [
                    Icon(
                      isThumbnails
                          ? Icons.grid_view_rounded
                          : Icons.account_tree_outlined,
                      size: 15,
                      color: palette.icon,
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        isThumbnails ? 'Pages' : 'Outline',
                        style: TextStyle(
                          color: palette.textPrimary,
                          fontFamily: 'Inter',
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    FilePreviewToolbarButton(
                      tooltip: 'Close side panel',
                      onPressed: onClose,
                      icon: Icons.close_rounded,
                    ),
                  ],
                ),
              ),
            ),
            Divider(height: 0.5, thickness: 0.5, color: palette.border),
            Expanded(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 200),
                switchInCurve: Curves.easeOutCubic,
                switchOutCurve: Curves.easeInCubic,
                child: isThumbnails
                    ? _ThumbnailList(
                        key: const ValueKey('pdf-thumbnails'),
                        document: document,
                        currentPage: currentPage,
                        onPageSelected: onPageSelected,
                      )
                    : _OutlineList(
                        key: const ValueKey('pdf-outline'),
                        outline: outline,
                        loading: outlineLoading,
                        onPageSelected: onPageSelected,
                        onDestinationSelected: onDestinationSelected,
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ThumbnailList extends StatelessWidget {
  const _ThumbnailList({
    super.key,
    required this.document,
    required this.currentPage,
    required this.onPageSelected,
  });

  final PdfDocument? document;
  final int currentPage;
  final ValueChanged<int> onPageSelected;

  @override
  Widget build(BuildContext context) {
    final document = this.document;
    if (document == null) {
      return const _SidebarSkeleton();
    }
    return Semantics(
      label: 'PDF page thumbnails',
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 16),
        cacheExtent: 520,
        itemCount: document.pages.length,
        itemBuilder: (context, index) {
          final page = index + 1;
          return RepaintBoundary(
            key: ValueKey('pdf-thumbnail-$page'),
            child: _ThumbnailTile(
              document: document,
              page: page,
              selected: currentPage == page,
              onTap: () => onPageSelected(page),
            ),
          );
        },
      ),
    );
  }
}

class _ThumbnailTile extends StatelessWidget {
  const _ThumbnailTile({
    required this.document,
    required this.page,
    required this.selected,
    required this.onTap,
  });

  final PdfDocument document;
  final int page;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Semantics(
      selected: selected,
      button: true,
      label: 'Go to PDF page $page',
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Material(
          color: selected ? palette.controlSelected : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(8),
            hoverColor: palette.controlHover,
            focusColor: palette.controlSelected,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Column(
                children: [
                  SizedBox(
                    height: 132,
                    child: PdfPageView(
                      document: document,
                      pageNumber: page,
                      maximumDpi: 144,
                      decorationBuilder: (_, __, ___, pageImage) {
                        return Center(
                          child: AspectRatio(
                            aspectRatio: document.pages[page - 1].width /
                                document.pages[page - 1].height,
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(3),
                                border: Border.all(
                                  color: selected
                                      ? palette.accent
                                      : palette.border,
                                  width: selected ? 1 : 0.5,
                                ),
                              ),
                              child: ClipRRect(
                                borderRadius: BorderRadius.circular(2.5),
                                child: pageImage ??
                                    ColoredBox(
                                      color: palette.control,
                                      child: const SizedBox.expand(),
                                    ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    '$page',
                    style: TextStyle(
                      color: selected
                          ? palette.textPrimary
                          : palette.textSecondary,
                      fontFamily: 'Inter',
                      fontSize: 10.5,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w500,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
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

class _OutlineList extends StatelessWidget {
  const _OutlineList({
    super.key,
    required this.outline,
    required this.loading,
    required this.onPageSelected,
    required this.onDestinationSelected,
  });

  final List<PdfOutlineNode>? outline;
  final bool loading;
  final ValueChanged<int> onPageSelected;
  final ValueChanged<PdfDest> onDestinationSelected;

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const _SidebarSkeleton();
    }
    final entries = <_OutlineEntry>[];
    void flatten(List<PdfOutlineNode> nodes, int depth) {
      for (final node in nodes) {
        entries.add(_OutlineEntry(node, depth));
        flatten(node.children, depth + 1);
      }
    }

    flatten(outline ?? const [], 0);
    return CustomScrollView(
      key: const PageStorageKey('pdf-outline-scroll'),
      slivers: [
        const SliverToBoxAdapter(
          child: _SidebarSectionLabel(label: 'DOCUMENT'),
        ),
        if (entries.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyOutline(),
          )
        else
          SliverList.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return _OutlineTile(
                title: entry.node.title,
                depth: entry.depth,
                onTap: entry.node.dest == null
                    ? null
                    : () => onDestinationSelected(entry.node.dest!),
              );
            },
          ),
        const SliverPadding(padding: EdgeInsets.only(bottom: 16)),
      ],
    );
  }
}

class _OutlineTile extends StatelessWidget {
  const _OutlineTile({
    required this.title,
    required this.depth,
    required this.onTap,
  });

  final String title;
  final int depth;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Semantics(
      button: onTap != null,
      label: title,
      child: Padding(
        padding: EdgeInsets.only(left: 6.0 + depth.clamp(0, 5) * 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            hoverColor: palette.controlHover,
            focusColor: palette.controlSelected,
            highlightColor: Colors.transparent,
            splashColor: Colors.transparent,
            splashFactory: NoSplash.splashFactory,
            borderRadius: BorderRadius.circular(7),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
              child: Row(
                children: [
                  Icon(
                    Icons.chevron_right_rounded,
                    size: 14,
                    color: palette.icon,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: onTap == null
                            ? palette.textSecondary
                            : palette.textPrimary,
                        fontFamily: 'Inter',
                        fontSize: 11.5,
                        height: 1.25,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
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

class _SidebarSectionLabel extends StatelessWidget {
  const _SidebarSectionLabel({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(13, 14, 10, 6),
      child: Text(
        label,
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
}

class _EmptyOutline extends StatelessWidget {
  const _EmptyOutline();

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.subject_rounded, size: 24, color: palette.iconDisabled),
            const SizedBox(height: 8),
            Text(
              'No outline in this document',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: palette.textSecondary,
                fontFamily: 'Inter',
                fontSize: 11.5,
                height: 1.35,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SidebarSkeleton extends StatefulWidget {
  const _SidebarSkeleton();

  @override
  State<_SidebarSkeleton> createState() => _SidebarSkeletonState();
}

class _SidebarSkeletonState extends State<_SidebarSkeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = PdfPreviewPalette.of(context);
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: controller,
        builder: (context, _) => ListView.separated(
          padding: const EdgeInsets.all(12),
          itemCount: 4,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (_, index) => Center(
            child: Opacity(
              opacity: 0.42 + controller.value * 0.32,
              child: Container(
                width: 110,
                height: 132,
                decoration: BoxDecoration(
                  color: palette.control,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(color: palette.border),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlineEntry {
  const _OutlineEntry(this.node, this.depth);

  final PdfOutlineNode node;
  final int depth;
}
