import 'dart:convert';
import 'dart:io';

import 'package:appflowy/plugins/base/emoji/emoji_text.dart';
import 'package:appflowy/shared/appflowy_network_image.dart';
import 'package:appflowy/shared/appflowy_network_svg.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_optical_size.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/user/application/user_service.dart';
import 'package:appflowy_backend/log.dart';
import 'package:appflowy_backend/protobuf/flowy-user/user_profile.pb.dart';
import 'package:flowy_infra_ui/style_widget/text.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:string_validator/string_validator.dart';

import '../../../../../shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import '../../../../base/icon/icon_widget.dart';

export 'package:appflowy/shared/icon_emoji_picker/icon_optical_size.dart';

class EmojiIconWidget extends StatefulWidget {
  const EmojiIconWidget({
    super.key,
    required this.emoji,
    this.emojiSize = 60,
  });

  final EmojiIconData emoji;
  final double emojiSize;

  @override
  State<EmojiIconWidget> createState() => _EmojiIconWidgetState();
}

class _EmojiIconWidgetState extends State<EmojiIconWidget> {
  bool hover = true;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setHidden(false),
      onExit: (_) => setHidden(true),
      cursor: SystemMouseCursors.click,
      child: Container(
        decoration: BoxDecoration(
          color: !hover
              ? Theme.of(context)
                  .colorScheme
                  .inverseSurface
                  .withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
        ),
        alignment: Alignment.center,
        child: RawEmojiIconWidget(
          emoji: widget.emoji,
          emojiSize: widget.emojiSize,
        ),
      ),
    );
  }

  void setHidden(bool value) {
    if (hover == value) return;
    setState(() {
      hover = value;
    });
  }
}

class RawEmojiIconWidget extends StatefulWidget {
  const RawEmojiIconWidget({
    super.key,
    required this.emoji,
    required this.emojiSize,
    this.enableColor = true,
    this.lineHeight,
    this.opticalRole,
  });

  final EmojiIconData emoji;
  final double emojiSize;
  final bool enableColor;
  final double? lineHeight;

  /// Opt-in for identity surfaces only. Null keeps existing picker/inline
  /// geometry. Header hosts reserve 66px and pass emojiSize: 56; sidebar hosts
  /// reserve 24px and pass emojiSize: 18. The stored icon is never rewritten.
  final IconOpticalRole? opticalRole;

  @override
  State<RawEmojiIconWidget> createState() => _RawEmojiIconWidgetState();
}

class _RawEmojiIconWidgetState extends State<RawEmojiIconWidget> {
  UserProfilePB? userProfile;

  EmojiIconData get emoji => widget.emoji;

  @override
  void initState() {
    super.initState();
    loadUserProfile();
  }

  @override
  void didUpdateWidget(RawEmojiIconWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    loadUserProfile();
  }

  @override
  Widget build(BuildContext context) {
    final role = widget.opticalRole;
    if (role == null) return _buildArtwork(widget.emojiSize);
    var colorful = widget.emoji.type != FlowyIconType.icon;
    if (!colorful) {
      try {
        final data = IconsData.fromJson(jsonDecode(widget.emoji.emoji));
        colorful = iconPackForGroup(data.groupName).isColorful;
      } catch (_) {
        // The existing renderer owns malformed-data recovery below.
      }
    }
    return OpticalIconFrame(
      role: role,
      baseSize: widget.emojiSize,
      colorful: colorful,
      builder: _buildArtwork,
    );
  }

  Widget _buildArtwork(double size) {
    final defaultEmoji = SizedBox(
      width: size,
      child: EmojiText(
        emoji: '❓',
        fontSize: size,
        textAlign: TextAlign.center,
      ),
    );
    try {
      switch (widget.emoji.type) {
        case FlowyIconType.emoji:
          // `lineHeight: 1` + `optimizeEmojiAlign` make the glyph box exactly
          // `emojiSize` tall with the leading split evenly, so an emoji fills
          // and centers in the box it was asked for instead of sitting on the
          // baseline of a taller line.
          return FlowyText.emoji(
            widget.emoji.emoji,
            fontSize: size,
            lineHeight:
                widget.opticalRole == null ? widget.lineHeight ?? 1.0 : 1.0,
            optimizeEmojiAlign: true,
          );
        case FlowyIconType.icon:
          IconsData iconData = IconsData.fromJson(
            jsonDecode(widget.emoji.emoji),
          );
          if (!widget.enableColor) {
            iconData = iconData.noColor();
          }

          return IconWidget(
            iconsData: iconData,
            size: size,
          );
        case FlowyIconType.custom:
          final url = widget.emoji.emoji;
          final isSvg = url.endsWith('.svg');
          final hasUserProfile = userProfile != null;
          if (isURL(url)) {
            Widget child = const SizedBox.shrink();
            if (isSvg) {
              child = FlowyNetworkSvg(
                url,
                headers:
                    hasUserProfile ? _buildRequestHeader(userProfile!) : {},
                width: size,
                height: size,
              );
            } else if (hasUserProfile) {
              child = FlowyNetworkImage(
                url: url,
                width: size,
                height: size,
                fit: widget.opticalRole == null ? BoxFit.cover : BoxFit.contain,
                userProfilePB: userProfile,
                errorWidgetBuilder: (context, url, error) {
                  return const SizedBox.shrink();
                },
              );
            }
            return SizedBox.square(
              dimension: size,
              child: child,
            );
          }
          final imageFile = File(url);
          if (!imageFile.existsSync()) {
            throw PathNotFoundException(url, const OSError());
          }
          return SizedBox.square(
            dimension: size,
            child: isSvg
                ? SvgPicture.file(
                    File(url),
                    width: size,
                    height: size,
                  )
                : Image.file(
                    imageFile,
                    fit: widget.opticalRole == null
                        ? BoxFit.cover
                        : BoxFit.contain,
                    width: size,
                    height: size,
                  ),
          );
      }
    } catch (e) {
      Log.error("Display widget error: $e");
      return defaultEmoji;
    }
  }

  Map<String, String> _buildRequestHeader(UserProfilePB userProfilePB) {
    final header = <String, String>{};
    final token = userProfilePB.token;
    try {
      final decodedToken = jsonDecode(token);
      header['Authorization'] = 'Bearer ${decodedToken['access_token']}';
    } catch (e) {
      Log.error('Unable to decode token: $e');
    }
    return header;
  }

  Future<void> loadUserProfile() async {
    if (userProfile != null) return;
    if (emoji.type == FlowyIconType.custom) {
      final userProfile =
          (await UserBackendService.getCurrentUserProfile()).fold(
        (userProfile) => userProfile,
        (l) => null,
      );
      if (mounted) {
        setState(() {
          this.userProfile = userProfile;
        });
      }
    }
  }
}
