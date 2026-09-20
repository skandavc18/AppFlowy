import 'package:appflowy/shared/icon_emoji_picker/icon.dart';
import 'package:appflowy/shared/icon_emoji_picker/vivid_icon_artwork.dart';

const appFlowyVividIconPackId = 'appflowy_vivid';
const appFlowyVividIconGroupPrefix = '${appFlowyVividIconPackId}_';

/// A small, compiled-in collection, built only when explicitly requested.
/// Saved icons resolve synchronously without opening the picker or reading an
/// asset. This is original AppFlowy artwork, not a subset of Fluent Emoji.
List<IconGroup> get appFlowyVividIconGroups => _vividIconGroups;

// Dart initializes this private top-level final lazily, on its first read.
final List<IconGroup> _vividIconGroups = List.unmodifiable([
  IconGroup(
    name: '${appFlowyVividIconGroupPrefix}essentials',
    icons: List.unmodifiable([
      for (final entry in _catalogue.entries)
        Icon(
          name: entry.key,
          keywords: entry.value,
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
};
