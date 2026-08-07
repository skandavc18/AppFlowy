import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_artwork.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_style.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_tiles.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/previews/folder_embed_preview.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:appflowy/workspace/application/collections/email/email_message.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

abstract final class EmailEmbedStyles {
  static const recent = 'recent';
  static const unread = 'unread';
  static const compact = 'compact';
}

/// Mail is the one collection that really is a mobile widget: a squarish
/// rectangle listing the newest messages, with less rounding than the others
/// because that is what a mail widget looks like on every platform.
CollectionEmbedDefinition buildEmailEmbedDefinition() =>
    CollectionEmbedDefinition(
      kind: CollectionKind.email,
      defaultItemLimit: 5,
      compactHeight: 150,
      mediumHeight: 262,
      largeHeight: 392,
      styles: const [
        CollectionEmbedStyle(
          id: EmailEmbedStyles.recent,
          labelKey: LocaleKeys.collections_embed_styles_mailbox,
          icon: Icons.mail_rounded,
        ),
        CollectionEmbedStyle(
          id: EmailEmbedStyles.unread,
          labelKey: LocaleKeys.collections_embed_styles_unread,
          icon: Icons.mark_email_unread_rounded,
        ),
        CollectionEmbedStyle(
          id: EmailEmbedStyles.compact,
          labelKey: LocaleKeys.collections_embed_styles_compact,
          icon: Icons.density_small_rounded,
        ),
      ],
      builder: (context, embed) => EmailEmbedPreview(embed: embed),
    );

class EmailEmbedPreview extends StatelessWidget {
  const EmailEmbedPreview({super.key, required this.embed});

  final CollectionEmbedContext embed;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    if (embed.controller.isLoading && embed.children.isEmpty) {
      return const CollectionEmbedSpinner();
    }

    final messages = <EmailMessage>[];
    for (final view in embed.children) {
      final message = EmailMessage.fromView(view);
      if (message == null) {
        continue;
      }
      if (embed.style == EmailEmbedStyles.unread && message.read) {
        continue;
      }
      messages.add(message);
    }
    // Newest first: a mail widget is a feed, not a folder listing.
    messages.sort((a, b) => _sortKey(b).compareTo(_sortKey(a)));

    if (messages.isEmpty) {
      return CollectionEmbedEmpty(
        theme: theme,
        icon: Icons.mark_email_read_rounded,
        message: LocaleKeys.collections_embed_noMessages.tr(),
        compact: embed.size.isCompact,
      );
    }

    final limit = embed.settings.itemLimit ?? embed.definition.defaultItemLimit;
    final shown =
        messages.length <= limit ? messages : messages.take(limit).toList();
    final dense =
        embed.style == EmailEmbedStyles.compact || embed.size.isCompact;

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(8, 2, 8, 10),
      physics: const ClampingScrollPhysics(),
      itemCount: shown.length,
      itemBuilder: (context, index) => _MessageRow(
        embed: embed,
        message: shown[index],
        dense: dense,
      ),
    );
  }
}

DateTime _sortKey(EmailMessage message) =>
    message.sentAt ?? DateTime.fromMillisecondsSinceEpoch(0);

class _MessageRow extends StatelessWidget {
  const _MessageRow({
    required this.embed,
    required this.message,
    required this.dense,
  });

  final CollectionEmbedContext embed;
  final EmailMessage message;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    final theme = embed.theme;
    final sender = message.sender.isEmpty
        ? LocaleKeys.collections_embed_unknownSender.tr()
        : message.sender;
    final hue = collectionObjectHue(sender.toLowerCase(), dark: theme.isDark);
    final snippet = message.metadata.snippet;

    return CollectionEmbedTappable(
      onTap: () => embed.onOpenObject(message.view),
      onSecondaryTap: embed.onShowMenu,
      lift: 0,
      builder: (context, hovered) => AnimatedContainer(
        duration: CollectionEmbedMetrics.hover,
        curve: CollectionEmbedMetrics.ease,
        margin: const EdgeInsets.symmetric(vertical: 1),
        padding: EdgeInsets.fromLTRB(8, dense ? 6 : 8, 8, dense ? 6 : 8),
        decoration: BoxDecoration(
          color: hovered ? theme.rowHover : theme.rowHover.withValues(alpha: 0),
          // A mail widget is squarish, not a pill.
          borderRadius: BorderRadius.circular(7),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!message.read)
              Container(
                width: 6,
                height: 6,
                margin: const EdgeInsets.only(top: 7, right: 5),
                decoration: BoxDecoration(
                  color: theme.accent,
                  shape: BoxShape.circle,
                ),
              )
            else
              const SizedBox(width: 11),
            if (!dense) ...[
              _Avatar(hue: hue, sender: sender, theme: theme),
              const SizedBox(width: 9),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          sender,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.face(
                            context,
                            size: dense ? 11.5 : 12.5,
                            color: message.read
                                ? theme.textBody
                                : theme.textPrimary,
                            weightAxis: message.read ? 560 : 660,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      if (message.metadata.hasAttachments) ...[
                        Icon(
                          Icons.attach_file_rounded,
                          size: 11,
                          color: theme.textFaint,
                        ),
                        const SizedBox(width: 4),
                      ],
                      Text(
                        _timeLabel(message.sentAt),
                        style: theme.caption(context, size: 10),
                      ),
                    ],
                  ),
                  const SizedBox(height: 1),
                  Text(
                    message.subject,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.face(
                      context,
                      size: dense ? 11 : 12,
                      color: message.read ? theme.textMuted : theme.textBody,
                      weightAxis: message.read ? 520 : 580,
                    ),
                  ),
                  if (!dense && snippet.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.caption(context, size: 10.5),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({
    required this.hue,
    required this.sender,
    required this.theme,
  });

  final Color hue;
  final String sender;
  final CollectionEmbedTheme theme;

  @override
  Widget build(BuildContext context) => Container(
        width: 24,
        height: 24,
        decoration: BoxDecoration(
          color: Color.alphaBlend(
            hue.withValues(alpha: theme.isDark ? 0.28 : 0.18),
            theme.sunken,
          ),
          borderRadius: BorderRadius.circular(7),
        ),
        alignment: Alignment.center,
        child: Text(
          emailInitials(sender),
          style: TextStyle(
            color: hue,
            fontSize: 10,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
}

/// Today shows a time, this year a date, anything older the year too — the
/// same abbreviation every mail client uses.
String _timeLabel(DateTime? value) {
  if (value == null) {
    return '';
  }
  final local = value.toLocal();
  final now = DateTime.now();
  if (local.year == now.year &&
      local.month == now.month &&
      local.day == now.day) {
    return DateFormat.jm().format(local);
  }
  if (local.year == now.year) {
    return DateFormat.MMMd().format(local);
  }
  return DateFormat.yMd().format(local);
}
