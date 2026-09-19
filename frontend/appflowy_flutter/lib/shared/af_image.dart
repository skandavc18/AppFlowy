import 'dart:io';

import 'package:flutter/material.dart';

import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';

class AFImage extends StatelessWidget {
  const AFImage({
    super.key,
    required this.url,
    required this.uploadType,
    this.height,
    this.width,
    this.fit = BoxFit.cover,
    this.userProfile,
    this.borderRadius,
    this.cacheWidth,
    this.cacheHeight,
    this.errorBuilder,
  })  : assert(cacheWidth == null || cacheWidth > 0),
        assert(cacheHeight == null || cacheHeight > 0),
        assert(
          uploadType != FileUploadTypePB.CloudFile || userProfile != null,
          'userProfile must be provided for accessing files from AF Cloud',
        );

  final String url;
  final FileUploadTypePB uploadType;
  final double? height;
  final double? width;
  final BoxFit fit;
  final UserProfilePB? userProfile;
  final BorderRadius? borderRadius;

  /// Optional decode dimensions in physical pixels, not layout dimensions.
  /// Leave one axis unset to retain the source aspect ratio when resizing.
  final int? cacheWidth;
  final int? cacheHeight;
  final ImageErrorWidgetBuilder? errorBuilder;

  Widget _error(BuildContext context, Object error, StackTrace? stackTrace) =>
      errorBuilder?.call(context, error, stackTrace) ?? const SizedBox.shrink();

  @override
  Widget build(BuildContext context) {
    if (uploadType == FileUploadTypePB.CloudFile && userProfile == null) {
      return const SizedBox.shrink();
    }

    Widget child;
    if (uploadType == FileUploadTypePB.NetworkFile) {
      child = Image.network(
        url,
        height: height,
        width: width,
        fit: fit,
        isAntiAlias: true,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: _error,
      );
    } else if (uploadType == FileUploadTypePB.LocalFile) {
      final File file;
      try {
        final uri = Uri.tryParse(url);
        // Do not URI-decode raw local paths: '#' and '%' may be literal names.
        file =
            uri != null && uri.isScheme('file') ? File.fromUri(uri) : File(url);
      } on Object catch (error, stackTrace) {
        return _error(context, error, stackTrace);
      }
      child = Image.file(
        file,
        height: height,
        width: width,
        fit: fit,
        isAntiAlias: true,
        cacheWidth: cacheWidth,
        cacheHeight: cacheHeight,
        errorBuilder: _error,
      );
    } else {
      child = FlowyNetworkImage(
        key: ValueKey(url),
        url: url,
        userProfilePB: userProfile,
        height: height,
        width: width,
        fit: fit,
        memCacheWidth: cacheWidth,
        memCacheHeight: cacheHeight,
        errorWidgetBuilder: (context, url, error) =>
            _error(context, error, null),
      );
    }

    if (borderRadius != null) {
      child = ClipRRect(
        borderRadius: borderRadius!,
        child: child,
      );
    }

    return child;
  }
}
