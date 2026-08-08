import 'dart:typed_data';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';

/// An album that lives on somebody's own Immich server.
///
/// Immich authenticates with an API key the person creates on their own
/// server, sent as `x-api-key`. There is no OAuth application to register and
/// no password ever leaves the dialog, which is why this is the one service
/// here that works with nothing else set up.
class ImmichAlbumProvider extends RemoteCollectionProvider
    implements AlbumProvider, ExternalFileProvider {
  ImmichAlbumProvider({
    required super.connection,
    required super.source,
    super.transport,
    super.cache,
  });

  /// Immich has no server-side cap on an album, so a wall has to have one.
  static const maxAssetsPerAlbum = 5000;

  @override
  ProviderService get service => ProviderService.immich;

  @override
  String get apiBase {
    final host = connection.host.trim();
    final trimmed =
        host.endsWith('/') ? host.substring(0, host.length - 1) : host;
    return trimmed.endsWith('/api') ? trimmed : '$trimmed/api';
  }

  @override
  String get originLabel {
    final host = Uri.tryParse(connection.host)?.host ?? connection.host;
    final album = source.remoteName;
    return album.isEmpty ? host : '$album · $host';
  }

  /// Immich wants its key on every request, media included.
  @override
  Map<String, String> get mediaHeaders => const <String, String>{};

  @override
  bool authenticatesMedia(String url) => url.startsWith(apiBase);

  @override
  Future<void> probe() async {
    final me = jsonMap(await transport.json('$apiBase/users/me'));
    if (me.isEmpty) {
      throw const ProviderFailure.authExpired(
        'Immich did not recognise the key.',
      );
    }
    // An Immich API key can be issued read-only, and the server does not say
    // which; favouriting is the only write offered, and a refusal there is
    // harmless and reported honestly.
    capabilities = const ProviderCapabilities(
      canSearch: true,
      canFavourite: true,
    );
  }

  @override
  Future<List<ProviderNode>> albums() async {
    final albums = jsonList(await transport.json('$apiBase/albums'));
    return [for (final album in albums) _album(album)];
  }

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    final albumId = parentId ?? source.remoteId;
    if (albumId.isEmpty) {
      // No album bound yet: the collection shows the account's albums so one
      // can be picked, which is the same listing the binding dialog uses.
      return ProviderPage(nodes: await albums());
    }

    final album = jsonMap(
      await transport.json(
        '$apiBase/albums/$albumId',
        query: const {'withoutAssets': 'false'},
      ),
    );
    final assets = jsonList(album['assets']);
    return ProviderPage(
      nodes: [
        for (final asset in assets.take(maxAssetsPerAlbum)) _asset(asset),
      ],
    );
  }

  @override
  Future<ProviderPage> search(String query, {String? pageToken}) async {
    final answer = jsonMap(
      await transport.json(
        '$apiBase/search/metadata',
        method: 'POST',
        body: {
          'query': query,
          'size': 120,
          if (source.remoteId.isNotEmpty) 'albumIds': [source.remoteId],
        },
      ),
    );
    final assets = jsonList(jsonMap(answer['assets'])['items']);
    return ProviderPage(nodes: [for (final asset in assets) _asset(asset)]);
  }

  @override
  Future<List<ProviderNode>> media({int limit = 2000}) async {
    final page = await list();
    return page.nodes.length > limit
        ? page.nodes.sublist(0, limit)
        : page.nodes;
  }

  @override
  Future<ProviderNode> setFavourite(ProviderNode node, bool favourite) async {
    await transport.json(
      '$apiBase/assets',
      method: 'PUT',
      body: {
        'ids': [node.id],
        'isFavorite': favourite,
      },
    );
    return node.copyWith(favourite: favourite);
  }

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

  ProviderNode _album(Map<String, dynamic> album) {
    final id = jsonString(album['id']);
    final thumbnail = jsonString(album['albumThumbnailAssetId']);
    return ProviderNode(
      id: id,
      name: jsonString(album['albumName'], 'Album'),
      kind: ProviderNodeKind.album,
      childCount: jsonInt(album['assetCount']),
      createdAt: jsonDate(album['createdAt']),
      modifiedAt: jsonDate(album['updatedAt']),
      description: jsonString(album['description']),
      thumbnailUrl: thumbnail.isEmpty ? null : _thumbnailUrl(thumbnail),
      webUrl: '${_serverBase()}/albums/$id',
    );
  }

  ProviderNode _asset(Map<String, dynamic> asset) {
    final id = jsonString(asset['id']);
    final exif = jsonMap(asset['exifInfo']);
    final type = jsonString(asset['type']).toUpperCase();
    final name = jsonString(
      asset['originalFileName'],
      jsonString(asset['originalPath']).split('/').last,
    );

    return ProviderNode(
      id: id,
      parentId: source.remoteId.isEmpty ? null : source.remoteId,
      name: name.isEmpty ? id : name,
      kind: switch (type) {
        'VIDEO' => ProviderNodeKind.video,
        'AUDIO' => ProviderNodeKind.audio,
        _ => ProviderNodeKind.image,
      },
      mimeType: jsonString(asset['originalMimeType']).isEmpty
          ? null
          : jsonString(asset['originalMimeType']),
      byteSize: jsonInt(exif['fileSizeInByte']),
      createdAt: jsonDate(asset['fileCreatedAt']) ??
          jsonDate(exif['dateTimeOriginal']),
      modifiedAt: jsonDate(asset['fileModifiedAt']),
      thumbnailUrl: _thumbnailUrl(id),
      downloadUrl: '$apiBase/assets/$id/original',
      webUrl: '${_serverBase()}/photos/$id',
      width: jsonInt(exif['exifImageWidth']),
      height: jsonInt(exif['exifImageHeight']),
      durationMs: _durationMs(jsonString(asset['duration'])),
      favourite: asset['isFavorite'] == true,
      latitude: jsonDouble(exif['latitude']),
      longitude: jsonDouble(exif['longitude']),
      description: jsonString(exif['description']),
      extra: {
        if (jsonString(exif['make']).isNotEmpty) 'camera_make': exif['make'],
        if (jsonString(exif['model']).isNotEmpty) 'camera_model': exif['model'],
        if (exif['fNumber'] != null) 'aperture': exif['fNumber'],
        if (exif['iso'] != null) 'iso': exif['iso'],
        if (jsonString(exif['city']).isNotEmpty) 'city': exif['city'],
        if (jsonString(exif['country']).isNotEmpty) 'country': exif['country'],
      },
    );
  }

  /// The small preview, never the original. A wall of originals off a home
  /// server would saturate the connection and show nothing any sooner.
  String _thumbnailUrl(String assetId) =>
      '$apiBase/assets/$assetId/thumbnail?size=preview';

  String _serverBase() {
    final base = apiBase;
    return base.endsWith('/api') ? base.substring(0, base.length - 4) : base;
  }

  /// Immich reports a duration as `00:00:12.345`.
  static int? _durationMs(String value) {
    if (value.isEmpty) {
      return null;
    }
    final parts = value.split(':');
    if (parts.length != 3) {
      return null;
    }
    final hours = int.tryParse(parts[0]) ?? 0;
    final minutes = int.tryParse(parts[1]) ?? 0;
    final seconds = double.tryParse(parts[2]) ?? 0;
    return (hours * 3600 + minutes * 60) * 1000 + (seconds * 1000).round();
  }

  @override
  Future<Uint8List> readBytes(
    ProviderNode node, {
    int maxBytes = 64 << 20,
  }) =>
      super.readBytes(node, maxBytes: maxBytes);
}
