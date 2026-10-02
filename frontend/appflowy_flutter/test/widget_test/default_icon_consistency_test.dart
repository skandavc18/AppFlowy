import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:appflowy/generated/flowy_svgs.g.dart';
import 'package:appflowy/plugins/base/icon/icon_widget.dart';
import 'package:appflowy/plugins/dashboard/presentation/dashboard_templates.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/header/emoji_icon_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/desktop_selection_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items_builder.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/default_icons.dart';
import 'package:appflowy/shared/icon_emoji_picker/flowy_icon_emoji_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_pack.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon_picker.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icons.dart';
import 'package:appflowy/shared/workspace_chrome.dart';
import 'package:appflowy/shared/workspace_icons.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/settings/settings_dialog_bloc.dart';
import 'package:appflowy/workspace/application/settings/default_icon_style.dart';
import 'package:appflowy/workspace/application/sidebar/folder/folder_bloc.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_design.dart';
import 'package:appflowy/workspace/presentation/home/menu/sidebar_typography.dart';
import 'package:appflowy/workspace/presentation/home/menu/view/view_item.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu.dart';
import 'package:appflowy/workspace/presentation/settings/widgets/settings_menu_element.dart';
import 'package:appflowy/workspace/presentation/widgets/view_cover/view_decoration_actions.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/icon.pb.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart'
    hide AFRolePB;
import 'package:appflowy_backend/protobuf/flowy-user/protobuf.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'test_asset_bundle.dart';
import 'vivid_icon_test_support.dart' show settleVividIconPictures;
import 'workspace_overlay_test_app.dart' as overlays;

const _appearances = ['light', 'dark', 'paper'];
late _PreloadedTranslations _translations;

void main() {
  setUpAll(() async {
    await overlays.initializeWorkspaceOverlayTests();
    _translations = await _PreloadedTranslations.read();
  });
  setUp(() {
    resetIconPacksForTesting();
    WorkspaceGlyphs.clearUnknownMappings();
  });

  test('all mapped identities resolve to the same round-stroke family', () {
    for (final icon in WorkspaceGlyphs.mappedIcons) {
      final name = WorkspaceGlyphs.nameForIcon(icon);
      expect(name, isNotNull);
      expect(defaultIconSvg(name!), isNotNull, reason: name);
    }
    for (final stem in WorkspaceGlyphs.mappedSvgNames) {
      final data = FlowySvgData('assets/flowy_icons/16x/$stem.svg');
      final name = WorkspaceGlyphs.nameForSvg(data);
      expect(name, isNotNull, reason: stem);
      expect(defaultIconSvg(name!), isNotNull, reason: stem);
    }
    for (final name in defaultIconNames) {
      final svg = defaultIconSvg(name)!;
      expect(svg, contains('viewBox="0 0 24 24"'), reason: name);
      expect(svg, contains('fill="none"'), reason: name);
      expect(svg, contains('stroke-width="1.75"'), reason: name);
      expect(svg, contains('stroke-linecap="round"'), reason: name);
      expect(svg, contains('stroke-linejoin="round"'), reason: name);
      expect(svg, isNot(contains('<text')), reason: name);
      expect(svg, isNot(contains('<image')), reason: name);
    }
  });

  test('distinct actions are not collapsed onto one generic symbol', () {
    const icons = [
      Icons.settings_rounded,
      Icons.description_rounded,
      Icons.edit_note_rounded,
      Icons.history_rounded,
      Icons.lock_outline_rounded,
      Icons.backup_rounded,
      Icons.hub_rounded,
      Icons.extension_rounded,
      Icons.document_scanner_rounded,
      Icons.text_snippet_rounded,
      Icons.copy_rounded,
      Icons.content_cut_rounded,
      Icons.content_paste_rounded,
      Icons.delete_outline_rounded,
      Icons.format_bold_rounded,
      Icons.format_italic_rounded,
      Icons.format_underline_rounded,
      Icons.format_align_left_rounded,
      Icons.format_align_center_rounded,
      Icons.format_align_right_rounded,
      Icons.format_align_justify_rounded,
      Icons.check_box_rounded,
      Icons.check_box_outline_blank_rounded,
    ];
    final names = icons.map(WorkspaceGlyphs.nameForIcon).toList();
    expect(names, isNot(contains(null)));
    expect(names.toSet(), hasLength(icons.length));
    expect(
      names.map((name) => defaultIconSvg(name!)).toSet(),
      hasLength(icons.length),
    );
    expect(
      WorkspaceGlyphs.nameForIcon(Icons.document_scanner_rounded),
      'scan-document',
    );
    expect(
      WorkspaceGlyphs.nameForIcon(Icons.text_snippet_rounded),
      'file-doc',
      reason: 'A Word file is not the OCR action.',
    );
    expect(
      WorkspaceGlyphs.nameForSvg(
        const FlowySvgData('assets/flowy_icons/20x/toolbar_extract_text.svg'),
      ),
      'scan-document',
    );
  });

  test('generated SVG paths resolve, including spaces and hyphens', () {
    expect(
      WorkspaceGlyphs.nameForSvg(FlowySvgs.slash_menu_icon_code_block_s),
      'code',
    );
    expect(WorkspaceGlyphs.nameForSvg(FlowySvgs.three_dots_s), 'dots-three');
    const headings = [
      FlowySvgs.slash_menu_icon_h1_s,
      FlowySvgs.slash_menu_icon_h2_s,
      FlowySvgs.slash_menu_icon_h3_s,
      FlowySvgs.toggle_heading1_s,
      FlowySvgs.toggle_heading2_s,
      FlowySvgs.toggle_heading3_s,
    ];
    expect(headings.map(WorkspaceGlyphs.nameForSvg).toSet(), hasLength(6));
    for (final template in dashboardTemplates()) {
      expect(
        WorkspaceGlyphs.nameForIcon(template.icon),
        isNotNull,
        reason: template.id,
      );
    }
    for (final type in CollectionRegistry.types) {
      expect(
        WorkspaceGlyphs.nameForIcon(type.icon),
        isNotNull,
        reason: type.kind.name,
      );
    }
  });

  test('optical geometry separates artwork and stable slots', () {
    final sidebar = IconOpticalSize.resolve(
      role: IconOpticalRole.sidebar,
      baseSize: 18,
    );
    expect(sidebar.artworkSize, 22);
    expect(sidebar.slotSize, 24);
    expect(sidebar.padding, const EdgeInsets.all(1));
    final header = IconOpticalSize.resolve(
      role: IconOpticalRole.header,
      baseSize: 56,
    );
    expect(header.artworkSize, 64);
    expect(header.slotSize, 66);
    expect(header.padding, const EdgeInsets.all(1));
    final line = IconOpticalSize.resolve(
      role: IconOpticalRole.sidebar,
      baseSize: 18,
      colorful: false,
    );
    expect(line.artworkSize, 18);
    expect(line.slotSize, sidebar.slotSize);
    expect(line.padding, const EdgeInsets.all(3));
  });

  test('saved default catalogue and serialized colors remain compatible', () {
    final all = appFlowyDefaultIconGroups.expand((group) => group.icons);
    expect(all, hasLength(58));
    for (final group in appFlowyDefaultIconGroups) {
      for (final icon in group.icons) {
        final data = IconsData(group.name, icon.name, '4283665274');
        final saved = data.toEmojiIconData().toViewIcon();
        final decoded = ViewIconPB.fromBuffer(saved.writeToBuffer());
        final restored = IconsData.fromJson(jsonDecode(decoded.value));
        expect(restored.groupName, data.groupName);
        expect(restored.iconName, data.iconName);
        expect(restored.color, data.color);
        expect(restored.svgString, icon.content);
      }
    }
  });

  testWidgets('every compiled-in glyph decodes with an empty asset cache',
      (tester) async {
    svg.cache.clear();
    final bundle = _RecordingBundle();
    final names = defaultIconNames.toList();
    for (var start = 0; start < names.length; start += 40) {
      final group = names.skip(start).take(40).toList();
      await tester.pumpWidget(
        MaterialApp(
          home: DefaultAssetBundle(
            bundle: bundle,
            child: Center(
              child: SizedBox(
                width: 240,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  children: [
                    for (final name in group)
                      WorkspaceGlyph.named(name, key: ValueKey(name)),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
      expect(find.byType(SvgPicture), findsNWidgets(group.length));
      await settleVividIconPictures(tester);
      expect(tester.takeException(), isNull, reason: group.join(', '));
    }
    expect(bundle.requests, isEmpty);
    expect(iconPacksVersion.value, 0);
    expect(isIconPackLoaded(sidebarIconPack), isFalse);
    expect(WorkspaceGlyphs.unknownMappings, isEmpty);
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('an unmapped default keeps its source and preserves semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    try {
      const unknown = IconData(0xffff, fontFamily: 'FutureExtensionIcons');
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          child: const WorkspaceGlyph(unknown, semanticLabel: 'New command'),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        tester.widget<WorkspaceGlyph>(find.byType(WorkspaceGlyph)).name,
        'unknown',
      );
      expect(WorkspaceGlyphs.unknownMappings, {'FutureExtensionIcons/ffff'});
      expect(find.bySemanticsLabel('New command'), findsOneWidget);
      expect(find.byIcon(unknown), findsOneWidget);
      expect(find.byType(SvgPicture), findsNothing);
      expect(tester.takeException(), isNull);
    } finally {
      semantics.dispose();
    }
  });

  for (final appearance in _appearances) {
    for (final scale in [1.0, 2.0]) {
      testWidgets(
          '$appearance/$scale real settings share outline ink and weight',
          (tester) async {
        var selected = SettingsPage.account;
        late StateSetter choose;
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            textScale: scale,
            child: Center(
              child: SizedBox(
                width: 216,
                height: 520,
                child: StatefulBuilder(
                  builder: (context, setState) {
                    choose = setState;
                    return SettingsMenu(
                      currentPage: selected,
                      userProfile: UserProfilePB()
                        ..workspaceType = WorkspaceTypePB.ServerW,
                      currentUserRole: AFRolePB.Owner,
                      isBillingEnabled: true,
                      changeSelectedPage: (SettingsPage page) =>
                          setState(() => selected = page),
                    );
                  },
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        final entries = tester
            .widgetList<SettingsMenuElement>(find.byType(SettingsMenuElement))
            .toList();
        expect(entries.length, greaterThan(12));
        for (final entry in entries) {
          final row = find.byWidget(entry);
          final glyph =
              find.descendant(of: row, matching: find.byType(WorkspaceGlyph));
          expect(glyph, findsOneWidget);
          expect(tester.getSize(glyph), const Size.square(18));
          _expectWithin(tester.getRect(glyph), tester.getRect(row));
          final label = tester.widget<Text>(
            find.descendant(of: row, matching: find.text(entry.label)),
          );
          expect(label.style!.fontWeight, FontWeight.w500);
          expect(
            label.style!.fontVariations,
            const [ui.FontVariation.weight(500)],
          );
          expect(label.style!.color, workspaceGlyphInk(tester.element(row)));
          _expectGlyphInk(
            tester,
            glyph,
            workspaceGlyphInk(tester.element(row)),
          );
        }
        final selectedRow = find.byWidget(entries.first);
        final before = _picture(
          tester,
          find.descendant(
            of: selectedRow,
            matching: find.byType(WorkspaceGlyph),
          ),
        ).colorFilter;
        choose(() => selected = SettingsPage.workspace);
        await tester.pumpAndSettle();
        final account = find.byWidgetPredicate(
          (widget) =>
              widget is SettingsMenuElement &&
              widget.page == SettingsPage.account,
        );
        final accountGlyph =
            find.descendant(of: account, matching: find.byType(WorkspaceGlyph));
        expect(_picture(tester, accountGlyph).colorFilter, before);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(
          find.descendant(
            of: find.byType(SettingsMenu),
            matching: find.byType(Icon),
          ),
          findsNothing,
        );
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets('$appearance/$scale compact settings use the same real menu',
          (tester) async {
        SettingsPage? chosen;
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            textScale: scale,
            child: Center(
              child: SizedBox(
                width: 240,
                child: SettingsMenu(
                  compact: true,
                  currentPage: SettingsPage.account,
                  userProfile: UserProfilePB()
                    ..workspaceType = WorkspaceTypePB.ServerW,
                  currentUserRole: AFRolePB.Guest,
                  isBillingEnabled: false,
                  changeSelectedPage: (SettingsPage page) => chosen = page,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        await tester
            .tap(find.byKey(const ValueKey('settings-category-picker')));
        await tester.pumpAndSettle();
        final rows =
            tester.widgetList<AppMenuRow>(find.byType(AppMenuRow)).toList();
        expect(rows.length, greaterThan(12));
        for (final row in rows) {
          expect(row.iconWidget, isA<WorkspaceGlyph>());
          expect((row.iconWidget! as WorkspaceGlyph).name, isNot('unknown'));
        }
        final workspaceRow = find.byWidget(rows[1]);
        await tester.ensureVisible(workspaceRow);
        await tester.pumpAndSettle();
        await tester.tap(workspaceRow);
        await tester.pumpAndSettle();
        expect(chosen, SettingsPage.workspace);
        expect(find.byType(AppMenuSurface), findsNothing);
        expect(WorkspaceGlyphs.unknownMappings, isEmpty);
        expect(tester.takeException(), isNull);
        await tester.pumpWidget(const SizedBox());
      });

      testWidgets(
          '$appearance/$scale the real slash catalogue renders outlined rows',
          (tester) async {
        final editor = EditorState.blank();
        final items = slashMenuItemsBuilder(isLocalMode: true);
        expect(items.length, greaterThan(40));
        try {
          for (var start = 0; start < items.length; start += 4) {
            final chunk = items.skip(start).take(4).toList();
            await tester.pumpWidget(
              workspaceOverlayTestApp(
                appearance: appearance,
                textScale: scale,
                child: Center(
                  child: SizedBox(
                    width: 280,
                    child: AppFlowyDesktopSelectionMenuWidget(
                      key: ValueKey(start),
                      items: chunk,
                      editorState: editor,
                      menuService: _SelectionService(),
                      onExit: () {},
                      onSelectionUpdate: () {},
                      selectionMenuStyle: SelectionMenuStyle.light,
                      deleteSlashByDefault: false,
                    ),
                  ),
                ),
              ),
            );
            await tester.pumpAndSettle();
            final rows =
                tester.widgetList<AppMenuRow>(find.byType(AppMenuRow)).toList();
            expect(rows, hasLength(chunk.length));
            for (final row in rows) {
              final finder = find.byWidget(row);
              final glyph = find.descendant(
                of: finder,
                matching: find.byType(WorkspaceGlyph),
              );
              expect(glyph, findsOneWidget, reason: row.label);
              expect(
                tester.widget<WorkspaceGlyph>(glyph).name,
                isNot('unknown'),
                reason: row.label,
              );
              expect(tester.getSize(glyph), const Size.square(18));
              _expectWithin(tester.getRect(glyph), tester.getRect(finder));
              _expectGlyphInk(
                tester,
                glyph,
                workspaceGlyphInk(tester.element(finder)),
              );
              final labelStyle = tester
                  .widget<AnimatedDefaultTextStyle>(
                    find.descendant(
                      of: finder,
                      matching: find.byType(AnimatedDefaultTextStyle),
                    ),
                  )
                  .style;
              expect(labelStyle.fontWeight, FontWeight.w500);
              expect(
                labelStyle.fontVariations,
                const [ui.FontVariation.weight(500)],
              );
            }
            if (chunk.length > 1) {
              await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
              await tester.pumpAndSettle();
              final highlighted =
                  tester.widgetList<AppMenuRow>(find.byType(AppMenuRow));
              expect(
                highlighted.where((row) => row.highlighted).single.label,
                chunk[1].name,
              );
            }
            expect(
              find.descendant(
                of: find.byType(AppFlowyDesktopSelectionMenuWidget),
                matching: find.byType(Icon),
              ),
              findsNothing,
            );
            expect(WorkspaceGlyphs.unknownMappings, isEmpty);
            expect(tester.takeException(), isNull);
          }
          expect(isIconPackLoaded(sidebarIconPack), isFalse);
          expect(iconPacksVersion.value, 0);
        } finally {
          await tester.pumpWidget(const SizedBox());
          editor.dispose();
        }
      });
    }

    testWidgets(
        '$appearance selectable helpers keep the same ink when selected',
        (tester) async {
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: Row(
            children: [
              for (final selected in [false, true]) ...[
                SelectableSvgWidget(
                  data: FlowySvgs.slash_menu_icon_h1_s,
                  isSelected: selected,
                  style: SelectionMenuStyle.light,
                ),
                SelectableIconWidget(
                  icon: Icons.draw_rounded,
                  isSelected: selected,
                  style: SelectionMenuStyle.light,
                ),
              ],
            ],
          ),
        ),
      );
      await tester.pumpAndSettle();
      final colors = tester
          .widgetList<SvgPicture>(find.byType(SvgPicture))
          .map((svg) => svg.colorFilter)
          .toSet();
      expect(colors, hasLength(1));
      expect(WorkspaceGlyphs.unknownMappings, isEmpty);
      expect(tester.takeException(), isNull);
    });

    testWidgets(
        '$appearance real context menu preserves states and custom artwork',
        (tester) async {
      var activated = 0;
      final saved = IconsData('appflowy_vivid_essentials', 'book', '4278255360')
          .toEmojiIconData();
      await tester.pumpWidget(
        _localizedIconTestApp(
          appearance: appearance,
          child: Builder(
            builder: (context) => TextButton(
              onPressed: () => showAppMenu<void>(
                context: context,
                globalPosition: const Offset(32, 32),
                entries: [
                  const AppMenuHeader('Actions'),
                  AppMenuItem(
                    label: 'Copy',
                    icon: Icons.copy_rounded,
                    onSelected: () => activated++,
                  ),
                  const AppMenuItem(
                    label: 'Selected',
                    icon: Icons.copy_rounded,
                    selected: true,
                  ),
                  const AppMenuItem(
                    label: 'Unavailable',
                    icon: Icons.copy_rounded,
                    enabled: false,
                  ),
                  const AppMenuItem(
                    label: 'Delete',
                    icon: Icons.delete_outline_rounded,
                    destructive: true,
                  ),
                  const AppMenuItem(
                    label: 'SVG default',
                    iconWidget: FlowySvg(FlowySvgs.settings_page_cloud_m),
                  ),
                  AppMenuItem(
                    label: 'Saved illustration',
                    iconWidget: RawEmojiIconWidget(emoji: saved, emojiSize: 18),
                  ),
                ],
              ),
              child: const Text('Open'),
            ),
          ),
        ),
      );
      final open = find.widgetWithText(TextButton, 'Open');
      await _finishLocalization(tester, open);
      expect(open.hitTestable(), findsOneWidget);
      await tester.tap(open);
      await settleVividIconPictures(tester);
      final normal = find.widgetWithText(AppMenuRow, 'Copy');
      final selected = find.widgetWithText(AppMenuRow, 'Selected');
      final normalGlyph =
          find.descendant(of: normal, matching: find.byType(WorkspaceGlyph));
      final selectedGlyph = find
          .descendant(of: selected, matching: find.byType(WorkspaceGlyph))
          .first;
      expect(
        _picture(tester, normalGlyph).colorFilter,
        _picture(tester, selectedGlyph).colorFilter,
      );
      final style = AppMenuStyle.of(tester.element(normal));
      _expectGlyphInk(
        tester,
        find.descendant(
          of: find.widgetWithText(AppMenuRow, 'Delete'),
          matching: find.byType(WorkspaceGlyph),
        ),
        style.danger,
      );
      _expectGlyphInk(
        tester,
        find.descendant(
          of: find.widgetWithText(AppMenuRow, 'Unavailable'),
          matching: find.byType(WorkspaceGlyph),
        ),
        style.iconMuted.withValues(alpha: 0.5),
      );
      final illustration =
          find.widgetWithText(AppMenuRow, 'Saved illustration');
      final custom = tester.widget<FlowySvg>(
        find.descendant(of: illustration, matching: find.byType(FlowySvg)),
      );
      expect(custom.blendMode, isNull);
      expect(custom.color, isNull);
      expect(
        custom.svgString,
        appFlowyVividIconGroups
            .firstWhere(
              (group) => group.name == 'appflowy_vivid_essentials',
            )
            .icons
            .firstWhere((icon) => icon.name == 'book')
            .content,
      );
      final before = _picture(tester, normalGlyph).colorFilter;
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset.zero);
      await mouse.moveTo(tester.getCenter(normal));
      await tester.pumpAndSettle();
      expect(_picture(tester, normalGlyph).colorFilter, before);
      await tester.tap(find.text('Unavailable'));
      await tester.pumpAndSettle();
      expect(find.byType(AppMenuSurface), findsOneWidget);
      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(activated, 1);
      expect(find.byType(AppMenuSurface), findsNothing);
      await mouse.removePointer();
      expect(WorkspaceGlyphs.unknownMappings, isEmpty);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$appearance saved art grows optically without changing picker defaults',
        (tester) async {
      final colorPack = iconPackForGroup('color_travel_places');
      await tester.runAsync(() => loadIconPack(colorPack));
      final group = loadedIconGroupsOf(colorPack).first;
      final samples = [
        IconsData('appflowy_vivid_essentials', 'book', '4278255360'),
        IconsData(group.name, group.icons.first.name, '4278255360'),
        IconsData('appflowy_default_collections', 'book', '4283665274'),
      ];
      for (final data in samples) {
        final saved = data.toEmojiIconData().toViewIcon();
        final bytes = saved.writeToBuffer();
        final colorful = iconPackForGroup(data.groupName).isColorful;
        for (final role in IconOpticalRole.values) {
          final base = role == IconOpticalRole.sidebar ? 18.0 : 56.0;
          final sizes = IconOpticalSize.resolve(
            role: role,
            baseSize: base,
            colorful: colorful,
          );
          await tester.pumpWidget(
            workspaceOverlayTestApp(
              appearance: appearance,
              textScale: 2,
              child: Center(
                child: SizedBox(
                  width: 100,
                  child: Center(
                    heightFactor: 1,
                    child: RawEmojiIconWidget(
                      emoji: ViewIconPB.fromBuffer(bytes).toEmojiIconData(),
                      emojiSize: base,
                      opticalRole: role,
                    ),
                  ),
                ),
              ),
            ),
          );
          await settleVividIconPictures(tester);
          final frame = find.byType(OpticalIconFrame);
          final art = find.byType(FlowySvg);
          expect(tester.getSize(frame), Size.square(sizes.slotSize));
          expect(tester.getSize(art), Size.square(sizes.artworkSize));
          _expectWithin(tester.getRect(art), tester.getRect(frame));
          expect(MediaQuery.textScalerOf(tester.element(art)).scale(1), 1);
          final svg = tester.widget<FlowySvg>(art);
          expect(svg.svgString, data.svgString);
          expect(svg.blendMode, colorful ? null : BlendMode.srcIn);
          expect(svg.color, colorful ? null : const Color(0xFF538B7A));
          expect(saved.writeToBuffer(), bytes);
          expect(tester.takeException(), isNull);
        }
      }
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          child: Center(
            child: RawEmojiIconWidget(
              emoji: samples.first.toEmojiIconData(),
              emojiSize: 18,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byType(OpticalIconFrame), findsNothing);
      expect(tester.getSize(find.byType(FlowySvg)), const Size.square(18));
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$appearance actual sidebar keeps picker and label slots stable',
        (tester) async {
      var view = ViewPB(
        id: 'optical-fixture',
        name: 'A long sidebar page title',
        layout: ViewLayoutPB.Document,
      );
      late StateSetter update;
      await tester.pumpWidget(
        workspaceOverlayTestApp(
          appearance: appearance,
          textScale: 2,
          child: Center(
            child: SizedBox(
              width: 220,
              child: StatefulBuilder(
                builder: (context, setState) {
                  update = setState;
                  return _sidebarRow(view);
                },
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final picker = find.byKey(const ValueKey('sidebar-icon-optical-fixture'));
      expect(find.byType(ViewIconPicker), findsOneWidget);
      final originalRect = tester.getRect(picker);
      final originalState = tester.state(picker);
      final originalLabel = tester.getTopLeft(find.text(view.name).first);
      expect(originalRect.size, const Size.square(24));
      for (final saved in [
        EmojiIconData.emoji('📚'),
        IconsData('appflowy_vivid_essentials', 'book', null).toEmojiIconData(),
        IconsData('appflowy_default_collections', 'book', '4283665274')
            .toEmojiIconData(),
        EmojiIconData.none(),
      ]) {
        update(() {
          view = ViewPB.fromBuffer(view.writeToBuffer())
            ..icon = saved.toViewIcon();
        });
        await tester.pumpAndSettle();
        expect(tester.state(picker), same(originalState));
        expect(tester.getRect(picker), originalRect);
        expect(tester.getTopLeft(find.text(view.name).first), originalLabel);
        if (saved.isNotEmpty) {
          final raw = tester
              .widget<RawEmojiIconWidget>(find.byType(RawEmojiIconWidget));
          expect(raw.opticalRole, IconOpticalRole.sidebar);
          expect(raw.emoji.emoji, saved.emoji);
          _expectWithin(
            tester.getRect(find.byType(OpticalIconFrame)),
            originalRect,
          );
          expect(
            tester.widget<SidebarRow>(find.byType(SidebarRow)).dimIcon,
            isFalse,
          );
        }
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets(
        '$appearance chrome weight changes do not flatten title hierarchy',
        (tester) async {
      const glyphKey = ValueKey('typography-context');
      await tester.pumpWidget(
        _localizedIconTestApp(
          appearance: appearance,
          child: const SidebarGlyph(
            SidebarIcon.document,
            key: glyphKey,
          ),
        ),
      );
      final glyph = find.byKey(glyphKey);
      await _finishLocalization(tester, glyph);
      final context = tester.element(glyph);
      final control =
          WorkspaceChrome.controlStyle(context).textStyle!.resolve({})!;
      expect(control.fontWeight, FontWeight.w500);
      expect(control.fontVariations, const [ui.FontVariation.weight(500)]);
      final title = WorkspaceChrome.title(context);
      expect(title.fontWeight, FontWeight.w700);
      expect(title.fontVariations, const [ui.FontVariation.weight(700)]);
      expect(
        SidebarTypography.textStyle(context).fontVariations,
        const [ui.FontVariation.weight(500)],
      );
      expect(
        SidebarTypography.textStyle(context, role: SidebarTextRole.heading)
            .fontVariations,
        const [ui.FontVariation.weight(600)],
      );
      expect(AppMenuStyle.of(context).headerStyle.fontWeight, FontWeight.w600);
      expect(
        AppMenuStyle.of(context).subtitleStyle.fontWeight,
        FontWeight.w500,
      );
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('$appearance constrained identity frames never clip artwork',
        (tester) async {
      for (final role in IconOpticalRole.values) {
        final bound = role == IconOpticalRole.sidebar ? 16.0 : 44.0;
        await tester.pumpWidget(
          workspaceOverlayTestApp(
            appearance: appearance,
            textScale: 2,
            child: Center(
              child: SizedBox.square(
                dimension: bound,
                child: RawEmojiIconWidget(
                  emoji: IconsData('appflowy_vivid_essentials', 'book', null)
                      .toEmojiIconData(),
                  emojiSize: role == IconOpticalRole.sidebar ? 18 : 56,
                  opticalRole: role,
                ),
              ),
            ),
          ),
        );
        await settleVividIconPictures(tester);
        final frame = tester.getRect(find.byType(OpticalIconFrame));
        final box = tester.renderObject<RenderBox>(find.byType(FlowySvg));
        final artwork = MatrixUtils.transformRect(
          box.getTransformTo(null),
          Offset.zero & box.size,
        );
        expect(frame.size, Size.square(bound));
        _expectWithin(artwork, frame);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpWidget(const SizedBox());
    });
  }

  test('the adapter leaves uploaded/inline art and saved renderers alone', () {
    final inline = FlowySvg.string(_uploadSvg);
    final upload = SvgPicture.string(_uploadSvg);
    const asset = FlowySvg(FlowySvgData('assets/custom_art.svg'));
    final saved = IconWidget(
      size: 18,
      iconsData: IconsData('appflowy_vivid_essentials', 'book', null),
    );
    for (final widget in [inline, upload, asset, saved]) {
      expect(WorkspaceGlyph.adapt(widget, color: Colors.red), same(widget));
    }
  });

  group('local upload optical frame (no native profile or cloud IO)', () {
    late Directory temporary;
    late File upload;
    late File raster;
    setUp(() async {
      temporary = await Directory.systemTemp.createTemp('optical-icon-');
      upload = await File('${temporary.path}/two-colors.svg')
          .writeAsString(_uploadSvg);
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        const Rect.fromLTWH(0, 0, 12, 12),
        Paint()..color = Colors.red,
      );
      canvas.drawRect(
        const Rect.fromLTWH(12, 0, 12, 12),
        Paint()..color = const Color(0xFF0000FF),
      );
      final picture = recorder.endRecording();
      final image = await picture.toImage(24, 12);
      try {
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!;
        raster = await File('${temporary.path}/wide-upload.png').writeAsBytes(
          png.buffer.asUint8List(png.offsetInBytes, png.lengthInBytes),
        );
      } finally {
        image.dispose();
        picture.dispose();
      }
    });
    tearDown(() async => temporary.delete(recursive: true));
    for (final appearance in _appearances) {
      for (final role in IconOpticalRole.values) {
        testWidgets('$appearance/$role upload keeps colors and padding',
            (tester) async {
          final base = role == IconOpticalRole.sidebar ? 18.0 : 56.0;
          final sizes = IconOpticalSize.resolve(role: role, baseSize: base);
          await tester.pumpWidget(
            workspaceOverlayTestApp(
              appearance: appearance,
              textScale: 2,
              child: Center(
                child: RepaintBoundary(
                  key: const ValueKey('upload-frame'),
                  child: OpticalIconFrame(
                    role: role,
                    baseSize: base,
                    colorful: true,
                    builder: (size) =>
                        SvgPicture.file(upload, width: size, height: size),
                  ),
                ),
              ),
            ),
          );
          await settleVividIconPictures(tester);
          final finder = find.byKey(const ValueKey('upload-frame'));
          expect(tester.getSize(finder), Size.square(sizes.slotSize));
          expect(
            tester.widget<SvgPicture>(find.byType(SvgPicture)).colorFilter,
            isNull,
          );
          final pixels = await _pixels(tester, finder);
          final width = sizes.slotSize.toInt();
          expect(pixels, hasLength(width * width * 4));
          var red = 0;
          var blue = 0;
          for (var y = 0; y < width; y++) {
            for (var x = 0; x < width; x++) {
              final offset = (y * width + x) * 4;
              final alpha = pixels[offset + 3];
              if (x == 0 || y == 0 || x == width - 1 || y == width - 1) {
                expect(
                  alpha,
                  0,
                  reason: 'Optical padding must remain transparent.',
                );
              }
              if (alpha > 240 &&
                  pixels[offset] > 200 &&
                  pixels[offset + 2] < 80) {
                red++;
              }
              if (alpha > 240 &&
                  pixels[offset + 2] > 200 &&
                  pixels[offset] < 80) {
                blue++;
              }
            }
          }
          expect(red, greaterThan(40));
          expect(blue, greaterThan(40));
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });

        testWidgets('$appearance/$role wide raster upload stays contained',
            (tester) async {
          final base = role == IconOpticalRole.sidebar ? 18.0 : 56.0;
          final sizes = IconOpticalSize.resolve(role: role, baseSize: base);
          // Start the file read/codec in the real IO zone, before Image.file
          // can create a pending cache entry inside the widget's fake clock.
          const decodeKey = ValueKey('raster-decode-context');
          await tester.pumpWidget(
            _localizedIconTestApp(
              appearance: appearance,
              textScale: 2,
              child: const SizedBox(key: decodeKey),
            ),
          );
          final decodeContext = find.byKey(decodeKey);
          await _finishLocalization(tester, decodeContext);
          final context = tester.element(decodeContext);
          await tester.runAsync(
            () => precacheImage(FileImage(raster), context)
                .timeout(const Duration(seconds: 5)),
          );
          await tester.pumpWidget(
            _localizedIconTestApp(
              appearance: appearance,
              textScale: 2,
              child: Center(
                child: RepaintBoundary(
                  key: const ValueKey('raster-frame'),
                  child: OpticalIconFrame(
                    role: role,
                    baseSize: base,
                    colorful: true,
                    builder: (size) => Image.file(
                      raster,
                      width: size,
                      height: size,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          );
          final frame = find.byKey(const ValueKey('raster-frame'));
          await _finishLocalization(tester, frame);
          expect(tester.getSize(frame), Size.square(sizes.slotSize));
          final image = find.descendant(
            of: frame,
            matching: find.image(FileImage(raster)),
          );
          expect(image, findsOneWidget);
          final widget = tester.widget<Image>(image);
          expect(widget.color, isNull);
          expect(widget.fit, BoxFit.contain);
          expect(tester.getSize(image), Size.square(sizes.artworkSize));
          _expectWithin(tester.getRect(image), tester.getRect(frame));
          final decoded = tester.widget<RawImage>(
            find.descendant(of: image, matching: find.byType(RawImage)),
          );
          expect(decoded.image, isNotNull);
          expect(decoded.image!.width, 24);
          expect(decoded.image!.height, 12);
          final pixels = await _pixels(tester, frame);
          final width = sizes.slotSize.toInt();
          expect(pixels, hasLength(width * width * 4));
          int channel(int x, int y, int channel) =>
              pixels[(y * width + x) * 4 + channel];
          expect(channel(width ~/ 4, width ~/ 2, 0), greaterThan(200));
          expect(channel(width * 3 ~/ 4, width ~/ 2, 2), greaterThan(200));
          // A contained 2:1 image leaves clear top and bottom padding.
          expect(channel(width ~/ 2, 2, 3), 0);
          expect(channel(width ~/ 2, width - 3, 3), 0);
          expect(tester.takeException(), isNull);
          await tester.pumpWidget(const SizedBox());
        });
      }
    }
  });
}

class _SelectionService extends Fake implements SelectionMenuService {}

// This suite deliberately tests the outline option. The production fallback
// is Vivid; default/preference and full-color adoption have their own suites.
Widget workspaceOverlayTestApp({
  required Widget child,
  String appearance = 'light',
  double textScale = 1,
}) =>
    overlays.workspaceOverlayTestApp(
      appearance: appearance,
      textScale: textScale,
      child: DefaultIconStyleScope(
        styles: const AlwaysStoppedAnimation(DefaultIconStyle.monochrome),
        child: child,
      ),
    );

Future<void> _finishLocalization(WidgetTester tester, Finder content) async {
  // Asset IO was awaited in setUpAll. The asynchronous localization delegate
  // schedules the route after the first pump; render that frame, not a timer.
  await tester.pump();
  expect(tester.takeException(), isNull);
  expect(content, findsOneWidget, reason: 'Localized content must be mounted.');
}

Widget _localizedIconTestApp({
  required Widget child,
  String appearance = 'light',
  double textScale = 1,
}) {
  final app = workspaceOverlayTestApp(
    child: child,
    appearance: appearance,
    textScale: textScale,
  ) as EasyLocalization;
  return EasyLocalization(
    supportedLocales: app.supportedLocales,
    path: app.path,
    fallbackLocale: app.fallbackLocale,
    useFallbackTranslations: app.useFallbackTranslations,
    saveLocale: app.saveLocale,
    assetLoader: _translations,
    child: app.child,
  );
}

/// Real translations, loaded outside the fake clock. Keep the shared app's
/// themes, Navigator and localization delegate; replace only asynchronous IO.
class _PreloadedTranslations extends AssetLoader {
  _PreloadedTranslations(this.resources);

  final Map<Locale, Map<String, dynamic>> resources;

  static Future<_PreloadedTranslations> read() async {
    const loader = TestBundleAssetLoader();
    final resources = <Locale, Map<String, dynamic>>{};
    for (final locale in const [Locale('en', 'US'), Locale('en')]) {
      try {
        resources[locale] = await loader.load('assets/translations', locale);
      } on FlutterError {
        // EasyLocalization also tolerates a missing language-only fallback,
        // but a missing primary locale must fail setup, not return fake copy.
        if (locale.countryCode != null) rethrow;
      }
    }
    return _PreloadedTranslations(resources);
  }

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) {
    final resource = resources[locale];
    if (resource == null) {
      throw FlutterError('No bundled translation for $locale');
    }
    return SynchronousFuture(resource);
  }
}

class _RecordingBundle extends CachingAssetBundle {
  final requests = <String>[];

  @override
  Future<ByteData> load(String key) {
    requests.add(key);
    throw StateError('Default glyphs must not load an asset: $key');
  }
}

SvgPicture _picture(WidgetTester tester, Finder glyph) =>
    tester.widget<SvgPicture>(
      find.descendant(of: glyph, matching: find.byType(SvgPicture)),
    );

void _expectGlyphInk(WidgetTester tester, Finder glyph, Color ink) => expect(
      _picture(tester, glyph).colorFilter,
      ColorFilter.mode(ink, BlendMode.srcIn),
    );

void _expectWithin(Rect child, Rect parent) {
  expect(child.left, greaterThanOrEqualTo(parent.left));
  expect(child.top, greaterThanOrEqualTo(parent.top));
  expect(child.right, lessThanOrEqualTo(parent.right));
  expect(child.bottom, lessThanOrEqualTo(parent.bottom));
}

Widget _sidebarRow(ViewPB view) => SingleInnerViewItem(
      view: view,
      parentView: null,
      isExpanded: false,
      level: 0,
      leftPadding: SidebarMetrics.indent,
      spaceType: FolderSpaceType.unknown,
      showActions: false,
      onSelected: (_, __) {},
      isFeedback: false,
      height: SidebarMetrics.rowHeight,
      leftIconBuilder: (_, __) => const SizedBox.shrink(),
      rightIconsBuilder: (_, __) => [],
      includeDefaultMoreAction: false,
      extendBuilder: null,
      disableSelectedStatus: null,
      shouldIgnoreView: null,
      isSelected: false,
    );

const _uploadSvg =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24">'
    '<path fill="#ff0000" d="M0 0h12v24H0z"/>'
    '<path fill="#0000ff" d="M12 0h12v24H12z"/></svg>';

Future<Uint8List> _pixels(WidgetTester tester, Finder finder) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(finder);
  return (await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final bytes = (await image.toByteData())!;
      return bytes.buffer.asUint8List(bytes.offsetInBytes, bytes.lengthInBytes);
    } finally {
      image.dispose();
    }
  }))!;
}
