import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_http.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/services/google_photos_provider.dart';
import 'package:flutter_test/flutter_test.dart';

const _source = CollectionSource(
  service: ProviderService.googlePhotos,
  connectionId: 'album-auth-test',
  remoteId: 'selection',
);

const _connection = ProviderConnection(
  id: 'album-auth-test',
  service: ProviderService.googlePhotos,
  accountLabel: 'Test photos',
);

void main() {
  group('a collection whose connection has expired', () {
    testWidgets('does not keep automatically refreshing a revoked sign in',
        (tester) async {
      final provider = _PhotoProvider()
        ..listingFailure = const ProviderFailure.authExpired();
      final controller = _controller(provider);
      try {
        await controller.load();
        expect(controller.status, ProviderStatus.authExpired);

        await tester.pump(const Duration(minutes: 30));
        expect(provider.listCalls, 1);
        expect(controller.status, ProviderStatus.authExpired);
      } finally {
        controller.dispose();
      }
    });

    testWidgets('keeps the listing when a later refresh needs sign in',
        (tester) async {
      final provider = _PhotoProvider();
      final controller = _controller(provider);
      try {
        await controller.load();
        await tester.pump();
        provider.listingFailure = const ProviderFailure.authExpired();
        await controller.refresh(silent: true);

        expect(controller.status, ProviderStatus.authExpired);
        expect(controller.nodes, hasLength(18));
        await tester.pump(const Duration(minutes: 30));
        expect(provider.listCalls, 2);
      } finally {
        controller.dispose();
      }
    });

    testWidgets('stops queued thumbnails and reports authentication failures',
        (tester) async {
      final provider = _PhotoProvider()
        ..thumbnailFailure = const ProviderFailure.authExpired();
      final controller = _controller(provider);
      try {
        await controller.load();
        await tester.pump();

        expect(controller.status, ProviderStatus.authExpired);
        expect(provider.thumbnailCalls, lessThanOrEqualTo(6));
        expect(controller.thumbnailRefused('photo-17'), isTrue);
        expect(controller.nodes, hasLength(18));

        await tester.pump(const Duration(minutes: 30));
        expect(provider.listCalls, 1);
        expect(provider.thumbnailCalls, lessThanOrEqualTo(6));
      } finally {
        controller.dispose();
      }
    });

    testWidgets('a failed download also publishes the sign-in state',
        (tester) async {
      final provider = _PhotoProvider()
        ..downloadFailure = const ProviderFailure.authExpired();
      final controller = _controller(provider);
      try {
        await controller.load();
        await tester.pump();
        expect(await controller.materialize(controller.nodes.first), isNull);
        expect(controller.status, ProviderStatus.authExpired);

        await tester.pump(const Duration(minutes: 30));
        expect(provider.listCalls, 1);
      } finally {
        controller.dispose();
      }
    });

    testWidgets('still retries a temporary network failure', (tester) async {
      final provider = _PhotoProvider()
        ..listingFailure = const ProviderFailure.offline();
      final controller = _controller(provider);
      try {
        await controller.load();
        expect(controller.status, ProviderStatus.offline);
        provider.listingFailure = null;

        await tester.pump(const Duration(minutes: 10));
        expect(provider.listCalls, 2);
        expect(controller.status, ProviderStatus.ready);
      } finally {
        controller.dispose();
      }
    });

    testWidgets('one missing thumbnail does not invalidate the connection',
        (tester) async {
      final provider = _PhotoProvider()
        ..thumbnailFailure = const ProviderFailure.notFound();
      final controller = _controller(provider);
      try {
        await controller.load();
        await tester.pump();

        expect(controller.status, ProviderStatus.ready);
        expect(provider.thumbnailCalls, 18);
        expect(controller.thumbnailRefused('photo-17'), isTrue);
      } finally {
        controller.dispose();
      }
    });

    testWidgets('changes to another account do not retry an expired account',
        (tester) async {
      final connections = _Connections()..replace(_connection);
      final provider = _PhotoProvider()
        ..listingFailure = const ProviderFailure.authExpired();
      final controller = ProviderController(
        collectionId: 'album',
        source: _source,
        provider: provider,
        cache: _MemoryCache(),
        connections: connections,
      );
      try {
        await controller.load();
        connections.replace(
          const ProviderConnection(
            id: 'another-account',
            service: ProviderService.googlePhotos,
            accountLabel: 'Another account',
          ),
        );
        await tester.pump(const Duration(minutes: 10));

        expect(provider.disposed, isFalse);
        expect(provider.listCalls, 1);
        expect(controller.status, ProviderStatus.authExpired);
      } finally {
        controller.dispose();
      }
    });

    testWidgets('old thumbnail failures cannot undo a successful reconnect',
        (tester) async {
      final pending = Completer<String?>();
      final connections = _Connections()..replace(_connection);
      final provider = _PhotoProvider()
        ..thumbnailLoader = (node) => node.id == 'photo-0'
            ? Future.error(const ProviderFailure.authExpired())
            : pending.future;
      final renewed = _PhotoProvider();
      ProviderRegistry.register(
        ProviderService.googlePhotos,
        (_, __) => renewed,
      );
      addTearDown(ProviderRegistry.reset);
      final controller = ProviderController(
        collectionId: 'album',
        source: _source,
        provider: provider,
        cache: _MemoryCache(),
        connections: connections,
      );
      try {
        await controller.load();
        await tester.pump();
        expect(controller.status, ProviderStatus.authExpired);

        connections.replace(_connection.copyWith(accountLabel: 'Signed in'));
        await tester.pump();
        expect(provider.disposed, isTrue);
        expect(controller.status, ProviderStatus.ready);
        expect(renewed.listCalls, 1);

        pending.completeError(const ProviderFailure.authExpired());
        await tester.pump();
        expect(controller.status, ProviderStatus.ready);
        expect(controller.failure, isNull);
        expect(controller.nodes, hasLength(18));
      } finally {
        controller.dispose();
      }
    });
  });

  group('Google Photos media authentication', () {
    GooglePhotosProvider photos(_MediaTransport transport) =>
        GooglePhotosProvider(
          connection: _connection,
          source: _source,
          transport: transport,
          cache: _MemoryCache(),
        );

    final expired = isA<ProviderFailure>().having(
      (failure) => failure.status,
      'status',
      ProviderStatus.authExpired,
    );

    test('an anonymous 403 cannot hide an expired sign in', () async {
      final transport = _MediaTransport();
      final provider = photos(transport);
      await expectLater(
        provider.fetchMedia('https://example.test/photo'),
        throwsA(expired),
      );
      expect(transport.requests, [true, false]);
    });

    test('thumbnail authentication failures reach the controller', () async {
      final provider = photos(_MediaTransport());
      await expectLater(
        provider.thumbnailPath(
          const ProviderNode(
            id: 'photo',
            name: 'Photo.jpg',
            kind: ProviderNodeKind.image,
            thumbnailUrl: 'https://example.test/thumbnail',
          ),
        ),
        throwsA(expired),
      );
    });

    test('downloads retain the authenticated failure too', () async {
      final provider = photos(_MediaTransport());
      await expectLater(
        provider.downloadMedia('https://example.test/photo', File('unused')),
        throwsA(expired),
      );
    });

    test('successful media-auth fallback is still remembered', () async {
      final transport = _MediaTransport()
        ..authenticatedFailure = const ProviderFailure.permissionDenied()
        ..anonymousFailure = null;
      final provider = photos(transport);
      expect(await provider.fetchMedia('https://example.test/photo'), [1]);
      expect(await provider.fetchMedia('https://example.test/next'), [1]);
      expect(transport.requests, [true, false, false]);
    });

    test('a missing thumbnail is not an authentication failure', () async {
      final transport = _MediaTransport()
        ..authenticatedFailure = const ProviderFailure.notFound();
      final provider = photos(transport);
      expect(
        await provider.thumbnailPath(
          const ProviderNode(
            id: 'missing',
            name: 'Missing.jpg',
            kind: ProviderNodeKind.image,
            thumbnailUrl: 'https://example.test/missing',
          ),
        ),
        isNull,
      );
      expect(transport.requests, [true]);
    });
  });
}

ProviderController _controller(_PhotoProvider provider) => ProviderController(
      collectionId: 'album',
      source: _source,
      provider: provider,
      cache: _MemoryCache(),
    );

class _MemoryCache extends Fake implements ProviderCache {
  final _values = <String, Object?>{};

  @override
  Future<CachedValue?> readJson(String cacheKey, String name) async {
    final value = _values['$cacheKey/$name'];
    return value == null ? null : CachedValue(value, DateTime.now());
  }

  @override
  Future<void> writeJson(String cacheKey, String name, Object? value) async {
    _values['$cacheKey/$name'] = value;
  }

  @override
  Future<String?> thumbnailPath(
    String cacheKey,
    String remoteId, {
    String extension = 'jpg',
  }) async =>
      null;
}

class _PhotoProvider extends CollectionProvider {
  ProviderFailure? listingFailure;
  ProviderFailure? thumbnailFailure;
  ProviderFailure? downloadFailure;
  Future<String?> Function(ProviderNode)? thumbnailLoader;
  int listCalls = 0;
  int thumbnailCalls = 0;
  bool disposed = false;

  @override
  ProviderService get service => _source.service;

  @override
  CollectionSource get source => _source;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  String get originLabel => 'Test photos';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    listCalls++;
    final failure = listingFailure;
    if (failure != null) {
      throw failure;
    }
    return ProviderPage(
      nodes: [
        for (var i = 0; i < 18; i++)
          ProviderNode(
            id: 'photo-$i',
            name: 'Photo $i.jpg',
            kind: ProviderNodeKind.image,
            thumbnailUrl: 'https://example.test/thumb/$i',
          ),
      ],
    );
  }

  @override
  Future<String?> thumbnailPath(ProviderNode node) async {
    thumbnailCalls++;
    final loader = thumbnailLoader;
    if (loader != null) {
      return loader(node);
    }
    final failure = thumbnailFailure;
    if (failure != null) {
      throw failure;
    }
    return null;
  }

  @override
  Future<String?> materialize(ProviderNode node) async {
    final failure = downloadFailure;
    if (failure != null) {
      throw failure;
    }
    return null;
  }

  @override
  Future<Uint8List> readBytes(ProviderNode node, {int maxBytes = 32 << 20}) =>
      throw UnimplementedError();

  @override
  void dispose() => disposed = true;
}

class _Connections extends Fake implements ProviderConnections {
  final _values = <String, ProviderConnection>{};
  final _listeners = <void Function()>[];

  void replace(ProviderConnection connection) {
    _values[connection.id] = connection;
    for (final listener in _listeners.toList()) {
      listener();
    }
  }

  @override
  ProviderConnection? byId(String id) => _values[id];

  @override
  Future<void> ensureLoaded() async {}

  @override
  void addListener(void Function() listener) => _listeners.add(listener);

  @override
  void removeListener(void Function() listener) => _listeners.remove(listener);
}

class _MediaTransport extends Fake implements ProviderTransport {
  ProviderFailure? authenticatedFailure = const ProviderFailure.authExpired();
  ProviderFailure? anonymousFailure = const ProviderFailure.permissionDenied();
  final requests = <bool>[];

  void _request(bool authenticated) {
    requests.add(authenticated);
    final failure = authenticated ? authenticatedFailure : anonymousFailure;
    if (failure != null) {
      throw failure;
    }
  }

  @override
  Future<Uint8List> bytes(
    String url, {
    Map<String, String>? headers,
    int maxBytes = ProviderTransport.defaultMaxBytes,
    bool authenticated = true,
  }) async {
    _request(authenticated);
    return Uint8List.fromList([1]);
  }

  @override
  Future<void> download(
    String url,
    File destination, {
    Map<String, String>? headers,
    int maxBytes = 512 << 20,
    void Function(int received, int? total)? onProgress,
    bool authenticated = true,
  }) async =>
      _request(authenticated);
}
