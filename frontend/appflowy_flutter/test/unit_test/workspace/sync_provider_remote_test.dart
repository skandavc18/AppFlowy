import 'package:appflowy/core/config/kv.dart';
import 'package:appflowy/workspace/application/backup/backup_policy.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_http.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/services/google_drive_provider.dart';
import 'package:appflowy/workspace/application/sync/sync_protocol.dart';
import 'package:appflowy/workspace/application/sync/sync_remote.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const connection = ProviderConnection(
    id: 'google|sub-1',
    service: ProviderService.googleDrive,
    accountLabel: 'me@example.com',
    accountId: 'sub-1',
  );

  test('reads a small sync file from Google Drive by its id alone', () async {
    final connections = ProviderConnections(storage: _MemoryKeyValue());
    await connections.upsertAll(
      [connection],
      const ProviderCredentials(accessToken: 'token'),
    );
    final asked = <http.Request>[];
    final drive = GoogleDriveProvider(
      connection: connection,
      source: CollectionSource(
        service: ProviderService.googleDrive,
        connectionId: connection.id,
        remoteId: 'folder',
        remoteName: 'Sync',
      ),
      transport: ProviderTransport(
        connectionId: connection.id,
        connections: connections,
        client: MockClient((request) async {
          asked.add(request);
          return request.url.path.endsWith('/files/file-1') &&
                  request.url.queryParameters['alt'] == 'media'
              ? http.Response('{"format":1}', 200)
              : http.Response('{}', 404);
        }),
      ),
    );
    final remote = ProviderSyncRemote(
      kind: BackupDestinationKind.googleDrive,
      connection: connection,
      folderId: 'folder',
      folderName: 'Sync',
      provider: drive,
    );

    // A file known from a listing or an upload carries no download link.
    final text = await remote.readText(
      RemoteSyncFile(
        name: SyncFileName.baseInfo('20261108T000000-abcdef'),
        id: 'file-1',
        bytes: 12,
      ),
    );

    expect(text, '{"format":1}');
    expect(asked.single.headers['Authorization'], 'Bearer token');
    remote.dispose();
  });
}

class _MemoryKeyValue implements KeyValueStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> get(String key) async => _values[key];

  @override
  Future<void> set(String key, String value) async => _values[key] = value;

  @override
  Future<void> remove(String key) async => _values.remove(key);

  @override
  Future<void> clear() async => _values.clear();

  @override
  Future<T?> getWithFormat<T>(
    String key,
    T Function(String value) formatter,
  ) async {
    final value = _values[key];
    return value == null ? null : formatter(value);
  }
}
