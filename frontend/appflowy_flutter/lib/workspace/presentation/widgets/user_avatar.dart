import 'package:appflowy/env/cloud_env.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:string_validator/string_validator.dart';

/// Interprets the plain string a user icon is stored as.
///
/// It can be an emoji, a serialized built-in icon, the URL of an uploaded
/// profile picture or the path of an image on this device.
EmojiIconData userIconData(String iconUrl) {
  final icon = iconUrl.trim();

  if (icon.isEmpty) {
    return EmojiIconData.none();
  }

  if (icon.startsWith('{')) {
    return EmojiIconData(FlowyIconType.icon, icon);
  }

  if (isURL(icon) || icon.contains(RegExp(r'[\\/]'))) {
    return EmojiIconData.custom(icon);
  }

  return EmojiIconData.emoji(icon);
}

class UserAvatar extends StatelessWidget {
  const UserAvatar({
    super.key,
    required this.iconUrl,
    required this.name,
    required this.size,
    this.isHovering = false,
    this.decoration,
  });

  final String iconUrl;
  final String name;

  final AFAvatarSize size;
  final Decoration? decoration;

  // If true, a border will be applied on top of the avatar
  final bool isHovering;

  @override
  Widget build(BuildContext context) {
    final theme = AppFlowyTheme.of(context);
    return SizedBox.square(
      dimension: size.size,
      child: DecoratedBox(
        decoration: decoration ??
            BoxDecoration(
              shape: BoxShape.circle,
              border: isHovering
                  ? Border.all(
                      color: theme.iconColorScheme.primary,
                      width: 4,
                    )
                  : null,
            ),
        child: AFAvatar(
          url: iconUrl,
          name: name,
          size: size,
          child: _buildIcon(),
        ),
      ),
    );
  }

  /// Emojis, built-in icons, images stored on this device and pictures uploaded
  /// to the workspace are rendered by [RawEmojiIconWidget], which knows how to
  /// authenticate against the cloud.
  ///
  /// Avatars hosted somewhere else, such as the ones the server returns for
  /// workspace members, are left to [AFAvatar]. Their request must not carry
  /// the access token of the current user.
  Widget? _buildIcon() {
    final icon = iconUrl.trim();
    if (icon.isEmpty) {
      return null;
    }

    if (isURL(icon) && !_isSelfHostedAsset(icon)) {
      return null;
    }

    final data = userIconData(icon);
    if (data.isEmpty) {
      return null;
    }

    final dimension = size.size;
    if (data.type == FlowyIconType.custom) {
      return SizedBox.square(
        dimension: dimension,
        child: RawEmojiIconWidget(emoji: data, emojiSize: dimension),
      );
    }

    return Center(
      child: RawEmojiIconWidget(
        emoji: data,
        emojiSize: dimension * 0.62,
        lineHeight: 1.0,
      ),
    );
  }

  bool _isSelfHostedAsset(String url) {
    if (!getIt.isRegistered<AppFlowyCloudSharedEnv>()) {
      return false;
    }

    final baseUrl = getIt<AppFlowyCloudSharedEnv>().appflowyCloudConfig.base_url;
    return baseUrl.isNotEmpty && url.startsWith(baseUrl);
  }
}

