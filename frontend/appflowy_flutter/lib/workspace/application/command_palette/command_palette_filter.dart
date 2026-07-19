import 'package:appflowy/workspace/application/command_palette/command_palette_bloc.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:fixnum/fixnum.dart';

class CommandPaletteFilter {
  const CommandPaletteFilter({
    this.titleOnly = false,
    this.createdByMe = false,
    this.spaceId,
    this.pageType,
  });

  final bool titleOnly;
  final bool createdByMe;
  final String? spaceId;
  final ViewLayoutPB? pageType;

  bool get isActive =>
      titleOnly || createdByMe || spaceId != null || pageType != null;

  CommandPaletteFilter copyWith({
    bool? titleOnly,
    bool? createdByMe,
    String? spaceId,
    bool clearSpace = false,
    ViewLayoutPB? pageType,
    bool clearPageType = false,
  }) {
    return CommandPaletteFilter(
      titleOnly: titleOnly ?? this.titleOnly,
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
        query.isNotEmpty &&
        !item.displayName.toLowerCase().contains(query.toLowerCase())) {
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
