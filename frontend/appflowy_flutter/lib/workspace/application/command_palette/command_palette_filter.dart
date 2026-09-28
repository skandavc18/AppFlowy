import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:fixnum/fixnum.dart';

class CommandPaletteFilter {
  const CommandPaletteFilter({
    bool titleOnly = false,
    this.pageContents = false,
    this.createdByMe = false,
    this.spaceId,
    this.pageType,
  }) : titleOnly = titleOnly && !pageContents;

  final bool titleOnly;
  final bool pageContents;
  final bool createdByMe;
  final String? spaceId;
  final ViewLayoutPB? pageType;

  bool get isActive =>
      titleOnly ||
      pageContents ||
      createdByMe ||
      spaceId != null ||
      pageType != null;

  CommandPaletteFilter copyWith({
    bool? titleOnly,
    bool? pageContents,
    bool? createdByMe,
    String? spaceId,
    bool clearSpace = false,
    ViewLayoutPB? pageType,
    bool clearPageType = false,
  }) {
    return CommandPaletteFilter(
      titleOnly: titleOnly ?? (pageContents == true ? false : this.titleOnly),
      pageContents:
          pageContents ?? (titleOnly == true ? false : this.pageContents),
      createdByMe: createdByMe ?? this.createdByMe,
      spaceId: clearSpace ? null : spaceId ?? this.spaceId,
      pageType: clearPageType ? null : pageType ?? this.pageType,
    );
  }

  bool matchesSearchResult({
    required SearchResultItem item,
    required ViewPB? view,
    required String query,
    required Map<String, ViewPB> cachedViews,
    required Int64? currentUserId,
  }) {
    if (titleOnly &&
        paletteTitleRank(
              view != null && view.name.trim().isNotEmpty
                  ? view.name
                  : item.displayName,
              query,
            ) ==
            null) {
      return false;
    }

    return _matchesView(
      view: view,
      cachedViews: cachedViews,
      currentUserId: currentUserId,
    );
  }

  bool matchesRecentView({
    required ViewPB view,
    required Map<String, ViewPB> cachedViews,
    required Int64? currentUserId,
  }) {
    return _matchesView(
      view: view,
      cachedViews: cachedViews,
      currentUserId: currentUserId,
    );
  }

  bool _matchesView({
    required ViewPB? view,
    required Map<String, ViewPB> cachedViews,
    required Int64? currentUserId,
  }) {
    final needsView = createdByMe || spaceId != null || pageType != null;
    if (view == null) {
      return !needsView;
    }
    if (createdByMe &&
        (currentUserId == null || view.createdBy != currentUserId)) {
      return false;
    }
    if (pageType != null && view.layout != pageType) {
      return false;
    }
    if (spaceId != null && !_isInSpace(view, spaceId!, cachedViews)) {
      return false;
    }
    return true;
  }

  bool _isInSpace(
    ViewPB view,
    String selectedSpaceId,
    Map<String, ViewPB> cachedViews,
  ) {
    var current = view;
    final visitedIds = <String>{};

    while (visitedIds.add(current.id)) {
      if (current.id == selectedSpaceId) {
        return true;
      }
      if (current.parentViewId.isEmpty) {
        return false;
      }
      if (current.parentViewId == selectedSpaceId) {
        return true;
      }
      final parent = cachedViews[current.parentViewId];
      if (parent == null) {
        return false;
      }
      current = parent;
    }

    return false;
  }
}

/// Shared literal/fuzzy title semantics. Exact and prefix hits win; whitespace
/// and case never change whether the title-only toggle accepts a cached hit.
String normalizePaletteQuery(String value) =>
    value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');

int? paletteTitleRank(String title, String query) {
  final needle = normalizePaletteQuery(query);
  final name = normalizePaletteQuery(title);
  if (needle.isEmpty) return 0;
  if (needle.length > 256) return null;
  if (name == needle) return 0;
  if (name.startsWith(needle)) return 1;
  if (name.contains(needle)) return 2;
  if (needle.split(' ').every(name.contains)) return 3;
  // Subsequence matching keeps Ctrl+P useful for abbreviated page titles.
  var offset = 0;
  for (final rune in needle.runes) {
    final found = name.indexOf(String.fromCharCode(rune), offset);
    if (found < 0) return null;
    offset = found + String.fromCharCode(rune).length;
  }
  return 4;
}
