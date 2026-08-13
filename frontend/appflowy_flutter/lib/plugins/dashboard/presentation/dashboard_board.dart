import 'package:flutter/widgets.dart';

/// Where every section of one dashboard is, so a widget dragged out of one can
/// be handed to another.
///
/// A canvas only knows its own band; this is the one place that knows the
/// board as a whole.
class DashboardSectionRegistry {
  final Map<String, GlobalKey> _sections = <String, GlobalKey>{};

  void register(String sectionId, GlobalKey key) => _sections[sectionId] = key;

  void unregister(String sectionId, GlobalKey key) {
    if (_sections[sectionId] == key) {
      _sections.remove(sectionId);
    }
  }

  /// The section under [globalPosition], and where in it.
  ///
  /// A point in the gap between two sections belongs to the nearer of them:
  /// letting go over a heading is still letting go over that band.
  ({String id, Offset local})? sectionAt(Offset globalPosition) {
    ({String id, Offset local})? nearest;
    var distance = double.infinity;
    for (final entry in _sections.entries) {
      final box = entry.value.currentContext?.findRenderObject() as RenderBox?;
      if (box == null || !box.hasSize) {
        continue;
      }
      final local = box.globalToLocal(globalPosition);
      if (local.dx >= 0 &&
          local.dy >= 0 &&
          local.dx <= box.size.width &&
          local.dy <= box.size.height) {
        return (id: entry.key, local: local);
      }
      final gap = local.dy < 0 ? -local.dy : local.dy - box.size.height;
      if (gap < distance) {
        distance = gap;
        nearest = (
          id: entry.key,
          local: Offset(local.dx, local.dy.clamp(0, box.size.height)),
        );
      }
    }
    // Only when it is genuinely close; a drop far off the board is not a move.
    return distance <= 120 ? nearest : null;
  }
}

/// Hands the registry down to the sections.
class DashboardBoard extends InheritedWidget {
  const DashboardBoard({
    super.key,
    required this.registry,
    required super.child,
  });

  final DashboardSectionRegistry registry;

  static DashboardSectionRegistry? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<DashboardBoard>()?.registry;

  @override
  bool updateShouldNotify(DashboardBoard oldWidget) =>
      registry != oldWidget.registry;
}
