import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';
import 'package:flutter/foundation.dart';

/// One round of picking, as Google models it.
@immutable
class PhotosPickingSession {
  const PhotosPickingSession({
    required this.id,
    required this.pickerUri,
    required this.mediaItemsSet,
    this.pollInterval = const Duration(seconds: 3),
    this.timeout = const Duration(minutes: 10),
  });

  final String id;

  /// Where the person chooses their photos: Google's own interface.
  final String pickerUri;

  /// Whether they have finished choosing.
  final bool mediaItemsSet;

  final Duration pollInterval;
  final Duration timeout;
}

/// A Google Photos selection, read through the Picker API.
///
/// ⚠️ This cannot list somebody's albums, and no scope will make it. Google
/// removed `photoslibrary.readonly` on 31 March 2025: `albums.list` and
/// `mediaItems.search` now answer `403 PERMISSION_DENIED` for every
/// application, and the Library API only sees what the application itself
/// created.
///
/// The supported route is the Picker API, and it inverts who chooses: AppFlowy
/// opens Google's own picker, the person selects there, and the selection comes
/// back as a session. An "album" here is therefore a set somebody picked —
/// which is also the more private arrangement, since AppFlowy never sees the
/// rest of the library.
class GooglePhotosProvider extends RemoteCollectionProvider
    implements AlbumProvider, ExternalFileProvider {
  GooglePhotosProvider({
    required super.connection,
    required super.source,
    super.transport,
    super.cache,
  });

  static const _pageSize = 100;

  /// Big enough for a large tile on a dense screen, small enough that a
  /// hundred of them is not a download.
  static const _thumbnailSpec = '=w640-h640';

  /// A full-size render, for a picture that is going to be looked at.
  ///
  /// Bounded rather than original because Google returns a JPEG for any sized
  /// request, and that is the whole point for the formats below.
  static const _displaySpec = '=w2560-h2560';

  /// What this application can actually decode and draw.
  ///
  /// ⚠️ A phone photograph is usually HEIC, and Flutter has no HEIC decoder,
  /// so asking for `=d` fetches megabytes that can only ever render as a
  /// broken image. Asking for a size instead makes Google transcode to JPEG.
  static const _decodable = <String>{
    'image/jpeg',
    'image/jpg',
    'image/png',
    'image/gif',
    'image/webp',
    'image/bmp',
  };

  /// Where the picked session id lives on the collection's binding.
  static const sessionOption = 'session';

  @override
  ProviderService get service => ProviderService.googlePhotos;

  @override
  String get apiBase => 'https://photospicker.googleapis.com/v1';

  String get sessionId =>
      source.option<String>(sessionOption) ?? source.remoteId;

  @override
  String get originLabel {
    final name = source.remoteName;
    return name.isEmpty
        ? 'Google Photos'
        : '$name · ${connection.accountLabel}';
  }

  /// ⚠️ The opposite of the old Library API: a Picker `baseUrl` REQUIRES the
  /// access token, and answers 403 without it.
  @override
  bool authenticatesMedia(String url) => true;

  @override
  Future<void> probe() async {
    capabilities = const ProviderCapabilities();
    if (sessionId.isEmpty) {
      return;
    }
    // A session is not permanent. When it lapses the collection says so and
    // offers to pick again, rather than looking empty for no reason.
    await readSession(sessionId);
  }

  // --- Picking --------------------------------------------------------------

  Future<PhotosPickingSession> createSession() async {
    final answer = jsonMap(
      await transport.json(
        '$apiBase/sessions',
        method: 'POST',
        body: const <String, Object?>{},
      ),
    );
    final session = _session(answer);
    if (session.id.isEmpty || session.pickerUri.isEmpty) {
      throw const ProviderFailure(
        ProviderStatus.error,
        detail: 'Google Photos did not open a picker.',
      );
    }
    return session;
  }

  Future<PhotosPickingSession> readSession(String id) async =>
      _session(jsonMap(await transport.json('$apiBase/sessions/$id')));

  /// Ends a selection. Google keeps the picked set alive with the session, so
  /// dropping it is what disconnecting has to mean.
  Future<void> deleteSession(String id) async {
    try {
      await transport.send('$apiBase/sessions/$id', method: 'DELETE');
    } on ProviderFailure {
      // A session that has already lapsed is not worth reporting.
    }
  }

  PhotosPickingSession _session(Map<String, dynamic> answer) {
    final polling = jsonMap(answer['pollingConfig']);
    return PhotosPickingSession(
      id: jsonString(answer['id']),
      pickerUri: jsonString(answer['pickerUri']),
      mediaItemsSet: answer['mediaItemsSet'] == true,
      pollInterval:
          _duration(polling['pollInterval']) ?? const Duration(seconds: 3),
      timeout: _duration(polling['timeoutIn']) ?? const Duration(minutes: 10),
    );
  }

  /// Google writes a duration as `"3.5s"`.
  static Duration? _duration(Object? value) {
    if (value is! String || !value.endsWith('s')) {
      return null;
    }
    final seconds = double.tryParse(value.substring(0, value.length - 1));
    return seconds == null
        ? null
        : Duration(milliseconds: (seconds * 1000).round());
  }

  // --- Reading --------------------------------------------------------------

  /// Nothing to list: Google no longer lets an application see somebody's
  /// albums. Binding a collection runs a picking session instead.
  @override
  Future<List<ProviderNode>> albums() async => const <ProviderNode>[];

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    final id = sessionId;
    if (id.isEmpty) {
      return ProviderPage.empty;
    }

    final answer = jsonMap(
      await transport.json(
        '$apiBase/mediaItems',
        query: {
          'sessionId': id,
          'pageSize': '$_pageSize',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        },
      ),
    );

    return ProviderPage(
      nodes: [
        for (final item in jsonList(answer['mediaItems'])) _mediaItem(item),
      ],
      nextPageToken: jsonString(answer['nextPageToken']),
    );
  }

  @override
  Future<ProviderPage> search(String query, {String? pageToken}) async {
    // The Picker API has no search, and the person already chose what is here,
    // so the only honest search is over what came back.
    final needle = query.toLowerCase();
    final all = await listAll();
    return ProviderPage(
      nodes: [
        for (final node in all)
          if (node.name.toLowerCase().contains(needle)) node,
      ],
    );
  }

  @override
  Future<List<ProviderNode>> media({int limit = 2000}) => listAll(limit: limit);

  // --- Embeds ---------------------------------------------------------------

  @override
  Future<ProviderPage> browse({String? parentId, String? pageToken}) =>
      list(parentId: parentId, pageToken: pageToken);

  @override
  Future<ProviderPage> find(String query, {String? pageToken}) =>
      search(query, pageToken: pageToken);

  @override
  Future<String?> materializeFile(ProviderNode node) => materialize(node);

  // --- Mapping --------------------------------------------------------------

  ProviderNode _mediaItem(Map<String, dynamic> item) => readMediaItem(item);

  /// How one picked item is read. Static because it depends on nothing but the
  /// answer, which is what makes the format rules testable on their own.
  @visibleForTesting
  static ProviderNode readMediaItem(Map<String, dynamic> item) {
    final file = jsonMap(item['mediaFile']);
    final metadata = jsonMap(file['mediaFileMetadata']);
    final photo = jsonMap(metadata['photoMetadata']);
    final video = jsonMap(metadata['videoMetadata']);
    final baseUrl = jsonString(file['baseUrl']);
    final mime = jsonString(file['mimeType']);
    final isVideo = jsonString(item['type']).toUpperCase() == 'VIDEO' ||
        mime.startsWith('video/');

    final name = jsonString(file['filename'], isVideo ? 'Video' : 'Photo');
    // A picture in a format with no decoder here is taken as a JPEG render
    // instead of as the original, because the original could never be shown.
    final rendered = !isVideo &&
        baseUrl.isNotEmpty &&
        !_decodable.contains(mime.toLowerCase());

    return ProviderNode(
      id: jsonString(item['id']),
      name: rendered ? _asJpeg(name) : name,
      kind: isVideo ? ProviderNodeKind.video : ProviderNodeKind.image,
      mimeType: rendered ? 'image/jpeg' : (mime.isEmpty ? null : mime),
      createdAt: jsonDate(item['createTime']),
      thumbnailUrl: baseUrl.isEmpty ? null : '$baseUrl$_thumbnailSpec',
      // `=d` is the original, asked for only when something is opened or saved.
      downloadUrl: baseUrl.isEmpty
          ? null
          : isVideo
              ? '$baseUrl=dv'
              : '$baseUrl${rendered ? _displaySpec : '=d'}',
      width: jsonInt(metadata['width']),
      height: jsonInt(metadata['height']),
      readOnly: true,
      extra: {
        if (rendered && mime.isNotEmpty) 'original_mime': mime,
        if (jsonString(metadata['cameraMake']).isNotEmpty)
          'camera_make': metadata['cameraMake'],
        if (jsonString(metadata['cameraModel']).isNotEmpty)
          'camera_model': metadata['cameraModel'],
        if (photo['apertureFNumber'] != null)
          'aperture': photo['apertureFNumber'],
        if (photo['isoEquivalent'] != null) 'iso': photo['isoEquivalent'],
        if (photo['focalLength'] != null) 'focal_length': photo['focalLength'],
        if (photo['exposureTime'] != null) 'exposure': photo['exposureTime'],
        if (video['fps'] != null) 'fps': video['fps'],
      },
    );
  }

  static String _asJpeg(String name) {
    final dot = name.lastIndexOf('.');
    final stem = dot > 0 ? name.substring(0, dot) : name;
    return '$stem.jpg';
  }
}
