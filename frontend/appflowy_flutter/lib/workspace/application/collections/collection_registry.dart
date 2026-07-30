import 'package:appflowy/plugins/collection/collection_views.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_controller.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Everything an adaptive view is handed to render a collection.
@immutable
class CollectionViewContext {
  const CollectionViewContext({
    required this.collectionView,
    required this.metadata,
    required this.definition,
    required this.explorer,
    required this.onOpen,
    required this.onStateChanged,
  });

  /// The collection itself. Its children are the objects it organises.
  final ViewPB collectionView;

  final CollectionMetadata metadata;

  final CollectionViewDefinition definition;

  /// The collection's objects, already loaded and kept in step with the
  /// backend. Every adaptive view reads the same graph, so switching views
  /// never reloads and never disagrees.
  final WorkspaceExplorerController explorer;

  /// Opens one of the collection's objects in the workspace.
  final ValueChanged<ViewPB> onOpen;

  /// Persists this view's own state, e.g. reading position or zoom.
  final ValueChanged<Map<String, dynamic>> onStateChanged;

  CollectionKind get kind => metadata.kind;

  /// The state this view persisted the last time it was open.
  Map<String, dynamic> get state => metadata.stateFor(definition.id);
}

typedef CollectionViewBuilder = Widget Function(
  BuildContext context,
  CollectionViewContext collection,
);

/// One way of looking at a collection.
///
/// Views are registered against a collection type rather than built into it,
/// so a new visualisation is added without touching the collection itself.
@immutable
class CollectionViewDefinition {
  const CollectionViewDefinition({
    required this.id,
    required this.labelKey,
    required this.icon,
    required this.builder,
  });

  final String id;
  final String labelKey;
  final IconData icon;
  final CollectionViewBuilder builder;

  String get label => labelKey.tr();
}

/// A collection type: what it is for, and how it can be looked at.
@immutable
class CollectionTypeDefinition {
  const CollectionTypeDefinition({
    required this.kind,
    required this.labelKey,
    required this.descriptionKey,
    required this.defaultNameKey,
    required this.icon,
    required this.accent,
    required this.views,
  });

  final CollectionKind kind;
  final String labelKey;
  final String descriptionKey;
  final String defaultNameKey;
  final IconData icon;

  /// The hue that identifies this type. Always blended against the surface
  /// rather than painted flat, so it reads the same in paper, light and dark.
  final Color accent;

  final List<CollectionViewDefinition> views;

  String get label => labelKey.tr();
  String get description => descriptionKey.tr();
  String get defaultName => defaultNameKey.tr();

  CollectionViewDefinition get defaultView => views.first;

  CollectionViewDefinition? viewById(String? id) {
    if (id == null) {
      return null;
    }
    for (final view in views) {
      if (view.id == id) {
        return view;
      }
    }
    return null;
  }

  CollectionTypeDefinition withViews(List<CollectionViewDefinition> views) =>
      CollectionTypeDefinition(
        kind: kind,
        labelKey: labelKey,
        descriptionKey: descriptionKey,
        defaultNameKey: defaultNameKey,
        icon: icon,
        accent: accent,
        views: views,
      );
}

/// The catalogue of collection types and their adaptive views.
abstract final class CollectionRegistry {
  static final Map<CollectionKind, CollectionTypeDefinition> _types = {};
  static bool _initialized = false;

  static void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    registerBuiltInCollections();
  }

  static void register(CollectionTypeDefinition definition) {
    _ensureInitialized();
    _types[definition.kind] = definition;
  }

  /// Adds [view] to [kind]. This is the extension point: a new visualisation
  /// only has to register itself.
  static void registerView(
    CollectionKind kind,
    CollectionViewDefinition view, {
    int? index,
  }) {
    final definition = typeFor(kind);
    final views = definition.views
        .where((existing) => existing.id != view.id)
        .toList(growable: true);
    views.insert(index?.clamp(0, views.length) ?? views.length, view);
    _types[kind] = definition.withViews(views);
  }

  static List<CollectionTypeDefinition> get types {
    _ensureInitialized();
    return [
      for (final kind in CollectionKind.values)
        if (_types[kind] != null) _types[kind]!,
    ];
  }

  static CollectionTypeDefinition typeFor(CollectionKind kind) {
    _ensureInitialized();
    final definition = _types[kind];
    if (definition == null) {
      throw StateError('No collection type is registered for $kind.');
    }
    return definition;
  }

  /// The view [id] names, or the type's default when the stored view is gone.
  static CollectionViewDefinition resolveView(CollectionKind kind, String? id) {
    final definition = typeFor(kind);
    return definition.viewById(id) ?? definition.defaultView;
  }

  @visibleForTesting
  static void reset() {
    _types.clear();
    _initialized = false;
  }
}
