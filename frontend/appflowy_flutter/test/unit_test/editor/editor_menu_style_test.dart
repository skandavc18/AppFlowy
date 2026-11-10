import 'package:appflowy/plugins/document/presentation/editor_menu_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/context_menu/custom_context_menu.dart';
import 'package:appflowy/mobile/presentation/selection_menu/mobile_selection_menu_item.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/simple_table/simple_table_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/mobile_items.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/slash_menu_items.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_metadata.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('menu text uses the shared regular UI weight', (tester) async {
    late TextStyle style;

    await tester.pumpWidget(
      MaterialApp(
        home: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(
            fontFamily: preferredFontFamily,
          ),
          child: Builder(
            builder: (context) {
              style = AppFlowyEditorMenuStyle.itemTextStyle(context);
              return Text('Copy', style: style);
            },
          ),
        ),
      ),
    );

    expect(style.fontSize, 14);
    expect(style.fontWeight, defaultFontWeight);
    expect(style.fontVariations, defaultFontVariations);
    expect(style.fontFeatures, isNotEmpty);
    expect(style.shadows, isNotEmpty);
  });

  test('uses reference menu geometry', () {
    expect(AppFlowyEditorMenuStyle.menuWidth, 280);
    expect(AppFlowyEditorMenuStyle.slashMenuMaxHeight, 400);
    expect(AppFlowyEditorMenuStyle.contextMenuEstimatedHeight, 192);
  });

  testWidgets('menu items support a neutral selected background', (
    tester,
  ) async {
    const selectedColor = Color(0x0D1F2329);

    await tester.pumpWidget(
      MaterialApp(
        home: AppFlowyTheme(
          data: AppFlowyDefaultTheme().light(
            fontFamily: preferredFontFamily,
          ),
          child: AFMenuItem(
            selected: true,
            selectedBackgroundColor: selectedColor,
            title: const Text('Selected'),
            onTap: () {},
          ),
        ),
      ),
    );

    final finder = find.byType(AFBaseButton);
    final button = tester.widget<AFBaseButton>(finder);
    final context = tester.element(finder);

    expect(button.backgroundColor?.call(context, false, false), selectedColor);
  });

  test('groups and annotates basic slash-menu items', () {
    final items = slashMenuItemsBuilder();
    final headingMetadata = slashMenuMetadataFor(heading1SlashMenuItem);

    expect(headingMetadata?.section, SlashMenuSection.basicBlocks);
    expect(headingMetadata?.shortcut, '#');
    expect(
      items.indexOf(toggleListSlashMenuItem),
      lessThan(items.indexOf(imageSlashMenuItem)),
    );
    expect(items, containsAll([audioSlashMenuItem, videoSlashMenuItem]));
    expect(
      items,
      containsAll([
        wordSlashMenuItem,
        excelSlashMenuItem,
        powerpointSlashMenuItem,
      ]),
    );
    expect(
      slashMenuMetadataFor(audioSlashMenuItem)?.section,
      SlashMenuSection.media,
    );
    expect(
      slashMenuMetadataFor(videoSlashMenuItem)?.section,
      SlashMenuSection.media,
    );
    for (final item in [
      wordSlashMenuItem,
      excelSlashMenuItem,
      powerpointSlashMenuItem,
    ]) {
      expect(
        slashMenuMetadataFor(item)?.section,
        SlashMenuSection.media,
      );
    }
    expect(
      slashMenuMetadataFor(aiWriterSlashMenuItem)?.section,
      SlashMenuSection.suggestions,
    );
  });

  test('mobile slash groups offer exactly the desktop entries', () {
    // Some entries are made afresh on each build (linked views, extension
    // islands, widgets), so both arrangements come from one build.
    final sections = slashMenuSections();
    final desktop = registerSlashMenuSections(sections);
    final groups = mobileSlashMenuGroups(sections);

    final offered = [
      for (final group in groups)
        ...(group as MobileSelectionMenuItem).children,
    ];
    expect(offered.toSet(), desktop.toSet());
    expect(offered.length, offered.toSet().length);

    // One group per section, named as desktop heads it and in its order.
    final expected = <String>[];
    for (final section in sections) {
      final label = slashMenuSectionLabel(section.section);
      if (section.items.isNotEmpty && !expected.contains(label)) {
        expected.add(label);
      }
    }
    expect(groups.map((group) => group.name), expected);

    // The blocks mobile used to leave out are among them.
    expect(
      offered,
      containsAll([
        aiWriterSlashMenuItem,
        emojiSlashMenuItem,
        excalidrawSlashMenuItem,
        twoColumnsSlashMenuItem,
        outlineSlashMenuItem,
        bookmarkSlashMenuItem,
        chartSlashMenuItem,
        linkToPageSlashMenuItem,
      ]),
    );
  });

  test('a table cell offers the table sections on mobile too', () {
    final sections = slashMenuSections(node: _tableCellParagraph());
    final groups = mobileSlashMenuGroups(sections);
    final offered = {
      for (final group in groups)
        ...(group as MobileSelectionMenuItem).children,
    };
    expect(offered, registerSlashMenuSections(sections).toSet());
    expect(offered, isNot(contains(photoGallerySlashMenuItem)));
  });

  test('context menu follows reference order and platform shortcuts', () {
    final entries = editorContextMenuEntries.expand((group) => group).toList();

    expect(
      entries.map((entry) => entry.action),
      [
        EditorContextMenuAction.copy,
        EditorContextMenuAction.cut,
        EditorContextMenuAction.paste,
        EditorContextMenuAction.pasteAsPlainText,
        EditorContextMenuAction.askAi,
      ],
    );
    expect(entries[0].shortcut?.call(TargetPlatform.windows), 'Ctrl+C');
    expect(
      entries[3].shortcut?.call(TargetPlatform.windows),
      'Ctrl+Shift+V',
    );
    expect(entries[0].shortcut?.call(TargetPlatform.macOS), '⌘C');
  });
}

/// The paragraph inside the first cell of a fresh table.
Node _tableCellParagraph() =>
    createSimpleTableBlockNode(columnCount: 1, rowCount: 1)
        .children
        .first
        .children
        .first
        .children
        .first;
