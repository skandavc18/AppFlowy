import 'package:appflowy/shared/patterns/file_type_patterns.dart';
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
  });

  final ViewPB view;
  final AlbumMediaKind kind;

  /// Where the bytes live. Empty when the file has not been stored yet.
  final String path;

  /// Position in the album's own order.
  final int index;
  final int? byteSize;
  final DateTime? modifiedAt;

  String get id => view.id;
  String get name => view.name;
  bool get isLocal => path.isNotEmpty && !path.startsWith('http');
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
