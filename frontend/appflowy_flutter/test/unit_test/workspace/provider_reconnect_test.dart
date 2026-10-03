import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/connect_service.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_flow.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_cache.dart';
import 'package:appflowy/workspace/application/providers/provider_controller.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_registry.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _album = CollectionSource(
  service: ProviderService.googlePhotos,
  connectionId: 'googlephotos|sub-1',
  remoteId: 'selection',
);

/// One Google account as it was stored before one sign in covered a family:
/// a connection per capability, each under an id of its own.
const _legacy = [
  ProviderConnection(
    id: 'googledrive|sub-1',
    service: ProviderService.googleDrive,
    accountLabel: 'me@gmail.com',
    accountId: 'sub-1',
  ),
  ProviderConnection(
    id: 'googlephotos|sub-1',
    service: ProviderService.googlePhotos,
    accountLabel: 'me@gmail.com',
    accountId: 'sub-1',
  ),
];

const _lapsed = ProviderCredentials(accessToken: 'lapsed');

void main() {
  group('signing in again for a collection', () {
    test('renews every id the account was signed in under', () async {
      final storage = _MemoryKeyValue();
      final connections = ProviderConnections(storage: storage);
      await connections.upsertAll(_legacy, _lapsed);
      final browser = _Browser();
      final connector = await _connector(
        connections,
        signedInAs: 'sub-1',
        browser: browser,
      );

      await connector.connectWithOAuth(
        service: ProviderService.googlePhotos,
        reconnectId: _album.connectionId,
      );

      // The browser is pointed at the account the album reads through.
      expect(browser.loginHints, ['sub-1']);
      expect(await _token(connections, 'googlephotos|sub-1'), 'fresh');
      expect(await _token(connections, 'googledrive|sub-1'), 'fresh');
      // Renewed in place: no third connection beside the two.
      expect(
        connections.all.map((c) => c.id),
        unorderedEquals(['googledrive|sub-1', 'googlephotos|sub-1']),
      );
      final written = jsonDecode(
        (await storage.get(ProviderConnections.storageKey))!,
      ) as List;
      expect(written, hasLength(2));
    });

    test('refuses a different account and changes nothing', () async {
      final connections = ProviderConnections(storage: _MemoryKeyValue());
      await connections.upsertAll(_legacy, _lapsed);
      final connector = await _connector(connections, signedInAs: 'sub-2');

      await expectLater(
        connector.connectWithOAuth(
          service: ProviderService.googlePhotos,
          reconnectId: _album.connectionId,
        ),
        throwsA(
          isA<ProviderFailure>().having(
            (failure) => failure.detail,
            'detail',
            oauthWrongAccount,
          ),
        ),
      );

      expect(await _token(connections, 'googlephotos|sub-1'), 'lapsed');
      expect(await _token(connections, 'googledrive|sub-1'), 'lapsed');
      expect(
        connections.all.map((c) => c.id),
        unorderedEquals(['googledrive|sub-1', 'googlephotos|sub-1']),
      );
    });

    test('gives a removed connection back the id its album names', () async {
      final connections = ProviderConnections(storage: _MemoryKeyValue());
      final browser = _Browser();
      final connector = await _connector(
        connections,
        signedInAs: 'sub-1',
        browser: browser,
      );

      final connection = await connector.connectWithOAuth(
        service: ProviderService.googlePhotos,
        reconnectId: _album.connectionId,
      );

      expect(browser.loginHints, ['sub-1']);
      expect(connection.id, _album.connectionId);
      expect(connection.accountId, 'sub-1');
      expect(await _token(connections, _album.connectionId), 'fresh');
      expect(connections.all.map((c) => c.id), [_album.connectionId]);
    });

    test('a removed id comes back beside the account it belongs to', () async {
      final connections = ProviderConnections(storage: _MemoryKeyValue());
      await connections.upsert(
        const ProviderConnection(
          id: 'google|sub-1',
          service: ProviderService.googleDrive,
          accountLabel: 'me@gmail.com',
          accountId: 'sub-1',
        ),
        _lapsed,
      );
      final connector = await _connector(connections, signedInAs: 'sub-1');

      await connector.connectWithOAuth(
        service: ProviderService.googlePhotos,
        reconnectId: _album.connectionId,
      );

      expect(await _token(connections, 'google|sub-1'), 'fresh');
      expect(await _token(connections, _album.connectionId), 'fresh');
      expect(connections.byId(_album.connectionId)?.accountId, 'sub-1');
    });

    test('a sign in from anywhere renews the whole account', () async {
      final connections = ProviderConnections(storage: _MemoryKeyValue());
      await connections.upsertAll(_legacy, _lapsed);
      final browser = _Browser();
      final connector = await _connector(
        connections,
        signedInAs: 'sub-1',
        browser: browser,
      );

      final connection = await connector.connectWithOAuth(
        service: ProviderService.googleDrive,
      );

      // Nobody named an account, so none is hinted or enforced.
      expect(browser.loginHints, [null]);
      expect(connection.id, 'googledrive|sub-1');
      expect(await _token(connections, 'googledrive|sub-1'), 'fresh');
      expect(await _token(connections, 'googlephotos|sub-1'), 'fresh');
      expect(connections.all, hasLength(2));
    });

    test('an account page refuses a sign in to another account', () async {
      final connections = ProviderConnections(storage: _MemoryKeyValue());
      await connections.upsertAll(_legacy, _lapsed);
      final connector = await _connector(connections, signedInAs: 'sub-2');

      await expectLater(
        connector.connectWithOAuth(
          service: ProviderService.googleDrive,
          preferAccountId: 'sub-1',
        ),
        throwsA(
          isA<ProviderFailure>().having(
            (failure) => failure.detail,
            'detail',
            oauthWrongAccount,
          ),
        ),
      );
      expect(connections.all, hasLength(2));
    });

    test('a new account beside the others is not held to one', () async {
      final connections = ProviderConnections(storage: _MemoryKeyValue());
      await connections.upsertAll(_legacy, _lapsed);
      final connector = await _connector(connections, signedInAs: 'sub-2');

      final connection = await connector.connectWithOAuth(
        service: ProviderService.googleDrive,
        preferAccountId: '',
      );

      expect(connection.id, 'google|sub-2');
      expect(await _token(connections, 'googlephotos|sub-1'), 'lapsed');
      expect(connections.all, hasLength(3));
    });

    // Microsoft answers "who signed in" from Graph for OneDrive and from the id
    // token for mail, and the two need not agree on one person's id.
    test('Microsoft is only held to the id of the connection itself', () {
      expect(
        ProviderConnector.expectedAccountFor(
          ProviderService.outlookMail,
          preferAccountId: 'graph-id',
        ),
        isNull,
      );
      expect(
        ProviderConnector.expectedAccountFor(
          ProviderService.oneDrive,
          reconnectId: 'microsoft|onedrive|graph-id',
          bound: const ProviderConnection(
            id: 'microsoft|onedrive|graph-id',
            service: ProviderService.oneDrive,
            accountLabel: 'me@outlook.com',
            accountId: 'graph-id',
          ),
        ),
        'graph-id',
      );
    });

    testWidgets('the album that asked recovers once signed in', (tester) async {
      final connections = ProviderConnections(storage: _MemoryKeyValue());
      await connections.upsertAll(_legacy, _lapsed);
      final connector = await _connector(connections, signedInAs: 'sub-1');
      final lapsed = _Album()..failure = const ProviderFailure.authExpired();
      final renewed = _Album();
      final builtWith = <String>[];
      ProviderRegistry.register(ProviderService.googlePhotos, (connection, _) {
        builtWith.add(connection.id);
        return renewed;
      });
      addTearDown(ProviderRegistry.reset);
      final controller = ProviderController(
        collectionId: 'album',
        source: _album,
        provider: lapsed,
        cache: _MemoryCache(),
        connections: connections,
      );
      try {
        await controller.load();
        expect(controller.status, ProviderStatus.authExpired);

        await connector.connectWithOAuth(
          service: ProviderService.googlePhotos,
          reconnectId: _album.connectionId,
        );
        await tester.pump();

        expect(lapsed.disposed, isTrue);
        expect(builtWith, [_album.connectionId]);
        expect(await _token(connections, builtWith.single), 'fresh');
        expect(renewed.listCalls, 1);
        expect(controller.status, ProviderStatus.ready);
        expect(controller.nodes, hasLength(1));
      } finally {
        controller.dispose();
      }
    });
  });

  group('reading the account back out of a connection id', () {
    test('reads ids made before and after one sign in covered a family', () {
      const photos = ProviderService.googlePhotos;
      String? account(String id) => ProviderConnections.accountIdIn(id, photos);
      expect(account('googlephotos|1134'), '1134');
      expect(account('googledrive|1134'), '1134');
      expect(account('google|1134'), '1134');
      expect(
        ProviderConnections.accountIdIn(
          'microsoft|onedrive|abc',
          ProviderService.oneDrive,
        ),
        'abc',
      );
    });

    test('names no account for an id that does not carry one', () {
      const photos = ProviderService.googlePhotos;
      expect(ProviderConnections.accountIdIn('google', photos), isNull);
      expect(ProviderConnections.accountIdIn('google|', photos), isNull);
      expect(ProviderConnections.accountIdIn('github|octocat', photos), isNull);
      expect(
        ProviderConnections.accountIdIn(
          'microsoft|onedrive',
          ProviderService.oneDrive,
        ),
        isNull,
      );
    });
  });
}

Future<String?> _token(ProviderConnections connections, String id) async =>
    (await connections.credentialsFor(id))?.accessToken;

Future<ProviderConnector> _connector(
  ProviderConnections connections, {
  required String signedInAs,
  _Browser? browser,
}) async {
  final apps = OAuthAppRegistry(storage: _MemoryKeyValue());
  await apps.writeFamily(
    ProviderAccountFamily.google,
    const OAuthApp(clientId: 'client', clientSecret: 'secret'),
  );
  return ProviderConnector(
    client: MockClient(
      (request) async => http.Response(
        jsonEncode({'sub': signedInAs, 'email': '$signedInAs@example.com'}),
        200,
      ),
    ),
    connections: connections,
    oauth: browser ?? _Browser(),
    apps: apps,
  );
}

/// The browser half of a sign in: whatever account it is asked about, it
/// hands back a fresh token. Which account that was is the userinfo answer.
class _Browser extends Fake implements OAuthFlow {
  final loginHints = <String?>[];

  @override
  Future<ProviderCredentials> authorize({
    required OAuthEndpoints endpoints,
    required OAuthApp app,
    List<String>? scopeOverride,
    String? loginHint,
  }) async {
    loginHints.add(loginHint);
    return const ProviderCredentials(
      accessToken: 'fresh',
      refreshToken: 'refresh',
    );
  }

  @override
  void close() {}
}

class _Album extends CollectionProvider {
  ProviderFailure? failure;
  int listCalls = 0;
  bool disposed = false;

  @override
  ProviderService get service => _album.service;

  @override
  CollectionSource get source => _album;

  @override
  ProviderCapabilities get capabilities => const ProviderCapabilities();

  @override
  String get originLabel => 'Google Photos';

  @override
  Future<void> ensureReady() async {}

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    listCalls++;
    final failure = this.failure;
    if (failure != null) {
      throw failure;
    }
    return const ProviderPage(
      nodes: [
        ProviderNode(
          id: 'photo-0',
          name: 'Photo 0.jpg',
          kind: ProviderNodeKind.image,
        ),
      ],
    );
  }

  @override
  Future<String?> thumbnailPath(ProviderNode node) async => null;

  @override
  Future<String?> materialize(ProviderNode node) async => null;

  @override
  Future<Uint8List> readBytes(ProviderNode node, {int maxBytes = 32 << 20}) =>
      throw UnimplementedError();

  @override
  void dispose() => disposed = true;
}

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

class _MemoryKeyValue implements KeyValueStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> remove(String key) async {
    _values.remove(key);
  }

  @override
  Future<void> clear() async {
    _values.clear();
  }

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = _values[key];
    return value == null ? null : formatter(value);
  }
}
