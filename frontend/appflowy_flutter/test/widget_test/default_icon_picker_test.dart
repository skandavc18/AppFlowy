import 'dart:convert';

import 'package:appflowy/plugins/base/emoji/emoji_picker.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/collection/collection_icon_button.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_color_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/space/space_icon_popup.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/protobuf.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_infra_ui/flowy_infra_ui.dart' show FlowyButton;
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_emoji_mart/flutter_emoji_mart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'test_asset_bundle.dart';

void main() {
  setUpAll(() async {
    RecentIcons.enable = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    kCachedEmojiData = await EmojiData.builtIn();
    await loadIconPack(kDefaultIconPack);
    final families = {
      SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
      for (final appearance in ['light', 'dark', 'paper'])
        _theme(appearance).textTheme.bodyMedium?.fontFamily,
    }.whereType<String>();
    for (final family in families) {
      await (FontLoader(family)
            ..addFont(
              rootBundle
                  .load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
            ))
          .load();
    }
  });

  tearDownAll(() => RecentIcons.enable = true);

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance picker offers defaults beside emoji and library',
        (tester) async {
      SelectedEmojiIconResult? result;
      await tester.pumpWidget(
        _app(
          appearance,
          _picker(onSelected: (value) => result = value),
        ),
      );
      await tester.pumpAndSettle();
      final tabs = tester.widget<PickerTab>(find.byType(PickerTab));
      expect(tabs.tabs, [
        PickerTabType.emoji,
        PickerTabType.defaultIcons,
        PickerTabType.icon,
        PickerTabType.custom,
      ]);
      await tester.tap(find.text('Default icons'));
      await tester.pumpAndSettle();
      expect(
        tester.widget<FlowyIconPicker>(find.byType(FlowyIconPicker)).fixedPack,
        kAppFlowyDefaultIconPack,
      );
      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(_glyph('book'), findsOneWidget);
      expect(_glyph('repository'), findsOneWidget);
      expect(_glyph('album'), findsOneWidget);
      // No library style selector steals the small popup's vertical space.
      expect(find.text('Bold'), findsNothing);
      expect(find.text('Color'), findsNothing);
      await tester.tap(_glyphButton('book'));
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      expect(result!.keepOpen, isFalse);
      expect(result!.data.type, FlowyIconType.icon);
      final saved = IconsData.fromJson(jsonDecode(result!.emoji));
      expect(saved.groupName, 'appflowy_default_collections');
      expect(saved.iconName, 'book');
      expect(saved.color, isNull);
      expect(tester.takeException(), isNull);
      await _disposePicker(tester);
    });

    testWidgets('$appearance default search and color selection work',
        (tester) async {
      SelectedEmojiIconResult? result;
      await tester.pumpWidget(
        _app(
          appearance,
          _picker(
            initialType: PickerTabType.defaultIcons,
            colors: true,
            onSelected: (value) => result = value,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'git');
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pumpAndSettle();
      expect(_glyph('repository'), findsOneWidget);
      expect(_glyph('book'), findsNothing);
      await tester.tap(_glyphButton('repository'));
      await tester.pumpAndSettle();
      expect(find.byType(IconColorPicker), findsOneWidget);
      expect(result, isNull);
      // Exercise a real color target, not the callback in isolation.
      final colorTargets = find.descendant(
        of: find.byType(IconColorPicker),
        matching: find.byWidgetPredicate(
          (widget) => widget is GestureDetector && widget.onTap != null,
        ),
      );
      await tester.tap(colorTargets.first);
      await tester.pumpAndSettle();
      expect(result, isNotNull);
      final saved = IconsData.fromJson(jsonDecode(result!.emoji));
      expect(saved.groupName, 'appflowy_default_collections');
      expect(saved.iconName, 'repository');
      expect(saved.color, builtInSpaceColors.first);
      expect(result!.keepOpen, isFalse);
      expect(find.byType(IconColorPicker), findsNothing);
      expect(tester.takeException(), isNull);
      await _disposePicker(tester);
    });

    testWidgets('$appearance saved defaults render before any pack is loaded',
        (tester) async {
      // Resolve localization first, then verify icons on their first frame.
      await tester.pumpWidget(_app(appearance, const SizedBox()));
      await tester.pumpAndSettle();
      resetIconPacksForTesting();
      final data = <IconsData>[
        for (final group in appFlowyDefaultIconGroups)
          for (final icon in group.icons)
            IconsData(group.name, icon.name, '4283665274'),
      ];
      for (final size in [18.0, 54.0]) {
        await tester.pumpWidget(
          _app(
            appearance,
            Wrap(
              children: [
                for (final icon in data)
                  IconWidget(size: size, iconsData: icon),
              ],
            ),
          ),
        );
        expect(isIconPackLoaded(kDefaultIconPack), isFalse);
        expect(find.byType(FlowySvg), findsNWidgets(data.length));
        for (final svg in tester.widgetList<FlowySvg>(find.byType(FlowySvg))) {
          expect(svg.color, const Color(0xFF538B7A));
          expect(svg.blendMode, BlendMode.srcIn);
          expect(tester.getSize(find.byWidget(svg)), Size.square(size));
        }
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }
      await _disposePicker(tester);
      await tester.runAsync(() => loadIconPack(kDefaultIconPack));
    });

    testWidgets('$appearance collection reopens saved defaults on their tab',
        (tester) async {
      await tester.pumpWidget(_app(appearance, const SizedBox()));
      await tester.pumpAndSettle();
      final chosen = EmojiIconData.icon(
        IconsData('appflowy_default_collections', 'repository', '4283665274'),
      );
      final original = ViewPB(
        id: 'default-icon-test',
        name: 'Book',
        layout: ViewLayoutPB.Document,
        extra: CollectionMetadata.newExtra(CollectionKind.book),
        icon: chosen.toViewIcon(),
      );
      final restored = ViewPB.fromBuffer(original.writeToBuffer());
      resetIconPacksForTesting();
      await tester.pumpWidget(
        _app(
          appearance,
          CollectionIconButton(view: restored, onViewChanged: (_) {}),
        ),
      );
      expect(_glyph('repository'), findsOneWidget);
      expect(
        tester.widget<FlowySvg>(_glyph('repository')).color,
        const Color(0xFF538B7A),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(CollectionIconButton));
      await tester.pumpAndSettle();
      final tabs = tester.widget<PickerTab>(find.byType(PickerTab));
      expect(tabs.tabs[tabs.controller.index], PickerTabType.defaultIcons);
      expect(
        tester.widget<IconPicker>(find.byType(IconPicker)).pack,
        kAppFlowyDefaultIconPack,
      );
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(790, 590));
      await tester.pumpAndSettle();
      await _disposePicker(tester);
      await tester.runAsync(() => loadIconPack(kDefaultIconPack));
    });
  }

  testWidgets('all four tabs fit the normal 360px popup', (tester) async {
    await tester.pumpWidget(_app('paper', _picker()));
    await tester.pumpAndSettle();
    final bar = tester.getRect(find.byType(TabBar));
    for (final label in ['Emojis', 'Default icons', 'Icons', 'Upload']) {
      final tab = find.text(label);
      expect(tab.hitTestable(), findsOneWidget);
      final rect = tester.getRect(tab);
      expect(rect.left, greaterThanOrEqualTo(bar.left));
      expect(rect.right, lessThanOrEqualTo(bar.right));
    }
    expect(tester.takeException(), isNull);
    await _disposePicker(tester);
  });

  testWidgets('defaults remain reachable in narrow and text-scaled pickers',
      (tester) async {
    for (final scale in [1.0, 1.5]) {
      await tester.pumpWidget(
        _app(
          'paper',
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(scale)),
            child: _picker(width: 320),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.text('Default icons'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Default icons'));
      await tester.pumpAndSettle();
      expect(_glyphButton('book').hitTestable(), findsOneWidget);
      expect(tester.takeException(), isNull);
      await _disposePicker(tester);
    }
  });

  testWidgets('removing an icon from the defaults tab restores the fallback',
      (tester) async {
    SelectedEmojiIconResult? result;
    await tester.pumpWidget(
      _app(
        'paper',
        _picker(
          initialType: PickerTabType.defaultIcons,
          onSelected: (value) => result = value,
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(result!.data.isEmpty, isTrue);
    expect(result!.keepOpen, isFalse);
    expect(tester.takeException(), isNull);
    await _disposePicker(tester);
  });

  testWidgets('default icons popup visual reference in all appearances',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 420);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        'light',
        RepaintBoundary(
          key: const ValueKey('default-icons-preview'),
          child: Row(
            children: [
              for (final appearance in ['light', 'dark', 'paper'])
                Expanded(
                  child: Theme(
                    data: _theme(appearance),
                    child: Builder(
                      builder: (context) => Material(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: Center(
                          child:
                              _picker(initialType: PickerTabType.defaultIcons),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await expectLater(
      find.byKey(const ValueKey('default-icons-preview')),
      matchesGoldenFile('goldens/default_icon_picker.png'),
    );
    await _disposePicker(tester);
  });
}

Future<void> _disposePicker(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  // The emoji library batches visibility-exit notifications for 500ms, even
  // after unmounting. Deliver them on the fake clock before test teardown.
  await tester.pump(const Duration(seconds: 1));
  await tester.pumpAndSettle();
}

Finder _glyph(String name) {
  final svg = findLoadedIcon('appflowy_default_collections', name)!.content;
  return find.byWidgetPredicate(
    (widget) => widget is FlowySvg && widget.svgString == svg,
  );
}

Finder _glyphButton(String name) =>
    find.ancestor(of: _glyph(name), matching: find.byType(FlowyButton)).first;

Widget _picker({
  PickerTabType initialType = PickerTabType.emoji,
  ValueChanged<SelectedEmojiIconResult>? onSelected,
  bool colors = false,
  double width = 360,
}) =>
    SizedBox(
      width: width,
      height: 380,
      child: FlowyIconEmojiPicker(
        tabs: const [
          PickerTabType.emoji,
          PickerTabType.icon,
          PickerTabType.custom,
        ],
        initialType: initialType,
        enableBackgroundColorSelection: colors,
        onSelectedEmoji: onSelected,
      ),
    );

ThemeData _theme(String appearance) => DesktopAppearance()
    .getThemeData(
      appearance == 'paper'
          ? AppTheme.builtins
              .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
          : AppTheme.fallback,
      appearance == 'dark' ? Brightness.dark : Brightness.light,
      SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
      builtInCodeFontFamily,
    )
    .copyWith(platform: TargetPlatform.windows);

Widget _app(String appearance, Widget child) => EasyLocalization(
      supportedLocales: const [Locale('en', 'US')],
      path: 'assets/translations',
      fallbackLocale: const Locale('en', 'US'),
      useFallbackTranslations: true,
      saveLocale: false,
      assetLoader: const TestBundleAssetLoader(),
      child: Builder(
        builder: (context) => MaterialApp(
          locale: const Locale('en', 'US'),
          localizationsDelegates: context.localizationDelegates,
          theme: _theme(appearance),
          themeAnimationDuration: Duration.zero,
          home: Scaffold(body: Center(child: child)),
        ),
      ),
    );
