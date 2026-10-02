import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/link_embed_block_component.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_embed/youtube_video_download.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/link_preview/shared.dart';
import 'package:appflowy_editor/appflowy_editor.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

import 'paste_choice_menu.dart';

class PasteAsMenuService {
  PasteAsMenuService({
    required this.context,
    required this.editorState,
  });

  final BuildContext context;
  final EditorState editorState;
  late final PasteChoiceMenuOverlay _overlay = PasteChoiceMenuOverlay(
    context: context,
    editorState: editorState,
  );

  /// Asks what the link just pasted before the caret should become.
  ///
  /// [length] is how much text the link takes up before the caret. It is not
  /// [href]'s length when the link came with a title, the way browsers copy
  /// an address.
  void show(String href, {int? length}) {
    final linkLength = length ?? href.length;
    _overlay.show(
      choices: PasteMenuType.values.length,
      builder: (dismiss) => PasteAsMenu(
        editorState: editorState,
        href: href,
        onSelect: (type) {
          final selection = editorState.selection;
          if (selection == null) return;
          final end = selection.end;
          final urlSelection = Selection(
            start: end.copyWith(offset: end.offset - linkLength),
            end: end,
          );
          if (type == PasteMenuType.bookmark) {
            convertUrlToLinkPreview(editorState, urlSelection, href);
          } else if (type == PasteMenuType.mention) {
            convertUrlToMention(editorState, urlSelection);
          } else if (type == PasteMenuType.embed) {
            convertUrlToLinkPreview(
              editorState,
              urlSelection,
              href,
              previewType: LinkEmbedKeys.embed,
            );
          }
          dismiss();
        },
        onDismiss: dismiss,
      ),
    );
  }

  void dismiss() => _overlay.dismiss();
}

/// What an embed of a pasted link would show, when anything can draw it.
@immutable
class PasteEmbedTarget {
  const PasteEmbedTarget({
    required this.subject,
    required this.icon,
    required this.color,
  });

  /// `X post`, `Spotify track`, `BBC article`.
  final String subject;
  final IconData icon;
  final Color color;

  static PasteEmbedTarget? of(String? href) {
    final link = ExtensionWebEmbedRegistry.recognize(href);
    if (link != null) {
      return PasteEmbedTarget(
        subject: webEmbedSubject(link),
        icon: link.icon,
        color: link.color,
      );
    }
    // The embed block plays YouTube itself, even with the sites switched off.
    if (href != null && isYoutubeVideoUrl(href)) {
      return const PasteEmbedTarget(
        subject: 'YouTube video',
        icon: Icons.smart_display_rounded,
        color: Color(0xFFFF0033),
      );
    }
    return null;
  }
}

/// The site and what the link is within it: `X post`, `BBC article`, or just
/// `Google Sheets` when the site's own name already says what it is.
String webEmbedSubject(WebEmbedLink link) {
  final site = link.site.trim();
  final kind = link.kind.trim();
  if (kind.isEmpty || site.toLowerCase().contains(kind.toLowerCase())) {
    return site;
  }
  // `PDF` and `TV show` keep their capitals; `Post` reads as `post`.
  final acronym = kind.length > 1 &&
      kind[1].toUpperCase() == kind[1] &&
      kind[1].toLowerCase() != kind[1];
  final word = acronym ? kind : kind[0].toLowerCase() + kind.substring(1);
  return '$site $word';
}

/// Asks what a pasted link should become.
///
/// A link a site can draw is asked about as an embed: the question names the
/// site and the embed is the answer already chosen, with keeping the link,
/// a bookmark card and a mention one key away. Any other link gets the plain
/// choice of what to paste it as.
class PasteAsMenu extends StatelessWidget {
  const PasteAsMenu({
    super.key,
    required this.onSelect,
    required this.onDismiss,
    required this.editorState,
    this.href,
  });

  final ValueChanged<PasteMenuType?> onSelect;
  final VoidCallback onDismiss;
  final EditorState editorState;

  /// The pasted link.
  final String? href;

  @override
  Widget build(BuildContext context) {
    final target = PasteEmbedTarget.of(href);
    if (target == null) {
      return PasteChoiceMenu<PasteMenuType>(
        editorState: editorState,
        title:
            LocaleKeys.document_plugins_linkPreview_typeSelection_pasteAs.tr(),
        choices: [
          for (final type in PasteMenuType.values)
            PasteChoice(value: type, label: type.title),
        ],
        onSelect: onSelect,
        onDismiss: onDismiss,
      );
    }
    return PasteChoiceMenu<PasteMenuType>(
      editorState: editorState,
      leading: Icon(target.icon, size: 16, color: target.color),
      title: LocaleKeys.document_plugins_linkPreview_typeSelection_embedQuestion
          .tr(args: [target.subject]),
      choices: [
        PasteChoice(
          value: PasteMenuType.embed,
          label: PasteMenuType.embed.title,
        ),
        PasteChoice(
          value: PasteMenuType.url,
          label: LocaleKeys.document_plugins_linkPreview_typeSelection_keepLink
              .tr(),
        ),
        PasteChoice(
          value: PasteMenuType.bookmark,
          label: PasteMenuType.bookmark.title,
        ),
        PasteChoice(
          value: PasteMenuType.mention,
          label: PasteMenuType.mention.title,
        ),
      ],
      onSelect: onSelect,
      onDismiss: onDismiss,
    );
  }
}

enum PasteMenuType {
  mention,
  url,
  bookmark,
  embed,
}

extension PasteMenuTypeExtension on PasteMenuType {
  String get title {
    switch (this) {
      case PasteMenuType.mention:
        return LocaleKeys.document_plugins_linkPreview_typeSelection_mention
            .tr();
      case PasteMenuType.url:
        return LocaleKeys.document_plugins_linkPreview_typeSelection_URL.tr();
      case PasteMenuType.bookmark:
        return LocaleKeys.document_plugins_linkPreview_typeSelection_bookmark
            .tr();
      case PasteMenuType.embed:
        return LocaleKeys.document_plugins_linkPreview_typeSelection_embed.tr();
    }
  }
}
