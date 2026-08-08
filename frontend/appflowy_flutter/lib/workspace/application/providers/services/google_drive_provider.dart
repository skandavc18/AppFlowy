import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';

/// A Google Drive folder.
///
/// Drive answers with everything about a file in one listing, which is what
/// lets a folder open at full speed: no per-file round trip for a name, a size
/// or a thumbnail. Google's own documents (Docs, Sheets, Slides) have no bytes
/// of their own, so they are exported to an ordinary format on the way out —
/// otherwise a Doc would be a file the workspace could not open.
class GoogleDriveProvider extends RemoteCollectionProvider
    implements FolderProvider, ExternalFileProvider {
  GoogleDriveProvider({
    required super.connection,
    required super.source,
    super.transport,
    super.cache,
  });

  static const _pageSize = 200;

  /// Everything a card, a preview and a viewer needs, asked for once.
  static const _fields =
      'nextPageToken,files(id,name,mimeType,size,modifiedTime,createdTime,'
      'parents,thumbnailLink,webViewLink,iconLink,starred,trashed,'
      'imageMediaMetadata(width,height,location),videoMediaMetadata(width,height,durationMillis),'
      'capabilities(canEdit,canDelete,canRename,canAddChildren),shortcutDetails)';

  /// What a Google-native document becomes when it is read.
  static const _exports = <String, ({String mime, String extension})>{
    'application/vnd.google-apps.document': (
      mime:
          'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
      extension: 'docx',
    ),
    'application/vnd.google-apps.spreadsheet': (
      mime: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
      extension: 'xlsx',
    ),
    'application/vnd.google-apps.presentation': (
      mime:
          'application/vnd.openxmlformats-officedocument.presentationml.presentation',
      extension: 'pptx',
    ),
    'application/vnd.google-apps.drawing': (
      mime: 'image/png',
      extension: 'png'
    ),
    'application/vnd.google-apps.script': (
      mime: 'application/vnd.google-apps.script+json',
      extension: 'json',
    ),
  };

  @override
  ProviderService get service => ProviderService.googleDrive;

  @override
  String get apiBase => 'https://www.googleapis.com/drive/v3';

  @override
  String get originLabel {
    final folder = source.remoteName;
    return folder.isEmpty
        ? 'Google Drive'
        : '$folder · ${connection.accountLabel}';
  }

  @override
  bool authenticatesMedia(String url) =>
      url.startsWith('https://www.googleapis.com');

  @override
  Future<void> probe() async {
    final about = jsonMap(
      await transport.json(
        '$apiBase/about',
        query: const {'fields': 'user(displayName,emailAddress),storageQuota'},
      ),
    );
    if (about.isEmpty) {
      throw const ProviderFailure.authExpired();
    }

    // The scope the connection was granted decides what may be offered. A
    // read-only grant hides every write rather than letting Drive refuse it.
    final canWrite = connection.scopes.any(
      (scope) =>
          scope == 'https://www.googleapis.com/auth/drive' ||
          scope == 'https://www.googleapis.com/auth/drive.file',
    );
    capabilities = canWrite
        ? const ProviderCapabilities(
            canSearch: true,
            canUpload: true,
            canCreateFolder: true,
            canRename: true,
            canMove: true,
            canDelete: true,
            canFavourite: true,
          )
        : const ProviderCapabilities(canSearch: true);
  }

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    final folder =
        parentId ?? (source.remoteId.isEmpty ? 'root' : source.remoteId);
    return _query(
      "'${_escape(folder)}' in parents and trashed = false",
      pageToken: pageToken,
      parentId: folder,
    );
  }

  @override
  Future<ProviderPage> search(String query, {String? pageToken}) {
    final needle = _escape(query);
    return _query(
      "name contains '$needle' and trashed = false",
      pageToken: pageToken,
    );
  }

  @override
  Future<List<ProviderNode>> folders({String? parentId}) async {
    final folder = parentId ?? 'root';
    final page = await _query(
      "'${_escape(folder)}' in parents and trashed = false and "
      "mimeType = 'application/vnd.google-apps.folder'",
      parentId: folder,
    );
    return page.nodes;
  }

  @override
  Future<List<ProviderNode>> ancestorsOf(ProviderNode node) async {
    final chain = <ProviderNode>[];
    var current = node.parentId;
    // Drive is a graph, not a tree — a file can have several parents — so the
    // walk follows the first one and stops at a sensible depth.
    while (current != null && current.isNotEmpty && chain.length < 12) {
      final file = jsonMap(
        await transport.json(
          '$apiBase/files/$current',
          query: const {
            'fields': 'id,name,parents,mimeType',
            'supportsAllDrives': 'true',
          },
        ),
      );
      if (file.isEmpty) {
        break;
      }
      chain.insert(0, _file(file, null));
      current = _firstParent(file);
    }
    return chain;
  }

  static String? _firstParent(Map<String, dynamic> file) {
    final parents = file['parents'];
    if (parents is! List || parents.isEmpty) {
      return null;
    }
    final first = parents.first;
    return first is String && first.isNotEmpty ? first : null;
  }

  // --- Writes ---------------------------------------------------------------

  @override
  Future<ProviderNode> createFolder(String name, {String? parentId}) async {
    final created = jsonMap(
      await transport.json(
        '$apiBase/files',
        method: 'POST',
        query: const {'fields': 'id,name,mimeType,parents,modifiedTime'},
        body: {
          'name': name,
          'mimeType': 'application/vnd.google-apps.folder',
          'parents': [parentId ?? source.remoteId.orRoot],
        },
      ),
    );
    return _file(created, parentId ?? source.remoteId);
  }

  @override
  Future<ProviderNode> upload(
    String name,
    Uint8List bytes, {
    String? parentId,
    String? mimeType,
  }) async {
    // Drive's multipart upload: one request, metadata then bytes, separated by
    // a boundary that cannot occur in either.
    const boundary = 'appflowy-drive-boundary-8f2c1d';
    final metadata = jsonEncode({
      'name': name,
      'parents': [parentId ?? source.remoteId.orRoot],
    });

    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(
        utf8.encode('Content-Type: application/json; charset=UTF-8\r\n\r\n'),
      )
      ..add(utf8.encode(metadata))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(
        utf8.encode(
          'Content-Type: ${mimeType ?? 'application/octet-stream'}\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--'));

    final response = await transport.send(
      'https://www.googleapis.com/upload/drive/v3/files',
      method: 'POST',
      headers: {'Content-Type': 'multipart/related; boundary=$boundary'},
      query: const {
        'uploadType': 'multipart',
        'fields': 'id,name,mimeType,size,parents,modifiedTime',
      },
      body: body.takeBytes(),
    );
    return _file(
      jsonMap(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      ),
      parentId ?? source.remoteId,
    );
  }

  @override
  Future<ProviderNode> rename(ProviderNode node, String name) async {
    final updated = jsonMap(
      await transport.json(
        '$apiBase/files/${node.id}',
        method: 'PATCH',
        query: const {'fields': 'id,name,mimeType,size,parents,modifiedTime'},
        body: {'name': name},
      ),
    );
    return _file(updated, node.parentId);
  }

  @override
  Future<ProviderNode> move(
    ProviderNode node, {
    required String parentId,
  }) async {
    final updated = jsonMap(
      await transport.json(
        '$apiBase/files/${node.id}',
        method: 'PATCH',
        query: {
          'addParents': parentId,
          if (node.parentId != null) 'removeParents': node.parentId!,
          'fields': 'id,name,mimeType,size,parents,modifiedTime',
        },
        body: const <String, Object?>{},
      ),
    );
    return _file(updated, parentId);
  }

  @override
  Future<void> delete(ProviderNode node) async {
    // Trash rather than erase: a delete made from a viewer should be as
    // recoverable as one made in Drive itself.
    await transport.json(
      '$apiBase/files/${node.id}',
      method: 'PATCH',
      body: {'trashed': true},
    );
  }

  @override
  Future<ProviderNode> setFavourite(ProviderNode node, bool favourite) async {
    await transport.json(
      '$apiBase/files/${node.id}',
      method: 'PATCH',
      body: {'starred': favourite},
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

  // --- Internals ------------------------------------------------------------

  Future<ProviderPage> _query(
    String q, {
    String? pageToken,
    String? parentId,
  }) async {
    final answer = jsonMap(
      await transport.json(
        '$apiBase/files',
        query: {
          'q': q,
          'fields': _fields,
          'pageSize': '$_pageSize',
          'orderBy': 'folder,name_natural',
          'supportsAllDrives': 'true',
          'includeItemsFromAllDrives': 'true',
          'corpora': 'allDrives',
          if (pageToken != null && pageToken.isNotEmpty) 'pageToken': pageToken,
        },
      ),
    );

    return ProviderPage(
      nodes: [
        for (final file in jsonList(answer['files']))
          if (file['trashed'] != true) _file(file, parentId),
      ],
      nextPageToken: jsonString(answer['nextPageToken']),
    );
  }

  ProviderNode _file(Map<String, dynamic> file, String? parentId) {
    final id = jsonString(file['id']);
    final mime = jsonString(file['mimeType']);
    final isFolder = mime == 'application/vnd.google-apps.folder';
    final export = _exports[mime];
    final image = jsonMap(file['imageMediaMetadata']);
    final video = jsonMap(file['videoMediaMetadata']);
    final permissions = jsonMap(file['capabilities']);
    final location = jsonMap(image['location']);
    final thumbnail = jsonString(file['thumbnailLink']);

    var name = jsonString(file['name'], 'Untitled');
    if (export != null &&
        !name.toLowerCase().endsWith('.${export.extension}')) {
      // A Doc has no extension of its own; naming it after what it exports as
      // is what lets the workspace pick the right viewer.
      name = '$name.${export.extension}';
    }

    return ProviderNode(
      id: id,
      parentId: parentId ?? _firstParent(file),
      name: name,
      kind: providerNodeKindFor(
        mimeType: export?.mime ?? mime,
        name: name,
        isFolder: isFolder,
      ),
      mimeType: export?.mime ?? (mime.isEmpty ? null : mime),
      byteSize: jsonInt(file['size']),
      modifiedAt: jsonDate(file['modifiedTime']),
      createdAt: jsonDate(file['createdTime']),
      thumbnailUrl: thumbnail.isEmpty ? null : thumbnail,
      downloadUrl: isFolder
          ? null
          : export == null
              ? '$apiBase/files/$id?alt=media&supportsAllDrives=true'
              : '$apiBase/files/$id/export?mimeType=${Uri.encodeQueryComponent(export.mime)}',
      webUrl: jsonString(file['webViewLink']),
      width: jsonInt(image['width']) ?? jsonInt(video['width']),
      height: jsonInt(image['height']) ?? jsonInt(video['height']),
      durationMs: jsonInt(video['durationMillis']),
      favourite: file['starred'] == true,
      readOnly: permissions['canEdit'] == false,
      latitude: jsonDouble(location['latitude']),
      longitude: jsonDouble(location['longitude']),
      extra: {
        if (export != null) 'google_native': mime,
        if (permissions.isNotEmpty) 'can_delete': permissions['canDelete'],
      },
    );
  }

  /// Drive's query language is single quoted, so a name containing one has to
  /// be escaped or the query is malformed — and a crafted name must never be
  /// able to change the meaning of the query.
  static String _escape(String value) =>
      value.replaceAll(r'\', r'\\').replaceAll("'", r"\'");
}

extension on String {
  String get orRoot => isEmpty ? 'root' : this;
}
