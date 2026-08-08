import 'dart:convert';
import 'dart:typed_data';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';

/// A OneDrive folder, read through Microsoft Graph.
///
/// Graph is the friendliest of the three: a listing carries the thumbnail, the
/// size, the modified time and a short-lived direct download link in one
/// answer, so a folder needs exactly one request to be drawn.
class OneDriveProvider extends RemoteCollectionProvider
    implements FolderProvider, ExternalFileProvider {
  OneDriveProvider({
    required super.connection,
    required super.source,
    super.transport,
    super.cache,
  });

  static const _pageSize = 200;

  /// `@microsoft.graph.downloadUrl` is a pre-signed link; asking for it in the
  /// listing saves a request per file when something is opened.
  static const _select =
      'id,name,size,file,folder,image,video,photo,location,webUrl,'
      'lastModifiedDateTime,createdDateTime,parentReference,'
      '@microsoft.graph.downloadUrl';

  @override
  ProviderService get service => ProviderService.oneDrive;

  @override
  String get apiBase => 'https://graph.microsoft.com/v1.0';

  @override
  String get originLabel {
    final folder = source.remoteName;
    return folder.isEmpty ? 'OneDrive' : '$folder · ${connection.accountLabel}';
  }

  @override
  bool authenticatesMedia(String url) =>
      url.startsWith('https://graph.microsoft.com');

  String get _drive => source.option<String>('drive_id')?.isNotEmpty ?? false
      ? '$apiBase/drives/${source.option<String>('drive_id')}'
      : '$apiBase/me/drive';

  @override
  Future<void> probe() async {
    final drive = jsonMap(await transport.json(_drive));
    if (drive.isEmpty) {
      throw const ProviderFailure.authExpired();
    }

    final canWrite = connection.scopes.any(
      (scope) => scope.toLowerCase().contains('files.readwrite'),
    );
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
    // A continuation link from Graph is a complete URL and must be followed as
    // it stands — rebuilding it from parts loses the paging token's context.
    if (pageToken != null && pageToken.isNotEmpty) {
      return _page(jsonMap(await transport.json(pageToken)), parentId);
    }

    final folder = parentId ?? source.remoteId;
    final url = folder.isEmpty
        ? '$_drive/root/children'
        : '$_drive/items/$folder/children';
    final answer = jsonMap(
      await transport.json(
        url,
        query: {'\$top': '$_pageSize', '\$select': _select},
      ),
    );
    return _page(answer, folder.isEmpty ? null : folder);
  }

  @override
  Future<ProviderPage> search(String query, {String? pageToken}) async {
    if (pageToken != null && pageToken.isNotEmpty) {
      return _page(jsonMap(await transport.json(pageToken)), null);
    }
    final scope = source.remoteId.isEmpty
        ? '$_drive/root'
        : '$_drive/items/${source.remoteId}';
    final answer = jsonMap(
      await transport.json(
        "$scope/search(q='${Uri.encodeComponent(query)}')",
        query: {'\$top': '$_pageSize', '\$select': _select},
      ),
    );
    return _page(answer, null);
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
    final chain = <ProviderNode>[];
    var current = node.parentId;
    while (current != null && current.isNotEmpty && chain.length < 12) {
      final item = jsonMap(
        await transport.json(
          '$_drive/items/$current',
          query: const {'\$select': 'id,name,folder,parentReference'},
        ),
      );
      if (item.isEmpty) {
        break;
      }
      chain.insert(0, _item(item, null));
      current = jsonString(jsonMap(item['parentReference'])['id']);
      if (current.isEmpty) {
        break;
      }
    }
    return chain;
  }

  // --- Writes ---------------------------------------------------------------

  @override
  Future<ProviderNode> createFolder(String name, {String? parentId}) async {
    final parent = parentId ?? source.remoteId;
    final url = parent.isEmpty
        ? '$_drive/root/children'
        : '$_drive/items/$parent/children';
    final created = jsonMap(
      await transport.json(
        url,
        method: 'POST',
        body: {
          'name': name,
          'folder': <String, Object?>{},
          // Rather than fail, let Graph pick "name (1)" — a create that is
          // refused because of a name clash reads as a bug.
          '@microsoft.graph.conflictBehavior': 'rename',
        },
      ),
    );
    return _item(created, parent.isEmpty ? null : parent);
  }

  @override
  Future<ProviderNode> upload(
    String name,
    Uint8List bytes, {
    String? parentId,
    String? mimeType,
  }) async {
    final parent = parentId ?? source.remoteId;
    final path = parent.isEmpty
        ? '$_drive/root:/${Uri.encodeComponent(name)}:/content'
        : '$_drive/items/$parent:/${Uri.encodeComponent(name)}:/content';

    final response = await transport.send(
      path,
      method: 'PUT',
      headers: {'Content-Type': mimeType ?? 'application/octet-stream'},
      body: bytes,
    );
    return _item(
      jsonMap(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      ),
      parent.isEmpty ? null : parent,
    );
  }

  @override
  Future<ProviderNode> rename(ProviderNode node, String name) async {
    final updated = jsonMap(
      await transport.json(
        '$_drive/items/${node.id}',
        method: 'PATCH',
        body: {'name': name},
      ),
    );
    return _item(updated, node.parentId);
  }

  @override
  Future<ProviderNode> move(
    ProviderNode node, {
    required String parentId,
  }) async {
    final updated = jsonMap(
      await transport.json(
        '$_drive/items/${node.id}',
        method: 'PATCH',
        body: {
          'parentReference': {'id': parentId},
        },
      ),
    );
    return _item(updated, parentId);
  }

  @override
  Future<void> delete(ProviderNode node) async {
    await transport.send('$_drive/items/${node.id}', method: 'DELETE');
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

  ProviderPage _page(Map<String, dynamic> answer, String? parentId) =>
      ProviderPage(
        nodes: [
          for (final item in jsonList(answer['value'])) _item(item, parentId),
        ],
        nextPageToken: jsonString(answer['@odata.nextLink']),
      );

  ProviderNode _item(Map<String, dynamic> item, String? parentId) {
    final id = jsonString(item['id']);
    final isFolder = item['folder'] is Map;
    final file = jsonMap(item['file']);
    final image = jsonMap(item['image']);
    final video = jsonMap(item['video']);
    final location = jsonMap(item['location']);
    final coordinates = jsonMap(
      location['coordinates'] is Map ? location['coordinates'] : location,
    );
    final name = jsonString(item['name'], 'Untitled');
    final mime = jsonString(file['mimeType']);

    return ProviderNode(
      id: id,
      parentId: parentId ?? jsonString(jsonMap(item['parentReference'])['id']),
      name: name,
      kind: providerNodeKindFor(
        mimeType: mime,
        name: name,
        isFolder: isFolder,
      ),
      mimeType: mime.isEmpty ? null : mime,
      byteSize: jsonInt(item['size']),
      modifiedAt: jsonDate(item['lastModifiedDateTime']),
      createdAt: jsonDate(item['createdDateTime']),
      thumbnailUrl:
          isFolder ? null : '$_drive/items/$id/thumbnails/0/large/content',
      downloadUrl: isFolder
          ? null
          : jsonString(item['@microsoft.graph.downloadUrl']).isNotEmpty
              ? jsonString(item['@microsoft.graph.downloadUrl'])
              : '$_drive/items/$id/content',
      webUrl: jsonString(item['webUrl']),
      childCount:
          isFolder ? jsonInt(jsonMap(item['folder'])['childCount']) : null,
      width: jsonInt(image['width']) ?? jsonInt(video['width']),
      height: jsonInt(image['height']) ?? jsonInt(video['height']),
      durationMs: jsonInt(video['duration']),
      latitude: jsonDouble(coordinates['latitude']),
      longitude: jsonDouble(coordinates['longitude']),
    );
  }
}
