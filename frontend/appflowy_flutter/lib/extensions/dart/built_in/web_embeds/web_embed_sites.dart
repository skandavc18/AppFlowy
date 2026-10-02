import 'package:appflowy/extensions/dart/web_embed_registry.dart';
import 'package:flutter/material.dart';

import 'audio_video_embeds.dart';
import 'document_embeds.dart';
import 'network_embeds.dart';
import 'pdf_embeds.dart';
import 'reading_embeds.dart';
import 'shopping_embeds.dart';
import 'social_embeds.dart';
import 'storage_embeds.dart';
import 'work_embeds.dart';

/// Every site the web embeds extension knows, in the order they are asked.
///
/// ⚠️ The file viewers go last. Office takes any public address ending in
/// `.docx` and PDF any ending in `.pdf`, which must not shadow a site that
/// previews its own files, like Dropbox or GitHub. OneDrive's folders and
/// photos follow Office, which knows OneDrive's documents better.
List<WebEmbedProvider> webEmbedSites() => const [
      YoutubeEmbeds(),
      // Social networks and communities.
      PinterestEmbeds(),
      RedditEmbeds(),
      QuoraEmbeds(),
      InstagramEmbeds(),
      XEmbeds(),
      LinkedInEmbeds(),
      FacebookEmbeds(),
      ThreadsEmbeds(),
      TikTokEmbeds(),
      SnapchatEmbeds(),
      TelegramEmbeds(),
      BlindEmbeds(),
      BlueskyEmbeds(),
      // Music, podcasts and video.
      SpotifyEmbeds(),
      AppleMediaEmbeds(),
      SoundCloudEmbeds(),
      JioSaavnEmbeds(),
      VimeoEmbeds(),
      DailymotionEmbeds(),
      LoomEmbeds(),
      TedEmbeds(),
      TwitchEmbeds(),
      // Google.
      GoogleMapsEmbeds(),
      GoogleWorkspaceEmbeds(),
      GooglePhotosEmbeds(),
      GoogleNewsEmbeds(),
      // Work, design and code.
      NotionEmbeds(),
      FigmaEmbeds(),
      CanvaEmbeds(),
      MiroEmbeds(),
      AirtableEmbeds(),
      FormEmbeds(),
      GitHubEmbeds(),
      GitLabEmbeds(),
      CodePlaygroundEmbeds(),
      // Files and storage.
      DropboxEmbeds(),
      BoxEmbeds(),
      MegaEmbeds(),
      ICloudEmbeds(),
      JioCloudEmbeds(),
      FileTransferEmbeds(),
      // Reading: reference, writing and the news.
      WikipediaEmbeds(),
      MediumEmbeds(),
      SubstackEmbeds(),
      HackerNewsEmbeds(),
      StackExchangeEmbeds(),
      IMDbEmbeds(),
      GoodreadsEmbeds(),
      InternetArchiveEmbeds(),
      MsnEmbeds(),
      NewsEmbeds(),
      // Shopping, travel and dining.
      AmazonEmbeds(),
      FlipkartEmbeds(),
      ListingEmbeds.stores(),
      ListingEmbeds.places(),
      // File viewers.
      MicrosoftOfficeEmbeds(),
      OneDriveEmbeds(),
      PdfEmbeds(),
    ];

/// One way in from the `/` menu: a site by the name people look for, or any
/// site at all.
@immutable
class WebEmbedEntry {
  const WebEmbedEntry({
    required this.id,
    required this.name,
    required this.prompt,
    required this.hint,
    required this.description,
    this.provider,
    this.kind = '',
    this.kinds = const {},
    this.alsoAccepts = const {},
    this.keywords = const [],
  });

  /// Stored on the block that asks for the link, so never renamed. Empty for
  /// the entry that takes any site.
  final String id;

  /// What the `/` menu calls it.
  final String name;

  /// The site it asks for, or null for any registered site.
  final WebEmbedProvider? provider;

  /// The kind of link it is mostly for, which picks its icon and colour.
  final String kind;

  /// The kinds it asks for, when its site makes several products, like Sheets
  /// among Google's. Empty for any.
  final Set<String> kinds;

  /// Other sites whose links are what it asks for too, like Google News and
  /// MSN for a news article.
  final Set<String> alsoAccepts;

  /// The field's placeholder.
  final String prompt;

  /// The shapes of link it takes, shown under the field.
  final String hint;

  /// The `/` menu's line about it.
  final String description;

  final List<String> keywords;

  bool get isAnySite => provider == null;

  IconData get icon => provider?.iconFor(kind) ?? Icons.language_rounded;

  Color? get color => provider?.colorFor(kind);

  /// Whether [link] is what this entry asked for.
  ///
  /// A link to another registered site is still embedded when it is given;
  /// this only decides which copied link is worth offering.
  bool accepts(WebEmbedLink link) =>
      provider == null ||
      alsoAccepts.contains(link.provider.id) ||
      (link.provider.id == provider!.id &&
          (kinds.isEmpty || kinds.contains(link.kind)));
}

/// The `/` menu's ways in: any site first, then each site by name.
///
/// ⚠️ `Word`, `Excel`, `PowerPoint` and `PDF` already name the menu's file
/// pickers, `Google Drive`, `OneDrive` and `Box` its connected accounts,
/// `News` the news block and `Map` the app's own map, so these say `online`,
/// `link`, `article` and `Google Maps`.
const webEmbedEntries = <WebEmbedEntry>[
  WebEmbedEntry(
    id: '',
    name: 'Web embed',
    prompt: 'Paste a link or embed code',
    hint: 'Posts, videos, music, maps, documents, files, articles and '
        'products show live; any other link shows as a preview.',
    description: 'A post, video, song, document or article, live on the page',
    keywords: [
      'embed',
      'web embed',
      'website',
      'iframe',
      'link',
      'social',
      'post',
      'live',
    ],
  ),
  WebEmbedEntry(
    id: 'pinterest',
    name: 'Pinterest',
    provider: PinterestEmbeds(),
    kind: 'Pin',
    prompt: 'Paste a Pinterest pin, board or profile link',
    hint: 'pinterest.com/pin/…, a board, a profile or a pin.it link',
    description: 'A pin, board or profile',
    keywords: ['pinterest', 'pin', 'pins', 'board', 'pin.it', 'inspiration'],
  ),
  WebEmbedEntry(
    id: 'reddit',
    name: 'Reddit',
    provider: RedditEmbeds(),
    kind: 'Post',
    prompt: 'Paste a Reddit post or comment link',
    hint: 'reddit.com/r/…/comments/…, a comment, a share link or redd.it',
    description: 'A post, comment or community',
    keywords: ['reddit', 'subreddit', 'post', 'comment', 'thread', 'redd.it'],
  ),
  WebEmbedEntry(
    id: 'quora',
    name: 'Quora',
    provider: QuoraEmbeds(),
    kind: 'Answer',
    prompt: 'Paste a Quora answer, question or post link',
    hint: 'quora.com/…/answer/…, a question, or a post in a Space',
    description: 'An answer, question or post',
    keywords: ['quora', 'answer', 'answers', 'question', 'qa'],
  ),
  WebEmbedEntry(
    id: 'instagram',
    name: 'Instagram',
    provider: InstagramEmbeds(),
    kind: 'Post',
    prompt: 'Paste an Instagram post or reel link',
    hint: 'instagram.com/p/…, /reel/…, or the post’s embed code',
    description: 'A post or reel',
    keywords: ['instagram', 'insta', 'ig', 'reel', 'reels', 'photo'],
  ),
  WebEmbedEntry(
    id: 'youtube',
    name: 'YouTube',
    provider: YoutubeEmbeds(),
    kind: 'Video',
    prompt: 'Paste a YouTube video or Short link',
    hint: 'youtube.com/watch?v=…, youtu.be/… or youtube.com/shorts/…',
    description: 'A video or Short, played in place',
    keywords: ['youtube', 'video', 'shorts', 'short', 'yt'],
  ),
  WebEmbedEntry(
    id: 'google_maps',
    name: 'Google Maps',
    provider: GoogleMapsEmbeds(),
    kind: 'Place',
    prompt: 'Paste a Google Maps place, directions or share link',
    hint: 'google.com/maps/place/…, directions, maps.app.goo.gl, or the '
        'map’s embed code',
    description: 'A place, area or route on a live map',
    keywords: [
      'google maps',
      'maps',
      'location',
      'place',
      'directions',
      'address',
      'route',
    ],
  ),
  WebEmbedEntry(
    id: 'google_docs',
    name: 'Google Docs',
    provider: GoogleWorkspaceEmbeds(),
    kind: 'Document',
    kinds: {'Document'},
    prompt: 'Paste a Google Docs link',
    hint: 'docs.google.com/document/d/…, shared or published to the web',
    description: 'A Google document, readable in place',
    keywords: ['google docs', 'gdocs', 'gdoc', 'doc', 'document'],
  ),
  WebEmbedEntry(
    id: 'google_sheets',
    name: 'Google Sheets',
    provider: GoogleWorkspaceEmbeds(),
    kind: 'Spreadsheet',
    kinds: {'Spreadsheet'},
    prompt: 'Paste a Google Sheets link',
    hint: 'docs.google.com/spreadsheets/d/…; a #gid picks the sheet shown',
    description: 'A Google spreadsheet, live in place',
    keywords: ['google sheets', 'gsheets', 'sheet', 'spreadsheet', 'table'],
  ),
  WebEmbedEntry(
    id: 'google_slides',
    name: 'Google Slides',
    provider: GoogleWorkspaceEmbeds(),
    kind: 'Presentation',
    kinds: {'Presentation'},
    prompt: 'Paste a Google Slides link',
    hint: 'docs.google.com/presentation/d/…, shared or published to the web',
    description: 'A Google presentation you can click through',
    keywords: ['google slides', 'slides', 'deck', 'presentation'],
  ),
  WebEmbedEntry(
    id: 'google_forms',
    name: 'Google Forms',
    provider: GoogleWorkspaceEmbeds(),
    kind: 'Form',
    kinds: {'Form'},
    prompt: 'Paste a Google Forms link',
    hint: 'docs.google.com/forms/d/… or forms.gle/…',
    description: 'A form people can fill in on the page',
    keywords: ['google forms', 'form', 'survey', 'quiz', 'forms.gle'],
  ),
  WebEmbedEntry(
    id: 'word',
    name: 'Word online',
    provider: MicrosoftOfficeEmbeds(),
    kind: 'Document',
    kinds: {'Document'},
    prompt: 'Paste a Word link from OneDrive or SharePoint',
    hint: 'A OneDrive or SharePoint share link, 1drv.ms/w/…, or a public '
        '.docx address',
    description: 'A Word document, viewed in place',
    keywords: [
      'word',
      'word online',
      'microsoft word',
      'docx',
      'onedrive',
      'sharepoint',
      'office',
    ],
  ),
  WebEmbedEntry(
    id: 'excel',
    name: 'Excel online',
    provider: MicrosoftOfficeEmbeds(),
    kind: 'Workbook',
    kinds: {'Workbook'},
    prompt: 'Paste an Excel link from OneDrive or SharePoint',
    hint: 'A OneDrive or SharePoint share link, 1drv.ms/x/…, or a public '
        '.xlsx address',
    description: 'An Excel workbook, viewed in place',
    keywords: [
      'excel',
      'excel online',
      'microsoft excel',
      'xlsx',
      'workbook',
      'onedrive',
      'sharepoint',
      'office',
    ],
  ),
  WebEmbedEntry(
    id: 'powerpoint',
    name: 'PowerPoint online',
    provider: MicrosoftOfficeEmbeds(),
    kind: 'Presentation',
    kinds: {'Presentation'},
    prompt: 'Paste a PowerPoint link from OneDrive or SharePoint',
    hint: 'A OneDrive or SharePoint share link, 1drv.ms/p/…, or a public '
        '.pptx address',
    description: 'A PowerPoint deck you can click through',
    keywords: [
      'powerpoint',
      'powerpoint online',
      'microsoft powerpoint',
      'pptx',
      'ppt',
      'deck',
      'slides',
      'onedrive',
      'sharepoint',
      'office',
    ],
  ),
  WebEmbedEntry(
    id: 'x',
    name: 'X (Twitter)',
    provider: XEmbeds(),
    kind: 'Post',
    prompt: 'Paste an X post link',
    hint: 'x.com/…/status/…, twitter.com/…, a profile, or the post’s embed '
        'code',
    description: 'A post from X, formerly Twitter',
    keywords: ['x', 'twitter', 'tweet', 'post', 'thread'],
  ),
  WebEmbedEntry(
    id: 'linkedin',
    name: 'LinkedIn',
    provider: LinkedInEmbeds(),
    kind: 'Post',
    prompt: 'Paste a LinkedIn post, profile, company or job link',
    hint: 'linkedin.com/posts/…, /feed/update/…, /in/…, /company/… or '
        '/jobs/view/…',
    description: 'A post, profile, company or job',
    keywords: ['linkedin', 'post', 'profile', 'company', 'job', 'resume'],
  ),
  WebEmbedEntry(
    id: 'facebook',
    name: 'Facebook',
    provider: FacebookEmbeds(),
    kind: 'Post',
    prompt: 'Paste a Facebook post, video, reel or Page link',
    hint: 'facebook.com/…/posts/…, /watch?v=…, /reel/…, a Page, a share link '
        'or fb.watch',
    description: 'A post, video, reel or Page',
    keywords: ['facebook', 'fb', 'post', 'video', 'reel', 'page', 'group'],
  ),
  WebEmbedEntry(
    id: 'threads',
    name: 'Threads',
    provider: ThreadsEmbeds(),
    kind: 'Post',
    prompt: 'Paste a Threads post link',
    hint: 'threads.com/@…/post/… or threads.net/@…/post/…',
    description: 'A post from Threads',
    keywords: ['threads', 'post', 'meta'],
  ),
  WebEmbedEntry(
    id: 'tiktok',
    name: 'TikTok',
    provider: TikTokEmbeds(),
    kind: 'Video',
    prompt: 'Paste a TikTok video link',
    hint: 'tiktok.com/@…/video/…, vm.tiktok.com/… or a profile',
    description: 'A TikTok video, played in place',
    keywords: ['tiktok', 'tik tok', 'video', 'short video'],
  ),
  WebEmbedEntry(
    id: 'snapchat',
    name: 'Snapchat',
    provider: SnapchatEmbeds(),
    kind: 'Spotlight',
    prompt: 'Paste a Snapchat Spotlight, story or profile link',
    hint: 'snapchat.com/spotlight/…, /add/…, a story, a lens or t.snapchat.com',
    description: 'A Spotlight snap, story, lens or profile',
    keywords: ['snapchat', 'snap', 'spotlight', 'story', 'lens'],
  ),
  WebEmbedEntry(
    id: 'telegram',
    name: 'Telegram',
    provider: TelegramEmbeds(),
    kind: 'Post',
    prompt: 'Paste a post or channel link from Telegram',
    hint: 't.me/<channel>/<post> or t.me/<channel> for a public channel',
    description: 'A post or a public channel',
    keywords: ['telegram', 't.me', 'channel', 'post'],
  ),
  WebEmbedEntry(
    id: 'blind',
    name: 'Blind',
    provider: BlindEmbeds(),
    kind: 'Post',
    prompt: 'Paste a Blind post, company or topic link',
    hint: 'teamblind.com/post/…, /company/… or a topic',
    description: 'A post, company or topic from Blind',
    keywords: ['blind', 'teamblind', 'anonymous', 'workplace', 'salary'],
  ),
  WebEmbedEntry(
    id: 'spotify',
    name: 'Spotify',
    provider: SpotifyEmbeds(),
    kind: 'Track',
    prompt: 'Paste a Spotify song, album, playlist or podcast link',
    hint: 'open.spotify.com/track/…, /album/…, /playlist/…, /episode/… or '
        'spotify.link',
    description: 'Music or a podcast, played in place',
    keywords: ['spotify', 'music', 'song', 'album', 'playlist', 'podcast'],
  ),
  WebEmbedEntry(
    id: 'apple_music',
    name: 'Apple Music',
    provider: AppleMediaEmbeds(),
    kind: 'Song',
    prompt: 'Paste an Apple Music or Apple Podcasts link',
    hint: 'music.apple.com/… for a song, album or playlist, or '
        'podcasts.apple.com/…',
    description: 'A song, album, playlist or podcast, played in place',
    keywords: [
      'apple music',
      'apple podcasts',
      'itunes',
      'music',
      'song',
      'podcast',
    ],
  ),
  WebEmbedEntry(
    id: 'soundcloud',
    name: 'SoundCloud',
    provider: SoundCloudEmbeds(),
    kind: 'Track',
    prompt: 'Paste a SoundCloud track, playlist or artist link',
    hint: 'soundcloud.com/<artist>/<track>, /sets/… or on.soundcloud.com',
    description: 'A track, playlist or artist, played in place',
    keywords: ['soundcloud', 'music', 'track', 'mix', 'audio'],
  ),
  WebEmbedEntry(
    id: 'vimeo',
    name: 'Vimeo',
    provider: VimeoEmbeds(),
    kind: 'Video',
    prompt: 'Paste a Vimeo video link',
    hint: 'vimeo.com/<id> or player.vimeo.com/video/<id>',
    description: 'A Vimeo video, played in place',
    keywords: ['vimeo', 'video', 'film'],
  ),
  WebEmbedEntry(
    id: 'notion',
    name: 'Notion',
    provider: NotionEmbeds(),
    kind: 'Page',
    prompt: 'Paste a Notion page or database link',
    hint: 'notion.so/… or a page published to notion.site',
    description: 'A Notion page or database, readable in place',
    keywords: ['notion', 'page', 'wiki', 'database', 'notion.site'],
  ),
  WebEmbedEntry(
    id: 'figma',
    name: 'Figma',
    provider: FigmaEmbeds(),
    kind: 'Design',
    prompt: 'Paste a Figma design, prototype or FigJam link',
    hint: 'figma.com/design/…, /proto/…, /board/… or /slides/…',
    description: 'A design, prototype or board, live in place',
    keywords: ['figma', 'figjam', 'design', 'prototype', 'mockup'],
  ),
  WebEmbedEntry(
    id: 'canva',
    name: 'Canva',
    provider: CanvaEmbeds(),
    kind: 'Design',
    prompt: 'Paste a Canva design link',
    hint: 'A public view link, canva.com/design/…/view, or canva.link',
    description: 'A Canva design or presentation',
    keywords: ['canva', 'design', 'poster', 'presentation'],
  ),
  WebEmbedEntry(
    id: 'github',
    name: 'GitHub',
    provider: GitHubEmbeds(),
    kind: 'Repository',
    prompt: 'Paste a GitHub repository, issue, pull request or file link',
    hint: 'github.com/<owner>/<repo>, /issues/…, /pull/…, /blob/… or a gist',
    description: 'A repository, issue, pull request, file or gist',
    keywords: ['github', 'repository', 'repo', 'issue', 'pull request', 'gist'],
  ),
  WebEmbedEntry(
    id: 'gitlab',
    name: 'GitLab',
    provider: GitLabEmbeds(),
    kind: 'Repository',
    prompt: 'Paste a GitLab project, issue, merge request or file link',
    hint: 'gitlab.com/<group>/<project>, /-/issues/…, /-/merge_requests/… or '
        'a self-hosted gitlab server',
    description: 'A project, issue, merge request or file',
    keywords: ['gitlab', 'repository', 'merge request', 'issue', 'snippet'],
  ),
  WebEmbedEntry(
    id: 'google_drive',
    name: 'Google Drive link',
    provider: GoogleWorkspaceEmbeds(),
    kind: 'Folder',
    kinds: {'File', 'Folder'},
    prompt: 'Paste a Google Drive file or folder link',
    hint: 'drive.google.com/file/d/…, /drive/folders/… or open?id=…',
    description: 'A shared Drive file or folder, previewed in place',
    keywords: ['google drive', 'drive', 'gdrive', 'file', 'folder', 'link'],
  ),
  WebEmbedEntry(
    id: 'onedrive',
    name: 'OneDrive link',
    provider: OneDriveEmbeds(),
    kind: 'Folder',
    alsoAccepts: {'microsoft_office'},
    prompt: 'Paste a OneDrive or SharePoint share link',
    hint: '1drv.ms/…, onedrive.live.com/… or a SharePoint sharing link',
    description: 'A shared OneDrive file, folder or photo',
    keywords: ['onedrive', 'one drive', 'sharepoint', 'file', 'folder', 'link'],
  ),
  WebEmbedEntry(
    id: 'dropbox',
    name: 'Dropbox',
    provider: DropboxEmbeds(),
    kind: 'File',
    prompt: 'Paste a Dropbox file, folder or Paper link',
    hint: 'dropbox.com/scl/fi/…, /scl/fo/…, /s/…, a transfer or db.tt',
    description: 'A shared Dropbox file or folder, previewed in place',
    keywords: ['dropbox', 'file', 'folder', 'shared link', 'paper'],
  ),
  WebEmbedEntry(
    id: 'box',
    name: 'Box link',
    provider: BoxEmbeds(),
    kind: 'Shared link',
    prompt: 'Paste a Box shared link',
    hint: 'app.box.com/s/… or your company’s box.com address',
    description: 'A shared Box file or folder, previewed in place',
    keywords: ['box', 'box.com', 'file', 'folder', 'shared link'],
  ),
  WebEmbedEntry(
    id: 'mega',
    name: 'MEGA',
    provider: MegaEmbeds(),
    kind: 'File',
    prompt: 'Paste a MEGA file or folder link',
    hint: 'mega.nz/file/…#… or mega.nz/folder/…#…, with its key',
    description: 'A MEGA file or folder, previewed in place',
    keywords: ['mega', 'mega.nz', 'file', 'folder', 'cloud'],
  ),
  WebEmbedEntry(
    id: 'icloud',
    name: 'iCloud',
    provider: ICloudEmbeds(),
    kind: 'File',
    prompt: 'Paste an iCloud Drive, Pages, Numbers, Keynote or photos link',
    hint: 'icloud.com/iclouddrive/…, /pages/…, /numbers/…, /keynote/… or a '
        'shared album',
    description: 'A shared iCloud file, document or album',
    keywords: [
      'icloud',
      'apple',
      'icloud drive',
      'pages',
      'numbers',
      'keynote',
      'shared album',
    ],
  ),
  WebEmbedEntry(
    id: 'apple_notes',
    name: 'Apple Notes',
    provider: ICloudEmbeds(),
    kind: 'Note',
    kinds: {'Note'},
    prompt: 'Paste a shared Apple Notes link',
    hint: 'icloud.com/notes/…',
    description: 'A note shared from Apple Notes',
    keywords: ['apple notes', 'notes', 'note', 'icloud'],
  ),
  WebEmbedEntry(
    id: 'jiocloud',
    name: 'JioCloud',
    provider: JioCloudEmbeds(),
    kind: 'Shared file',
    prompt: 'Paste a JioCloud shared link',
    hint: 'jiocloud.com/s/?t=… or a transfer.jiocloud.com link',
    description: 'A file shared from JioCloud',
    keywords: ['jiocloud', 'jio cloud', 'jio', 'file', 'shared link'],
  ),
  WebEmbedEntry(
    id: 'news',
    name: 'News article',
    provider: NewsEmbeds(),
    kind: 'Article',
    alsoAccepts: {'google_news', 'msn'},
    prompt: 'Paste a news article link',
    hint: 'An article from BBC, Reuters, The Times of India, The Hindu, NDTV '
        'and other papers, Google News or MSN',
    description: 'A news article, readable in place',
    keywords: [
      'news',
      'article',
      'headline',
      'newspaper',
      'google news',
      'msn',
    ],
  ),
  WebEmbedEntry(
    id: 'wikipedia',
    name: 'Wikipedia',
    provider: WikipediaEmbeds(),
    kind: 'Article',
    prompt: 'Paste a Wikipedia article link',
    hint: '<language>.wikipedia.org/wiki/…',
    description: 'A Wikipedia article, with its summary',
    keywords: ['wikipedia', 'wiki', 'encyclopedia', 'reference'],
  ),
  WebEmbedEntry(
    id: 'amazon',
    name: 'Amazon',
    provider: AmazonEmbeds(),
    kind: 'Product',
    prompt: 'Paste an Amazon product link',
    hint: 'amazon.in/dp/…, amazon.com/…/dp/…, amzn.to/… or a wish list',
    description: 'A product from any Amazon store',
    keywords: ['amazon', 'product', 'shopping', 'buy', 'amzn'],
  ),
  WebEmbedEntry(
    id: 'flipkart',
    name: 'Flipkart',
    provider: FlipkartEmbeds(),
    kind: 'Product',
    prompt: 'Paste a Flipkart product link',
    hint: 'flipkart.com/…/p/itm…, dl.flipkart.com/s/… or fkrt.it',
    description: 'A product from Flipkart',
    keywords: ['flipkart', 'product', 'shopping', 'buy'],
  ),
  WebEmbedEntry(
    id: 'pdf',
    name: 'PDF link',
    provider: PdfEmbeds(),
    kind: 'Document',
    prompt: 'Paste a link to a PDF',
    hint: 'Any address ending in .pdf, or an arXiv paper',
    description: 'A PDF from the web, read in place',
    keywords: ['pdf', 'pdf link', 'document', 'paper', 'arxiv', 'report'],
  ),
];

/// The entry stored as [id], or the one for any site when it is unknown.
WebEmbedEntry webEmbedEntryById(String? id) => webEmbedEntries.firstWhere(
      (entry) => entry.id == id,
      orElse: () => webEmbedEntries.first,
    );
