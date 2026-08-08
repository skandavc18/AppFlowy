import 'package:appflowy/workspace/application/collections/album/album_controller.dart';
import 'package:appflowy/workspace/application/collections/album/album_media.dart';
import 'package:appflowy/workspace/application/collections/album/album_places.dart';
import 'package:appflowy/workspace/application/collections/album/album_state.dart';
import 'package:appflowy/workspace/application/collections/album/image_header.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:typed_data';

ViewPB _file(String id, String name) => ViewPB(
      id: id,
      name: name,
      layout: ViewLayoutPB.Document,
      extra: WorkspaceItemMetadata.file(
        contentKind: WorkspaceFileContentKind.binary,
        storageUrl: 'C:/albums/$name',
      ).mergeIntoExtra(''),
    );

AlbumMediaItem _item(String id, {DateTime? at}) => AlbumMediaItem(
      view: _file(id, '$id.jpg'),
      kind: AlbumMediaKind.image,
      path: 'C:/albums/$id.jpg',
      index: 0,
      modifiedAt: at,
    );

void main() {
  group('what makes an album repaint', () {
    AlbumMediaItem at(String id, String path) => AlbumMediaItem(
          view: _file(id, '$id.jpg'),
          kind: AlbumMediaKind.image,
          path: path,
          index: 0,
        );

    AlbumController controller() => AlbumController(
          initialState: const {},
          onPersist: (_) {},
          persistDebounce: const Duration(days: 1),
        );

    test('a picture arriving is reported even though the ids did not move', () {
      final album = controller();
      addTearDown(album.dispose);
      album.setItems([at('a', 'https://photos/a')]);

      var notified = 0;
      album.addListener(() => notified++);
      // What a hosted album does when a thumbnail lands: same id, new path.
      album.setItems([at('a', 'C:/cache/a.jpg')]);

      expect(notified, 1);
      expect(album.items.single.isLocal, isTrue);
    });

    test('setting the very same list again says nothing', () {
      final album = controller();
      addTearDown(album.dispose);
      album.setItems([at('a', 'C:/cache/a.jpg')]);

      var notified = 0;
      album.addListener(() => notified++);
      album.setItems([at('a', 'C:/cache/a.jpg')]);

      expect(notified, 0);
    });

    test('a picture the service refused is not the same as one still coming',
        () {
      final waiting = at('a', 'https://photos/a');
      final refused = AlbumMediaItem(
        view: _file('a', 'a.jpg'),
        kind: AlbumMediaKind.image,
        path: 'https://photos/a',
        index: 0,
        unavailable: true,
      );

      expect(waiting == refused, isFalse);
    });
  });

  group('album media', () {
    test('picks up pictures, video and audio and skips everything else', () {
      final items = albumMediaFrom([
        _file('a', 'beach.JPG'),
        _file('b', 'clip.mp4'),
        _file('c', 'song.mp3'),
        _file('d', 'notes.md'),
        ViewPB(id: 'e', name: 'A page', layout: ViewLayoutPB.Document),
      ]);

      expect(items.map((item) => item.id), ['a', 'b', 'c']);
      expect(items[0].kind, AlbumMediaKind.image);
      expect(items[1].kind, AlbumMediaKind.video);
      expect(items[2].kind, AlbumMediaKind.audio);
      expect(items[0].index, 0);
      expect(items[2].index, 2);
    });

    test('knows what shows and what plays', () {
      expect(AlbumMediaKind.image.isVisual, isTrue);
      expect(AlbumMediaKind.image.plays, isFalse);
      expect(AlbumMediaKind.video.isVisual, isTrue);
      expect(AlbumMediaKind.video.plays, isTrue);
      expect(AlbumMediaKind.audio.isVisual, isFalse);
      expect(AlbumMediaKind.audio.plays, isTrue);
    });

    test('a file kept in the cloud is not treated as a local path', () {
      final view = ViewPB(
        id: 'remote',
        name: 'sunset.jpg',
        layout: ViewLayoutPB.Document,
        extra: const WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl: 'https://example.com/sunset.jpg',
        ).mergeIntoExtra(''),
      );

      expect(albumMediaFrom([view]).single.isLocal, isFalse);
    });
  });

  group('album state', () {
    test('round trips settings, stars and the last picture seen', () {
      const state = AlbumState(
        settings: AlbumSettings(
          tileSize: AlbumTileSize.large,
          sort: AlbumSort.name,
          grouping: AlbumGrouping.day,
          showNames: true,
          slideshow: AlbumSlideshowSettings(
            seconds: 12,
            transition: AlbumSlideshowTransition.zoom,
            shuffle: true,
            loop: false,
          ),
        ),
        favourites: {'a', 'b'},
        selectedId: 'a',
      );

      final restored = AlbumState.fromJson(state.toJson());

      expect(restored.settings.tileSize, AlbumTileSize.large);
      expect(restored.settings.sort, AlbumSort.name);
      expect(restored.settings.grouping, AlbumGrouping.day);
      expect(restored.settings.showNames, isTrue);
      expect(restored.settings.slideshow.seconds, 12);
      expect(restored.settings.slideshow.shuffle, isTrue);
      expect(restored.settings.slideshow.loop, isFalse);
      expect(restored.favourites, {'a', 'b'});
      expect(restored.selectedId, 'a');
    });

    test('an empty envelope is a fresh album', () {
      final state = AlbumState.fromJson({});

      expect(state.settings.tileSize, AlbumTileSize.medium);
      expect(state.settings.sort, AlbumSort.newestFirst);
      expect(state.favourites, isEmpty);
      expect(state.selectedId, isNull);
    });

    test('the slide interval is clamped to something watchable', () {
      const slideshow = AlbumSlideshowSettings();

      expect(
        slideshow.copyWith(seconds: 999).seconds,
        AlbumSlideshowSettings.maximumSeconds,
      );
      expect(
        slideshow.copyWith(seconds: 0).seconds,
        AlbumSlideshowSettings.minimumSeconds,
      );
      expect(slideshow.interval, const Duration(seconds: 5));
    });

    test('stars toggle and forget media that has gone', () {
      const state = AlbumState(favourites: {'a'}, selectedId: 'gone');

      expect(state.toggleFavourite('a').favourites, isEmpty);
      expect(state.toggleFavourite('b').favourites, {'a', 'b'});

      final pruned = state.prunedTo(['a']);
      expect(pruned.favourites, {'a'});
      expect(pruned.selectedId, isNull);
      expect(identical(pruned.prunedTo(['a']), pruned), isTrue);
    });
  });

  group('album grouping', () {
    test('splits a run into headed months', () {
      final items = [
        _item('a', at: DateTime(2026, 7, 30)),
        _item('b', at: DateTime(2026, 7, 2)),
        _item('c', at: DateTime(2026, 6, 28)),
      ];

      final groups = groupAlbumMedia(
        items,
        AlbumGrouping.month,
        (item) => item.modifiedAt,
      );

      expect(groups.length, 2);
      expect(groups[0].items.length, 2);
      expect(groups[0].date, DateTime(2026, 7));
      expect(groups[1].items.single.id, 'c');
    });

    test('media with no date gets its own heading', () {
      final groups = groupAlbumMedia(
        [_item('a', at: DateTime(2026, 7, 30)), _item('b')],
        AlbumGrouping.day,
        (item) => item.modifiedAt,
      );

      expect(groups.length, 2);
      expect(groups.last.date, isNull);
    });

    test('no grouping keeps the album in one run', () {
      final groups = groupAlbumMedia(
        [_item('a', at: DateTime(2026, 7, 30)), _item('b')],
        AlbumGrouping.none,
        (item) => item.modifiedAt,
      );

      expect(groups.single.items.length, 2);
      expect(
        groupAlbumMedia(const [], AlbumGrouping.day, (_) => null),
        isEmpty,
      );
    });
  });

  group('album places', () {
    test('gathers pictures taken near each other into one pin', () {
      final places = clusterAlbumPlaces([
        AlbumPlacePoint(item: _item('a'), latitude: 51.507, longitude: -0.127),
        AlbumPlacePoint(item: _item('b'), latitude: 51.509, longitude: -0.130),
        AlbumPlacePoint(item: _item('c'), latitude: 48.858, longitude: 2.294),
      ]);

      expect(places.length, 2);
      // Sorted by how much was photographed there.
      expect(places.first.count, 2);
      expect(places.first.latitude, closeTo(51.508, 0.01));
      expect(places.last.count, 1);
    });

    test('the date line does not split one place in two', () {
      final places = clusterAlbumPlaces([
        AlbumPlacePoint(item: _item('a'), latitude: -16.5, longitude: 179.9),
        AlbumPlacePoint(item: _item('b'), latitude: -16.5, longitude: -179.9),
      ]);

      expect(places.length, 1);
    });

    test('impossible coordinates are dropped rather than plotted', () {
      final places = clusterAlbumPlaces([
        AlbumPlacePoint(item: _item('a'), latitude: 120, longitude: 0),
        AlbumPlacePoint(item: _item('b'), latitude: 0, longitude: 900),
      ]);

      expect(places, isEmpty);
      expect(clusterAlbumPlaces(const []), isEmpty);
    });

    test('a place reads as coordinates a person can use', () {
      final place = clusterAlbumPlaces([
        AlbumPlacePoint(
          item: _item('a'),
          latitude: 51.5074,
          longitude: -0.1278,
        ),
      ]).single;

      expect(place.label, '51.50740, -0.12780');
    });
  });

  group('image headers', () {
    test('reads the size out of a PNG header', () {
      final bytes = Uint8List(32);
      bytes.setAll(0, [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
      final data = ByteData.sublistView(bytes)
        ..setUint32(16, 1920)
        ..setUint32(20, 1080);

      final size = readImageHeaderSize(data.buffer.asUint8List());

      expect(size?.width, 1920);
      expect(size?.height, 1080);
      expect(size?.aspectRatio, closeTo(16 / 9, 0.001));
    });

    test('reads the size out of a JPEG frame header', () {
      final bytes = <int>[
        0xFF, 0xD8, // SOI
        0xFF, 0xE0, 0x00, 0x04, 0x00, 0x00, // a segment to skip
        0xFF, 0xC0, 0x00, 0x11, 0x08, // SOF0
        0x03, 0x20, // height 800
        0x04, 0xB0, // width 1200
        ...List.filled(10, 0),
      ];

      final size = readImageHeaderSize(Uint8List.fromList(bytes));

      expect(size?.width, 1200);
      expect(size?.height, 800);
    });

    test('reads the size out of a GIF header', () {
      final bytes = Uint8List(20);
      bytes.setAll(0, 'GIF89a'.codeUnits);
      ByteData.sublistView(bytes)
        ..setUint16(6, 640, Endian.little)
        ..setUint16(8, 480, Endian.little);

      final size = readImageHeaderSize(bytes);

      expect(size?.width, 640);
      expect(size?.height, 480);
    });

    test('says nothing rather than guessing at unknown bytes', () {
      expect(readImageHeaderSize(Uint8List(4)), isNull);
      expect(readImageHeaderSize(Uint8List(64)), isNull);
      expect(
        readImageHeaderSize(Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xDA])),
        isNull,
      );
    });
  });
}
