import 'dart:io';

import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/cover_image_decode.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/shared/page_cover.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/material.dart';

class ViewCoverImage extends StatelessWidget {
  const ViewCoverImage({
    super.key,
    required this.cover,
    this.userProfile,
    BoxFit? fit,
    this.alignment,
    this.width,
    this.height,
    this.fallback,
  }) : _fit = fit;

  final PageStyleCover cover;
  final UserProfilePB? userProfile;
  final BoxFit? _fit;
  BoxFit get fit => _fit ?? BoxFit.cover;
  final Alignment? alignment;
  final double? width;
  final double? height;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final fallback =
        this.fallback ?? _CoverFallback(width: width, height: height);
    final presentation = PageCoverPresentation.maybeOf(context);
    final fit = _fit ?? presentation?.appearance.boxFit ?? BoxFit.cover;
    final alignment =
        this.alignment ?? presentation?.alignment ?? Alignment.center;

    if (cover.type == PageStyleCoverImageType.builtInImage ||
        cover.type == PageStyleCoverImageType.localImage ||
        cover.type == PageStyleCoverImageType.customImage ||
        cover.type == PageStyleCoverImageType.unsplashImage) {
      return LayoutBuilder(
        builder: (context, constraints) {
          final decode = CoverImageDecodeSize.fromConstraints(
            constraints,
            MediaQuery.devicePixelRatioOf(context),
            width: width,
            height: height,
          );
          if (cover.type == PageStyleCoverImageType.builtInImage) {
            return _buildImage(
              AssetImage(PageStyleCoverImageType.builtInImagePath(cover.value)),
              fallback,
              fit,
              alignment,
              decode,
            );
          }
          if (cover.type == PageStyleCoverImageType.localImage) {
            return _buildLocalImage(fallback, fit, alignment, decode);
          }
          return _buildNetworkImage(fallback, fit, alignment, decode);
        },
      );
    }
    return switch (cover.type) {
      PageStyleCoverImageType.none => fallback,
      PageStyleCoverImageType.pureColor => _buildColor(context, fallback),
      PageStyleCoverImageType.gradientColor => _buildGradient(),
      _ => fallback,
    };
  }

  Widget _buildColor(BuildContext context, Widget fallback) {
    final color = cover.value.coverColor(context);
    return color == null
        ? fallback
        : SizedBox(
            width: width,
            height: height,
            child: ColoredBox(color: color),
          );
  }

  Widget _buildGradient() {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        gradient: FlowyGradientColor.fromId(cover.value).linear,
      ),
    );
  }

  Widget _buildImage(
    ImageProvider provider,
    Widget fallback,
    BoxFit fit,
    Alignment alignment,
    CoverImageDecodeSize? decode,
  ) {
    return Image(
      image:
          decode == null ? provider : CoverImageProvider(provider, decode, fit),
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      frameBuilder: (_, child, frame, synchronous) =>
          frame != null || synchronous ? child : fallback,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  Widget _buildLocalImage(
    Widget fallback,
    BoxFit fit,
    Alignment alignment,
    CoverImageDecodeSize? decode,
  ) {
    if (cover.value.isEmpty) return fallback;
    final uri = Uri.tryParse(cover.value);
    final file = uri?.scheme == 'file' ? File.fromUri(uri!) : File(cover.value);
    // FileImage handles missing files asynchronously; do not stat every cover
    // synchronously during layout/resize.
    return _buildImage(FileImage(file), fallback, fit, alignment, decode);
  }

  Widget _buildNetworkImage(
    Widget fallback,
    BoxFit fit,
    Alignment alignment,
    CoverImageDecodeSize? decode,
  ) {
    final uri = Uri.tryParse(cover.value);
    if (uri == null ||
        (uri.scheme != 'http' && uri.scheme != 'https') ||
        (cover.value.isAppFlowyCloudUrl &&
            (userProfile == null || userProfile!.token.isEmpty))) {
      return fallback;
    }
    return FlowyNetworkImage(
      url: cover.value,
      userProfilePB: userProfile,
      width: width,
      height: height,
      fit: fit,
      alignment: alignment,
      coverDecodeSize: decode,
      placeholderBuilder: (_, __) => fallback,
      fadeInDuration: Duration.zero,
      fadeOutDuration: Duration.zero,
      // A selected cover is not an AI image still being generated. Keep the
      // shared default {404} for its existing consumers, but don't repeatedly
      // download a permanently missing cover or retry unauthorized requests.
      retryErrorCodes: const {408, 429, 500, 502, 503, 504},
      errorWidgetBuilder: (_, __, ___) => fallback,
    );
  }
}

class ViewCoverThumbnail extends StatelessWidget {
  const ViewCoverThumbnail({
    super.key,
    required this.cover,
    this.userProfile,
    this.width = 44,
    this.height = 32,
    this.borderRadius = 8,
    this.fallback,
  });

  final PageStyleCover? cover;
  final UserProfilePB? userProfile;
  final double width;
  final double height;
  final double borderRadius;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final fallback = this.fallback ?? const SizedBox.shrink();
    final cover = this.cover;
    if (cover == null || cover.isNone) {
      return fallback;
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: SizedBox(
        width: width,
        height: height,
        child: ViewCoverImage(
          cover: cover,
          userProfile: userProfile,
          // A thumbnail may live in a page-cover overlay. It is not the hero
          // and must not inherit that page's fit/position presentation scope.
          fit: BoxFit.cover,
          alignment: Alignment.center,
          width: width,
          height: height,
          fallback: fallback,
        ),
      ),
    );
  }
}

class _CoverFallback extends StatelessWidget {
  const _CoverFallback({this.width, this.height});

  final double? width;
  final double? height;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: width,
      height: height,
      child: ColoredBox(
        color: EditorSurfaceStyle.previewBackgroundFor(
          theme.brightness,
          theme.colorScheme.surfaceContainer,
          isPaper: PaperTheme.isEnabled(context),
        ),
      ),
    );
  }
}
