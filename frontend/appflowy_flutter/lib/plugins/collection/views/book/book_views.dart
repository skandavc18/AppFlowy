import 'package:appflowy/generated/locale_keys.g.dart';
import 'package:appflowy/plugins/collection/views/book/book_contents_view.dart';
import 'package:appflowy/plugins/collection/views/book/book_reader_view.dart';
import 'package:appflowy/workspace/application/collections/collection_registry.dart';
import 'package:flutter/material.dart';

/// The key the whole book model is stored under, so the reader and the
/// contents page read and write one state rather than two.
const bookStateKey = 'book';

abstract final class BookViewIds {
  static const reader = 'book_reader';
  static const contents = 'book_contents';
}

List<CollectionViewDefinition> bookCollectionViews() => [
      CollectionViewDefinition(
        id: BookViewIds.reader,
        labelKey: LocaleKeys.collections_book_reader,
        icon: Icons.chrome_reader_mode_rounded,
        builder: (context, collection) =>
            BookReaderView(collection: collection),
      ),
      CollectionViewDefinition(
        id: BookViewIds.contents,
        labelKey: LocaleKeys.collections_book_contents,
        icon: Icons.toc_rounded,
        builder: (context, collection) =>
            BookContentsView(collection: collection),
      ),
    ];
