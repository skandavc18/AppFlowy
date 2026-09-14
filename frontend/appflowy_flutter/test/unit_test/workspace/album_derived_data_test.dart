import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_metadata.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AlbumController album;

  setUp(() {
    album = AlbumController(initialState: const {}, onPersist: (_) {});
  });
  tearDown(() => album.dispose());

  test('large album projections are reused between reads', () {
    album.setItems(List.generate(10000, (index) => _item('$index', index)));
    final visual = album.visual;
    final playable = album.playable;

    for (var read = 0; read < 100; read++) {
      expect(identical(album.visual, visual), isTrue);
      expect(identical(album.playable, playable), isTrue);
      expect(album.imageCount, 3334);
      expect(album.videoCount, 3333);
      expect(album.audioCount, 3333);
    }
  });

  test('selection and favourites do not invalidate media projections', () {
    album.setItems([_item('a', 0), _item('b', 1), _item('c', 2)]);
    final visual = album.visual;
    final playable = album.playable;
    album.select('b');
    album.toggleFavourite('b');

    expect(identical(album.visual, visual), isTrue);
    expect(identical(album.playable, playable), isTrue);
  });

  test('replacement, removal and sorting update projections and counts', () {
    album.setItems([_item('z', 0), _item('a', 1), _item('m', 2)]);
    album.updateSettings(album.settings.copyWith(sort: AlbumSort.name));
    expect(album.visual.map((item) => item.id), ['a', 'z']);
    expect(album.playable.map((item) => item.id), ['a', 'm']);

    album.setItems([_item('m', 0), _item('a', 2)]);
    expect(album.imageCount, 1);
    expect(album.videoCount, 0);
    expect(album.audioCount, 1);
    expect(album.visual.single.id, 'm');
    expect(album.playable.single.id, 'a');

    album.setItems([]);
    expect(album.visual, isEmpty);
    expect(album.playable, isEmpty);
    expect(album.imageCount + album.videoCount + album.audioCount, 0);
  });

  test('thumbnail arrival replaces the cached media projection', () {
    album.setItems([_item('photo', 0, path: 'https://example.invalid/photo')]);
    final old = album.visual;
    album.setItems([_item('photo', 0, path: 'C:/cache/photo.jpg')]);

    expect(identical(album.visual, old), isFalse);
    expect(album.visual.single.path, 'C:/cache/photo.jpg');
    expect(old.single.path, 'https://example.invalid/photo');
  });

  test('seeded dates still reorder an otherwise identical listing', () {
    final items = [_item('a', 0), _item('b', 1)];
    album.metadata.seed('a', AlbumMediaMetadata(capturedAt: DateTime(2026)));
    album.metadata.seed('b', AlbumMediaMetadata(capturedAt: DateTime(2025)));
    album.setItems(items);
    expect(album.visual.first.id, 'a');

    album.metadata.seed('b', AlbumMediaMetadata(capturedAt: DateTime(2027)));
    album.setItems(items);
    expect(album.visual.first.id, 'b');
  });

  test('mutating an input list cannot leave counters or projections stale', () {
    final items = [_item('a', 0)];
    album.setItems(items);
    items.add(_item('b', 1));
    expect(album.items, hasLength(1));
    expect(album.videoCount, 0);
    expect(album.visual, hasLength(1));

    album.setItems(items);
    expect(album.items, hasLength(2));
    expect(album.videoCount, 1);
    expect(album.visual, hasLength(2));
  });

  test('callers cannot mutate cached projections', () {
    album.setItems([_item('a', 0), _item('b', 1)]);
    expect(() => album.visual.clear(), throwsUnsupportedError);
    expect(() => album.playable.clear(), throwsUnsupportedError);
    expect(album.ordered, hasLength(2));
  });
}

AlbumMediaItem _item(String id, int index, {String? path}) => AlbumMediaItem(
      view: ViewPB(id: id, name: id),
      kind: AlbumMediaKind.values[index % AlbumMediaKind.values.length],
      path: path ?? 'C:/cache/$id',
      index: index,
    );
