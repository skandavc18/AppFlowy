import 'dart:io';

import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_thumbnail_cache.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_explorer_models.dart';
import 'package:flutter/material.dart';

/// A small preview of a picture or a clip, used where a file icon would go.
///
/// Only files kept in AppFlowy's own storage are previewed. A cloud object
/// would need a download and an access token, which is far too much work for a
/// sidebar row, so those keep their icon.
class WorkspaceItemThumbnail extends StatelessWidget {
  const WorkspaceItemThumbnail({
    super.key,
    required this.path,
    required this.isVideo,
    required this.size,
    required this.fallback,
  });

  final String path;
  final bool isVideo;
  final double size;

  /// Shown while the file cannot be decoded — a broken picture, a clip.
  final Widget fallback;

  /// Whether [item] has a local picture or clip worth previewing.
  static String? localSourceFor(WorkspaceExplorerItem item) {
    if (item.kind != WorkspaceExplorerItemKind.file) {
      return null;
    }
    final source = item.metadata?.storageUrl;
    if (source == null || source.isEmpty) {
      return null;
    }
    final scheme = Uri.tryParse(source)?.scheme.toLowerCase() ?? '';
    if (scheme == 'http' || scheme == 'https') {
      return null;
    }
    return isPreviewableMedia(item.name) ? source : null;
  }

  static bool isPreviewableMedia(String name) {
    final lower = name.toLowerCase();
    return imgExtensionRegex.hasMatch(lower) ||
        videoExtensionRegex.hasMatch(lower);
  }

  static bool isVideoName(String name) =>
      videoExtensionRegex.hasMatch(name.toLowerCase());

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.24);
    final ratio = MediaQuery.devicePixelRatioOf(context);
    if (isVideo) {
      return _VideoThumbnail(
        path: path,
        size: size,
        radius: radius,
        cacheWidth: (size * ratio).round(),
      );
    }

    return ClipRRect(
      borderRadius: radius,
      child: SizedBox.square(
        dimension: size,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          // A sidebar row never needs more than its own pixels; decoding a
          // photograph at full size would stall the raster thread.
          cacheWidth: (size * ratio).round(),
          errorBuilder: (_, __, ___) => fallback,
        ),
      ),
    );
  }
}

/// A clip's poster frame, with the film icon while it is being decoded.
class _VideoThumbnail extends StatefulWidget {
  const _VideoThumbnail({
    required this.path,
    required this.size,
    required this.radius,
    required this.cacheWidth,
  });

  final String path;
  final double size;
  final BorderRadius radius;
  final int cacheWidth;

  @override
  State<_VideoThumbnail> createState() => _VideoThumbnailState();
}

class _VideoThumbnailState extends State<_VideoThumbnail> {
  late Future<File?> poster;

  @override
  void initState() {
    super.initState();
    poster = VideoThumbnailCache.instance.thumbnailFor(widget.path);
  }

  @override
  void didUpdateWidget(covariant _VideoThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.path != widget.path) {
      poster = VideoThumbnailCache.instance.thumbnailFor(widget.path);
    }
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = _VideoTile(size: widget.size, radius: widget.radius);
    return FutureBuilder<File?>(
      future: poster,
      builder: (context, snapshot) {
        final file = snapshot.data;
        if (file == null) {
          return placeholder;
        }
        return ClipRRect(
          borderRadius: widget.radius,
          child: SizedBox.square(
            dimension: widget.size,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.file(
                  file,
                  fit: BoxFit.cover,
                  cacheWidth: widget.cacheWidth,
                  errorBuilder: (_, __, ___) => placeholder,
                ),
                Center(
                  child: Icon(
                    Icons.play_arrow_rounded,
                    size: widget.size * 0.52,
                    color: Colors.white.withValues(alpha: 0.92),
                    shadows: const [
                      Shadow(color: Color(0x8C000000), blurRadius: 4),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Shown while the poster is being decoded, or when the clip has no frame.
class _VideoTile extends StatelessWidget {
  const _VideoTile({required this.size, required this.radius});

  final double size;
  final BorderRadius radius;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox.square(
      dimension: size,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              scheme.tertiary.withValues(alpha: 0.30),
              scheme.tertiary.withValues(alpha: 0.14),
            ],
          ),
        ),
        child: Center(
          child: Icon(
            Icons.play_arrow_rounded,
            size: size * 0.62,
            color: scheme.tertiary,
          ),
        ),
      ),
    );
  }
}
