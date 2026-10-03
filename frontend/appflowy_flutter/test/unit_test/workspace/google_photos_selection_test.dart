import 'dart:convert';

import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_http.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/services/google_photos_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

const _connection = ProviderConnection(
  id: 'googlephotos|sub-1',
  service: ProviderService.googlePhotos,
  accountLabel: 'me@gmail.com',
  accountId: 'sub-1',
);

const _album = CollectionSource(
  service: ProviderService.googlePhotos,
  connectionId: 'googlephotos|sub-1',
  remoteId: 'august',
  readOnly: true,
  options: {GooglePhotosProvider.sessionOption: 'august'},
);

/// Google's error envelope, as the Picker API sends it.
String _googleError(int code, String status, [String? reason]) => jsonEncode({
      'error': {
        'code': code,
        'message': 'A message nobody should render.',
        'status': status,
        if (reason != null)
          'details': [
            {'@type': 'type.googleapis.com/google.rpc.Help', 'links': []},
            {
              '@type': 'type.googleapis.com/google.rpc.ErrorInfo',
              'reason': reason,
              'domain': 'googleapis.com',
            },
          ],
      },
    });

void main() {
  group('the reason a service gave', () {
    String read(Object body) => readServiceErrorReason(
          utf8.encode(body is String ? body : jsonEncode(body)),
        );

    test('comes from Google error details, skipping entries without one', () {
      expect(
        read(_googleError(403, 'PERMISSION_DENIED', 'SERVICE_DISABLED')),
        'SERVICE_DISABLED',
      );
    });

    test('comes from the older errors list', () {
      expect(
        read({
          'error': {
            'code': 403,
            'errors': [
              {'reason': 'accessNotConfigured'},
            ],
          },
        }),
        'accessNotConfigured',
      );
    });

    test('falls back to the status, or an OAuth error code', () {
      expect(read(_googleError(403, 'PERMISSION_DENIED')), 'PERMISSION_DENIED');
      expect(
        read({'error': 'invalid_grant', 'error_description': 'Bad Request'}),
        'invalid_grant',
      );
    });

    test('is empty for anything else, and never long', () {
      expect(readServiceErrorReason(const []), '');
      expect(read('<html>Forbidden</html>'), '');
      expect(read({'message': 'Not Found'}), '');
      expect(read({'error': 'x' * 500}), hasLength(80));
    });
  });

  group('classifying a refusal', () {
    test('a token without the permission means signing in again', () {
      final failure = ProviderFailure.fromStatusCode(
        403,
        reason: ProviderFailure.insufficientScope,
      );
      expect(failure.status, ProviderStatus.authExpired);
      expect(failure.reason, ProviderFailure.insufficientScope);
    });

    test('keeps the reason out of the detail', () {
      final failure = ProviderFailure.fromStatusCode(
        403,
        reason: 'PERMISSION_DENIED',
      );
      expect(failure.status, ProviderStatus.permissionDenied);
      expect(failure.reason, 'PERMISSION_DENIED');
      expect(failure.detail, isEmpty);
    });
  });

  group('a Google Photos selection', () {
    late ProviderConnections connections;
    late List<Uri> requested;

    setUp(() async {
      connections = ProviderConnections(storage: _MemoryKeyValue());
      await connections.upsert(
        _connection,
        const ProviderCredentials(accessToken: 'live'),
      );
      requested = <Uri>[];
    });

    GooglePhotosProvider provider(int status, String body) =>
        GooglePhotosProvider(
          connection: _connection,
          source: _album,
          transport: ProviderTransport(
            connectionId: _connection.id,
            connections: connections,
            client: MockClient((request) async {
              requested.add(request.url);
              return http.Response(
                body,
                status,
                headers: const {'content-type': 'application/json'},
              );
            }),
          ),
        );

    Matcher failsWith(ProviderStatus status, {bool lapsed = false}) => throwsA(
          isA<ProviderFailure>()
              .having((failure) => failure.status, 'status', status)
              .having(
                (failure) => failure.isLapsedSelection,
                'isLapsedSelection',
                lapsed,
              ),
        );

    test('that Google still knows but no longer hands out has lapsed',
        () async {
      final photos = provider(403, _googleError(403, 'PERMISSION_DENIED'));
      await expectLater(
        photos.ensureReady(),
        failsWith(ProviderStatus.notFound, lapsed: true),
      );
      expect(requested.single.path, '/v1/sessions/august');
      photos.dispose();
    });

    test('that Google has dropped has lapsed', () async {
      final photos = provider(404, _googleError(404, 'NOT_FOUND'));
      await expectLater(
        photos.ensureReady(),
        failsWith(ProviderStatus.notFound, lapsed: true),
      );
      photos.dispose();
    });

    test('whose items are refused has lapsed', () async {
      final photos = provider(403, _googleError(403, 'PERMISSION_DENIED'));
      await expectLater(
        photos.list(),
        failsWith(ProviderStatus.notFound, lapsed: true),
      );
      expect(requested.single.path, '/v1/mediaItems');
      expect(requested.single.queryParameters['sessionId'], 'august');
      photos.dispose();
    });

    test('is not blamed when the Picker API is switched off', () async {
      final photos = provider(
        403,
        _googleError(403, 'PERMISSION_DENIED', 'SERVICE_DISABLED'),
      );
      await expectLater(
        photos.ensureReady(),
        failsWith(ProviderStatus.permissionDenied),
      );
      photos.dispose();
    });

    test('is not blamed when the sign in lacks the permission', () async {
      final photos = provider(
        403,
        _googleError(
          403,
          'PERMISSION_DENIED',
          ProviderFailure.insufficientScope,
        ),
      );
      await expectLater(
        photos.ensureReady(),
        failsWith(ProviderStatus.authExpired),
      );
      photos.dispose();
    });
  });
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
