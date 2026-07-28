import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/common.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/image/image_editor/image_editor_source.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/media/media_actions.dart';
import 'package:appflowy/workspace/application/view/view_cover.dart';
import 'package:appflowy/workspace/presentation/widgets/dialogs.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:path/path.dart' as p;
import 'package:string_validator/string_validator.dart';

/// Where a cover picture's bytes live.
enum CoverImageStorage {
  /// A picture bundled with the app, read through [rootBundle].
  asset,

  /// A picture in AppFlowy's own local storage.
  local,

  /// A picture hosted on the workspace server or a third party host.
  remote,
}

/// A cover that has real picture bytes behind it, as opposed to a solid colour
/// or a gradient, which have nothing to save.
class DownloadableCoverImage {
  const DownloadableCoverImage._(this.storage, this.value);

  const DownloadableCoverImage.asset(String path)
      : this._(CoverImageStorage.asset, path);

  const DownloadableCoverImage.local(String path)
      : this._(CoverImageStorage.local, path);

  const DownloadableCoverImage.remote(String url)
      : this._(CoverImageStorage.remote, url);

  /// Picks [CoverImageStorage.remote] or [CoverImageStorage.local] from the
  /// shape of [value], the same way the cover renderers do.
  factory DownloadableCoverImage.resolve(String value) => isURL(value)
      ? DownloadableCoverImage.remote(value)
      : DownloadableCoverImage.local(value);

  /// The downloadable picture behind a page cover, or null when the cover is a
  /// colour, a gradient or absent.
  static DownloadableCoverImage? fromPageStyleCover(PageStyleCover? cover) {
    if (cover == null || cover.isNone || cover.value.isEmpty) {
      return null;
    }
    return switch (cover.type) {
      PageStyleCoverImageType.builtInImage => DownloadableCoverImage.asset(
          PageStyleCoverImageType.builtInImagePath(cover.value),
        ),
      PageStyleCoverImageType.localImage =>
        DownloadableCoverImage.local(cover.value),
      PageStyleCoverImageType.customImage ||
      PageStyleCoverImageType.unsplashImage =>
        DownloadableCoverImage.resolve(cover.value),
      PageStyleCoverImageType.none ||
      PageStyleCoverImageType.pureColor ||
      PageStyleCoverImageType.gradientColor =>
        null,
    };
  }

  final CoverImageStorage storage;
  final String value;

  Future<Uint8List> readBytes({UserProfilePB? userProfile}) async {
    switch (storage) {
      case CoverImageStorage.asset:
        final data = await rootBundle.load(value);
        return data.buffer.asUint8List(
          data.offsetInBytes,
          data.lengthInBytes,
        );
      case CoverImageStorage.local:
        return File(value).readAsBytes();
      case CoverImageStorage.remote:
        return ImageEditorSource(
          url: value,
          type: CustomImageType.internal,
          userProfile: userProfile,
        ).readBytes();
    }
  }

  /// The stored name, given an extension that matches the actual payload when
  /// the source carries none — workspace URLs are often extension-less.
  String fileNameFor(Uint8List bytes) {
    final name = p.basename(Uri.tryParse(value)?.path ?? value);
    if (name.isEmpty) {
      return 'appflowy-cover.${imageExtensionFor(sniffImageFormat(bytes))}';
    }
    if (p.extension(name).isNotEmpty) {
      return name;
    }
    return '$name.${imageExtensionFor(sniffImageFormat(bytes))}';
  }
}

/// Reads the cover's bytes and asks the user where to keep them.
///
/// Returns false when the save sheet was dismissed. Reports its own failure
/// toast, so callers only have to fire and forget.
Future<bool> downloadCoverImage(
  DownloadableCoverImage cover, {
  UserProfilePB? userProfile,
}) async {
  try {
    final bytes = await cover.readBytes(userProfile: userProfile);
    if (bytes.isEmpty) {
      throw const FileSystemException('The cover image is empty');
    }

    final saved = await saveMediaBytes(
      bytes: bytes,
      name: cover.fileNameFor(bytes),
    );
    if (saved) {
      showToastNotification(
        message: LocaleKeys.grid_media_downloadSuccess.tr(),
      );
    }
    return saved;
  } catch (e) {
    Log.error('Unable to download the cover image ${cover.value}', e);
    showToastNotification(
      message: LocaleKeys.document_plugins_image_imageDownloadFailed.tr(),
      type: ToastificationType.error,
    );
    return false;
  }
}
