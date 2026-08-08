import 'dart:convert';
import 'dart:io';

import 'package:appflowy/workspace/application/providers/collection_provider.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/remote_provider_base.dart';

/// A GitHub repository, read through the REST API.
///
/// The one design decision worth naming: the tree is read **once**, recursively
/// (`/git/trees/<sha>?recursive=1`), rather than one request per folder. A
/// repository of a few thousand files is a single request that way, and every
/// folder in the interface opens instantly afterwards. Blobs are only fetched
/// when somebody actually opens a file.
class GitHubRepositoryProvider extends RemoteCollectionProvider
    implements RepositoryProvider, ExternalFileProvider {
  GitHubRepositoryProvider({
    required super.connection,
    required super.source,
    super.transport,
    super.cache,
  });

  /// GitHub truncates a recursive tree past 100,000 entries or 7 MB and says
  /// so; this cap keeps the interface responsive well before that.
  static const maxTreeEntries = 20000;

  @override
  ProviderService get service => ProviderService.github;

  @override
  String get apiBase => connection.host.isEmpty
      ? 'https://api.github.com'
      : '${connection.host.replaceAll(RegExp(r'/+$'), '')}/api/v3';

  /// `owner/name`, which is how a repository is named everywhere on GitHub.
  String get fullName => source.remoteId;

  @override
  String get branch =>
      source.option<String>('branch') ?? _summary?.defaultBranch ?? 'main';

  @override
  String get originLabel => fullName.isEmpty ? 'GitHub' : fullName;

  RepoSummary? _summary;
  List<ProviderNode>? _tree;
  String? _treeBranch;

  @override
  Map<String, String> get mediaHeaders => const {
        'Accept': 'application/vnd.github.raw+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  Map<String, String> get _headers => const {
        'Accept': 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      };

  @override
  Future<void> probe() async {
    if (fullName.isEmpty) {
      // Nothing bound yet: the account listing is all this provider is for.
      await transport.json('$apiBase/user', headers: _headers);
      capabilities = const ProviderCapabilities(canSearch: true);
      return;
    }

    final repository = jsonMap(
      await transport.json('$apiBase/repos/$fullName', headers: _headers),
    );
    if (repository.isEmpty) {
      throw const ProviderFailure.notFound('The repository is gone.');
    }
    _summary = _summaryOf(repository);

    // GitHub reports exactly what this token may do with this repository, so
    // the interface never offers a push that would be refused.
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
      final repositories = jsonList(
        await transport.json(
          '$apiBase/user/repos',
          headers: _headers,
          query: {
            'per_page': '100',
            'page': '$page',
            'sort': 'updated',
            'affiliation': 'owner,collaborator,organization_member',
          },
        ),
      );
      if (repositories.isEmpty) {
        break;
      }
      for (final repository in repositories) {
        nodes.add(
          ProviderNode(
            id: jsonString(repository['full_name']),
            name: jsonString(repository['name'], 'repository'),
            kind: ProviderNodeKind.folder,
            description: jsonString(repository['description']),
            modifiedAt: jsonDate(repository['pushed_at']),
            webUrl: jsonString(repository['html_url']),
            readOnly: jsonMap(repository['permissions'])['push'] != true,
            extra: {
              'private': repository['private'] == true,
              'default_branch': jsonString(repository['default_branch']),
              'stars': jsonInt(repository['stargazers_count']) ?? 0,
              'language': jsonString(repository['language']),
            },
          ),
        );
      }
      if (repositories.length < 100) {
        break;
      }
      page++;
    }
    return nodes;
  }

  @override
  Future<ProviderPage> list({String? parentId, String? pageToken}) async {
    if (fullName.isEmpty) {
      return ProviderPage(nodes: await repositories());
    }

    final tree = await _readTree();
    final parentPath = parentId == null ? '' : _pathOf(parentId);
    return ProviderPage(
      nodes: [
        for (final node in tree)
          if (_parentPathOf(node.path) == parentPath) node,
      ],
    );
  }

  /// The whole tree at once, which is what a repository browser wants.
  @override
  Future<List<ProviderNode>> listAll({
    String? parentId,
    int limit = 2000,
  }) async {
    if (fullName.isEmpty) {
      return repositories();
    }
    final tree = await _readTree();
    if (parentId == null) {
      return tree.length > maxTreeEntries
          ? tree.sublist(0, maxTreeEntries)
          : tree;
    }
    final parentPath = _pathOf(parentId);
    return [
      for (final node in tree)
        if (_parentPathOf(node.path) == parentPath) node,
    ];
  }

  @override
  Future<ProviderPage> search(String query, {String? pageToken}) async {
    if (fullName.isEmpty) {
      return ProviderPage.empty;
    }
    // A path match over the tree already in memory is instant and does not
    // spend the search rate limit, which on GitHub is only 30 a minute.
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
        '$apiBase/repos/$fullName/branches',
        headers: _headers,
        query: const {'per_page': '100'},
      ),
    );
    final defaultBranch = _summary?.defaultBranch ?? '';
    return [
      for (final entry in branches)
        RepoRef(
          name: jsonString(entry['name']),
          commitSha: jsonString(jsonMap(entry['commit'])['sha']),
          isDefault: jsonString(entry['name']) == defaultBranch,
          isProtected: entry['protected'] == true,
        ),
    ];
  }

  @override
  Future<List<RepoRef>> tags() async {
    final tags = jsonList(
      await transport.json(
        '$apiBase/repos/$fullName/tags',
        headers: _headers,
        query: const {'per_page': '100'},
      ),
    );
    return [
      for (final tag in tags)
        RepoRef(
          name: jsonString(tag['name']),
          commitSha: jsonString(jsonMap(tag['commit'])['sha']),
        ),
    ];
  }

  @override
  Future<List<RepoCommit>> commits({String? path, int limit = 40}) async {
    final commits = jsonList(
      await transport.json(
        '$apiBase/repos/$fullName/commits',
        headers: _headers,
        query: {
          'sha': branch,
          'per_page': '$limit',
          if (path != null && path.isNotEmpty) 'path': path,
        },
      ),
    );
    return [
      for (final entry in commits)
        RepoCommit(
          sha: jsonString(entry['sha']),
          message: jsonString(jsonMap(entry['commit'])['message']),
          authorName: jsonString(
            jsonMap(jsonMap(entry['commit'])['author'])['name'],
            jsonString(jsonMap(entry['author'])['login']),
          ),
          authoredAt:
              jsonDate(jsonMap(jsonMap(entry['commit'])['author'])['date']),
          authorAvatarUrl: jsonString(jsonMap(entry['author'])['avatar_url']),
          webUrl: jsonString(entry['html_url']),
        ),
    ];
  }

  @override
  Future<String?> readme() async {
    try {
      final response = await transport.send(
        '$apiBase/repos/$fullName/readme',
        headers: const {
          'Accept': 'application/vnd.github.raw',
          'X-GitHub-Api-Version': '2022-11-28',
        },
        query: {'ref': branch},
      );
      return utf8.decode(response.bodyBytes, allowMalformed: true);
    } on ProviderFailure catch (failure) {
      if (failure.status == ProviderStatus.notFound) {
        return null;
      }
      rethrow;
    }
  }

  @override
  Future<String?> archiveUrl(String ref) async =>
      fullName.isEmpty ? null : '$apiBase/repos/$fullName/tarball/$ref';

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
        headers: _headers,
        maxBytes: maxBytes,
        onProgress: onProgress,
      );

  @override
  Future<Map<String, int>> languages() async {
    final languages = jsonMap(
      await transport.json('$apiBase/repos/$fullName/languages',
          headers: _headers,),
    );
    return {
      for (final entry in languages.entries)
        if (jsonInt(entry.value) != null) entry.key: jsonInt(entry.value)!,
    };
  }

  @override
  Future<List<RepoTicket>> issues({int limit = 40}) async {
    final issues = jsonList(
      await transport.json(
        '$apiBase/repos/$fullName/issues',
        headers: _headers,
        query: {'state': 'open', 'per_page': '$limit'},
      ),
    );
    return [
      // GitHub returns pull requests from the issues endpoint too; a listing
      // of issues that silently includes them is simply wrong.
      for (final issue in issues)
        if (issue['pull_request'] == null) _ticket(issue),
    ];
  }

  @override
  Future<List<RepoTicket>> pullRequests({int limit = 40}) async {
    final pulls = jsonList(
      await transport.json(
        '$apiBase/repos/$fullName/pulls',
        headers: _headers,
        query: {'state': 'open', 'per_page': '$limit'},
      ),
    );
    return [
      for (final pull in pulls)
        RepoTicket(
          number: jsonInt(pull['number']) ?? 0,
          title: jsonString(pull['title']),
          state: jsonString(pull['state'], 'open'),
          authorName: jsonString(jsonMap(pull['user'])['login']),
          createdAt: jsonDate(pull['created_at']),
          updatedAt: jsonDate(pull['updated_at']),
          webUrl: jsonString(pull['html_url']),
          labels: [
            for (final label in jsonList(pull['labels']))
              jsonString(label['name']),
          ],
          isDraft: pull['draft'] == true,
          isMerged: pull['merged_at'] != null,
          sourceBranch: jsonString(jsonMap(pull['head'])['ref']),
          targetBranch: jsonString(jsonMap(pull['base'])['ref']),
        ),
    ];
  }

  @override
  Future<List<RepoRelease>> releases({int limit = 20}) async {
    final releases = jsonList(
      await transport.json(
        '$apiBase/repos/$fullName/releases',
        headers: _headers,
        query: {'per_page': '$limit'},
      ),
    );
    return [
      for (final release in releases)
        RepoRelease(
          name: jsonString(release['name'], jsonString(release['tag_name'])),
          tag: jsonString(release['tag_name']),
          body: jsonString(release['body']),
          publishedAt: jsonDate(release['published_at']),
          webUrl: jsonString(release['html_url']),
          isPrerelease: release['prerelease'] == true,
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

    final tree = jsonMap(
      await transport.json(
        '$apiBase/repos/$fullName/git/trees/${Uri.encodeComponent(branch)}',
        headers: _headers,
        query: const {'recursive': '1'},
      ),
    );

    final entries = jsonList(tree['tree']);
    final nodes = <ProviderNode>[];
    for (final entry in entries.take(maxTreeEntries)) {
      final path = jsonString(entry['path']);
      if (path.isEmpty) {
        continue;
      }
      final type = jsonString(entry['type']);
      final isFolder = type == 'tree';
      final name = path.split('/').last;

      nodes.add(
        ProviderNode(
          // The path is the identity: a sha changes on every commit, and a
          // stable id is what keeps selection and expansion across a refresh.
          id: path,
          parentId: _parentPathOf(path).isEmpty ? null : _parentPathOf(path),
          name: name,
          path: path,
          kind: providerNodeKindFor(name: name, isFolder: isFolder),
          byteSize: jsonInt(entry['size']),
          downloadUrl: isFolder
              ? null
              : '$apiBase/repos/$fullName/contents/${_encodePath(path)}?ref=${Uri.encodeComponent(branch)}',
          webUrl: _summary == null
              ? null
              : '${_summary!.webUrl}/${isFolder ? 'tree' : 'blob'}/$branch/$path',
          readOnly: !(_summary?.canPush ?? false),
          extra: {
            'sha': jsonString(entry['sha']),
            'mode': jsonString(entry['mode']),
          },
        ),
      );
    }

    // A submodule ("commit") has no contents here; it is listed as a folder
    // with nothing in it rather than being silently dropped.
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

  RepoSummary _summaryOf(Map<String, dynamic> repository) => RepoSummary(
        fullName: jsonString(repository['full_name']),
        description: jsonString(repository['description']),
        defaultBranch: jsonString(repository['default_branch'], 'main'),
        webUrl: jsonString(repository['html_url']),
        cloneUrl: jsonString(repository['clone_url']),
        stars: jsonInt(repository['stargazers_count']) ?? 0,
        forks: jsonInt(repository['forks_count']) ?? 0,
        openIssues: jsonInt(repository['open_issues_count']) ?? 0,
        watchers: jsonInt(repository['subscribers_count']) ?? 0,
        isPrivate: repository['private'] == true,
        isFork: repository['fork'] == true,
        isArchived: repository['archived'] == true,
        canPush: jsonMap(repository['permissions'])['push'] == true,
        license: jsonString(jsonMap(repository['license'])['spdx_id']),
        topics: [
          for (final topic in (repository['topics'] is List
              ? repository['topics'] as List
              : const []))
            if (topic is String) topic,
        ],
        pushedAt: jsonDate(repository['pushed_at']),
        sizeKb: jsonInt(repository['size']) ?? 0,
      );

  RepoTicket _ticket(Map<String, dynamic> entry) => RepoTicket(
        number: jsonInt(entry['number']) ?? 0,
        title: jsonString(entry['title']),
        state: jsonString(entry['state'], 'open'),
        authorName: jsonString(jsonMap(entry['user'])['login']),
        createdAt: jsonDate(entry['created_at']),
        updatedAt: jsonDate(entry['updated_at']),
        webUrl: jsonString(entry['html_url']),
        commentCount: jsonInt(entry['comments']) ?? 0,
        labels: [
          for (final label in jsonList(entry['labels']))
            jsonString(label['name']),
        ],
      );

  String _pathOf(String id) => id;

  static String _parentPathOf(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  /// A repository path goes into a URL path, so every segment is encoded but
  /// the separators are kept.
  static String _encodePath(String path) =>
      path.split('/').map(Uri.encodeComponent).join('/');
}
