import 'package:appflowy/extensions/application/extension_manifest.dart';
import 'package:appflowy/extensions/application/extension_store.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';
import 'package:appflowy/extensions/presentation/island_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/slash_menu/slash_menu_items/slash_menu_item_builder.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:flutter/material.dart';

/// One slash item per island every enabled extension declares, plus one per
/// block a Dart extension registered with a `/` name.
///
/// Read from the registries as the menu is built, so anything added is offered
/// without a rebuild of the menu itself.
List<SelectionMenuItem> islandSlashMenuItems() {
  final items = <SelectionMenuItem>[];
  for (final extension in ExtensionStore.instance.active) {
    for (final island in extension.manifest.islands) {
      items.add(_islandItem(extension.manifest, island));
    }
  }
  for (final block in ExtensionBlockRegistry.all()) {
    for (final entry in block.slashEntries) {
      items.add(_blockItem(entry));
    }
  }
  return items;
}

Map<SelectionMenuItem, String> islandSlashMenuDescriptions(
  List<SelectionMenuItem> items,
) {
  final descriptions = <SelectionMenuItem, String>{};
  var at = 0;

  void describe(String text) {
    if (at < items.length && text.isNotEmpty) {
      descriptions[items[at]] = text;
    }
    at++;
  }

  for (final extension in ExtensionStore.instance.active) {
    for (final island in extension.manifest.islands) {
      describe(
        island.description.isNotEmpty
            ? island.description
            : extension.manifest.name,
      );
    }
  }
  for (final block in ExtensionBlockRegistry.all()) {
    for (final entry in block.slashEntries) {
      describe(entry.description);
    }
  }
  return descriptions;
}

SelectionMenuItem _blockItem(ExtensionSlashEntry entry) =>
    SelectionMenuItem.node(
      getName: () => entry.name,
      keywords: [entry.name.toLowerCase(), ...entry.keywords],
      nodeBuilder: (_, __) => entry.newNode(),
      replace: (_, node) => node.delta?.isEmpty ?? false,
      nameBuilder: slashMenuItemNameBuilder,
      iconBuilder: (_, isSelected, style) => SelectableIconWidget(
        icon: entry.icon,
        isSelected: isSelected,
        style: style,
      ),
    );

SelectionMenuItem _islandItem(
  ExtensionManifest manifest,
  ExtensionIsland island,
) =>
    SelectionMenuItem.node(
      getName: () => island.name,
      keywords: [
        island.id,
        island.name.toLowerCase(),
        manifest.id,
        ...island.keywords,
      ],
      nodeBuilder: (_, __) => extensionIslandNode(
        extensionId: manifest.id,
        island: island.id,
        height: island.height,
      ),
      replace: (_, node) => node.delta?.isEmpty ?? false,
      nameBuilder: slashMenuItemNameBuilder,
      iconBuilder: (_, isSelected, style) => SelectableIconWidget(
        icon: Icons.extension_rounded,
        isSelected: isSelected,
        style: style,
      ),
    );
