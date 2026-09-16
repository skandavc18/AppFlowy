import 'dart:io';

import 'package:appflowy/plugins/base/emoji/emoji_picker.dart';
import 'package:appflowy/plugins/collection/collection_icon_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart'
    show IconsData;
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_icon_artwork.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flowy_infra/theme.dart';
import 'package:flowy_svg/flowy_svg.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_emoji_mart/flutter_emoji_mart.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUpAll(() async {
    RecentIcons.enable = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    kCachedEmojiData = await EmojiData.builtIn();
    await loadIconPack(kDefaultIconPack);
    // Sidebar typography uses the platform family explicitly. Supply fixed,
    // bundled metrics under that family so goldens do not depend on OS fonts.
    await (FontLoader(
      SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
    )..addFont(
            rootBundle.load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf'),
          ))
        .load();
  });

  tearDownAll(() => RecentIcons.enable = true);

  test('every default has compact round-stroke artwork', () {
    for (final icon in SidebarIcon.values) {
      final svg = roundedSidebarIconSvg(icon.name);
      expect(svg, isNotNull, reason: icon.name);
      expect(svg, contains('viewBox="0 0 24 24"'));
      expect(svg, contains('stroke-width="1.75"'));
      expect(svg, contains('stroke-linecap="round"'));
      expect(svg, contains('stroke-linejoin="round"'));
      expect(svg, isNot(contains('<text')));
    }
    expect(roundedSidebarIconSvg('not-a-sidebar-symbol'), isNull);
  });

  test('all collection kinds share their sidebar and header fallback', () {
    for (final kind in CollectionKind.values) {
      expect(sidebarViewIcon(_collection(kind)), sidebarCollectionIcon(kind));
    }
  });

  test('collection page reads the live icon and adopts successful edits', () {
    final source = File(
      'lib/plugins/collection/collection_page.dart',
    ).readAsStringSync();
    expect(source, contains('child: CollectionIconButton('));
    expect(source, contains('view: _currentView,'));
    expect(
      source,
      contains('onViewChanged: (updated) => controller.updateView('),
    );
    expect(source, contains('..mergeFromMessage(_currentView)'));
    expect(source, contains('..icon = updated.icon'));
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    testWidgets('$appearance defaults render without a loaded picker pack',
        (tester) async {
      resetIconPacksForTesting();
      await tester.pumpWidget(
        _app(
          appearance,
          Wrap(
            children: [
              for (final icon in SidebarIcon.values) SidebarGlyph(icon),
            ],
          ),
        ),
      );
      expect(isIconPackLoaded(sidebarIconPack), isFalse);
      expect(find.byType(FlowySvg), findsNWidgets(SidebarIcon.values.length));
      await tester.pumpAndSettle();
      for (final element in find.byType(FlowySvg).evaluate()) {
        final svg = element.widget as FlowySvg;
        expect(svg.color, SidebarPalette.of(element).icon);
        expect(tester.getSize(find.byWidget(svg)), const Size.square(18));
      }
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() => loadIconPack(kDefaultIconPack));
    });

    for (final kind in [
      CollectionKind.book,
      CollectionKind.album,
      CollectionKind.repository,
    ]) {
      testWidgets('$appearance ${kind.name} icon remains clickable on hover',
          (tester) async {
        var opened = 0;
        var expanded = false;
        var view = _collection(kind);
        late StateSetter updateRow;
        final icon = find.byKey(ValueKey('sidebar-icon-${view.id}'));
        final disclosure = find.byKey(const ValueKey('test-disclosure'));
        final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
        await tester.pumpWidget(
          _app(
            appearance,
            Center(
              child: SizedBox(
                width: 260,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    updateRow = setState;
                    return _viewRow(
                      view,
                      onOpen: () => opened++,
                      disclosure: SidebarDisclosure(
                        key: const ValueKey('test-disclosure'),
                        expanded: expanded,
                        onTap: () => setState(() => expanded = !expanded),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final before = tester.getRect(icon);
        final pickerState = tester.state(icon);
        await mouse.addPointer(location: const Offset(790, 590));
        await mouse.moveTo(before.center);
        await tester.pumpAndSettle();

        // This is the original failure: hover removed this picker entirely.
        expect(icon.hitTestable(), findsOneWidget);
        expect(tester.state(icon), same(pickerState));
        expect(tester.getRect(icon), before);
        expect(tester.getRect(disclosure).overlaps(before), isFalse);
        await tester.tap(icon);
        await tester.pumpAndSettle();
        expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);
        expect(opened, 0);
        expect(expanded, isFalse);

        // A backend notification can land while a random/keep-open selection
        // is still in the picker. Changing icon type must not unmount it.
        updateRow(() {
          view = ViewPB()
            ..mergeFromMessage(view)
            ..icon = EmojiIconData.emoji('📚').toViewIcon();
        });
        await tester.pumpAndSettle();
        expect(tester.state(icon), same(pickerState));
        expect(find.byType(FlowyIconEmojiPicker), findsOneWidget);

        await tester.tapAt(const Offset(790, 590));
        await tester.pumpAndSettle();
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);
        await mouse.moveTo(tester.getCenter(disclosure));
        await tester.pumpAndSettle();
        await tester.tap(disclosure);
        await tester.pumpAndSettle();
        expect(expanded, isTrue);
        expect(opened, 0);
        expect(find.byType(FlowyIconEmojiPicker), findsNothing);

        await tester.tap(find.text(view.name).first);
        await tester.pump(const Duration(milliseconds: 350));
        expect(opened, 1);
        expect(tester.takeException(), isNull);
        await mouse.removePointer();
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('$appearance collection header opens the full icon picker',
        (tester) async {
      final view = _collection(CollectionKind.album);
      await tester.pumpWidget(
        _app(
          appearance,
          Center(
            child: CollectionIconButton(view: view, onViewChanged: (_) {}),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<SidebarGlyph>(find.byType(SidebarGlyph)).icon,
        SidebarIcon.album,
      );
      await tester.tap(find.byType(CollectionIconButton));
      await tester.pumpAndSettle();
      final picker = tester.widget<FlowyIconEmojiPicker>(
        find.byType(FlowyIconEmojiPicker),
      );
      expect(picker.documentId, view.id);
      expect(picker.effectiveTabs, [
        PickerTabType.emoji,
        PickerTabType.defaultIcons,
        PickerTabType.icon,
        PickerTabType.custom,
      ]);
      expect(picker.onSelectedEmoji, isNotNull);
      expect(tester.takeException(), isNull);
      await tester.tapAt(const Offset(790, 590));
      await tester.pumpAndSettle();
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance header follows post-save icon changes and reset',
        (tester) async {
      for (final kind in CollectionKind.values) {
        var view = _collection(kind);
        await tester.pumpWidget(
          _app(
            appearance,
            Center(
              child: StatefulBuilder(
                key: ValueKey(kind),
                builder: (context, setState) => CollectionIconButton(
                  view: view,
                  onViewChanged: (updated) => setState(() => view = updated),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(
          tester.widget<SidebarGlyph>(find.byType(SidebarGlyph)).icon,
          sidebarCollectionIcon(kind),
        );
        final updated = ViewPB()
          ..mergeFromMessage(view)
          ..icon = EmojiIconData.emoji('📚').toViewIcon();
        tester
            .widget<ViewIconPicker>(find.byType(ViewIconPicker))
            .onViewChanged!(updated);
        await tester.pumpAndSettle();
        expect(find.byType(SidebarGlyph), findsNothing);
        expect(
          tester
              .widget<RawEmojiIconWidget>(find.byType(RawEmojiIconWidget))
              .emoji
              .emoji,
          '📚',
        );
        final reset = ViewPB()
          ..mergeFromMessage(view)
          ..icon = EmojiIconData.none().toViewIcon();
        tester
            .widget<ViewIconPicker>(find.byType(ViewIconPicker))
            .onViewChanged!(reset);
        await tester.pumpAndSettle();
        expect(find.byType(RawEmojiIconWidget), findsNothing);
        expect(
          tester.widget<SidebarGlyph>(find.byType(SidebarGlyph)).icon,
          sidebarCollectionIcon(kind),
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance chosen library icons keep their artwork and color',
        (tester) async {
      for (final pack in [
        sidebarIconPack,
        kIconPacks.firstWhere((pack) => pack.isColorful),
      ]) {
        final groups = (await tester.runAsync(() => loadIconPack(pack)))!;
        final group = groups.first;
        final artwork = group.icons.first;
        final saved = EmojiIconData.icon(
          IconsData(group.name, artwork.name, '4283665274'),
        );
        final view = _collection(CollectionKind.album)
          ..icon = saved.toViewIcon();
        await tester.pumpWidget(
          _app(
            appearance,
            Center(
              child: SizedBox(
                width: 260,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CollectionIconButton(view: view, onViewChanged: (_) {}),
                    _viewRow(
                      view,
                      onOpen: () {},
                      disclosure: const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(find.byType(SidebarGlyph), findsNothing);
        expect(tester.widget<SidebarRow>(find.byType(SidebarRow)).dimIcon,
            isFalse);
        expect(find.byType(FlowySvg), findsNWidgets(2));
        for (final svg in tester.widgetList<FlowySvg>(find.byType(FlowySvg))) {
          expect(svg.svgString, artwork.content);
          expect(svg.blendMode, pack.isColorful ? null : BlendMode.srcIn);
          if (!pack.isColorful) {
            expect(svg.color, const Color(0xFF538B7A));
          }
        }
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      }
    });
  }

  testWidgets('a locked collection does not offer an icon edit',
      (tester) async {
    final view = _collection(CollectionKind.book)..isLocked = true;
    await tester.pumpWidget(
      _app(
        'paper',
        Center(child: CollectionIconButton(view: view, onViewChanged: (_) {})),
      ),
    );
    expect(find.byType(SidebarGlyph), findsOneWidget);
    expect(find.byType(ViewIconPicker), findsNothing);
  });

  testWidgets('leaf and expandable row names keep the same alignment',
      (tester) async {
    await tester.pumpWidget(
      _app(
        'paper',
        SizedBox(
          width: 260,
          child: Column(
            children: [
              SidebarRow(
                reserveLeadingSpace: true,
                leading: SidebarDisclosure(expanded: false, onTap: () {}),
                icon: const SidebarGlyph(SidebarIcon.book),
                label: const Text('Expandable'),
              ),
              const SidebarRow(
                reserveLeadingSpace: true,
                icon: SidebarGlyph(SidebarIcon.document),
                label: Text('Leaf'),
              ),
            ],
          ),
        ),
      ),
    );
    expect(
      tester.getTopLeft(find.text('Expandable')).dx,
      tester.getTopLeft(find.text('Leaf')).dx,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('rounded sidebar visual reference in light dark and paper',
      (tester) async {
    tester.view.physicalSize = const Size(900, 670);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        'light',
        RepaintBoundary(
          key: const ValueKey('sidebar-icon-preview'),
          child: Row(
            children: [
              for (final appearance in ['light', 'dark', 'paper'])
                Expanded(
                  child: Theme(
                    data: _theme(appearance),
                    child: _SidebarPreview(appearance),
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
      find.byKey(const ValueKey('sidebar-icon-preview')),
      matchesGoldenFile('goldens/sidebar_rounded_icons.png'),
    );
  });
}

ViewPB _collection(CollectionKind kind) => ViewPB(
      id: 'test-${kind.name}',
      name: 'New ${kind.name}',
      layout: ViewLayoutPB.Document,
      extra: CollectionMetadata.newExtra(kind),
    );

Widget _viewRow(
  ViewPB view, {
  required VoidCallback onOpen,
  required Widget disclosure,
}) =>
    SingleInnerViewItem(
      view: view,
      parentView: null,
      isExpanded: false,
      level: 0,
      leftPadding: SidebarMetrics.indent,
      spaceType: FolderSpaceType.unknown,
      showActions: false,
      onSelected: (_, __) => onOpen(),
      isFeedback: false,
      height: SidebarMetrics.rowHeight,
      leftIconBuilder: (_, __) => disclosure,
      rightIconsBuilder: (_, __) => [],
      includeDefaultMoreAction: false,
      extendBuilder: null,
      disableSelectedStatus: null,
      shouldIgnoreView: null,
      isSelected: false,
    );

ThemeData _theme(String appearance) {
  final base = DesktopAppearance().getThemeData(
    appearance == 'paper'
        ? AppTheme.builtins
            .firstWhere((theme) => theme.themeName == BuiltInTheme.paper)
        : AppTheme.fallback,
    appearance == 'dark' ? Brightness.dark : Brightness.light,
    SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
    builtInCodeFontFamily,
  );
  return base.copyWith(platform: TargetPlatform.windows);
}

Widget _app(String appearance, Widget child) => MaterialApp(
      theme: _theme(appearance),
      themeAnimationDuration: Duration.zero,
      home: Scaffold(body: child),
    );

class _SidebarPreview extends StatelessWidget {
  const _SidebarPreview(this.appearance);

  final String appearance;

  @override
  Widget build(BuildContext context) {
    final palette = SidebarPalette.of(context);
    Widget row(
      String label,
      SidebarIcon icon, {
      bool collection = false,
      double indent = 0,
      bool selected = false,
    }) =>
        SidebarRow(
          reserveLeadingSpace: true,
          indent: indent,
          selected: selected,
          leading: collection
              ? SidebarDisclosure(expanded: true, onTap: () {})
              : null,
          icon: SidebarGlyph(icon),
          label: Text(
            label,
            style: SidebarTypography.textStyle(
              context,
              color: palette.textBody,
              role: SidebarTextRole.page,
            ),
          ),
        );
    return ColoredBox(
      color: palette.background,
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
              child: SidebarSectionLabel(appearance.toUpperCase()),
            ),
            const SidebarNavItem(icon: SidebarIcon.search, label: 'Search'),
            const SidebarNavItem(icon: SidebarIcon.newPage, label: 'New page'),
            const SidebarNavItem(icon: SidebarIcon.home, label: 'Home'),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.all(8),
              child: SidebarSectionLabel('Workspace'),
            ),
            row('Reading list', SidebarIcon.book, collection: true),
            row('Research.pdf', SidebarIcon.pdf, indent: 14),
            row('Notes', SidebarIcon.document, indent: 14),
            row('Photo library', SidebarIcon.album, collection: true),
            row('Landscape.jpg', SidebarIcon.image, indent: 14),
            row('Projects', SidebarIcon.folder, collection: true),
            row('README.md', SidebarIcon.document, indent: 14, selected: true),
            row('main.dart', SidebarIcon.code, indent: 14),
            row('Repository', SidebarIcon.repository, collection: true),
            row('Tasks', SidebarIcon.grid),
            row('Saved links', SidebarIcon.link),
            const Spacer(),
            const SidebarNavItem(
              icon: SidebarIcon.templates,
              label: 'Templates',
            ),
            const SidebarNavItem(
              icon: SidebarIcon.extensions,
              label: 'Extensions',
            ),
            const SidebarNavItem(icon: SidebarIcon.trash, label: 'Trash'),
          ],
        ),
      ),
    );
  }
}
