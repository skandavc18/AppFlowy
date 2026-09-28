import 'package:flutter/widgets.dart';

/// Session offsets belong to a presentation, not a coincidentally identical
/// PageStorage key used by another layout. The host owns/disposes this object.
class FileBrowserScrollController extends ScrollController {
  FileBrowserScrollController() : super(keepScrollOffset: false);

  double _lastOffset = 0;

  @override
  double get initialScrollOffset => _lastOffset;

  @override
  void detach(ScrollPosition position) {
    if (position.hasPixels) _lastOffset = position.pixels;
    super.detach(position);
  }
}

/// A collection lends its header to exactly one audited main listing. Nested
/// previews must not implicitly consume it or create another page viewport.
class FileBrowserPageHeader extends InheritedWidget {
  const FileBrowserPageHeader({
    super.key,
    required this.header,
    required super.child,
  });

  final Widget header;

  static Widget? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<FileBrowserPageHeader>()
      ?.header;

  @override
  bool updateShouldNotify(FileBrowserPageHeader oldWidget) =>
      header != oldWidget.header;
}

/// Header and lazy content share one native viewport. SliverToBoxAdapter keeps
/// the header's editors mounted when clipped; the listing delegate stays lazy.
class FileBrowserScrollView extends StatelessWidget {
  const FileBrowserScrollView({
    super.key,
    this.scrollKey,
    this.controller,
    this.header,
    this.footer,
    this.cacheExtent,
    required this.slivers,
  });

  final Key? scrollKey;
  final ScrollController? controller;
  final Widget? header;
  final Widget? footer;
  final double? cacheExtent;
  final List<Widget> slivers;

  @override
  Widget build(BuildContext context) => KeyedSubtree(
        // Scrollable otherwise reuses the old position when two controllers
        // have the same runtimeType, mixing Gallery and Thumbnail offsets.
        key: ObjectKey(controller),
        child: CustomScrollView(
          key: scrollKey,
          controller: controller,
          cacheExtent: cacheExtent,
          slivers: [
            if (header != null) SliverToBoxAdapter(child: header),
            ...slivers,
            if (footer != null) SliverToBoxAdapter(child: footer),
          ],
        ),
      );
}
