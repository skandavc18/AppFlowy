import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_view_factory.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter/foundation.dart';

enum AlbumMediaKind {
  image,
  video,
  audio;

  bool get isVisual => this != AlbumMediaKind.audio;
  bool get plays => this != AlbumMediaKind.image;
}

/// One piece of media in an album.
///
/// An album references the workspace files that already exist — nothing is
/// copied, and the file keeps working everywhere else in AppFlowy.
@immutable
class AlbumMediaItem {
  const AlbumMediaItem({
    required this.view,
    required this.kind,
    required this.path,
    required this.index,
    this.byteSize,
    this.modifiedAt,
    this.unavailable = false,
  });

  final ViewPB view;
  final AlbumMediaKind kind;

  /// Where the bytes live. Empty when the file has not been stored yet.
  final String path;

  /// Position in the album's own order.
  final int index;
  final int? byteSize;
  final DateTime? modifiedAt;

  /// Set when the service was asked for this and would not give it.
  final bool unavailable;

  String get id => view.id;
  String get name => view.name;
  bool get isLocal => path.isNotEmpty && !path.startsWith('http');

  /// Compared by what a tile actually draws.
  ///
  /// A hosted album keeps the same ids from the first listing to the last
  /// picture arriving — the PATH is what changes — so comparing identity
  /// alone would report "nothing happened" and the wall would never repaint.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is AlbumMediaItem &&
          other.id == id &&
          other.name == name &&
          other.kind == kind &&
          other.path == path &&
          other.index == index &&
          other.byteSize == byteSize &&
          other.modifiedAt == modifiedAt &&
          other.unavailable == unavailable;

  @override
  int get hashCode => Object.hash(
        id,
        name,
        kind,
        path,
        index,
        byteSize,
        modifiedAt,
        unavailable,
      );
}

AlbumMediaKind? albumMediaKindOf(ViewPB view) {
  if (!view.isWorkspaceFile) {
    return null;
  }
  final name = view.name.toLowerCase();
  if (imgExtensionRegex.hasMatch(name)) {
    return AlbumMediaKind.image;
  }
  if (videoExtensionRegex.hasMatch(name)) {
    return AlbumMediaKind.video;
  }
  if (audioExtensionRegex.hasMatch(name)) {
    return AlbumMediaKind.audio;
  }
  return null;
}

/// The media among [views], in the order the backend stores them.
List<AlbumMediaItem> albumMediaFrom(Iterable<ViewPB> views) {
  final items = <AlbumMediaItem>[];
  for (final view in views) {
    final kind = albumMediaKindOf(view);
    if (kind == null) {
      continue;
    }
    final metadata = view.workspaceItem;
    final edited = view.lastEdited.toInt();
    items.add(
      AlbumMediaItem(
        view: view,
        kind: kind,
        path: metadata?.storageUrl ?? '',
        index: items.length,
        byteSize: metadata?.size,
        modifiedAt: edited > 0
            ? DateTime.fromMillisecondsSinceEpoch(edited * 1000)
            : metadata?.modifiedAt,
      ),
    );
  }
  return items;
}

/// The media in a hosted album.
///
/// The kind comes from what the service says a thing is, not from its name: a
/// photo library item is often called `IMG_0042` with no extension at all, and
/// reading the name would silently drop the whole album.
List<AlbumMediaItem> albumMediaFromProvider(
  Iterable<ProviderItemView> items, {
  bool Function(String nodeId)? refused,
}) {
  final media = <AlbumMediaItem>[];
  for (final item in items) {
    final kind = switch (item.node.kind) {
      ProviderNodeKind.image => AlbumMediaKind.image,
      ProviderNodeKind.video => AlbumMediaKind.video,
      ProviderNodeKind.audio => AlbumMediaKind.audio,
      _ => null,
    };
    if (kind == null) {
      continue;
    }
    media.add(
      AlbumMediaItem(
        view: item.view,
        kind: kind,
        path: item.view.workspaceItem?.storageUrl ?? '',
        index: media.length,
        byteSize: item.node.byteSize,
        modifiedAt: item.node.createdAt ?? item.node.modifiedAt,
        unavailable: refused?.call(item.node.id) ?? false,
      ),
    );
  }
  return media;
}
