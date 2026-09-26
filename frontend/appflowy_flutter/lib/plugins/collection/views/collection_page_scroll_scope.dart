import 'package:flutter/widgets.dart';

/// Lends the full collection page's nested body controller to an audited view.
///
/// Use this for exactly one main vertical scroller and its scrollbar. Secondary
/// panes keep their own controllers, as do views rendered outside this scope
/// (embeds and standalone hosts). The borrower must never dispose this
/// controller: [NestedScrollView] owns it and coordinates the header itself.
/// No scroll notifications or already-applied deltas are forwarded here.
///
/// Drags and Flutter's `pointerScroll` path let the nested coordinator consume
/// forward travel in the header before the body. The full page also wraps its
/// owning [NestedScrollView] in `PremiumCoordinatedScrollScope`, opting only
/// that owner's controllers into immediate native wheel handling. Borrowing
/// alone is not enough: a wheel animator writing [ScrollPosition.setPixels]
/// directly bypasses coordination. Do not replay body deltas into the header
/// to compensate; that would consume the same input twice.
class CollectionPageScrollScope extends InheritedWidget {
  const CollectionPageScrollScope({
    super.key,
    required this.controller,
    required super.child,
  });

  final ScrollController controller;

  static ScrollController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CollectionPageScrollScope>()
      ?.controller;

  @override
  bool updateShouldNotify(CollectionPageScrollScope oldWidget) =>
      controller != oldWidget.controller;
}
