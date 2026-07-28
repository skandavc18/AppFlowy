import 'dart:convert';

import 'package:appflowy/shared/icon_emoji_picker/icon.dart';
import 'package:appflowy_backend/log.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// A selectable icon library.
///
/// Every pack is a separate JSON asset with the same shape as the built-in
/// `icons.json`, and its group names are namespaced with [groupPrefix] so that
/// a stored `groupName/iconName` pair stays globally unique.
class IconPack {
  const IconPack({
    required this.id,
    required this.displayName,
    required this.asset,
    required this.groupPrefix,
    required this.attribution,
    required this.attributionUrl,
    this.isColorful = false,
  });

  final String id;

  /// The label shown in the style selector of the icon picker.
  final String displayName;

  final String asset;

  /// The prefix every group name of this pack starts with. Empty for the
  /// built-in pack, whose groups are plain category names.
  final String groupPrefix;

  /// The library the artwork comes from, credited under the icon grid.
  final String attribution;
  final String attributionUrl;

  /// Whether the artwork carries its own colors. Multi-color icons must be
  /// painted as-is; tinting them collapses every layer into one flat color.
  final bool isColorful;

  bool owns(String groupName) =>
      groupPrefix.isNotEmpty && groupName.startsWith(groupPrefix);
}

const kDefaultIconPack = IconPack(
  id: 'default',
  displayName: 'Default',
  asset: 'assets/icons/icons.json',
  groupPrefix: '',
  attribution: 'Streamline',
  attributionUrl: 'https://www.streamlinehq.com/',
);

const _kPhosphorAttribution = 'Phosphor Icons';
const _kPhosphorUrl = 'https://phosphoricons.com/';

/// The packs available in the icon picker, in the order they are offered.
const List<IconPack> kIconPacks = [
  kDefaultIconPack,
  IconPack(
    id: 'color',
    displayName: 'Color',
    asset: 'assets/icons/color_icons.json',
    groupPrefix: 'color_',
    attribution: 'Fluent Emoji',
    attributionUrl: 'https://github.com/microsoft/fluentui-emoji',
    isColorful: true,
  ),
  IconPack(
    id: 'phosphor_thin',
    displayName: 'Thin',
    asset: 'assets/icons/phosphor_thin.json',
    groupPrefix: 'phosphor_thin_',
    attribution: _kPhosphorAttribution,
    attributionUrl: _kPhosphorUrl,
  ),
  IconPack(
    id: 'phosphor_light',
    displayName: 'Light',
    asset: 'assets/icons/phosphor_light.json',
    groupPrefix: 'phosphor_light_',
    attribution: _kPhosphorAttribution,
    attributionUrl: _kPhosphorUrl,
  ),
  IconPack(
    id: 'phosphor_regular',
    displayName: 'Line',
    asset: 'assets/icons/phosphor_regular.json',
    groupPrefix: 'phosphor_regular_',
    attribution: _kPhosphorAttribution,
    attributionUrl: _kPhosphorUrl,
  ),
  IconPack(
    id: 'phosphor_bold',
    displayName: 'Bold',
    asset: 'assets/icons/phosphor_bold.json',
    groupPrefix: 'phosphor_bold_',
    attribution: _kPhosphorAttribution,
    attributionUrl: _kPhosphorUrl,
  ),
  IconPack(
    id: 'phosphor_fill',
    displayName: 'Solid',
    asset: 'assets/icons/phosphor_fill.json',
    groupPrefix: 'phosphor_fill_',
    attribution: _kPhosphorAttribution,
    attributionUrl: _kPhosphorUrl,
  ),
  IconPack(
    id: 'phosphor_duotone',
    displayName: 'Duotone',
    asset: 'assets/icons/phosphor_duotone.json',
    groupPrefix: 'phosphor_duotone_',
    attribution: _kPhosphorAttribution,
    attributionUrl: _kPhosphorUrl,
  ),
];

IconPack iconPackForGroup(String groupName) => kIconPacks.firstWhere(
      (pack) => pack.owns(groupName),
      orElse: () => kDefaultIconPack,
    );

final Map<String, List<IconGroup>> _loadedPacks = {};
final Map<String, Future<List<IconGroup>>> _pendingPacks = {};

/// Bumped every time a pack finishes loading, so widgets that resolve an icon
/// synchronously can repaint once its pack becomes available.
final ValueNotifier<int> iconPacksVersion = ValueNotifier<int>(0);

bool isIconPackLoaded(IconPack pack) => _loadedPacks.containsKey(pack.id);

List<IconGroup> loadedIconGroupsOf(IconPack pack) =>
    _loadedPacks[pack.id] ?? const [];

/// Loads [pack] once and returns its groups. Concurrent calls share one load.
Future<List<IconGroup>> loadIconPack(IconPack pack) {
  final loaded = _loadedPacks[pack.id];
  if (loaded != null) {
    return Future.value(loaded);
  }
  return _pendingPacks[pack.id] ??= _loadIconPack(pack);
}

/// Makes sure the pack that owns [groupName] is loaded, so an icon stored by a
/// document renders even when its pack has never been opened in the picker.
Future<void> ensureIconPackLoadedForGroup(String groupName) async {
  final pack = iconPackForGroup(groupName);
  if (isIconPackLoaded(pack)) {
    return;
  }
  await loadIconPack(pack);
}

Future<List<IconGroup>> _loadIconPack(IconPack pack) async {
  final stopwatch = Stopwatch()..start();
  try {
    final jsonString = await rootBundle.loadString(pack.asset);
    // decoding a ~1MB pack blocks long enough to drop frames on the main
    // isolate, so hand it off
    final json = await compute(jsonDecode, jsonString) as Map<String, dynamic>;
    final groups = json.entries.map(IconGroup.fromMapEntry).toList();
    for (final group in groups) {
      group.packId = pack.id;
      group.groupPrefix = pack.groupPrefix;
      group.isColorful = pack.isColorful;
    }
    _loadedPacks[pack.id] = groups;
    iconPacksVersion.value++;
    return groups;
  } catch (e) {
    Log.error('Failed to load icon pack ${pack.id}', e);
    _loadedPacks[pack.id] = const [];
    return const [];
  } finally {
    _pendingPacks.remove(pack.id)?.ignore();
    stopwatch.stop();
    Log.info(
      'Loaded icon pack ${pack.id} in ${stopwatch.elapsedMilliseconds}ms',
    );
  }
}

@visibleForTesting
void resetIconPacksForTesting() {
  _loadedPacks.clear();
  _pendingPacks.clear();
  iconPacksVersion.value = 0;
}
