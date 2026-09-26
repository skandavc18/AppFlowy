import 'package:appflowy/startup/plugin/plugin.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';

/// A destination, not a live Plugin: replaced plugins have already been
/// disposed and must never be reused when walking back through visited pages.
class PageHistoryEntry {
  const PageHistoryEntry({
    required this.pluginType,
    this.viewId,
    this.workspaceRoot,
    this.tabId,
  });

  final PluginType pluginType;
  final String? viewId;
  final String? tabId;

  /// The workspace root is a synthetic folder, not a backend View record.
  /// Other views are re-read before opening, so deleted/stale pages are skipped.
  final ViewPB? workspaceRoot;

  Object get previewKey => (pluginType, viewId);

  bool sameDestination(PageHistoryEntry other) =>
      (tabId == null || other.tabId == null || tabId == other.tabId) &&
      (viewId != null
          ? viewId == other.viewId
          : other.viewId == null && pluginType == other.pluginType);
}

/// Bounded, session-only workspace visit history, independent of tab order.
class PageNavigationHistory {
  PageNavigationHistory({this.capacity = 100}) : assert(capacity > 1);

  final int capacity;
  final _entries = <PageHistoryEntry>[];
  int _index = -1;
  int _generation = 0;

  /// Changes only when the session/workspace is cleared, not on each visit.
  int get generation => _generation;

  bool get canGoBack => _index > 0;
  bool get canGoForward => _index >= 0 && _index < _entries.length - 1;
  PageHistoryEntry? get current => _index < 0 ? null : _entries[_index];

  void record(PageHistoryEntry entry) {
    // Re-selecting the current tab must not erase an existing forward branch.
    if (current?.sameDestination(entry) == true) return;
    _entries.removeRange(_index + 1, _entries.length);
    _entries.add(entry);
    if (_entries.length > capacity) _entries.removeAt(0);
    _index = _entries.length - 1;
  }

  /// Resolve visits to this exact loading Home without adding an invisible
  /// intermediate destination or truncating the user's forward branch.
  void resolveHomeTab(String tabId, PageHistoryEntry entry) {
    for (var i = 0; i < _entries.length; i++) {
      final previous = _entries[i];
      if (previous.tabId == tabId &&
          previous.pluginType == PluginType.blank &&
          previous.viewId == null) {
        _entries[i] = entry;
      }
    }
  }

  PageHistoryEntry? peek({required bool forward}) =>
      (forward ? canGoForward : canGoBack)
          ? _entries[_index + (forward ? 1 : -1)]
          : null;

  void move({required bool forward}) {
    if (peek(forward: forward) != null) _index += forward ? 1 : -1;
  }

  /// Drop an unavailable destination without moving the current page.
  void discard(PageHistoryEntry entry) {
    final index = _entries.indexOf(entry);
    if (index < 0 || index == _index) return;
    _entries.removeAt(index);
    if (index < _index) _index--;
  }

  void clear() {
    _generation++;
    _entries.clear();
    _index = -1;
  }
}
