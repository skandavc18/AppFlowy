import 'dart:io';

import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/editor_surface_style.dart';
import 'package:appflowy/shared/flowy_gradient_colors.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/util/string_extension.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flutter/material.dart';

class ViewCoverImage extends StatelessWidget {
  const ViewCoverImage({
    super.key,
    required this.cover,
    this.userProfile,
    this.fit = BoxFit.cover,
    this.width,
    this.height,
    this.fallback,
  });

  final PageStyleCover cover;
  final UserProfilePB? userProfile;
  final BoxFit fit;
  final double? width;
  final double? height;
  final Widget? fallback;

  @override
  Widget build(BuildContext context) {
    final fallback =
        this.fallback ?? _CoverFallback(width: width, height: height);

    return switch (cover.type) {
      PageStyleCoverImageType.none => fallback,
      PageStyleCoverImageType.pureColor => _buildColor(context, fallback),
      PageStyleCoverImageType.gradientColor => _buildGradient(),
      PageStyleCoverImageType.builtInImage => Image.asset(
          PageStyleCoverImageType.builtInImagePath(cover.value),
          width: width,
          height: height,
          fit: fit,
          errorBuilder: (_, __, ___) => fallback,
        ),
      PageStyleCoverImageType.localImage => _buildLocalImage(fallback),
      PageStyleCoverImageType.customImage ||
      PageStyleCoverImageType.unsplashImage =>
        _buildNetworkImage(fallback),
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

  Widget _buildLocalImage(Widget fallback) {
    final file = File(cover.value);
    if (cover.value.isEmpty || !file.existsSync()) {
      return fallback;
    }
    return Image.file(
      file,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, __, ___) => fallback,
    );
  }

  Widget _buildNetworkImage(Widget fallback) {
    final uri = Uri.tryParse(cover.value);
    if (uri == null || !uri.hasScheme) {
      return fallback;
    }
    return FlowyNetworkImage(
      url: cover.value,
      userProfilePB: userProfile,
      width: width,
      height: height,
      fit: fit,
      progressIndicatorBuilder: (_, __, ___) => fallback,
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
