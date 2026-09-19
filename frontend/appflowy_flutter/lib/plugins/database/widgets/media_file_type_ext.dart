import 'package:flutter/material.dart';

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/file/file_preview_kind.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/patterns/file_type_patterns.dart';
import 'package:appflowy/shared/premium_theme.dart';
import 'package:appflowy/util/xfile_ext.dart';
import 'package:appflowy/workspace/presentation/widgets/image_viewer/image_provider.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/media_entities.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';

extension MediaFileTypeResolution on MediaFilePB {
  /// Repairs old image classification for presentation only. The protobuf,
  /// attachment identity and explicit non-image types remain untouched.
  MediaFileTypePB get effectiveFileType {
    if (fileType != MediaFileTypePB.Other && fileType != MediaFileTypePB.Link) {
      return fileType;
    }

    final namedType = inferFileType(name);
    if (namedType == FileType.image ||
        (namedType == FileType.other && inferFileType(url) == FileType.image)) {
      return MediaFileTypePB.Image;
    }
    return fileType;
  }

  bool get isImage => effectiveFileType == MediaFileTypePB.Image;

  /// A label only: never rename the attachment or expose a signed query.
  /// Keep actual filenames (including literal percent signs) verbatim.
  String get displayName {
    if (name.trim().isNotEmpty) return name;
    final basename = fileTypePath(url).split(RegExp(r'[/\\]')).last;
    if (basename.trim().isNotEmpty) return basename;
    return LocaleKeys.document_plugins_file_name.tr();
  }

  /// Resolve the same glyph as a page file without opening or fetching it.
  /// MediaFilePB stores no MIME string; its explicit category is the remaining
  /// MIME-derived metadata, and must not be replaced by a misleading suffix.
  IconData get displayIcon {
    if (isImage) return Icons.image_rounded;
    switch (fileType) {
      case MediaFileTypePB.Audio:
        return Icons.audiotrack_rounded;
      case MediaFileTypePB.Video:
        return Icons.movie_rounded;
      case MediaFileTypePB.Archive:
        return Icons.folder_zip_rounded;
      default:
        break;
    }

    for (final source in [name.trim(), url]) {
      final path = fileTypePath(source);
      final kind = filePreviewKindFromName(path);
      if (fileType == MediaFileTypePB.Document &&
          kind != FilePreviewKind.pdf &&
          !isOfficeFile(path)) {
        continue;
      }
      if (fileType == MediaFileTypePB.Text &&
          (kind == null ||
              kind == FilePreviewKind.pdf ||
              kind == FilePreviewKind.archive)) {
        continue;
      }
      // HTML links remain browser links, not downloadable document previews.
      if (fileType == MediaFileTypePB.Link && kind == FilePreviewKind.html) {
        continue;
      }
      final icon = fileIconForName(path);
      if (icon != Icons.insert_drive_file_rounded &&
          icon != Icons.image_rounded) {
        return icon;
      }
      switch (inferFileType(path)) {
        case FileType.video:
          return Icons.movie_rounded;
        case FileType.audio:
          return Icons.audiotrack_rounded;
        case FileType.archive:
          return Icons.folder_zip_rounded;
        case FileType.text:
          return Icons.description_rounded;
        default:
          break;
      }
    }
    return switch (fileType) {
      MediaFileTypePB.Link => Icons.link_rounded,
      MediaFileTypePB.Document ||
      MediaFileTypePB.Text =>
        Icons.description_rounded,
      _ => Icons.insert_drive_file_rounded,
    };
  }
}

/// Compact attachment chrome shared by grid cells and row details. Images
/// keep their own thumbnail layout; this never constructs a document/player
/// preview or reads an attachment just to discover its type.
class MediaFileLabel extends StatelessWidget {
  const MediaFileLabel({
    super.key,
    required this.file,
    this.onTap,
    this.trailingInset = 0,
  });

  final MediaFilePB file;
  final VoidCallback? onTap;
  final double trailingInset;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final palette = PremiumThemeExtension.maybeOf(context);
    final radius = BorderRadius.circular(6);
    return Tooltip(
      message: file.displayName,
      excludeFromSemantics: true,
      child: Material(
        key: ValueKey('media-attachment-${file.id}'),
        color: EditorSurfaceStyle.previewBackgroundFor(
          theme.brightness,
          palette?.surface ?? theme.colorScheme.surfaceContainerLow,
          isPaper: PaperTheme.isEnabled(context),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: EditorSurfaceStyle.embedBorder(context)),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          hoverColor: palette?.hoverOverlay ?? theme.hoverColor,
          focusColor: palette?.selectedOverlay ?? theme.focusColor,
          child: Semantics(
            label: file.displayName,
            button: onTap != null,
            excludeSemantics: true,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 200),
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 24),
                  // Padding clamps the name's remaining width to zero without
                  // flex overflow. Keep a legible icon instead of squeezing it
                  // into a sliver; the Material clips only at the actual edge.
                  // Stack/Padding support the grid's IntrinsicHeight too.
                  child: Stack(
                    clipBehavior: Clip.none,
                    alignment: AlignmentDirectional.centerStart,
                    children: [
                      Padding(
                        padding: EdgeInsetsDirectional.only(
                          start: 28,
                          end: trailingInset,
                        ),
                        child: Text(
                          file.displayName,
                          key: ValueKey('media-attachment-name-${file.id}'),
                          maxLines: 1,
                          softWrap: false,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: palette?.textPrimary ??
                                theme.colorScheme.onSurface,
                            fontSize: 12,
                          ),
                        ),
                      ),
                      PositionedDirectional(
                        start: 0,
                        top: 0,
                        bottom: 0,
                        width: 24,
                        child: Center(
                          child: TooltipVisibility(
                            visible: false,
                            child: MediaFileThumbnail(
                              file: file,
                              size: const Size.square(24),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The actual thumbnail used by the grid and row-detail media skins.
///
/// A single decode axis preserves the source aspect ratio; BoxFit.cover then
/// crops to the tile rather than stretching a rectangular photo into a square.
/// No image capability is inferred from the filename beyond classification:
/// unavailable files and unsupported codecs display a visible fallback.
class MediaFileThumbnail extends StatelessWidget {
  MediaFileThumbnail({
    Key? key,
    required this.file,
    required this.size,
    this.userProfile,
    this.borderRadius = const BorderRadius.all(Radius.circular(6)),
  }) : super(key: key ?? ValueKey(file.id));

  final MediaFilePB file;
  final Size size;
  final UserProfilePB? userProfile;
  final BorderRadius borderRadius;

  @override
  Widget build(BuildContext context) {
    final canLoad = file.isImage &&
        (file.uploadType != FileUploadTypePB.CloudFile || userProfile != null);
    final iconSize = (size.shortestSide * 0.36).clamp(12.0, 26.0);
    Widget fallback(bool failed) => _MediaFileFallback(
          file: file,
          failed: failed,
          iconSize: iconSize,
        );

    return RepaintBoundary(
      child: ClipRRect(
        borderRadius: borderRadius,
        child: SizedBox.fromSize(
          size: size,
          child: canLoad
              ? AFImage(
                  key: ValueKey(file.id),
                  url: file.url,
                  uploadType: file.uploadType,
                  userProfile: userProfile,
                  width: size.width,
                  height: size.height,
                  cacheWidth:
                      (size.width * MediaQuery.devicePixelRatioOf(context))
                          .ceil()
                          .clamp(1, 4096),
                  errorBuilder: (_, __, ___) => fallback(true),
                )
              : fallback(file.isImage),
        ),
      ),
    );
  }
}

class _MediaFileFallback extends StatelessWidget {
  const _MediaFileFallback({
    required this.file,
    required this.failed,
    this.iconSize = 26,
  });

  final MediaFilePB file;
  final bool failed;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = failed
        ? '${file.displayName}: ${LocaleKeys.document_imageBlock_error_invalidImage.tr()}'
        : file.displayName;
    return Semantics(
      label: label,
      image: failed,
      child: Tooltip(
        message: label,
        child: ColoredBox(
          key: ValueKey('media-${failed ? 'unavailable' : 'file'}-${file.id}'),
          color: EditorSurfaceStyle.previewBackgroundFor(
            theme.brightness,
            theme.colorScheme.surfaceContainerHighest,
            isPaper: PaperTheme.isEnabled(context),
          ),
          child: Center(
            child: failed
                ? Icon(
                    Icons.broken_image_rounded,
                    size: iconSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  )
                : Icon(
                    file.displayIcon,
                    key: ValueKey('media-file-icon-${file.id}'),
                    size: iconSize,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
          ),
        ),
      ),
    );
  }
}

/// An ordered, read-only projection of a media cell for its image viewer.
/// Uses AFImage too so local file URIs and decode failures work in full view.
class MediaFileImageProvider extends AFImageProvider {
  MediaFileImageProvider({
    required Iterable<MediaFilePB> files,
    String? initialFileId,
    super.onDeleteImage,
  })  : files = List.unmodifiable(files.where((file) => file.isImage)),
        _initialFileId = initialFileId;

  final List<MediaFilePB> files;
  final String? _initialFileId;

  @override
  int get imageCount => files.length;

  @override
  String getImageName(int index) =>
      files[index].name.isEmpty ? super.getImageName(index) : files[index].name;

  @override
  int get initialIndex {
    final index = files.indexWhere((file) => file.id == _initialFileId);
    return index < 0 ? 0 : index;
  }

  @override
  ImageBlockData getImage(int index) {
    final file = files[index];
    return ImageBlockData(
      url: file.url,
      type: switch (file.uploadType) {
        FileUploadTypePB.LocalFile => CustomImageType.local,
        FileUploadTypePB.CloudFile => CustomImageType.internal,
        _ => CustomImageType.external,
      },
    );
  }

  @override
  Widget renderImage(
    BuildContext context,
    int index, [
    UserProfilePB? userProfile,
  ]) {
    final file = files[index];
    Widget fallback() => _MediaFileFallback(file: file, failed: true);
    if (file.uploadType == FileUploadTypePB.CloudFile && userProfile == null) {
      return fallback();
    }
    return AFImage(
      key: ValueKey(file.id),
      url: file.url,
      uploadType: file.uploadType,
      userProfile: userProfile,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => fallback(),
    );
  }
}

extension FileTypeDisplay on MediaFileTypePB {
  FlowySvgData get icon => switch (this) {
        MediaFileTypePB.Image => FlowySvgs.image_s,
        MediaFileTypePB.Link => FlowySvgs.ft_link_s,
        MediaFileTypePB.Document => FlowySvgs.icon_document_s,
        MediaFileTypePB.Archive => FlowySvgs.ft_archive_s,
        MediaFileTypePB.Video => FlowySvgs.ft_video_s,
        MediaFileTypePB.Audio => FlowySvgs.ft_audio_s,
        MediaFileTypePB.Text => FlowySvgs.ft_text_s,
        _ => FlowySvgs.icon_document_s,
      };

  Color get color => switch (this) {
        MediaFileTypePB.Image => const Color(0xFF5465A1),
        MediaFileTypePB.Link => const Color(0xFFEBE4FF),
        MediaFileTypePB.Audio => const Color(0xFFE4FFDE),
        MediaFileTypePB.Video => const Color(0xFFE0F8FF),
        MediaFileTypePB.Archive => const Color(0xFFFFE7EE),
        MediaFileTypePB.Text ||
        MediaFileTypePB.Document ||
        MediaFileTypePB.Other =>
          const Color(0xFFF5FFDC),
        _ => const Color(0xFF87B3A8),
      };
}
