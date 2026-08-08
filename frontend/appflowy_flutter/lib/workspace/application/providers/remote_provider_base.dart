import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_http.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy_backend/log.dart';

/// What every service-backed provider shares.
///
/// Fetching a thumbnail and putting a file on disk are the same job whichever
/// service is answering, and both are entirely about the cache, so they live
/// here once rather than seven times.
abstract class RemoteCollectionProvider extends CollectionProvider {
  RemoteCollectionProvider({
    required this.connection,
    required CollectionSource source,
    ProviderTransport? transport,
    ProviderCache? cache,
  })  : _source = source,
        _cache = cache ?? ProviderCache.instance,
        transport = transport ?? ProviderTransport(connectionId: connection.id);

  final ProviderConnection connection;
  final ProviderTransport transport;
  final ProviderCache _cache;

  CollectionSource _source;
  ProviderCapabilities _capabilities = ProviderCapabilities.readOnly;
  bool _ready = false;

  @override
  CollectionSource get source => _source;

  @override
  ProviderCapabilities get capabilities =>
      _source.readOnly ? _capabilities.readOnlyCopy() : _capabilities;

  ProviderCache get cache => _cache;

  /// Narrowed by [ensureReady] from what the service says the account can do.
  set capabilities(ProviderCapabilities value) => _capabilities = value;

  set source(CollectionSource value) => _source = value;

  /// The base address of the service, honouring a self-hosted host.
  String get apiBase;

  /// Proves the connection once per provider instance.
  ///
  /// A subclass overrides [probe] rather than this, so the "only ask once"
  /// rule is not something every service has to remember.
  @override
  Future<void> ensureReady() async {
    if (_ready) {
      return;
    }
    await probe();
    _ready = true;
  }

  /// Asks the service who we are and what we may do.
  Future<void> probe();

  /// The extra headers this service wants on a media request. Most want none;
  /// Immich wants its API key on the thumbnail request too.
  Map<String, String> get mediaHeaders => const <String, String>{};

  /// Whether a media URL needs this connection's credentials. A signed URL,
  /// such as the ones Google hands out, must be fetched *without* them — some
  /// services refuse a request that carries both.
  bool authenticatesMedia(String url) => url.startsWith(apiBase);

  /// Which way round the media host actually wanted it, once one worked.
  bool? _mediaAuthWorks;

  /// Reads a media URL, trying the other way round if the host refuses.
  ///
  /// Whether a signed media URL wants the access token is a per-service
  /// decision the documentation does not always get right, and being wrong
  /// means every thumbnail in a collection silently fails. So the first
  /// refusal is retried the other way and the answer is remembered.
  Future<Uint8List> fetchMedia(
    String url, {
    int maxBytes = ProviderTransport.defaultMaxBytes,
  }) async {
    final preferred = _mediaAuthWorks ?? authenticatesMedia(url);
    try {
      final bytes = await transport.bytes(
        url,
        headers: mediaHeaders,
        maxBytes: maxBytes,
        authenticated: preferred,
      );
      _mediaAuthWorks = preferred;
      return bytes;
    } on ProviderFailure catch (failure) {
      if (failure.status != ProviderStatus.permissionDenied &&
          failure.status != ProviderStatus.authExpired) {
        rethrow;
      }
      final bytes = await transport.bytes(
        url,
        headers: mediaHeaders,
        maxBytes: maxBytes,
        authenticated: !preferred,
      );
      Log.info(
        'Media on ${Uri.parse(url).host} wants '
        '${preferred ? 'no' : 'an'} access token.',
      );
      _mediaAuthWorks = !preferred;
      return bytes;
    }
  }

  @override
  Future<Uint8List> readBytes(
    ProviderNode node, {
    int maxBytes = ProviderTransport.defaultMaxBytes,
  }) async {
    final url = node.downloadUrl;
    if (url == null || url.isEmpty) {
      throw const ProviderFailure.notFound('This object has no content.');
    }
    return fetchMedia(url, maxBytes: maxBytes);
  }

  @override
  Future<String?> thumbnailPath(ProviderNode node) async {
    final cached = await _cache.thumbnailPath(_source.cacheKey, node.id);
    if (cached != null) {
      return cached;
    }

    final url = node.thumbnailUrl;
    if (url == null || url.isEmpty) {
      return null;
    }

    try {
      final bytes = await fetchMedia(
        url,
        maxBytes: ProviderCache.maxThumbnailBytes,
      );
      return _cache.writeThumbnail(_source.cacheKey, node.id, bytes);
    } on ProviderFailure catch (failure) {
      if (failure.status != ProviderStatus.notFound) {
        Log.warn(
          'Unable to read a thumbnail from ${Uri.parse(url).host}: '
          '${failure.status.name}',
        );
      }
      return null;
    } catch (error) {
      Log.warn('Unable to read a thumbnail: $error');
      return null;
    }
  }

  @override
  Future<String?> materialize(ProviderNode node) async {
    if (node.isFolder) {
      return null;
    }

    final file = await _cache.contentFile(_source.cacheKey, node.id, node.name);
    if (file.existsSync()) {
      final size = node.byteSize;
      // Trust the cached copy only when its size matches what the service now
      // reports; a file edited elsewhere would otherwise read as stale for ever.
      if (size == null || file.lengthSync() == size) {
        return file.path;
      }
    }

    final url = node.downloadUrl;
    if (url == null || url.isEmpty) {
      return null;
    }

    try {
      await transport.download(
        url,
        file,
        headers: mediaHeaders,
        authenticated: authenticatesMedia(url),
      );
      return file.path;
    } on ProviderFailure {
      rethrow;
    } catch (error) {
      Log.warn('Unable to download remote content: $error');
      return null;
    }
  }

  /// Reads a file that is already on disk, for an upload.
  Future<Uint8List> readLocal(String path) => File(path).readAsBytes();

  @override
  void dispose() => transport.close();
}

/// A `application/json` list, whatever key the service buried it under.
List<Map<String, dynamic>> jsonList(Object? value, [String? key]) {
  final source = key == null
      ? value
      : value is Map
          ? value[key]
          : null;
  if (source is! List) {
    return const <Map<String, dynamic>>[];
  }
  return [
    for (final entry in source)
      if (entry is Map) Map<String, dynamic>.from(entry),
  ];
}

Map<String, dynamic> jsonMap(Object? value) =>
    value is Map ? Map<String, dynamic>.from(value) : <String, dynamic>{};

String jsonString(Object? value, [String fallback = '']) =>
    value is String ? value : fallback;

int? jsonInt(Object? value) => switch (value) {
      final int value => value,
      final double value => value.round(),
      final String value => int.tryParse(value),
      _ => null,
    };

double? jsonDouble(Object? value) => switch (value) {
      final double value => value,
      final int value => value.toDouble(),
      final String value => double.tryParse(value),
      _ => null,
    };

DateTime? jsonDate(Object? value) =>
    value is String && value.isNotEmpty ? DateTime.tryParse(value) : null;
