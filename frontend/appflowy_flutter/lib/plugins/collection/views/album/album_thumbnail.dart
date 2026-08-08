import 'dart:io';

import 'package:appflowy/plugins/collection/collection_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/video_thumbnail_cache.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:flutter/material.dart';

/// The one tile every album view is built from.
///
/// A picture, a video poster and an audio card are all drawn the same way, so
/// a wall of mixed media reads as one album rather than three.
class AlbumThumbnail extends StatefulWidget {
  const AlbumThumbnail({
    super.key,
    required this.item,
    required this.palette,
    this.decodeWidth,
    this.radius = 10,
    this.showKindBadge = true,
  });

  final AlbumMediaItem item;
  final CollectionPalette palette;

  /// The width the bitmap is decoded at. A wall of forty megapixel pictures
  /// decoded at full size costs gigabytes and stalls the raster thread.
  final double? decodeWidth;
  final double radius;
  final bool showKindBadge;

  @override
  State<AlbumThumbnail> createState() => _AlbumThumbnailState();
}

class _AlbumThumbnailState extends State<AlbumThumbnail> {
  Future<File?>? poster;

  @override
  void initState() {
    super.initState();
    _resolvePoster();
  }

  @override
  void didUpdateWidget(covariant AlbumThumbnail oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.item.path != widget.item.path) {
      _resolvePoster();
    }
  }

  void _resolvePoster() {
    poster = widget.item.kind == AlbumMediaKind.video && widget.item.isLocal
        ? VideoThumbnailCache.instance.thumbnailFor(widget.item.path)
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(widget.radius),
      child: Stack(
        fit: StackFit.expand,
        children: [
          _buildSurface(context),
          if (widget.showKindBadge && widget.item.kind.plays)
            Positioned(
              left: 8,
              bottom: 8,
              child: _KindBadge(kind: widget.item.kind),
            ),
        ],
      ),
    );
  }

  Widget _buildSurface(BuildContext context) {
    final palette = widget.palette;
    switch (widget.item.kind) {
      case AlbumMediaKind.image:
        return _buildPicture(context, File(widget.item.path));
      case AlbumMediaKind.video:
        return FutureBuilder<File?>(
          future: poster,
          builder: (context, snapshot) {
            final file = snapshot.data;
            if (file == null) {
              return _AlbumTilePlaceholder(
                palette: palette,
                icon: Icons.movie_rounded,
                busy: snapshot.connectionState != ConnectionState.done,
              );
            }
            return _buildPicture(context, file);
          },
        );
      case AlbumMediaKind.audio:
        return _AlbumTilePlaceholder(
          palette: palette,
          icon: Icons.graphic_eq_rounded,
          label: widget.item.name,
        );
    }
  }

  Widget _buildPicture(BuildContext context, File file) {
    if (!widget.item.isLocal && widget.item.kind == AlbumMediaKind.image) {
      // A picture the service refused is not coming; anything else is still
      // on its way, and a cloud glyph there reads as "cannot be shown".
      return widget.item.unavailable
          ? _AlbumTilePlaceholder(
              palette: widget.palette,
              icon: Icons.cloud_off_rounded,
            )
          : _AlbumTilePlaceholder(palette: widget.palette, busy: true);
    }
    final ratio = MediaQuery.devicePixelRatioOf(context);
    final width = widget.decodeWidth;
    return Image.file(
      file,
      fit: BoxFit.cover,
      cacheWidth: width == null ? null : (width * ratio).round(),
      gaplessPlayback: true,
      errorBuilder: (context, _, __) => _AlbumTilePlaceholder(
        palette: widget.palette,
        icon: Icons.broken_image_rounded,
      ),
      frameBuilder: (context, child, frame, wasSynchronous) {
        if (wasSynchronous || frame != null) {
          return child;
        }
        return _AlbumTilePlaceholder(palette: widget.palette, busy: true);
      },
    );
  }
}

class _AlbumTilePlaceholder extends StatelessWidget {
  const _AlbumTilePlaceholder({
    required this.palette,
    this.icon,
    this.label,
    this.busy = false,
  });

  final CollectionPalette palette;
  final IconData? icon;
  final String? label;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Color.alphaBlend(
        palette.accent.withValues(alpha: 0.06),
        palette.surface,
      ),
      child: Center(
        child: busy
            ? SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 1.6,
                  color: palette.textMuted,
                ),
              )
            : Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    icon ?? Icons.image_outlined,
                    size: 22,
                    color: palette.textMuted,
                  ),
                  if (label != null) ...[
                    const SizedBox(height: 8),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14),
                      child: Text(
                        label!,
                        maxLines: 2,
                        textAlign: TextAlign.center,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: palette.textSecondary,
                          fontSize: 11.5,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
      ),
    );
  }
}

class _KindBadge extends StatelessWidget {
  const _KindBadge({required this.kind});

  final AlbumMediaKind kind;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.46),
        shape: BoxShape.circle,
      ),
      child: Icon(
        kind == AlbumMediaKind.video
            ? Icons.play_arrow_rounded
            : Icons.music_note_rounded,
        size: 13,
        color: Colors.white,
      ),
    );
  }
}
