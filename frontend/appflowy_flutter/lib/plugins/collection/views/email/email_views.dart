import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/email/email_compact_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_conversation_view.dart';
import 'package:appflowy/plugins/collection/views/email/email_three_pane_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// The stable identifiers a mailbox's own views are stored under.
abstract final class EmailViewIds {
  static const threePane = 'email_three_pane';
  static const conversation = 'email_conversation';
  static const compact = 'email_compact';
}

/// The three readings of a mailbox.
List<CollectionViewDefinition> emailCollectionViews() => [
      CollectionViewDefinition(
        id: EmailViewIds.threePane,
        labelKey: LocaleKeys.collections_email_threePane,
        icon: Icons.vertical_split_rounded,
        builder: (context, collection) =>
            EmailThreePaneView(collection: collection),
      ),
      CollectionViewDefinition(
        id: EmailViewIds.conversation,
        labelKey: LocaleKeys.collections_email_conversation,
        icon: Icons.forum_rounded,
        builder: (context, collection) =>
            EmailConversationView(collection: collection),
      ),
      CollectionViewDefinition(
        id: EmailViewIds.compact,
        labelKey: LocaleKeys.collections_email_compact,
        icon: Icons.format_list_bulleted_rounded,
        builder: (context, collection) =>
            EmailCompactView(collection: collection),
      ),
    ];
