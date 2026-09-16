import 'package:appflowy/shared/icon_emoji_picker/default_icon_artwork.dart';
import 'package:appflowy/shared/icon_emoji_picker/icon.dart';

const appFlowyDefaultIconPackId = 'appflowy_default';
const appFlowyDefaultIconGroupPrefix = '${appFlowyDefaultIconPackId}_';

bool isAppFlowyDefaultIconGroup(String groupName) =>
    groupName.startsWith(appFlowyDefaultIconGroupPrefix);

/// Built into Dart so a saved default renders immediately, including on a cold
/// launch before the picker or any asset-backed icon pack has been opened.
/// The namespaced group/name pair uses the existing icon persistence format.
final List<IconGroup> appFlowyDefaultIconGroups = List.unmodifiable(
  _catalogue.entries.map(
    (group) => IconGroup(
      name: '$appFlowyDefaultIconGroupPrefix${group.key}',
      icons: group.value.entries
          .map(
            (entry) => Icon(
              name: entry.key,
              keywords: [entry.value, ...?_searchTerms[entry.key]],
              content: defaultIconSvg(entry.value)!,
            ),
          )
          .toList(growable: false),
    )
      ..packId = appFlowyDefaultIconPackId
      ..groupPrefix = appFlowyDefaultIconGroupPrefix,
  ),
);

// User-facing identities are independent of the compatibility artwork keys.
// Do not rename these entries: saved selections and recents reference them.
const _catalogue = <String, Map<String, String>>{
  'collections': {
    'book': 'book-open',
    'album': 'images',
    'repository': 'git-branch',
    'database': 'database',
    'bookmark': 'link-simple',
    'mail': 'envelope-simple',
    'folder': 'folder',
    'open-folder': 'folder-open',
  },
  'pages_and_views': {
    'page': 'file-text',
    'table': 'table',
    'board': 'kanban',
    'calendar': 'calendar-blank',
    'chat': 'chat-circle',
    'chart': 'chart-bar',
    'map': 'map-trifold',
    'slides': 'presentation-chart',
    'timeline': 'graph',
    'feed': 'article',
    'form': 'list-checks',
    'gallery': 'squares-four',
  },
  'files': {
    'file': 'file',
    'pdf': 'file-pdf',
    'document': 'file-doc',
    'spreadsheet': 'file-xls',
    'presentation': 'file-ppt',
    'archive': 'file-zip',
    'code': 'file-code',
    'csv': 'file-csv',
    'image': 'image',
    'video': 'film-strip',
    'audio': 'music-note',
  },
  'navigation': {
    'search': 'magnifying-glass',
    'new-page': 'note-pencil',
    'home': 'house',
    'add': 'plus',
    'more': 'dots-three',
    'expand': 'caret-right',
    'dropdown': 'caret-down',
    'switcher': 'caret-up-down',
    'sidebar': 'sidebar-simple',
    'trash': 'trash',
    'templates': 'layout',
    'extensions': 'puzzle-piece',
    'pin': 'push-pin',
    'settings': 'gear',
    'notifications': 'bell',
  },
};

const _searchTerms = <String, List<String>>{
  'book': ['closed', 'reading', 'chapters', 'library'],
  'album': ['photos', 'pictures', 'media'],
  'repository': ['git', 'source', 'code', 'project'],
  'mail': ['email', 'inbox', 'mailbox'],
  'page': ['document', 'note', 'text'],
  'document': ['word', 'docx', 'text'],
  'spreadsheet': ['excel', 'xlsx', 'sheet'],
  'presentation': ['powerpoint', 'pptx', 'deck'],
  'archive': ['zip', 'compressed'],
  'image': ['photo', 'picture'],
  'video': ['movie', 'film'],
  'audio': ['music', 'sound'],
};
