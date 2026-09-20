import 'dart:convert';
import 'dart:ui' as ui;

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/core/config/kv_keys.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon.dart' as icons;
import 'package:appflowy/shared/icon_emoji_picker/icon_color_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_search_bar.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icons.dart';
import 'package:appflowy/shared/paper_theme.dart';
import 'package:appflowy/startup/startup.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart' show FlowyButton;
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'vivid_icon_test_support.dart';

void main() {
  setUpAll(() async {
    RecentIcons.enable = false;
    await prepareVividIconTestAssets();
  });
  setUp(resetVividIconTestPacks);
  tearDownAll(() => RecentIcons.enable = true);

  for (final appearance in vividIconTestAppearances) {
    for (final colors in [true, false]) {
      testWidgets(
          '$appearance: Vivid is visible and all 24 choices select '
          '(color selection $colors)', (tester) async {
        final selections = <SelectedEmojiIconResult>[];
        await tester.pumpWidget(
          vividIconTestApp(
            appearance,
            vividIconTestPicker(colors: colors, onSelected: selections.add),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<IconPicker>(find.byType(IconPicker)).pack,
          kDefaultIconPack,
        );
        final tabs = tester.widget<PickerTab>(find.byType(PickerTab));
        expect(tabs.tabs, [
          PickerTabType.emoji,
          PickerTabType.defaultIcons,
          PickerTabType.icon,
          PickerTabType.custom,
        ]);
        expect(vividIconStyleButton('Vivid').hitTestable(), findsOneWidget);
        expect(vividIconStyleButton('Color').hitTestable(), findsOneWidget);
        expect(
          tester.getTopLeft(vividIconStyleButton('Vivid')).dy,
          tester.getTopLeft(vividIconStyleButton('Default')).dy,
        );
        final version = iconPacksVersion.value;
        await tester.tap(vividIconStyleButton('Vivid'));
        await settleVividIconPictures(tester);
        final picker = tester.widget<IconPicker>(find.byType(IconPicker));
        expect(picker.pack, kVividIconPack);
        expect(picker.iconGroups.single.icons, hasLength(24));
        expect(find.byType(CircularProgressIndicator), findsNothing);
        expect(iconPacksVersion.value, version);
        expect(isIconPackLoaded(iconPackForGroup('color_activities')), isFalse);
        expect(find.byType(StreamlinePermit), findsOneWidget);
        expect(
          tester.widget<StreamlinePermit>(find.byType(StreamlinePermit)).pack,
          kVividIconPack,
        );
        final permit = tester.widget<RichText>(
          find.descendant(
            of: find.byType(StreamlinePermit),
            matching: find.byType(RichText),
          ),
        );
        final expectedFont = DefaultTextStyle.of(
          tester.element(find.byType(StreamlinePermit)),
        ).style.fontFamily;
        expect(expectedFont, isNotNull);
        for (final span in (permit.text as TextSpan).children!) {
          expect(span.style!.fontFamily, expectedFont);
        }

        for (final icon in picker.iconGroups.single.icons) {
          final button = vividIconOption(icon.name);
          expect(button.hitTestable(), findsOneWidget, reason: icon.name);
          await tester.tap(button);
          await tester.pump();
          final selected = selections.last;
          expect(selected.keepOpen, isFalse);
          final stored = ViewIconPB.fromBuffer(
            selected.data.toViewIcon().writeToBuffer(),
          );
          final restored = IconsData.fromJson(jsonDecode(stored.value));
          expect(stored.ty, ViewIconTypePB.Icon);
          expect(restored.groupName, vividIconTestGroup);
          expect(restored.iconName, icon.name);
          expect(restored.color, isNull);
          expect(restored.svgString, icon.content);
          expect(find.byType(IconColorPicker), findsNothing);
        }
        expect(selections, hasLength(24));
        expect(tester.takeException(), isNull);
        await disposeVividIconPicker(tester);
      });
    }

    testWidgets(
        '$appearance: real search filters synonyms and recovers from '
        'empty results', (tester) async {
      SelectedEmojiIconResult? result;
      await tester.pumpWidget(
        vividIconTestApp(
          appearance,
          vividIconTestPicker(onSelected: (selection) => result = selection),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(vividIconStyleButton('Vivid'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'SPROUT');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(vividIconOption('seedling'), findsOneWidget);
      expect(vividIconOption('home'), findsNothing);
      await tester.enterText(find.byType(TextField), 'no-such-vivid-icon');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(
        tester.widget<IconPicker>(find.byType(IconPicker)).iconGroups,
        isEmpty,
      );
      await tester.enterText(find.byType(TextField), 'coffee mug');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      await tester.tap(vividIconOption('coffee'));
      await tester.pumpAndSettle();
      expect(IconsData.fromJson(jsonDecode(result!.emoji)).iconName, 'coffee');
      expect(find.byType(IconColorPicker), findsNothing);
      await tester.enterText(find.byType(TextField), '');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(
        tester
            .widget<IconPicker>(find.byType(IconPicker))
            .iconGroups
            .single
            .icons,
        hasLength(24),
      );
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets(
        '$appearance: random Vivid choices keep their palette and '
        'the picker open', (tester) async {
      SelectedEmojiIconResult? result;
      await tester.pumpWidget(
        vividIconTestApp(
          appearance,
          vividIconTestPicker(onSelected: (selection) => result = selection),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(vividIconStyleButton('Vivid'));
      await tester.pumpAndSettle();
      final random = find
          .descendant(
            of: find.byType(IconSearchBar),
            matching: find.byType(FlowyButton),
          )
          .last;
      for (var i = 0; i < 12; i++) {
        await tester.tap(random);
        await tester.pump();
        expect(result!.keepOpen, isTrue);
        final data = IconsData.fromJson(jsonDecode(result!.emoji));
        expect(data.groupName, vividIconTestGroup);
        expect(data.color, isNull);
        expect(data.svgString, isNotNull);
      }
      expect(find.byType(IconColorPicker), findsNothing);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    });

    testWidgets(
        '$appearance: cold IconPB rendering keeps actual gradient '
        'pixels, transparency and colors', (tester) async {
      await tester.pumpWidget(vividIconTestApp(appearance, const SizedBox()));
      await tester.pumpAndSettle();
      resetIconPacksForTesting();
      final names = appFlowyVividIconGroups.single.icons
          .map((icon) => icon.name)
          .toList();
      for (final size in [18.0, 32.0, 54.0]) {
        await tester.pumpWidget(
          vividIconTestApp(
            appearance,
            Wrap(
              children: [
                for (final name in names)
                  RepaintBoundary(
                    key: ValueKey('cold-vivid-$name'),
                    child: RawEmojiIconWidget(
                      emoji: ViewIconPB.fromBuffer(
                        IconsData(vividIconTestGroup, name, '4278255360')
                            .toEmojiIconData()
                            .toViewIcon()
                            .writeToBuffer(),
                      ).toEmojiIconData(),
                      emojiSize: size,
                      // Both paths must preserve multicolor artwork, even if
                      // a legacy caller removes its stored tint.
                      enableColor: size != 18,
                    ),
                  ),
              ],
            ),
          ),
        );
        // The SVG is resolved on the very first frame, without an asset pack.
        expect(find.byType(IconWidget), findsNWidgets(24));
        expect(find.byType(FlowySvg), findsNWidgets(24));
        for (final svg in tester.widgetList<FlowySvg>(find.byType(FlowySvg))) {
          expect(svg.blendMode, isNull);
          expect(svg.color, isNull);
          expect(svg.opacity, isNull);
          expect(tester.getSize(find.byWidget(svg)), Size.square(size));
        }
        expect(iconPacksVersion.value, 0);
        expect(isIconPackLoaded(kDefaultIconPack), isFalse);
        expect(isIconPackLoaded(iconPackForGroup('color_activities')), isFalse);
        await settleVividIconPictures(tester);
        if (size == 32) {
          for (final name in names) {
            final pixels = await _pixels(
              tester,
              find.byKey(ValueKey('cold-vivid-$name')),
            );
            _expectIllustratedPixels(pixels, reason: '$appearance/$name');
          }
        }
        expect(tester.takeException(), isNull);
      }
      await disposeVividIconPicker(tester);
    });

    testWidgets(
        '$appearance: 280px picker at 2x text supports native Tab, '
        'Enter and Space with labeled buttons', (tester) async {
      final semantics = tester.ensureSemantics();
      final results = <SelectedEmojiIconResult>[];
      try {
        await tester.pumpWidget(
          vividIconTestApp(
            appearance,
            MediaQuery(
              data: const MediaQueryData(textScaler: TextScaler.linear(2)),
              child: vividIconTestPicker(width: 280, onSelected: results.add),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(vividIconStyleButton('Vivid').hitTestable(), findsOneWidget);
        expect(vividIconStyleButton('Color').hitTestable(), findsOneWidget);
        await _tabTo(tester, vividIconStyleButton('Vivid'));
        await tester.sendKeyEvent(LogicalKeyboardKey.enter);
        await tester.pumpAndSettle();
        final styleData = tester
            .getSemantics(vividIconStyleButton('Vivid'))
            .getSemanticsData();
        expect(styleData.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(styleData.hasFlag(ui.SemanticsFlag.isSelected), isTrue);
        expect(styleData.hasAction(ui.SemanticsAction.tap), isTrue);
        expect(tester.getSize(find.byType(IconPicker)).height, greaterThan(60));

        await tester.enterText(find.byType(TextField), 'rocket');
        await tester.pump(const Duration(milliseconds: 200));
        await tester.pumpAndSettle();
        await _tabTo(tester, vividIconOption('rocket'));
        final iconData =
            tester.getSemantics(vividIconOption('rocket')).getSemanticsData();
        expect(iconData.label, 'rocket');
        expect(iconData.hasFlag(ui.SemanticsFlag.isButton), isTrue);
        expect(iconData.hasFlag(ui.SemanticsFlag.isFocused), isTrue);
        expect(iconData.hasAction(ui.SemanticsAction.tap), isTrue);
        final button = tester.widget<TextButton>(vividIconOption('rocket'));
        expect(
          button.style!.side!.resolve({WidgetState.focused})!.color,
          vividIconTestTheme(appearance).colorScheme.primary,
        );
        final glyph = find.descendant(
          of: vividIconOption('rocket'),
          matching: find.byType(FlowySvg),
        );
        expect(
          MediaQuery.textScalerOf(tester.element(glyph)).scale(24),
          24,
          reason: 'Illustrations must not paint over neighboring grid cells',
        );
        expect(
          MediaQuery.textScalerOf(
            tester.element(vividIconStyleButton('Vivid')),
          ).scale(12),
          24,
          reason: 'Only illustration sizing is fixed; labels still scale',
        );
        await tester.sendKeyEvent(LogicalKeyboardKey.space);
        await tester.pumpAndSettle();
        expect(results, hasLength(1));
        final saved = IconsData.fromJson(jsonDecode(results.single.emoji));
        expect(saved.iconName, 'rocket');
        expect(saved.color, isNull);
        expect(find.byType(IconColorPicker), findsNothing);
        expect(tester.takeException(), isNull);
        await disposeVividIconPicker(tester);
      } finally {
        semantics.dispose();
      }
    });

    testWidgets(
        '$appearance: Vivid hover uses the surrounding theme without '
        'a card background', (tester) async {
      await tester
          .pumpWidget(vividIconTestApp(appearance, vividIconTestPicker()));
      await tester.pumpAndSettle();
      await tester.tap(vividIconStyleButton('Vivid'));
      await tester.pumpAndSettle();
      final home = vividIconOption('home');
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: const Offset(1, 1));
      await mouse.moveTo(tester.getCenter(home));
      await tester.pump(const Duration(milliseconds: 150));
      final button = tester.widget<TextButton>(home);
      expect(button.style!.backgroundColor!.resolve({}), Colors.transparent);
      expect(
        button.style!.overlayColor!.resolve({WidgetState.hovered}),
        appearance == 'paper'
            ? PaperTheme.hoverOverlay
            : vividIconTestTheme(appearance)
                .colorScheme
                .primary
                .withValues(alpha: 0.08),
      );
      expect(tester.takeException(), isNull);
      await mouse.removePointer();
      await disposeVividIconPicker(tester);
    });
  }

  testWidgets(
      'legacy Color still selects its real untinted artwork and '
      'line defaults still offer the color picker', (tester) async {
    final colorPack = iconPackForGroup('color_travel_places');
    await tester.runAsync(() => loadIconPack(colorPack));
    SelectedEmojiIconResult? result;
    await tester.pumpWidget(
      vividIconTestApp(
        'paper',
        vividIconTestPicker(
          onSelected: (selection) => result = selection,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(vividIconStyleButton('Color'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), 'full-moon');
    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpAndSettle();
    final moonKey = find.byKey(
      const ValueKey('picker-icon-color_travel_places/full-moon'),
    );
    final svg = tester.widget<FlowySvg>(
      find.descendant(of: moonKey, matching: find.byType(FlowySvg)),
    );
    expect(svg.blendMode, isNull);
    expect(svg.color, isNull);
    expect(
      svg.svgString,
      findLoadedIcon('color_travel_places', 'full-moon')!.content,
    );
    await tester
        .tap(find.descendant(of: moonKey, matching: find.byType(TextButton)));
    await tester.pumpAndSettle();
    expect(
      IconsData.fromJson(jsonDecode(result!.emoji)).groupName,
      'color_travel_places',
    );
    expect(find.byType(IconColorPicker), findsNothing);

    await tester.tap(find.text('Default icons'));
    await tester.pumpAndSettle();
    final book = find.byWidgetPredicate(
      (widget) =>
          widget is FlowySvg &&
          widget.svgString ==
              findLoadedIcon('appflowy_default_collections', 'book')!.content,
    );
    await tester
        .tap(find.ancestor(of: book, matching: find.byType(FlowyButton)).first);
    await tester.pumpAndSettle();
    expect(find.byType(IconColorPicker), findsOneWidget);
    final colorTargets = find.descendant(
      of: find.byType(IconColorPicker),
      matching: find.byWidgetPredicate(
        (widget) => widget is GestureDetector && widget.onTap != null,
      ),
    );
    await tester.tap(colorTargets.first);
    await tester.pumpAndSettle();
    final lineSelection = IconsData.fromJson(jsonDecode(result!.emoji));
    expect(lineSelection.groupName, 'appflowy_default_collections');
    expect(lineSelection.iconName, 'book');
    expect(lineSelection.color, isNotNull);
    expect(find.byType(IconColorPicker), findsNothing);
    expect(tester.takeException(), isNull);
    await disposeVividIconPicker(tester);
  });

  testWidgets(
      'persisted mixed recents retain Vivid identity and palette '
      'after filtering and reordering', (tester) async {
    final storage = _MemoryKeyValue();
    getIt.pushNewScope();
    getIt.registerSingleton<KeyValueStorage>(storage);
    RecentIcons.enable = true;
    try {
      RecentIcons.clear();
      final vivid = findLoadedIcon(vividIconTestGroup, 'coffee')!;
      await RecentIcons.putIcon(icons.RecentIcon(vivid, vividIconTestGroup));
      final line = findLoadedIcon('appflowy_default_collections', 'book')!;
      await RecentIcons.putIcon(
        icons.RecentIcon(line, 'appflowy_default_collections'),
      );
      expect(storage.values[KVKeys.recentIcons], contains(vividIconTestGroup));
      await tester.pumpWidget(
        vividIconTestApp('paper', vividIconTestPicker()),
      );
      await tester.pumpAndSettle();
      final recent =
          tester.widget<IconPicker>(find.byType(IconPicker)).iconGroups.first;
      expect(recent.name, 'Recent');
      expect(recent.icons.map((icon) => icon.name), ['book', 'coffee']);
      await tester.enterText(find.byType(TextField), 'coffee mug');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      // Coffee was index 1 before filtering; it must not inherit book's group.
      expect(vividIconOption('coffee'), findsOneWidget);
      final svg = tester.widget<FlowySvg>(
        find.descendant(
          of: vividIconOption('coffee'),
          matching: find.byType(FlowySvg),
        ),
      );
      expect(svg.blendMode, isNull);
      await tester.tap(vividIconOption('coffee'));
      await tester.pumpAndSettle();
      expect(find.byType(IconColorPicker), findsNothing);
      final restored = (await RecentIcons.getIcons()).first;
      expect(restored.groupName, vividIconTestGroup);
      expect(restored.name, 'coffee');
      expect(restored.content, vivid.content);
      await disposeVividIconPicker(tester);
      await tester.pumpWidget(vividIconTestApp('paper', vividIconTestPicker()));
      await tester.pumpAndSettle();
      expect(vividIconOption('coffee').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await disposeVividIconPicker(tester);
    } finally {
      RecentIcons.clear();
      RecentIcons.enable = false;
      await getIt.popScope();
    }
  });

  testWidgets('Remove still resets an icon from the Vivid style',
      (tester) async {
    SelectedEmojiIconResult? result;
    await tester.pumpWidget(
      vividIconTestApp(
        'light',
        vividIconTestPicker(
          onSelected: (selection) => result = selection,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(vividIconStyleButton('Vivid'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(result!.data.isEmpty, isTrue);
    expect(result!.keepOpen, isFalse);
    expect(tester.takeException(), isNull);
    await disposeVividIconPicker(tester);
  });
}

Future<Uint8List> _pixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      expect(image.width, 32);
      expect(image.height, 32);
      final rgba = await image.toByteData();
      return rgba!.buffer.asUint8List(rgba.offsetInBytes, rgba.lengthInBytes);
    } finally {
      image.dispose();
    }
  });
  return bytes!;
}

void _expectIllustratedPixels(Uint8List bytes, {required String reason}) {
  expect(bytes, hasLength(32 * 32 * 4), reason: reason);
  for (final pixel in [0, 31, 31 * 32, 32 * 32 - 1]) {
    expect(bytes[pixel * 4 + 3], 0, reason: '$reason transparent corner');
  }
  final hues = <int>{};
  final colors = <int>{};
  var colorfulPixels = 0;
  for (var offset = 0; offset < bytes.length; offset += 4) {
    if (bytes[offset + 3] < 240) continue;
    final red = bytes[offset];
    final green = bytes[offset + 1];
    final blue = bytes[offset + 2];
    final hsv = HSVColor.fromColor(Color.fromARGB(255, red, green, blue));
    if (hsv.saturation < 0.25 || hsv.value < 0.3) continue;
    colorfulPixels++;
    colors.add((red << 16) | (green << 8) | blue);
    hues.add((hsv.hue / 30).floor());
  }
  expect(
    colorfulPixels,
    greaterThan(80),
    reason: '$reason nonempty illustration',
  );
  expect(
    hues.length,
    greaterThanOrEqualTo(2),
    reason: '$reason not monochrome',
  );
  expect(
    colors.length,
    greaterThan(24),
    reason: '$reason rendered gradient shades',
  );
}

Future<void> _tabTo(WidgetTester tester, Finder target) async {
  for (var attempt = 0; attempt < 40; attempt++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.pump(const Duration(milliseconds: 100));
    final targetElement = target.evaluate().single;
    var found = false;
    FocusManager.instance.primaryFocus?.context
        ?.visitAncestorElements((element) {
      if (identical(element, targetElement)) {
        found = true;
        return false;
      }
      return true;
    });
    if (found) return;
  }
  fail('Native Tab traversal did not reach $target');
}

class _MemoryKeyValue implements KeyValueStorage {
  final values = <String, String>{};

  @override
  Future<void> set(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<String?> get(String key) async => values[key];
  @override
  Future<T?> getWithFormat<T>(String key, T Function(String) formatter) async {
    final value = values[key];
    return value == null ? null : formatter(value);
  }

  @override
  Future<void> remove(String key) async {
    values.remove(key);
  }

  @override
  Future<void> clear() async {
    values.clear();
  }
}
