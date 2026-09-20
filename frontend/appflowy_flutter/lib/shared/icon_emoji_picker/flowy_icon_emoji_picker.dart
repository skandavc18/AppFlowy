import 'dart:convert';
import 'dart:math';

import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/base/emoji/emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart';
import 'package:flutter/material.dart' hide Icon;
import 'package:flutter/services.dart';
import 'package:universal_platform/universal_platform.dart';

import 'icon_uploader.dart';

extension ToProto on FlowyIconType {
  ViewIconTypePB toProto() {
    switch (this) {
      case FlowyIconType.emoji:
        return ViewIconTypePB.Emoji;
      case FlowyIconType.icon:
        return ViewIconTypePB.Icon;
      case FlowyIconType.custom:
        return ViewIconTypePB.Url;
    }
  }
}

extension FromProto on ViewIconTypePB {
  FlowyIconType fromProto() {
    switch (this) {
      case ViewIconTypePB.Emoji:
        return FlowyIconType.emoji;
      case ViewIconTypePB.Icon:
        return FlowyIconType.icon;
      case ViewIconTypePB.Url:
        return FlowyIconType.custom;
      default:
        return FlowyIconType.custom;
    }
  }
}

extension ToEmojiIconData on ViewIconPB {
  EmojiIconData toEmojiIconData() => EmojiIconData(ty.fromProto(), value);
}

enum FlowyIconType {
  emoji,
  icon,
  custom;
}

extension FlowyIconTypeToPickerTabType on FlowyIconType {
  PickerTabType? toPickerTabType() => name.toPickerTabType();
}

class EmojiIconData {
  factory EmojiIconData.none() => const EmojiIconData(FlowyIconType.icon, '');

  factory EmojiIconData.emoji(String emoji) =>
      EmojiIconData(FlowyIconType.emoji, emoji);

  factory EmojiIconData.icon(IconsData icon) =>
      EmojiIconData(FlowyIconType.icon, icon.iconString);

  factory EmojiIconData.custom(String url) =>
      EmojiIconData(FlowyIconType.custom, url);

  const EmojiIconData(
    this.type,
    this.emoji,
  );

  /// String-only metadata historically held an emoji. Keep those values
  /// unchanged while explicitly tagging other icon kinds, rather than later
  /// trying to paint an icon's JSON or an image path as emoji text.
  factory EmojiIconData.fromStorageString(String? value) {
    if (value == null || value.isEmpty) {
      return EmojiIconData.none();
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(value);
    } on FormatException {
      // Ordinary legacy emoji strings are not JSON.
      return EmojiIconData.emoji(value);
    }
    if (decoded is Map && decoded.containsKey('appflowy_icon')) {
      final storedType = decoded['type'];
      final type = FlowyIconType.values
          .where((type) => type.name == storedType)
          .firstOrNull;
      final icon = decoded['value'];
      if (decoded['appflowy_icon'] != 1 ||
          type == null ||
          icon is! String ||
          icon.isEmpty) {
        return EmojiIconData.none();
      }
      if (type == FlowyIconType.icon) {
        try {
          final data = jsonDecode(icon);
          if (data is! Map ||
              data['groupName'] is! String ||
              data['iconName'] is! String ||
              (data['groupName'] as String).isEmpty ||
              (data['iconName'] as String).isEmpty ||
              (data['color'] != null && data['color'] is! String)) {
            return EmojiIconData.none();
          }
        } on FormatException {
          // A damaged tagged icon is not legacy emoji. Show the fallback,
          // never its serialized envelope as text in a sidebar or row title.
          return EmojiIconData.none();
        }
      }
      return EmojiIconData(type, icon);
    }
    return EmojiIconData.emoji(value);
  }

  final FlowyIconType type;
  final String emoji;

  static EmojiIconData fromViewIconPB(ViewIconPB v) {
    return EmojiIconData(v.ty.fromProto(), v.value);
  }

  String toStorageString() {
    if (isEmpty) return '';
    if (type == FlowyIconType.emoji) return emoji;
    return jsonEncode({
      'appflowy_icon': 1,
      'type': type.name,
      'value': emoji,
    });
  }

  ViewIconPB toViewIcon() {
    return ViewIconPB()
      ..ty = type.toProto()
      ..value = emoji;
  }

  bool get isEmpty => emoji.isEmpty;

  bool get isNotEmpty => emoji.isNotEmpty;

  /// A saved default should reopen its own tab, not the unrelated library
  /// styles. Keep the protobuf type and group/name JSON format unchanged.
  PickerTabType? toPickerTabType() {
    if (type == FlowyIconType.icon) {
      if (isEmpty) {
        return PickerTabType.defaultIcons;
      }
      try {
        final data = jsonDecode(emoji);
        if (data is Map &&
            data['groupName'] is String &&
            isAppFlowyDefaultIconGroup(data['groupName'] as String)) {
          return PickerTabType.defaultIcons;
        }
      } on FormatException {
        // A malformed stored icon still opens the library tab for replacement.
      }
    }
    return type.toPickerTabType();
  }
}

class SelectedEmojiIconResult {
  SelectedEmojiIconResult(this.data, this.keepOpen);

  final EmojiIconData data;
  final bool keepOpen;

  FlowyIconType get type => data.type;

  String get emoji => data.emoji;
}

extension EmojiIconDataToSelectedResultExtension on EmojiIconData {
  SelectedEmojiIconResult toSelectedResult({bool keepOpen = false}) =>
      SelectedEmojiIconResult(this, keepOpen);
}

class FlowyIconEmojiPicker extends StatefulWidget {
  const FlowyIconEmojiPicker({
    super.key,
    this.onSelectedEmoji,
    this.initialType,
    this.documentId,
    this.enableBackgroundColorSelection = true,
    this.tabs = const [
      PickerTabType.emoji,
      PickerTabType.icon,
    ],
  });

  final ValueChanged<SelectedEmojiIconResult>? onSelectedEmoji;
  final bool enableBackgroundColorSelection;
  final List<PickerTabType> tabs;
  final PickerTabType? initialType;
  final String? documentId;

  /// Also expose defaults for legacy callers that already allow library icons.
  List<PickerTabType> get effectiveTabs => pickerTabsWithDefaults(tabs);

  @override
  State<FlowyIconEmojiPicker> createState() => _FlowyIconEmojiPickerState();
}

class _FlowyIconEmojiPickerState extends State<FlowyIconEmojiPicker>
    with SingleTickerProviderStateMixin {
  late TabController controller;
  int currentIndex = 0;

  List<PickerTabType> get tabs => widget.effectiveTabs;

  @override
  void initState() {
    super.initState();
    final initialType = widget.initialType;
    if (initialType != null) {
      currentIndex = max(tabs.indexOf(initialType), 0);
    }
    controller = TabController(
      initialIndex: currentIndex,
      length: tabs.length,
      vsync: this,
    );
    controller.addListener(() {
      currentIndex = controller.index;
      final currentType = tabs[currentIndex];
      if (currentType == PickerTabType.custom) {
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      }
    });
  }

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          height: 46,
          padding: const EdgeInsets.only(left: 4.0, right: 12.0),
          child: Row(
            children: [
              Expanded(
                child: PickerTab(
                  controller: controller,
                  tabs: tabs,
                  onTap: (index) => currentIndex = index,
                ),
              ),
              _RemoveIconButton(
                onTap: () {
                  widget.onSelectedEmoji
                      ?.call(EmojiIconData.none().toSelectedResult());
                },
              ),
            ],
          ),
        ),
        const FlowyDivider(),
        Expanded(
          child: TabBarView(
            controller: controller,
            children: tabs.map((tab) {
              switch (tab) {
                case PickerTabType.emoji:
                  return _buildEmojiPicker();
                case PickerTabType.defaultIcons:
                  return _buildIconPicker(fixedPack: kAppFlowyDefaultIconPack);
                case PickerTabType.icon:
                  return _buildIconPicker();
                case PickerTabType.custom:
                  return _buildIconUploader();
              }
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _buildEmojiPicker() {
    return FlowyEmojiPicker(
      ensureFocus: true,
      emojiPerLine: _getEmojiPerLine(context),
      onEmojiSelected: (r) {
        widget.onSelectedEmoji?.call(
          EmojiIconData.emoji(r.emoji).toSelectedResult(keepOpen: r.isRandom),
        );
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      },
    );
  }

  int _getEmojiPerLine(BuildContext context) {
    if (UniversalPlatform.isDesktopOrWeb) {
      return 9;
    }
    final width = MediaQuery.of(context).size.width;
    return width ~/ 40.0; // the size of the emoji
  }

  Widget _buildIconPicker({IconPack? fixedPack}) {
    return FlowyIconPicker(
      fixedPack: fixedPack,
      ensureFocus: true,
      enableBackgroundColorSelection: widget.enableBackgroundColorSelection,
      onSelectedIcon: (r) {
        widget.onSelectedEmoji?.call(
          r.data.toEmojiIconData().toSelectedResult(keepOpen: r.isRandom),
        );
        SystemChannels.textInput.invokeMethod('TextInput.hide');
      },
    );
  }

  Widget _buildIconUploader() {
    return IconUploader(
      documentId: widget.documentId ?? '',
      ensureFocus: true,
      onUrl: (url) {
        widget.onSelectedEmoji
            ?.call(SelectedEmojiIconResult(EmojiIconData.custom(url), false));
      },
    );
  }
}

class _RemoveIconButton extends StatelessWidget {
  const _RemoveIconButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 32,
      child: FlowyButton(
        onTap: onTap,
        useIntrinsicWidth: true,
        text: FlowyText(
          fontSize: 14.0,
          figmaLineHeight: 16.0,
          fontWeight: FontWeight.w500,
          LocaleKeys.button_remove.tr(),
          color: Theme.of(context).hintColor,
        ),
      ),
    );
  }
}
