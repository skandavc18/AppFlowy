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
  'page',
  'file',
  'pdf',
  'document',
  'spreadsheet',
  'presentation',
  'archive',
  'code-file',
  'markdown',
  'html-file',
  'json-file',
  'notebook',
  'csv',
  'image',
  'video',
  'album',
  'repository',
  'database',
  'bookmark',
  'mail',
  'table',
  'board',
  'chat',
  'ai-chat',
  'map',
  'slides',
  'timeline',
  'feed',
  'form',
  'gallery',
  'dashboard',
  'canvas',
];

const _essentialsGroup = 'appflowy_vivid_essentials';

// Literal saved identities: these must resolve without first reading a
// catalogue or borrowing an icon from a differently named category.
const _categorySearchCases = <String, (String, String)>{
  'appflowy_vivid_navigation': ('search', 'magnifying glass'),
  'appflowy_vivid_editing': ('selection', 'marquee'),
  'appflowy_vivid_data': ('relation', 'link records'),
  'appflowy_vivid_work': ('briefcase', 'career'),
  'appflowy_vivid_security': ('key', 'credential'),
  'appflowy_vivid_learning': ('graduation-cap', 'university'),
  'appflowy_vivid_nature': ('sun', 'sunshine'),
  'appflowy_vivid_travel': ('sailboat', 'harbor'),
  'appflowy_vivid_food': ('teapot', 'brew'),
  'appflowy_vivid_health': ('stethoscope', 'diagnosis'),
  'appflowy_vivid_technology': ('terminal', 'command line'),
};

Iterable<(String, icons.Icon)> get _vividChoices =>
    appFlowyVividIconGroups.expand(
      (group) => group.icons.map((icon) => (group.name, icon)),
    );

void main() {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetIconPacksForTesting();
    kIconGroups = null;
  });

  test('Vivid retains its original choices and adds workspace identities', () {
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

    final group = appFlowyVividIconGroups.firstWhere(
      (group) => group.name == _essentialsGroup,
    );
    expect(group.name, _essentialsGroup);
    expect(group.displayName, 'essentials');
    expect(group.packId, appFlowyVividIconPackId);
    expect(group.isColorful, isTrue);
    expect(group.icons, hasLength(56));
    expect(group.icons.map((icon) => icon.name), _names);
    expect(group.icons.map((icon) => icon.content).toSet(), hasLength(56));
    for (final icon in group.icons) {
      expect(icon.isColorful, isTrue);
      expect(icon.iconPath, '${group.name}/${icon.name}');
      expect(icon.content, vividIconSvg(icon.name));
      expect(iconPackForGroup(group.name), same(kVividIconPack));
      expect(icon.keywords, isNotEmpty);
    }
    expect(
      group.icons.fold<int>(
        0,
        (size, icon) => size + utf8.encode(icon.content).length,
      ),
      lessThan(96 * 1024),
      reason: 'A small compiled collection, not a copy of the 2.8MB Color pack',
    );
    expect(
      appFlowyDefaultIconGroups.expand((group) => group.icons),
      hasLength(57),
    );
  });

  test('all Vivid categories expose unique illustrated picker identities', () {
    final groups = appFlowyVividIconGroups;
    final choices = _vividChoices.toList();
    expect(groups, hasLength(12));
    expect(
      groups.map((group) => group.name),
      containsAll([_essentialsGroup, ..._categorySearchCases.keys]),
    );
    expect(groups.map((group) => group.name).toSet(), hasLength(groups.length));
    expect(choices, hasLength(150));
    expect(
      choices.map((choice) => '${choice.$1}/${choice.$2.name}').toSet(),
      hasLength(choices.length),
    );
    expect(
      choices.map((choice) => choice.$2.name).toSet(),
      hasLength(choices.length),
      reason: 'A new name belongs to one category, not several aliases',
    );
    for (final group in groups) {
      expect(group.name, startsWith(appFlowyVividIconGroupPrefix));
      expect(group.icons, isNotEmpty, reason: group.name);
      expect(group.packId, appFlowyVividIconPackId, reason: group.name);
      expect(group.groupPrefix, appFlowyVividIconGroupPrefix);
      expect(group.isColorful, isTrue, reason: group.name);
      expect(iconPackForGroup(group.name), same(kVividIconPack));
    }
    for (final (groupName, icon) in choices) {
      final identity = '$groupName/${icon.name}';
      expect(icon.name, isNot(startsWith('utility-')), reason: identity);
      expect(icon.iconGroup?.name, groupName, reason: identity);
      expect(icon.iconPath, identity);
      expect(icon.isColorful, isTrue, reason: identity);
      expect(icon.keywords, isNotEmpty, reason: identity);
      expect(icon.content, vividIconSvg(icon.name), reason: identity);
      expect(
        findLoadedIcon(groupName, icon.name),
        same(icon),
        reason: identity,
      );
      for (final other in groups.where((group) => group.name != groupName)) {
        expect(
          findLoadedIcon(other.name, icon.name),
          isNull,
          reason: '$identity must not resolve under ${other.name}',
        );
      }
    }
  });

  test('cold Vivid resolution performs no asset IO or version notification',
      () async {
    final requestedAssets = <String>[];
    binding.defaultBinaryMessenger.setMockMessageHandler('flutter/assets',
        (message) async {
      requestedAssets.add(
        utf8.decode(
          message!.buffer.asUint8List(
            message.offsetInBytes,
            message.lengthInBytes,
          ),
        ),
      );
      return null;
    });
    addTearDown(() {
      binding.defaultBinaryMessenger
          .setMockMessageHandler('flutter/assets', null);
    });

    final notifications = <int>[];
    void onVersionChanged() => notifications.add(iconPacksVersion.value);
    iconPacksVersion.addListener(onVersionChanged);
    addTearDown(() => iconPacksVersion.removeListener(onVersionChanged));

    Future<void> expectColdResolution(String groupName, String iconName) async {
      resetIconPacksForTesting();
      final version = iconPacksVersion.value;
      final saved = IconsData(groupName, iconName, null);
      expect(saved.svgString, startsWith('<svg'), reason: saved.iconString);
      expect(saved.svgString, vividIconSvg(saved.iconName));
      expect(
        findLoadedIcon(saved.groupName, saved.iconName)?.iconPath,
        '$groupName/$iconName',
        reason: saved.iconString,
      );
      expect(isIconPackLoaded(kVividIconPack), isTrue);
      final groups = await loadIconPack(kVividIconPack);
      expect(groups, same(appFlowyVividIconGroups));
      await ensureIconPackLoadedForGroup(saved.groupName);
      expect(iconPacksVersion.value, version, reason: saved.iconString);
      expect(kIconGroups, isNull);
    }

    // Resolve literal persisted identities before reading the catalogue.
    final identities = {
      _essentialsGroup: ('home', 'house'),
      ..._categorySearchCases,
    };
    for (final entry in identities.entries) {
      await expectColdResolution(entry.key, entry.value.$1);
    }
    final choices = _vividChoices.toList();
    expect(choices, hasLength(150));
    for (final (groupName, icon) in choices) {
      await expectColdResolution(groupName, icon.name);
    }
    expect(requestedAssets, isEmpty);
    expect(notifications, isEmpty);
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
    final choices = _vividChoices.toList();
    expect(choices, hasLength(150));
    for (final (groupName, icon) in choices) {
      final name = icon.name;
      for (final color in [null, '4283665274']) {
        final original = IconsData(groupName, name, color);
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
        expect(
          utf8.encode(restored.svgString!),
          utf8.encode(icon.content),
          reason: '$groupName/$name keeps its exact artwork bytes',
        );
        expect(restored.noColor().groupName, groupName);
        expect(restored.noColor().color, isNull);
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
        expect(roundTrip.keywords, icon.keywords);
        expect(roundTrip.content, restored.svgString);
        expect(iconPackForGroup(roundTrip.groupName).isColorful, isTrue);
      }
    }
  });

  test('familiar names and synonyms search the curated collection', () {
    final group = appFlowyVividIconGroups.firstWhere(
      (group) => group.name == _essentialsGroup,
    );
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
      'compressed': 'archive',
      'jupyter': 'notebook',
      'assistant': 'ai-chat',
      'kanban': 'board',
    };
    for (final query in queries.entries) {
      final filtered = group.filter(query.key);
      expect(filtered.icons.map((icon) => icon.name), contains(query.value));
      expect(filtered.isColorful, isTrue);
      expect(filtered.icons.every((icon) => icon.isColorful), isTrue);
      expect(filtered.name, group.name);
    }
    expect(group.filter('no-such-vivid-icon').icons, isEmpty);
    expect(group.icons, hasLength(56));
  });

  test('all names, keywords and added categories are searchable', () {
    final groups = appFlowyVividIconGroups;
    expect(groups, hasLength(12));
    expect(groups.expand((group) => group.icons), hasLength(150));
    for (final group in groups) {
      if (group.name != _essentialsGroup) {
        final category =
            group.name.substring(appFlowyVividIconGroupPrefix.length);
        final filtered = group.filter(category.toUpperCase());
        expect(
          filtered.icons.map((icon) => icon.name),
          group.icons.map((icon) => icon.name),
          reason: 'The entire $category category must be searchable',
        );
        for (final icon in group.icons) {
          expect(icon.keywords, contains(category), reason: icon.iconPath);
        }
      }
      for (final icon in group.icons) {
        for (final query in [icon.name, ...icon.keywords]) {
          final filtered = group.filter(query.toUpperCase());
          expect(
            filtered.icons,
            contains(icon),
            reason: '${group.name}/$query',
          );
          expect(filtered.name, group.name);
          expect(filtered.packId, appFlowyVividIconPackId);
          expect(filtered.groupPrefix, appFlowyVividIconGroupPrefix);
          expect(filtered.isColorful, isTrue);
          expect(filtered.icons.every((icon) => icon.isColorful), isTrue);
        }
      }
    }
    for (final entry in _categorySearchCases.entries) {
      final matches = groups
          .map((group) => group.filter(entry.value.$2.toUpperCase()))
          .expand(
            (group) => group.icons.map((icon) => '${group.name}/${icon.name}'),
          );
      expect(matches, contains('${entry.key}/${entry.value.$1}'));
    }
    for (final query in ['no-such-vivid-icon', 'utility-']) {
      expect(
        groups
            .map((group) => group.filter(query))
            .expand((group) => group.icons),
        isEmpty,
        reason: query,
      );
    }
  });

  test('legacy icon kinds, stored colors, defaults and tabs remain unchanged',
      () {
    final choices = [
      EmojiIconData.emoji('📚'),
      EmojiIconData.custom('local-profile-photo.png'),
      EmojiIconData.icon(
        IconsData('interface_essential', 'home', '4283665274'),
      ),
      EmojiIconData.icon(IconsData('color_travel_places', 'full-moon', null)),
      EmojiIconData.icon(IconsData('phosphor_bold_office', 'book-open', null)),
      EmojiIconData.icon(
        IconsData('appflowy_default_collections', 'book', null),
      ),
    ];
    for (final choice in choices) {
      final stored = ViewIconPB.fromBuffer(choice.toViewIcon().writeToBuffer());
      final restored = stored.toEmojiIconData();
      expect(restored.type, choice.type);
      expect(restored.emoji, choice.emoji);
      expect(restored.toPickerTabType(), choice.toPickerTabType());
    }
    expect(
      pickerTabsWithDefaults([PickerTabType.emoji]),
      [PickerTabType.emoji],
    );
    expect(
      pickerTabsWithDefaults([PickerTabType.custom]),
      [PickerTabType.custom],
    );
    expect(EmojiIconData.none().toPickerTabType(), PickerTabType.defaultIcons);
    expect(iconPackForGroup('color_travel_places').id, 'color');
    expect(iconPackForGroup('phosphor_bold_office').id, 'phosphor_bold');
    expect(
      iconPackForGroup('appflowy_default_collections'),
      kAppFlowyDefaultIconPack,
    );
    expect(iconPackForGroup('appflowy_vividish_essentials'), kDefaultIconPack);
    expect(findLoadedIcon('appflowy_vivid_essentials', 'missing'), isNull);
    expect(findLoadedIcon('appflowy_vivid_missing', 'home'), isNull);
    expect(vividIconSvg('missing'), isNull);
  });

  test('every picker SVG is self-contained with meaningful unique geometry',
      () {
    final bodies = <String, String>{};
    final choices = _vividChoices.toList();
    expect(choices, hasLength(150));
    for (final (groupName, icon) in choices) {
      final identity = '$groupName/${icon.name}';
      final root = _expectSelfContainedSvg(icon.content, reason: identity);
      final shapes = _artworkElements(root).where(
        (element) => const {
          'path',
          'rect',
          'circle',
          'ellipse',
          'line',
          'polyline',
          'polygon',
        }.contains(element.name.local),
      );
      expect(shapes.length, greaterThanOrEqualTo(2), reason: identity);
      for (final path
          in shapes.where((element) => element.name.local == 'path')) {
        expect(path.getAttribute('d'), isNotEmpty, reason: identity);
      }
      final body = jsonEncode(_artworkGeometry(root));
      expect(
        bodies.containsKey(body),
        isFalse,
        reason: '$identity must not merely recolor ${bodies[body]}',
      );
      bodies[body] = identity;

      // Keep the original Essentials palette contract without imposing its
      // saturated colors or an exact gradient count on new illustrations.
      // Some new illustrations use only their four gradient-stop colors.
      if (groupName == _essentialsGroup) {
        expect(
          root.descendants.whereType<XmlElement>().where(
                (element) => element.name.local == 'linearGradient',
              ),
          hasLength(2),
          reason: identity,
        );
        expect(
          RegExp('#[0-9A-F]{6}')
              .allMatches(icon.content)
              .map((match) => match[0])
              .toSet()
              .length,
          greaterThanOrEqualTo(5),
          reason: identity,
        );
      }
    }
  });

  test('compiled utility fallback is valid artwork but never a picker choice',
      () {
    for (final name in [
      'utility-check',
      'utility-arrow-left',
      'utility-trash',
    ]) {
      final content = vividIconSvg(name);
      expect(content, isNotNull, reason: name);
      _expectSelfContainedSvg(content!, reason: name);
      for (final group in appFlowyVividIconGroups) {
        expect(findLoadedIcon(group.name, name), isNull, reason: group.name);
      }
    }
    expect(vividIconSvg('utility-unknown'), isNull);
    expect(vividIconSvg('utility-no-such-icon'), isNull);
  });
}

XmlElement _expectSelfContainedSvg(String content, {required String reason}) {
  final root = XmlDocument.parse(content).rootElement;
  expect(root.name.local, 'svg', reason: reason);
  expect(root.getAttribute('viewBox'), '0 0 32 32', reason: reason);
  expect(
    content.toLowerCase(),
    isNot(contains('currentcolor')),
    reason: reason,
  );
  expect(content.toUpperCase(), isNot(contains('<!DOCTYPE')), reason: reason);
  final elements = [root, ...root.descendants.whereType<XmlElement>()];
  expect(
    elements.map((element) => element.name.local.toLowerCase()),
    isNot(
      anyElement(
        isIn(['filter', 'image', 'script', 'foreignobject', 'use', 'style']),
      ),
    ),
    reason: reason,
  );
  for (final attribute in elements.expand((element) => element.attributes)) {
    // Local names include both href and xlink:href, independent of quoting.
    final name = attribute.name.local.toLowerCase();
    expect(name, isNot('href'), reason: reason);
    expect(name, isNot(startsWith('on')), reason: '$reason event handler');
  }
  final ids = elements
      .map((element) => element.getAttribute('id'))
      .whereType<String>()
      .toList();
  expect(
    ids.toSet(),
    hasLength(ids.length),
    reason: '$reason duplicate SVG ids',
  );
  final gradients = elements.where(
    (element) =>
        const ['linearGradient', 'radialGradient'].contains(element.name.local),
  );
  expect(gradients, isNotEmpty, reason: reason);
  final gradientIds = <String>{};
  for (final gradient in gradients) {
    final id = gradient.getAttribute('id');
    expect(id, isNotEmpty, reason: reason);
    gradientIds.add(id!);
    expect(
      gradient.getAttribute('gradientUnits'),
      'userSpaceOnUse',
      reason: reason,
    );
    final stops = gradient.findElements('stop').toList();
    expect(stops.length, greaterThanOrEqualTo(2), reason: reason);
    final colors =
        stops.map((stop) => stop.getAttribute('stop-color')).toList();
    expect(colors, everyElement(isNotEmpty), reason: reason);
    expect(colors.first, isNot(colors.last), reason: '$reason real gradient');
  }
  final references = <String>{};
  for (final match
      in RegExp(r'url\(([^)]*)\)', caseSensitive: false).allMatches(content)) {
    final reference = RegExp(r'''^(['"]?)#([A-Za-z_][\w.:-]*)\1$''')
        .firstMatch(match.group(1)!.trim());
    expect(reference, isNotNull, reason: '$reason only local SVG references');
    final id = reference!.group(2)!;
    expect(ids, contains(id), reason: '$reason dangling reference #$id');
    references.add(id);
  }
  expect(
    references,
    containsAll(gradientIds),
    reason: '$reason uses its gradients',
  );
  return root;
}

Iterable<XmlElement> _artworkElements(XmlElement root) sync* {
  for (final child in root.childElements) {
    if (const ['defs', 'title', 'desc'].contains(child.name.local)) continue;
    yield child;
    yield* _artworkElements(child);
  }
}

// Ignore palette, ids and descriptive metadata so recolored duplicates cannot
// inflate the catalogue. Retain nested transforms and actual drawing geometry.
List<Object> _artworkGeometry(XmlElement element) => [
      element.name.local,
      for (final name in const [
        'd',
        'points',
        'x',
        'y',
        'x1',
        'x2',
        'y1',
        'y2',
        'cx',
        'cy',
        'r',
        'rx',
        'ry',
        'width',
        'height',
        'transform',
        'fill-rule',
        'clip-rule',
        'stroke-width',
        'stroke-linecap',
        'stroke-linejoin',
      ])
        if (element.getAttribute(name) != null)
          [
            name,
            element.getAttribute(name)!.replaceAll(RegExp(r'\s+'), ' ').trim(),
          ],
      for (final child in element.childElements)
        if (!const ['defs', 'title', 'desc'].contains(child.name.local))
          _artworkGeometry(child),
    ];
