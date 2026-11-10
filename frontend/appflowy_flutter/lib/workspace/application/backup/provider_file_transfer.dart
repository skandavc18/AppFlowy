// Moving a whole file to and from Google Drive, OneDrive or Box.
//
// The providers' own `upload` takes the file in one request, which is right
// for a picture dropped into a page and wrong for a backup or a sync snapshot
// of a few hundred megabytes. Every one of these services has its own way of
// taking a big file in pieces; this is where each is spoken.

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/backup/backup_target.dart';
import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/connections/provider_connection.dart';
import 'package:appflowy/workspace/application/providers/provider_http.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';
import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;

/// How far along a transfer is.
typedef FileTransferProgress = void Function(int done, int total);

class ProviderFileTransfer {
  ProviderFileTransfer({required this.service, required this.connection});

  final ProviderService service;
  final ProviderConnection connection;

  http.Client? _client;

  /// Google, Microsoft and Box all ask for pieces that are a multiple of a
  /// few hundred kilobytes; eight mebibytes divides cleanly into all of them
  /// and keeps a retry cheap.
  static const int chunkBytes = 8 * 1024 * 1024;

  /// Below this a single request is simpler, and is the path the rest of the
  /// application already exercises.
  static const int simpleUploadCeiling = 4 * 1024 * 1024;

  /// Puts [file] in [folderId] under [name].
  Future<ProviderNode> upload({
    required CollectionProvider provider,
    required File file,
    required String name,
    required String folderId,
    String mimeType = 'application/octet-stream',
    FileTransferProgress? onProgress,
  }) async {
    final total = file.lengthSync();
    if (total <= simpleUploadCeiling) {
      final node = await provider.upload(
        name,
        await file.readAsBytes(),
        parentId: folderId,
        mimeType: mimeType,
      );
      onProgress?.call(total, total);
      return node;
    }
    return switch (service) {
      ProviderService.googleDrive => _uploadToDrive(
          file: file,
          name: name,
          folderId: folderId,
          total: total,
          onProgress: onProgress,
        ),
      ProviderService.oneDrive => _uploadToOneDrive(
          file: file,
          name: name,
          folderId: folderId,
          total: total,
          onProgress: onProgress,
        ),
      ProviderService.box => _uploadToBox(
          file: file,
          name: name,
          folderId: folderId,
          total: total,
          onProgress: onProgress,
        ),
      _ => throw const BackupTargetError('That service cannot take a file.'),
    };
  }

  /// Brings the file with service id [id] to [destination].
  Future<void> download({
    required CollectionProvider provider,
    required String id,
    required File destination,
    int expectedBytes = 0,
    FileTransferProgress? onProgress,
  }) async {
    await destination.parent.create(recursive: true);
    final url = contentUrl(id);
    if (provider is RemoteCollectionProvider && url != null) {
      await provider.transport.download(
        url,
        destination,
        maxBytes: 8 << 30,
        onProgress: (received, contentLength) =>
            onProgress?.call(received, contentLength ?? expectedBytes),
      );
      return;
    }
    throw const BackupTargetError('That copy could not be downloaded.');
  }

  /// The bytes of the small file with service id [id].
  ///
  /// A file known only by its id has no download link of its own, so it is
  /// read where [download] reads it.
  Future<Uint8List> readBytes({
    required CollectionProvider provider,
    required String id,
    int maxBytes = 4 << 20,
  }) async {
    final url = contentUrl(id);
    if (provider is RemoteCollectionProvider && url != null) {
      return provider.transport.bytes(url, maxBytes: maxBytes);
    }
    throw const BackupTargetError('That file could not be read.');
  }

  /// Where the bytes of the file with service id [id] are served from.
  String? contentUrl(String id) => switch (service) {
        ProviderService.googleDrive =>
          'https://www.googleapis.com/drive/v3/files/$id?alt=media&supportsAllDrives=true',
        ProviderService.oneDrive =>
          'https://graph.microsoft.com/v1.0/me/drive/items/$id/content',
        ProviderService.box => 'https://api.box.com/2.0/files/$id/content',
        _ => null,
      };

  void close() {
    _client?.close();
    _client = null;
  }

  http.Client get _http => _client ??= http.Client();

  /// A fresh bearer token for every request.
  ///
  /// An upload can run for longer than a token lives, so the token is asked for
  /// per piece rather than once at the start; it comes out of memory unless it
  /// has actually expired.
  Future<Map<String, String>> _authorization() async {
    final token = await providerAccessToken(connection.id);
    if (token == null || token.isEmpty) {
      throw const ProviderFailure.authExpired();
    }
    return {'Authorization': 'Bearer $token'};
  }

  /// Drive's resumable upload: ask for a session, then send ranges to it.
  Future<ProviderNode> _uploadToDrive({
    required File file,
    required String name,
    required String folderId,
    required int total,
    FileTransferProgress? onProgress,
  }) async {
    final start = await _http.post(
      Uri.parse(
        'https://www.googleapis.com/upload/drive/v3/files'
        '?uploadType=resumable&fields=id,name,size,modifiedTime',
      ),
      headers: {
        ...await _authorization(),
        'Content-Type': 'application/json; charset=UTF-8',
        'X-Upload-Content-Type': 'application/octet-stream',
        'X-Upload-Content-Length': '$total',
      },
      body: jsonEncode({
        'name': name,
        'parents': [folderId],
      }),
    );
    if (start.statusCode >= 400) {
      throw ProviderFailure.fromStatusCode(start.statusCode);
    }
    final session = start.headers['location'];
    if (session == null || session.isEmpty) {
      throw const BackupTargetError('Google Drive refused to start an upload.');
    }

    final answer = await _sendRanges(
      file: file,
      total: total,
      session: Uri.parse(session),
      // Drive answers 308 while it wants more; the client must be told not to
      // treat that as a redirect, which is what `_sendRanges` arranges.
      authorize: true,
      onProgress: onProgress,
    );
    final uploaded = jsonMap(jsonDecode(answer));
    return ProviderNode(
      id: jsonString(uploaded['id']),
      name: name,
      kind: ProviderNodeKind.archive,
      parentId: folderId,
      byteSize: total,
    );
  }

  /// Graph's upload session. The session url carries its own permission, so
  /// the pieces are sent without the account's token.
  Future<ProviderNode> _uploadToOneDrive({
    required File file,
    required String name,
    required String folderId,
    required int total,
    FileTransferProgress? onProgress,
  }) async {
    final encoded = Uri.encodeComponent(name);
    final start = await _http.post(
      Uri.parse(
        'https://graph.microsoft.com/v1.0/me/drive/items/'
        '$folderId:/$encoded:/createUploadSession',
      ),
      headers: {
        ...await _authorization(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'item': {'@microsoft.graph.conflictBehavior': 'replace'},
      }),
    );
    if (start.statusCode >= 400) {
      throw ProviderFailure.fromStatusCode(start.statusCode);
    }
    final session = jsonString(jsonMap(jsonDecode(start.body))['uploadUrl']);
    if (session.isEmpty) {
      throw const BackupTargetError('OneDrive refused to start an upload.');
    }

    final answer = await _sendRanges(
      file: file,
      total: total,
      session: Uri.parse(session),
      authorize: false,
      onProgress: onProgress,
    );
    final uploaded = jsonMap(jsonDecode(answer));
    return ProviderNode(
      id: jsonString(uploaded['id']),
      name: name,
      kind: ProviderNodeKind.archive,
      parentId: folderId,
      byteSize: total,
    );
  }

  /// One session, one `PUT` per part, then a commit naming every part.
  ///
  /// Box is the only one of the three that checks the bytes itself: each part
  /// and the whole file carry a SHA-1 it verifies, so a piece that arrived
  /// wrong is refused rather than quietly stored.
  Future<ProviderNode> _uploadToBox({
    required File file,
    required String name,
    required String folderId,
    required int total,
    FileTransferProgress? onProgress,
  }) async {
    final start = await _http.post(
      Uri.parse('https://upload.box.com/api/2.0/files/upload_sessions'),
      headers: {
        ...await _authorization(),
        'Content-Type': 'application/json',
      },
      body: jsonEncode({
        'folder_id': folderId,
        'file_size': total,
        'file_name': name,
      }),
    );
    if (start.statusCode >= 400) {
      throw ProviderFailure.fromStatusCode(start.statusCode);
    }
    final session = jsonMap(jsonDecode(start.body));
    final sessionId = jsonString(session['id']);
    final partSize =
        session['part_size'] is int ? session['part_size']! as int : chunkBytes;
    if (sessionId.isEmpty) {
      throw const BackupTargetError('Box refused to start an upload.');
    }

    final parts = <Map<String, dynamic>>[];
    final whole = _DigestSink();
    final wholeSink = sha1.startChunkedConversion(whole);

    final handle = await file.open();
    try {
      var offset = 0;
      while (offset < total) {
        final piece = await handle.read(partSize);
        if (piece.isEmpty) {
          break;
        }
        wholeSink.add(piece);
        final digest = base64Encode(sha1.convert(piece).bytes);
        final response = await _http.put(
          Uri.parse(
            'https://upload.box.com/api/2.0/files/upload_sessions/$sessionId',
          ),
          headers: {
            ...await _authorization(),
            'Content-Type': 'application/octet-stream',
            'Digest': 'sha=$digest',
            'Content-Range':
                'bytes $offset-${offset + piece.length - 1}/$total',
          },
          body: piece,
        );
        if (response.statusCode >= 400) {
          throw ProviderFailure.fromStatusCode(response.statusCode);
        }
        final part = jsonMap(jsonMap(jsonDecode(response.body))['part']);
        parts.add(part);
        offset += piece.length;
        onProgress?.call(offset, total);
      }
    } finally {
      await handle.close();
    }
    wholeSink.close();

    final commit = await _http.post(
      Uri.parse(
        'https://upload.box.com/api/2.0/files/upload_sessions/$sessionId/commit',
      ),
      headers: {
        ...await _authorization(),
        'Content-Type': 'application/json',
        'Digest': 'sha=${base64Encode(whole.value!.bytes)}',
      },
      body: jsonEncode({'parts': parts}),
    );
    if (commit.statusCode >= 400) {
      throw ProviderFailure.fromStatusCode(commit.statusCode);
    }
    final entries = jsonList(jsonMap(jsonDecode(commit.body)), 'entries');
    return ProviderNode(
      id: entries.isEmpty ? '' : jsonString(entries.first['id']),
      name: name,
      kind: ProviderNodeKind.archive,
      parentId: folderId,
      byteSize: total,
    );
  }

  /// The half Drive and Graph share: `Content-Range` pieces until the last one
  /// answers with the finished file.
  Future<String> _sendRanges({
    required File file,
    required int total,
    required Uri session,
    required bool authorize,
    FileTransferProgress? onProgress,
  }) async {
    final handle = await file.open();
    try {
      var offset = 0;
      while (offset < total) {
        final piece = await handle.read(chunkBytes);
        if (piece.isEmpty) {
          break;
        }
        final request = http.Request('PUT', session)
          // ⚠️ A resumable upload answers 308 for every piece but the last, and
          // an HTTP client that follows redirects treats 308 as one — then
          // fails, because the answer carries no Location header.
          ..followRedirects = false
          ..bodyBytes = piece
          ..headers['Content-Range'] =
              'bytes $offset-${offset + piece.length - 1}/$total';
        if (authorize) {
          request.headers.addAll(await _authorization());
        }

        final response =
            await http.Response.fromStream(await _http.send(request));
        offset += piece.length;
        onProgress?.call(offset, total);

        if (response.statusCode == 200 || response.statusCode == 201) {
          return response.body;
        }
        // 308 (Drive) and 202 (Graph) both mean "send the next piece".
        if (response.statusCode != 308 && response.statusCode != 202) {
          throw ProviderFailure.fromStatusCode(response.statusCode);
        }
      }
    } finally {
      await handle.close();
    }
    throw const BackupTargetError('The upload ended without being finished.');
  }
}

/// Catches the one digest a chunked SHA-1 produces.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}
