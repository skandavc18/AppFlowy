import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/providers/external_picker.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/base/selectable_svg_widget.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/external/external_embed_block_component.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';

import 'slash_menu_item_builder.dart';

/// One entry per service a page can pull content from.
///
/// They read as `/Google Drive`, `/OneDrive`, `/Box`, `/Google Photos` — the
/// name of the service, because that is what somebody is looking for. What
/// arrives on the page is an AppFlowy embed, not a link out.
List<SelectionMenuItem> externalEmbedSlashMenuItems() => [
      for (final info in ProviderServices.connectable)
        if (_embeddable.contains(info.service)) _item(info),
    ];

/// A repository is browsed rather than embedded as one object, so it is not
/// offered here; a Repository collection is the right shape for that.
const _embeddable = <ProviderService>{
  ProviderService.googleDrive,
  ProviderService.oneDrive,
  ProviderService.box,
  ProviderService.googlePhotos,
  ProviderService.immich,
};

SelectionMenuItem _item(ProviderServiceInfo info) => SelectionMenuItem(
      getName: () => info.label,
      keywords: [
        info.label.toLowerCase(),
        ..._keywordsFor(info.service),
      ],
      handler: (editorState, menuService, context) async {
        if (!context.mounted) {
          return;
        }
        final picked = await showExternalPicker(context, info: info);
        if (picked == null) {
          return;
        }
        await editorState.insertExternalEmbed(
          service: info.service,
          connectionId: picked.source.connectionId,
          node: picked.node,
        );
      },
      nameBuilder: slashMenuItemNameBuilder,
      icon: (_, isSelected, style) => SelectableIconWidget(
        icon: info.icon,
        isSelected: isSelected,
        style: style,
      ),
    );

List<String> _keywordsFor(ProviderService service) => switch (service) {
      ProviderService.googleDrive => const [
          'drive',
          'google',
          'file',
          'document',
          'cloud',
        ],
      ProviderService.oneDrive => const [
          'onedrive',
          'microsoft',
          'file',
          'sharepoint',
          'cloud',
        ],
      ProviderService.box => const ['box', 'file', 'cloud'],
      ProviderService.googlePhotos => const [
          'photos',
          'google photos',
          'picture',
          'album',
          'image',
        ],
      ProviderService.immich => const [
          'immich',
          'photo',
          'album',
          'self hosted',
        ],
      _ => const <String>[],
    };

extension InsertExternalEmbed on EditorState {
  /// Puts an external object on the page where the caret is.
  Future<void> insertExternalEmbed({
    required ProviderService service,
    required String connectionId,
    required ProviderNode node,
  }) async {
    final selection = this.selection;
    if (selection == null || !selection.isCollapsed) {
      return;
    }
    final path = selection.end.path;
    final current = getNodeAtPath(path);
    if (current == null) {
      return;
    }

    final block = externalEmbedNode(
      service: service,
      connectionId: connectionId,
      node: node,
    );

    final transaction = this.transaction;
    // Replace the empty paragraph the slash was typed in, otherwise every
    // embed leaves a blank line above it.
    if (current.delta?.isEmpty ?? false) {
      transaction
        ..insertNode(path, block)
        ..deleteNode(current)
        ..afterSelection = Selection.collapsed(Position(path: path));
    } else {
      final next = [...path.take(path.length - 1), path.last + 1];
      transaction
        ..insertNode(next, block)
        ..afterSelection = Selection.collapsed(Position(path: next));
    }
    await apply(transaction);
  }
}

/// The label the slash menu section uses.
String externalEmbedSectionLabel() => LocaleKeys.providers_connections.tr();
