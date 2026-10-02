import 'package:appflowy/extensions/dart/appflowy_extension.dart';
import 'package:appflowy/extensions/dart/extension_context.dart';
import 'package:appflowy/extensions/dart/extension_registries.dart';

import 'web_embeds/web_embed_block.dart';
import 'web_embeds/web_embed_dashboard_widget.dart';
import 'web_embeds/web_embed_sites.dart';

/// Posts, videos, maps and documents from the web, shown by their own sites
/// wherever a link to them is kept: a page, a dashboard, a canvas or a
/// bookmark collection.
///
/// The sites are registered once and everything that shows a link asks them,
/// so a page's link embed, a canvas card and a saved bookmark all agree on
/// what a link is and how it is drawn — and all fall back to a plain preview
/// when this is switched off.
class WebEmbedsExtension extends AppFlowyExtension {
  static const id = 'web_embeds';

  @override
  DartExtensionInfo get info => const DartExtensionInfo(
        id: id,
        name: 'Web embeds',
        description: 'Posts from X, LinkedIn, Facebook, Instagram, Threads, '
            'TikTok, Snapchat, Reddit, Quora, Pinterest and Blind; YouTube, '
            'Spotify, Apple Music and SoundCloud; Notion, Figma, GitHub and '
            'GitLab; files from Google Drive, OneDrive, Dropbox, Box, MEGA, '
            'iCloud and JioCloud; Google Maps, Docs, Sheets and Slides and '
            'Office online; news from Google News, MSN and papers worldwide '
            'and across India; Amazon and Flipkart products; and PDFs, live '
            'wherever their links are kept.',
      );

  @override
  Future<void> activate(ExtensionContext context) async {
    final ctx = context as DartExtensionContext;

    for (final site in webEmbedSites()) {
      ctx.webEmbeds.add(site);
    }

    final anySite = webEmbedEntries.first;
    ctx.blocks.define(
      type: WebEmbedBlockKeys.type,
      builder: (configuration) =>
          WebEmbedBlockComponentBuilder(configuration: configuration),
      parser: WebEmbedNodeParser(),
      slashName: anySite.name,
      slashKeywords: anySite.keywords,
      slashIcon: anySite.icon,
      slashDescription: anySite.description,
      newNode: webEmbedPlaceholderNode,
      slashEntries: [
        for (final entry in webEmbedEntries.skip(1))
          ExtensionSlashEntry(
            name: entry.name,
            keywords: entry.keywords,
            icon: entry.icon,
            description: entry.description,
            newNode: () => webEmbedPlaceholderNode(entry.id),
          ),
      ],
    );

    ctx.dashboardWidgets.add(webEmbedDashboardWidget(id));
  }
}
