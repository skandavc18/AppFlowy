import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The dashboard the workspace opens on, if one has been chosen.
///
/// Kept as a preference rather than on the view itself: "this is my home" is
/// a statement about this person's workspace, not about the page, and a page
/// shared with somebody else should not drag their home with it.
class DashboardHome extends ChangeNotifier {
  DashboardHome._();

  static final DashboardHome instance = DashboardHome._();

  static const _key = 'appflowy_home_dashboard';

  String? _viewId;
  bool _loaded = false;

  String? get viewId => _viewId;

  bool isHome(String viewId) => _viewId == viewId;

  Future<void> ensureLoaded() async {
    if (_loaded) {
      return;
    }
    _loaded = true;
    // A stored preference is never worth failing a view over.
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    final stored = await getIt<KeyValueStorage>().get(_key);
    if (stored != null && stored.isNotEmpty && _viewId == null) {
      _viewId = stored;
      notifyListeners();
    }
  }

  /// Make [viewId] the home dashboard, or clear it when it already is.
  Future<void> toggle(String viewId) async {
    await ensureLoaded();
    final next = _viewId == viewId ? null : viewId;
    _viewId = next;
    notifyListeners();
    if (!getIt.isRegistered<KeyValueStorage>()) {
      return;
    }
    final storage = getIt<KeyValueStorage>();
    if (next == null) {
      await storage.remove(_key);
    } else {
      await storage.set(_key, next);
    }
  }

  Future<void> clear() async {
    _viewId = null;
    notifyListeners();
    if (getIt.isRegistered<KeyValueStorage>()) {
      await getIt<KeyValueStorage>().remove(_key);
    }
  }
}

/// What a sidebar tree should show: everything except the home dashboard,
/// which already has its own place at the top. A plain page that was merely
/// pointed at as the home stays in the tree, so nothing a person wrote can
/// quietly disappear from it.
List<ViewPB> withoutHomeDashboard(List<ViewPB> views) {
  final home = DashboardHome.instance.viewId;
  if (home == null || home.isEmpty) {
    return views;
  }
  return [
    for (final view in views)
      if (view.id != home || !view.isDashboard) view,
  ];
}
