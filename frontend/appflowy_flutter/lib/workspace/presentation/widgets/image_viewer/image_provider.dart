import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/shared/af_image.dart';
import 'package:appflowy_backend/protobuf/flowy-database2/file_entities.pbenum.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// Abstract class for providing images to the [InteractiveImageViewer].
///
abstract class AFImageProvider {
  const AFImageProvider({this.onDeleteImage});

  /// Provide this callback if you want it to be possible to
  /// delete the Image through the [InteractiveImageViewer].
  ///
  final Function(int index)? onDeleteImage;

  int get imageCount;
  int get initialIndex;

  ImageBlockData getImage(int index);

  /// Display/export metadata only; this never changes the stored image schema.
  /// Providers with an original filename can override the URL-derived default.
  String getImageName(int index) =>
      MediaActionSource.image(getImage(index)).name;

  Widget renderImage(
    BuildContext context,
    int index, [
    UserProfilePB? userProfile,
  ]);
}

class AFBlockImageProvider extends AFImageProvider {
  const AFBlockImageProvider({
    required this.images,
    this.initialIndex = 0,
    super.onDeleteImage,
  });

  final List<ImageBlockData> images;

  @override
  final int initialIndex;

  @override
  int get imageCount => images.length;

  @override
  ImageBlockData getImage(int index) => images[index];

  @override
  Widget renderImage(
    BuildContext context,
    int index, [
    UserProfilePB? userProfile,
  ]) {
    final image = getImage(index);
    final target = MediaActionSource.image(image, userProfile: userProfile);
    Widget unavailable() => Center(
          child: Semantics(
            image: true,
            label: LocaleKeys.document_imageBlock_error_invalidImage.tr(),
            child: Icon(
              Icons.broken_image_rounded,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        );

    if (target.requireAuthentication && target.httpHeaders.isEmpty) {
      return unavailable();
    }

    return AFImage(
      url: image.url,
      uploadType: switch (image.type) {
        CustomImageType.local => FileUploadTypePB.LocalFile,
        CustomImageType.internal => FileUploadTypePB.CloudFile,
        CustomImageType.external => FileUploadTypePB.NetworkFile,
      },
      userProfile: image.type == CustomImageType.internal ? userProfile : null,
      fit: BoxFit.contain,
      errorBuilder: (_, __, ___) => unavailable(),
    );
  }
}
