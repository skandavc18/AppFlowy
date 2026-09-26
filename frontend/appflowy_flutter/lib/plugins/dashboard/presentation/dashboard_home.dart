import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/dashboard/dashboard_metadata.dart';
import 'package:appflowy/workspace/application/view/view_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The dashboard the workspace opens on, if one has been chosen.
///
/// Kept as a preference rather than on the view itself: "this is my home" is
/// a statement about this person's workspace, not about the page, and a page
/// shared with somebody else should not drag their home with it.
class DashboardHome extends ChangeNotifier {
  DashboardHome({
    KeyValueStorage? storage,
    Future<ViewPB?> Function(String)? loadView,
    Future<List<ViewPB>> Function(String)? loadAncestors,
  })  : _storage = storage,
        _loadView = loadView ?? _readView,
        _loadAncestors = loadAncestors ?? _readAncestors;

  static final DashboardHome instance = DashboardHome();

  static const _key = 'appflowy_home_dashboard';
  final KeyValueStorage? _storage;
  final Future<ViewPB?> Function(String) _loadView;
  final Future<List<ViewPB>> Function(String) _loadAncestors;

  String? _viewId;
  bool _loaded = false;
  Future<void>? _loading;

  KeyValueStorage? get _preferences =>
      _storage ??
      (getIt.isRegistered<KeyValueStorage>() ? getIt<KeyValueStorage>() : null);

  String? get viewId => _viewId;

  bool isHome(String viewId) => _viewId == viewId;

  Future<void> ensureLoaded() => _loaded
      ? Future<void>.value()
      : _loading ??= _loadPreference().whenComplete(() => _loading = null);

  Future<void> _loadPreference() async {
    final storage = _preferences;
    if (storage == null) return;
    final stored = await storage.get(_key);
    _loaded = true;
    if (stored != null && stored.isNotEmpty && _viewId == null) {
      _viewId = stored;
      notifyListeners();
    }
  }

  /// Resolve only the chosen dashboard, never the latest/opened/pinned views.
  /// The legacy preference is not workspace-scoped, so check membership before
  /// opening it. Missing, inaccessible or non-dashboard targets fall back to
  /// Home without changing the preference or creating a replacement page.
  Future<ViewPB?> resolveForWorkspace(String workspaceId) async {
    if (workspaceId.isEmpty) return null;
    try {
      await ensureLoaded();
      final id = _viewId;
      if (id == null || id.isEmpty) return null;
      final view = await _loadView(id);
      if (view == null ||
          view.id != id ||
          view.id == workspaceId ||
          !_isHomeDashboard(view)) {
        return null;
      }
      if (view.parentViewId == workspaceId) return view;
      final ancestors = await _loadAncestors(id);
      return ancestors.any((ancestor) => ancestor.id == workspaceId)
          ? view
          : null;
    } catch (error, stackTrace) {
      Log.error('Could not load Home: $error', error, stackTrace);
      return null;
    }
  }

  static Future<ViewPB?> _readView(String id) async =>
      (await ViewBackendService.getView(id)).fold((view) => view, (_) => null);

  static Future<List<ViewPB>> _readAncestors(String id) async =>
      (await ViewBackendService.getViewAncestors(id))
          .fold((views) => views.items, (_) => <ViewPB>[]);

  /// Make [viewId] the home dashboard, or clear it when it already is.
  Future<void> toggle(String viewId) async {
    await ensureLoaded();
    final next = _viewId == viewId ? null : viewId;
    _viewId = next;
    notifyListeners();
    final storage = _preferences;
    if (storage == null) return;
    if (next == null) {
      await storage.remove(_key);
    } else {
      await storage.set(_key, next);
    }
  }

  Future<void> clear() async {
    await ensureLoaded();
    _viewId = null;
    notifyListeners();
    await _preferences?.remove(_key);
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
      if (view.id != home || !_isHomeDashboard(view)) view,
  ];
}

// A converted page may retain a dashboard envelope. Those higher-priority
// plugins must neither be mounted as Home nor disappear from the sidebar.
bool _isHomeDashboard(ViewPB view) =>
    view.parentViewId.isNotEmpty &&
    view.isDashboard &&
    !view.isCollection &&
    !view.isWorkspaceItem &&
    decodeViewExtra(view.extra)['is_space'] != true;
