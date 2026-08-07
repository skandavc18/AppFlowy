import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/bookmark/bookmark_dialogs.dart';
import 'package:appflowy/plugins/collection/views/email/email_import.dart';
import 'package:appflowy/shared/context_menu/app_context_menu.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/collection_content_policy.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:appflowy/workspace/application/collections/collection_service.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_file_kind.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_database_menu.dart';
import 'package:appflowy/workspace/presentation/widgets/folder_explorer/workspace_file_kind_menu.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

/// One thing a collection can be asked to add.
sealed class CollectionAddChoice {
  const CollectionAddChoice();
}

class CollectionAddFile extends CollectionAddChoice {
  const CollectionAddFile(this.action);

  final WorkspaceFileMenuAction action;
}

class CollectionAddFolder extends CollectionAddChoice {
  const CollectionAddFolder();
}

class CollectionAddPage extends CollectionAddChoice {
  const CollectionAddPage();
}

class CollectionAddTable extends CollectionAddChoice {
  const CollectionAddTable(this.kind);

  final WorkspaceTableKind kind;
}

class CollectionAddNested extends CollectionAddChoice {
  const CollectionAddNested(this.kind);

  final CollectionKind kind;
}

class CollectionAddLink extends CollectionAddChoice {
  const CollectionAddLink();
}

class CollectionAddMail extends CollectionAddChoice {
  const CollectionAddMail();
}

/// The rows a collection's Add menu shows, given what it will hold.
///
/// The actions a type exists for come first — a mailbox opens on importing
/// mail, a library on saving a link — then the objects authored here, then the
/// files, tables and nested collections it accepts.
///
/// [onSelected] is only needed when the rows are nested in a submenu:
/// `showAppMenu` hands back the value of the row that was chosen at the top
/// level and nothing deeper.
List<AppMenuEntry> collectionAddEntries(
  CollectionContentPolicy policy, {
  ValueChanged<CollectionAddChoice>? onSelected,
}) {
  AppMenuItem row(
    String label,
    IconData icon,
    CollectionAddChoice choice, {
    String? subtitle,
  }) =>
      AppMenuItem(
        label: label,
        icon: icon,
        subtitle: subtitle,
        value: choice,
        onSelected: onSelected == null ? null : () => onSelected(choice),
      );

  final entries = <AppMenuEntry>[];
  if (policy.allowsLinks) {
    entries.add(
      row(
        LocaleKeys.collections_bookmark_addLink.tr(),
        Icons.add_link_rounded,
        const CollectionAddLink(),
      ),
    );
  }
  if (policy.allowsMail) {
    entries.add(
      row(
        LocaleKeys.collections_email_import.tr(),
        Icons.forward_to_inbox_rounded,
        const CollectionAddMail(),
      ),
    );
  }
  if (policy.allowsPages) {
    entries.add(
      row(
        LocaleKeys.workspaceFolderExplorer_newPage.tr(),
        Icons.description_rounded,
        const CollectionAddPage(),
      ),
    );
  }
  if (policy.allowsFolders) {
    entries.add(
      row(
        LocaleKeys.workspaceFolderExplorer_newFolder.tr(),
        workspaceAddFolderIcon,
        const CollectionAddFolder(),
      ),
    );
  }
  for (final entry in workspaceFileKindEntries(kinds: policy.fileKinds)) {
    entries.add(
      switch (entry) {
        AppMenuItem(value: final WorkspaceFileMenuAction action) => row(
            entry.label,
            entry.icon ?? action.icon,
            CollectionAddFile(action),
          ),
        _ => entry,
      },
    );
  }
  if (policy.allowsTables) {
    entries
      ..add(const AppMenuSeparator())
      ..add(AppMenuHeader(LocaleKeys.collections_database_tables.tr()));
    for (final kind in WorkspaceTableKind.values) {
      entries.add(
        row(
          workspaceTableKindLabel(kind),
          workspaceTableKindIcon(kind),
          CollectionAddTable(kind),
        ),
      );
    }
  }
  if (policy.allowsCollections) {
    entries
      ..add(const AppMenuSeparator())
      ..add(AppMenuHeader(LocaleKeys.collections_plural.tr()));
    for (final definition in CollectionRegistry.types) {
      entries.add(
        row(
          definition.label,
          definition.icon,
          CollectionAddNested(definition.kind),
          subtitle: definition.description,
        ),
      );
    }
  }
  return entries;
}

/// Shows what [policy] allows, anchored at [globalPosition].
Future<CollectionAddChoice?> showCollectionAddMenu({
  required BuildContext context,
  required Offset globalPosition,
  required CollectionContentPolicy policy,
}) =>
    showAppMenu<CollectionAddChoice>(
      context: context,
      globalPosition: globalPosition,
      width: WorkspaceFileKindMenuStyle.width,
      entries: collectionAddEntries(policy),
    );

/// Carries out [choice] under [parentId], and hands back what it made.
///
/// A link and an import answer with null: both open their own interface and
/// report themselves, and neither produces one object to open.
Future<ViewPB?> applyCollectionAddChoice(
  BuildContext context, {
  required CollectionAddChoice choice,
  required CollectionViewContext collection,
  required String parentId,
}) async {
  switch (choice) {
    case CollectionAddFile(:final action):
      return collection.explorer
          .createFileImmediately(action, parentId: parentId);
    case CollectionAddFolder():
      return collection.explorer.createFolderImmediately(parentId: parentId);
    case CollectionAddPage():
      return collection.explorer.createPageImmediately(parentId: parentId);
    case CollectionAddTable(:final kind):
      return createWorkspaceDatabase(parentViewId: parentId, kind: kind);
    case CollectionAddNested(:final kind):
      final created = await const CollectionService().createCollection(
        parentViewId: parentId,
        kind: kind,
        name: CollectionRegistry.typeFor(kind).defaultName,
      );
      return created.fold((view) => view, (_) => null);
    case CollectionAddLink():
      await showAddBookmarkDialog(context: context, collection: collection);
      return null;
    case CollectionAddMail():
      await importMailWithFeedback(
        context,
        collection: collection.collectionView,
      );
      return null;
  }
}
