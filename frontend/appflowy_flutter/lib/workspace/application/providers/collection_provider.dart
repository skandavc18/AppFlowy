import 'dart:io';

import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:flutter/foundation.dart';

/// The one thing every backing of a collection has to be.
///
/// Everything above this line — the album wall, the repository tree, the folder
/// gallery, the page embed — talks to this and never to a service's own API.
/// That is what makes "backed by Immich" an implementation detail rather than a
/// different kind of collection.
abstract class CollectionProvider {
  ProviderService get service;

  /// The collection this provider answers for.
  CollectionSource get source;

  /// What this provider may be asked to do, already narrowed by what the
  /// account can actually do.
  ProviderCapabilities get capabilities;

  /// A short line naming the backing, e.g. `photos.example.com` or
  /// `octocat/hello-world`. Shown beside the collection's own name.
  String get originLabel;

  /// Proves the connection still works, and narrows [capabilities] from what
  /// the service reports about the account.
  ///
  /// Throws a [ProviderFailure] rather than returning false, so the interface
  /// can tell "expired token" from "no network" without inspecting anything.
  Future<void> ensureReady();

  /// One page of the children of [parentId], or of the collection's root when
  /// it is null.
  Future<ProviderPage> list({String? parentId, String? pageToken});

  /// Everything under [parentId], following pagination for the caller.
  ///
  /// [limit] is a real stop, not a hint: a photo library is unbounded and a
  /// view that asks for "everything" must still return.
  Future<List<ProviderNode>> listAll({
    String? parentId,
    int limit = 2000,
  }) async {
    final all = <ProviderNode>[];
    String? token;
    do {
      final page = await list(parentId: parentId, pageToken: token);
      all.addAll(page.nodes);
      token = page.nextPageToken;
    } while (token != null && token.isNotEmpty && all.length < limit);
    return all.length > limit ? all.sublist(0, limit) : all;
  }

  /// Finds objects by name or content, as far as the service allows.
  Future<ProviderPage> search(String query, {String? pageToken}) async =>
      ProviderPage.empty;

  /// The bytes of one object.
  ///
  /// [maxBytes] is a hard cap — a provider must stop reading rather than pull
  /// an arbitrarily large file from a stranger's server into memory.
  Future<Uint8List> readBytes(ProviderNode node, {int maxBytes = 32 << 20});

  /// A small picture for [node], already cached on disk, or null when the
  /// service has none.
  Future<String?> thumbnailPath(ProviderNode node);

  /// The object's bytes on disk, so an existing viewer can open it by path.
  Future<String?> materialize(ProviderNode node);

  /// Frees anything held open. Called when the collection closes.
  void dispose() {}

  // --- Writes. Every one is guarded by [capabilities] before it is offered. ---

  Future<ProviderNode> createFolder(String name, {String? parentId}) =>
      throw const ProviderFailure(ProviderStatus.permissionDenied);

  Future<ProviderNode> upload(
    String name,
    Uint8List bytes, {
    String? parentId,
    String? mimeType,
  }) =>
      throw const ProviderFailure(ProviderStatus.permissionDenied);

  Future<ProviderNode> rename(ProviderNode node, String name) =>
      throw const ProviderFailure(ProviderStatus.permissionDenied);

  Future<ProviderNode> move(ProviderNode node, {required String parentId}) =>
      throw const ProviderFailure(ProviderStatus.permissionDenied);

  Future<void> delete(ProviderNode node) =>
      throw const ProviderFailure(ProviderStatus.permissionDenied);

  Future<ProviderNode> setFavourite(ProviderNode node, bool favourite) =>
      throw const ProviderFailure(ProviderStatus.permissionDenied);
}

/// A photo library.
abstract class AlbumProvider extends CollectionProvider {
  /// The albums the account can see, for the picker that binds a collection.
  Future<List<ProviderNode>> albums();

  /// Everything in the bound album, newest first where the service says so.
  Future<List<ProviderNode>> media({int limit = 2000}) =>
      listAll(parentId: source.remoteId, limit: limit);
}

/// A source tree, with or without history.
abstract class RepositoryProvider extends CollectionProvider {
  /// The repositories or projects the account can see.
  Future<List<ProviderNode>> repositories();

  /// The branch the collection is reading, once known.
  String get branch;

  Future<List<RepoRef>> branches();

  Future<List<RepoRef>> tags();

  Future<List<RepoCommit>> commits({String? path, int limit = 40});

  /// The README's rendered source, or null when there is none.
  Future<String?> readme();

  /// One request that yields the whole tree, as a `.tar.gz`.
  ///
  /// Reading a project needs file contents, and asking per file would be
  /// thousands of requests against a rate limit. Null when the host offers no
  /// such endpoint, in which case only the listing is available.
  Future<String?> archiveUrl(String ref) async => null;

  /// Streams [url] to [destination]. Lives here so the archive fetcher does
  /// not need the transport, which belongs to the provider.
  Future<void> downloadArchive(
    String url,
    File destination, {
    int maxBytes = 96 << 20,
    void Function(int received, int? total)? onProgress,
  }) =>
      throw const ProviderFailure(ProviderStatus.error);

  /// Streams one file's bytes to [destination].
  ///
  /// The counterpart to [archiveUrl] for a repository too large to take whole:
  /// nothing is fetched until somebody opens it.
  Future<void> downloadFile(ProviderNode node, File destination) =>
      throw const ProviderFailure(ProviderStatus.error);

  /// Language shares, as the service measures them.
  Future<Map<String, int>> languages() async => const <String, int>{};

  Future<List<RepoTicket>> issues({int limit = 40}) async =>
      const <RepoTicket>[];

  Future<List<RepoTicket>> pullRequests({int limit = 40}) async =>
      const <RepoTicket>[];

  Future<List<RepoRelease>> releases({int limit = 20}) async =>
      const <RepoRelease>[];

  Future<RepoSummary?> summary() async => null;
}

/// A drive: folders and files, arbitrarily nested.
abstract class FolderProvider extends CollectionProvider {
  /// The folders the account can see under [parentId], for the binding picker.
  Future<List<ProviderNode>> folders({String? parentId});

  /// The path from the collection's root down to [node], for breadcrumbs.
  Future<List<ProviderNode>> ancestorsOf(ProviderNode node) async =>
      const <ProviderNode>[];
}

/// A service a page can pull one object out of, for an embed.
///
/// Every folder and album provider is one of these; the interface exists so
/// the insert menu can offer "a file from a service" without knowing which
/// collection type that service usually stands behind.
abstract class ExternalFileProvider {
  ProviderService get service;

  Future<ProviderPage> browse({String? parentId, String? pageToken});

  Future<ProviderPage> find(String query, {String? pageToken});

  Future<String?> materializeFile(ProviderNode node);
}

/// A named point in a repository's history.
@immutable
class RepoRef {
  const RepoRef({
    required this.name,
    this.commitSha = '',
    this.isDefault = false,
    this.isProtected = false,
    this.webUrl = '',
  });

  final String name;
  final String commitSha;
  final bool isDefault;
  final bool isProtected;
  final String webUrl;
}

@immutable
class RepoCommit {
  const RepoCommit({
    required this.sha,
    required this.message,
    required this.authorName,
    this.authoredAt,
    this.authorAvatarUrl = '',
    this.webUrl = '',
    this.additions,
    this.deletions,
  });

  final String sha;
  final String message;
  final String authorName;
  final DateTime? authoredAt;
  final String authorAvatarUrl;
  final String webUrl;
  final int? additions;
  final int? deletions;

  String get shortSha => sha.length > 7 ? sha.substring(0, 7) : sha;

  /// The first line, which is what a list of commits shows.
  String get subject {
    final newline = message.indexOf('\n');
    return newline < 0 ? message : message.substring(0, newline);
  }
}

/// An issue, a pull request or a merge request — the same shape, because a
/// listing of them is the same listing.
@immutable
class RepoTicket {
  const RepoTicket({
    required this.number,
    required this.title,
    required this.state,
    this.authorName = '',
    this.createdAt,
    this.updatedAt,
    this.webUrl = '',
    this.commentCount = 0,
    this.labels = const <String>[],
    this.isDraft = false,
    this.isMerged = false,
    this.sourceBranch = '',
    this.targetBranch = '',
  });

  final int number;
  final String title;
  final String state;
  final String authorName;
  final DateTime? createdAt;
  final DateTime? updatedAt;
  final String webUrl;
  final int commentCount;
  final List<String> labels;
  final bool isDraft;
  final bool isMerged;
  final String sourceBranch;
  final String targetBranch;

  bool get isOpen =>
      state.toLowerCase() == 'open' || state.toLowerCase() == 'opened';
}

@immutable
class RepoRelease {
  const RepoRelease({
    required this.name,
    required this.tag,
    this.body = '',
    this.publishedAt,
    this.webUrl = '',
    this.isPrerelease = false,
  });

  final String name;
  final String tag;
  final String body;
  final DateTime? publishedAt;
  final String webUrl;
  final bool isPrerelease;
}

/// What a repository's own front page says about itself.
@immutable
class RepoSummary {
  const RepoSummary({
    required this.fullName,
    this.description = '',
    this.defaultBranch = '',
    this.webUrl = '',
    this.cloneUrl = '',
    this.stars = 0,
    this.forks = 0,
    this.openIssues = 0,
    this.watchers = 0,
    this.isPrivate = false,
    this.isFork = false,
    this.isArchived = false,
    this.canPush = false,
    this.license = '',
    this.topics = const <String>[],
    this.pushedAt,
    this.sizeKb = 0,
  });

  final String fullName;
  final String description;
  final String defaultBranch;
  final String webUrl;
  final String cloneUrl;
  final int stars;
  final int forks;
  final int openIssues;
  final int watchers;
  final bool isPrivate;
  final bool isFork;
  final bool isArchived;

  /// Whether the account may write. This is what hides commit, push and merge
  /// rather than letting the service refuse them later.
  final bool canPush;

  final String license;
  final List<String> topics;
  final DateTime? pushedAt;
  final int sizeKb;
}
