import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_thumbnail_cache.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/collections/bookmark/bookmark_link.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/application/view/view_ext.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_cover_image.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/material.dart';

/// The local path a view's file is stored at, or `null` when it lives in the
/// cloud or is not a stored file at all.
///
/// `WorkspaceFileReference.fromView` throws for anything that is not a stored
/// file, which is far too sharp for artwork resolution — a widget that cannot
/// find a picture should draw a glyph, not fail.
String? localFilePathOf(ViewPB view) {
  final url = view.workspaceItem?.storageUrl;
  if (url == null || url.isEmpty) {
    return null;
  }
  final scheme = Uri.tryParse(url)?.scheme.toLowerCase() ?? '';
  if (scheme == 'http' || scheme == 'https') {
    return null;
  }
  return url;
}

/// Where a view's artwork comes from, worked out once so the widget below
/// stays a pure `build`.
enum CollectionArtworkSource { cover, picture, video, remote, none }

CollectionArtworkSource collectionArtworkSourceOf(ViewPB view) {
  final bookmark = view.bookmark;
  if (bookmark != null) {
    return bookmark.imageUrl != null && bookmark.imageUrl!.isNotEmpty
        ? CollectionArtworkSource.remote
        : CollectionArtworkSource.none;
  }
  final cover = view.cover;
  if (cover != null && cover.type != PageStyleCoverImageType.none) {
    return CollectionArtworkSource.cover;
  }
  final path = localFilePathOf(view);
  if (path != null) {
    final lower = path.toLowerCase();
    if (imgExtensionRegex.hasMatch(lower)) {
      return CollectionArtworkSource.picture;
    }
    if (videoExtensionRegex.hasMatch(lower)) {
      return CollectionArtworkSource.video;
    }
  }
  return CollectionArtworkSource.none;
}

bool viewHasArtwork(ViewPB view) =>
    collectionArtworkSourceOf(view) != CollectionArtworkSource.none;

/// One object's artwork, at whatever box the caller gives it.
///
/// Pictures decode at the rendered width rather than their intrinsic size — a
/// wall of forty megapixel photographs would otherwise cost gigabytes and
/// stall the raster thread, which is exactly what makes an embed feel heavy.
class CollectionArtwork extends StatefulWidget {
  const CollectionArtwork({
    super.key,
    required this.view,
    required this.theme,
    this.userProfile,
    this.decodeWidth,
    this.fit = BoxFit.cover,
    this.fallback,
    this.showGlyphFallback = true,
  });

  final ViewPB view;
  final CollectionEmbedTheme theme;
  final UserProfilePB? userProfile;
  final double? decodeWidth;
  final BoxFit fit;
  final Widget? fallback;
  final bool showGlyphFallback;

  @override
  State<CollectionArtwork> createState() => _CollectionArtworkState();
}

class _CollectionArtworkState extends State<CollectionArtwork> {
  Future<File?>? poster;
  CollectionArtworkSource source = CollectionArtworkSource.none;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant CollectionArtwork oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.view.id != widget.view.id ||
        oldWidget.view.extra != widget.view.extra) {
      _resolve();
    }
  }

  void _resolve() {
    source = collectionArtworkSourceOf(widget.view);
    final path = localFilePathOf(widget.view);
    poster = source == CollectionArtworkSource.video && path != null
        ? VideoThumbnailCache.instance.thumbnailFor(path)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    switch (source) {
      case CollectionArtworkSource.cover:
        return ViewCoverImage(
          cover: widget.view.cover!,
          userProfile: widget.userProfile,
          fit: widget.fit,
          fallback: _fallback(context),
        );
      case CollectionArtworkSource.picture:
        final path = localFilePathOf(widget.view)!;
        return Image.file(
          File(path),
          fit: widget.fit,
          cacheWidth: _cacheWidth,
          errorBuilder: (_, __, ___) => _fallback(context),
        );
      case CollectionArtworkSource.video:
        return FutureBuilder<File?>(
          future: poster,
          builder: (context, snapshot) {
            final file = snapshot.data;
            if (file == null) {
              return _fallback(context);
            }
            return Image.file(
              file,
              fit: widget.fit,
              cacheWidth: _cacheWidth,
              errorBuilder: (_, __, ___) => _fallback(context),
            );
          },
        );
      case CollectionArtworkSource.remote:
        return FlowyNetworkImage(
          url: widget.view.bookmark!.imageUrl!,
          userProfilePB: widget.userProfile,
          fit: widget.fit,
          errorWidgetBuilder: (_, __, ___) => _fallback(context),
        );
      case CollectionArtworkSource.none:
        return _fallback(context);
    }
  }

  int? get _cacheWidth {
    final width = widget.decodeWidth;
    if (width == null || !width.isFinite || width <= 0) {
      return null;
    }
    final ratio = MediaQuery.maybeDevicePixelRatioOf(context) ?? 1;
    return (width * ratio).round().clamp(64, 2048);
  }

  Widget _fallback(BuildContext context) =>
      widget.fallback ??
      (widget.showGlyphFallback
          ? CollectionArtworkGlyph(view: widget.view, theme: widget.theme)
          : const SizedBox.shrink());
}

/// Artwork for an object that has none: the object's own hue plus its glyph.
///
/// A deterministic hue per object is what stops a wall of documents reading
/// as a row of identical grey rectangles.
class CollectionArtworkGlyph extends StatelessWidget {
  const CollectionArtworkGlyph({
    super.key,
    required this.view,
    required this.theme,
    this.icon,
  });

  final ViewPB view;
  final CollectionEmbedTheme theme;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final hue = collectionObjectHue(view.id, dark: theme.isDark);
    return LayoutBuilder(
      builder: (context, constraints) {
        final side = constraints.biggest.shortestSide;
        return DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                Color.alphaBlend(
                  hue.withValues(alpha: theme.isDark ? 0.30 : 0.20),
                  theme.sunken,
                ),
                Color.alphaBlend(
                  hue.withValues(alpha: theme.isDark ? 0.14 : 0.08),
                  theme.sunken,
                ),
              ],
            ),
          ),
          child: Center(
            child: Icon(
              icon ?? _glyph,
              size: (side * 0.30).clamp(14.0, 34.0),
              color: hue.withValues(alpha: theme.isDark ? 0.86 : 0.72),
            ),
          ),
        );
      },
    );
  }

  IconData get _glyph {
    if (view.bookmark != null) {
      return Icons.link_rounded;
    }
    if (view.isCollection) {
      return Icons.widgets_rounded;
    }
    if (view.isWorkspaceFolder) {
      return Icons.folder_rounded;
    }
    if (view.isWorkspaceFile) {
      return fileIconForName(view.name);
    }
    if (view.isDatabase) {
      return Icons.table_chart_rounded;
    }
    return Icons.description_rounded;
  }
}

/// A stable hue for an object, seeded from its id.
///
/// `String.hashCode` is not promised to be stable across runs, so the seed is
/// an FNV walk — the same object keeps its colour between sessions.
Color collectionObjectHue(String id, {required bool dark}) {
  var hash = 0x811c9dc5;
  for (var i = 0; i < id.length; i++) {
    hash ^= id.codeUnitAt(i);
    hash = (hash * 0x01000193) & 0xFFFFFFFF;
  }
  final hue = (hash % 360).toDouble();
  return HSLColor.fromAHSL(
    1,
    hue,
    dark ? 0.42 : 0.48,
    dark ? 0.62 : 0.52,
  ).toColor();
}
