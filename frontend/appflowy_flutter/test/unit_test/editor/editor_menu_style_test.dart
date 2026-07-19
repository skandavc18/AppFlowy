import 'package:appflowy/plugins/document/presentation/editor_menu_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/context_menu/custom_context_menu.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/slash_menu_items.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items_builder.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_metadata.dart';
import 'package:appflowy/workspace/application/settings/appearance/base_appearance.dart';
import 'package:appflowy_ui/appflowy_ui.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('menu text uses polished shared UI weight 550', (tester) async {
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
      slashMenuMetadataFor(audioSlashMenuItem)?.section,
      SlashMenuSection.media,
    );
    expect(
      slashMenuMetadataFor(videoSlashMenuItem)?.section,
      SlashMenuSection.media,
    );
    expect(
      slashMenuMetadataFor(aiWriterSlashMenuItem)?.section,
      SlashMenuSection.suggestions,
    );
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
