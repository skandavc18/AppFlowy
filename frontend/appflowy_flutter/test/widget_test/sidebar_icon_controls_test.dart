import 'dart:io';

import 'package:appflowy/plugins/base/emoji/emoji_picker.dart';
import 'package:appflowy/plugins/collection/collection_icon_button.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart'
    show IconsData;
import 'package:appflowy/shared/icon_emoji_picker/recent_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/tab.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy/workspace/application/settings/appearance/desktop_appearance.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar/footer/sidebar_footer_button.dart';
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

import 'vivid_icon_test_support.dart' show settleVividIconPictures;

void main() {
  final loadedFontFamilies = <String>{};
  setUpAll(() async {
    RecentIcons.enable = false;
    SharedPreferences.setMockInitialValues({});
    EasyLocalization.logger.enableLevels = [];
    await EasyLocalization.ensureInitialized();
    kCachedEmojiData = await EmojiData.builtIn();
    await loadIconPack(kDefaultIconPack);
    // Keep the actual selected theme. Supply bundled metrics for both shared
    // workspace typography and platform sidebar text, without fetching fonts.
    final font =
        rootBundle.load('assets/google_fonts/DM_Sans/DMSans-Variable.ttf');
    for (final family in {
      SidebarTypography.fontFamilyForPlatform(TargetPlatform.windows),
      _theme('light').textTheme.bodyMedium!.fontFamily!,
    }) {
      await (FontLoader(family)..addFont(font)).load();
      loadedFontFamilies.add(family);
    }
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
    expect(source, contains('final current = _currentView;'));
    expect(
      source,
      matches(
        RegExp(
          r"builder: \(_, scale\) => CollectionIconButton\(\s+"
          r"key: const ValueKey\('collection-header-icon'\),\s+"
          r'view: current,\s+'
          r'iconSize: CollectionMetrics\.pageIconSize \* scale,',
        ),
      ),
    );
    expect(
      source,
      contains('onViewChanged: (updated) => controller.updateView('),
    );
    expect(source, contains('..mergeFromMessage(_currentView)'));
    expect(source, contains('..icon = updated.icon'));
  });

  for (final appearance in ['light', 'dark', 'paper']) {
    for (final style in DefaultIconStyle.values) {
      final vivid = style == DefaultIconStyle.vivid;
      final preference = vivid ? 'unset Vivid' : 'saved Monochrome';
      testWidgets(
          '$appearance/$preference defaults render without a loaded picker pack',
          (tester) async {
        final styles = ValueNotifier(DefaultIconStyle.fromId(style.name));
        addTearDown(styles.dispose);
        const additionalSources = [
          Icons.toc_rounded,
          Icons.queue_music_rounded,
          Icons.apps_rounded,
          Icons.reorder_rounded,
        ];
        final sourceCount =
            SidebarIcon.values.length + additionalSources.length;
        resetIconPacksForTesting();
        final icons = Wrap(
          children: [
            for (final icon in SidebarIcon.values) SidebarGlyph(icon),
            for (final icon in additionalSources) WorkspaceGlyph(icon),
          ],
        );
        await tester.pumpWidget(
          _app(
            appearance,
            // No scope for Vivid: exercise the actual unset device default.
            vivid ? icons : DefaultIconStyleScope(styles: styles, child: icons),
          ),
        );
        expect(isIconPackLoaded(sidebarIconPack), isFalse);
        final glyphs = find.byType(WorkspaceGlyph);
        expect(sourceCount, 53);
        expect(glyphs, findsNWidgets(sourceCount));
        expect(find.byType(SvgPicture), findsNWidgets(sourceCount));
        expect(find.byType(FlowySvg), findsNothing);
        expect(
          DefaultIconStyleScope.of(tester.element(glyphs.first)).value,
          style,
        );
        await settleVividIconPictures(tester);
        expect(
          tester.widgetList<WorkspaceGlyph>(glyphs).map((glyph) => glyph.name),
          [
            for (final icon in SidebarIcon.values) icon.name,
            for (final icon in additionalSources)
              WorkspaceGlyphs.nameForIcon(icon),
          ],
        );
        for (final element in glyphs.evaluate()) {
          final glyph = element.widget as WorkspaceGlyph;
          expect(glyph.name, isNot('unknown'));
          expect(glyph.style, isNull);
          final picture = tester.widget<SvgPicture>(
            find.descendant(
              of: find.byWidget(glyph),
              matching: find.byType(SvgPicture),
            ),
          );
          final artwork = vivid
              ? vividIconSvg(WorkspaceGlyphs.vividNameFor(glyph.name)!)!
              : defaultIconSvg(glyph.name)!;
          final loader = picture.bytesLoader as SvgStringLoader;
          expect(
            loader,
            SvgStringLoader(
              artwork,
              theme: loader.theme,
              colorMapper: loader.colorMapper,
            ),
            reason: glyph.name,
          );
          expect(
            picture.colorFilter,
            vivid
                ? isNull
                : ColorFilter.mode(
                    SidebarPalette.of(element).icon,
                    BlendMode.srcIn,
                  ),
          );
          expect(tester.getSize(find.byWidget(glyph)), const Size.square(18));
        }
        expect(iconPacksVersion.value, 0);
        expect(
          kIconPacks
              .where((pack) => pack.asset.isNotEmpty)
              .where(isIconPackLoaded),
          isEmpty,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
        await tester.runAsync(() => loadIconPack(kDefaultIconPack));
      });
    }

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
        tester.widget<WorkspaceGlyph>(find.byType(WorkspaceGlyph)).name,
        SidebarIcon.album.name,
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
          tester.widget<WorkspaceGlyph>(find.byType(WorkspaceGlyph)).name,
          sidebarCollectionIcon(kind).name,
        );
        final updated = ViewPB()
          ..mergeFromMessage(view)
          ..icon = EmojiIconData.emoji('📚').toViewIcon();
        tester
            .widget<ViewIconPicker>(find.byType(ViewIconPicker))
            .onViewChanged!(updated);
        await tester.pumpAndSettle();
        expect(find.byType(WorkspaceGlyph), findsNothing);
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
          tester.widget<WorkspaceGlyph>(find.byType(WorkspaceGlyph)).name,
          sidebarCollectionIcon(kind).name,
        );
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance chosen library icons keep their artwork and color',
        (tester) async {
      for (final pack in [
        kAppFlowyDefaultIconPack,
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
        expect(find.byType(WorkspaceGlyph), findsNothing);
        expect(
          tester.widget<SidebarRow>(find.byType(SidebarRow)).dimIcon,
          isFalse,
        );
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
    expect(find.byType(WorkspaceGlyph), findsOneWidget);
    expect(
      tester.widget<WorkspaceGlyph>(find.byType(WorkspaceGlyph)).name,
      SidebarIcon.book.name,
    );
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

  testWidgets('Monochrome sidebar visual reference in light dark and paper',
      (tester) async {
    // This fixture documents the outline style, not the unset device default.
    final styles = ValueNotifier(DefaultIconStyle.monochrome);
    addTearDown(styles.dispose);
    tester.view.physicalSize = const Size(900, 670);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(
        'light',
        DefaultIconStyleScope(
          styles: styles,
          child: RepaintBoundary(
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
      ),
    );
    await settleVividIconPictures(tester);
    expect(tester.takeException(), isNull);
    for (final appearance in ['light', 'dark', 'paper']) {
      final preview = find.byWidgetPredicate(
        (widget) =>
            widget is _SidebarPreview && widget.appearance == appearance,
      );
      final selectedFamily =
          Theme.of(tester.element(preview)).textTheme.bodyMedium!.fontFamily;
      expect(
        loadedFontFamilies,
        contains(selectedFamily),
        reason: 'The selected theme font must have bundled fixture metrics.',
      );
      final bounds = tester.getRect(preview);
      expect(bounds.size, const Size(300, 670));
      final utilities = find.descendant(
        of: preview,
        matching: find.byKey(const ValueKey('sidebar-preview-utilities')),
      );
      expect(
        find.descendant(of: utilities, matching: find.byType(SidebarNavItem)),
        findsNothing,
      );
      expect(
        tester
            .widgetList<SidebarIconButton>(
              find.descendant(
                of: utilities,
                matching: find.byType(SidebarIconButton),
              ),
            )
            .map((button) => button.icon),
        [SidebarIcon.templates, SidebarIcon.extensions, SidebarIcon.trash],
      );
      expect(
        find
            .descendant(of: utilities, matching: find.byType(IconButton))
            .hitTestable(),
        findsNWidgets(3),
      );
      final newPage = find.descendant(
        of: preview,
        matching: find.widgetWithText(SidebarNavItem, 'New page'),
      );
      expect(newPage, findsOneWidget);
      expect(
        tester.getRect(newPage).top,
        greaterThanOrEqualTo(tester.getRect(utilities).bottom),
      );
      for (final element in find
          .descendant(
            of: preview,
            matching: find.byWidgetPredicate(
              (widget) => widget is SidebarRow || widget is IconButton,
            ),
          )
          .evaluate()) {
        final control = tester.getRect(find.byWidget(element.widget));
        expect(control.isEmpty, isFalse);
        expect(
          control.intersect(bounds),
          control,
          reason:
              'Rows and buttons must fit the unchanged viewport, unclipped.',
        );
      }
    }
    await expectLater(
      find.byKey(const ValueKey('sidebar-icon-preview')),
      matchesGoldenFile('goldens/sidebar_rounded_icons.png'),
    );
    await tester.pumpWidget(const SizedBox());
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
              padding: const EdgeInsets.all(SidebarMetrics.space2),
              child: Row(
                children: [
                  Expanded(
                    child: SidebarText.heading(
                      'Workspace',
                      color: palette.textPrimary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  SidebarSectionLabel(appearance.toUpperCase()),
                ],
              ),
            ),
            const SidebarNavItem(icon: SidebarIcon.search, label: 'Search'),
            const SidebarNavItem(icon: SidebarIcon.home, label: 'Home'),
            const SizedBox(height: 16),
            const Padding(
              padding: EdgeInsets.all(8),
              child: SidebarSectionLabel('Pages'),
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
            Wrap(
              key: const ValueKey('sidebar-preview-utilities'),
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: SidebarMetrics.space1,
              runSpacing: SidebarMetrics.space1,
              children: [
                for (final (icon, label) in const [
                  (SidebarIcon.templates, 'Templates'),
                  (SidebarIcon.extensions, 'Extensions'),
                  (SidebarIcon.trash, 'Trash'),
                ])
                  SidebarFooterButton(
                    compact: true,
                    icon: icon,
                    text: label,
                    onTap: () {},
                  ),
              ],
            ),
            const SizedBox(height: SidebarMetrics.space1),
            SidebarNavItem(
              icon: SidebarIcon.newPage,
              label: 'New page',
              onTap: () {},
            ),
          ],
        ),
      ),
    );
  }
}
