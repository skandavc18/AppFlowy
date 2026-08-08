import 'dart:io';

import 'package:appflowy/workspace/application/collections/repository/repo_entry.dart';
import 'package:appflowy/workspace/application/providers/collection_source.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_config.dart';
import 'package:appflowy/workspace/application/providers/connections/oauth_flow.dart';
import 'package:appflowy/workspace/application/providers/git/git_diff.dart';
import 'package:appflowy/workspace/application/providers/git/git_repository.dart';
import 'package:appflowy/workspace/application/providers/provider_node.dart';
import 'package:appflowy/workspace/application/providers/provider_service.dart';
import 'package:appflowy/workspace/application/providers/provider_state.dart';
import 'package:appflowy/workspace/application/providers/provider_view_factory.dart';
import 'package:appflowy/workspace/application/providers/services/repository_archive.dart';
import 'package:appflowy/workspace/application/workspace_item/workspace_item.dart';
import 'package:appflowy_backend/protobuf/flowy-folder/view.pb.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  group('where a collection reads from', () {
    test('a collection with no envelope is a local one', () {
      const metadata = WorkspaceItemMetadata.folder();
      expect(CollectionSource.fromExtra(metadata.mergeIntoExtra('')), isNull);
    });

    test('a binding survives a round trip through the view extra', () {
      final source = CollectionSource(
        service: ProviderService.github,
        connectionId: 'github|octocat',
        remoteId: 'octocat/hello-world',
        remoteName: 'hello-world',
        remoteUrl: 'https://github.com/octocat/hello-world',
        lastSyncedAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        options: const {'branch': 'main'},
      );

      final extra = source.mergeIntoExtra(
        const WorkspaceItemMetadata.folder().mergeIntoExtra(''),
      );
      final read = CollectionSource.fromExtra(extra)!;

      expect(read.service, ProviderService.github);
      expect(read.remoteId, 'octocat/hello-world');
      expect(read.option<String>('branch'), 'main');
      expect(read.lastSyncedAt, source.lastSyncedAt);
      // The folder envelope must survive alongside it, or the collection stops
      // behaving like a folder.
      expect(WorkspaceItemMetadata.fromExtra(extra)?.isFolder, isTrue);
    });

    test('going back to the workspace removes the envelope entirely', () {
      const source = CollectionSource(service: ProviderService.box);
      final bound = source.mergeIntoExtra('');
      final released = CollectionSource.local.mergeIntoExtra(bound);
      expect(CollectionSource.fromExtra(released), isNull);
    });

    test('two bindings of the same account differ by their cache key', () {
      const a = CollectionSource(
        service: ProviderService.immich,
        connectionId: 'immich|photos.example.com',
        remoteId: 'album-1',
      );
      final b = a.copyWith(remoteId: 'album-2');
      expect(a.cacheKey, isNot(b.cacheKey));
    });
  });

  group('what one object is', () {
    test('a MIME type is trusted before a file name', () {
      expect(
        providerNodeKindFor(mimeType: 'image/png', name: 'report.pdf'),
        ProviderNodeKind.image,
      );
    });

    test('a name is read when the service gives no type', () {
      expect(providerNodeKindFor(name: 'notes.md'), ProviderNodeKind.markup);
      expect(providerNodeKindFor(name: 'main.rs'), ProviderNodeKind.code);
      expect(providerNodeKindFor(name: 'clip.MOV'), ProviderNodeKind.video);
    });

    test('a Google document is reported as a folder only when it is one', () {
      expect(
        providerNodeKindFor(mimeType: 'application/vnd.google-apps.folder'),
        ProviderNodeKind.folder,
      );
      expect(
        providerNodeKindFor(mimeType: 'application/vnd.google-apps.document'),
        ProviderNodeKind.other,
      );
    });

    test('a node survives a round trip through the cache', () {
      final node = ProviderNode(
        id: 'abc',
        name: 'Sunset.jpg',
        kind: ProviderNodeKind.image,
        parentId: 'album',
        byteSize: 4096,
        createdAt: DateTime.fromMillisecondsSinceEpoch(1700000000000),
        thumbnailUrl: 'https://example.com/t',
        latitude: 51.5,
        longitude: -0.12,
        favourite: true,
        extra: const {'iso': 200},
      );
      final read = ProviderNode.fromJson(node.toJson())!;

      expect(read.id, node.id);
      expect(read.kind, ProviderNodeKind.image);
      expect(read.byteSize, 4096);
      expect(read.favourite, isTrue);
      expect(read.hasLocation, isTrue);
      expect(read.extra['iso'], 200);
    });

    test('an extension is read off the end of the name only', () {
      expect(
        const ProviderNode(
                id: '1', name: 'a.b.tar.gz', kind: ProviderNodeKind.archive,)
            .extension,
        'gz',
      );
      expect(
        const ProviderNode(
                id: '1', name: 'Makefile', kind: ProviderNodeKind.other,)
            .extension,
        '',
      );
    });
  });

  group('what went wrong, in words the interface can draw', () {
    test('an HTTP code becomes a state, never a message', () {
      expect(
        ProviderFailure.fromStatusCode(401).status,
        ProviderStatus.authExpired,
      );
      expect(
        ProviderFailure.fromStatusCode(403).status,
        ProviderStatus.permissionDenied,
      );
      expect(
        ProviderFailure.fromStatusCode(404).status,
        ProviderStatus.notFound,
      );
      expect(
        ProviderFailure.fromStatusCode(429).status,
        ProviderStatus.rateLimited,
      );
      expect(ProviderFailure.fromStatusCode(500).status, ProviderStatus.error);
    });

    test('a 403 that carries a retry is a rate limit, not a refusal', () {
      final failure =
          ProviderFailure.fromStatusCode(403, retryAfterHeader: '30');
      expect(failure.status, ProviderStatus.rateLimited);
      expect(failure.retryAfter, const Duration(seconds: 30));
    });

    test('only the recoverable states offer a way out', () {
      expect(ProviderStatus.offline.isRetryable, isTrue);
      expect(ProviderStatus.authExpired.isRetryable, isFalse);
      expect(ProviderStatus.authExpired.needsReconnect, isTrue);
      expect(ProviderStatus.permissionDenied.isRetryable, isFalse);
    });

    test('a read-only account is offered no writes at all', () {
      const full = ProviderCapabilities.full;
      final narrowed = full.readOnlyCopy();
      expect(full.isReadOnly, isFalse);
      expect(narrowed.isReadOnly, isTrue);
      expect(narrowed.canRead, isTrue);
      expect(narrowed.canFavourite, isFalse);
    });
  });

  group('a remote object dressed as a workspace item', () {
    final factory = ProviderViewFactory(
      collectionId: 'collection-1',
      source: const CollectionSource(
        service: ProviderService.googleDrive,
        connectionId: 'google|me',
      ),
    );

    test('an id is derived from the remote one, so it survives a refresh', () {
      expect(factory.viewIdFor('file-9'), 'collection-1::file-9');
      expect(factory.remoteIdOf('collection-1::file-9'), 'file-9');
      expect(factory.remoteIdOf('some-other-view'), isNull);
    });

    test('a file becomes a binary workspace file', () {
      const node = ProviderNode(
        id: 'file-9',
        name: 'Report.pdf',
        kind: ProviderNodeKind.pdf,
        parentId: 'folder-1',
        byteSize: 900,
      );
      final item = factory.viewFor(node, localPath: r'C:\cache\report.pdf');
      final metadata = WorkspaceItemMetadata.fromExtra(item.view.extra)!;

      expect(item.view.id, 'collection-1::file-9');
      expect(item.view.parentViewId, 'collection-1::folder-1');
      expect(metadata.isFile, isTrue);
      // Binary is what lets the gallery skip a backend read for this item.
      expect(metadata.contentKind, WorkspaceFileContentKind.binary);
      expect(metadata.storageUrl, r'C:\cache\report.pdf');
    });

    test('a folder becomes a folder', () {
      const node = ProviderNode(
        id: 'folder-1',
        name: 'Designs',
        kind: ProviderNodeKind.folder,
      );
      final item = factory.viewFor(node);
      expect(
          WorkspaceItemMetadata.fromExtra(item.view.extra)?.isFolder, isTrue,);
      expect(item.item.isFolder, isTrue);
    });

    test('an external view is told apart from a workspace one', () {
      expect(isProviderView('collection-1::file-9'), isTrue);
      expect(isProviderView('a-real-view-id'), isFalse);
    });
  });

  group('reading what git says has changed', () {
    test('the branch header carries the tracking counts', () {
      const output = '## main...origin/main [ahead 2, behind 1]\u0000'
          ' M lib/main.dart\u0000'
          'A  lib/new.dart\u0000'
          '?? notes.txt\u0000';
      final status = GitRepository.parseStatus(output);

      expect(status.branch, 'main');
      expect(status.upstream, 'origin/main');
      expect(status.ahead, 2);
      expect(status.behind, 1);
      expect(status.canPush, isTrue);
      expect(status.canPull, isTrue);
      expect(status.changes, hasLength(3));
    });

    test('staged and unstaged are told apart', () {
      const output = '## main\u0000'
          'A  added.dart\u0000'
          ' M edited.dart\u0000'
          'MM both.dart\u0000';
      final status = GitRepository.parseStatus(output);

      expect(status.staged.map((c) => c.path), ['added.dart', 'both.dart']);
      expect(status.unstaged.map((c) => c.path), ['edited.dart', 'both.dart']);
      expect(status.hasStaged, isTrue);
      expect(status.isClean, isFalse);
    });

    test('a file name with a space survives, because the records are NUL split',
        () {
      const output = '## main\u0000 M lib/my file.dart\u0000';
      final status = GitRepository.parseStatus(output);
      expect(status.changes.single.path, 'lib/my file.dart');
      expect(status.changes.single.name, 'my file.dart');
    });

    test('a rename carries the name it came from', () {
      const output = '## main\u0000R  new.dart\u0000old.dart\u0000';
      final status = GitRepository.parseStatus(output);
      expect(status.changes, hasLength(1));
      expect(status.changes.single.path, 'new.dart');
      expect(status.changes.single.originalPath, 'old.dart');
      expect(status.changes.single.isRenamed, isTrue);
    });

    test('a conflict is recognised however it is spelled', () {
      const output = '## main\u0000'
          'UU both-edited.dart\u0000'
          'AA both-added.dart\u0000';
      final status = GitRepository.parseStatus(output);
      expect(status.hasConflicts, isTrue);
      expect(status.conflicted, hasLength(2));
    });

    test('a detached head is not read as a branch called HEAD', () {
      final status = GitRepository.parseStatus('## HEAD (no branch)\u0000');
      expect(status.isDetached, isTrue);
      expect(status.branch, isEmpty);
    });

    test('an operation in progress is reported', () {
      final status =
          GitRepository.parseStatus('## main\u0000', operation: 'rebase');
      expect(status.isMidOperation, isTrue);
      expect(status.operation, 'rebase');
    });
  });

  group('reading a diff', () {
    const diff = '''
diff --git a/lib/main.dart b/lib/main.dart
index 83db48f..bf3a3d6 100644
--- a/lib/main.dart
+++ b/lib/main.dart
@@ -1,5 +1,6 @@ void main() {
 import 'dart:io';
 
-void main() {
+void main(List<String> args) {
+  print(args);
   run();
 }
''';

    test('a file, its hunks and its counts are read', () {
      final files = parseUnifiedDiff(diff);
      expect(files, hasLength(1));

      final file = files.single;
      expect(file.path, 'lib/main.dart');
      expect(file.name, 'main.dart');
      expect(file.directory, 'lib');
      expect(file.additions, 2);
      expect(file.deletions, 1);
      expect(file.hunks, hasLength(1));
      // The text after the second @@ is the enclosing declaration, which is
      // what makes a long diff readable.
      expect(file.hunks.single.context, 'void main() {');
    });

    test('line numbers advance on the side each line belongs to', () {
      final hunk = parseUnifiedDiff(diff).single.hunks.single;
      final additions = [
        for (final line in hunk.lines)
          if (line.kind == GitDiffLineKind.addition) line,
      ];
      final deletions = [
        for (final line in hunk.lines)
          if (line.kind == GitDiffLineKind.deletion) line,
      ];

      expect(additions.first.newLineNumber, isNotNull);
      expect(additions.first.oldLineNumber, isNull);
      expect(deletions.first.oldLineNumber, isNotNull);
      expect(deletions.first.newLineNumber, isNull);
    });

    test('a new file and a deleted file are recognised', () {
      const added = '''
diff --git a/new.txt b/new.txt
new file mode 100644
--- /dev/null
+++ b/new.txt
@@ -0,0 +1 @@
+hello
''';
      final file = parseUnifiedDiff(added).single;
      expect(file.isNew, isTrue);
      expect(file.additions, 1);
    });

    test('a binary file is reported rather than rendered', () {
      const binary = '''
diff --git a/logo.png b/logo.png
index 1234567..89abcde 100644
Binary files a/logo.png and b/logo.png differ
''';
      final file = parseUnifiedDiff(binary).single;
      expect(file.isBinary, isTrue);
      expect(file.hunks, isEmpty);
    });

    test('a diff inside a diff is content, not syntax', () {
      // The whole reason the parser is a state machine: these lines look
      // exactly like diff headers but are inside a hunk.
      const nested = '''
diff --git a/fixture.txt b/fixture.txt
--- a/fixture.txt
+++ b/fixture.txt
@@ -1,2 +1,3 @@
 diff --git a/inner b/inner
-@@ -1 +1 @@
+@@ -2 +2 @@
+ +not an addition
''';
      final files = parseUnifiedDiff(nested);
      expect(files, hasLength(1));
      expect(files.single.path, 'fixture.txt');
      expect(files.single.hunks, hasLength(1));
    });
  });

  group('resolving a conflict', () {
    const conflicted = '''
before
<<<<<<< HEAD
mine one
mine two
=======
theirs one
>>>>>>> feature
after
''';

    test('both sides are read out of the markers', () {
      final file = parseConflicts(conflicted);
      expect(file.hasConflicts, isTrue);

      final block = file.blocks.single;
      expect(block.ours, ['mine one', 'mine two']);
      expect(block.theirs, ['theirs one']);
      expect(block.oursLabel, 'HEAD');
      expect(block.theirsLabel, 'feature');
    });

    test('a diff3 conflict keeps its common ancestor', () {
      const diff3 = '''
<<<<<<< HEAD
mine
||||||| base
original
=======
theirs
>>>>>>> other
''';
      final block = parseConflicts(diff3).blocks.single;
      expect(block.base, ['original']);
      expect(block.ours, ['mine']);
      expect(block.theirs, ['theirs']);
    });

    test('taking one side rewrites the file without any markers', () {
      final file = parseConflicts(conflicted);
      final ours = resolveConflictsWith(file, ours: true);
      final theirs = resolveConflictsWith(file, ours: false);

      expect(ours, contains('mine one'));
      expect(ours, isNot(contains('theirs one')));
      expect(ours, isNot(contains('<<<<<<<')));
      expect(theirs, contains('theirs one'));
      expect(theirs, isNot(contains('mine one')));
      // Everything outside the block is left exactly as it was.
      expect(ours, contains('before'));
      expect(ours, contains('after'));
    });

    test('a file with no conflict is returned untouched', () {
      final file = parseConflicts('one\ntwo\n');
      expect(file.hasConflicts, isFalse);
      expect(resolveConflictsWith(file, ours: true), 'one\ntwo\n');
    });
  });

  group('why a sign in was refused', () {
    test('the standard error fields are read', () {
      final error = readOAuthError(
        '{"error":"invalid_client",'
        '"error_description":"The OAuth client was not found."}',
      )!;
      expect(error.code, 'invalid_client');
      expect(error.description, 'The OAuth client was not found.');
    });

    test('an error with no description still names the code', () {
      expect(
          readOAuthError('{"error":"invalid_grant"}')?.code, 'invalid_grant',);
    });

    test('a body that is not an error is not read as one', () {
      expect(readOAuthError('{"access_token":"abc"}'), isNull);
      expect(readOAuthError(''), isNull);
      expect(readOAuthError('<html>bad gateway</html>'), isNull);
    });

    test('a nested Google-style error object is still read', () {
      final error = readOAuthError(
        '{"error":{"status":"UNAUTHENTICATED","message":"Invalid credentials"}}',
      )!;
      expect(error.code, 'Invalid credentials');
    });

    test('a service cannot push an unbounded string into the log', () {
      final long = 'x' * 500;
      final error = readOAuthError('{"error":"$long"}')!;
      expect(error.code.length, lessThanOrEqualTo(201));
      expect(error.code, endsWith('…'));
    });

    test('whitespace and newlines are flattened to one line', () {
      final error = readOAuthError(
        '{"error":"invalid_request","error_description":"a\\n\\nb   c"}',
      )!;
      expect(error.description, 'a b c');
    });
  });

  group('which services need a client secret', () {
    // Google's console issues a secret for a Desktop app client and its token
    // endpoint answers 400 invalid_client without it. Getting this wrong is
    // what made a successful browser sign in end in HTTP 400.
    test('Google asks for one', () {
      expect(OAuthServices.googleDrive.wantsClientSecret, isTrue);
      expect(OAuthServices.googlePhotos.wantsClientSecret, isTrue);
    });

    test('Box asks for one', () {
      expect(OAuthServices.box.wantsClientSecret, isTrue);
    });

    test('Microsoft is a public client and must not be sent one', () {
      expect(OAuthServices.oneDrive.wantsClientSecret, isFalse);
    });

    test('every browser service still uses PKCE', () {
      for (final service in ProviderService.values) {
        final endpoints = OAuthServices.forService(service);
        if (endpoints != null) {
          expect(endpoints.usesPkce, isTrue, reason: service.name);
        }
      }
    });

    // Google removed these on 31 March 2025. Asking for one now gets the sign
    // in accepted and then 403 on the first read, which is exactly the failure
    // that is hardest to trace back to a scope.
    test('no service asks for a scope Google has withdrawn', () {
      const withdrawn = {
        'https://www.googleapis.com/auth/photoslibrary',
        'https://www.googleapis.com/auth/photoslibrary.readonly',
        'https://www.googleapis.com/auth/photoslibrary.sharing',
      };
      for (final service in ProviderService.values) {
        final endpoints = OAuthServices.forService(service);
        for (final scope in endpoints?.scopes ?? const <String>[]) {
          expect(withdrawn, isNot(contains(scope)), reason: service.name);
        }
      }
    });

    test('Google Photos is bound by picking, not by listing albums', () {
      // There is no albums.list any more, so the source picker must hand over
      // to Google's own interface instead of showing a list.
      expect(ProviderServices.googlePhotos.picksExternally, isTrue);
      expect(ProviderServices.googleDrive.picksExternally, isFalse);
    });
  });

  group('the catalogue of services', () {
    test('every collection kind can at least be local', () {
      for (final kind in ProviderServices.local.kinds) {
        expect(ProviderServices.forKind(kind).first.service.isLocal, isTrue);
      }
    });

    test('only the kinds with a real backing offer a remote option', () {
      expect(
        ProviderServices.forKind(ProviderServices.immich.kinds.first)
            .map((info) => info.service),
        contains(ProviderService.immich),
      );
    });

    test('an unknown service name falls back to the workspace', () {
      expect(ProviderService.fromValue('dropbox'), ProviderService.local);
      expect(ProviderService.fromValue(null), ProviderService.local);
    });
  });

  group('unpacking a hosted repository', () {
    final root = Directory(p.join(Directory.systemTemp.path, 'af-repo-test'));

    test('the wrapper folder both hosts add is dropped', () {
      expect(
        RepositoryArchive.stripWrapper('octocat-hello-abc123/lib/main.dart'),
        'lib/main.dart',
      );
      expect(
        RepositoryArchive.stripWrapper('octocat-hello-abc123/README.md'),
        'README.md',
      );
    });

    test('an entry that is only the wrapper itself is not a file', () {
      expect(RepositoryArchive.stripWrapper('octocat-hello-abc123'), isNull);
      expect(RepositoryArchive.stripWrapper('octocat-hello-abc123/'), isNull);
    });

    test('an ordinary path lands inside the tree', () {
      final file = RepositoryArchive.safeJoin(root, 'lib/main.dart');
      expect(file, isNotNull);
      expect(p.isWithin(root.absolute.path, file!.path), isTrue);
    });

    test('a name that climbs out of the tree is refused', () {
      expect(RepositoryArchive.safeJoin(root, '../evil.dart'), isNull);
      expect(
        RepositoryArchive.safeJoin(root, 'lib/../../../evil.dart'),
        isNull,
      );
      expect(RepositoryArchive.safeJoin(root, '..'), isNull);
    });

    test('a name carrying a null byte is refused', () {
      expect(RepositoryArchive.safeJoin(root, 'lib/main\u0000.dart'), isNull);
      expect(RepositoryArchive.safeJoin(root, ''), isNull);
    });

    test('progress reports a fraction only when a total is known', () {
      const unknown = RepositoryArchiveProgress(
        stage: RepositoryArchiveStage.downloading,
        received: 512,
      );
      expect(unknown.fraction, isNull);

      const known = RepositoryArchiveProgress(
        stage: RepositoryArchiveStage.downloading,
        received: 50,
        total: 200,
      );
      expect(known.fraction, 0.25);
    });

    test('a server that overstates what it sent cannot exceed one', () {
      const overrun = RepositoryArchiveProgress(
        stage: RepositoryArchiveStage.downloading,
        received: 300,
        total: 200,
      );
      expect(overrun.fraction, 1.0);
    });
  });

  group('how a hosted repository reaches the views', () {
    test('an unpacked file is treated as a local one', () {
      final view = ViewPB(
        id: 'root::lib/main.dart',
        parentViewId: 'root',
        name: 'main.dart',
        layout: ViewLayoutPB.Document,
        extra: WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl: p.join('C:', 'cache', 'tree', 'lib', 'main.dart'),
          size: 120,
        ).mergeIntoExtra(''),
      );

      final entry = repoEntryFor(view, parentPath: 'lib', depth: 1);
      expect(entry.isLocalFile, isTrue);
      expect(entry.path, 'lib/main.dart');
    });

    test('a file still living on the host is not a local one', () {
      final view = ViewPB(
        id: 'root::lib/main.dart',
        parentViewId: 'root',
        name: 'main.dart',
        layout: ViewLayoutPB.Document,
        extra: WorkspaceItemMetadata.file(
          contentKind: WorkspaceFileContentKind.binary,
          storageUrl:
              'https://raw.githubusercontent.com/o/r/main/lib/main.dart',
        ).mergeIntoExtra(''),
      );

      expect(
          repoEntryFor(view, parentPath: 'lib', depth: 1).isLocalFile, false,);
    });
  });
}
