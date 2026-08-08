import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';

/// A Box folder.
///
/// Box pages by offset rather than by cursor, and it will not tell you anything
/// beyond an id and a name unless you ask for the fields by name — so both are
/// spelled out here rather than discovered at runtime.
class BoxProvider extends RemoteCollectionProvider
    implements FolderProvider, ExternalFileProvider {
  BoxProvider({
    required super.connection,
    required super.source,
    super.transport,
    super.cache,
  });

  static const _pageSize = 200;

  static const _fields =
      'id,type,name,size,modified_at,created_at,parent,extension,'
      'shared_link,permissions,item_status,path_collection';

  @override
  ProviderService get service => ProviderService.box;

  @override
  String get apiBase => 'https://api.box.com/2.0';

  @override
  String get originLabel {
    final folder = source.remoteName;
    return folder.isEmpty ? 'Box' : '$folder · ${connection.accountLabel}';
  }

  @override
  bool authenticatesMedia(String url) => url.startsWith('https://api.box.com');

  @override
  Future<void> probe() async {
    final me = jsonMap(await transport.json('$apiBase/users/me'));
    if (me.isEmpty) {
      throw const ProviderFailure.authExpired();
    }

    final canWrite = connection.scopes.contains('root_readwrite');
    capabilities = canWrite
        ? const ProviderCapabilities(
            canSearch: true,
            canUpload: true,
            canCreateFolder: true,
            canRename: true,
            canMove: true,
            canDelete: true,
          )
        : const ProviderCapabilities(canSearch: true);
  }

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    final folder =
        parentId ?? (source.remoteId.isEmpty ? '0' : source.remoteId);
    final offset = int.tryParse(pageToken ?? '') ?? 0;
    final answer = jsonMap(
      await transport.json(
        '$apiBase/folders/$folder/items',
        query: {
          'fields': _fields,
          'limit': '$_pageSize',
          'offset': '$offset',
          'usemarker': 'false',
        },
      ),
    );

    final entries = jsonList(answer['entries']);
    final total = jsonInt(answer['total_count']) ?? entries.length;
    final consumed = offset + entries.length;
    return ProviderPage(
      nodes: [for (final entry in entries) _entry(entry, folder)],
      nextPageToken: consumed < total ? '$consumed' : null,
    );
  }

  @override
  Future<ProviderPage> search(String query, {String? pageToken}) async {
    final offset = int.tryParse(pageToken ?? '') ?? 0;
    final answer = jsonMap(
      await transport.json(
        '$apiBase/search',
        query: {
          'query': query,
          'fields': _fields,
          'limit': '$_pageSize',
          'offset': '$offset',
          if (source.remoteId.isNotEmpty)
            'ancestor_folder_ids': source.remoteId,
        },
      ),
    );

    final entries = jsonList(answer['entries']);
    final total = jsonInt(answer['total_count']) ?? entries.length;
    final consumed = offset + entries.length;
    return ProviderPage(
      nodes: [for (final entry in entries) _entry(entry, null)],
      nextPageToken: consumed < total ? '$consumed' : null,
    );
  }

  @override
  Future<List<ProviderNode>> folders({String? parentId}) async {
    final page = await list(parentId: parentId);
    return [
      for (final node in page.nodes)
        if (node.isFolder) node,
    ];
  }

  @override
  Future<List<ProviderNode>> ancestorsOf(ProviderNode node) async {
    // Box already gives the whole chain with every item, so no walk is needed.
    final path = node.extra['path'];
    if (path is! List) {
      return const <ProviderNode>[];
    }
    return [
      for (final entry in path)
        if (entry is Map)
          ProviderNode(
            id: jsonString(entry['id']),
            name: jsonString(entry['name'], 'Folder'),
            kind: ProviderNodeKind.folder,
          ),
    ];
  }

  // --- Writes ---------------------------------------------------------------

  @override
  Future<ProviderNode> createFolder(String name, {String? parentId}) async {
    final parent =
        parentId ?? (source.remoteId.isEmpty ? '0' : source.remoteId);
    final created = jsonMap(
      await transport.json(
        '$apiBase/folders',
        method: 'POST',
        body: {
          'name': name,
          'parent': {'id': parent},
        },
      ),
    );
    return _entry(created, parent);
  }

  @override
  Future<ProviderNode> upload(
    String name,
    Uint8List bytes, {
    String? parentId,
    String? mimeType,
  }) async {
    final parent =
        parentId ?? (source.remoteId.isEmpty ? '0' : source.remoteId);
    const boundary = 'appflowy-box-boundary-4a91e7';
    final attributes = jsonEncode({
      'name': name,
      'parent': {'id': parent},
    });

    final body = BytesBuilder(copy: false)
      ..add(utf8.encode('--$boundary\r\n'))
      ..add(
        utf8.encode(
          'Content-Disposition: form-data; name="attributes"\r\n\r\n',
        ),
      )
      ..add(utf8.encode(attributes))
      ..add(utf8.encode('\r\n--$boundary\r\n'))
      ..add(
        utf8.encode(
          'Content-Disposition: form-data; name="file"; '
          'filename="${_headerSafe(name)}"\r\n'
          'Content-Type: ${mimeType ?? 'application/octet-stream'}\r\n\r\n',
        ),
      )
      ..add(bytes)
      ..add(utf8.encode('\r\n--$boundary--\r\n'));

    final response = await transport.send(
      'https://upload.box.com/api/2.0/files/content',
      method: 'POST',
      headers: {'Content-Type': 'multipart/form-data; boundary=$boundary'},
      body: body.takeBytes(),
    );
    final answer = jsonMap(
      jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
    );
    final entries = jsonList(answer['entries']);
    return _entry(entries.isEmpty ? answer : entries.first, parent);
  }

  @override
  Future<ProviderNode> rename(ProviderNode node, String name) async {
    final endpoint = node.isFolder ? 'folders' : 'files';
    final updated = jsonMap(
      await transport.json(
        '$apiBase/$endpoint/${node.id}',
        method: 'PUT',
        body: {'name': name},
      ),
    );
    return _entry(updated, node.parentId);
  }

  @override
  Future<ProviderNode> move(
    ProviderNode node, {
    required String parentId,
  }) async {
    final endpoint = node.isFolder ? 'folders' : 'files';
    final updated = jsonMap(
      await transport.json(
        '$apiBase/$endpoint/${node.id}',
        method: 'PUT',
        body: {
          'parent': {'id': parentId},
        },
      ),
    );
    return _entry(updated, parentId);
  }

  @override
  Future<void> delete(ProviderNode node) async {
    final endpoint = node.isFolder ? 'folders' : 'files';
    await transport.send(
      '$apiBase/$endpoint/${node.id}${node.isFolder ? '?recursive=true' : ''}',
      method: 'DELETE',
    );
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

  ProviderNode _entry(Map<String, dynamic> entry, String? parentId) {
    final id = jsonString(entry['id']);
    final isFolder = jsonString(entry['type']) == 'folder';
    final name = jsonString(entry['name'], 'Untitled');
    final permissions = jsonMap(entry['permissions']);
    final pathCollection = jsonMap(entry['path_collection'])['entries'];

    return ProviderNode(
      id: id,
      parentId: parentId ?? jsonString(jsonMap(entry['parent'])['id']),
      name: name,
      kind: providerNodeKindFor(name: name, isFolder: isFolder),
      byteSize: jsonInt(entry['size']),
      modifiedAt: jsonDate(entry['modified_at']),
      createdAt: jsonDate(entry['created_at']),
      // Box renders a preview per file rather than serving a stored thumbnail;
      // it answers 202 while one is being made, which the transport treats as
      // a success with no body and the cache simply skips.
      thumbnailUrl: isFolder
          ? null
          : '$apiBase/files/$id/thumbnail.jpg?min_height=320&min_width=320',
      downloadUrl: isFolder ? null : '$apiBase/files/$id/content',
      webUrl: 'https://app.box.com/${isFolder ? 'folder' : 'file'}/$id',
      readOnly: permissions.isNotEmpty && permissions['can_upload'] != true,
      extra: {
        if (pathCollection is List) 'path': pathCollection,
      },
    );
  }

  /// A file name goes into a MIME header, so a quote or a line break in it
  /// must not be able to end the header early.
  static String _headerSafe(String name) =>
      name.replaceAll(RegExp(r'[\r\n"]'), '_');
}
