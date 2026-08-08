import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';

/// A GitLab project.
///
/// GitLab's shape is the same as GitHub's underneath — a tree, refs, commits,
/// merge requests — so this provider answers exactly the same interface, and
/// every repository view works against either without knowing which it has.
///
/// The differences worth knowing: a project is addressed by a numeric id or a
/// URL-encoded path, the tree is paged rather than returned whole, and GitLab
/// calls a pull request a merge request.
class GitLabRepositoryProvider extends RemoteCollectionProvider
    implements RepositoryProvider, ExternalFileProvider {
  GitLabRepositoryProvider({
    required super.connection,
    required super.source,
    super.transport,
    super.cache,
  });

  static const maxTreeEntries = 20000;
  static const _pageSize = 100;

  @override
  ProviderService get service => ProviderService.gitlab;

  @override
  String get apiBase {
    final host = connection.host.trim().isEmpty
        ? 'https://gitlab.com'
        : connection.host.trim();
    return '${host.replaceAll(RegExp(r'/+$'), '')}/api/v4';
  }

  /// The project's id or URL-encoded full path, ready to go into a URL.
  String get projectRef => Uri.encodeComponent(source.remoteId);

  @override
  String get branch =>
      source.option<String>('branch') ?? _summary?.defaultBranch ?? 'main';

  @override
  String get originLabel =>
      source.remoteId.isEmpty ? 'GitLab' : source.remoteId;

  RepoSummary? _summary;
  List<ProviderNode>? _tree;
  String? _treeBranch;

  @override
  Future<void> probe() async {
    if (source.remoteId.isEmpty) {
      await transport.json('$apiBase/user');
      capabilities = const ProviderCapabilities(canSearch: true);
      return;
    }

    final project =
        jsonMap(await transport.json('$apiBase/projects/$projectRef'));
    if (project.isEmpty) {
      throw const ProviderFailure.notFound('The project is gone.');
    }
    _summary = _summaryOf(project);

    capabilities = _summary!.canPush
        ? const ProviderCapabilities(
            canSearch: true,
            canUpload: true,
            canRename: true,
            canDelete: true,
            canWriteBack: true,
          )
        : const ProviderCapabilities(canSearch: true);
  }

  @override
  Future<RepoSummary?> summary() async {
    if (_summary == null) {
      await ensureReady();
    }
    return _summary;
  }

  @override
  Future<List<ProviderNode>> repositories() async {
    final nodes = <ProviderNode>[];
    var page = 1;
    while (page <= 5) {
      final projects = jsonList(
        await transport.json(
          '$apiBase/projects',
          query: {
            'membership': 'true',
            'order_by': 'last_activity_at',
            'per_page': '$_pageSize',
            'page': '$page',
            'simple': 'false',
          },
        ),
      );
      if (projects.isEmpty) {
        break;
      }
      for (final project in projects) {
        nodes.add(
          ProviderNode(
            id: jsonString(project['path_with_namespace']),
            name: jsonString(project['name'], 'project'),
            kind: ProviderNodeKind.folder,
            description: jsonString(project['description']),
            modifiedAt: jsonDate(project['last_activity_at']),
            webUrl: jsonString(project['web_url']),
            thumbnailUrl: jsonString(project['avatar_url']).isEmpty
                ? null
                : jsonString(project['avatar_url']),
            readOnly: _accessLevelOf(jsonMap(project['permissions'])) < 30,
            extra: {
              'default_branch': jsonString(project['default_branch']),
              'stars': jsonInt(project['star_count']) ?? 0,
              'visibility': jsonString(project['visibility']),
            },
          ),
        );
      }
      if (projects.length < _pageSize) {
        break;
      }
      page++;
    }
    return nodes;
  }

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    if (source.remoteId.isEmpty) {
      return ProviderPage(nodes: await repositories());
    }
    final tree = await _readTree();
    final parentPath = parentId ?? '';
    return ProviderPage(
      nodes: [
        for (final node in tree)
          if (_parentPathOf(node.path) == parentPath) node,
      ],
    );
  }

  @override
  Future<List<ProviderNode>> listAll({
    String? parentId,
    int limit = 2000,
  }) async {
    if (source.remoteId.isEmpty) {
      return repositories();
    }
    final tree = await _readTree();
    if (parentId == null) {
      return tree.length > maxTreeEntries
          ? tree.sublist(0, maxTreeEntries)
          : tree;
    }
    return [
      for (final node in tree)
        if (_parentPathOf(node.path) == parentId) node,
    ];
  }

  @override
  Future<ProviderPage> search(String query, {String? pageToken}) async {
    if (source.remoteId.isEmpty) {
      return ProviderPage.empty;
    }
    final needle = query.toLowerCase();
    final tree = await _readTree();
    return ProviderPage(
      nodes: [
        for (final node in tree)
          if (node.path.toLowerCase().contains(needle)) node,
      ],
    );
  }

  @override
  Future<List<RepoRef>> branches() async {
    final branches = jsonList(
      await transport.json(
        '$apiBase/projects/$projectRef/repository/branches',
        query: const {'per_page': '100'},
      ),
    );
    return [
      for (final entry in branches)
        RepoRef(
          name: jsonString(entry['name']),
          commitSha: jsonString(jsonMap(entry['commit'])['id']),
          isDefault: entry['default'] == true,
          isProtected: entry['protected'] == true,
          webUrl: jsonString(entry['web_url']),
        ),
    ];
  }

  @override
  Future<List<RepoRef>> tags() async {
    final tags = jsonList(
      await transport.json(
        '$apiBase/projects/$projectRef/repository/tags',
        query: const {'per_page': '100'},
      ),
    );
    return [
      for (final tag in tags)
        RepoRef(
          name: jsonString(tag['name']),
          commitSha: jsonString(jsonMap(tag['commit'])['id']),
        ),
    ];
  }

  @override
  Future<List<RepoCommit>> commits({String? path, int limit = 40}) async {
    final commits = jsonList(
      await transport.json(
        '$apiBase/projects/$projectRef/repository/commits',
        query: {
          'ref_name': branch,
          'per_page': '$limit',
          if (path != null && path.isNotEmpty) 'path': path,
        },
      ),
    );
    return [
      for (final entry in commits)
        RepoCommit(
          sha: jsonString(entry['id']),
          message: jsonString(entry['message'], jsonString(entry['title'])),
          authorName: jsonString(entry['author_name']),
          authoredAt: jsonDate(entry['authored_date']),
          webUrl: jsonString(entry['web_url']),
          additions: jsonInt(jsonMap(entry['stats'])['additions']),
          deletions: jsonInt(jsonMap(entry['stats'])['deletions']),
        ),
    ];
  }

  @override
  Future<String?> readme() async {
    final tree = await _readTree();
    for (final node in tree) {
      final name = node.name.toLowerCase();
      if (!node.isFolder &&
          _parentPathOf(node.path).isEmpty &&
          (name == 'readme.md' ||
              name == 'readme' ||
              name == 'readme.rst' ||
              name == 'readme.txt')) {
        try {
          final bytes = await readBytes(node, maxBytes: 2 << 20);
          return utf8.decode(bytes, allowMalformed: true);
        } on ProviderFailure {
          return null;
        }
      }
    }
    return null;
  }

  @override
  Future<String?> archiveUrl(String ref) async => source.remoteId.isEmpty
      ? null
      : '$apiBase/projects/$projectRef/repository/archive.tar.gz'
          '?sha=${Uri.encodeQueryComponent(ref)}';

  @override
  Future<void> downloadArchive(
    String url,
    File destination, {
    int maxBytes = 96 << 20,
    void Function(int received, int? total)? onProgress,
  }) =>
      transport.download(
        url,
        destination,
        maxBytes: maxBytes,
        onProgress: onProgress,
      );

  @override
  Future<Map<String, int>> languages() async {
    final languages = jsonMap(
      await transport.json('$apiBase/projects/$projectRef/languages'),
    );
    // GitLab reports percentages; the interface wants relative weights, and a
    // percentage is already one.
    return {
      for (final entry in languages.entries)
        if (jsonDouble(entry.value) != null)
          entry.key: (jsonDouble(entry.value)! * 100).round(),
    };
  }

  @override
  Future<List<RepoTicket>> issues({int limit = 40}) async {
    final issues = jsonList(
      await transport.json(
        '$apiBase/projects/$projectRef/issues',
        query: {'state': 'opened', 'per_page': '$limit'},
      ),
    );
    return [for (final issue in issues) _ticket(issue)];
  }

  @override
  Future<List<RepoTicket>> pullRequests({int limit = 40}) async {
    final requests = jsonList(
      await transport.json(
        '$apiBase/projects/$projectRef/merge_requests',
        query: {'state': 'opened', 'per_page': '$limit'},
      ),
    );
    return [
      for (final request in requests)
        RepoTicket(
          number: jsonInt(request['iid']) ?? 0,
          title: jsonString(request['title']),
          state: jsonString(request['state'], 'opened'),
          authorName: jsonString(jsonMap(request['author'])['name']),
          createdAt: jsonDate(request['created_at']),
          updatedAt: jsonDate(request['updated_at']),
          webUrl: jsonString(request['web_url']),
          commentCount: jsonInt(request['user_notes_count']) ?? 0,
          labels: [
            for (final label in (request['labels'] is List
                ? request['labels'] as List
                : const []))
              if (label is String) label,
          ],
          isDraft:
              request['draft'] == true || request['work_in_progress'] == true,
          isMerged: jsonString(request['state']) == 'merged',
          sourceBranch: jsonString(request['source_branch']),
          targetBranch: jsonString(request['target_branch']),
        ),
    ];
  }

  @override
  Future<List<RepoRelease>> releases({int limit = 20}) async {
    final releases = jsonList(
      await transport.json(
        '$apiBase/projects/$projectRef/releases',
        query: {'per_page': '$limit'},
      ),
    );
    return [
      for (final release in releases)
        RepoRelease(
          name: jsonString(release['name'], jsonString(release['tag_name'])),
          tag: jsonString(release['tag_name']),
          body: jsonString(release['description']),
          publishedAt: jsonDate(release['released_at']),
          webUrl: jsonString(jsonMap(release['_links'])['self']),
          isPrerelease: release['upcoming_release'] == true,
        ),
    ];
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

  Future<List<ProviderNode>> _readTree() async {
    if (_tree != null && _treeBranch == branch) {
      return _tree!;
    }
    await ensureReady();

    final nodes = <ProviderNode>[];
    // GitLab pages the recursive tree by keyset; following the cursor is the
    // only way to read a repository of any size without missing entries.
    String? cursor;
    var pages = 0;
    do {
      final response = await transport.send(
        '$apiBase/projects/$projectRef/repository/tree',
        query: {
          'recursive': 'true',
          'ref': branch,
          'per_page': '$_pageSize',
          'pagination': 'keyset',
          if (cursor != null && cursor.isNotEmpty) 'page_token': cursor,
        },
      );

      final entries = jsonList(
        jsonDecode(utf8.decode(response.bodyBytes, allowMalformed: true)),
      );
      for (final entry in entries) {
        final path = jsonString(entry['path']);
        if (path.isEmpty) {
          continue;
        }
        final isFolder = jsonString(entry['type']) == 'tree';
        final name = jsonString(entry['name'], path.split('/').last);
        nodes.add(
          ProviderNode(
            id: path,
            parentId: _parentPathOf(path).isEmpty ? null : _parentPathOf(path),
            name: name,
            path: path,
            kind: providerNodeKindFor(name: name, isFolder: isFolder),
            downloadUrl: isFolder
                ? null
                : '$apiBase/projects/$projectRef/repository/files/'
                    '${Uri.encodeComponent(path)}/raw?ref=${Uri.encodeComponent(branch)}',
            webUrl: _summary == null
                ? null
                : '${_summary!.webUrl}/-/${isFolder ? 'tree' : 'blob'}/$branch/$path',
            readOnly: !(_summary?.canPush ?? false),
            extra: {'sha': jsonString(entry['id'])},
          ),
        );
      }

      cursor = _nextPageToken(response.headers['link']);
      pages++;
    } while (cursor != null &&
        cursor.isNotEmpty &&
        nodes.length < maxTreeEntries &&
        pages < 240);

    nodes.sort((a, b) {
      if (a.isFolder != b.isFolder) {
        return a.isFolder ? -1 : 1;
      }
      return a.path.toLowerCase().compareTo(b.path.toLowerCase());
    });

    _tree = nodes;
    _treeBranch = branch;
    return nodes;
  }

  /// Pulls `page_token` out of a `Link: <…>; rel="next"` header.
  static String? _nextPageToken(String? link) {
    if (link == null || link.isEmpty) {
      return null;
    }
    for (final part in link.split(',')) {
      if (!part.contains('rel="next"')) {
        continue;
      }
      final start = part.indexOf('<');
      final end = part.indexOf('>');
      if (start < 0 || end <= start) {
        continue;
      }
      final uri = Uri.tryParse(part.substring(start + 1, end));
      return uri?.queryParameters['page_token'];
    }
    return null;
  }

  RepoSummary _summaryOf(Map<String, dynamic> project) {
    final level = _accessLevelOf(jsonMap(project['permissions']));

    return RepoSummary(
      fullName: jsonString(project['path_with_namespace']),
      description: jsonString(project['description']),
      defaultBranch: jsonString(project['default_branch'], 'main'),
      webUrl: jsonString(project['web_url']),
      cloneUrl: jsonString(project['http_url_to_repo']),
      stars: jsonInt(project['star_count']) ?? 0,
      forks: jsonInt(project['forks_count']) ?? 0,
      openIssues: jsonInt(project['open_issues_count']) ?? 0,
      isPrivate: jsonString(project['visibility']) != 'public',
      isFork: project['forked_from_project'] != null,
      isArchived: project['archived'] == true,
      // 30 is Developer, the lowest level that may push a branch.
      canPush: level >= 30,
      topics: [
        for (final topic in (project['topics'] is List
            ? project['topics'] as List
            : const []))
          if (topic is String) topic,
      ],
      pushedAt: jsonDate(project['last_activity_at']),
    );
  }

  RepoTicket _ticket(Map<String, dynamic> entry) => RepoTicket(
        number: jsonInt(entry['iid']) ?? 0,
        title: jsonString(entry['title']),
        state: jsonString(entry['state'], 'opened'),
        authorName: jsonString(jsonMap(entry['author'])['name']),
        createdAt: jsonDate(entry['created_at']),
        updatedAt: jsonDate(entry['updated_at']),
        webUrl: jsonString(entry['web_url']),
        commentCount: jsonInt(entry['user_notes_count']) ?? 0,
        labels: [
          for (final label
              in (entry['labels'] is List ? entry['labels'] as List : const []))
            if (label is String) label,
        ],
      );

  static String _parentPathOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  /// The highest access GitLab reports, whether it comes from the project or
  /// from the group above it. 30 is Developer, the lowest level that may push.
  static int _accessLevelOf(Map<String, dynamic> permissions) {
    final project =
        jsonInt(jsonMap(permissions['project_access'])['access_level']) ?? 0;
    final group =
        jsonInt(jsonMap(permissions['group_access'])['access_level']) ?? 0;
    return project > group ? project : group;
  }
}
