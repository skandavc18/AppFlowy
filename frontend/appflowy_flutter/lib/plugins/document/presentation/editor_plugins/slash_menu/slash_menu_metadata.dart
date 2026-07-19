import 'package:appflowy_editor/appflowy_editor.dart';

enum SlashMenuSection {
  suggestions,
  basicBlocks,
  media,
  database,
  advanced,
}

class SlashMenuItemMetadata {
  const SlashMenuItemMetadata({
    required this.section,
    this.shortcut,
    this.isNew = false,
  });

  final SlashMenuSection section;
  final String? shortcut;
  final bool isNew;
}

class SlashMenuSectionItems {
  const SlashMenuSectionItems({
    required this.section,
    required this.items,
    this.shortcuts = const {},
    this.newItems = const {},
  });

  final SlashMenuSection section;
  final List<SelectionMenuItem> items;
  final Map<SelectionMenuItem, String> shortcuts;
  final Set<SelectionMenuItem> newItems;
}

final _metadata =
    Expando<SlashMenuItemMetadata>('appflowy_slash_menu_metadata');

SlashMenuItemMetadata? slashMenuMetadataFor(SelectionMenuItem item) =>
    _metadata[item];

List<SelectionMenuItem> registerSlashMenuSections(
  List<SlashMenuSectionItems> sections,
) {
  final items = <SelectionMenuItem>[];
  for (final section in sections) {
    for (final item in section.items) {
      _metadata[item] = SlashMenuItemMetadata(
        section: section.section,
        shortcut: section.shortcuts[item],
        isNew: section.newItems.contains(item),
      );
      items.add(item);
    }
  }
  return items;
}
