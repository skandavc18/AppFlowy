import 'package:appflowy_editor/appflowy_editor.dart';

enum SlashMenuSection {
  suggestions,
  basicBlocks,
  interactive,
  canvas,
  dashboards,

  /// Dashboard widgets placed straight into the page.
  widgets,
  diagrams,
  media,
  collections,
  database,
  advanced,
}

class SlashMenuItemMetadata {
  const SlashMenuItemMetadata({
    required this.section,
    this.shortcut,
    this.description,
    this.isNew = false,
    this.blockType,
    this.pageOnly = false,
  });

  final SlashMenuSection section;
  final String? shortcut;

  /// A quiet second line saying what the block is for.
  final String? description;

  final bool isNew;

  /// The node type the entry inserts, where it is known.
  ///
  /// A dashboard widget that already IS this block (its `pageBlock`) is what
  /// a dashboard offers instead, so the block is not offered twice there.
  final String? blockType;

  /// The entry only makes sense in a page's flow of text — a heading level,
  /// an inline date, columns — so it is not offered on dashboards and
  /// canvases. Everything else, including every entry added later, is.
  final bool pageOnly;
}

class SlashMenuSectionItems {
  const SlashMenuSectionItems({
    required this.section,
    required this.items,
    this.shortcuts = const {},
    this.descriptions = const {},
    this.newItems = const {},
    this.blockTypes = const {},
    this.pageOnly = const {},
    this.wholeSectionPageOnly = false,
  });

  final SlashMenuSection section;
  final List<SelectionMenuItem> items;
  final Map<SelectionMenuItem, String> shortcuts;
  final Map<SelectionMenuItem, String> descriptions;
  final Set<SelectionMenuItem> newItems;
  final Map<SelectionMenuItem, String> blockTypes;
  final Set<SelectionMenuItem> pageOnly;

  /// Every entry in the section is [SlashMenuItemMetadata.pageOnly].
  final bool wholeSectionPageOnly;
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
        description: section.descriptions[item],
        isNew: section.newItems.contains(item),
        blockType: section.blockTypes[item],
        pageOnly:
            section.wholeSectionPageOnly || section.pageOnly.contains(item),
      );
      items.add(item);
    }
  }
  return items;
}
