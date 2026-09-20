import 'dart:convert';

import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('legacy emoji and untagged strings keep their exact stored bytes', () {
    for (final value in ['📚', '👩🏽‍💻', '🇮🇳', '🌻', '{}', 'null', '{']) {
      final icon = EmojiIconData.fromStorageString(value);
      expect(icon.type, FlowyIconType.emoji);
      expect(icon.emoji, value);
      expect(icon.toStorageString(), value);
    }
  });

  test('typed icons round-trip without losing tint or custom path', () {
    for (final icon in [
      IconsData('appflowy_default_files', 'file', '4278255360')
          .toEmojiIconData(),
      IconsData('appflowy_vivid_essentials', 'rocket', null).toEmojiIconData(),
      EmojiIconData.custom(r'C:\owned icons\drawing #2.svg'),
      EmojiIconData.custom('https://example.invalid/icon.png?version=2#crop'),
    ]) {
      final restored = EmojiIconData.fromStorageString(icon.toStorageString());
      expect(restored.type, icon.type);
      expect(restored.emoji, icon.emoji);
      expect(restored.toStorageString(), icon.toStorageString());
    }
  });

  for (final payload in [
    {'appflowy_icon': 2, 'type': 'icon', 'value': '{}'},
    {'appflowy_icon': 1, 'type': 'unknown', 'value': 'value'},
    {'appflowy_icon': 1, 'type': 'custom', 'value': 23},
    {'appflowy_icon': 1, 'type': 'emoji', 'value': ''},
    {'appflowy_icon': 1, 'type': 'icon', 'value': '{'},
    {'appflowy_icon': 1, 'type': 'icon', 'value': '[]'},
    {'appflowy_icon': 1, 'type': 'icon', 'value': '{}'},
    {
      'appflowy_icon': 1,
      'type': 'icon',
      'value': jsonEncode({'groupName': '', 'iconName': 'book'}),
    },
    {
      'appflowy_icon': 1,
      'type': 'icon',
      'value': jsonEncode({'groupName': 'group', 'iconName': null}),
    },
    {
      'appflowy_icon': 1,
      'type': 'icon',
      'value': jsonEncode({
        'groupName': 'group',
        'iconName': 'book',
        'color': 42,
      }),
    },
  ]) {
    test('invalid tagged icon uses a fallback: ${jsonEncode(payload)}', () {
      expect(
        EmojiIconData.fromStorageString(jsonEncode(payload)).isEmpty,
        isTrue,
      );
    });
  }

  test('empty legacy values use the removable default fallback', () {
    expect(EmojiIconData.fromStorageString(null).isEmpty, isTrue);
    expect(EmojiIconData.fromStorageString('').isEmpty, isTrue);
    expect(EmojiIconData.none().toStorageString(), isEmpty);
  });
}
