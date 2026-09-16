import 'dart:convert';

import 'package:appflowy/plugins/base/emoji/emoji_picker_screen.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon.dart' as icons;
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_icon_artwork.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetIconPacksForTesting);

  test('the selectable defaults include every sidebar symbol exactly once', () {
    final defaults =
        appFlowyDefaultIconGroups.expand((group) => group.icons).toList();
    expect(defaults.length, SidebarIcon.values.length);
    expect(
      defaults.map((icon) => icon.iconPath).toSet().length,
      defaults.length,
    );
    for (final symbol in SidebarIcon.values) {
      expect(
        defaults.map((icon) => icon.content),
        contains(roundedSidebarIconSvg(symbol.name)),
        reason: symbol.name,
      );
    }
    for (final group in appFlowyDefaultIconGroups) {
      expect(iconPackForGroup(group.name), kAppFlowyDefaultIconPack);
      expect(
        group.displayName,
        isNot(contains(appFlowyDefaultIconGroupPrefix)),
      );
      expect(group.isColorful, isFalse);
    }
  });

  test('book has a closed spine and repository has a code folder', () {
    final book = findLoadedIcon('appflowy_default_collections', 'book')!;
    final repository = findLoadedIcon(
      'appflowy_default_collections',
      'repository',
    )!;
    expect(book.content, contains('M9 3v13'));
    expect(book.content, isNot(contains('M12 6.5')));
    expect(repository.content, contains('L12.8 7H19'));
    expect(repository.content, contains('m9.5 11.5-2.5 2.5 2.5 2.5'));
  });

  test('default selections round trip through existing protobuf and JSON', () {
    for (final group in appFlowyDefaultIconGroups) {
      for (final icon in group.icons) {
        for (final color in [null, '4283665274']) {
          final chosen = EmojiIconData.icon(
            IconsData(group.name, icon.name, color),
          );
          final stored = ViewIconPB.fromBuffer(
            chosen.toViewIcon().writeToBuffer(),
          );
          final restored = stored.toEmojiIconData();
          final data = IconsData.fromJson(jsonDecode(restored.emoji));
          expect(stored.ty, ViewIconTypePB.Icon);
          expect(data.groupName, group.name);
          expect(data.iconName, icon.name);
          expect(data.color, color);
          expect(data.svgString, icon.content);
          expect(restored.toPickerTabType(), PickerTabType.defaultIcons);
        }
      }
    }
  });

  test('defaults survive a cold cache without loading an asset pack', () async {
    expect(isIconPackLoaded(kDefaultIconPack), isFalse);
    expect(isIconPackLoaded(sidebarIconPack), isFalse);
    expect(isIconPackLoaded(kAppFlowyDefaultIconPack), isTrue);
    final version = iconPacksVersion.value;
    final groups = await loadIconPack(kAppFlowyDefaultIconPack);
    expect(groups, same(appFlowyDefaultIconGroups));
    await ensureIconPackLoadedForGroup(groups.first.name);
    expect(iconPacksVersion.value, version);
    expect(isIconPackLoaded(kDefaultIconPack), isFalse);
    resetIconPacksForTesting();
    expect(
      IconsData(groups.first.name, 'book', null).svgString,
      roundedSidebarIconSvg(SidebarIcon.book.name),
    );
  });

  test('old icon kinds keep their own tabs and reset opens defaults', () {
    expect(EmojiIconData.emoji('📚').toPickerTabType(), PickerTabType.emoji);
    expect(
      EmojiIconData.custom('photo.png').toPickerTabType(),
      PickerTabType.custom,
    );
    expect(
      EmojiIconData.icon(IconsData('phosphor_bold_office', 'book-open', null))
          .toPickerTabType(),
      PickerTabType.icon,
    );
    expect(EmojiIconData.none().toPickerTabType(), PickerTabType.defaultIcons);
    for (final invalid in ['not json', '[]', '{}', 'null']) {
      expect(
        EmojiIconData(FlowyIconType.icon, invalid).toPickerTabType(),
        PickerTabType.icon,
      );
    }
  });

  test('legacy tab lists gain defaults only when icons are allowed', () {
    const original = [
      PickerTabType.emoji,
      PickerTabType.icon,
      PickerTabType.custom,
    ];
    expect(pickerTabsWithDefaults(original), [
      PickerTabType.emoji,
      PickerTabType.defaultIcons,
      PickerTabType.icon,
      PickerTabType.custom,
    ]);
    expect(original.length, 3);
    expect(pickerTabsWithDefaults([PickerTabType.icon]), [
      PickerTabType.defaultIcons,
      PickerTabType.icon,
    ]);
    expect(
      pickerTabsWithDefaults([PickerTabType.emoji]),
      [PickerTabType.emoji],
    );
    expect(
      pickerTabsWithDefaults([PickerTabType.custom]),
      [PickerTabType.custom],
    );
    const explicit = [PickerTabType.defaultIcons, PickerTabType.icon];
    expect(pickerTabsWithDefaults(explicit), same(explicit));
  });

  test('existing tab names and ordinals are unchanged', () {
    expect(PickerTabType.emoji.index, 0);
    expect(PickerTabType.icon.index, 1);
    expect(PickerTabType.custom.index, 2);
    for (final tab in PickerTabType.values) {
      expect(tab.name.toPickerTabType(), tab);
    }
    expect('unknown'.toPickerTabType(), isNull);
  });

  test('mobile URI tab names round trip without widening emoji-only pickers',
      () {
    for (final tab in PickerTabType.values) {
      final uri = Uri(
        path: MobileEmojiPickerScreen.routeName,
        queryParameters: {
          MobileEmojiPickerScreen.iconSelectedType: tab.name,
          // Uri accepts iterable values as well as strings. Keep existing
          // emoji-only callers compatible instead of rewriting their routes.
          MobileEmojiPickerScreen.selectTabs: [PickerTabType.emoji.name],
        },
      );
      final query = Uri.parse(uri.toString()).queryParameters;
      expect(
        query[MobileEmojiPickerScreen.iconSelectedType]!.toPickerTabType(),
        tab,
      );
      final tabs = query[MobileEmojiPickerScreen.selectTabs]!
          .split('-')
          .map((name) => name.toPickerTabType()!)
          .toList();
      expect(pickerTabsWithDefaults(tabs), [PickerTabType.emoji]);
    }
  });

  test('default icons can be searched using familiar collection names', () {
    List<String> search(String keyword) => appFlowyDefaultIconGroups
        .map((group) => group.filter(keyword))
        .expand((group) => group.icons.map((icon) => icon.name))
        .toList();
    expect(search('CLOSED'), contains('book'));
    expect(search('git'), contains('repository'));
    expect(search('photos'), contains('album'));
    expect(search('inbox'), contains('mail'));
  });

  test('recents retain namespaced default identities without parent cycles',
      () {
    final group = appFlowyDefaultIconGroups.first;
    final recent = icons.RecentIcon(group.icons.first, group.name);
    final restored = icons.RecentIcon.fromJson(
      jsonDecode(jsonEncode(recent)) as Map<String, dynamic>,
    );
    expect(restored.groupName, group.name);
    expect(restored.name, 'book');
    expect(
      IconsData(restored.groupName, restored.name, null).svgString,
      recent.content,
    );
  });
}
