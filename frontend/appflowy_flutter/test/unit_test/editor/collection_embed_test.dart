import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_registry.dart';
import 'package:appflowy/plugins/document/presentation/editor_plugins/collection_embed/collection_embed_settings.dart';
import 'package:appflowy/workspace/application/collections/collection.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('collection embed settings', () {
    test('a page with no stored settings gets the type defaults', () {
      const settings = CollectionEmbedSettings();
      expect(settings.size, CollectionEmbedSize.medium);
      expect(settings.style, isNull);
      expect(settings.itemLimit, isNull);
      expect(settings.sort, CollectionEmbedSort.manual);
      expect(settings.showMetadata, isTrue);
      expect(settings.background, CollectionEmbedBackground.surface);
    });

    test('only what differs from the default is written', () {
      expect(
        const CollectionEmbedSettings().toJson(),
        {'size': 'medium'},
      );
      expect(
        const CollectionEmbedSettings(
          size: CollectionEmbedSize.large,
          style: 'bookshelf',
          itemLimit: 8,
          sort: CollectionEmbedSort.newest,
          showMetadata: false,
          background: CollectionEmbedBackground.flush,
          coverId: 'v1',
          columns: 4,
        ).toJson(),
        {
          'size': 'large',
          'style': 'bookshelf',
          'items': 8,
          'sort': 'newest',
          'meta': false,
          'background': 'flush',
          'cover': 'v1',
          'columns': 4,
        },
      );
    });

    test('a stored embed round trips', () {
      const settings = CollectionEmbedSettings(
        size: CollectionEmbedSize.compact,
        style: 'slideshow',
        itemLimit: 12,
        sort: CollectionEmbedSort.name,
        showMetadata: false,
        background: CollectionEmbedBackground.tinted,
        coverId: 'photo-3',
        columns: 3,
      );
      expect(CollectionEmbedSettings.fromJson(settings.toJson()), settings);
    });

    test('anything unreadable falls back rather than failing the block', () {
      expect(
        CollectionEmbedSettings.fromJson('not a map'),
        const CollectionEmbedSettings(),
      );
      expect(
        CollectionEmbedSettings.fromJson(
            {'size': 'enormous', 'sort': 'colour'}),
        const CollectionEmbedSettings(),
      );
      // An empty style is not a style; it must fall back to the type default.
      expect(CollectionEmbedSettings.fromJson({'style': ''}).style, isNull);
    });

    test('item and column counts are clamped to what a widget can show', () {
      expect(CollectionEmbedSettings.fromJson({'items': 900}).itemLimit, 60);
      expect(CollectionEmbedSettings.fromJson({'items': 0}).itemLimit, 1);
      expect(CollectionEmbedSettings.fromJson({'columns': 99}).columns, 8);
    });

    test('clearing a value is not the same as leaving it alone', () {
      const settings = CollectionEmbedSettings(itemLimit: 6, columns: 3);
      expect(settings.copyWith(clearItemLimit: true).itemLimit, isNull);
      expect(settings.copyWith(clearItemLimit: true).columns, 3);
      expect(settings.copyWith(clearColumns: true).columns, isNull);
      expect(settings.copyWith().itemLimit, 6);
    });
  });

  group('collection embed registry', () {
    test('every collection type says how it appears inside a page', () {
      for (final kind in CollectionKind.values) {
        final definition = CollectionEmbedRegistry.definitionFor(kind);
        expect(definition.kind, kind, reason: '$kind has no widget');
        expect(definition.styles, isNotEmpty);
        expect(definition.defaultStyle, definition.styles.first.id);
      }
    });

    test('a plain folder falls back to the generic widget', () {
      final definition = CollectionEmbedRegistry.definitionFor(null);
      expect(definition.kind, isNull);
      expect(definition.styles, isNotEmpty);
    });

    test('an unknown style resolves to the type default', () {
      final definition =
          CollectionEmbedRegistry.definitionFor(CollectionKind.album);
      expect(definition.styleFor('nonsense').id, definition.defaultStyle);
      expect(definition.styleFor(null).id, definition.defaultStyle);
    });

    test('a size is a height, and the sizes are ordered', () {
      final definition =
          CollectionEmbedRegistry.definitionFor(CollectionKind.book);
      final compact = definition.heightFor(CollectionEmbedSize.compact);
      final medium = definition.heightFor(CollectionEmbedSize.medium);
      final large = definition.heightFor(CollectionEmbedSize.large);
      expect(compact, lessThan(medium));
      expect(medium, lessThan(large));
    });

    test('the database widget is seamless by design', () {
      final definition =
          CollectionEmbedRegistry.definitionFor(CollectionKind.database);
      expect(definition.flush, isTrue);
      expect(definition.showsHeading, isFalse);
    });
  });
}
