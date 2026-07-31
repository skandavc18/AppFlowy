import 'dart:convert';

import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

/// The semantic containers a workspace can group its objects into.
///
/// A collection never changes how an object is stored — it only declares the
/// purpose of the group and, through that, which adaptive views the group is
/// presented with.
enum CollectionKind {
  book,
  album,
  repository,
  database,
  bookmark,
  email;

  static CollectionKind? fromValue(Object? value) {
    for (final kind in CollectionKind.values) {
      if (kind.name == value) {
        return kind;
      }
    }
    return null;
  }
}

/// The collection envelope stored inside `ViewPB.extra`.
///
/// A collection view also carries [WorkspaceItemMetadata.folder] so every
/// existing container behaviour (children, drag and drop, breadcrumbs) keeps
/// working untouched; this envelope is the layer on top of it.
@immutable
class CollectionMetadata {
  const CollectionMetadata({
    required this.kind,
    this.activeViewId,
    this.createdAt,
    this.viewState = const <String, dynamic>{},
  });

  static const envelopeKey = 'appflowy_collection';
  static const currentVersion = 1;

  final CollectionKind kind;

  /// The adaptive view the collection was last read in.
  final String? activeViewId;

  final DateTime? createdAt;

  /// Per-view persisted state, keyed by adaptive view id.
  ///
  /// Reading progress, gallery zoom, the selected repository path and so on
  /// live here so a view can remember itself without a schema change.
  final Map<String, dynamic> viewState;

  CollectionMetadata copyWith({
    CollectionKind? kind,
    String? activeViewId,
    DateTime? createdAt,
    Map<String, dynamic>? viewState,
  }) =>
      CollectionMetadata(
        kind: kind ?? this.kind,
        activeViewId: activeViewId ?? this.activeViewId,
        createdAt: createdAt ?? this.createdAt,
        viewState: viewState ?? this.viewState,
      );

  /// Reads the state a single adaptive view persisted.
  Map<String, dynamic> stateFor(String viewId) {
    final value = viewState[viewId];
    return value is Map
        ? Map<String, dynamic>.from(value)
        : <String, dynamic>{};
  }

  /// Returns a copy where [viewId] holds [state], dropping the entry when the
  /// view has nothing left to remember.
  CollectionMetadata withStateFor(String viewId, Map<String, dynamic> state) {
    final next = Map<String, dynamic>.from(viewState);
    if (state.isEmpty) {
      next.remove(viewId);
    } else {
      next[viewId] = state;
    }
    return copyWith(viewState: next);
  }

  Map<String, Object?> toJson() => {
        'version': currentVersion,
        'kind': kind.name,
        if (activeViewId != null && activeViewId!.isNotEmpty)
          'active_view': activeViewId,
        if (createdAt != null) 'created_at': createdAt!.millisecondsSinceEpoch,
        if (viewState.isNotEmpty) 'view_state': viewState,
      };

  String mergeIntoExtra(String extra) {
    final values = decodeViewExtra(extra);
    values[envelopeKey] = toJson();
    return jsonEncode(values);
  }

  static CollectionMetadata? fromExtra(String extra) {
    final envelope = decodeViewExtra(extra)[envelopeKey];
    if (envelope is! Map) {
      return null;
    }

    final values = Map<String, dynamic>.from(envelope);
    final version = values['version'];
    final kind = CollectionKind.fromValue(values['kind']);
    if (version is! int ||
        version < 1 ||
        version > currentVersion ||
        kind == null) {
      return null;
    }

    final activeViewId = values['active_view'];
    final createdAt = values['created_at'];
    final viewState = values['view_state'];
    return CollectionMetadata(
      kind: kind,
      activeViewId: activeViewId is String && activeViewId.isNotEmpty
          ? activeViewId
          : null,
      createdAt: createdAt is int
          ? DateTime.fromMillisecondsSinceEpoch(createdAt)
          : null,
      viewState:
          viewState is Map ? Map<String, dynamic>.from(viewState) : const {},
    );
  }

  /// The `extra` payload of a brand new collection: a workspace folder that
  /// also declares its purpose.
  static String newExtra(CollectionKind kind, {DateTime? createdAt}) =>
      CollectionMetadata(kind: kind, createdAt: createdAt ?? DateTime.now())
          .mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
}

extension CollectionViewExtension on ViewPB {
  CollectionMetadata? get collection => CollectionMetadata.fromExtra(extra);

  bool get isCollection => collection != null;
}
