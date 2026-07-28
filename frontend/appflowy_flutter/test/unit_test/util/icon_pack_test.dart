import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('icon packs', () {
    test('the default pack is the built-in streamline set', () {
      expect(kIconPacks.first, kDefaultIconPack);
      expect(kDefaultIconPack.groupPrefix, isEmpty);
      expect(kDefaultIconPack.owns('interface_essential'), isFalse);
    });

    test('every extra pack has a unique, non-empty group prefix', () {
      final prefixes = kIconPacks
          .where((pack) => pack != kDefaultIconPack)
          .map((pack) => pack.groupPrefix)
          .toList();

      expect(prefixes, isNotEmpty);
      expect(prefixes.any((prefix) => prefix.isEmpty), isFalse);
      expect(prefixes.toSet().length, prefixes.length);
    });

    test('a group name resolves back to the pack that owns it', () {
      for (final pack in kIconPacks.where((p) => p != kDefaultIconPack)) {
        expect(iconPackForGroup('${pack.groupPrefix}nature'), pack);
      }
      // unknown groups fall back to the built-in pack
      expect(iconPackForGroup('interface_essential'), kDefaultIconPack);
    });

    test('every pack loads and its icons carry renderable svg content',
        () async {
      for (final pack in kIconPacks) {
        final groups = await loadIconPack(pack);

        expect(groups, isNotEmpty, reason: pack.id);
        expect(isIconPackLoaded(pack), isTrue, reason: pack.id);

        for (final group in groups) {
          expect(group.icons, isNotEmpty, reason: '${pack.id}/${group.name}');
          expect(group.name.startsWith(pack.groupPrefix), isTrue);
          if (pack.groupPrefix.isNotEmpty) {
            // the pack namespace is an implementation detail of the storage key
            expect(group.displayName.contains(pack.groupPrefix), isFalse);
          }
        }

        final icon = groups.first.icons.first;
        expect(icon.content, startsWith('<svg'));
        expect(
          findLoadedIcon(groups.first.name, icon.name)?.content,
          icon.content,
        );
      }
    });

    test('a stored icon of any pack resolves to its svg', () async {
      for (final pack in kIconPacks) {
        final groups = await loadIconPack(pack);
        final group = groups.first;
        final icon = group.icons.first;

        expect(
          IconsData(group.name, icon.name, null).svgString,
          icon.content,
          reason: pack.id,
        );
      }
    });

    test('only the color pack reports multi-color artwork', () async {
      final colorful = kIconPacks.where((pack) => pack.isColorful).toList();
      expect(colorful.map((pack) => pack.id), ['color']);

      for (final pack in kIconPacks) {
        final groups = await loadIconPack(pack);
        for (final group in groups) {
          expect(group.isColorful, pack.isColorful, reason: group.name);
          expect(group.icons.first.isColorful, pack.isColorful);
        }
      }
    });

    test('color icons keep their own fills', () async {
      final groups = await loadIconPack(
        kIconPacks.firstWhere((pack) => pack.isColorful),
      );
      final icon = findLoadedIcon('color_travel_places', 'full-moon');

      expect(icon, isNotNull);
      // more than one fill is exactly what a tint would destroy
      expect('fill="#'.allMatches(icon!.content).length, greaterThan(1));
      expect(groups.expand((group) => group.icons).length, greaterThan(1000));
    });
  });
}
