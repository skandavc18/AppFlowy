import 'package:appflowy/shared/icon_emoji_picker/icon.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';

const appFlowyVividIconPackId = 'appflowy_vivid';
const appFlowyVividIconGroupPrefix = '${appFlowyVividIconPackId}_';

/// A curated, compiled-in collection, built only when explicitly requested.
/// Saved icons resolve synchronously without opening the picker or reading an
/// asset. This is original AppFlowy artwork, not a subset of Fluent Emoji.
List<IconGroup> get appFlowyVividIconGroups => _vividIconGroups;

// Dart initializes this private top-level final lazily, on its first read.
final List<IconGroup> _vividIconGroups = List.unmodifiable([
  for (final category in _catalogues.entries)
    IconGroup(
      name: '$appFlowyVividIconGroupPrefix${category.key}',
      icons: List.unmodifiable([
        for (final entry in category.value.entries)
          Icon(
            name: entry.key,
            keywords: List.unmodifiable([
              ...entry.value,
              if (category.key != 'essentials') category.key,
            ]),
            content: vividIconSvg(entry.key)!,
          ),
      ]),
    )
      ..packId = appFlowyVividIconPackId
      ..groupPrefix = appFlowyVividIconGroupPrefix
      ..isColorful = true,
]);

// These group/name identities are persisted. Add entries, never rename them.
const _catalogue = <String, List<String>>{
  'home': ['house', 'building', 'welcome'],
  'book': ['closed book', 'reading', 'journal', 'notebook'],
  'bolt': ['lightning', 'electricity', 'energy', 'quick'],
  'coffee': ['coffee mug', 'cup', 'cafe', 'drink', 'break'],
  'target': ['bullseye', 'goal', 'focus', 'aim'],
  'rocket': ['launch', 'space', 'startup', 'ship'],
  'seedling': ['sprout', 'plant', 'growth', 'nature', 'leaf'],
  'bulb': ['light bulb', 'idea', 'inspiration', 'lightbulb'],
  'sparkles': ['stars', 'magic', 'shine', 'new'],
  'planet': ['saturn', 'orbit', 'space', 'universe'],
  'books': ['library', 'study', 'knowledge', 'stack'],
  'camera': ['photo', 'photography', 'picture', 'album'],
  'music': ['notes', 'audio', 'song', 'sound'],
  'calendar': ['date', 'schedule', 'plan', 'event'],
  'folder': ['files', 'organize', 'collection', 'documents'],
  'chart': ['graph', 'analytics', 'data', 'progress'],
  'globe': ['earth', 'world', 'travel', 'geography'],
  'palette': ['art', 'paint', 'design', 'creative', 'color'],
  'gem': ['diamond', 'jewel', 'crystal', 'treasure'],
  'trophy': ['award', 'win', 'success', 'achievement'],
  'heart': ['love', 'favorite', 'health', 'care'],
  'cloud': ['weather', 'sky', 'sun', 'dream'],
  'mountain': ['outdoors', 'adventure', 'hike', 'landscape'],
  'compass': ['direction', 'explore', 'navigation', 'journey'],
  'page': ['note', 'text', 'document page'],
  'file': ['attachment', 'generic file', 'binary'],
  'pdf': ['document', 'portable document', 'paper'],
  'document': ['word', 'docx', 'odt', 'rtf'],
  'spreadsheet': ['excel', 'xlsx', 'ods', 'sheet'],
  'presentation': ['powerpoint', 'pptx', 'odp', 'deck'],
  'archive': ['zip', 'tar', 'rar', '7z', 'compressed'],
  'code-file': ['source', 'program', 'dart', 'python'],
  'markdown': ['md', 'readme', 'markup'],
  'html-file': ['html', 'web', 'markup'],
  'json-file': ['json', 'data', 'configuration'],
  'notebook': ['jupyter', 'ipynb', 'code', 'cells'],
  'csv': ['csv', 'tsv', 'delimited', 'data'],
  'image': ['photo', 'picture', 'png', 'jpeg'],
  'video': ['movie', 'film', 'mp4'],
  'album': ['photos', 'pictures', 'media collection'],
  'repository': ['git', 'source', 'code folder', 'project'],
  'database': ['data collection', 'storage', 'tables'],
  'bookmark': ['link', 'saved website', 'reading'],
  'mail': ['email', 'inbox', 'mailbox', 'collection'],
  'table': ['grid', 'rows', 'columns', 'database view'],
  'board': ['kanban', 'tasks', 'cards'],
  'chat': ['conversation', 'messages'],
  'ai-chat': ['assistant', 'conversation', 'artificial intelligence'],
  'map': ['places', 'location', 'geography'],
  'slides': ['carousel', 'deck', 'rows'],
  'timeline': ['schedule', 'dates', 'project'],
  'feed': ['articles', 'news', 'reading'],
  'form': ['answers', 'checklist', 'fields'],
  'gallery': ['cards', 'grid', 'pictures'],
  'dashboard': ['workspace', 'layout', 'widgets'],
  'canvas': ['board', 'drawing', 'layout'],
};

// Essentials is deliberately not redistributed: all 56 saved group/name pairs
// keep their original artwork and ordering. New names belong to exactly one
// stable category. Category keywords make the whole category searchable without
// padding the picker with recolored aliases or generated utility variants.
const _catalogues = <String, Map<String, List<String>>>{
  'essentials': _catalogue,
  'navigation': {
    'search': ['magnifying glass', 'magnifier', 'find', 'lookup', 'discover'],
    'settings': ['gear', 'cog', 'preferences', 'configuration', 'configure'],
    'bell': ['notification', 'notifications', 'alert', 'reminder', 'ringer'],
    'pin': ['pushpin', 'thumbtack', 'pinned', 'keep', 'priority'],
    'history': ['recent', 'restore', 'revisions', 'past', 'undo'],
    'clock': ['time', 'alarm', 'timer', 'hours', 'deadline'],
    'download': ['save locally', 'receive', 'export', 'arrow down', 'offline'],
    'upload': ['send', 'publish', 'import', 'arrow up', 'cloud transfer'],
  },
  'editing': {
    'plus': ['add', 'create', 'new', 'insert', 'positive'],
    'copy': ['duplicate', 'clone', 'pages', 'copies'],
    'trash': ['delete', 'remove', 'bin', 'discard', 'rubbish'],
    'pen': ['write', 'edit', 'fountain pen', 'nib', 'signature'],
    'text': ['typography', 'font', 'title', 'heading', 'letter'],
    'number': ['numeric', 'digits', 'integer', 'count', '123'],
    'checkbox': ['check', 'checked', 'done', 'complete', 'todo'],
    'selection': ['select', 'cursor', 'marquee', 'bounds', 'resize'],
    'scissors': ['cut', 'trim', 'snip', 'craft'],
    'refresh': ['reload', 'sync', 'update'],
    'link': ['url', 'chain', 'website'],
  },
  'data': {
    'relation': ['related', 'link records', 'connect', 'nodes', 'relationship'],
    'attachment': ['paperclip', 'attach', 'enclosure', 'clip', 'paper clip'],
    'sigma': ['sum', 'summation', 'formula', 'calculate', 'aggregate'],
    'filter': ['funnel', 'refine', 'criteria', 'query'],
    'sort': ['order', 'arrange', 'ascending'],
    'select': ['dropdown', 'option', 'choice'],
    'connections': ['network', 'hub', 'linked'],
    'pie-chart': ['proportion', 'percentage', 'statistics', 'analytics'],
  },
  'work': {
    'user': ['person', 'profile', 'account', 'member', 'avatar'],
    'users': ['people', 'team', 'members', 'collaborate', 'group'],
    'workspace': ['desk', 'office', 'workstation', 'desktop', 'organization'],
    'briefcase': ['business', 'career', 'job', 'professional'],
    'clipboard': ['checklist', 'tasks', 'review', 'inspection'],
    'flag': ['milestone', 'finish', 'report', 'mark'],
    'handshake': ['agreement', 'partnership', 'cooperate', 'deal'],
    'wallet': ['finance', 'money', 'payment'],
    'coins': ['savings', 'budget', 'investment'],
    'calculator': ['accounting', 'arithmetic', 'total'],
    'store': ['shop', 'retail', 'commerce'],
  },
  'security': {
    'lock': ['private', 'password', 'locked', 'restricted', 'secure'],
    'key': ['unlock', 'access', 'credential', 'permission'],
    'shield': ['protect', 'verified', 'safety', 'trusted', 'privacy'],
  },
  'learning': {
    'graduation-cap': [
      'education',
      'school',
      'university',
      'graduate',
      'study',
    ],
    'microscope': ['biology', 'laboratory', 'research', 'science', 'specimen'],
    'telescope': ['astronomy', 'stargazing', 'observation', 'space'],
    'ruler': ['measure', 'geometry', 'triangle', 'length', 'set square'],
    'atom': ['physics', 'chemistry', 'electron', 'nucleus', 'science'],
    'abacus': ['arithmetic', 'mathematics', 'counting', 'beads'],
    'graduation': ['education', 'ceremony', 'degree'],
    'science': ['laboratory', 'flask', 'experiment'],
    'backpack': ['school bag', 'student', 'college'],
    'pencil-ruler': ['geometry', 'design', 'drawing'],
  },
  'nature': {
    'flower': ['blossom', 'petals', 'garden', 'bloom', 'botany'],
    'tree': ['forest', 'woodland', 'canopy', 'ecology', 'park'],
    'leaf': ['foliage', 'green', 'environment', 'organic'],
    'sun': ['sunshine', 'daylight', 'summer', 'sunny', 'weather'],
    'moon': ['crescent', 'night', 'lunar', 'sleep', 'moonlight'],
    'butterfly': ['insect', 'wings', 'wildlife', 'pollinator'],
    'cactus': ['desert', 'succulent', 'plant'],
    'rainbow': ['weather', 'spectrum', 'color'],
  },
  'travel': {
    'suitcase': ['luggage', 'packing', 'vacation', 'trip', 'baggage'],
    'airplane': ['flight', 'airport', 'plane', 'aviation'],
    'bicycle': ['bike', 'cycling', 'pedal', 'commute'],
    'train': ['railway', 'railroad', 'station', 'transit', 'rail'],
    'sailboat': ['sailing', 'boat', 'harbor', 'sea', 'ocean'],
    'tent': ['camping', 'campsite', 'outdoors', 'shelter'],
    'beach': ['umbrella', 'summer', 'holiday'],
  },
  'food': {
    'apple': ['fruit', 'orchard', 'snack', 'nutrition'],
    'carrot': ['vegetable', 'produce', 'harvest', 'cooking'],
    'bread': ['bakery', 'loaf', 'baking', 'toast', 'breakfast'],
    'cheese': ['dairy', 'wedge', 'picnic', 'cheddar'],
    'bowl': ['noodles', 'soup', 'lunch', 'dinner', 'meal'],
    'teapot': ['tea', 'brew', 'hospitality', 'drink', 'kettle'],
    'pizza': ['meal', 'slice', 'restaurant'],
    'tea': ['drink', 'cup', 'relax'],
    'cake': ['birthday', 'dessert', 'celebration'],
  },
  'health': {
    'stethoscope': ['doctor', 'medical', 'diagnosis', 'heartbeat', 'clinic'],
    'bandage': ['plaster', 'wound', 'healing', 'care'],
    'pill': ['medicine', 'capsule', 'pharmacy', 'prescription'],
    'dumbbell': ['fitness', 'gym', 'exercise', 'strength', 'workout'],
    'first-aid': ['medical kit', 'emergency', 'treatment', 'supplies'],
    'tooth': ['dental', 'dentist', 'hygiene', 'enamel'],
    'meditation': ['yoga', 'mindfulness', 'calm'],
    'running': ['exercise', 'sport', 'jogging'],
  },
  'technology': {
    'puzzle': ['extension', 'plugin', 'integration', 'jigsaw', 'piece'],
    'laptop': ['computer', 'portable', 'notebook computer', 'hardware'],
    'keyboard': ['typing', 'keys', 'input', 'shortcut'],
    'mouse': ['pointer', 'click', 'scroll', 'peripheral'],
    'headphones': ['listen', 'headset', 'podcast', 'audio', 'sound'],
    'microchip': ['processor', 'cpu', 'silicon', 'circuit', 'computing'],
    'wifi': ['wireless', 'internet', 'network', 'connection', 'signal'],
    'battery': ['power', 'charge', 'charging', 'capacity'],
    'robot': ['automation', 'bot', 'machine', 'assistant'],
    'terminal': ['command line', 'console', 'shell', 'prompt', 'developer'],
    'gamepad': ['gaming', 'controller', 'play'],
  },
};
