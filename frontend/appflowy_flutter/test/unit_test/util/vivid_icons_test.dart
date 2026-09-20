import 'dart:convert';

import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon.dart' as icons;
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icons.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:xml/xml.dart';

const _names = [
  'home',
  'book',
  'bolt',
  'coffee',
  'target',
  'rocket',
  'seedling',
  'bulb',
  'sparkles',
  'planet',
  'books',
  'camera',
  'music',
  'calendar',
  'folder',
  'chart',
  'globe',
  'palette',
  'gem',
  'trophy',
  'heart',
  'cloud',
  'mountain',
  'compass',
];

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetIconPacksForTesting();
    kIconGroups = null;
  });

  test('Vivid adds 24 stable original choices beside the existing styles', () {
    expect(kIconPacks.take(3).map((pack) => pack.id), [
      'default',
      appFlowyVividIconPackId,
      'color',
    ]);
    expect(kIconPacks.map((pack) => pack.id).toSet().length, kIconPacks.length);
    expect(kVividIconPack.asset, isEmpty);
    expect(kVividIconPack.attribution, 'AppFlowy (original artwork)');
    expect(kVividIconPack.isColorful, isTrue);
    expect(kDefaultIconPack.isColorful, isFalse);
    expect(kAppFlowyDefaultIconPack.isColorful, isFalse);

    final group = appFlowyVividIconGroups.single;
    expect(group.name, 'appflowy_vivid_essentials');
    expect(group.displayName, 'essentials');
    expect(group.packId, appFlowyVividIconPackId);
    expect(group.isColorful, isTrue);
    expect(group.icons.map((icon) => icon.name), _names);
    expect(group.icons.map((icon) => icon.content).toSet(), hasLength(24));
    for (final icon in group.icons) {
      expect(icon.isColorful, isTrue);
      expect(icon.iconPath, '${group.name}/${icon.name}');
      expect(icon.content, vividIconSvg(icon.name));
      expect(iconPackForGroup(group.name), same(kVividIconPack));
      expect(icon.keywords, isNotEmpty);
    }
    expect(
      group.icons.fold<int>(
          0, (size, icon) => size + utf8.encode(icon.content).length,),
      lessThan(64 * 1024),
      reason: 'A small compiled collection, not a copy of the 2.8MB Color pack',
    );
    expect(
      appFlowyDefaultIconGroups.expand((group) => group.icons),
      hasLength(46),
    );
  });

  test('cold Vivid resolution performs no asset IO or version notification',
      () async {
    final requestedAssets = <String>[];
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',
        (message) async {
      requestedAssets.add(
        utf8.decode(message!.buffer.asUint8List(
          message.offsetInBytes,
          message.lengthInBytes,
        ),),
      );
      return null;
    });
    addTearDown(() {
      binding.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    final version = iconPacksVersion.value;
    // Start from a literal persisted identity, not a preloaded catalogue.
    final saved = IconsData('appflowy_vivid_essentials', 'home', null);
    expect(saved.svgString, startsWith('<svg'));
    expect(isIconPackLoaded(kVividIconPack), isTrue);
    final groups = await loadIconPack(kVividIconPack);
    expect(groups, same(appFlowyVividIconGroups));
    await ensureIconPackLoadedForGroup(saved.groupName);
    expect(requestedAssets, isEmpty);
    expect(iconPacksVersion.value, version);
    for (final pack in kIconPacks.where((pack) => pack.asset.isNotEmpty)) {
      expect(isIconPackLoaded(pack), isFalse, reason: pack.id);
    }
  });

  test('loadIconGroups still loads only the original default asset pack',
      () async {
    final groups = await loadIconGroups();
    expect(groups, isNotEmpty);
    expect(groups, same(loadedIconGroupsOf(kDefaultIconPack)));
    expect(kIconGroups, same(groups));
    expect(await loadIconGroups(), same(groups));
    expect(iconPacksVersion.value, 1);
    for (final pack in kIconPacks.where(
      (pack) => pack.asset.isNotEmpty && pack != kDefaultIconPack,
    )) {
      expect(isIconPackLoaded(pack), isFalse, reason: pack.id);
    }
  });

  test('every Vivid identity survives protobuf, JSON, recents and a cold cache',
      () {
    for (final name in _names) {
      for (final color in [null, '4283665274']) {
        final original = IconsData('appflowy_vivid_essentials', name, color);
        final stored = ViewIconPB.fromBuffer(
          original.toEmojiIconData().toViewIcon().writeToBuffer(),
        );
        resetIconPacksForTesting();
        final decoded = stored.toEmojiIconData();
        final restored = IconsData.fromJson(jsonDecode(decoded.emoji));
        expect(stored.ty, ViewIconTypePB.Icon);
        expect(decoded.toPickerTabType(), PickerTabType.icon);
        expect(restored.groupName, original.groupName);
        expect(restored.iconName, original.iconName);
        expect(restored.color, color);
        expect(restored.svgString, vividIconSvg(name));
        expect(restored.noColor().svgString, vividIconSvg(name));
        expect(isIconPackLoaded(kDefaultIconPack), isFalse);
        expect(iconPacksVersion.value, 0);

        final recent = icons.RecentIcon(
          findLoadedIcon(restored.groupName, name)!,
          restored.groupName,
        );
        final roundTrip = icons.RecentIcon.fromJson(
          jsonDecode(jsonEncode(recent)) as Map<String, dynamic>,
        );
        expect(roundTrip.groupName, original.groupName);
        expect(roundTrip.name, name);
        expect(roundTrip.content, restored.svgString);
        expect(iconPackForGroup(roundTrip.groupName).isColorful, isTrue);
      }
    }
  });

  test('familiar names and synonyms search the curated collection', () {
    final group = appFlowyVividIconGroups.single;
    const queries = {
      'HOUSE': 'home',
      'closed book': 'book',
      'lightning': 'bolt',
      'coffee mug': 'coffee',
      'bullseye': 'target',
      'launch': 'rocket',
      'sprout': 'seedling',
      'light bulb': 'bulb',
      'magic': 'sparkles',
      'saturn': 'planet',
      'library': 'books',
    };
    for (final query in queries.entries) {
      final filtered = group.filter(query.key);
      expect(filtered.icons.map((icon) => icon.name), contains(query.value));
      expect(filtered.isColorful, isTrue);
      expect(filtered.icons.every((icon) => icon.isColorful), isTrue);
      expect(filtered.name, group.name);
    }
    expect(group.filter('no-such-vivid-icon').icons, isEmpty);
    expect(group.icons, hasLength(24));
  });

  test('legacy icon kinds, stored colors, defaults and tabs remain unchanged',
      () {
    final choices = [
      EmojiIconData.emoji('📚'),
      EmojiIconData.custom('local-profile-photo.png'),
      EmojiIconData.icon(
          IconsData('interface_essential', 'home', '4283665274'),),
      EmojiIconData.icon(IconsData('color_travel_places', 'full-moon', null)),
      EmojiIconData.icon(IconsData('phosphor_bold_office', 'book-open', null)),
      EmojiIconData.icon(
          IconsData('appflowy_default_collections', 'book', null),),
    ];
    for (final choice in choices) {
      final stored = ViewIconPB.fromBuffer(choice.toViewIcon().writeToBuffer());
      final restored = stored.toEmojiIconData();
      expect(restored.type, choice.type);
      expect(restored.emoji, choice.emoji);
      expect(restored.toPickerTabType(), choice.toPickerTabType());
    }
    expect(
        pickerTabsWithDefaults([PickerTabType.emoji]), [PickerTabType.emoji],);
    expect(
        pickerTabsWithDefaults([PickerTabType.custom]), [PickerTabType.custom],);
    expect(EmojiIconData.none().toPickerTabType(), PickerTabType.defaultIcons);
    expect(iconPackForGroup('color_travel_places').id, 'color');
    expect(iconPackForGroup('phosphor_bold_office').id, 'phosphor_bold');
    expect(iconPackForGroup('appflowy_default_collections'),
        kAppFlowyDefaultIconPack,);
    expect(iconPackForGroup('appflowy_vividish_essentials'), kDefaultIconPack);
    expect(findLoadedIcon('appflowy_vivid_essentials', 'missing'), isNull);
    expect(findLoadedIcon('appflowy_vivid_missing', 'home'), isNull);
    expect(vividIconSvg('missing'), isNull);
  });

  for (final name in _names) {
    test('$name is a self-contained colorful 32px SVG with real gradients', () {
      final content = vividIconSvg(name)!;
      final root = XmlDocument.parse(content).rootElement;
      expect(root.name.local, 'svg');
      expect(root.getAttribute('viewBox'), '0 0 32 32');
      final elements = root.descendants.whereType<XmlElement>().toList();
      expect(
        elements.map((element) => element.name.local),
        isNot(anyElement(isIn(['filter', 'image', 'script', 'foreignObject']))),
      );
      expect(content, isNot(contains('currentColor')));
      expect(content, isNot(contains('href=')));
      final gradients = elements
          .where((element) => element.name.local == 'linearGradient')
          .toList();
      expect(gradients, hasLength(2));
      for (final gradient in gradients) {
        expect(gradient.getAttribute('gradientUnits'), 'userSpaceOnUse');
        final stops = gradient.findElements('stop').toList();
        expect(stops, hasLength(2));
        expect(stops.first.getAttribute('stop-color'),
            isNot(stops.last.getAttribute('stop-color')),);
      }
      final ids =
          gradients.map((gradient) => gradient.getAttribute('id')).toSet();
      final references = RegExp(r'url\(#([^)]+)\)')
          .allMatches(content)
          .map((match) => match.group(1))
          .toSet();
      expect(references, ids);
      expect(
          RegExp('#[0-9A-F]{6}')
              .allMatches(content)
              .map((m) => m[0])
              .toSet()
              .length,
          greaterThanOrEqualTo(5),);
    });
  }
}
