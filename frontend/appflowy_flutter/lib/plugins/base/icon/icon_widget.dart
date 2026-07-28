import 'dart:async';

import 'package:appflowy/plugins/base/emoji/emoji_text.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:flutter/material.dart';

import '../../../generated/flowy_svgs.g.dart';

class IconWidget extends StatelessWidget {
  const IconWidget({super.key, required this.size, required this.iconsData});

  final IconsData iconsData;
  final double size;

  @override
  Widget build(BuildContext context) {
    // an icon may belong to a pack that has not been opened in the picker yet,
    // so load it on demand and repaint once it lands
    return ValueListenableBuilder<int>(
      valueListenable: iconPacksVersion,
      builder: (context, _, __) => _buildIcon(context),
    );
  }

  Widget _buildIcon(BuildContext context) {
    final pack = iconPackForGroup(iconsData.groupName);
    if (!isIconPackLoaded(pack)) {
      unawaited(loadIconPack(pack));
      return SizedBox.square(dimension: size);
    }

    final svgString = iconsData.svgString;
    if (svgString == null) {
      return EmojiText(
        emoji: '❓',
        fontSize: size,
        textAlign: TextAlign.center,
      );
    }

    if (pack.isColorful) {
      // a null blend mode keeps the artwork's own colors; tinting would
      // collapse every layer into one flat color
      return FlowySvg.string(
        svgString,
        size: Size.square(size),
        blendMode: null,
      );
    }

    final colorValue = int.tryParse(iconsData.color ?? '');
    final color = colorValue != null ? Color(colorValue) : null;
    return FlowySvg.string(
      svgString,
      size: Size.square(size),
      color: color,
    );
  }
}
