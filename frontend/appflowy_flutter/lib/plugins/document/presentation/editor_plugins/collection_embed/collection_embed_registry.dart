import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_controller.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/collection_embed_previews.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Everything a preview is handed. A preview never reaches for the editor,
/// the tab bar or the block node — it only reads this and calls back.
@immutable
class CollectionEmbedContext {
  const CollectionEmbedContext({
    required this.collection,
    required this.controller,
    required this.settings,
    required this.theme,
    required this.definition,
    required this.onSettingsChanged,
    required this.onOpenObject,
    required this.onOpenCollection,
    required this.onFullscreen,
    required this.onRefresh,
    required this.onShowMenu,
    this.userProfile,
    this.hovered = false,
    this.fullscreen = false,
    this.editable = true,
  });

  final ViewPB collection;
  final CollectionEmbedController controller;
  final CollectionEmbedSettings settings;
  final CollectionEmbedTheme theme;
  final CollectionEmbedDefinition definition;
  final UserProfilePB? userProfile;

  /// True while the pointer is anywhere over the widget. Previews use it to
  /// reveal their own controls without a second `MouseRegion`.
  final bool hovered;
  final bool fullscreen;
  final bool editable;

  final ValueChanged<CollectionEmbedSettings> onSettingsChanged;

  /// Opens one object of the collection in a workspace tab.
  final ValueChanged<ViewPB> onOpenObject;

  /// Opens the whole collection — the clear path out of the widget.
  final VoidCallback onOpenCollection;
  final VoidCallback onFullscreen;
  final VoidCallback onRefresh;

  /// Raises the shared context menu at a point on screen.
  final ValueChanged<Offset> onShowMenu;

  CollectionKind? get kind => collection.collection?.kind;

  CollectionEmbedSize get size => settings.size;

  /// The preview style in force, already resolved against the type's default.
  String get style => settings.style ?? definition.defaultStyle;

  bool isStyle(String id) => style == id;

  List<ViewPB> get children => controller.children;

  List<ViewPB> slice([int? limit]) =>
      controller.slice(settings, limit ?? definition.defaultItemLimit);

  CollectionEmbedContext copyWith({
    CollectionEmbedSettings? settings,
    bool? hovered,
    bool? fullscreen,
  }) =>
      CollectionEmbedContext(
        collection: collection,
        controller: controller,
        settings: settings ?? this.settings,
        theme: theme,
        definition: definition,
        userProfile: userProfile,
        hovered: hovered ?? this.hovered,
        fullscreen: fullscreen ?? this.fullscreen,
        editable: editable,
        onSettingsChanged: onSettingsChanged,
        onOpenObject: onOpenObject,
        onOpenCollection: onOpenCollection,
        onFullscreen: onFullscreen,
        onRefresh: onRefresh,
        onShowMenu: onShowMenu,
      );
}

typedef CollectionEmbedPreviewBuilder = Widget Function(
  BuildContext context,
  CollectionEmbedContext embed,
);

/// One way a collection type can be previewed inside a page.
@immutable
class CollectionEmbedStyle {
  const CollectionEmbedStyle({
    required this.id,
    required this.labelKey,
    required this.icon,
    this.supportsColumns = false,
  });

  final String id;
  final String labelKey;
  final IconData icon;

  /// Whether "items per row" means anything for this style.
  final bool supportsColumns;

  String get label => labelKey.tr();
}

/// How one collection type presents itself as a widget.
@immutable
class CollectionEmbedDefinition {
  const CollectionEmbedDefinition({
    required this.kind,
    required this.styles,
    required this.builder,
    this.defaultItemLimit = 6,
    this.compactHeight = 132,
    this.mediumHeight = 268,
    this.largeHeight = 420,
    this.flush = false,
    this.supportsItemLimit = true,
    this.showsHeading = true,
  });

  /// `null` is the plain workspace folder — a collection of things with no
  /// declared purpose, which still deserves a proper visual preview.
  final CollectionKind? kind;
  final List<CollectionEmbedStyle> styles;
  final CollectionEmbedPreviewBuilder builder;
  final int defaultItemLimit;
  final double compactHeight;
  final double mediumHeight;
  final double largeHeight;

  /// A flush type paints no card at all — its content continues the page.
  final bool flush;
  final bool supportsItemLimit;

  /// Whether the frame draws the shared identity row above the preview.
  final bool showsHeading;

  String get defaultStyle => styles.first.id;

  CollectionEmbedStyle styleFor(String? id) => styles.firstWhere(
        (style) => style.id == id,
        orElse: () => styles.first,
      );

  double heightFor(CollectionEmbedSize size) => switch (size) {
        CollectionEmbedSize.compact => compactHeight,
        CollectionEmbedSize.medium => mediumHeight,
        CollectionEmbedSize.large => largeHeight,
      };
}

/// The one place a collection type says how it looks inside a page.
///
/// Adding a type — or a new way of previewing an existing one — never touches
/// the frame, the menu or the block.
abstract final class CollectionEmbedRegistry {
  static final Map<CollectionKind?, CollectionEmbedDefinition> _definitions =
      <CollectionKind?, CollectionEmbedDefinition>{};
  static bool _initialized = false;

  static void register(CollectionEmbedDefinition definition) {
    _definitions[definition.kind] = definition;
  }

  static CollectionEmbedDefinition definitionFor(CollectionKind? kind) {
    _ensureInitialized();
    return _definitions[kind] ?? _definitions[null]!;
  }

  @visibleForTesting
  static void reset() {
    _definitions.clear();
    _initialized = false;
  }

  static void _ensureInitialized() {
    if (_initialized) {
      return;
    }
    _initialized = true;
    registerBuiltInCollectionEmbeds();
  }
}
